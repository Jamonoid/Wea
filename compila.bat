@echo off
rem ============================================================
rem  compila.bat - AOT: archivo.wea -> bin\archivo.exe nativo
rem  uso: compila.bat programa.wea
rem  intermedios (.gen.asm/.gen.obj) quedan en obj\
rem ============================================================
setlocal

if "%~1"=="" (
    echo uso: compila.bat programa.wea
    exit /b 2
)

set VCVARS="C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
call %VCVARS% >nul 2>&1

cd /d "%~dp0"

if not exist bin\wea.exe (
    call build.bat
    if errorlevel 1 exit /b 1
)
if not exist obj mkdir obj

rem 1. wea genera el MASM (queda al lado del fuente) y lo movemos a obj\
bin\wea.exe compila "%~f1"
if errorlevel 1 exit /b %errorlevel%
move /y "%~dpn1.gen.asm" "obj\%~n1.gen.asm" >nul

rem 2. ml64 + link con el runtime -> bin\
ml64 /nologo /c /Fo "obj\%~n1.gen.obj" "obj\%~n1.gen.asm"
if errorlevel 1 (
    echo LA CAGASTE: el MASM generado no ensambla
    exit /b 1
)

link /nologo /subsystem:console /entry:inicio_gen /out:"bin\%~n1.exe" "obj\%~n1.gen.obj" obj\runtime.obj obj\util.obj obj\errores.obj obj\archivo.obj kernel32.lib
if errorlevel 1 (
    echo LA CAGASTE: no enlaza
    exit /b 1
)

echo listo po: bin\%~n1.exe
endlocal
