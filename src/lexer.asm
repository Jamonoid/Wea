; ============================================================
; lexer.asm - reconocimiento de frases y tokens sobre lineas
; ya normalizadas (ver util.asm/normalizar)
; ============================================================

include winapi.inc
include isa.inc

PUBLIC buscar_frase         ; rcx=linea norm asciiz -> rax=entrada tabla (0 si nada),
                            ;                          rdx=ptr al resto (operandos)
PUBLIC buscar_registro      ; rcx=ptr, rdx=largo -> rax=idx registro, -1 si no es
PUBLIC saltar_espacios      ; rcx=ptr -> rax ptr al primer no-espacio
PUBLIC siguiente_token      ; rcx=ptr -> rax=inicio, rdx=largo (corta en espacio,
                            ;            coma, corchete); 0,0 si fin de linea

EXTERN tabla_frases: BYTE
EXTERN tabla_registros: BYTE
EXTERN mem_igual: PROC

.code

; ------------------------------------------------------------
; buscar_frase: match MAS LARGO contra toda la tabla.
; Una frase calza si la linea empieza con ella Y lo que sigue
; es fin de linea o espacio.
; ------------------------------------------------------------
buscar_frase PROC
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 20h
    mov     rsi, rcx                ; linea
    lea     rbx, tabla_frases       ; entrada actual
    xor     r12, r12                ; mejor entrada
    xor     r13, r13                ; mejor largo
bf_loop:
    movzx   eax, byte ptr [rbx+TF_LARGO]
    test    eax, eax
    jz      bf_fin_tabla
    cmp     rax, r13
    jbe     bf_siguiente            ; no supera al mejor: ni comparar
    ; comparar
    mov     rcx, rsi
    mov     rdx, rbx                ; texto al inicio de la entrada
    movzx   r8d, byte ptr [rbx+TF_LARGO]
    call    mem_igual
    test    eax, eax
    jz      bf_siguiente
    ; lo que sigue debe ser 0 o espacio
    movzx   eax, byte ptr [rbx+TF_LARGO]
    movzx   edx, byte ptr [rsi+rax]
    test    edx, edx
    jz      bf_es_mejor
    cmp     dl, ' '
    jne     bf_siguiente
bf_es_mejor:
    mov     r12, rbx
    movzx   r13d, byte ptr [rbx+TF_LARGO]
bf_siguiente:
    add     rbx, TF_TAM
    jmp     bf_loop
bf_fin_tabla:
    mov     rax, r12
    test    r12, r12
    jz      bf_nada
    lea     rdx, [rsi+r13]          ; resto: despues de la frase
    ; saltar el espacio que separa
    cmp     byte ptr [rdx], ' '
    jne     bf_ret
    inc     rdx
    jmp     bf_ret
bf_nada:
    xor     rdx, rdx
bf_ret:
    add     rsp, 20h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
buscar_frase ENDP

; ------------------------------------------------------------
; buscar_registro: rcx=ptr, rdx=largo -> eax idx o -1
; ------------------------------------------------------------
buscar_registro PROC
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 20h
    mov     rsi, rcx
    mov     rdi, rdx
    lea     rbx, tabla_registros
br_loop:
    cmp     byte ptr [rbx], 0
    je      br_no
    ; largo del nombre de la entrada
    xor     rax, rax
br_len:
    cmp     byte ptr [rbx+rax], 0
    je      br_len_ok
    inc     rax
    jmp     br_len
br_len_ok:
    cmp     rax, rdi
    jne     br_next
    mov     rcx, rsi
    mov     rdx, rbx
    mov     r8, rdi
    call    mem_igual
    test    eax, eax
    jz      br_next
    movzx   eax, byte ptr [rbx+TR_IDX]
    jmp     br_ret
br_next:
    add     rbx, TR_TAM
    jmp     br_loop
br_no:
    mov     eax, -1
br_ret:
    add     rsp, 20h
    pop     rdi
    pop     rsi
    pop     rbx
    ret
buscar_registro ENDP

; ------------------------------------------------------------
; saltar_espacios: rcx -> rax primer char != ' '
; ------------------------------------------------------------
saltar_espacios PROC
    mov     rax, rcx
se_loop:
    cmp     byte ptr [rax], ' '
    jne     se_fin
    inc     rax
    jmp     se_loop
se_fin:
    ret
saltar_espacios ENDP

; ------------------------------------------------------------
; siguiente_token: rcx=ptr -> rax inicio, rdx largo
; Token = secuencia sin espacio/coma/corchetes/mas/menos... no:
; corta en: espacio, coma, ']', 0. (los '[' '+' '-' los maneja
; el parser de operandos por su cuenta)
; ------------------------------------------------------------
siguiente_token PROC
    sub     rsp, 28h
    call    saltar_espacios
    add     rsp, 28h
    mov     r8, rax                 ; inicio
    xor     rdx, rdx
st_loop:
    movzx   ecx, byte ptr [r8+rdx]
    test    cl, cl
    jz      st_fin
    cmp     cl, ' '
    je      st_fin
    cmp     cl, ','
    je      st_fin
    cmp     cl, ']'
    je      st_fin
    inc     rdx
    jmp     st_loop
st_fin:
    mov     rax, r8
    test    rdx, rdx
    jnz     st_ret
    xor     rax, rax                ; sin token
st_ret:
    ret
siguiente_token ENDP

END
