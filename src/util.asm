; ============================================================
; util.asm - herramientas basicas: print, itoa/atoi, normalizador
; Convencion interna: Win64 (rcx rdx r8 r9, caller aloca shadow space)
; Toda funcion preserva rbx rsi rdi r12-r15 si los usa.
; ============================================================

include winapi.inc

PUBLIC util_init
PUBLIC print_out            ; rcx=ptr, rdx=largo -> stdout
PUBLIC print_err            ; rcx=ptr, rdx=largo -> stderr
PUBLIC print_out_z          ; rcx=ptr asciiz -> stdout
PUBLIC print_err_z          ; rcx=ptr asciiz -> stderr
PUBLIC print_int_out        ; ecx=int32 con signo -> stdout
PUBLIC print_int_err        ; ecx=int32 con signo -> stderr
PUBLIC str_largo            ; rcx=ptr asciiz -> rax largo
PUBLIC mem_igual            ; rcx=a, rdx=b, r8=n -> rax 1/0
PUBLIC itoa32               ; ecx=valor, rdx=buffer(12+ bytes) -> rax largo
PUBLIC atoi_wea             ; rcx=ptr, rdx=largo -> rax=valor, r8=1 ok / 0 malo
PUBLIC normalizar           ; rcx=src, rdx=largo, r8=dst -> rax largo normalizado
PUBLIC leer_linea_stdin     ; rcx=buffer, rdx=cap -> rax largo (sin \r\n), -1 EOF
PUBLIC codepoint_a_utf8     ; ecx=codepoint, rdx=buffer(4) -> rax largo

EXTERN ExitProcess: PROC

.data
h_stdout    dq 0
h_stderr    dq 0
h_stdin     dq 0
escritos    dq 0
char_in     db 0

.code

; ------------------------------------------------------------
; util_init: agarra los handles y pone la consola en UTF-8
; ------------------------------------------------------------
util_init PROC
    push    rbp
    mov     rbp, rsp
    and     rsp, -16                ; alineacion a prueba de todo
    sub     rsp, 20h
    mov     ecx, STD_OUTPUT_HANDLE
    call    GetStdHandle
    mov     h_stdout, rax
    mov     ecx, STD_ERROR_HANDLE
    call    GetStdHandle
    mov     h_stderr, rax
    mov     ecx, STD_INPUT_HANDLE
    call    GetStdHandle
    mov     h_stdin, rax
    mov     ecx, CP_UTF8
    call    SetConsoleOutputCP
    mov     rsp, rbp
    pop     rbp
    ret
util_init ENDP

; ------------------------------------------------------------
; print_out / print_err: rcx=ptr, rdx=largo
; ------------------------------------------------------------
print_out PROC
    mov     r10, h_stdout
    jmp     escribir_handle
print_out ENDP

print_err PROC
    mov     r10, h_stderr
    jmp     escribir_handle
print_err ENDP

; interna: r10=handle, rcx=ptr, rdx=largo
; realinea la pila: es EL punto de salida a WriteFile de todo el
; programa, asi ningun camino (ni los de error) puede desalinearla
escribir_handle PROC PRIVATE
    test    rdx, rdx
    jz      eh_listo
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 30h                ; shadow + arg5
    mov     r8d, edx                ; bytes
    mov     rdx, rcx                ; buffer
    mov     rcx, r10                ; handle
    lea     r9, escritos
    mov     qword ptr [rsp+20h], 0  ; lpOverlapped
    call    WriteFile
    mov     rsp, rbp
    pop     rbp
eh_listo:
    ret
escribir_handle ENDP

; ------------------------------------------------------------
; print_out_z / print_err_z: rcx=asciiz
; ------------------------------------------------------------
print_out_z PROC
    push    rsi
    sub     rsp, 20h
    mov     rsi, rcx
    call    str_largo
    mov     rdx, rax
    mov     rcx, rsi
    call    print_out
    add     rsp, 20h
    pop     rsi
    ret
print_out_z ENDP

print_err_z PROC
    push    rsi
    sub     rsp, 20h
    mov     rsi, rcx
    call    str_largo
    mov     rdx, rax
    mov     rcx, rsi
    call    print_err
    add     rsp, 20h
    pop     rsi
    ret
print_err_z ENDP

; ------------------------------------------------------------
; str_largo: rcx=asciiz -> rax
; ------------------------------------------------------------
str_largo PROC
    xor     rax, rax
sl_loop:
    cmp     byte ptr [rcx+rax], 0
    je      sl_fin
    inc     rax
    jmp     sl_loop
sl_fin:
    ret
str_largo ENDP

; ------------------------------------------------------------
; mem_igual: rcx=a, rdx=b, r8=n -> rax 1 si iguales
; ------------------------------------------------------------
mem_igual PROC
    test    r8, r8
    jz      mi_si
mi_loop:
    mov     al, [rcx]
    cmp     al, [rdx]
    jne     mi_no
    inc     rcx
    inc     rdx
    dec     r8
    jnz     mi_loop
mi_si:
    mov     eax, 1
    ret
mi_no:
    xor     eax, eax
    ret
mem_igual ENDP

; ------------------------------------------------------------
; itoa32: ecx=valor con signo, rdx=buffer (minimo 12) -> rax largo
; ------------------------------------------------------------
itoa32 PROC
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 16                 ; scratch para digitos al reves
                                    ; (en Windows x64 NO hay red zone)
    mov     rsi, rdx                ; buffer destino
    mov     eax, ecx
    xor     rdi, rdi                ; flag negativo
    test    eax, eax
    jns     ia_pos
    mov     rdi, 1
    neg     eax                     ; ojo: INT_MIN se queda igual, pero
                                    ; como usamos div sin signo igual sale bien
ia_pos:
    mov     r9, rsp                 ; scratch
    xor     rbx, rbx                ; contador digitos
    mov     r10d, 10
ia_digito:
    xor     edx, edx
    div     r10d                    ; eax/10, resto en edx
    add     dl, '0'
    mov     [r9+rbx], dl
    inc     rbx
    test    eax, eax
    jnz     ia_digito
    xor     rax, rax                ; largo final
    test    rdi, rdi
    jz      ia_sin_signo
    mov     byte ptr [rsi], '-'
    inc     rax
ia_sin_signo:
ia_volcar:
    dec     rbx
    mov     dl, [r9+rbx]
    mov     [rsi+rax], dl
    inc     rax
    test    rbx, rbx
    jnz     ia_volcar
    add     rsp, 16
    pop     rdi
    pop     rsi
    pop     rbx
    ret
itoa32 ENDP

; ------------------------------------------------------------
; print_int_out / print_int_err: ecx=int32
; ------------------------------------------------------------
print_int_out PROC
    sub     rsp, 38h                ; 16 buffer + shadow + align
    lea     rdx, [rsp+20h]
    call    itoa32
    mov     rdx, rax
    lea     rcx, [rsp+20h]
    call    print_out
    add     rsp, 38h
    ret
print_int_out ENDP

print_int_err PROC
    sub     rsp, 38h
    lea     rdx, [rsp+20h]
    call    itoa32
    mov     rdx, rax
    lea     rcx, [rsp+20h]
    call    print_err
    add     rsp, 38h
    ret
print_int_err ENDP

; ------------------------------------------------------------
; atoi_wea: rcx=ptr, rdx=largo -> rax valor, r8=1 ok / 0 error
; Acepta: decimal con signo, 0x hex, 0b binario, 'c' caracter
; ------------------------------------------------------------
atoi_wea PROC
    push    rbx
    push    rsi
    push    rdi
    mov     rsi, rcx                ; ptr
    mov     rdi, rdx                ; largo
    xor     rax, rax
    xor     r8, r8                  ; asume error
    test    rdi, rdi
    jz      at_fin
    xor     r11, r11                ; flag negativo
    cmp     byte ptr [rsi], '-'
    jne     at_no_neg
    mov     r11, 1
    inc     rsi
    dec     rdi
    jz      at_fin
at_no_neg:
    ; caracter 'c' (largo 3: comilla, char, comilla)
    cmp     byte ptr [rsi], 27h     ; '
    jne     at_no_char
    cmp     rdi, 3
    jne     at_fin
    cmp     byte ptr [rsi+2], 27h
    jne     at_fin
    movzx   eax, byte ptr [rsi+1]
    jmp     at_signo
at_no_char:
    ; prefijos 0x / 0b
    cmp     rdi, 2
    jbe     at_decimal
    cmp     byte ptr [rsi], '0'
    jne     at_decimal
    mov     bl, [rsi+1]
    or      bl, 20h                 ; a minuscula
    cmp     bl, 'x'
    je      at_hex
    cmp     bl, 'b'
    je      at_bin

at_decimal:
    xor     rax, rax
ad_loop:
    movzx   ebx, byte ptr [rsi]
    sub     bl, '0'
    cmp     bl, 9
    ja      at_fin                  ; digito invalido -> r8 quedo 0
    imul    rax, rax, 10
    movzx   ebx, bl
    add     rax, rbx
    inc     rsi
    dec     rdi
    jnz     ad_loop
    jmp     at_signo

at_hex:
    add     rsi, 2
    sub     rdi, 2
    jz      at_fin
    xor     rax, rax
ah_loop:
    movzx   ebx, byte ptr [rsi]
    or      bl, 20h
    sub     bl, '0'
    cmp     bl, 9
    jbe     ah_ok
    sub     bl, 'a'-'0'
    cmp     bl, 5
    ja      at_fin
    add     bl, 10
ah_ok:
    shl     rax, 4
    movzx   ebx, bl
    or      rax, rbx
    inc     rsi
    dec     rdi
    jnz     ah_loop
    jmp     at_signo

at_bin:
    add     rsi, 2
    sub     rdi, 2
    jz      at_fin
    xor     rax, rax
ab_loop:
    movzx   ebx, byte ptr [rsi]
    sub     bl, '0'
    cmp     bl, 1
    ja      at_fin
    shl     rax, 1
    movzx   ebx, bl
    or      rax, rbx
    inc     rsi
    dec     rdi
    jnz     ab_loop

at_signo:
    test    r11, r11
    jz      at_ok
    neg     eax
at_ok:
    mov     r8, 1
at_fin:
    pop     rdi
    pop     rsi
    pop     rbx
    ret
atoi_wea ENDP

; ------------------------------------------------------------
; normalizar: rcx=src, rdx=largo, r8=dst -> rax largo resultante
; - minusculas ascii
; - tildes UTF-8 (C3 xx) -> letra pelada:  a e i o u n u
; - apostrofe ' (27h) y el tipografico E2 80 99: se eliminan
; - tabs -> espacio; espacios repetidos -> uno solo
; - NO toca lo que hay dentro de comillas dobles
; ------------------------------------------------------------
normalizar PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    mov     rsi, rcx                ; src
    mov     r12, rdx                ; largo restante
    mov     rdi, r8                 ; dst
    xor     rax, rax                ; escrito
    xor     r13, r13                ; flag: dentro de comillas
    xor     r11, r11                ; flag: ultimo fue espacio
no_loop:
    test    r12, r12
    jz      no_fin
    movzx   ebx, byte ptr [rsi]

    ; dentro de comillas se copia tal cual
    test    r13, r13
    jz      no_normal
    mov     [rdi+rax], bl
    inc     rax
    cmp     bl, '"'
    jne     no_avanza1
    xor     r13, r13
no_avanza1:
    inc     rsi
    dec     r12
    jmp     no_loop

no_normal:
    cmp     bl, '#'                 ; comentario: se acaba la linea
    je      no_fin
    cmp     bl, ';'
    je      no_fin
    cmp     bl, '"'
    jne     no_no_comilla
    mov     byte ptr [rdi+rax], '"'
    inc     rax
    mov     r13, 1
    xor     r11, r11
    inc     rsi
    dec     r12
    jmp     no_loop
no_no_comilla:
    ; tab o espacio -> un espacio (colapsado)
    cmp     bl, 9
    je      no_espacio
    cmp     bl, ' '
    je      no_espacio
    cmp     bl, 0Dh                 ; \r fuera
    je      no_saltar1
    cmp     bl, 27h                 ; apostrofe fuera
    je      no_saltar1
    ; secuencia UTF-8 C3 xx (vocales con tilde y enie)
    cmp     bl, 0C3h
    je      no_c3
    ; apostrofe tipografico E2 80 99 fuera
    cmp     bl, 0E2h
    je      no_e2
    ; mayuscula ascii -> minuscula
    cmp     bl, 'A'
    jb      no_copia
    cmp     bl, 'Z'
    ja      no_copia
    or      bl, 20h
no_copia:
    mov     [rdi+rax], bl
    inc     rax
    xor     r11, r11
no_saltar1:
    inc     rsi
    dec     r12
    jmp     no_loop

no_espacio:
    test    r11, r11
    jnz     no_saltar1              ; ya habia espacio
    ; no meter espacio al puro inicio
    test    rax, rax
    jz      no_saltar1
    mov     byte ptr [rdi+rax], ' '
    inc     rax
    mov     r11, 1
    inc     rsi
    dec     r12
    jmp     no_loop

no_c3:
    cmp     r12, 2
    jb      no_copia                ; C3 suelto al final: copiar y ya
    movzx   ebx, byte ptr [rsi+1]
    ; tabla: a1/81->a  a9/89->e  ad/8d->i  b3/93->o  ba/9a->u  b1/91->n  bc/9c->u
    cmp     bl, 0A1h
    je      no_c3_a
    cmp     bl, 081h
    je      no_c3_a
    cmp     bl, 0A9h
    je      no_c3_e
    cmp     bl, 089h
    je      no_c3_e
    cmp     bl, 0ADh
    je      no_c3_i
    cmp     bl, 08Dh
    je      no_c3_i
    cmp     bl, 0B3h
    je      no_c3_o
    cmp     bl, 093h
    je      no_c3_o
    cmp     bl, 0BAh
    je      no_c3_u
    cmp     bl, 09Ah
    je      no_c3_u
    cmp     bl, 0B1h
    je      no_c3_n
    cmp     bl, 091h
    je      no_c3_n
    cmp     bl, 0BCh
    je      no_c3_u
    cmp     bl, 09Ch
    je      no_c3_u
    ; otro C3 xx: copiar los dos bytes tal cual
    mov     byte ptr [rdi+rax], 0C3h
    inc     rax
    mov     [rdi+rax], bl
    inc     rax
    xor     r11, r11
    add     rsi, 2
    sub     r12, 2
    jmp     no_loop
no_c3_a:
    mov     bl, 'a'
    jmp     no_c3_pone
no_c3_e:
    mov     bl, 'e'
    jmp     no_c3_pone
no_c3_i:
    mov     bl, 'i'
    jmp     no_c3_pone
no_c3_o:
    mov     bl, 'o'
    jmp     no_c3_pone
no_c3_u:
    mov     bl, 'u'
    jmp     no_c3_pone
no_c3_n:
    mov     bl, 'n'
no_c3_pone:
    mov     [rdi+rax], bl
    inc     rax
    xor     r11, r11
    add     rsi, 2
    sub     r12, 2
    jmp     no_loop

no_e2:
    cmp     r12, 3
    jb      no_copia
    cmp     byte ptr [rsi+1], 80h
    jne     no_copia
    cmp     byte ptr [rsi+2], 99h
    jne     no_copia
    add     rsi, 3                  ; apostrofe tipografico: fuera
    sub     r12, 3
    jmp     no_loop

no_fin:
    ; espacio final fuera
    test    rax, rax
    jz      no_ret
    cmp     byte ptr [rdi+rax-1], ' '
    jne     no_ret
    dec     rax
no_ret:
    mov     byte ptr [rdi+rax], 0
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
normalizar ENDP

; ------------------------------------------------------------
; leer_linea_stdin: rcx=buffer, rdx=cap -> rax largo, -1 si EOF
; lee byte a byte hasta \n (simple y correcto para consola y pipe)
; ------------------------------------------------------------
leer_linea_stdin PROC
    push    rbx
    push    rsi
    push    rdi
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 30h                ; shadow + arg5
    mov     rsi, rcx                ; buffer
    mov     rdi, rdx                ; cap
    xor     rbx, rbx                ; largo
lls_loop:
    mov     rcx, h_stdin
    lea     rdx, char_in            ; 1 byte
    mov     r8d, 1
    lea     r9, escritos
    mov     qword ptr [rsp+20h], 0
    call    ReadFile
    test    eax, eax
    jz      lls_eof                 ; error de lectura = EOF
    cmp     qword ptr escritos, 0
    je      lls_eof
    movzx   eax, byte ptr char_in
    cmp     al, 0Ah                 ; \n termina
    je      lls_fin
    cmp     al, 0Dh                 ; \r se ignora
    je      lls_loop
    cmp     rbx, rdi
    jae     lls_loop                ; se paso de la cap: descartar
    mov     [rsi+rbx], al
    inc     rbx
    jmp     lls_loop
lls_eof:
    test    rbx, rbx
    jnz     lls_fin                 ; habia algo antes del EOF: entregarlo
    mov     rax, -1
    jmp     lls_ret
lls_fin:
    ; PowerShell mete BOM UTF-8 (EF BB BF) al inicio del pipe: fuera
    cmp     rbx, 3
    jb      lls_sin_bom
    cmp     byte ptr [rsi], 0EFh
    jne     lls_sin_bom
    cmp     byte ptr [rsi+1], 0BBh
    jne     lls_sin_bom
    cmp     byte ptr [rsi+2], 0BFh
    jne     lls_sin_bom
    sub     rbx, 3
    xor     rax, rax
lls_bom_mueve:
    cmp     rax, rbx
    jae     lls_sin_bom
    mov     cl, [rsi+rax+3]
    mov     [rsi+rax], cl
    inc     rax
    jmp     lls_bom_mueve
lls_sin_bom:
    mov     rax, rbx
lls_ret:
    mov     rsp, rbp
    pop     rbp
    pop     rdi
    pop     rsi
    pop     rbx
    ret
leer_linea_stdin ENDP

; ------------------------------------------------------------
; codepoint_a_utf8: ecx=codepoint, rdx=buffer(4 bytes) -> rax largo
; ------------------------------------------------------------
codepoint_a_utf8 PROC
    mov     eax, ecx
    cmp     eax, 80h
    jae     cu_2
    mov     [rdx], al
    mov     eax, 1
    ret
cu_2:
    cmp     eax, 800h
    jae     cu_3
    mov     r8d, eax
    shr     r8d, 6
    or      r8b, 0C0h
    mov     [rdx], r8b
    and     al, 3Fh
    or      al, 80h
    mov     [rdx+1], al
    mov     eax, 2
    ret
cu_3:
    cmp     eax, 10000h
    jae     cu_4
    mov     r8d, eax
    shr     r8d, 12
    or      r8b, 0E0h
    mov     [rdx], r8b
    mov     r8d, eax
    shr     r8d, 6
    and     r8b, 3Fh
    or      r8b, 80h
    mov     [rdx+1], r8b
    and     al, 3Fh
    or      al, 80h
    mov     [rdx+2], al
    mov     eax, 3
    ret
cu_4:
    mov     r8d, eax
    shr     r8d, 18
    and     r8b, 7
    or      r8b, 0F0h
    mov     [rdx], r8b
    mov     r8d, eax
    shr     r8d, 12
    and     r8b, 3Fh
    or      r8b, 80h
    mov     [rdx+1], r8b
    mov     r8d, eax
    shr     r8d, 6
    and     r8b, 3Fh
    or      r8b, 80h
    mov     [rdx+2], r8b
    and     al, 3Fh
    or      al, 80h
    mov     [rdx+3], al
    mov     eax, 4
    ret
codepoint_a_utf8 ENDP

END
