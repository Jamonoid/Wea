; ============================================================
; tablas.asm - LA UNICA FUENTE DE VERDAD del ISA
; Frases ya normalizadas (minusculas, sin tildes, sin apostrofes).
; El lexer escanea TODA la tabla y se queda con el match mas largo,
; asi "sueltate un cacho" le gana a "sueltate un" sin importar el orden.
; ============================================================

include isa.inc

PUBLIC tabla_frases
PUBLIC tabla_registros
PUBLIC nombres_opcodes      ; para desnudate / trazas: 43 punteros

TAM_TEXTO_FRASE equ 24

; entrada: 24 texto + largo + opcode + aridad + k1 + k2 + 3 pad = 32
FRASE MACRO txt, op, ar, ka, kb
    LOCAL ini
ini db txt
    db (TAM_TEXTO_FRASE - (@SizeStr(txt) - 2)) dup (0)
    db (@SizeStr(txt) - 2), op, ar, ka, kb
    db 3 dup (0)
ENDM

.data

tabla_frases LABEL BYTE
    ; --- movimiento ---
    FRASE <"metetelo">,             OP_MOV,     2, K_W,      K_R
    FRASE <"chupate">,              OP_MOV,     2, K_W,      K_R
    FRASE <"dejalo en">,            OP_MOV,     2, K_W,      K_R
    FRASE <"tragate">,              OP_PUSH,    1, K_R,      K_NADA
    FRASE <"vomitate">,             OP_POP,     1, K_W,      K_NADA
    FRASE <"cambiense">,            OP_XCHG,    2, K_W,      K_W
    ; --- aritmetica ---
    FRASE <"echale mas">,           OP_ADD,     2, K_W,      K_R
    FRASE <"sacale">,               OP_SUB,     2, K_W,      K_R
    FRASE <"culialo">,              OP_MUL,     2, K_W,      K_R
    FRASE <"partele el pico">,      OP_DIV,     2, K_W,      K_R
    FRASE <"lo que caga">,          OP_MOD,     2, K_W,      K_R
    FRASE <"se le paro">,           OP_INC,     1, K_W,      K_NADA
    FRASE <"se le bajo">,           OP_DEC,     1, K_W,      K_NADA
    FRASE <"dale vuelta">,          OP_NEG,     1, K_W,      K_NADA
    ; --- logica ---
    FRASE <"las dos weas">,         OP_AND,     2, K_W,      K_R
    FRASE <"cualquier wea">,        OP_OR,      2, K_W,      K_R
    FRASE <"una o la otra">,        OP_XOR,     2, K_W,      K_R
    FRASE <"ni pico">,              OP_NOT,     1, K_W,      K_NADA
    FRASE <"correlo palla">,        OP_SHL,     2, K_W,      K_R
    FRASE <"correlo paca">,         OP_SAR,     2, K_W,      K_R
    FRASE <"correlo paca pelao">,   OP_SHR,     2, K_W,      K_R
    ; --- comparar y saltar ---
    FRASE <"cachai si">,            OP_CMP,     2, K_R,      K_R
    FRASE <"arranca pa">,           OP_JMP,     1, K_SALTO,  K_NADA
    FRASE <"si po">,                OP_JE,      1, K_SALTO,  K_NADA
    FRASE <"nica po">,              OP_JNE,     1, K_SALTO,  K_NADA
    FRASE <"re brigido">,           OP_JG,      1, K_SALTO,  K_NADA
    FRASE <"re penca">,             OP_JL,      1, K_SALTO,  K_NADA
    FRASE <"brigido noma">,         OP_JGE,     1, K_SALTO,  K_NADA
    FRASE <"penca noma">,           OP_JLE,     1, K_SALTO,  K_NADA
    ; --- llamadas ---
    FRASE <"hazme la pega">,        OP_CALL,    1, K_SALTO,  K_NADA
    FRASE <"toma">,                 OP_RET,     0, K_NADA,   K_NADA
    FRASE <"abrete">,               OP_ENTER,   1, K_IMM,    K_NADA
    FRASE <"cierrate">,             OP_LEAVE,   0, K_NADA,   K_NADA
    ; --- entrada / salida ---
    FRASE <"sueltate un">,          OP_PRINTLN, 1, K_R,      K_NADA
    FRASE <"sueltate un cacho">,    OP_PRINT,   1, K_R,      K_NADA
    FRASE <"chamulla">,             OP_PUTS,    1, K_CADENA, K_NADA
    FRASE <"escupe una letra">,     OP_PUTCHAR, 1, K_R,      K_NADA
    FRASE <"pesca">,                OP_READINT, 1, K_W,      K_NADA
    FRASE <"pesca una letra">,      OP_GETCHAR, 1, K_W,      K_NADA
    FRASE <"desnudate">,            OP_DUMP,    0, K_NADA,   K_NADA
    ; --- sistema ---
    FRASE <"ya wn para">,           OP_HALT,    0, K_NADA,   K_NADA
    FRASE <"conchetumare">,         OP_ABORT,   1, K_MSG,    K_NADA
    FRASE <"pajeandome">,           OP_NOP,     0, K_NADA,   K_NADA
    FRASE <"al lote">,              OP_RANDOM,  2, K_W,      K_R
    FRASE <"esperate un cacho">,    OP_SLEEP,   1, K_R,      K_NADA
    ; fin de tabla: entrada con largo 0
    db TF_TAM dup (0)

; ------------------------------------------------------------
; registros: 8 texto asciiz + idx + 7 pad = 16 bytes por entrada
; ------------------------------------------------------------
REGISTRO MACRO txt, idx
    LOCAL ini
ini db txt
    db (8 - (@SizeStr(txt) - 2)) dup (0)
    db idx
    db 7 dup (0)
ENDM

tabla_registros LABEL BYTE
    REGISTRO <"wn">,      REG_WN
    REGISTRO <"ql">,      REG_QL
    REGISTRO <"pico">,    REG_PICO
    REGISTRO <"tetas">,   REG_TETAS
    REGISTRO <"pichula">, REG_PICHULA
    REGISTRO <"poto">,    REG_POTO
    REGISTRO <"chucha">,  REG_CHUCHA
    REGISTRO <"raja">,    REG_RAJA
    REGISTRO <"hoyo">,    REG_HOYO
    REGISTRO <"ojete">,   REG_OJETE
    REGISTRO <"sapeo">,   REG_SAPEO
    db TR_TAM dup (0)

; ------------------------------------------------------------
; nombres cortos de opcode (para desnudate y trazas)
; ------------------------------------------------------------
n_nop       db "pajeandome", 0
n_mov       db "metetelo", 0
n_push      db "tragate", 0
n_pop       db "vomitate", 0
n_xchg      db "cambiense", 0
n_add       db "echale mas", 0
n_sub       db "sacale", 0
n_mul       db "culialo", 0
n_div       db "partele el pico", 0
n_mod       db "lo que caga", 0
n_inc       db "se le paro", 0
n_dec       db "se le bajo", 0
n_neg       db "dale vuelta", 0
n_and       db "las dos weas", 0
n_or        db "cualquier wea", 0
n_xor       db "una o la otra", 0
n_not       db "ni pico", 0
n_shl       db "correlo palla", 0
n_sar       db "correlo paca", 0
n_shr       db "correlo paca pelao", 0
n_cmp       db "cachai si", 0
n_jmp       db "arranca pa", 0
n_je        db "si po", 0
n_jne       db "nica po", 0
n_jg        db "re brigido", 0
n_jl        db "re penca", 0
n_jge       db "brigido noma", 0
n_jle       db "penca noma", 0
n_call      db "hazme la pega", 0
n_ret       db "toma", 0
n_enter     db "abrete", 0
n_leave     db "cierrate", 0
n_println   db "sueltate un", 0
n_print     db "sueltate un cacho", 0
n_puts      db "chamulla", 0
n_putchar   db "escupe una letra", 0
n_readint   db "pesca", 0
n_getchar   db "pesca una letra", 0
n_dump      db "desnudate", 0
n_halt      db "ya wn para", 0
n_abort     db "conchetumare", 0
n_random    db "al lote", 0
n_sleep     db "esperate un cacho", 0

ALIGN 8
nombres_opcodes LABEL QWORD
    dq n_nop, n_mov, n_push, n_pop, n_xchg
    dq n_add, n_sub, n_mul, n_div, n_mod
    dq n_inc, n_dec, n_neg
    dq n_and, n_or, n_xor, n_not, n_shl, n_sar, n_shr
    dq n_cmp, n_jmp, n_je, n_jne, n_jg, n_jl, n_jge, n_jle
    dq n_call, n_ret, n_enter, n_leave
    dq n_println, n_print, n_puts, n_putchar, n_readint, n_getchar, n_dump
    dq n_halt, n_abort, n_random, n_sleep

END
