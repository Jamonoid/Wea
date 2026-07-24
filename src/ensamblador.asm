; ============================================================
; ensamblador.asm - dos pasadas sobre el fuente
;   pasada 1: layout (simbolos, tamanos, literales, datos)
;   pasada 2: emision de bytecode
; El segmento de datos se escribe directo en vm_mem.
; ============================================================

include winapi.inc
include isa.inc

PUBLIC ensamblar            ; rcx=fuente ptr, rdx=largo -> (llena los PUBLIC de abajo)
PUBLIC asm_codigo           ; buffer de bytecode
PUBLIC asm_codigo_len       ; dd
PUBLIC asm_entry            ; dd pc inicial
PUBLIC asm_linea_por_byte   ; dd por byte de codigo (solo validos los inicios)
PUBLIC asm_inicio_instr     ; byte por byte de codigo: 1 = aqui parte instruccion
PUBLIC asm_datos_fin        ; dd primera celda libre despues de los datos (guardia pila)

EXTERN normalizar: PROC
EXTERN buscar_frase: PROC
EXTERN buscar_registro: PROC
EXTERN saltar_espacios: PROC
EXTERN siguiente_token: PROC
EXTERN mem_igual: PROC
EXTERN atoi_wea: PROC
EXTERN error_asm: PROC
EXTERN vm_mem: QWORD

EXTERN e_no_cacho:BYTE, e_registro_malo:BYTE, e_aridad:BYTE
EXTERN e_etiqueta_fantasma:BYTE, e_etiqueta_dupe:BYTE, e_sin_pega:BYTE
EXTERN e_operando_malo:BYTE, e_slot_escritura:BYTE, e_slot_salto:BYTE
EXTERN e_seccion:BYTE, e_string_malo:BYTE, e_directiva_mala:BYTE
EXTERN e_muchos_simbolos:BYTE, e_datos_llenos:BYTE, e_mucho_codigo:BYTE
EXTERN e_sapeo:BYTE, e_entry:BYTE, e_fuente_grande:BYTE

MAX_CODIGO      equ 10000h          ; 64 KiB de bytecode
MAX_LINEA       equ 1000h           ; 4 KiB por linea
MAX_ARENA       equ 10000h          ; nombres y literales
MAX_LITERALES   equ 256

; seccion actual
SECC_CODIGO     equ 0
SECC_DATOS      equ 1

; origen del operando (para validar slots)
ORIG_NUM        equ 0
ORIG_REG        equ 1
ORIG_SIM_DATO   equ 2
ORIG_SIM_CODIGO equ 3
ORIG_SIM_CONST  equ 4
ORIG_MEM        equ 5
ORIG_LITERAL    equ 6

.data
fuente_ptr      dq 0
fuente_len      dq 0
pasada          dd 0                ; 1 o 2
seccion         dd SECC_CODIGO      ; por defecto codigo: un hola.wea sin directivas corre
linea_num       dd 0
data_cursor     dd 0
pc              dd 0
num_instr       dd 0
num_simbolos    dd 0
num_literales   dd 0
arena_cursor    dq 0
entry_nombre    dq 0                ; ptr arena (0 = no hubo .empezamos en)
entry_largo     dd 0
asm_entry       dd 0
asm_codigo_len  dd 0
asm_datos_fin   dd 0

; resultado del parser de operandos
op_modo         dd 0
op_reg          dd 0
op_valor        dd 0
op_origen       dd 0

; frases de directivas / prefijos (ya normalizadas)
d_la_wea        db ".la wea", 0
d_la_pega       db ".la pega", 0
d_empezamos     db ".empezamos en ", 0
d_dale_con      db "dale con ", 0
d_chamullo      db "chamullo", 0
d_numerito      db "numerito", 0
d_puros_hoyos   db "puros hoyos", 0
nombre_inicio   db "inicio", 0

.data?
buf_linea       db MAX_LINEA dup (?)    ; linea normalizada
buf_extra       db 128 dup (?)          ; texto para mensajes de error
simbolos        db (MAX_SIMBOLOS * SIM_TAM) dup (?)
arena           db MAX_ARENA dup (?)
literales       db (MAX_LITERALES * 16) dup (?)  ; ptr(8) largo(4) addr(4)
asm_codigo      db MAX_CODIGO dup (?)
asm_linea_por_byte dd MAX_CODIGO dup (?)
asm_inicio_instr   db MAX_CODIGO dup (?)

.code

; ============================================================
; ensamblar: rcx=ptr, rdx=largo
; ============================================================
ensamblar PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 20h
    mov     fuente_ptr, rcx
    mov     fuente_len, rdx
    lea     rax, arena
    mov     arena_cursor, rax

    mov     pasada, 1
    call    correr_pasada
    call    asignar_literales
    mov     eax, data_cursor
    mov     asm_datos_fin, eax

    mov     pasada, 2
    mov     dword ptr seccion, SECC_CODIGO
    mov     dword ptr data_cursor, 0     ; los datos ya quedaron escritos en p1
    mov     dword ptr pc, 0
    call    correr_pasada

    mov     eax, pc
    mov     asm_codigo_len, eax

    ; sin codigo = puro weveo
    cmp     dword ptr num_instr, 0
    jne     ens_hay_codigo
    lea     rcx, e_sin_pega
    xor     edx, edx
    xor     r8, r8
    call    error_asm
ens_hay_codigo:

    ; resolver punto de entrada
    call    resolver_entry

    add     rsp, 20h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
ensamblar ENDP

; ============================================================
; correr_pasada: recorre el fuente linea por linea
; ============================================================
correr_pasada PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 20h
    mov     rsi, fuente_ptr         ; cursor
    mov     rdi, fuente_ptr
    add     rdi, fuente_len         ; fin
    mov     dword ptr linea_num, 0
cp_linea:
    cmp     rsi, rdi
    jae     cp_fin
    inc     dword ptr linea_num
    ; buscar fin de linea
    mov     rbx, rsi                ; inicio de linea
cp_busca_nl:
    cmp     rsi, rdi
    jae     cp_procesa
    cmp     byte ptr [rsi], 0Ah
    je      cp_procesa
    inc     rsi
    jmp     cp_busca_nl
cp_procesa:
    mov     r12, rsi                ; fin de linea (apunta al \n o al fin)
    sub     r12, rbx                ; largo crudo
    cmp     r12, MAX_LINEA-1
    jb      cp_largo_ok
    lea     rcx, e_fuente_grande
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
cp_largo_ok:
    ; normalizar la linea
    mov     rcx, rbx
    mov     rdx, r12
    lea     r8, buf_linea
    call    normalizar
    ; procesarla
    lea     rcx, buf_linea
    call    procesar_linea
    ; avanzar despues del \n
    cmp     rsi, rdi
    jae     cp_fin
    inc     rsi
    jmp     cp_linea
cp_fin:
    add     rsp, 20h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
correr_pasada ENDP

; ============================================================
; procesar_linea: rcx=linea normalizada asciiz
; ============================================================
procesar_linea PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 20h
    mov     rbx, rcx

    cmp     byte ptr [rbx], 0
    je      pl_fin                  ; linea vacia

    ; ---- etiqueta al inicio?  ident: ----
    ; buscar ':' antes del primer espacio
    xor     r12, r12                ; indice
pl_busca_dp:
    movzx   eax, byte ptr [rbx+r12]
    test    al, al
    jz      pl_sin_etiqueta
    cmp     al, ' '
    je      pl_sin_etiqueta
    cmp     al, ':'
    je      pl_hay_etiqueta
    cmp     al, '"'
    je      pl_sin_etiqueta
    cmp     al, '['
    je      pl_sin_etiqueta
    inc     r12
    jmp     pl_busca_dp
pl_hay_etiqueta:
    test    r12, r12
    jz      pl_sin_etiqueta         ; ":algo" no es etiqueta
    ; en pasada 1 se define; en pasada 2 se ignora
    cmp     dword ptr pasada, 1
    jne     pl_et_salta
    mov     rcx, rbx
    mov     rdx, r12
    call    definir_etiqueta
pl_et_salta:
    lea     rbx, [rbx+r12+1]        ; despues del ':'
    mov     rcx, rbx
    call    saltar_espacios
    mov     rbx, rax
    cmp     byte ptr [rbx], 0
    je      pl_fin                  ; etiqueta sola en la linea

pl_sin_etiqueta:
    ; ---- directivas con punto ----
    cmp     byte ptr [rbx], '.'
    jne     pl_no_punto
    ; .la wea
    lea     rcx, d_la_wea
    mov     rdx, rbx
    call    prefijo_igual
    test    eax, eax
    jz      pl_p2
    mov     dword ptr seccion, SECC_DATOS
    jmp     pl_fin
pl_p2:
    lea     rcx, d_la_pega
    mov     rdx, rbx
    call    prefijo_igual
    test    eax, eax
    jz      pl_p3
    mov     dword ptr seccion, SECC_CODIGO
    jmp     pl_fin
pl_p3:
    lea     rcx, d_empezamos
    mov     rdx, rbx
    call    prefijo_parcial         ; ".empezamos en " es prefijo?
    test    eax, eax
    jz      pl_dir_mala
    cmp     dword ptr pasada, 1
    jne     pl_fin
    ; guardar nombre del entry
    lea     rcx, [rbx+14]           ; largo de ".empezamos en "
    call    saltar_espacios
    mov     rcx, rax
    call    siguiente_token
    test    rax, rax
    jz      pl_dir_mala
    mov     rcx, rax
    ; rdx ya tiene largo
    call    arena_copiar
    mov     entry_nombre, rax
    mov     entry_largo, edx
    jmp     pl_fin
pl_dir_mala:
    lea     rcx, e_directiva_mala
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm

pl_no_punto:
    ; ---- dale con NOMBRE = valor (constante) ----
    lea     rcx, d_dale_con
    mov     rdx, rbx
    call    prefijo_parcial
    test    eax, eax
    jz      pl_no_dale
    cmp     dword ptr pasada, 1
    jne     pl_fin                  ; en p2 ya esta definida
    lea     rcx, [rbx+9]            ; largo "dale con "
    call    definir_constante
    jmp     pl_fin
pl_no_dale:

    ; ---- seccion de datos ----
    cmp     dword ptr seccion, SECC_DATOS
    jne     pl_codigo
    cmp     dword ptr pasada, 2
    je      pl_fin                  ; datos ya emitidos en p1
    mov     rcx, rbx
    call    procesar_dato
    jmp     pl_fin

pl_codigo:
    ; ---- instruccion ----
    mov     rcx, rbx
    call    procesar_instruccion

pl_fin:
    add     rsp, 20h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
procesar_linea ENDP

; ============================================================
; prefijo_igual: rcx=frase asciiz, rdx=linea -> eax=1 si la linea
; ES exactamente la frase (o frase + fin)
; prefijo_parcial: eax=1 si la linea EMPIEZA con la frase
; ============================================================
prefijo_igual PROC
    push    rsi
    push    rdi
    push    rbx
    sub     rsp, 20h
    mov     rsi, rcx
    mov     rdi, rdx
    xor     rbx, rbx
pi_loop:
    mov     al, [rsi+rbx]
    test    al, al
    jz      pi_fin_frase
    cmp     al, [rdi+rbx]
    jne     pi_no
    inc     rbx
    jmp     pi_loop
pi_fin_frase:
    cmp     byte ptr [rdi+rbx], 0
    jne     pi_no
    mov     eax, 1
    jmp     pi_ret
pi_no:
    xor     eax, eax
pi_ret:
    add     rsp, 20h
    pop     rbx
    pop     rdi
    pop     rsi
    ret
prefijo_igual ENDP

prefijo_parcial PROC
    push    rsi
    push    rdi
    push    rbx
    sub     rsp, 20h
    mov     rsi, rcx
    mov     rdi, rdx
    xor     rbx, rbx
pp_loop:
    mov     al, [rsi+rbx]
    test    al, al
    jz      pp_si
    cmp     al, [rdi+rbx]
    jne     pp_no
    inc     rbx
    jmp     pp_loop
pp_si:
    mov     eax, 1
    jmp     pp_ret
pp_no:
    xor     eax, eax
pp_ret:
    add     rsp, 20h
    pop     rbx
    pop     rdi
    pop     rsi
    ret
prefijo_parcial ENDP

; ============================================================
; arena_copiar: rcx=ptr, rdx=largo -> rax=ptr en arena (asciiz)
;               rdx se preserva
; ============================================================
arena_copiar PROC
    push    rsi
    push    rdi
    push    rbx
    sub     rsp, 20h
    mov     rsi, rcx
    mov     rbx, rdx
    mov     rdi, arena_cursor
    ; alcanza?
    lea     rax, arena
    add     rax, MAX_ARENA - 2
    lea     rcx, [rdi+rbx]
    cmp     rcx, rax
    jb      ac_cabe
    lea     rcx, e_muchos_simbolos
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
ac_cabe:
    xor     rax, rax
ac_loop:
    cmp     rax, rbx
    jae     ac_fin
    mov     cl, [rsi+rax]
    mov     [rdi+rax], cl
    inc     rax
    jmp     ac_loop
ac_fin:
    mov     byte ptr [rdi+rbx], 0
    mov     rax, rdi
    lea     rcx, [rdi+rbx+1]
    mov     arena_cursor, rcx
    mov     rdx, rbx
    add     rsp, 20h
    pop     rbx
    pop     rdi
    pop     rsi
    ret
arena_copiar ENDP

; ============================================================
; buscar_simbolo: rcx=ptr, rdx=largo -> rax=ptr entrada o 0
; ============================================================
buscar_simbolo PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 20h
    mov     rsi, rcx
    mov     rdi, rdx
    lea     rbx, simbolos
    mov     r12d, num_simbolos
bs_loop:
    test    r12d, r12d
    jz      bs_no
    cmp     dword ptr [rbx+SIM_LARGO], edi
    jne     bs_next
    mov     rcx, rsi
    mov     rdx, [rbx+SIM_NOMBRE]
    mov     r8, rdi
    call    mem_igual
    test    eax, eax
    jz      bs_next
    mov     rax, rbx
    jmp     bs_ret
bs_next:
    add     rbx, SIM_TAM
    dec     r12d
    jmp     bs_loop
bs_no:
    xor     rax, rax
bs_ret:
    add     rsp, 20h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
buscar_simbolo ENDP

; ============================================================
; agregar_simbolo: rcx=ptr, rdx=largo, r8d=kind, r9d=valor
; revienta si ya existe o si esta llena la tabla
; ============================================================
agregar_simbolo PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 20h
    mov     rsi, rcx
    mov     rdi, rdx
    mov     r12d, r8d
    mov     r13d, r9d
    ; nombre = registro? no po
    mov     rcx, rsi
    mov     rdx, rdi
    call    buscar_registro
    cmp     eax, -1
    je      as_no_reg
    call    copiar_extra_sd         ; rsi/rdi -> buf_extra
    lea     rcx, e_registro_malo
    mov     edx, linea_num
    lea     r8, buf_extra
    call    error_asm
as_no_reg:
    ; duplicada?
    mov     rcx, rsi
    mov     rdx, rdi
    call    buscar_simbolo
    test    rax, rax
    jz      as_nueva
    call    copiar_extra_sd
    lea     rcx, e_etiqueta_dupe
    mov     edx, linea_num
    lea     r8, buf_extra
    call    error_asm
as_nueva:
    cmp     dword ptr num_simbolos, MAX_SIMBOLOS
    jb      as_cabe
    lea     rcx, e_muchos_simbolos
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
as_cabe:
    ; copiar nombre al arena
    mov     rcx, rsi
    mov     rdx, rdi
    call    arena_copiar            ; rax=ptr, rdx=largo
    ; entrada nueva
    mov     ecx, num_simbolos
    imul    rcx, rcx, SIM_TAM
    lea     rbx, simbolos
    add     rbx, rcx
    mov     [rbx+SIM_NOMBRE], rax
    mov     [rbx+SIM_LARGO], edi
    mov     [rbx+SIM_KIND], r12d
    mov     [rbx+SIM_VALOR], r13d
    mov     eax, linea_num
    mov     [rbx+SIM_LINEA], eax
    inc     dword ptr num_simbolos
    add     rsp, 20h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
agregar_simbolo ENDP

; copia rsi/largo rdi a buf_extra (para errores). max 127.
copiar_extra_sd PROC PRIVATE
    push    rax
    push    rcx
    mov     rcx, rdi
    cmp     rcx, 127
    jbe     ce_ok
    mov     rcx, 127
ce_ok:
    lea     r11, buf_extra
    xor     rax, rax
ce_loop:
    cmp     rax, rcx
    jae     ce_fin
    mov     r10b, [rsi+rax]
    mov     [r11+rax], r10b
    inc     rax
    jmp     ce_loop
ce_fin:
    mov     byte ptr [r11+rax], 0
    pop     rcx
    pop     rax
    ret
copiar_extra_sd ENDP

; ============================================================
; definir_etiqueta: rcx=ptr nombre, rdx=largo (pasada 1)
; kind y valor segun la seccion actual
; ============================================================
definir_etiqueta PROC
    sub     rsp, 28h
    cmp     dword ptr seccion, SECC_DATOS
    je      de_dato
    mov     r8d, SIMK_CODIGO
    mov     r9d, pc
    jmp     de_agregar
de_dato:
    mov     r8d, SIMK_DATO
    mov     r9d, data_cursor
de_agregar:
    call    agregar_simbolo
    add     rsp, 28h
    ret
definir_etiqueta ENDP

; ============================================================
; definir_constante: rcx=ptr despues de "dale con "
; formato: NOMBRE = valor
; ============================================================
definir_constante PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 20h
    call    siguiente_token         ; nombre... pero corta en '='? no: '=' no es
                                    ; separador del token, asi que el nombre no
                                    ; puede ir pegado al '='; exigimos espacio
    test    rax, rax
    jz      dc_malo
    mov     rsi, rax                ; nombre
    mov     rdi, rdx                ; largo
    ; puede venir "NOMBRE=..." pegado: cortar en '='
    xor     rcx, rcx
dc_corta:
    cmp     rcx, rdi
    jae     dc_cortado
    cmp     byte ptr [rsi+rcx], '='
    je      dc_corta_aqui
    inc     rcx
    jmp     dc_corta
dc_corta_aqui:
    mov     rdi, rcx
    test    rdi, rdi
    jz      dc_malo
dc_cortado:
    ; buscar el '=' desde nombre+largo
    lea     rbx, [rsi+rdi]
dc_busca_igual:
    movzx   eax, byte ptr [rbx]
    test    al, al
    jz      dc_malo
    cmp     al, '='
    je      dc_igual
    cmp     al, ' '
    jne     dc_malo
    inc     rbx
    jmp     dc_busca_igual
dc_igual:
    inc     rbx
    mov     rcx, rbx
    call    siguiente_token
    test    rax, rax
    jz      dc_malo
    mov     rcx, rax
    ; rdx = largo
    call    atoi_wea
    test    r8, r8
    jz      dc_malo
    mov     r13d, eax               ; valor
    mov     rcx, rsi
    mov     rdx, rdi
    mov     r8d, SIMK_CONST
    mov     r9d, r13d
    call    agregar_simbolo
    jmp     dc_fin
dc_malo:
    lea     rcx, e_directiva_mala
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
dc_fin:
    add     rsp, 20h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
definir_constante ENDP

; ============================================================
; procesar_dato: rcx=resto de linea (seccion datos, pasada 1)
;   chamullo "texto" | numerito a, b, c | puros hoyos N
; ============================================================
procesar_dato PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 20h
    mov     rbx, rcx

    lea     rcx, d_chamullo
    mov     rdx, rbx
    call    prefijo_parcial
    test    eax, eax
    jnz     pd_chamullo
    lea     rcx, d_numerito
    mov     rdx, rbx
    call    prefijo_parcial
    test    eax, eax
    jnz     pd_numerito
    lea     rcx, d_puros_hoyos
    mov     rdx, rbx
    call    prefijo_parcial
    test    eax, eax
    jnz     pd_hoyos
    lea     rcx, e_directiva_mala
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm

; ---- chamullo "..." ----
pd_chamullo:
    lea     rcx, [rbx+8]            ; largo "chamullo"
    call    saltar_espacios
    mov     rsi, rax
    cmp     byte ptr [rsi], '"'
    je      pd_ch_comilla
    lea     rcx, e_string_malo
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
pd_ch_comilla:
    inc     rsi                     ; dentro del string
    ; buscar comilla de cierre
    xor     r12, r12
pd_ch_busca:
    movzx   eax, byte ptr [rsi+r12]
    test    al, al
    jz      pd_ch_sin_cierre
    cmp     al, '"'
    je      pd_ch_ok
    cmp     al, '\'                 ; escape: saltar el siguiente
    jne     pd_ch_sigue
    cmp     byte ptr [rsi+r12+1], 0
    je      pd_ch_sin_cierre
    inc     r12
pd_ch_sigue:
    inc     r12
    jmp     pd_ch_busca
pd_ch_sin_cierre:
    lea     rcx, e_string_malo
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
pd_ch_ok:
    ; escribir en vm_mem desde data_cursor
    mov     rcx, rsi
    mov     rdx, r12
    mov     r8d, data_cursor
    call    escribir_string_mem     ; -> eax celdas escritas
    add     data_cursor, eax
    jmp     pd_fin

; ---- numerito a, b, c ----
pd_numerito:
    lea     rcx, [rbx+8]            ; largo "numerito"
pd_num_loop:
    call    saltar_espacios
    mov     rcx, rax
    cmp     byte ptr [rcx], 0
    je      pd_fin
    cmp     byte ptr [rcx], ','
    jne     pd_num_tok
    inc     rcx
    jmp     pd_num_loop
pd_num_tok:
    call    siguiente_token
    test    rax, rax
    jz      pd_fin
    mov     rsi, rax
    mov     rdi, rdx
    lea     r12, [rax+rdx]          ; continuar desde aqui
    mov     rcx, rsi
    mov     rdx, rdi
    call    atoi_wea
    test    r8, r8
    jnz     pd_num_ok
    call    copiar_extra_sd         ; rsi/rdi ya tienen el token
    lea     rcx, e_operando_malo
    mov     edx, linea_num
    lea     r8, buf_extra
    call    error_asm
pd_num_ok:
    mov     ecx, data_cursor
    cmp     ecx, MEM_PALABRAS
    jb      pd_num_cabe
    lea     rcx, e_datos_llenos
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
pd_num_cabe:
    mov     rdx, vm_mem
    mov     [rdx+rcx*4], eax
    inc     dword ptr data_cursor
    mov     rcx, r12
    jmp     pd_num_loop

; ---- puros hoyos N ----
pd_hoyos:
    lea     rcx, [rbx+11]           ; largo "puros hoyos"
    call    saltar_espacios
    mov     rcx, rax
    call    siguiente_token
    test    rax, rax
    jz      pd_hoyos_malo
    mov     rcx, rax
    call    atoi_wea
    test    r8, r8
    jz      pd_hoyos_malo
    test    eax, eax
    js      pd_hoyos_malo
    add     data_cursor, eax
    cmp     dword ptr data_cursor, MEM_PALABRAS
    jbe     pd_fin
    lea     rcx, e_datos_llenos
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
pd_hoyos_malo:
    lea     rcx, e_directiva_mala
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm

pd_fin:
    add     rsp, 20h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
procesar_dato ENDP

; ============================================================
; escribir_string_mem: rcx=ptr interior, rdx=largo, r8d=celda
; decodifica escapes + UTF-8 -> celdas int32, agrega terminador 0
; -> eax = celdas escritas (incluye el 0)
; SOLO revisa limites; en pasada 1 escribe de verdad.
; ============================================================
escribir_string_mem PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 20h
    mov     rsi, rcx                ; ptr
    mov     rdi, rdx                ; restante
    mov     r12d, r8d               ; celda actual
    mov     r13d, r8d               ; celda inicial
esm_loop:
    test    rdi, rdi
    jz      esm_terminar
    movzx   eax, byte ptr [rsi]
    cmp     al, '\'
    je      esm_escape
    ; UTF-8
    cmp     al, 80h
    jb      esm_ascii
    ; multibyte
    mov     ecx, eax
    cmp     al, 0E0h
    jae     esm_3o4
    ; 2 bytes: C2-DF
    and     ecx, 1Fh
    shl     ecx, 6
    movzx   eax, byte ptr [rsi+1]
    and     eax, 3Fh
    or      eax, ecx
    add     rsi, 2
    sub     rdi, 2
    jmp     esm_pone
esm_3o4:
    cmp     al, 0F0h
    jae     esm_4
    ; 3 bytes
    and     ecx, 0Fh
    shl     ecx, 6
    movzx   eax, byte ptr [rsi+1]
    and     eax, 3Fh
    or      ecx, eax
    shl     ecx, 6
    movzx   eax, byte ptr [rsi+2]
    and     eax, 3Fh
    or      eax, ecx
    add     rsi, 3
    sub     rdi, 3
    jmp     esm_pone
esm_4:
    and     ecx, 7
    shl     ecx, 6
    movzx   eax, byte ptr [rsi+1]
    and     eax, 3Fh
    or      ecx, eax
    shl     ecx, 6
    movzx   eax, byte ptr [rsi+2]
    and     eax, 3Fh
    or      ecx, eax
    shl     ecx, 6
    movzx   eax, byte ptr [rsi+3]
    and     eax, 3Fh
    or      eax, ecx
    add     rsi, 4
    sub     rdi, 4
    jmp     esm_pone
esm_ascii:
    inc     rsi
    dec     rdi
    jmp     esm_pone
esm_escape:
    cmp     rdi, 2
    jb      esm_terminar
    movzx   eax, byte ptr [rsi+1]
    add     rsi, 2
    sub     rdi, 2
    cmp     al, 'n'
    jne     @f
    mov     eax, 10
    jmp     esm_pone
@@: cmp     al, 't'
    jne     @f
    mov     eax, 9
    jmp     esm_pone
@@: cmp     al, 'r'
    jne     @f
    mov     eax, 13
    jmp     esm_pone
@@: cmp     al, '0'
    jne     esm_pone                ; \\ \" y cualquier otro: literal
    xor     eax, eax
esm_pone:
    cmp     r12d, MEM_PALABRAS
    jb      esm_cabe
    lea     rcx, e_datos_llenos
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
esm_cabe:
    mov     rdx, vm_mem
    mov     ecx, r12d
    mov     [rdx+rcx*4], eax
    inc     r12d
    jmp     esm_loop
esm_terminar:
    cmp     r12d, MEM_PALABRAS
    jb      esm_cabe2
    lea     rcx, e_datos_llenos
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
esm_cabe2:
    mov     rdx, vm_mem
    mov     ecx, r12d
    mov     dword ptr [rdx+rcx*4], 0
    inc     r12d
    mov     eax, r12d
    sub     eax, r13d               ; celdas escritas
    add     rsp, 20h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
escribir_string_mem ENDP

; ============================================================
; procesar_instruccion: rcx=linea desde el mnemonico
; ============================================================
procesar_instruccion PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 40h                ; espacio para locales
    mov     rbx, rcx

    ; en seccion de datos no van instrucciones
    cmp     dword ptr seccion, SECC_DATOS
    jne     pin_secc_ok
    lea     rcx, e_seccion
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
pin_secc_ok:

    mov     rcx, rbx
    call    buscar_frase
    test    rax, rax
    jnz     pin_frase_ok
    ; no cacho: primer token pal mensaje
    mov     rcx, rbx
    call    siguiente_token
    mov     rsi, rax
    mov     rdi, rdx
    call    copiar_extra_sd
    lea     rcx, e_no_cacho
    mov     edx, linea_num
    lea     r8, buf_extra
    call    error_asm
pin_frase_ok:
    mov     rsi, rax                ; entrada de tabla
    mov     rdi, rdx                ; resto (operandos)

    ; limites de codigo
    mov     eax, pc
    add     eax, 13                 ; peor caso 1+6+6
    cmp     eax, MAX_CODIGO
    jb      pin_cabe
    lea     rcx, e_mucho_codigo
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
pin_cabe:

    cmp     dword ptr pasada, 1
    jne     pin_pasada2

    ; ---- PASADA 1: solo medir + internar literales ----
    inc     dword ptr num_instr
    movzx   eax, byte ptr [rsi+TF_ARIDAD]
    imul    eax, eax, 6
    inc     eax
    add     pc, eax
    ; internar literal si el slot 1 es cadena/msg
    movzx   eax, byte ptr [rsi+TF_K1]
    cmp     eax, K_CADENA
    je      pin_p1_lit
    cmp     eax, K_MSG
    je      pin_p1_lit
    jmp     pin_fin
pin_p1_lit:
    mov     rcx, rdi
    call    saltar_espacios
    cmp     byte ptr [rax], '"'
    jne     pin_fin                 ; no es literal: nada que internar
    mov     rcx, rax
    call    internar_literal
    jmp     pin_fin

pin_pasada2:
    ; ---- PASADA 2: emitir ----
    mov     eax, pc
    mov     [rsp+30h], eax          ; pc_inicio (local)
    ; opcode
    lea     rcx, asm_codigo
    mov     edx, pc
    movzx   r8d, byte ptr [rsi+TF_OPCODE]
    mov     [rcx+rdx], r8b
    inc     dword ptr pc
    ; marcar inicio + linea
    mov     edx, [rsp+30h]
    lea     rcx, asm_inicio_instr
    mov     byte ptr [rcx+rdx], 1
    lea     rcx, asm_linea_por_byte
    mov     eax, linea_num
    mov     [rcx+rdx*4], eax

    ; operando 1
    movzx   eax, byte ptr [rsi+TF_ARIDAD]
    test    eax, eax
    jz      pin_fin
    mov     rcx, rdi
    movzx   edx, byte ptr [rsi+TF_K1]
    call    parsear_y_emitir_operando   ; -> rax = resto
    mov     rdi, rax

    ; operando 2
    movzx   eax, byte ptr [rsi+TF_ARIDAD]
    cmp     eax, 2
    jb      pin_ver_sobra
    ; separador: coma
    mov     rcx, rdi
    call    saltar_espacios
    mov     rdi, rax
    cmp     byte ptr [rdi], ','
    je      pin_coma_ok
    lea     rcx, e_aridad
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
pin_coma_ok:
    inc     rdi
    mov     rcx, rdi
    movzx   edx, byte ptr [rsi+TF_K2]
    call    parsear_y_emitir_operando
    mov     rdi, rax

pin_ver_sobra:
    ; no debe sobrar nada
    mov     rcx, rdi
    call    saltar_espacios
    cmp     byte ptr [rax], 0
    je      pin_fin
    lea     rcx, e_aridad
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm

pin_fin:
    add     rsp, 40h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
procesar_instruccion ENDP

; ============================================================
; internar_literal: rcx=ptr a la comilla inicial
; guarda (ptr arena, largo) si no estaba. addr se asigna despues.
; -> eax = indice del literal
; ============================================================
internar_literal PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 20h
    inc     rcx                     ; dentro
    mov     rsi, rcx
    ; largo hasta comilla de cierre (respetando \")
    xor     r12, r12
il_busca:
    movzx   eax, byte ptr [rsi+r12]
    test    al, al
    jz      il_malo
    cmp     al, '"'
    je      il_largo_ok
    cmp     al, '\'
    jne     il_sigue
    cmp     byte ptr [rsi+r12+1], 0
    je      il_malo
    inc     r12
il_sigue:
    inc     r12
    jmp     il_busca
il_malo:
    lea     rcx, e_string_malo
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
il_largo_ok:
    ; ya existe?
    lea     rbx, literales
    mov     r13d, num_literales
    xor     edi, edi                ; indice
il_dedup:
    cmp     edi, r13d
    jae     il_nuevo
    cmp     [rbx+8], r12d           ; largo
    jne     il_dedup_next
    mov     rcx, rsi
    mov     rdx, [rbx]
    mov     r8, r12
    call    mem_igual
    test    eax, eax
    jz      il_dedup_next
    mov     eax, edi                ; encontrado
    jmp     il_ret
il_dedup_next:
    add     rbx, 16
    inc     edi
    jmp     il_dedup
il_nuevo:
    cmp     dword ptr num_literales, MAX_LITERALES
    jb      il_cabe
    lea     rcx, e_datos_llenos
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
il_cabe:
    mov     rcx, rsi
    mov     rdx, r12
    call    arena_copiar            ; rax = ptr arena
    mov     ecx, num_literales
    shl     ecx, 4                  ; *16
    lea     rbx, literales
    add     rbx, rcx
    mov     [rbx], rax
    mov     [rbx+8], r12d
    mov     dword ptr [rbx+12], 0   ; addr por asignar
    mov     eax, num_literales
    inc     dword ptr num_literales
il_ret:
    add     rsp, 20h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
internar_literal ENDP

; ============================================================
; asignar_literales: despues de pasada 1. les da direccion al
; final del segmento de datos y ESCRIBE las celdas en vm_mem.
; ============================================================
asignar_literales PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 20h
    lea     rbx, literales
    mov     r12d, num_literales
al_loop:
    test    r12d, r12d
    jz      al_fin
    mov     eax, data_cursor
    mov     [rbx+12], eax           ; addr del literal
    mov     rcx, [rbx]              ; ptr texto
    mov     edx, [rbx+8]            ; largo
    mov     r8d, eax
    call    escribir_string_mem
    add     data_cursor, eax
    add     rbx, 16
    dec     r12d
    jmp     al_loop
al_fin:
    add     rsp, 20h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
asignar_literales ENDP

; ============================================================
; buscar_literal: rcx=ptr interior, rdx=largo -> eax=addr, -1 no
; ============================================================
buscar_literal PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 20h
    mov     rsi, rcx
    mov     rdi, rdx
    lea     rbx, literales
    mov     r12d, num_literales
bl_loop:
    test    r12d, r12d
    jz      bl_no
    cmp     [rbx+8], edi
    jne     bl_next
    mov     rcx, rsi
    mov     rdx, [rbx]
    mov     r8, rdi
    call    mem_igual
    test    eax, eax
    jz      bl_next
    mov     eax, [rbx+12]
    jmp     bl_ret
bl_next:
    add     rbx, 16
    dec     r12d
    jmp     bl_loop
bl_no:
    mov     eax, -1
bl_ret:
    add     rsp, 20h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
buscar_literal ENDP

; ============================================================
; parsear_y_emitir_operando: rcx=ptr, edx=kind del slot
; emite 6 bytes (modo, reg, valor) en asm_codigo[pc]
; -> rax = ptr al resto de la linea
; ============================================================
parsear_y_emitir_operando PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 20h
    mov     r13d, edx               ; kind
    call    parsear_operando        ; llena op_modo/op_reg/op_valor/op_origen
    mov     rbx, rax                ; resto

    ; ---- validar slot ----
    cmp     r13d, K_R
    je      peo_emitir              ; K_R acepta todo
    cmp     r13d, K_W
    je      peo_w
    cmp     r13d, K_SALTO
    je      peo_salto
    cmp     r13d, K_IMM
    je      peo_imm
    cmp     r13d, K_CADENA
    je      peo_cadena
    cmp     r13d, K_MSG
    je      peo_msg
    jmp     peo_emitir

peo_w:
    cmp     dword ptr op_modo, MODO_IMM
    jne     peo_w_reg
    lea     rcx, e_slot_escritura
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
peo_w_reg:
    cmp     dword ptr op_modo, MODO_REG
    jne     peo_emitir
    cmp     dword ptr op_reg, REG_SAPEO
    jne     peo_emitir
    lea     rcx, e_sapeo
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm

peo_salto:
    cmp     dword ptr op_modo, MODO_REG
    je      peo_emitir              ; salto indirecto
    cmp     dword ptr op_origen, ORIG_SIM_CODIGO
    je      peo_emitir
    lea     rcx, e_slot_salto
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm

peo_imm:
    cmp     dword ptr op_modo, MODO_IMM
    je      peo_emitir
    lea     rcx, e_operando_malo
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm

peo_cadena:
    ; literal(MEM), MEM, MEMREG o REG-puntero: todo menos IMM numerico
    cmp     dword ptr op_modo, MODO_IMM
    jne     peo_emitir
    cmp     dword ptr op_origen, ORIG_SIM_DATO
    je      peo_emitir              ; etiqueta pelada de dato = puntero, vale
    lea     rcx, e_operando_malo
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm

peo_msg:
    cmp     dword ptr op_origen, ORIG_LITERAL
    je      peo_emitir
    lea     rcx, e_operando_malo
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm

peo_emitir:
    lea     rcx, asm_codigo
    mov     edx, pc
    mov     eax, op_modo
    mov     [rcx+rdx], al
    mov     eax, op_reg
    mov     [rcx+rdx+1], al
    mov     eax, op_valor
    mov     [rcx+rdx+2], eax
    add     dword ptr pc, 6
    mov     rax, rbx
    add     rsp, 20h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
parsear_y_emitir_operando ENDP

; ============================================================
; parsear_operando: rcx=ptr -> llena op_* , rax = resto
; ============================================================
parsear_operando PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 20h
    call    saltar_espacios
    mov     rbx, rax

    movzx   eax, byte ptr [rbx]
    test    al, al
    jz      po_malo
    cmp     al, '['
    je      po_mem
    cmp     al, '"'
    je      po_literal

    ; token normal
    mov     rcx, rbx
    call    siguiente_token
    test    rax, rax
    jz      po_malo
    mov     rsi, rax                ; token
    mov     rdi, rdx                ; largo
    lea     rbx, [rax+rdx]          ; resto

    ; registro?
    mov     rcx, rsi
    mov     rdx, rdi
    call    buscar_registro
    cmp     eax, -1
    je      po_no_reg
    mov     dword ptr op_modo, MODO_REG
    mov     op_reg, eax
    mov     dword ptr op_valor, 0
    mov     dword ptr op_origen, ORIG_REG
    jmp     po_fin

po_no_reg:
    ; numero?
    mov     rcx, rsi
    mov     rdx, rdi
    call    atoi_wea
    test    r8, r8
    jz      po_no_num
    mov     dword ptr op_modo, MODO_IMM
    mov     dword ptr op_reg, 0
    mov     op_valor, eax
    mov     dword ptr op_origen, ORIG_NUM
    jmp     po_fin

po_no_num:
    ; simbolo
    mov     rcx, rsi
    mov     rdx, rdi
    call    buscar_simbolo
    test    rax, rax
    jz      po_fantasma
    mov     dword ptr op_modo, MODO_IMM
    mov     dword ptr op_reg, 0
    mov     ecx, [rax+SIM_VALOR]
    mov     op_valor, ecx
    mov     ecx, [rax+SIM_KIND]
    cmp     ecx, SIMK_CODIGO
    je      po_sim_cod
    cmp     ecx, SIMK_CONST
    je      po_sim_const
    mov     dword ptr op_origen, ORIG_SIM_DATO
    jmp     po_fin
po_sim_cod:
    mov     dword ptr op_origen, ORIG_SIM_CODIGO
    jmp     po_fin
po_sim_const:
    mov     dword ptr op_origen, ORIG_SIM_CONST
    jmp     po_fin

po_fantasma:
    call    copiar_extra_sd         ; usa rsi/rdi
    lea     rcx, e_etiqueta_fantasma
    mov     edx, linea_num
    lea     r8, buf_extra
    call    error_asm

; ---- [algo] / [algo+n] / [algo-n] ----
po_mem:
    inc     rbx                     ; dentro del [
    mov     rcx, rbx
    call    siguiente_token
    test    rax, rax
    jz      po_malo
    mov     rsi, rax
    mov     rdi, rdx
    lea     rbx, [rax+rdx]

    ; el token puede traer +/- pegado: cortarlo
    xor     r12, r12                ; largo base
po_mem_corta:
    cmp     r12, rdi
    jae     po_mem_cortado
    mov     al, [rsi+r12]
    cmp     al, '+'
    je      po_mem_cortado
    cmp     al, '-'
    je      po_mem_cortado
    inc     r12
    jmp     po_mem_corta
po_mem_cortado:
    ; base: registro / numero / simbolo de datos
    mov     rcx, rsi
    mov     rdx, r12
    call    buscar_registro
    cmp     eax, -1
    je      po_mem_no_reg
    mov     dword ptr op_modo, MODO_MEMREG
    mov     op_reg, eax
    mov     dword ptr op_valor, 0
    mov     dword ptr op_origen, ORIG_MEM
    jmp     po_mem_desp
po_mem_no_reg:
    mov     rcx, rsi
    mov     rdx, r12
    call    atoi_wea
    test    r8, r8
    jz      po_mem_no_num
    mov     dword ptr op_modo, MODO_MEM
    mov     dword ptr op_reg, 0
    mov     op_valor, eax
    mov     dword ptr op_origen, ORIG_MEM
    jmp     po_mem_desp
po_mem_no_num:
    mov     rcx, rsi
    mov     rdx, r12
    call    buscar_simbolo
    test    rax, rax
    jz      po_mem_fantasma
    mov     dword ptr op_modo, MODO_MEM
    mov     dword ptr op_reg, 0
    mov     ecx, [rax+SIM_VALOR]
    mov     op_valor, ecx
    mov     dword ptr op_origen, ORIG_MEM
    jmp     po_mem_desp
po_mem_fantasma:
    push    rdi
    mov     rdi, r12
    call    copiar_extra_sd
    pop     rdi
    lea     rcx, e_etiqueta_fantasma
    mov     edx, linea_num
    lea     r8, buf_extra
    call    error_asm

po_mem_desp:
    ; desplazamiento? el resto del token original o lo que siga
    cmp     r12, rdi
    jae     po_mem_desp_fuera
    ; hay +/- pegado dentro del token
    lea     rcx, [rsi+r12]          ; desde el signo
    mov     rdx, rdi
    sub     rdx, r12
    call    leer_desplazamiento
    jmp     po_mem_cierra
po_mem_desp_fuera:
    ; puede venir " + n" separado
    mov     rcx, rbx
    call    saltar_espacios
    mov     rbx, rax
    movzx   eax, byte ptr [rbx]
    cmp     al, '+'
    je      po_mem_desp_sep
    cmp     al, '-'
    je      po_mem_desp_sep
    jmp     po_mem_cierra
po_mem_desp_sep:
    ; armar: signo + siguiente token
    mov     r13b, al                ; signo
    inc     rbx
    mov     rcx, rbx
    call    siguiente_token
    test    rax, rax
    jz      po_malo
    mov     rsi, rax
    mov     rdi, rdx
    lea     rbx, [rax+rdx]
    mov     rcx, rsi
    mov     rdx, rdi
    call    atoi_wea
    test    r8, r8
    jz      po_malo
    cmp     r13b, '-'
    jne     po_mem_suma
    neg     eax
po_mem_suma:
    add     op_valor, eax
po_mem_cierra:
    mov     rcx, rbx
    call    saltar_espacios
    mov     rbx, rax
    cmp     byte ptr [rbx], ']'
    je      po_mem_ok
    lea     rcx, e_operando_malo
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
po_mem_ok:
    inc     rbx
    jmp     po_fin

; ---- "literal" ----
po_literal:
    ; en pasada 2 el literal ya esta internado con direccion
    inc     rbx                     ; dentro
    mov     rsi, rbx
    xor     r12, r12
po_lit_busca:
    movzx   eax, byte ptr [rsi+r12]
    test    al, al
    jz      po_lit_malo
    cmp     al, '"'
    je      po_lit_ok
    cmp     al, '\'
    jne     po_lit_sigue
    cmp     byte ptr [rsi+r12+1], 0
    je      po_lit_malo
    inc     r12
po_lit_sigue:
    inc     r12
    jmp     po_lit_busca
po_lit_malo:
    lea     rcx, e_string_malo
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
po_lit_ok:
    mov     rcx, rsi
    mov     rdx, r12
    call    buscar_literal
    cmp     eax, -1
    jne     po_lit_addr
    ; no deberia pasar (se interno en p1), pero por si acaso
    lea     rcx, e_string_malo
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
po_lit_addr:
    mov     dword ptr op_modo, MODO_MEM
    mov     dword ptr op_reg, 0
    mov     op_valor, eax
    mov     dword ptr op_origen, ORIG_LITERAL
    lea     rbx, [rsi+r12+1]        ; despues de la comilla
    jmp     po_fin

po_malo:
    lea     rcx, e_operando_malo
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm

po_fin:
    mov     rax, rbx
    add     rsp, 20h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
parsear_operando ENDP

; leer_desplazamiento: rcx=ptr (parte con + o -), rdx=largo
; suma el valor a op_valor
leer_desplazamiento PROC PRIVATE
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 20h
    mov     rsi, rcx
    mov     rdi, rdx
    movzx   ebx, byte ptr [rsi]     ; signo
    inc     rsi
    dec     rdi
    jz      ld_malo
    mov     rcx, rsi
    mov     rdx, rdi
    call    atoi_wea
    test    r8, r8
    jz      ld_malo
    cmp     bl, '-'
    jne     ld_suma
    neg     eax
ld_suma:
    add     op_valor, eax
    add     rsp, 20h
    pop     rdi
    pop     rsi
    pop     rbx
    ret
ld_malo:
    lea     rcx, e_operando_malo
    mov     edx, linea_num
    xor     r8, r8
    call    error_asm
    add     rsp, 20h
    pop     rdi
    pop     rsi
    pop     rbx
    ret
leer_desplazamiento ENDP

; ============================================================
; resolver_entry
; ============================================================
resolver_entry PROC
    push    rbx
    sub     rsp, 20h
    cmp     entry_nombre, 0
    je      re_default
    mov     rcx, entry_nombre
    mov     edx, entry_largo
    call    buscar_simbolo
    test    rax, rax
    jz      re_no_existe
    cmp     dword ptr [rax+SIM_KIND], SIMK_CODIGO
    jne     re_no_existe
    mov     ecx, [rax+SIM_VALOR]
    mov     asm_entry, ecx
    jmp     re_fin
re_no_existe:
    lea     rcx, e_entry
    xor     edx, edx
    mov     r8, entry_nombre
    call    error_asm
re_default:
    ; etiqueta "inicio" si existe, si no pc=0
    lea     rcx, nombre_inicio
    mov     edx, 6
    call    buscar_simbolo
    test    rax, rax
    jz      re_cero
    cmp     dword ptr [rax+SIM_KIND], SIMK_CODIGO
    jne     re_cero
    mov     ecx, [rax+SIM_VALOR]
    mov     asm_entry, ecx
    jmp     re_fin
re_cero:
    mov     dword ptr asm_entry, 0
re_fin:
    add     rsp, 20h
    pop     rbx
    ret
resolver_entry ENDP

END
