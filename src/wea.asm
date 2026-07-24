; ============================================================
; wea.asm - punto de entrada y CLI
;   wea corre archivo.wea [--semilla=N]
;   wea revisa archivo.wea
;   wea archivo.wea            (atajo: corre)
; ============================================================

include winapi.inc

EXTERN util_init: PROC
EXTERN leer_archivo: PROC
EXTERN pedir_memoria: PROC
EXTERN ensamblar: PROC
EXTERN vm_init: PROC
EXTERN vm_correr: PROC
EXTERN vm_semilla: DWORD
EXTERN error_asm: PROC
EXTERN aviso: PROC
EXTERN atoi_wea: PROC
EXTERN mem_igual: PROC
EXTERN str_largo: PROC
EXTERN e_archivo: BYTE
EXTERN e_uso: BYTE
EXTERN compilar_a_asm: PROC

PUBLIC inicio

MODO_CORRE   equ 0
MODO_REVISA  equ 1
MODO_COMPILA equ 2

.data
sub_corre   db "corre", 0
sub_run     db "run", 0
sub_revisa  db "revisa", 0
sub_check   db "check", 0
sub_compila db "compila", 0
sub_build   db "build", 0
pre_semilla db "--semilla=", 0
msg_filete  db "ta filete, compila la wea", 0
msg_gen     db "quedo lista la wea generada (.gen.asm), ahora ml64 hace el resto", 0
ext_gen     db ".gen.asm", 0

modo        dd MODO_CORRE
tok_sub     db 260 dup (0)
tok_arch    db 260 dup (0)
tok_flag    db 260 dup (0)
sal_path    db 300 dup (0)

.code

; ------------------------------------------------------------
; copiar_token: rcx=ptr cmdline, rdx=destino (260)
; -> rax = ptr despues del token (respeta comillas)
; ------------------------------------------------------------
copiar_token PROC PRIVATE
    push    rsi
    push    rdi
    push    rbx
    mov     rsi, rcx
    mov     rdi, rdx
    ; saltar espacios
ct_espacios:
    movzx   eax, byte ptr [rsi]
    cmp     al, ' '
    je      ct_avanza
    cmp     al, 9
    je      ct_avanza
    jmp     ct_copia
ct_avanza:
    inc     rsi
    jmp     ct_espacios
ct_copia:
    xor     rbx, rbx                ; largo copiado
    xor     r10d, r10d              ; dentro de comillas
ct_loop:
    movzx   eax, byte ptr [rsi]
    test    al, al
    jz      ct_fin
    cmp     al, '"'
    jne     ct_no_comilla
    xor     r10d, 1                 ; toggle, la comilla no se copia
    inc     rsi
    jmp     ct_loop
ct_no_comilla:
    test    r10d, r10d
    jnz     ct_dentro
    cmp     al, ' '
    je      ct_fin
    cmp     al, 9
    je      ct_fin
ct_dentro:
    cmp     rbx, 258
    jae     ct_fin
    mov     [rdi+rbx], al
    inc     rbx
    inc     rsi
    jmp     ct_loop
ct_fin:
    mov     byte ptr [rdi+rbx], 0
    mov     rax, rsi
    pop     rbx
    pop     rdi
    pop     rsi
    ret
copiar_token ENDP

; ------------------------------------------------------------
; igual_z: rcx=a asciiz, rdx=b asciiz -> eax 1/0
; ------------------------------------------------------------
igual_z PROC PRIVATE
    push    rsi
    push    rdi
    mov     rsi, rcx
    mov     rdi, rdx
iz_loop:
    mov     al, [rsi]
    cmp     al, [rdi]
    jne     iz_no
    test    al, al
    jz      iz_si
    inc     rsi
    inc     rdi
    jmp     iz_loop
iz_si:
    mov     eax, 1
    pop     rdi
    pop     rsi
    ret
iz_no:
    xor     eax, eax
    pop     rdi
    pop     rsi
    ret
igual_z ENDP

; ------------------------------------------------------------
; empieza_con: rcx=texto, rdx=prefijo -> eax 1/0
; ------------------------------------------------------------
empieza_con PROC PRIVATE
    push    rsi
    push    rdi
    mov     rsi, rcx
    mov     rdi, rdx
ec_loop:
    mov     al, [rdi]
    test    al, al
    jz      ec_si
    cmp     al, [rsi]
    jne     ec_no
    inc     rsi
    inc     rdi
    jmp     ec_loop
ec_si:
    mov     eax, 1
    pop     rdi
    pop     rsi
    ret
ec_no:
    xor     eax, eax
    pop     rdi
    pop     rsi
    ret
empieza_con ENDP

; ------------------------------------------------------------
; procesar_flag: rcx=token  (--semilla=N)
; ------------------------------------------------------------
procesar_flag PROC PRIVATE
    push    rbx
    sub     rsp, 20h
    mov     rbx, rcx
    lea     rdx, pre_semilla
    call    empieza_con
    test    eax, eax
    jz      pf_fin
    lea     rcx, [rbx+10]           ; largo "--semilla="
    push    rcx
    call    str_largo               ; ojo: rcx ya es el ptr
    pop     rcx
    mov     rdx, rax
    call    atoi_wea
    test    r8, r8
    jz      pf_fin
    mov     vm_semilla, eax
pf_fin:
    add     rsp, 20h
    pop     rbx
    ret
procesar_flag ENDP

; ------------------------------------------------------------
; armar_salida: rbx = ruta de entrada asciiz
; llena sal_path = ruta sin extension + ".gen.asm"
; ------------------------------------------------------------
armar_salida PROC PRIVATE
    push    rsi
    push    rdi
    push    r12
    sub     rsp, 20h
    mov     rsi, rbx
    lea     rdi, sal_path
    xor     r12, r12                ; posicion del ultimo '.' (0 = ninguno)
    xor     rax, rax                ; indice
as_copia:
    mov     cl, [rsi+rax]
    mov     [rdi+rax], cl
    test    cl, cl
    jz      as_copiado
    cmp     cl, '.'
    jne     as_no_punto
    mov     r12, rax
as_no_punto:
    cmp     cl, '\'
    je      as_reset
    cmp     cl, '/'
    jne     as_sigue
as_reset:
    xor     r12, r12                ; punto de un directorio: no vale
as_sigue:
    inc     rax
    cmp     rax, 288
    jb      as_copia
as_copiado:
    ; truncar en el punto (si hubo) y pegar ".gen.asm"
    test    r12, r12
    jz      as_sin_punto
    mov     rax, r12
as_sin_punto:
    lea     rdi, [rdi+rax]
    lea     rsi, ext_gen
as_ext:
    mov     cl, [rsi]
    mov     [rdi], cl
    test    cl, cl
    jz      as_fin
    inc     rsi
    inc     rdi
    jmp     as_ext
as_fin:
    add     rsp, 20h
    pop     r12
    pop     rdi
    pop     rsi
    ret
armar_salida ENDP

; ============================================================
; inicio - entry point
; ============================================================
inicio PROC
    sub     rsp, 28h

    call    util_init

    ; linea de comandos
    call    GetCommandLineA
    mov     rcx, rax
    lea     rdx, tok_sub            ; primer token = exe (se bota)
    call    copiar_token
    mov     rcx, rax
    lea     rdx, tok_sub
    call    copiar_token            ; token 1 real
    mov     rcx, rax
    lea     rdx, tok_arch
    call    copiar_token            ; token 2
    mov     rcx, rax
    lea     rdx, tok_flag
    call    copiar_token            ; token 3 (flag)

    ; sin argumentos?
    cmp     byte ptr tok_sub, 0
    jne     ini_hay_args
    lea     rcx, e_uso
    xor     edx, edx
    xor     r8, r8
    call    error_asm

ini_hay_args:
    ; subcomando?
    lea     rcx, tok_sub
    lea     rdx, sub_corre
    call    igual_z
    test    eax, eax
    jnz     ini_es_corre
    lea     rcx, tok_sub
    lea     rdx, sub_run
    call    igual_z
    test    eax, eax
    jnz     ini_es_corre
    lea     rcx, tok_sub
    lea     rdx, sub_revisa
    call    igual_z
    test    eax, eax
    jnz     ini_es_revisa
    lea     rcx, tok_sub
    lea     rdx, sub_check
    call    igual_z
    test    eax, eax
    jnz     ini_es_revisa
    lea     rcx, tok_sub
    lea     rdx, sub_compila
    call    igual_z
    test    eax, eax
    jnz     ini_es_compila
    lea     rcx, tok_sub
    lea     rdx, sub_build
    call    igual_z
    test    eax, eax
    jnz     ini_es_compila
    ; no es subcomando: es el archivo directo. correr.
    ; tok_arch pasa a ser flag
    lea     rcx, tok_arch
    call    procesar_flag
    lea     rcx, tok_sub            ; el "subcomando" era el archivo
    jmp     ini_cargar

ini_es_compila:
    mov     dword ptr modo, MODO_COMPILA
    jmp     ini_con_sub
ini_es_revisa:
    mov     dword ptr modo, MODO_REVISA
    jmp     ini_con_sub
ini_es_corre:
    mov     dword ptr modo, MODO_CORRE
ini_con_sub:
    cmp     byte ptr tok_arch, 0
    jne     ini_arch_ok
    lea     rcx, e_uso
    xor     edx, edx
    xor     r8, r8
    call    error_asm
ini_arch_ok:
    lea     rcx, tok_flag
    call    procesar_flag
    lea     rcx, tok_arch

ini_cargar:
    ; rcx = ruta del archivo
    mov     rbx, rcx                ; guardar por si hay error
    call    leer_archivo
    test    rax, rax
    jnz     ini_leido
    lea     rcx, e_archivo
    xor     edx, edx
    mov     r8, rbx
    call    error_asm
ini_leido:
    mov     rsi, rax                ; fuente
    mov     rdi, rdx                ; largo

    ; memoria de la VM (el ensamblador escribe los datos ahi)
    call    vm_init
    test    eax, eax
    jnz     ini_vm_ok
    lea     rcx, e_archivo          ; sin memoria... dificil, pero po si acaso
    xor     edx, edx
    xor     r8, r8
    call    error_asm
ini_vm_ok:

    mov     rcx, rsi
    mov     rdx, rdi
    call    ensamblar

    cmp     dword ptr modo, MODO_REVISA
    jne     ini_no_revisa
    lea     rcx, msg_filete
    call    aviso
    xor     ecx, ecx
    call    ExitProcess

ini_no_revisa:
    cmp     dword ptr modo, MODO_COMPILA
    jne     ini_correr
    ; armar la ruta de salida: <entrada sin extension>.gen.asm
    call    armar_salida            ; usa rbx (ruta entrada), llena sal_path
    lea     rcx, sal_path
    call    compilar_a_asm
    lea     rcx, msg_gen
    call    aviso
    xor     ecx, ecx
    call    ExitProcess

ini_correr:
    call    vm_correr
    ; vm_correr no vuelve (halt o error), pero por si acaso:
    xor     ecx, ecx
    call    ExitProcess
    ret
inicio ENDP

END
