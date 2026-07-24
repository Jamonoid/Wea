@echo off
rem ============================================================
rem  build.bat - compila Wea con MASM x64 (sin CRT, puro kernel32)
rem  Requiere Visual Studio 2022 Community (ml64 + link)
rem ============================================================
setlocal

set VCVARS="C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if not exist %VCVARS% (
    echo ERROR: no encontre vcvars64.bat - instala Visual Studio 2022 con C++
    exit /b 1
)

call %VCVARS% >nul 2>&1

cd /d "%~dp0"
if not exist bin mkdir bin
if not exist obj mkdir obj

set SRC=src\util.asm src\archivo.asm src\tablas.asm src\lexer.asm src\ensamblador.asm src\vm.asm src\errores.asm src\compilador.asm src\wea.asm
set OBJ=obj\util.obj obj\archivo.obj obj\tablas.obj obj\lexer.obj obj\ensamblador.obj obj\vm.obj obj\errores.obj obj\compilador.obj obj\wea.obj

for %%f in (%SRC%) do (
    ml64 /nologo /c /I src /Fo obj\%%~nf.obj %%f
    if errorlevel 1 (
        echo.
        echo ============================================
        echo  LA CAGASTE: no ensambla %%f
        echo ============================================
        exit /b 1
    )
)

rem el runtime NO va dentro de wea.exe: acompana a los .exe compilados
ml64 /nologo /c /I src /Fo obj\runtime.obj src\runtime.asm
if errorlevel 1 (
    echo LA CAGASTE: no ensambla src\runtime.asm
    exit /b 1
)

link /nologo /subsystem:console /entry:inicio /out:bin\wea.exe %OBJ% kernel32.lib
if errorlevel 1 (
    echo.
    echo ============================================
    echo  LA CAGASTE: no enlaza
    echo ============================================
    exit /b 1
)

echo.
echo listo po: bin\wea.exe
endlocal
