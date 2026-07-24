; ============================================================
; archivo.asm - leer el fuente completo a memoria
; ============================================================

include winapi.inc

PUBLIC leer_archivo         ; rcx=ruta asciiz -> rax=ptr (0 si fallo), rdx=largo
PUBLIC pedir_memoria        ; rcx=bytes -> rax=ptr (0 si fallo)

.data
leidos      dq 0

.code

; ------------------------------------------------------------
; pedir_memoria: rcx=bytes -> rax ptr con ceros (o 0)
; ------------------------------------------------------------
pedir_memoria PROC
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 20h
    mov     rdx, rcx                ; dwSize
    xor     ecx, ecx                ; lpAddress = NULL
    mov     r8d, MEM_COMMIT or MEM_RESERVE
    mov     r9d, PAGE_READWRITE
    call    VirtualAlloc
    mov     rsp, rbp
    pop     rbp
    ret
pedir_memoria ENDP

; ------------------------------------------------------------
; leer_archivo: rcx=ruta -> rax=ptr, rdx=largo. rax=0 si no se pudo.
; Deja un 0 al final (asciiz) y se come el BOM UTF-8 si viene.
; ------------------------------------------------------------
leer_archivo PROC
    push    rbx
    push    rsi
    push    rdi
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 50h                ; shadow + args extra + LARGE_INTEGER

    ; CreateFileA(ruta, GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, 0, 0)
    mov     edx, GENERIC_READ
    mov     r8d, FILE_SHARE_READ
    xor     r9d, r9d
    mov     dword ptr [rsp+20h], OPEN_EXISTING
    mov     dword ptr [rsp+28h], FILE_ATTRIBUTE_NORMAL
    mov     qword ptr [rsp+30h], 0
    call    CreateFileA
    cmp     rax, INVALID_HANDLE_VALUE
    je      la_fallo
    mov     rbx, rax                ; handle

    ; GetFileSizeEx(h, &tam)
    mov     rcx, rbx
    lea     rdx, [rsp+40h]
    call    GetFileSizeEx
    test    eax, eax
    jz      la_cerrar_fallo
    mov     rsi, [rsp+40h]          ; tam en bytes
    cmp     rsi, MAX_FUENTE
    ja      la_cerrar_fallo         ; muy grande: el fuente no puede pasar 1 MiB

    ; buffer = tam + 1 (para el 0 final)
    lea     rcx, [rsi+1]
    call    pedir_memoria
    test    rax, rax
    jz      la_cerrar_fallo
    mov     rdi, rax                ; buffer

    ; ReadFile(h, buf, tam, &leidos, 0)
    mov     rcx, rbx
    mov     rdx, rdi
    mov     r8, rsi
    lea     r9, leidos
    mov     qword ptr [rsp+20h], 0
    call    ReadFile
    test    eax, eax
    jz      la_cerrar_fallo

    mov     rcx, rbx
    call    CloseHandle

    mov     rax, rdi
    mov     rdx, leidos
    mov     byte ptr [rax+rdx], 0   ; asciiz

    ; BOM UTF-8: EF BB BF
    cmp     rdx, 3
    jb      la_listo
    cmp     byte ptr [rax], 0EFh
    jne     la_listo
    cmp     byte ptr [rax+1], 0BBh
    jne     la_listo
    cmp     byte ptr [rax+2], 0BFh
    jne     la_listo
    add     rax, 3
    sub     rdx, 3
la_listo:
    mov     rsp, rbp
    pop     rbp
    pop     rdi
    pop     rsi
    pop     rbx
    ret

la_cerrar_fallo:
    mov     rcx, rbx
    call    CloseHandle
la_fallo:
    xor     rax, rax
    xor     rdx, rdx
    mov     rsp, rbp
    pop     rbp
    pop     rdi
    pop     rsi
    pop     rbx
    ret
leer_archivo ENDP

END
