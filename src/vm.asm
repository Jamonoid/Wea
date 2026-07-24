; ============================================================
; vm.asm - la maquina virtual de Wea
; fetch/decode/execute con jump table. Registros int32.
; La gracia de hacerla en asm: eax YA es aritmetica con wrap
; de 32 bits, e idiv YA trunca como C. El hardware coopera.
; ============================================================

include winapi.inc
include isa.inc

PUBLIC vm_init              ; asigna memoria -> eax 1 ok / 0 fallo
PUBLIC vm_correr            ; ejecuta desde asm_entry. no vuelve si error.
PUBLIC vm_mem               ; qword ptr a 65536 celdas int32
PUBLIC vm_semilla           ; dd semilla del PRNG (0 = usar reloj)

EXTERN pedir_memoria: PROC
EXTERN print_out: PROC
EXTERN print_err: PROC
EXTERN print_out_z: PROC
EXTERN print_err_z: PROC
EXTERN print_int_out: PROC
EXTERN print_int_err: PROC
EXTERN itoa32: PROC
EXTERN atoi_wea: PROC
EXTERN leer_linea_stdin: PROC
EXTERN codepoint_a_utf8: PROC
EXTERN error_runtime: PROC
EXTERN str_largo: PROC

EXTERN asm_codigo: BYTE
EXTERN asm_codigo_len: DWORD
EXTERN asm_entry: DWORD
EXTERN asm_linea_por_byte: DWORD
EXTERN asm_inicio_instr: BYTE
EXTERN asm_datos_fin: DWORD

EXTERN r_div_cero:BYTE, r_mem:BYTE, r_pila_over:BYTE, r_pila_under:BYTE
EXTERN r_salto:BYTE, r_sin_halt:BYTE, r_eof:BYTE, r_num_malo:BYTE
EXTERN r_lote:BYTE, r_limite:BYTE

EXTERN nombres_opcodes: QWORD

MAX_PASOS       equ 100000000       ; 100M pasos y se declara colgada la wea

.data
vm_mem          dq 0
vm_semilla      dd 0
regs            dd NUM_REGS dup (0)
pc_actual       dd 0                ; inicio de la instruccion en curso (para errores)
pasos           dq 0
rng_estado      dd 0
ft_buf          dq 0                ; FILETIME para la semilla

nl              db 10, 0
prompt_regs_1   db "  wn=", 0
sep_reg         db "  ", 0
eq_txt          db "=", 0
sapeo_txt       db "  sapeo=", 0
desnudo_pre     db "[desnudate] ", 0

nombres_regs    db "wn", 0, 0, 0, 0, 0, 0
                db "ql", 0, 0, 0, 0, 0, 0
                db "pico", 0, 0, 0, 0
                db "tetas", 0, 0, 0
                db "pichula", 0
                db "poto", 0, 0, 0, 0
                db "chucha", 0, 0
                db "raja", 0, 0, 0, 0
                db "hoyo", 0, 0, 0, 0
                db "ojete", 0, 0, 0

.data?
buf_num         db 16 dup (?)
buf_linea_in    db 256 dup (?)
buf_utf8        db 8 dup (?)

.code

; ============================================================
; vm_init
; ============================================================
vm_init PROC
    sub     rsp, 28h
    mov     rcx, MEM_PALABRAS * TAM_CELDA
    call    pedir_memoria
    mov     vm_mem, rax
    test    rax, rax
    setnz   al
    movzx   eax, al
    add     rsp, 28h
    ret
vm_init ENDP

; ============================================================
; helpers internos
; ============================================================

; error con linea actual: rcx=msg -> no vuelve
morir PROC PRIVATE
    mov     eax, pc_actual
    lea     rdx, asm_linea_por_byte
    mov     edx, [rdx+rax*4]
    xor     r8, r8
    jmp     error_runtime
morir ENDP

; chequear direccion de memoria: ecx=direccion -> revienta si mala
; devuelve rax = ptr a la celda
chequear_dir PROC PRIVATE
    cmp     ecx, MEM_PALABRAS
    jae     cd_malo
    mov     rax, vm_mem
    mov     edx, ecx
    lea     rax, [rax+rdx*4]
    ret
cd_malo:
    lea     rcx, r_mem
    call    morir
    ret
chequear_dir ENDP

; leer_operando: rsi=ptr al operando (modo,reg,valor) -> eax=valor
; usa: rcx rdx
leer_operando PROC PRIVATE
    movzx   ecx, byte ptr [rsi]     ; modo
    cmp     ecx, MODO_REG
    je      lo_reg
    cmp     ecx, MODO_IMM
    je      lo_imm
    cmp     ecx, MODO_MEM
    je      lo_mem
    ; MEMREG
    movzx   edx, byte ptr [rsi+1]
    lea     rcx, regs
    mov     ecx, [rcx+rdx*4]
    add     ecx, [rsi+2]            ; + desplazamiento
    sub     rsp, 28h
    call    chequear_dir
    add     rsp, 28h
    mov     eax, [rax]
    ret
lo_reg:
    movzx   edx, byte ptr [rsi+1]
    lea     rax, regs
    mov     eax, [rax+rdx*4]
    ret
lo_imm:
    mov     eax, [rsi+2]
    ret
lo_mem:
    mov     ecx, [rsi+2]
    sub     rsp, 28h
    call    chequear_dir
    add     rsp, 28h
    mov     eax, [rax]
    ret
leer_operando ENDP

; escribir_operando: rsi=ptr operando, eax=valor
escribir_operando PROC PRIVATE
    push    rax
    movzx   ecx, byte ptr [rsi]
    cmp     ecx, MODO_REG
    je      eo_reg
    cmp     ecx, MODO_MEM
    je      eo_mem
    ; MEMREG
    movzx   edx, byte ptr [rsi+1]
    lea     rcx, regs
    mov     ecx, [rcx+rdx*4]
    add     ecx, [rsi+2]
    sub     rsp, 20h                ; 1 push + 20h -> alineado
    call    chequear_dir
    add     rsp, 20h
    pop     rcx
    mov     [rax], ecx
    ret
eo_reg:
    movzx   edx, byte ptr [rsi+1]
    pop     rax
    lea     rcx, regs
    mov     [rcx+rdx*4], eax
    ret
eo_mem:
    mov     ecx, [rsi+2]
    sub     rsp, 20h
    call    chequear_dir
    add     rsp, 20h
    pop     rcx
    mov     [rax], ecx
    ret
escribir_operando ENDP

; poner_flags: eax = resultado -> sapeo (Z si 0, S si negativo)
poner_flags PROC PRIVATE
    xor     ecx, ecx
    test    eax, eax
    jnz     pf_no_z
    or      ecx, FLAG_Z
pf_no_z:
    jns     pf_no_s
    or      ecx, FLAG_S
pf_no_s:
    lea     rdx, regs
    mov     [rdx+REG_SAPEO*4], ecx
    ret
poner_flags ENDP

; push_vm: eax=valor -> revienta si overflow
push_vm PROC PRIVATE
    lea     rcx, regs
    mov     edx, [rcx+REG_HOYO*4]
    dec     edx
    cmp     edx, asm_datos_fin      ; guardia: no pisar los datos
    jbe     pv_over
    mov     [rcx+REG_HOYO*4], edx
    mov     rcx, vm_mem
    mov     [rcx+rdx*4], eax
    ret
pv_over:
    lea     rcx, r_pila_over
    call    morir
    ret
push_vm ENDP

; pop_vm: -> eax
pop_vm PROC PRIVATE
    lea     rcx, regs
    mov     edx, [rcx+REG_HOYO*4]
    cmp     edx, MEM_PALABRAS
    jae     pv_under
    mov     rax, vm_mem
    mov     eax, [rax+rdx*4]
    inc     edx
    mov     [rcx+REG_HOYO*4], edx
    ret
pv_under:
    lea     rcx, r_pila_under
    call    morir
    ret
pop_vm ENDP

; saltar_a: eax = pc destino -> valida y actualiza rdi (pc del loop)
; OJO: se usa dentro de vm_correr, rdi es el pc del interprete
validar_salto PROC PRIVATE
    cmp     eax, asm_codigo_len
    jae     vs_malo
    lea     rcx, asm_inicio_instr
    cmp     byte ptr [rcx+rax], 1
    jne     vs_malo
    ret
vs_malo:
    lea     rcx, r_salto
    call    morir
    ret
validar_salto ENDP

; imprimir string de vm_mem: ecx = direccion celda inicial
; celdas = codepoints hasta 0
chamullar PROC PRIVATE
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 20h
    mov     ebx, ecx
ch_loop:
    mov     ecx, ebx
    call    chequear_dir
    mov     eax, [rax]
    test    eax, eax
    jz      ch_fin
    mov     ecx, eax
    lea     rdx, buf_utf8
    call    codepoint_a_utf8
    mov     rdx, rax
    lea     rcx, buf_utf8
    call    print_out
    inc     ebx
    jmp     ch_loop
ch_fin:
    add     rsp, 20h
    pop     rdi
    pop     rsi
    pop     rbx
    ret
chamullar ENDP

; xorshift32
rng_siguiente PROC PRIVATE
    mov     eax, rng_estado
    mov     ecx, eax
    shl     ecx, 13
    xor     eax, ecx
    mov     ecx, eax
    shr     ecx, 17
    xor     eax, ecx
    mov     ecx, eax
    shl     ecx, 5
    xor     eax, ecx
    mov     rng_estado, eax
    ret
rng_siguiente ENDP

; ============================================================
; vm_correr - el loop principal
;   rdi = pc (offset en asm_codigo)
;   rsi = ptr al operando en curso
; ============================================================
vm_correr PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 20h

    ; init registros
    lea     rcx, regs
    xor     eax, eax
    mov     edx, NUM_REGS
vc_limpia:
    mov     [rcx], eax
    add     rcx, 4
    dec     edx
    jnz     vc_limpia
    lea     rcx, regs
    mov     dword ptr [rcx+REG_HOYO*4], MEM_PALABRAS   ; pila vacia = tope
    mov     dword ptr [rcx+REG_OJETE*4], MEM_PALABRAS

    ; init rng
    mov     eax, vm_semilla
    test    eax, eax
    jnz     vc_semilla_ok
    lea     rcx, ft_buf
    call    GetSystemTimeAsFileTime
    mov     eax, dword ptr ft_buf
    or      eax, 1                  ; que no sea 0
vc_semilla_ok:
    mov     rng_estado, eax

    mov     edi, asm_entry
    mov     qword ptr pasos, 0

; ---------------- loop principal ----------------
vc_loop:
    ; fin del codigo sin halt?
    cmp     edi, asm_codigo_len
    jb      vc_sigue
    lea     rcx, r_sin_halt
    mov     eax, asm_codigo_len
    test    eax, eax
    jz      vc_sin_halt_sin_linea
    mov     pc_actual, edi
vc_sin_halt_sin_linea:
    xor     edx, edx
    xor     r8, r8
    call    error_runtime
vc_sigue:
    mov     pc_actual, edi
    inc     qword ptr pasos
    mov     rax, pasos
    cmp     rax, MAX_PASOS
    jb      vc_pasos_ok
    lea     rcx, r_limite
    call    morir
vc_pasos_ok:
    lea     rbx, asm_codigo
    movzx   eax, byte ptr [rbx+rdi]
    lea     rsi, [rbx+rdi+1]        ; operando 1
    ; dispatch
    lea     rcx, tabla_saltos
    mov     rax, [rcx+rax*8]
    jmp     rax

; ---- NOP ----
op_nop_x:
    inc     rdi
    jmp     vc_loop

; ---- MOV dst, src ----
op_mov_x:
    lea     rdx, [rsi+6]            ; operando 2
    push    rsi
    mov     rsi, rdx
    call    leer_operando
    pop     rsi
    call    escribir_operando
    add     rdi, 13
    jmp     vc_loop

; ---- PUSH src ----
op_push_x:
    call    leer_operando
    call    push_vm
    add     rdi, 7
    jmp     vc_loop

; ---- POP dst ----
op_pop_x:
    call    pop_vm
    call    escribir_operando
    add     rdi, 7
    jmp     vc_loop

; ---- XCHG a, b ----
op_xchg_x:
    call    leer_operando
    mov     r12d, eax               ; a
    push    rsi
    lea     rsi, [rsi+6]
    call    leer_operando
    mov     r13d, eax               ; b
    mov     eax, r12d
    call    escribir_operando       ; b = a
    pop     rsi
    mov     eax, r13d
    call    escribir_operando       ; a = b
    add     rdi, 13
    jmp     vc_loop

; ---- aritmetica de 2 operandos: dst op= src ----
op_add_x:
    call    leer_op2                ; r12d=dst, r13d=src
    add     r12d, r13d
    jmp     op2_guardar
op_sub_x:
    call    leer_op2
    sub     r12d, r13d
    jmp     op2_guardar
op_mul_x:
    call    leer_op2
    mov     eax, r12d
    imul    eax, r13d
    mov     r12d, eax
    jmp     op2_guardar
op_div_x:
    call    leer_op2
    test    r13d, r13d
    jnz     od_no_cero
    lea     rcx, r_div_cero
    call    morir
od_no_cero:
    ; INT_MIN / -1 revienta idiv: wrap manual
    cmp     r12d, 80000000h
    jne     od_idiv
    cmp     r13d, -1
    jne     od_idiv
    jmp     op2_guardar             ; INT_MIN / -1 = INT_MIN (wrap)
od_idiv:
    mov     eax, r12d
    cdq
    idiv    r13d
    mov     r12d, eax
    jmp     op2_guardar
op_mod_x:
    call    leer_op2
    test    r13d, r13d
    jnz     om_no_cero
    lea     rcx, r_div_cero
    call    morir
om_no_cero:
    cmp     r12d, 80000000h
    jne     om_idiv
    cmp     r13d, -1
    jne     om_idiv
    xor     r12d, r12d              ; INT_MIN % -1 = 0
    jmp     op2_guardar
om_idiv:
    mov     eax, r12d
    cdq
    idiv    r13d
    mov     r12d, edx               ; resto
    jmp     op2_guardar
op_and_x:
    call    leer_op2
    and     r12d, r13d
    jmp     op2_guardar
op_or_x:
    call    leer_op2
    or      r12d, r13d
    jmp     op2_guardar
op_xor_x:
    call    leer_op2
    xor     r12d, r13d
    jmp     op2_guardar
op_shl_x:
    call    leer_op2
    mov     ecx, r13d
    and     ecx, 31
    shl     r12d, cl
    jmp     op2_guardar
op_sar_x:
    call    leer_op2
    mov     ecx, r13d
    and     ecx, 31
    sar     r12d, cl
    jmp     op2_guardar
op_shr_x:
    call    leer_op2
    mov     ecx, r13d
    and     ecx, 31
    shr     r12d, cl
    jmp     op2_guardar

; comun: leer ambos operandos. rsi=op1. r12d=valor1, r13d=valor2
leer_op2 PROC PRIVATE
    push    rsi
    sub     rsp, 20h                ; 1 push+20h+ret_addr: dentro ok
    call    leer_operando
    mov     r12d, eax
    lea     rsi, [rsi+6]
    call    leer_operando
    mov     r13d, eax
    add     rsp, 20h
    pop     rsi
    ret
leer_op2 ENDP

op2_guardar:
    mov     eax, r12d
    call    escribir_operando
    call    poner_flags
    add     rdi, 13
    jmp     vc_loop

; ---- aritmetica de 1 operando ----
op_inc_x:
    call    leer_operando
    inc     eax
    jmp     op1_guardar
op_dec_x:
    call    leer_operando
    dec     eax
    jmp     op1_guardar
op_neg_x:
    call    leer_operando
    neg     eax
    jmp     op1_guardar
op_not_x:
    call    leer_operando
    not     eax
op1_guardar:
    call    escribir_operando
    call    poner_flags
    add     rdi, 7
    jmp     vc_loop

; ---- CMP a, b: sapeo = Z(iguales) S(a<b con signo) ----
op_cmp_x:
    call    leer_op2
    xor     ecx, ecx
    cmp     r12d, r13d
    jne     oc_no_z
    or      ecx, FLAG_Z
oc_no_z:
    jge     oc_no_s                 ; jge: con signo, sin lios de overflow
    or      ecx, FLAG_S
oc_no_s:
    lea     rdx, regs
    mov     [rdx+REG_SAPEO*4], ecx
    add     rdi, 13
    jmp     vc_loop

; ---- saltos ----
; condicion en r12d: 1 salta / 0 sigue
op_jmp_x:
    mov     r12d, 1
    jmp     saltar_cond
op_je_x:
    lea     rcx, regs
    mov     eax, [rcx+REG_SAPEO*4]
    and     eax, FLAG_Z
    setnz   r12b
    movzx   r12d, r12b
    jmp     saltar_cond
op_jne_x:
    lea     rcx, regs
    mov     eax, [rcx+REG_SAPEO*4]
    and     eax, FLAG_Z
    setz    r12b
    movzx   r12d, r12b
    jmp     saltar_cond
op_jl_x:
    lea     rcx, regs
    mov     eax, [rcx+REG_SAPEO*4]
    and     eax, FLAG_S
    setnz   r12b
    movzx   r12d, r12b
    jmp     saltar_cond
op_jge_x:
    lea     rcx, regs
    mov     eax, [rcx+REG_SAPEO*4]
    and     eax, FLAG_S
    setz    r12b
    movzx   r12d, r12b
    jmp     saltar_cond
op_jle_x:
    lea     rcx, regs
    mov     eax, [rcx+REG_SAPEO*4]
    test    eax, FLAG_S or FLAG_Z
    setnz   r12b
    movzx   r12d, r12b
    jmp     saltar_cond
op_jg_x:
    lea     rcx, regs
    mov     eax, [rcx+REG_SAPEO*4]
    test    eax, FLAG_S or FLAG_Z
    setz    r12b
    movzx   r12d, r12b
saltar_cond:
    test    r12d, r12d
    jz      sc_no_salta
    call    leer_operando           ; destino (etiqueta=IMM pc, o registro)
    call    validar_salto
    mov     edi, eax
    jmp     vc_loop
sc_no_salta:
    add     rdi, 7
    jmp     vc_loop

; ---- CALL ----
op_call_x:
    lea     eax, [edi+7]            ; direccion de retorno
    call    push_vm
    call    leer_operando
    call    validar_salto
    mov     edi, eax
    jmp     vc_loop

; ---- RET ----
op_ret_x:
    call    pop_vm
    call    validar_salto
    mov     edi, eax
    jmp     vc_loop

; ---- ENTER n: push ojete; ojete=hoyo; hoyo -= n ----
op_enter_x:
    lea     rcx, regs
    mov     eax, [rcx+REG_OJETE*4]
    call    push_vm
    lea     rcx, regs
    mov     eax, [rcx+REG_HOYO*4]
    mov     [rcx+REG_OJETE*4], eax
    push    rsi
    sub     rsp, 20h
    call    leer_operando           ; n (imm)
    add     rsp, 20h
    pop     rsi
    lea     rcx, regs
    sub     [rcx+REG_HOYO*4], eax
    ; validar que no se fue a la chucha
    mov     eax, [rcx+REG_HOYO*4]
    cmp     eax, asm_datos_fin
    jbe     oe_over
    cmp     eax, MEM_PALABRAS
    ja      oe_over
    add     rdi, 7
    jmp     vc_loop
oe_over:
    lea     rcx, r_pila_over
    call    morir

; ---- LEAVE: hoyo=ojete; pop ojete ----
op_leave_x:
    lea     rcx, regs
    mov     eax, [rcx+REG_OJETE*4]
    mov     [rcx+REG_HOYO*4], eax
    call    pop_vm
    lea     rcx, regs
    mov     [rcx+REG_OJETE*4], eax
    inc     rdi
    jmp     vc_loop

; ---- PRINTLN / PRINT ----
op_println_x:
    call    leer_operando
    mov     ecx, eax
    call    print_int_out
    lea     rcx, nl
    call    print_out_z
    add     rdi, 7
    jmp     vc_loop
op_print_x:
    call    leer_operando
    mov     ecx, eax
    call    print_int_out
    add     rdi, 7
    jmp     vc_loop

; ---- PUTS (chamulla) ----
op_puts_x:
    movzx   ecx, byte ptr [rsi]     ; modo
    cmp     ecx, MODO_REG
    jne     opu_mem
    movzx   edx, byte ptr [rsi+1]
    lea     rcx, regs
    mov     ecx, [rcx+rdx*4]        ; el registro contiene la direccion
    jmp     opu_imprimir
opu_mem:
    cmp     ecx, MODO_IMM
    jne     opu_directo
    mov     ecx, [rsi+2]            ; etiqueta pelada: direccion
    jmp     opu_imprimir
opu_directo:
    cmp     ecx, MODO_MEMREG
    jne     opu_mem_simple
    movzx   edx, byte ptr [rsi+1]
    lea     rcx, regs
    mov     ecx, [rcx+rdx*4]
    add     ecx, [rsi+2]
    jmp     opu_imprimir
opu_mem_simple:
    mov     ecx, [rsi+2]            ; MEM: la direccion misma
opu_imprimir:
    call    chamullar
    add     rdi, 7
    jmp     vc_loop

; ---- PUTCHAR ----
op_putchar_x:
    call    leer_operando
    mov     ecx, eax
    lea     rdx, buf_utf8
    call    codepoint_a_utf8
    mov     rdx, rax
    lea     rcx, buf_utf8
    call    print_out
    add     rdi, 7
    jmp     vc_loop

; ---- READINT (pesca) ----
op_readint_x:
    lea     rcx, buf_linea_in
    mov     edx, 255
    call    leer_linea_stdin
    cmp     rax, -1
    jne     ori_hay
    lea     rcx, r_eof
    call    morir
ori_hay:
    mov     rdx, rax
    lea     rcx, buf_linea_in
    call    atoi_wea
    test    r8, r8
    jnz     ori_ok
    lea     rcx, r_num_malo
    call    morir
ori_ok:
    call    escribir_operando
    add     rdi, 7
    jmp     vc_loop

; ---- GETCHAR: un byte de stdin, -1 en EOF ----
op_getchar_x:
    lea     rcx, buf_linea_in
    mov     edx, 1
    call    leer_linea_stdin        ; simplificacion: lee linea, toma 1er char
    cmp     rax, -1
    jne     ogc_hay
    mov     eax, -1
    jmp     ogc_pone
ogc_hay:
    test    rax, rax
    jnz     ogc_char
    mov     eax, 10                 ; linea vacia = \n
    jmp     ogc_pone
ogc_char:
    movzx   eax, byte ptr buf_linea_in
ogc_pone:
    call    escribir_operando
    add     rdi, 7
    jmp     vc_loop

; ---- DUMP (desnudate): registros a stderr ----
op_dump_x:
    lea     rcx, desnudo_pre
    call    print_err_z
    xor     r12d, r12d
odu_loop:
    cmp     r12d, 10                ; wn..ojete (sapeo aparte)
    jae     odu_sapeo
    mov     eax, r12d
    shl     eax, 3
    lea     rcx, nombres_regs
    add     rcx, rax
    call    print_err_z
    lea     rcx, eq_txt
    call    print_err_z
    lea     rcx, regs
    mov     ecx, [rcx+r12*4]
    call    print_int_err
    lea     rcx, sep_reg
    call    print_err_z
    inc     r12d
    jmp     odu_loop
odu_sapeo:
    lea     rcx, sapeo_txt
    call    print_err_z
    lea     rcx, regs
    mov     ecx, [rcx+REG_SAPEO*4]
    call    print_int_err
    lea     rcx, nl
    call    print_err_z
    inc     rdi
    jmp     vc_loop

; ---- HALT ----
op_halt_x:
    mov     ecx, EXIT_OK
    call    ExitProcess
    jmp     vc_loop                 ; no llega

; ---- ABORT (conchetumare "msg") ----
op_abort_x:
    ; el literal quedo en MEM: imprimir a stderr y morirse
    mov     ebx, [rsi+2]            ; direccion
oab_loop:
    mov     ecx, ebx
    call    chequear_dir
    mov     eax, [rax]
    test    eax, eax
    jz      oab_fin
    mov     ecx, eax
    lea     rdx, buf_utf8
    call    codepoint_a_utf8
    mov     rdx, rax
    lea     rcx, buf_utf8
    call    print_err
    inc     ebx
    jmp     oab_loop
oab_fin:
    lea     rcx, nl
    call    print_err_z
    mov     ecx, EXIT_RUNTIME
    call    ExitProcess
    jmp     vc_loop                 ; no llega

; ---- RANDOM (al lote dst, max) ----
op_random_x:
    push    rsi
    lea     rsi, [rsi+6]
    sub     rsp, 20h
    call    leer_operando           ; max
    add     rsp, 20h
    pop     rsi
    test    eax, eax
    jg      ora_ok
    lea     rcx, r_lote
    call    morir
ora_ok:
    mov     r12d, eax
    call    rng_siguiente
    xor     edx, edx
    div     r12d                    ; edx = rnd % max
    mov     eax, edx
    call    escribir_operando
    add     rdi, 13
    jmp     vc_loop

; ---- SLEEP (esperate un cacho n) ----
op_sleep_x:
    call    leer_operando
    test    eax, eax
    js      osl_listo               ; negativo: nada
    cmp     eax, 60000
    jbe     osl_duerme
    mov     eax, 60000              ; tope 60s
osl_duerme:
    mov     ecx, eax
    call    Sleep
osl_listo:
    add     rdi, 7
    jmp     vc_loop

    ; tabla de dispatch
.data
ALIGN 8
tabla_saltos LABEL QWORD
    dq op_nop_x                     ; 0
    dq op_mov_x                     ; 1
    dq op_push_x                    ; 2
    dq op_pop_x                     ; 3
    dq op_xchg_x                    ; 4
    dq op_add_x                     ; 5
    dq op_sub_x                     ; 6
    dq op_mul_x                     ; 7
    dq op_div_x                     ; 8
    dq op_mod_x                     ; 9
    dq op_inc_x                     ; 10
    dq op_dec_x                     ; 11
    dq op_neg_x                     ; 12
    dq op_and_x                     ; 13
    dq op_or_x                      ; 14
    dq op_xor_x                     ; 15
    dq op_not_x                     ; 16
    dq op_shl_x                     ; 17
    dq op_sar_x                     ; 18
    dq op_shr_x                     ; 19
    dq op_cmp_x                     ; 20
    dq op_jmp_x                     ; 21
    dq op_je_x                      ; 22
    dq op_jne_x                     ; 23
    dq op_jg_x                      ; 24
    dq op_jl_x                      ; 25
    dq op_jge_x                     ; 26
    dq op_jle_x                     ; 27
    dq op_call_x                    ; 28
    dq op_ret_x                     ; 29
    dq op_enter_x                   ; 30
    dq op_leave_x                   ; 31
    dq op_println_x                 ; 32
    dq op_print_x                   ; 33
    dq op_puts_x                    ; 34
    dq op_putchar_x                 ; 35
    dq op_readint_x                 ; 36
    dq op_getchar_x                 ; 37
    dq op_dump_x                    ; 38
    dq op_halt_x                    ; 39
    dq op_abort_x                   ; 40
    dq op_random_x                  ; 41
    dq op_sleep_x                   ; 42
.code

vm_correr ENDP

END
