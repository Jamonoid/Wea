# Wea

**El lenguaje ensamblador chileno.** Escrito en ensamblador de verdad (MASM x64, cero
dependencias, cero runtime de C — puro kernel32), porque hacer un lenguaje de bajo nivel
sobre Python no tiene ninguna gracia.

Wea es el hermano chico y pulento del [lenguaje Wea de alto nivel](correcciones.md): la
misma familia, un piso más abajo. Acá no hay variables ni closures — hay registros con
nombre de garabato, una pila que se te puede ir a la chucha, y saltos condicionales po.

```
# hola.wea
.la pega
inicio:
    chamulla "hola conchetumare, soy Wea"
    escupe una letra 10
    ya wn para
```

```
> wea corre hola.wea
hola conchetumare, soy Wea
```

## Compilar

Necesitas Visual Studio 2022 con las herramientas de C++ (por `ml64` y `link`):

```
.\build.bat
```

Deja `bin\wea.exe`. Correr los tests:

```
powershell -File tests\corre_tests.ps1
```

## Uso

```
wea corre programa.wea [--semilla=N]    ejecuta (interpretado)
wea revisa programa.wea                 solo compila (a ver si ta bueno)
wea compila programa.wea                genera el .gen.asm (MASM x64)
wea programa.wea                        atajo de corre
```

Exit codes: `0` todo filete · `1` reventó corriendo (o `conchetumare`) · `2` no compiló.

### Compilar a .exe nativo

```
.\compila.bat programa.wea      ->  bin\programa.exe
```

Sí: Wea también es un **compilador de verdad**. `wea compila` traduce el bytecode a
ensamblador MASM x64 (los 8 registros garabato quedan mapeados a registros x64 reales:
`wn`→`ebx`, `ql`→`ebp`, `pico`→`esi`, `tetas`→`edi`, `pichula`→`r12d`, `poto`→`r13d`,
`chucha`→`r14d`, `raja`→`r15d`), y `compila.bat` lo pasa por `ml64` + `link` junto al
runtime. Sale un ejecutable standalone de ~8 KB que corre sin la VM. `culialo pico, wn`
termina siendo un `imul` de verdad po.

## Los registros

Once registros de 32 bits con signo. Todos garabatos, como corresponde:

| Registro | # | Qué es |
|---|---|---|
| `wn` | 0 | uso general |
| `ql` | 1 | uso general |
| `pico` | 2 | uso general — por convención, el valor de retorno |
| `tetas` | 3 | uso general |
| `pichula` | 4 | uso general |
| `poto` | 5 | uso general |
| `chucha` | 6 | uso general |
| `raja` | 7 | uso general |
| `hoyo` | 8 | puntero de pila (SP) |
| `ojete` | 9 | puntero de marco (BP) |
| `sapeo` | 10 | flags de `cachai si` — solo lectura, el sapeo no se toca |

## La memoria

65536 celdas de 32 bits, direccionadas **por celda** (no por byte). Los datos de `.la wea`
parten en la celda 0. La pila parte del tope (65536) y crece hacia abajo. Los strings son
un codepoint Unicode por celda, terminados en 0 — así que las tildes y la ñ funcionan po.

Modos de direccionamiento:

| Se escribe | Qué hace |
|---|---|
| `wn` | el registro |
| `42` / `0x2A` / `0b101010` / `'a'` | inmediato |
| `etiqueta` | inmediato = **la dirección** de la etiqueta |
| `[42]` / `[etiqueta]` | la celda en esa dirección |
| `[wn]` / `[wn+2]` / `[ojete-1]` | la celda apuntada por el registro (más desplazamiento) |

## El set de instrucciones

Los mnemónicos no distinguen mayúsculas ni tildes (`métetelo` ≡ `METETELO` ≡ `metetelo`).
Los apóstrofes se ignoran (`pa'llá` ≡ `palla`). Comentarios con `#` o `;`.

### Movimiento

| Wea | Hace |
|---|---|
| `metetelo dst, src` | MOV — dst = src |
| `chupate dst, [dir]` | LOAD (es el mismo MOV, pero se lee mejor) |
| `dejalo en [dir], src` | STORE (ídem) |
| `tragate src` | PUSH |
| `vomitate dst` | POP |
| `cambiense a, b` | XCHG |

### Aritmética (todas dejan el `sapeo` listo)

| Wea | Hace |
|---|---|
| `echale mas dst, src` | ADD |
| `sacale dst, src` | SUB |
| `culialo dst, src` | MUL |
| `partele el pico dst, src` | DIV (truncada, como C; por cero revienta con estilo) |
| `lo que caga dst, src` | MOD |
| `se le paro dst` | INC |
| `se le bajo dst` | DEC |
| `dale vuelta dst` | NEG |

### Lógica

| Wea | Hace |
|---|---|
| `las dos weas dst, src` | AND |
| `cualquier wea dst, src` | OR |
| `una o la otra dst, src` | XOR |
| `ni pico dst` | NOT |
| `correlo palla dst, n` | SHL |
| `correlo paca dst, n` | SAR (aritmético) |
| `correlo paca pelao dst, n` | SHR (lógico) |

### Comparar y saltar

`cachai si a, b` compara (con signo, sin trampas de overflow) y deja el veredicto en
`sapeo`. Después saltas:

| Wea | Salta si |
|---|---|
| `arranca pa L` | siempre (acepta registro: salto indirecto) |
| `si po L` | a == b |
| `nica po L` | a != b |
| `re brigido L` | a > b |
| `re penca L` | a < b |
| `brigido noma L` | a >= b |
| `penca noma L` | a <= b |

### Funciones

| Wea | Hace |
|---|---|
| `hazme la pega L` | CALL — empuja el retorno y salta |
| `toma` | RET |
| `abrete N` | ENTER — arma el marco y reserva N locales |
| `cierrate` | LEAVE — desarma el marco |

Convención: argumentos por la pila de derecha a izquierda, **el que llama limpia**
(`echale mas hoyo, N`), resultado en `pico`. Con `abrete 0`: `[ojete+2]` es el primer
argumento, `[ojete+1]` el retorno, `[ojete-1]` el primer local.

### Entrada / salida

| Wea | Hace |
|---|---|
| `sueltate un src` | imprime el número + salto de línea |
| `sueltate un cacho src` | imprime el número pelado |
| `chamulla "..."` / `chamulla etiqueta` / `chamulla reg` | imprime un string |
| `escupe una letra src` | imprime un carácter (codepoint) |
| `pesca dst` | lee un entero de stdin |
| `pesca una letra dst` | lee un carácter (-1 si EOF) |
| `desnudate` | vuelca todos los registros a stderr (pa cachar qué pasa) |

### Sistema

| Wea | Hace |
|---|---|
| `ya wn para` | HALT — terminar bien (exit 0) |
| `conchetumare "msg"` | abortar con mensaje (exit 1) |
| `pajeandome` | NOP — puro weveo |
| `al lote dst, max` | aleatorio en [0, max) |
| `esperate un cacho ms` | dormir (tope 60 segundos) |

## Directivas

| Wea | Hace |
|---|---|
| `.la wea` | empieza la sección de datos |
| `.la pega` | empieza la sección de código (es la sección por defecto) |
| `etiqueta:` | define una etiqueta (de dato o de código según la sección) |
| `chamullo "texto"` | string en memoria, terminado en 0 |
| `numerito a, b, c` | enteros consecutivos |
| `puros hoyos N` | reserva N celdas en cero |
| `dale con NOMBRE = v` | constante |
| `.empezamos en L` | punto de entrada (si no, la etiqueta `inicio`, si no, la primera instrucción) |

## Cuando la cagas

Los errores vienen con línea y con el cariño característico:

```
[wea] Conchetumare weon, escribiste una wea que no cacho -> 'pescate' (linea 4)
[wea] CONCHETUMARE! Dividiste por cero. Aweonao. (linea 5)
[wea] Se te fue la pila a la chucha, ql. Recursion infinita o soi weon noma? (linea 3)
[wea] Se acabo el codigo y nunca pusiste 'ya wn para'. Aweonao.
[wea] Al sapeo no se le escribe, solo se mira po ql (linea 3)
```

## Ejemplos

En [examples/](examples/): `holamundo`, `fizzbuzz`, `fibonacci`, `factorial` (recursión
con marcos de pila), `ordena` (bubble sort in place con direccionamiento indexado),
`adivina` (juego interactivo con `pesca` y `al lote`) y `chelas` (las 99 chelas en la
pared, el clásico que todo lenguaje tiene que poder cantar — con singular, plural y
verso final como corresponde).

## Resaltado de sintaxis

Copia la carpeta `editor/vscode-wea` a `%USERPROFILE%\.vscode\extensions\` y reinicia
VS Code. Los `.wea` quedan con colores.

## Cómo está hecho

Todo el compilador y la máquina virtual están escritos en **ensamblador MASM x64**:

- `src/tablas.asm` — la única fuente de verdad del ISA (frases, opcodes, registros)
- `src/lexer.asm` — reconoce las frases multi-palabra por *maximal munch* (por eso
  `sueltate un cacho` le gana a `sueltate un`)
- `src/util.asm` — normalizador (tildes → ascii, mayúsculas → minúsculas), UTF-8, itoa/atoi
- `src/ensamblador.asm` — dos pasadas: layout de símbolos y literales, después emisión
- `src/vm.asm` — fetch/decode/execute con jump table; acá el hardware coopera: los
  registros de 32 bits ya hacen wrap solos y `idiv` ya trunca como C
- `src/compilador.asm` — el AOT: recorre el bytecode y emite texto MASM x64
- `src/runtime.asm` — lo que llaman los .exe compilados (print, pesca, al lote...)
- `src/errores.asm` — el catálogo de garabatos
- `src/wea.asm` — el CLI

El bytecode usa operandos de ancho fijo (`modo:u8, reg:u8, valor:i32`), así que el tamaño
de cada instrucción se conoce en la primera pasada y no hay relajación de saltos.
