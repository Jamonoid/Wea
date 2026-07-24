# ============================================================
#  corre_tests.ps1 - la suite de tests de Wea
#  uso:  powershell -File tests\corre_tests.ps1
# ============================================================
$ErrorActionPreference = "Continue"
$raiz = Split-Path -Parent $PSScriptRoot
$exe  = Join-Path $raiz "bin\wea.exe"
$ejemplos = Join-Path $raiz "examples"
$temp = Join-Path $env:TEMP "wea_tests"
if (-not (Test-Path $temp)) { New-Item -ItemType Directory -Force $temp | Out-Null }

if (-not (Test-Path $exe)) {
    Write-Host "primero compila po: .\build.bat" -ForegroundColor Red
    exit 1
}

$total = 0
$buenos = 0

function Reporte($nombre, $ok, $detalle) {
    $script:total++
    if ($ok) {
        $script:buenos++
        Write-Host ("  [OK]    " + $nombre) -ForegroundColor Green
    } else {
        Write-Host ("  [MALO]  " + $nombre + "  " + $detalle) -ForegroundColor Red
    }
}

# ------------------------------------------------------------
# 1. ejemplos contra sus goldens (.salida)
# ------------------------------------------------------------
Write-Host "`n--- ejemplos ---"
Get-ChildItem "$ejemplos\*.wea" | ForEach-Object {
    $wea = $_.FullName
    $nombre = $_.BaseName
    $golden = Join-Path $ejemplos "$nombre.salida"
    if (-not (Test-Path $golden)) { return }

    $stdin_file = Join-Path $ejemplos "$nombre.entrada"
    if (Test-Path $stdin_file) {
        $salida = Get-Content $stdin_file | & $exe corre $wea --semilla=7 2>$null
    } else {
        $salida = & $exe corre $wea 2>$null
    }
    $codigo = $LASTEXITCODE
    $esperado = Get-Content $golden
    $real = @($salida)
    $esp  = @($esperado)
    $igual = ($codigo -eq 0) -and ($real.Count -eq $esp.Count)
    if ($igual) {
        for ($i = 0; $i -lt $real.Count; $i++) {
            if ($real[$i] -cne $esp[$i]) { $igual = $false; break }
        }
    }
    Reporte $nombre $igual "exit=$codigo lineas=$($real.Count)/$($esp.Count)"
}

# ------------------------------------------------------------
# 2. errores: que revienten con el exit code y el garabato correcto
# ------------------------------------------------------------
Write-Host "`n--- errores flaites ---"

function TestError($nombre, $fuente, $exitEsperado, $patron) {
    $f = Join-Path $temp "$nombre.wea"
    Set-Content -Path $f -Value $fuente -Encoding ascii
    $err = & $exe corre $f 2>&1 | Out-String
    $codigo = $LASTEXITCODE
    $ok = ($codigo -eq $exitEsperado) -and ($err -match $patron)
    Reporte $nombre $ok "exit=$codigo (esperaba $exitEsperado)"
}

TestError "mnemonico_malo" @"
.la pega
inicio:
    pescate wn, 3
    ya wn para
"@ 2 "no cacho"

TestError "etiqueta_fantasma" @"
.la pega
inicio:
    arranca pa ninguna_parte
    ya wn para
"@ 2 "no existe en ninguna parte"

TestError "division_cero" @"
.la pega
inicio:
    metetelo wn, 10
    metetelo ql, 0
    partele el pico wn, ql
    ya wn para
"@ 1 "Dividiste por cero"

TestError "recursion_infinita" @"
.la pega
inicio:
    hazme la pega inicio
"@ 1 "pila a la chucha"

TestError "sin_halt" @"
.la pega
inicio:
    metetelo wn, 1
"@ 1 "ya wn para"

TestError "etiqueta_duplicada" @"
.la pega
vuelta:
    metetelo wn, 1
vuelta:
    ya wn para
"@ 2 "ya la habiai puesto"

TestError "escribir_al_sapeo" @"
.la pega
inicio:
    metetelo sapeo, 1
    ya wn para
"@ 2 "solo se mira"

TestError "conchetumare_abort" @"
.la pega
inicio:
    conchetumare "me mori po"
"@ 1 "me mori po"

# ------------------------------------------------------------
# 3. semantica fina: wrap int32, division truncada, INT_MIN
# ------------------------------------------------------------
Write-Host "`n--- semantica ---"

function TestSalida($nombre, $fuente, $esperado) {
    $f = Join-Path $temp "$nombre.wea"
    Set-Content -Path $f -Value $fuente -Encoding ascii
    $salida = (& $exe corre $f 2>$null) -join "`n"
    $ok = ($LASTEXITCODE -eq 0) -and ($salida -ceq $esperado)
    Reporte $nombre $ok "salio '$salida' esperaba '$esperado'"
}

TestSalida "wrap_int32" @"
.la pega
inicio:
    metetelo wn, 2147483647
    se le paro wn
    sueltate un wn
    ya wn para
"@ "-2147483648"

TestSalida "division_truncada" @"
.la pega
inicio:
    metetelo wn, -7
    metetelo ql, 2
    partele el pico wn, ql
    sueltate un wn
    ya wn para
"@ "-3"

TestSalida "resto_con_signo" @"
.la pega
inicio:
    metetelo wn, -7
    metetelo ql, 2
    lo que caga wn, ql
    sueltate un wn
    ya wn para
"@ "-1"

TestSalida "int_min_entre_menos_uno" @"
.la pega
inicio:
    metetelo wn, -2147483648
    metetelo ql, -1
    partele el pico wn, ql
    sueltate un wn
    ya wn para
"@ "-2147483648"

TestSalida "cmp_sin_overflow" @"
.la pega
inicio:
    metetelo wn, -2000000000
    cachai si wn, 2000000000
    re penca es_menor
    chamulla "MALO"
    ya wn para
es_menor:
    chamulla "menor"
    ya wn para
"@ "menor"

TestSalida "constantes_dale_con" @"
dale con VECES = 3
.la pega
inicio:
    metetelo wn, VECES
    sueltate un wn
    ya wn para
"@ "3"

TestSalida "tildes_y_apostrofes" @"
.la pega
inicio:
    mEtEtElO wn, 5
    sE Le PaRo wn
    sueltate un wn
    ya wn para
"@ "6"

TestSalida "pila_basica" @"
.la pega
inicio:
    metetelo wn, 11
    metetelo ql, 22
    tragate wn
    tragate ql
    vomitate pico
    vomitate tetas
    sueltate un cacho pico
    chamulla ","
    sueltate un cacho tetas
    escupe una letra 10
    ya wn para
"@ "22,11"

# ------------------------------------------------------------
Write-Host ""
if ($buenos -eq $total) {
    Write-Host "wena wn: $buenos/$total tests buenos, ta filete la wea" -ForegroundColor Green
    exit 0
} else {
    Write-Host "la cagaste en algo: $buenos/$total buenos" -ForegroundColor Red
    exit 1
}
