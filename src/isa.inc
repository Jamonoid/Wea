; ============================================================
; isa.inc - constantes del ISA de Wea (compartidas por todos)
; ============================================================

; --- opcodes (indice directo a la jump table de la VM) ---
OP_NOP      equ 0       ; pajeandome
OP_MOV      equ 1       ; metetelo / chupate / dejalo en
OP_PUSH     equ 2       ; tragate
OP_POP      equ 3       ; vomitate
OP_XCHG     equ 4       ; cambiense
OP_ADD      equ 5       ; echale mas
OP_SUB      equ 6       ; sacale
OP_MUL      equ 7       ; culialo
OP_DIV      equ 8       ; partele el pico
OP_MOD      equ 9       ; lo que caga
OP_INC      equ 10      ; se le paro
OP_DEC      equ 11      ; se le bajo
OP_NEG      equ 12      ; dale vuelta
OP_AND      equ 13      ; las dos weas
OP_OR       equ 14      ; cualquier wea
OP_XOR      equ 15      ; una o la otra
OP_NOT      equ 16      ; ni pico
OP_SHL      equ 17      ; correlo palla
OP_SAR      equ 18      ; correlo paca
OP_SHR      equ 19      ; correlo paca pelao
OP_CMP      equ 20      ; cachai si
OP_JMP      equ 21      ; arranca pa
OP_JE       equ 22      ; si po
OP_JNE      equ 23      ; nica po
OP_JG       equ 24      ; re brigido
OP_JL       equ 25      ; re penca
OP_JGE      equ 26      ; brigido noma
OP_JLE      equ 27      ; penca noma
OP_CALL     equ 28      ; hazme la pega
OP_RET      equ 29      ; toma
OP_ENTER    equ 30      ; abrete
OP_LEAVE    equ 31      ; cierrate
OP_PRINTLN  equ 32      ; sueltate un
OP_PRINT    equ 33      ; sueltate un cacho
OP_PUTS     equ 34      ; chamulla
OP_PUTCHAR  equ 35      ; escupe una letra
OP_READINT  equ 36      ; pesca
OP_GETCHAR  equ 37      ; pesca una letra
OP_DUMP     equ 38      ; desnudate
OP_HALT     equ 39      ; ya wn para
OP_ABORT    equ 40      ; conchetumare
OP_RANDOM   equ 41      ; al lote
OP_SLEEP    equ 42      ; esperate un cacho
NUM_OPCODES equ 43

; --- modos de operando (van al bytecode) ---
MODO_REG    equ 0
MODO_IMM    equ 1
MODO_MEM    equ 2       ; [direccion constante o etiqueta de datos]
MODO_MEMREG equ 3       ; [reg+desp] / [reg-desp] / [reg]

; --- tipos de slot de operando (validacion del ensamblador) ---
K_NADA      equ 0
K_W         equ 1       ; escribible: REG / MEM / MEMREG
K_R         equ 2       ; legible: cualquiera
K_SALTO     equ 3       ; etiqueta de codigo o REG (salto indirecto)
K_IMM       equ 4       ; solo inmediato (abrete N)
K_CADENA    equ 5       ; "literal" / MEM / MEMREG / REG-puntero (chamulla)
K_MSG       equ 6       ; solo "literal" (conchetumare)

; --- registros ---
REG_WN      equ 0
REG_QL      equ 1
REG_PICO    equ 2
REG_TETAS   equ 3
REG_PICHULA equ 4
REG_POTO    equ 5
REG_CHUCHA  equ 6
REG_RAJA    equ 7
REG_HOYO    equ 8       ; puntero de pila
REG_OJETE   equ 9       ; puntero de marco
REG_SAPEO   equ 10      ; flags, solo lectura
NUM_REGS    equ 11

; --- flags en sapeo ---
FLAG_Z      equ 1       ; resultado cero / iguales
FLAG_S      equ 2       ; resultado negativo / a < b (con signo, sin wrap)

; --- layout de la tabla de frases (tablas.asm) ---
; entrada = 32 bytes: 24 texto asciiz + largo + opcode + aridad + k1 + k2 + 3 pad
TF_TEXTO    equ 0
TF_LARGO    equ 24
TF_OPCODE   equ 25
TF_ARIDAD   equ 26
TF_K1       equ 27
TF_K2       equ 28
TF_TAM      equ 32

; --- layout tabla de registros: 8 texto asciiz + idx + 7 pad = 16 ---
TR_TEXTO    equ 0
TR_IDX      equ 8
TR_TAM      equ 16

; --- simbolos del ensamblador: 32 bytes ---
SIM_NOMBRE  equ 0       ; ptr al arena
SIM_LARGO   equ 8
SIM_KIND    equ 12      ; 0=dato 1=codigo 2=constante
SIM_VALOR   equ 16
SIM_LINEA   equ 20
SIM_TAM     equ 32

SIMK_DATO   equ 0
SIMK_CODIGO equ 1
SIMK_CONST  equ 2
