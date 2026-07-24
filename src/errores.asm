; ============================================================
; errores.asm - catalogo de mensajes flaites + salida con estilo
; Formato: [wea] MENSAJE -> 'extra' (linea N)
; ============================================================

include winapi.inc

PUBLIC error_asm            ; rcx=msg, edx=linea (0=sin linea), r8=extra asciiz (0=nada)
PUBLIC error_runtime        ; idem, exit 1
PUBLIC aviso                ; rcx=msg -> stderr, sigue

; --- errores de ensamblado ---
PUBLIC e_no_cacho, e_registro_malo, e_aridad, e_etiqueta_fantasma
PUBLIC e_etiqueta_dupe, e_sin_pega, e_operando_malo, e_slot_escritura
PUBLIC e_slot_salto, e_seccion, e_string_malo, e_archivo, e_directiva_mala
PUBLIC e_fuente_grande, e_muchos_simbolos, e_datos_llenos, e_mucho_codigo
PUBLIC e_sapeo, e_entry, e_uso

; --- errores de runtime ---
PUBLIC r_div_cero, r_mem, r_pila_over, r_pila_under, r_salto
PUBLIC r_sin_halt, r_eof, r_num_malo, r_lote, r_limite

EXTERN print_err: PROC
EXTERN print_err_z: PROC
EXTERN print_int_err: PROC
EXTERN str_largo: PROC
EXTERN ExitProcess: PROC

.data
pre         db "[wea] ", 0
flecha      db " -> '", 0
comilla     db "'", 0
lin_abre    db " (linea ", 0
lin_cierra  db ")", 0
salto_nl    db 10, 0

; ------------------------------------------------------------
; ensamblado (exit 2)
; ------------------------------------------------------------
e_no_cacho          db "Conchetumare weon, escribiste una wea que no cacho", 0
e_registro_malo     db "Ese registro no existe po. Los que hay: wn ql pico tetas pichula poto chucha raja hoyo ojete", 0
e_aridad            db "Te fuiste en la vola conchetumare: esa instruccion no lleva esa cantidad de operandos", 0
e_etiqueta_fantasma db "La cagaste aweonao, esa etiqueta no existe en ninguna parte", 0
e_etiqueta_dupe     db "Oye ql, esa etiqueta ya la habiai puesto antes", 0
e_sin_pega          db "Y el codigo onde esta? No hay ninguna seccion .la pega. Puro weveo este archivo", 0
e_operando_malo     db "Esa wea no es un operando valido po", 0
e_slot_escritura    db "No podi escribirle a esa wea, aweonao", 0
e_slot_salto        db "No podi saltar pa alla po ql, eso no es codigo", 0
e_seccion           db "Esa wea va en la otra seccion, te confundiste conchetumare", 0
e_string_malo       db "Te falto cerrar las comillas, aweonao", 0
e_archivo           db "No existe esa wea de archivo", 0
e_directiva_mala    db "Esa directiva no existe po, que estai inventando", 0
e_fuente_grande     db "Mucho texto ql, el fuente no puede pasar de 1 MB", 0
e_muchos_simbolos   db "Te pasaste de etiquetas weon, maximo 1024", 0
e_datos_llenos      db "Llenaste toa la memoria de datos, conchetumare", 0
e_mucho_codigo      db "Mucho codigo po weon, maximo 4096 instrucciones", 0
e_sapeo             db "Al sapeo no se le escribe, solo se mira po ql", 0
e_entry             db "El punto de entrada que pusiste no existe, aweonao", 0
e_uso               db "Uso: wea corre archivo.wea  (o: wea revisa archivo.wea)", 0

; ------------------------------------------------------------
; runtime (exit 1)
; ------------------------------------------------------------
r_div_cero          db "CONCHETUMARE! Dividiste por cero. Aweonao.", 0
r_mem               db "Te fuiste al pico de la memoria: esa direccion no existe", 0
r_pila_over         db "Se te fue la pila a la chucha, ql. Recursion infinita o soi weon noma?", 0
r_pila_under        db "Vomitaste con el hoyo vacio, weon", 0
r_salto             db "Saltaste al pico: esa ni siquiera es una instruccion", 0
r_sin_halt          db "Se acabo el codigo y nunca pusiste 'ya wn para'. Aweonao.", 0
r_eof               db "Se acabo la wea que leer (EOF), ctm", 0
r_num_malo          db "Eso no es un numerito po, weon", 0
r_lote              db "'al lote' necesita un maximo mayor que cero po", 0
r_limite            db "Se colgo la wea culiada: demasiados pasos", 0

.code

; ------------------------------------------------------------
; interna: imprime el mensaje armado. r12d=exit code
; rcx=msg, edx=linea, r8=extra
; ------------------------------------------------------------
imprimir_y_salir PROC PRIVATE
    ; no vuelve nunca: realinear sin guardar nada, venga de donde venga
    and     rsp, -16
    sub     rsp, 20h
    mov     rbx, rcx                ; msg
    mov     esi, edx                ; linea
    mov     rdi, r8                 ; extra

    lea     rcx, pre
    call    print_err_z
    mov     rcx, rbx
    call    print_err_z

    test    rdi, rdi
    jz      iys_sin_extra
    lea     rcx, flecha
    call    print_err_z
    mov     rcx, rdi
    call    print_err_z
    lea     rcx, comilla
    call    print_err_z
iys_sin_extra:
    test    esi, esi
    jz      iys_sin_linea
    lea     rcx, lin_abre
    call    print_err_z
    mov     ecx, esi
    call    print_int_err
    lea     rcx, lin_cierra
    call    print_err_z
iys_sin_linea:
    lea     rcx, salto_nl
    call    print_err_z

    mov     ecx, r12d
    call    ExitProcess
    ; no vuelve
    ret
imprimir_y_salir ENDP

error_asm PROC
    mov     r12d, EXIT_ENSAMBLADO
    jmp     imprimir_y_salir
error_asm ENDP

error_runtime PROC
    mov     r12d, EXIT_RUNTIME
    jmp     imprimir_y_salir
error_runtime ENDP

; aviso: rcx=msg -> "[wea] msg\n" a stderr y sigue
aviso PROC
    push    rbx
    sub     rsp, 20h
    mov     rbx, rcx
    lea     rcx, pre
    call    print_err_z
    mov     rcx, rbx
    call    print_err_z
    lea     rcx, salto_nl
    call    print_err_z
    add     rsp, 20h
    pop     rbx
    ret
aviso ENDP

END
