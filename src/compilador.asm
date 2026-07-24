; ============================================================
; compilador.asm - AOT: bytecode de Wea -> texto MASM x64
;
; Mapeo de registros del codigo generado:
;   wn=ebx  ql=ebp  pico=esi  tetas=edi
;   pichula=r12d  poto=r13d  chucha=r14d  raja=r15d
;   hoyo/ojete/sapeo -> globals del runtime
;   scratch: eax (valor dst), ecx (valor src), edx+r10 (direcciones)
;
; sapeo se materializa a memoria tras cada op ALU/CMP; los saltos
; leen [wea_sapeo]. Los saltos dinamicos (registro, toma) van por
; tabla_pc + salto_dinamico.
; ============================================================

include winapi.inc
include isa.inc

PUBLIC compilar_a_asm       ; rcx=ruta de salida -> escribe el .gen.asm

EXTERN pedir_memoria: PROC
EXTERN escribir_archivo: PROC
EXTERN itoa32: PROC
EXTERN str_largo: PROC
EXTERN error_asm: PROC
EXTERN e_mucho_codigo: BYTE
EXTERN e_archivo: BYTE

EXTERN asm_codigo: BYTE
EXTERN asm_codigo_len: DWORD
EXTERN asm_entry: DWORD
EXTERN asm_linea_por_byte: DWORD
EXTERN asm_inicio_instr: BYTE
EXTERN asm_datos_fin: DWORD
EXTERN vm_mem: QWORD

MAX_GEN     equ 400000h             ; 4 MiB de texto generado

.data
gen_base    dq 0
gen_cur     dq 0
gen_linea   dd 0                    ; linea fuente de la instruccion en curso
etq_n       dd 0                    ; contador de etiquetas F<n>

; aridad por opcode (mismo orden que isa.inc)
aridades    db 0,2,1,1,2            ; nop mov push pop xchg
            db 2,2,2,2,2            ; add sub mul div mod
            db 1,1,1                ; inc dec neg
            db 2,2,2,1,2,2,2        ; and or xor not shl sar shr
            db 2                    ; cmp
            db 1,1,1,1,1,1,1        ; jmp je jne jg jl jge jle
            db 1,0,1,0              ; call ret enter leave
            db 1,1,1,1,1,1,0        ; println print puts putchar readint getchar dump
            db 0,1,2,1              ; halt abort random sleep

; mnemonico x64 de las ALU de 2 operandos (indexado por opcode)
; solo validas las entradas de add..shr
txt_add     db "add", 0
txt_sub     db "sub", 0
txt_imul    db "imul", 0
txt_and     db "and", 0
txt_or      db "or", 0
txt_xor     db "xor", 0
txt_shl     db "shl", 0
txt_sar     db "sar", 0
txt_shr     db "shr", 0
txt_inc     db "inc", 0
txt_dec     db "dec", 0
txt_neg     db "neg", 0
txt_not     db "not", 0

; nombres x64 de los registros Wea 0..7 (32 bits)
regs32      db "ebx", 0, 0, 0, 0, 0
            db "ebp", 0, 0, 0, 0, 0
            db "esi", 0, 0, 0, 0, 0
            db "edi", 0, 0, 0, 0, 0
            db "r12d", 0, 0, 0, 0
            db "r13d", 0, 0, 0, 0
            db "r14d", 0, 0, 0, 0
            db "r15d", 0, 0, 0, 0

; nombres de los globals especiales (hoyo=8 ojete=9 sapeo=10)
g_hoyo      db "wea_hoyo", 0
g_ojete     db "wea_ojete", 0
g_sapeo     db "wea_sapeo", 0

; ---- fragmentos de texto ----
nl1         db 10, 0
t_eax       db "eax", 0
t_ecx       db "ecx", 0

t_prologo   db "; generado por wea compila - no toquis esta wea a mano", 10
            db "EXTERN rt_init: PROC", 10
            db "EXTERN rt_print_int: PROC", 10
            db "EXTERN rt_print_int_nl: PROC", 10
            db "EXTERN rt_chamulla: PROC", 10
            db "EXTERN rt_putchar: PROC", 10
            db "EXTERN rt_pesca: PROC", 10
            db "EXTERN rt_getchar: PROC", 10
            db "EXTERN rt_random: PROC", 10
            db "EXTERN rt_sleep: PROC", 10
            db "EXTERN rt_desnudate: PROC", 10
            db "EXTERN rt_abort: PROC", 10
            db "EXTERN rt_halt: PROC", 10
            db "EXTERN rt_err_div: PROC", 10
            db "EXTERN rt_err_mem: PROC", 10
            db "EXTERN rt_err_pila_over: PROC", 10
            db "EXTERN rt_err_pila_under: PROC", 10
            db "EXTERN rt_err_salto: PROC", 10
            db "EXTERN rt_err_sin_halt: PROC", 10
            db "EXTERN wea_mem: QWORD", 10
            db "EXTERN wea_hoyo: DWORD", 10
            db "EXTERN wea_ojete: DWORD", 10
            db "EXTERN wea_sapeo: DWORD", 10
            db "EXTERN wea_dump: DWORD", 10
            db 10
            db "PUBLIC inicio_gen", 10
            db 10
            db ".data", 10
            db "wea_datos LABEL DWORD", 10, 0

t_dd        db "    dd ", 0

t_entry1    db 10, ".code", 10
            db "inicio_gen PROC", 10
            db "    sub rsp, 28h", 10
            db "    lea rcx, wea_datos", 10
            db "    mov edx, ", 0
t_entry2    db 10
            db "    call rt_init", 10
            db "    mov dword ptr [wea_hoyo], 65536", 10
            db "    mov dword ptr [wea_ojete], 65536", 10
            db "    mov dword ptr [wea_sapeo], 0", 10
            db "    xor ebx, ebx", 10
            db "    xor ebp, ebp", 10
            db "    xor esi, esi", 10
            db "    xor edi, edi", 10
            db "    xor r12d, r12d", 10
            db "    xor r13d, r13d", 10
            db "    xor r14d, r14d", 10
            db "    xor r15d, r15d", 10
            db "    jmp L", 0

t_fin_codigo db "    call rt_err_sin_halt", 10, 0

t_saltodin1 db "salto_dinamico:", 10
            db "    cmp eax, ", 0
t_saltodin2 db 10
            db "    jae sd_malo", 10
            db "    lea r10, tabla_pc", 10
            db "    mov r10, [r10+rax*8]", 10
            db "    test r10, r10", 10
            db "    jz sd_malo", 10
            db "    jmp r10", 10
            db "sd_malo:", 10
            db "    mov ecx, 0", 10
            db "    call rt_err_salto", 10, 0

t_tabla1    db ".data", 10
            db "ALIGN 8", 10
            db "tabla_pc LABEL QWORD", 10, 0
t_dq_l      db "    dq L", 0
t_dq_0      db "    dq 0", 0
t_epilogo   db ".code", 10
            db "inicio_gen ENDP", 10
            db "END", 10, 0

; flags / errores
t_flags     db "    test eax, eax", 10
            db "    setz cl", 10
            db "    sets dl", 10
            db "    movzx ecx, cl", 10
            db "    movzx edx, dl", 10
            db "    lea ecx, [ecx+edx*2]", 10
            db "    mov dword ptr [wea_sapeo], ecx", 10, 0

t_cmpflags  db "    cmp eax, ecx", 10
            db "    setz cl", 10
            db "    setl dl", 10
            db "    movzx ecx, cl", 10
            db "    movzx edx, dl", 10
            db "    lea ecx, [ecx+edx*2]", 10
            db "    mov dword ptr [wea_sapeo], ecx", 10, 0

t_mov_pre   db "    mov ", 0
t_coma      db ", ", 0
t_dosp      db ":", 10, 0
t_L         db "L", 0
t_F         db "F", 0

t_mem_ld1   db "    mov r10, [wea_mem]", 10
            db "    mov ", 0
t_mem_ld2   db ", [r10+rdx*4]", 10, 0
t_mem_st1   db "    mov r10, [wea_mem]", 10
            db "    mov [r10+rdx*4], ", 0

t_cmp_edx   db "    cmp edx, 65536", 10
            db "    jb F", 0
t_err_lin   db "    mov ecx, ", 0
t_call      db "    call ", 0
t_jmp       db "    jmp ", 0
t_rt_mem    db "rt_err_mem", 0
t_rt_div    db "rt_err_div", 0
t_rt_over   db "rt_err_pila_over", 0
t_rt_under  db "rt_err_pila_under", 0

t_add_edx   db "    add edx, ", 0
t_gl1       db "    mov ", 0
t_gl2       db ", dword ptr [", 0
t_gl3       db "]", 10, 0
t_st_gl1    db "    mov dword ptr [", 0
t_st_gl2    db "], ", 0

t_push1     db "    mov edx, dword ptr [wea_hoyo]", 10
            db "    dec edx", 10
            db "    cmp edx, 65536", 10
            db "    jae F", 0        ; wrap: hoyo era 0
t_push2     db "    cmp edx, ", 0    ; datos_fin
t_push3     db "    ja F", 0
t_push4     db "    mov dword ptr [wea_hoyo], edx", 10
            db "    mov r10, [wea_mem]", 10
            db "    mov [r10+rdx*4], eax", 10, 0

t_pop1      db "    mov edx, dword ptr [wea_hoyo]", 10
            db "    cmp edx, 65536", 10
            db "    jb F", 0
t_pop2      db "    mov r10, [wea_mem]", 10
            db "    mov eax, [r10+rdx*4]", 10
            db "    inc edx", 10
            db "    mov dword ptr [wea_hoyo], edx", 10, 0

t_test_z    db "    test ecx, ecx", 10
            db "    jnz F", 0
t_intmin1   db "    cmp eax, -2147483648", 10
            db "    jne F", 0
t_intmin2   db "    cmp ecx, -1", 10
            db "    jne F", 0
t_cdq_idiv  db "    cdq", 10
            db "    idiv ecx", 10, 0
t_mov_eax_edx db "    mov eax, edx", 10, 0
t_xor_eax   db "    xor eax, eax", 10, 0
t_and31     db "    and ecx, 31", 10, 0
t_cl        db " eax, cl", 10, 0
t_eax_ecx   db " eax, ecx", 10, 0
t_eax_solo  db " eax", 10, 0

t_sapeo_ld  db "    mov edx, dword ptr [wea_sapeo]", 10
            db "    test edx, ", 0
t_jnz_L     db "    jnz L", 0
t_jz_L      db "    jz L", 0
t_jnz_F     db "    jnz F", 0
t_jz_F      db "    jz F", 0

t_enter1    db "    mov eax, dword ptr [wea_hoyo]", 10
            db "    mov dword ptr [wea_ojete], eax", 10
            db "    sub eax, ", 0
t_enter2    db "    cmp eax, ", 0
t_enter3    db "    ja F", 0
t_enter4    db "    cmp eax, 65536", 10
            db "    jbe F", 0
t_enter5    db "    mov dword ptr [wea_hoyo], eax", 10, 0

t_leave1    db "    mov eax, dword ptr [wea_ojete]", 10
            db "    mov dword ptr [wea_hoyo], eax", 10, 0
t_leave2    db "    mov dword ptr [wea_ojete], eax", 10, 0

t_mov_ecx_eax db "    mov ecx, eax", 10, 0
t_rt_println  db "rt_print_int_nl", 0
t_rt_print    db "rt_print_int", 0
t_rt_chamulla db "rt_chamulla", 0
t_rt_putchar  db "rt_putchar", 0
t_rt_pesca    db "rt_pesca", 0
t_rt_getchar  db "rt_getchar", 0
t_rt_random   db "rt_random", 0
t_rt_sleep    db "rt_sleep", 0
t_rt_halt     db "rt_halt", 0
t_rt_abort    db "rt_abort", 0
t_rt_desnudate db "rt_desnudate", 0
t_salto_din   db "salto_dinamico", 10, 0

t_dump      db "    mov dword ptr [wea_dump+0], ebx", 10
            db "    mov dword ptr [wea_dump+4], ebp", 10
            db "    mov dword ptr [wea_dump+8], esi", 10
            db "    mov dword ptr [wea_dump+12], edi", 10
            db "    mov dword ptr [wea_dump+16], r12d", 10
            db "    mov dword ptr [wea_dump+20], r13d", 10
            db "    mov dword ptr [wea_dump+24], r14d", 10
            db "    mov dword ptr [wea_dump+28], r15d", 10
            db "    mov eax, dword ptr [wea_hoyo]", 10
            db "    mov dword ptr [wea_dump+32], eax", 10
            db "    mov eax, dword ptr [wea_ojete]", 10
            db "    mov dword ptr [wea_dump+36], eax", 10
            db "    mov eax, dword ptr [wea_sapeo]", 10
            db "    mov dword ptr [wea_dump+40], eax", 10
            db "    lea rcx, wea_dump", 10
            db "    call rt_desnudate", 10, 0

t_mov_edx   db "    mov edx, ", 0
t_mov_ecx   db "    mov ecx, ", 0

; mascaras/sentido por salto condicional: (mask, es_jnz)
; JE:1,jnz  JNE:1,jz  JG:3,jz  JL:2,jnz  JGE:2,jz  JLE:3,jnz
mask_jcc    db 1, 1, 3, 2, 2, 3     ; JE JNE JG JL JGE JLE (op-22)
sent_jcc    db 1, 0, 0, 1, 0, 1     ; 1=jnz 0=jz

.data?
buf_num     db 16 dup (?)

.code

; ============================================================
; emision basica
; ============================================================

; e_z: rcx=asciiz -> lo agrega al buffer
e_z PROC
    push    rsi
    push    rdi
    mov     rsi, rcx
    mov     rdi, gen_cur
ez_loop:
    mov     al, [rsi]
    test    al, al
    jz      ez_fin
    mov     [rdi], al
    inc     rsi
    inc     rdi
    jmp     ez_loop
ez_fin:
    mov     gen_cur, rdi
    ; limite
    mov     rax, gen_base
    add     rax, MAX_GEN - 4096
    cmp     rdi, rax
    jb      ez_ok
    sub     rsp, 28h
    lea     rcx, e_mucho_codigo
    xor     edx, edx
    xor     r8, r8
    call    error_asm
ez_ok:
    pop     rdi
    pop     rsi
    ret
e_z ENDP

; e_int: ecx=valor con signo
e_int PROC
    push    rsi
    sub     rsp, 20h
    lea     rdx, buf_num
    call    itoa32
    lea     rsi, buf_num
    mov     byte ptr [rsi+rax], 0
    mov     rcx, rsi
    call    e_z
    add     rsp, 20h
    pop     rsi
    ret
e_int ENDP

; e_nl: salto de linea
e_nl PROC
    sub     rsp, 28h
    lea     rcx, nl1
    call    e_z
    add     rsp, 28h
    ret
e_nl ENDP

; e_reg: ecx=idx 0..7 -> nombre x64 mapeado
e_reg PROC
    sub     rsp, 28h
    mov     eax, ecx
    shl     eax, 3
    lea     rcx, regs32
    add     rcx, rax
    call    e_z
    add     rsp, 28h
    ret
e_reg ENDP

; e_global: ecx=idx 8..10 -> nombre del global
e_global PROC
    sub     rsp, 28h
    cmp     ecx, REG_HOYO
    jne     eg_no_hoyo
    lea     rcx, g_hoyo
    jmp     eg_pone
eg_no_hoyo:
    cmp     ecx, REG_OJETE
    jne     eg_sapeo
    lea     rcx, g_ojete
    jmp     eg_pone
eg_sapeo:
    lea     rcx, g_sapeo
eg_pone:
    call    e_z
    add     rsp, 28h
    ret
e_global ENDP

; e_dest: edx=0 "eax" / 1 "ecx"
e_dest PROC
    sub     rsp, 28h
    test    edx, edx
    jnz     ed_ecx
    lea     rcx, t_eax
    jmp     ed_pone
ed_ecx:
    lea     rcx, t_ecx
ed_pone:
    call    e_z
    add     rsp, 28h
    ret
e_dest ENDP

; nueva_etq -> eax = numero fresco
nueva_etq PROC
    mov     eax, etq_n
    inc     etq_n
    ret
nueva_etq ENDP

; emite "F<n>:" con salto de linea. ecx=n
e_etq_def PROC
    push    rbx
    sub     rsp, 20h
    mov     ebx, ecx
    lea     rcx, t_F
    call    e_z
    mov     ecx, ebx
    call    e_int
    lea     rcx, t_dosp
    call    e_z
    add     rsp, 20h
    pop     rbx
    ret
e_etq_def ENDP

; emite "    mov ecx, <linea>\n    call <rt>\n". rcx=nombre rt
e_morir PROC
    push    rbx
    sub     rsp, 20h
    mov     rbx, rcx
    lea     rcx, t_err_lin
    call    e_z
    mov     ecx, gen_linea
    call    e_int
    call    e_nl
    lea     rcx, t_call
    call    e_z
    mov     rcx, rbx
    call    e_z
    call    e_nl
    add     rsp, 20h
    pop     rbx
    ret
e_morir ENDP

; ============================================================
; em_direccion: rcx=op ptr (MEM o MEMREG) -> emite:
;   mov edx, <base> [+ add edx, disp] + bounds check
; ============================================================
em_direccion PROC
    push    rbx
    push    rsi
    push    r12
    sub     rsp, 20h
    mov     rsi, rcx
    movzx   eax, byte ptr [rsi]     ; modo
    cmp     eax, MODO_MEM
    je      ed_const

    ; MEMREG: base = registro
    lea     rcx, t_mov_edx          ; "    mov edx, "
    call    e_z
    movzx   ecx, byte ptr [rsi+1]
    cmp     ecx, 8
    jae     ed_base_gl
    call    e_reg
    call    e_nl
    jmp     ed_disp
ed_base_gl:
    ; edx <- global: "dword ptr [wea_hoyo]"
    push    rcx                     ; guardar el idx (e_z pisa rcx)
    lea     rcx, t_dptr_abre
    call    e_z
    pop     rcx
    call    e_global
    lea     rcx, t_gl3              ; "]\n"
    call    e_z
    jmp     ed_disp

ed_const:
    lea     rcx, t_mov_edx
    call    e_z
    mov     ecx, [rsi+2]
    call    e_int
    call    e_nl
    jmp     ed_check

ed_disp:
    mov     eax, [rsi+2]            ; desplazamiento
    test    eax, eax
    jz      ed_check
    lea     rcx, t_add_edx
    call    e_z
    mov     ecx, [rsi+2]
    call    e_int
    call    e_nl

ed_check:
    ; cmp edx, 65536 / jb F<n> / morir / F<n>:
    call    nueva_etq
    mov     r12d, eax
    lea     rcx, t_cmp_edx
    call    e_z
    mov     ecx, r12d
    call    e_int
    call    e_nl
    lea     rcx, t_rt_mem
    call    e_morir
    mov     ecx, r12d
    call    e_etq_def
    add     rsp, 20h
    pop     r12
    pop     rsi
    pop     rbx
    ret
em_direccion ENDP

.data
t_dptr_abre db "dword ptr [", 0
.code

; ============================================================
; cargar: rcx=op ptr, edx=0 eax / 1 ecx -> emite la carga
; ============================================================
cargar PROC
    push    rbx
    push    rsi
    push    r12
    sub     rsp, 20h
    mov     rsi, rcx
    mov     r12d, edx               ; destino
    movzx   eax, byte ptr [rsi]
    cmp     eax, MODO_REG
    je      ca_reg
    cmp     eax, MODO_IMM
    je      ca_imm
    ; MEM / MEMREG
    mov     rcx, rsi
    call    em_direccion
    lea     rcx, t_mem_ld1          ; "mov r10,[wea_mem]\n    mov "
    call    e_z
    mov     edx, r12d
    call    e_dest
    lea     rcx, t_mem_ld2          ; ", [r10+rdx*4]\n"
    call    e_z
    jmp     ca_fin
ca_reg:
    movzx   ebx, byte ptr [rsi+1]
    cmp     ebx, 8
    jae     ca_reg_gl
    ; "    mov eax, ebx\n"
    lea     rcx, t_mov_pre
    call    e_z
    mov     edx, r12d
    call    e_dest
    lea     rcx, t_coma
    call    e_z
    mov     ecx, ebx
    call    e_reg
    call    e_nl
    jmp     ca_fin
ca_reg_gl:
    ; "    mov eax, dword ptr [wea_hoyo]\n"
    lea     rcx, t_gl1
    call    e_z
    mov     edx, r12d
    call    e_dest
    lea     rcx, t_gl2
    call    e_z
    mov     ecx, ebx
    call    e_global
    lea     rcx, t_gl3
    call    e_z
    jmp     ca_fin
ca_imm:
    lea     rcx, t_mov_pre
    call    e_z
    mov     edx, r12d
    call    e_dest
    lea     rcx, t_coma
    call    e_z
    mov     ecx, [rsi+2]
    call    e_int
    call    e_nl
ca_fin:
    add     rsp, 20h
    pop     r12
    pop     rsi
    pop     rbx
    ret
cargar ENDP

; ============================================================
; guardar: rcx=op ptr, edx=0 desde eax / 1 desde ecx
; ============================================================
guardar PROC
    push    rbx
    push    rsi
    push    r12
    sub     rsp, 20h
    mov     rsi, rcx
    mov     r12d, edx
    movzx   eax, byte ptr [rsi]
    cmp     eax, MODO_REG
    je      gu_reg
    ; MEM / MEMREG
    mov     rcx, rsi
    call    em_direccion
    lea     rcx, t_mem_st1          ; "mov r10,[wea_mem]\n    mov [r10+rdx*4], "
    call    e_z
    mov     edx, r12d
    call    e_dest
    call    e_nl
    jmp     gu_fin
gu_reg:
    movzx   ebx, byte ptr [rsi+1]
    cmp     ebx, 8
    jae     gu_reg_gl
    ; "    mov ebx, eax\n"
    lea     rcx, t_mov_pre
    call    e_z
    mov     ecx, ebx
    call    e_reg
    lea     rcx, t_coma
    call    e_z
    mov     edx, r12d
    call    e_dest
    call    e_nl
    jmp     gu_fin
gu_reg_gl:
    ; "    mov dword ptr [wea_hoyo], eax\n"
    lea     rcx, t_st_gl1
    call    e_z
    mov     ecx, ebx
    call    e_global
    lea     rcx, t_st_gl2
    call    e_z
    mov     edx, r12d
    call    e_dest
    call    e_nl
gu_fin:
    add     rsp, 20h
    pop     r12
    pop     rsi
    pop     rbx
    ret
guardar ENDP

; ============================================================
; em_push: emite el push de eax a la pila Wea
; ============================================================
em_push PROC
    push    r12
    push    r13
    sub     rsp, 28h
    ; F<a> para el wrap, F<b> para el guardia, comparten destino? no:
    ; jae F_err? mas simple: dos checks que caen al mismo error:
    call    nueva_etq
    mov     r12d, eax               ; etiqueta ok
    ; cmp edx,65536 jae -> error   (wrap)
    lea     rcx, t_push1
    call    e_z
    call    nueva_etq
    mov     r13d, eax               ; etiqueta error
    mov     ecx, r13d
    call    e_int
    call    e_nl
    ; cmp edx, datos_fin ; ja F<ok>
    lea     rcx, t_push2
    call    e_z
    mov     ecx, asm_datos_fin
    call    e_int
    call    e_nl
    lea     rcx, t_push3
    call    e_z
    mov     ecx, r12d
    call    e_int
    call    e_nl
    ; F<err>: morir
    mov     ecx, r13d
    call    e_etq_def
    lea     rcx, t_rt_over
    call    e_morir
    ; F<ok>: escribir
    mov     ecx, r12d
    call    e_etq_def
    lea     rcx, t_push4
    call    e_z
    add     rsp, 28h
    pop     r13
    pop     r12
    ret
em_push ENDP

; ============================================================
; em_pop: emite el pop de la pila Wea -> eax
; ============================================================
em_pop PROC
    push    r12
    sub     rsp, 20h
    call    nueva_etq
    mov     r12d, eax
    lea     rcx, t_pop1
    call    e_z
    mov     ecx, r12d
    call    e_int
    call    e_nl
    lea     rcx, t_rt_under
    call    e_morir
    mov     ecx, r12d
    call    e_etq_def
    lea     rcx, t_pop2
    call    e_z
    add     rsp, 20h
    pop     r12
    ret
em_pop ENDP

; ============================================================
; compilar_a_asm: rcx = ruta de salida
; ============================================================
compilar_a_asm PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 30h
    mov     [rsp+28h], rcx          ; ruta

    mov     rcx, MAX_GEN
    call    pedir_memoria
    test    rax, rax
    jnz     cg_mem_ok
    lea     rcx, e_archivo
    xor     edx, edx
    xor     r8, r8
    call    error_asm
cg_mem_ok:
    mov     gen_base, rax
    mov     gen_cur, rax
    mov     dword ptr etq_n, 0

    ; ---- prologo + datos ----
    lea     rcx, t_prologo
    call    e_z
    mov     r12d, asm_datos_fin
    test    r12d, r12d
    jnz     cg_hay_datos
    ; sin datos: una celda dummy
    lea     rcx, t_dd
    call    e_z
    xor     ecx, ecx
    call    e_int
    call    e_nl
    jmp     cg_datos_listos
cg_hay_datos:
    xor     ebx, ebx
cg_dato:
    cmp     ebx, r12d
    jae     cg_datos_listos
    lea     rcx, t_dd
    call    e_z
    mov     rax, vm_mem
    mov     ecx, [rax+rbx*4]
    call    e_int
    call    e_nl
    inc     ebx
    jmp     cg_dato
cg_datos_listos:

    ; ---- entry ----
    lea     rcx, t_entry1
    call    e_z
    mov     ecx, asm_datos_fin
    call    e_int
    lea     rcx, t_entry2
    call    e_z
    mov     ecx, asm_entry
    call    e_int
    call    e_nl

    ; ---- codigo ----
    xor     ebx, ebx                ; pc
cg_instr:
    cmp     ebx, asm_codigo_len
    jae     cg_codigo_listo
    ; linea fuente
    lea     rax, asm_linea_por_byte
    mov     eax, [rax+rbx*4]
    mov     gen_linea, eax
    ; etiqueta L<pc>:
    lea     rcx, t_L
    call    e_z
    mov     ecx, ebx
    call    e_int
    lea     rcx, t_dosp
    call    e_z
    ; opcode y operandos
    lea     rax, asm_codigo
    movzx   r12d, byte ptr [rax+rbx]    ; opcode
    lea     rsi, [rax+rbx+1]            ; op1
    lea     rdi, [rsi+6]                ; op2
    ; avanzar pc
    lea     rax, aridades
    movzx   eax, byte ptr [rax+r12]
    imul    eax, eax, 6
    inc     eax
    add     ebx, eax
    ; ebx ya es el pc SIGUIENTE (util para call)
    ; dispatch
    lea     rax, gen_tabla
    mov     rax, [rax+r12*8]
    call    rax
    jmp     cg_instr
cg_codigo_listo:

    ; si el codigo se acaba sin halt
    lea     rcx, t_fin_codigo
    call    e_z

    ; ---- salto dinamico + tabla ----
    lea     rcx, t_saltodin1
    call    e_z
    mov     ecx, asm_codigo_len
    call    e_int
    lea     rcx, t_saltodin2
    call    e_z

    lea     rcx, t_tabla1
    call    e_z
    xor     ebx, ebx
cg_tabla:
    cmp     ebx, asm_codigo_len
    jae     cg_tabla_lista
    lea     rax, asm_inicio_instr
    cmp     byte ptr [rax+rbx], 1
    jne     cg_tabla_cero
    lea     rcx, t_dq_l
    call    e_z
    mov     ecx, ebx
    call    e_int
    call    e_nl
    jmp     cg_tabla_sig
cg_tabla_cero:
    lea     rcx, t_dq_0
    call    e_z
    call    e_nl
cg_tabla_sig:
    inc     ebx
    jmp     cg_tabla
cg_tabla_lista:
    lea     rcx, t_epilogo
    call    e_z

    ; ---- escribir el archivo ----
    mov     rcx, [rsp+28h]
    mov     rdx, gen_base
    mov     r8, gen_cur
    sub     r8, gen_base
    call    escribir_archivo
    test    eax, eax
    jnz     cg_fin
    lea     rcx, e_archivo
    xor     edx, edx
    mov     r8, [rsp+28h]
    call    error_asm
cg_fin:
    add     rsp, 30h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
compilar_a_asm ENDP

; ============================================================
; generadores por opcode
; convencion: rsi=op1, rdi=op2, ebx=pc siguiente, r12d=opcode
; todos preservan rbx/rsi/rdi (usan push si los tocan)
; ============================================================

g_nop PROC
    ret
g_nop ENDP

g_mov PROC
    sub     rsp, 28h
    mov     rcx, rdi                ; src
    xor     edx, edx                ; -> eax
    call    cargar
    mov     rcx, rsi
    xor     edx, edx
    call    guardar
    add     rsp, 28h
    ret
g_mov ENDP

g_push PROC
    sub     rsp, 28h
    mov     rcx, rsi
    xor     edx, edx
    call    cargar
    call    em_push
    add     rsp, 28h
    ret
g_push ENDP

g_pop PROC
    sub     rsp, 28h
    call    em_pop
    mov     rcx, rsi
    xor     edx, edx
    call    guardar
    add     rsp, 28h
    ret
g_pop ENDP

g_xchg PROC
    sub     rsp, 28h
    mov     rcx, rsi
    xor     edx, edx                ; a -> eax
    call    cargar
    mov     rcx, rdi
    mov     edx, 1                  ; b -> ecx
    call    cargar
    mov     rcx, rsi
    mov     edx, 1                  ; a = ecx
    call    guardar
    mov     rcx, rdi
    xor     edx, edx                ; b = eax
    call    guardar
    add     rsp, 28h
    ret
g_xchg ENDP

; alu2 comun: rcx = nombre del mnemonico x64
alu2_comun PROC
    push    r13
    sub     rsp, 20h
    mov     r13, rcx
    mov     rcx, rsi
    xor     edx, edx
    call    cargar                  ; dst -> eax
    mov     rcx, rdi
    mov     edx, 1
    call    cargar                  ; src -> ecx
    ; "    " + mn + " eax, ecx\n"
    lea     rcx, t_cuatro
    call    e_z
    mov     rcx, r13
    call    e_z
    lea     rcx, t_eax_ecx
    call    e_z
    lea     rcx, t_flags
    call    e_z
    mov     rcx, rsi
    xor     edx, edx
    call    guardar
    add     rsp, 20h
    pop     r13
    ret
alu2_comun ENDP

.data
t_cuatro    db "    ", 0
.code

g_add PROC
    lea     rcx, txt_add
    jmp     alu2_comun
g_add ENDP
g_sub PROC
    lea     rcx, txt_sub
    jmp     alu2_comun
g_sub ENDP
g_mul PROC
    lea     rcx, txt_imul
    jmp     alu2_comun
g_mul ENDP
g_and PROC
    lea     rcx, txt_and
    jmp     alu2_comun
g_and ENDP
g_or PROC
    lea     rcx, txt_or
    jmp     alu2_comun
g_or ENDP
g_xor PROC
    lea     rcx, txt_xor
    jmp     alu2_comun
g_xor ENDP

; shifts: "    and ecx,31\n    <mn> eax, cl\n"
shift_comun PROC
    push    r13
    sub     rsp, 20h
    mov     r13, rcx
    mov     rcx, rsi
    xor     edx, edx
    call    cargar
    mov     rcx, rdi
    mov     edx, 1
    call    cargar
    lea     rcx, t_and31
    call    e_z
    lea     rcx, t_cuatro
    call    e_z
    mov     rcx, r13
    call    e_z
    lea     rcx, t_cl
    call    e_z
    lea     rcx, t_flags
    call    e_z
    mov     rcx, rsi
    xor     edx, edx
    call    guardar
    add     rsp, 20h
    pop     r13
    ret
shift_comun ENDP

g_shl PROC
    lea     rcx, txt_shl
    jmp     shift_comun
g_shl ENDP
g_sar PROC
    lea     rcx, txt_sar
    jmp     shift_comun
g_sar ENDP
g_shr PROC
    lea     rcx, txt_shr
    jmp     shift_comun
g_shr ENDP

; div/mod: r13d = 0 div / 1 mod
divmod_comun PROC
    push    r13
    push    r14
    push    r15
    sub     rsp, 20h
    mov     r13d, ecx
    mov     rcx, rsi
    xor     edx, edx
    call    cargar                  ; dst -> eax
    mov     rcx, rdi
    mov     edx, 1
    call    cargar                  ; src -> ecx
    ; test ecx,ecx / jnz F<a> / morir div / F<a>:
    call    nueva_etq
    mov     r14d, eax
    lea     rcx, t_test_z
    call    e_z
    mov     ecx, r14d
    call    e_int
    call    e_nl
    lea     rcx, t_rt_div
    call    e_morir
    mov     ecx, r14d
    call    e_etq_def
    ; INT_MIN / -1
    call    nueva_etq
    mov     r14d, eax               ; F<b> = camino idiv
    call    nueva_etq
    mov     r15d, eax               ; F<c> = despues
    lea     rcx, t_intmin1
    call    e_z
    mov     ecx, r14d
    call    e_int
    call    e_nl
    lea     rcx, t_intmin2
    call    e_z
    mov     ecx, r14d
    call    e_int
    call    e_nl
    ; caso especial: div deja eax (INT_MIN); mod deja 0
    test    r13d, r13d
    jz      dm_esp_div
    lea     rcx, t_xor_eax
    call    e_z
dm_esp_div:
    lea     rcx, t_jmp
    call    e_z
    lea     rcx, t_F
    call    e_z
    mov     ecx, r15d
    call    e_int
    call    e_nl
    ; F<b>: idiv
    mov     ecx, r14d
    call    e_etq_def
    lea     rcx, t_cdq_idiv
    call    e_z
    test    r13d, r13d
    jz      dm_sin_resto
    lea     rcx, t_mov_eax_edx
    call    e_z
dm_sin_resto:
    ; F<c>:
    mov     ecx, r15d
    call    e_etq_def
    lea     rcx, t_flags
    call    e_z
    mov     rcx, rsi
    xor     edx, edx
    call    guardar
    add     rsp, 20h
    pop     r15
    pop     r14
    pop     r13
    ret
divmod_comun ENDP

g_div PROC
    xor     ecx, ecx
    jmp     divmod_comun
g_div ENDP
g_mod PROC
    mov     ecx, 1
    jmp     divmod_comun
g_mod ENDP

; alu1: rcx = mnemonico
alu1_comun PROC
    push    r13
    sub     rsp, 20h
    mov     r13, rcx
    mov     rcx, rsi
    xor     edx, edx
    call    cargar
    lea     rcx, t_cuatro
    call    e_z
    mov     rcx, r13
    call    e_z
    lea     rcx, t_eax_solo
    call    e_z
    lea     rcx, t_flags
    call    e_z
    mov     rcx, rsi
    xor     edx, edx
    call    guardar
    add     rsp, 20h
    pop     r13
    ret
alu1_comun ENDP

g_inc PROC
    lea     rcx, txt_inc
    jmp     alu1_comun
g_inc ENDP
g_dec PROC
    lea     rcx, txt_dec
    jmp     alu1_comun
g_dec ENDP
g_neg PROC
    lea     rcx, txt_neg
    jmp     alu1_comun
g_neg ENDP
g_not PROC
    lea     rcx, txt_not
    jmp     alu1_comun
g_not ENDP

g_cmp PROC
    sub     rsp, 28h
    mov     rcx, rsi
    xor     edx, edx
    call    cargar
    mov     rcx, rdi
    mov     edx, 1
    call    cargar
    lea     rcx, t_cmpflags
    call    e_z
    add     rsp, 28h
    ret
g_cmp ENDP

; JMP: directo o dinamico
g_jmp PROC
    sub     rsp, 28h
    cmp     byte ptr [rsi], MODO_REG
    je      gj_reg
    ; "    jmp L<v>\n"
    lea     rcx, t_jmp
    call    e_z
    lea     rcx, t_L
    call    e_z
    mov     ecx, [rsi+2]
    call    e_int
    call    e_nl
    jmp     gj_fin
gj_reg:
    mov     rcx, rsi
    xor     edx, edx
    call    cargar                  ; direccion -> eax
    lea     rcx, t_jmp
    call    e_z
    lea     rcx, t_salto_din
    call    e_z
gj_fin:
    add     rsp, 28h
    ret
g_jmp ENDP

; condicionales: r12d = opcode (22..27)
g_jcc PROC
    push    r13
    push    r14
    sub     rsp, 28h
    lea     rax, mask_jcc
    movzx   r13d, byte ptr [rax+r12-OP_JE]  ; mascara
    lea     rax, sent_jcc
    movzx   r14d, byte ptr [rax+r12-OP_JE]  ; 1=jnz

    cmp     byte ptr [rsi], MODO_REG
    je      gc_reg

    ; "    mov edx,[wea_sapeo]\n    test edx, <m>\n    jnz|jz L<v>\n"
    lea     rcx, t_sapeo_ld
    call    e_z
    mov     ecx, r13d
    call    e_int
    call    e_nl
    test    r14d, r14d
    jz      gc_jz
    lea     rcx, t_jnz_L
    jmp     gc_pone
gc_jz:
    lea     rcx, t_jz_L
gc_pone:
    call    e_z
    mov     ecx, [rsi+2]
    call    e_int
    call    e_nl
    jmp     gc_fin

gc_reg:
    ; invertido: si NO se cumple, saltar F<skip>; si se cumple, dinamico
    call    nueva_etq
    push    rax                     ; OJO: desalinea, pero aca no llamamos API
    mov     r13d, r13d
    lea     rcx, t_sapeo_ld
    call    e_z
    mov     ecx, r13d
    call    e_int
    call    e_nl
    pop     rax
    push    rax
    ; sentido invertido
    test    r14d, r14d
    jz      gc_reg_jnz
    lea     rcx, t_jz_F
    jmp     gc_reg_pone
gc_reg_jnz:
    lea     rcx, t_jnz_F
gc_reg_pone:
    call    e_z
    pop     rax
    push    rax
    mov     ecx, eax
    call    e_int
    call    e_nl
    mov     rcx, rsi
    xor     edx, edx
    call    cargar
    lea     rcx, t_jmp
    call    e_z
    lea     rcx, t_salto_din
    call    e_z
    pop     rax
    mov     ecx, eax
    call    e_etq_def
gc_fin:
    add     rsp, 28h
    pop     r14
    pop     r13
    ret
g_jcc ENDP

g_call PROC
    sub     rsp, 28h
    ; eax = pc de retorno (ebx ya es el siguiente)
    lea     rcx, t_mov_pre
    call    e_z
    lea     rcx, t_eax
    call    e_z
    lea     rcx, t_coma
    call    e_z
    mov     ecx, ebx
    call    e_int
    call    e_nl
    call    em_push
    cmp     byte ptr [rsi], MODO_REG
    je      gca_reg
    lea     rcx, t_jmp
    call    e_z
    lea     rcx, t_L
    call    e_z
    mov     ecx, [rsi+2]
    call    e_int
    call    e_nl
    jmp     gca_fin
gca_reg:
    mov     rcx, rsi
    xor     edx, edx
    call    cargar
    lea     rcx, t_jmp
    call    e_z
    lea     rcx, t_salto_din
    call    e_z
gca_fin:
    add     rsp, 28h
    ret
g_call ENDP

g_ret PROC
    sub     rsp, 28h
    call    em_pop
    lea     rcx, t_jmp
    call    e_z
    lea     rcx, t_salto_din
    call    e_z
    add     rsp, 28h
    ret
g_ret ENDP

g_enter PROC
    push    r13
    push    r14
    sub     rsp, 28h
    ; push del ojete actual
    lea     rcx, t_gl1              ; "    mov "
    call    e_z
    lea     rcx, t_eax
    call    e_z
    lea     rcx, t_gl2              ; ", dword ptr ["
    call    e_z
    mov     ecx, REG_OJETE
    call    e_global
    lea     rcx, t_gl3
    call    e_z
    call    em_push
    ; ojete = hoyo ; hoyo -= n con guardias
    lea     rcx, t_enter1
    call    e_z
    mov     ecx, [rsi+2]            ; n (imm)
    call    e_int
    call    e_nl
    call    nueva_etq
    mov     r13d, eax               ; F<ok bajo>
    lea     rcx, t_enter2
    call    e_z
    mov     ecx, asm_datos_fin
    call    e_int
    call    e_nl
    lea     rcx, t_enter3
    call    e_z
    mov     ecx, r13d
    call    e_int
    call    e_nl
    lea     rcx, t_rt_over
    call    e_morir
    mov     ecx, r13d
    call    e_etq_def
    call    nueva_etq
    mov     r14d, eax               ; F<ok alto>
    lea     rcx, t_enter4
    call    e_z
    mov     ecx, r14d
    call    e_int
    call    e_nl
    lea     rcx, t_rt_over
    call    e_morir
    mov     ecx, r14d
    call    e_etq_def
    lea     rcx, t_enter5
    call    e_z
    add     rsp, 28h
    pop     r14
    pop     r13
    ret
g_enter ENDP

g_leave PROC
    sub     rsp, 28h
    lea     rcx, t_leave1
    call    e_z
    call    em_pop
    lea     rcx, t_leave2
    call    e_z
    add     rsp, 28h
    ret
g_leave ENDP

; io comun con valor: rcx=nombre rt; carga op1->eax, mov ecx,eax, call
io_valor_comun PROC
    push    r13
    sub     rsp, 20h
    mov     r13, rcx
    mov     rcx, rsi
    xor     edx, edx
    call    cargar
    lea     rcx, t_mov_ecx_eax
    call    e_z
    lea     rcx, t_call
    call    e_z
    mov     rcx, r13
    call    e_z
    call    e_nl
    add     rsp, 20h
    pop     r13
    ret
io_valor_comun ENDP

g_println PROC
    lea     rcx, t_rt_println
    jmp     io_valor_comun
g_println ENDP
g_print PROC
    lea     rcx, t_rt_print
    jmp     io_valor_comun
g_print ENDP
g_putchar PROC
    lea     rcx, t_rt_putchar
    jmp     io_valor_comun
g_putchar ENDP
g_sleep PROC
    lea     rcx, t_rt_sleep
    jmp     io_valor_comun
g_sleep ENDP

; chamulla: la DIRECCION del operando va en ecx (semantica del interprete)
g_puts PROC
    sub     rsp, 28h
    movzx   eax, byte ptr [rsi]
    cmp     eax, MODO_REG
    je      gp_reg
    cmp     eax, MODO_MEMREG
    je      gp_memreg
    ; IMM o MEM: la direccion es el valor
    lea     rcx, t_mov_ecx
    call    e_z
    mov     ecx, [rsi+2]
    call    e_int
    call    e_nl
    jmp     gp_llama
gp_reg:
    ; ecx = valor del registro
    lea     rcx, t_mov_ecx
    call    e_z
    movzx   ecx, byte ptr [rsi+1]
    cmp     ecx, 8
    jae     gp_reg_gl
    call    e_reg
    call    e_nl
    jmp     gp_llama
gp_reg_gl:
    lea     rcx, t_dptr_abre
    call    e_z
    movzx   ecx, byte ptr [rsi+1]
    call    e_global
    lea     rcx, t_gl3
    call    e_z
    jmp     gp_llama
gp_memreg:
    ; ecx = reg + disp
    lea     rcx, t_mov_ecx
    call    e_z
    movzx   ecx, byte ptr [rsi+1]
    cmp     ecx, 8
    jae     gp_mr_gl
    call    e_reg
    call    e_nl
    jmp     gp_mr_disp
gp_mr_gl:
    lea     rcx, t_dptr_abre
    call    e_z
    movzx   ecx, byte ptr [rsi+1]
    call    e_global
    lea     rcx, t_gl3
    call    e_z
gp_mr_disp:
    mov     eax, [rsi+2]
    test    eax, eax
    jz      gp_llama
    lea     rcx, t_add_ecx
    call    e_z
    mov     ecx, [rsi+2]
    call    e_int
    call    e_nl
gp_llama:
    lea     rcx, t_mov_edx
    call    e_z
    mov     ecx, gen_linea
    call    e_int
    call    e_nl
    lea     rcx, t_call
    call    e_z
    lea     rcx, t_rt_chamulla
    call    e_z
    call    e_nl
    add     rsp, 28h
    ret
g_puts ENDP

.data
t_add_ecx   db "    add ecx, ", 0
.code

g_readint PROC
    sub     rsp, 28h
    lea     rcx, t_err_lin          ; "    mov ecx, "
    call    e_z
    mov     ecx, gen_linea
    call    e_int
    call    e_nl
    lea     rcx, t_call
    call    e_z
    lea     rcx, t_rt_pesca
    call    e_z
    call    e_nl
    mov     rcx, rsi
    xor     edx, edx
    call    guardar
    add     rsp, 28h
    ret
g_readint ENDP

g_getchar PROC
    sub     rsp, 28h
    lea     rcx, t_call
    call    e_z
    lea     rcx, t_rt_getchar
    call    e_z
    call    e_nl
    mov     rcx, rsi
    xor     edx, edx
    call    guardar
    add     rsp, 28h
    ret
g_getchar ENDP

g_dump PROC
    sub     rsp, 28h
    lea     rcx, t_dump
    call    e_z
    add     rsp, 28h
    ret
g_dump ENDP

g_halt PROC
    sub     rsp, 28h
    lea     rcx, t_call
    call    e_z
    lea     rcx, t_rt_halt
    call    e_z
    call    e_nl
    add     rsp, 28h
    ret
g_halt ENDP

g_abort PROC
    sub     rsp, 28h
    lea     rcx, t_mov_ecx
    call    e_z
    mov     ecx, [rsi+2]
    call    e_int
    call    e_nl
    lea     rcx, t_call
    call    e_z
    lea     rcx, t_rt_abort
    call    e_z
    call    e_nl
    add     rsp, 28h
    ret
g_abort ENDP

g_random PROC
    sub     rsp, 28h
    mov     rcx, rdi                ; max -> eax
    xor     edx, edx
    call    cargar
    lea     rcx, t_mov_ecx_eax
    call    e_z
    lea     rcx, t_mov_edx
    call    e_z
    mov     ecx, gen_linea
    call    e_int
    call    e_nl
    lea     rcx, t_call
    call    e_z
    lea     rcx, t_rt_random
    call    e_z
    call    e_nl
    mov     rcx, rsi
    xor     edx, edx
    call    guardar
    add     rsp, 28h
    ret
g_random ENDP

; tabla de generadores
.data
ALIGN 8
gen_tabla LABEL QWORD
    dq g_nop, g_mov, g_push, g_pop, g_xchg
    dq g_add, g_sub, g_mul, g_div, g_mod
    dq g_inc, g_dec, g_neg
    dq g_and, g_or, g_xor, g_not, g_shl, g_sar, g_shr
    dq g_cmp
    dq g_jmp, g_jcc, g_jcc, g_jcc, g_jcc, g_jcc, g_jcc
    dq g_call, g_ret, g_enter, g_leave
    dq g_println, g_print, g_puts, g_putchar, g_readint, g_getchar, g_dump
    dq g_halt, g_abort, g_random, g_sleep
.code

END
