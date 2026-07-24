; ============================================================
; runtime.asm - lo que llaman los .exe compilados por Wea
; NO se enlaza dentro de wea.exe: acompana al codigo generado.
; Todas las rt_* realinean la pila (el codigo generado no arma
; marcos, asi que no se confia en la alineacion de entrada).
; OJO: el codigo generado guarda los registros de Wea en
; rbx/rbp/rsi/rdi/r12-r15 -> toda rt_* que los use DEBE
; preservarlos, y los pop van en orden inverso a los push.
; ============================================================

include winapi.inc
include isa.inc

PUBLIC rt_init              ; rcx=ptr datos, edx=celdas -> deja wea_mem listo
PUBLIC rt_print_int         ; ecx=valor
PUBLIC rt_print_int_nl      ; ecx=valor
PUBLIC rt_chamulla          ; ecx=direccion, edx=linea
PUBLIC rt_putchar           ; ecx=codepoint
PUBLIC rt_pesca             ; ecx=linea -> eax
PUBLIC rt_getchar           ; -> eax (-1 EOF)
PUBLIC rt_random            ; ecx=max, edx=linea -> eax
PUBLIC rt_sleep             ; ecx=ms
PUBLIC rt_desnudate         ; rcx=ptr a 11 dwords
PUBLIC rt_abort             ; ecx=direccion del mensaje
PUBLIC rt_halt
PUBLIC rt_err_div           ; ecx=linea (no vuelven)
PUBLIC rt_err_mem
PUBLIC rt_err_pila_over
PUBLIC rt_err_pila_under
PUBLIC rt_err_salto
PUBLIC rt_err_sin_halt
PUBLIC wea_mem              ; qword: base de las 65536 celdas
PUBLIC wea_hoyo             ; dd
PUBLIC wea_ojete            ; dd
PUBLIC wea_sapeo            ; dd
PUBLIC wea_dump             ; 11 dd

EXTERN util_init: PROC
EXTERN pedir_memoria: PROC
EXTERN print_out: PROC
EXTERN print_err: PROC
EXTERN print_out_z: PROC
EXTERN print_err_z: PROC
EXTERN print_int_out: PROC
EXTERN print_int_err: PROC
EXTERN leer_linea_stdin: PROC
EXTERN atoi_wea: PROC
EXTERN codepoint_a_utf8: PROC
EXTERN error_runtime: PROC
EXTERN r_div_cero:BYTE, r_mem:BYTE, r_pila_over:BYTE, r_pila_under:BYTE
EXTERN r_salto:BYTE, r_eof:BYTE, r_num_malo:BYTE, r_lote:BYTE
EXTERN r_sin_halt:BYTE

.data
wea_mem     dq 0
wea_hoyo    dd 0
wea_ojete   dd 0
wea_sapeo   dd 0
wea_dump    dd 11 dup (0)
rng_estado  dd 0
ft_buf      dq 0
nl          db 10, 0
desnudo_pre db "[desnudate] ", 0
eq_txt      db "=", 0
sep_reg     db "  ", 0
nombres_regs db "wn", 0, 0, 0, 0, 0, 0
             db "ql", 0, 0, 0, 0, 0, 0
             db "pico", 0, 0, 0, 0
             db "tetas", 0, 0, 0
             db "pichula", 0
             db "poto", 0, 0, 0, 0
             db "chucha", 0, 0
             db "raja", 0, 0, 0, 0
             db "hoyo", 0, 0, 0, 0
             db "ojete", 0, 0, 0
             db "sapeo", 0, 0, 0

.data?
buf_in      db 256 dup (?)
buf_utf8    db 8 dup (?)

.code

; ------------------------------------------------------------
; rt_init: rcx=datos, edx=celdas
; ------------------------------------------------------------
rt_init PROC
    push    rbx
    push    rsi
    push    rdi
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 20h
    mov     rsi, rcx                ; datos
    mov     edi, edx                ; celdas
    call    util_init
    mov     rcx, MEM_PALABRAS * TAM_CELDA
    call    pedir_memoria
    mov     wea_mem, rax
    mov     rbx, rax
    xor     ecx, ecx
ri_copia:
    cmp     ecx, edi
    jae     ri_semilla
    mov     eax, [rsi+rcx*4]
    mov     [rbx+rcx*4], eax
    inc     ecx
    jmp     ri_copia
ri_semilla:
    lea     rcx, ft_buf
    call    GetSystemTimeAsFileTime
    mov     eax, dword ptr ft_buf
    or      eax, 1
    mov     rng_estado, eax
    mov     rsp, rbp
    pop     rbp
    pop     rdi
    pop     rsi
    pop     rbx
    ret
rt_init ENDP

; ------------------------------------------------------------
rt_print_int PROC
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 20h
    call    print_int_out
    mov     rsp, rbp
    pop     rbp
    ret
rt_print_int ENDP

rt_print_int_nl PROC
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 20h
    call    print_int_out
    lea     rcx, nl
    call    print_out_z
    mov     rsp, rbp
    pop     rbp
    ret
rt_print_int_nl ENDP

; ------------------------------------------------------------
; rt_chamulla: ecx=direccion, edx=linea
; ------------------------------------------------------------
rt_chamulla PROC
    push    rbx
    push    rsi
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 20h
    mov     ebx, ecx
    mov     esi, edx                ; linea (por si revienta)
rc_loop:
    cmp     ebx, MEM_PALABRAS
    jae     rc_mala
    mov     rax, wea_mem
    mov     edx, ebx
    mov     eax, [rax+rdx*4]
    test    eax, eax
    jz      rc_fin
    mov     ecx, eax
    lea     rdx, buf_utf8
    call    codepoint_a_utf8
    mov     rdx, rax
    lea     rcx, buf_utf8
    call    print_out
    inc     ebx
    jmp     rc_loop
rc_mala:
    lea     rcx, r_mem
    mov     edx, esi
    xor     r8, r8
    call    error_runtime           ; no vuelve
rc_fin:
    mov     rsp, rbp
    pop     rbp
    pop     rsi
    pop     rbx
    ret
rt_chamulla ENDP

; ------------------------------------------------------------
rt_putchar PROC
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 20h
    lea     rdx, buf_utf8
    call    codepoint_a_utf8
    mov     rdx, rax
    lea     rcx, buf_utf8
    call    print_out
    mov     rsp, rbp
    pop     rbp
    ret
rt_putchar ENDP

; ------------------------------------------------------------
; rt_pesca: ecx=linea -> eax
; ------------------------------------------------------------
rt_pesca PROC
    push    rbx
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 20h
    mov     ebx, ecx                ; linea
    lea     rcx, buf_in
    mov     edx, 255
    call    leer_linea_stdin
    cmp     rax, -1
    jne     rp_hay
    lea     rcx, r_eof
    mov     edx, ebx
    xor     r8, r8
    call    error_runtime
rp_hay:
    mov     rdx, rax
    lea     rcx, buf_in
    call    atoi_wea
    test    r8, r8
    jnz     rp_ok
    lea     rcx, r_num_malo
    mov     edx, ebx
    xor     r8, r8
    call    error_runtime
rp_ok:
    mov     rsp, rbp
    pop     rbp
    pop     rbx
    ret
rt_pesca ENDP

; ------------------------------------------------------------
rt_getchar PROC
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 20h
    lea     rcx, buf_in
    mov     edx, 1
    call    leer_linea_stdin
    cmp     rax, -1
    jne     rg_hay
    mov     eax, -1
    jmp     rg_fin
rg_hay:
    test    rax, rax
    jnz     rg_char
    mov     eax, 10
    jmp     rg_fin
rg_char:
    movzx   eax, byte ptr buf_in
rg_fin:
    mov     rsp, rbp
    pop     rbp
    ret
rt_getchar ENDP

; ------------------------------------------------------------
; rt_random: ecx=max, edx=linea -> eax en [0, max)
; ------------------------------------------------------------
rt_random PROC
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 20h
    test    ecx, ecx
    jg      rr_ok
    mov     r9d, edx
    lea     rcx, r_lote
    mov     edx, r9d
    xor     r8, r8
    call    error_runtime
rr_ok:
    mov     r8d, ecx
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
    xor     edx, edx
    div     r8d
    mov     eax, edx
    mov     rsp, rbp
    pop     rbp
    ret
rt_random ENDP

; ------------------------------------------------------------
rt_sleep PROC
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 20h
    test    ecx, ecx
    js      rs_fin
    cmp     ecx, 60000
    jbe     rs_duerme
    mov     ecx, 60000
rs_duerme:
    call    Sleep
rs_fin:
    mov     rsp, rbp
    pop     rbp
    ret
rt_sleep ENDP

; ------------------------------------------------------------
; rt_desnudate: rcx = ptr a 11 dwords (wn..sapeo)
; ------------------------------------------------------------
rt_desnudate PROC
    push    rbx
    push    rsi
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 20h
    mov     rsi, rcx
    lea     rcx, desnudo_pre
    call    print_err_z
    xor     ebx, ebx
rd_loop:
    cmp     ebx, 11
    jae     rd_fin
    mov     eax, ebx
    shl     eax, 3
    lea     rcx, nombres_regs
    add     rcx, rax
    call    print_err_z
    lea     rcx, eq_txt
    call    print_err_z
    mov     ecx, [rsi+rbx*4]
    call    print_int_err
    lea     rcx, sep_reg
    call    print_err_z
    inc     ebx
    jmp     rd_loop
rd_fin:
    lea     rcx, nl
    call    print_err_z
    mov     rsp, rbp
    pop     rbp
    pop     rsi
    pop     rbx
    ret
rt_desnudate ENDP

; ------------------------------------------------------------
; rt_abort: ecx = direccion del mensaje -> stderr, exit 1
; ------------------------------------------------------------
rt_abort PROC
    ; no vuelve: da lo mismo que quede la pila
    and     rsp, -16
    sub     rsp, 20h
    mov     ebx, ecx
ra_loop:
    cmp     ebx, MEM_PALABRAS
    jae     ra_fin
    mov     rax, wea_mem
    mov     edx, ebx
    mov     eax, [rax+rdx*4]
    test    eax, eax
    jz      ra_fin
    mov     ecx, eax
    lea     rdx, buf_utf8
    call    codepoint_a_utf8
    mov     rdx, rax
    lea     rcx, buf_utf8
    call    print_err
    inc     ebx
    jmp     ra_loop
ra_fin:
    lea     rcx, nl
    call    print_err_z
    mov     ecx, EXIT_RUNTIME
    call    ExitProcess
    ret
rt_abort ENDP

rt_halt PROC
    and     rsp, -16
    sub     rsp, 20h
    xor     ecx, ecx
    call    ExitProcess
    ret
rt_halt ENDP

; ------------------------------------------------------------
; errores (no vuelven). ecx = linea
; error_runtime realinea solo, asi que el tail-jump es seguro.
; ------------------------------------------------------------
rt_err_div PROC
    mov     edx, ecx
    lea     rcx, r_div_cero
    xor     r8, r8
    jmp     error_runtime
rt_err_div ENDP

rt_err_mem PROC
    mov     edx, ecx
    lea     rcx, r_mem
    xor     r8, r8
    jmp     error_runtime
rt_err_mem ENDP

rt_err_pila_over PROC
    mov     edx, ecx
    lea     rcx, r_pila_over
    xor     r8, r8
    jmp     error_runtime
rt_err_pila_over ENDP

rt_err_pila_under PROC
    mov     edx, ecx
    lea     rcx, r_pila_under
    xor     r8, r8
    jmp     error_runtime
rt_err_pila_under ENDP

rt_err_salto PROC
    mov     edx, ecx
    lea     rcx, r_salto
    xor     r8, r8
    jmp     error_runtime
rt_err_salto ENDP

rt_err_sin_halt PROC
    xor     edx, edx
    lea     rcx, r_sin_halt
    xor     r8, r8
    jmp     error_runtime
rt_err_sin_halt ENDP

END
