; ============================================================
; winapi.inc - lo unico que Wea le pide a Windows (kernel32)
; ============================================================

; --- consola ---
EXTERN GetStdHandle: PROC
EXTERN WriteFile: PROC
EXTERN ReadFile: PROC
EXTERN SetConsoleOutputCP: PROC
EXTERN GetConsoleMode: PROC

; --- archivos ---
EXTERN CreateFileA: PROC
EXTERN GetFileSizeEx: PROC
EXTERN CloseHandle: PROC

; --- memoria ---
EXTERN VirtualAlloc: PROC

; --- proceso ---
EXTERN ExitProcess: PROC
EXTERN GetCommandLineA: PROC

; --- misc ---
EXTERN Sleep: PROC
EXTERN GetSystemTimeAsFileTime: PROC

; --- constantes ---
STD_INPUT_HANDLE        equ -10
STD_OUTPUT_HANDLE       equ -11
STD_ERROR_HANDLE        equ -12

GENERIC_READ            equ 80000000h
GENERIC_WRITE           equ 40000000h
FILE_SHARE_READ         equ 1
OPEN_EXISTING           equ 3
CREATE_ALWAYS           equ 2
FILE_ATTRIBUTE_NORMAL   equ 80h
INVALID_HANDLE_VALUE    equ -1

MEM_COMMIT              equ 1000h
MEM_RESERVE             equ 2000h
PAGE_READWRITE          equ 4

CP_UTF8                 equ 65001

; --- limites de Wea (todo pre-asignado, esto es asm po) ---
MAX_FUENTE              equ 100000h     ; 1 MiB de codigo fuente
MAX_SIMBOLOS            equ 1024       ; etiquetas + constantes
MAX_INSTRUCCIONES       equ 4096
MEM_PALABRAS            equ 10000h     ; 65536 celdas int32 de la VM
TAM_CELDA               equ 4

; exit codes
EXIT_OK                 equ 0
EXIT_RUNTIME            equ 1          ; error de ejecucion o conchetumare
EXIT_ENSAMBLADO         equ 2          ; error de compilacion
