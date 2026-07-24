# Wea

Estimado lector:

Reciba usted, antes que nada, un cordial y afectuoso saludo. Constituye para mí un honor
inconmensurable, así como una fuente de la más profunda satisfacción, darle la bienvenida a la
documentación oficial de **Wea**, el lenguaje ensamblador chileno. Me permito señalar que el presente
lenguaje se encuentra escrito en ensamblador auténtico (MASM x64, con absoluta
ausencia de dependencias y prescindiendo por completo del runtime de C — únicamente kernel32).

Permítame ilustrar lo anterior con un ejemplo:

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

## De la compilación del sistema

Me permito poner en su  conocimiento que, para proceder a la construcción del
presente software, le será menester contar con Visual Studio 2022 provisto de sus herramientas
de C++ (las cuales suministran, con la gentileza que las caracteriza, tanto `ml64` como `link`).
Cumplido dicho requisito, tenga usted la amabilidad de ejecutar:

```
.\build.bat
```

Dicha operación depositará respetuosamente `bin\wea.exe` a su disposición. Si además tuviese
usted a bien verificar la corrección del conjunto — gesto que le agradecería de todo corazón —
le ruego ejecutar:

```
powershell -File tests\corre_tests.ps1
```

## Del uso cotidiano

A continuación, y agradeciendo de antemano su paciencia, me permito detallar las modalidades de
invocación que el ejecutable tiene el agrado de ofrecerle:

```
wea corre programa.wea [--semilla=N]    ejecuta (interpretado)
wea revisa programa.wea                 solo compila (a ver si ta bueno)
wea compila programa.wea                genera el .gen.asm (MASM x64)
wea programa.wea                        atajo de corre
```

En lo concerniente a los códigos de salida, sírvase usted tomar nota: `0` significa que todo ha
concluido de manera enteramente satisfactoria; `1` indica que la ejecución ha encontrado un
infortunio en tiempo de ejecución (o bien que el programa ha invocado `conchetumare`, instrucción
cuyo nombre le suplico disculpar); `2` comunica, muy a mi pesar, que la compilación no ha podido
llevarse a término.

### De la compilación a ejecutable nativo

```
.\compila.bat programa.wea      ->  bin\programa.exe
```

Me es sumamente grato informarle que Wea constituye, asimismo, un compilador en el sentido más
riguroso del término. La orden `wea compila` traduce el bytecode a ensamblador MASM x64,
quedando los ocho registros de denominación malsonante — por la cual le reitero mis más sentidas
excusas — dignamente aposentados en registros x64 auténticos (`wn`→`ebx`, `ql`→`ebp`,
`pico`→`esi`, `tetas`→`edi`, `pichula`→`r12d`, `poto`→`r13d`, `chucha`→`r14d`, `raja`→`r15d`);
acto seguido, `compila.bat` somete el resultado a la consideración de `ml64` y `link` en
compañía del runtime. El fruto de tan laborioso proceso es un ejecutable autónomo de
aproximadamente 8 KB que funciona con total independencia de la máquina virtual. Tenga usted a
bien observar que `culialo pico, wn` deviene, efectivamente, en un `imul` legítimo.

## De los registros

El lenguaje pone a su entera disposición once registros de 32 bits con signo, cuyas
denominaciones — le ruego encarecidamente asirse de su asiento — son las que siguen:

| Registro | # | Naturaleza y cometido |
|---|---|---|
| `wn` | 0 | de propósito general |
| `ql` | 1 | de propósito general |
| `pico` | 2 | de propósito general — por convención, tiene el honor de portar el valor de retorno |
| `tetas` | 3 | de propósito general |
| `pichula` | 4 | de propósito general |
| `poto` | 5 | de propósito general |
| `chucha` | 6 | de propósito general |
| `raja` | 7 | de propósito general |
| `hoyo` | 8 | puntero de pila (SP), si me permite la expresión |
| `ojete` | 9 | puntero de marco (BP), y le agradezco no hacer preguntas |
| `sapeo` | 10 | indicadores de `cachai si` — de sola lectura; le imploro no escribirle |

## De la memoria

El sistema administra 65.536 celdas de 32 bits, direccionadas por celda y no por byte, detalle
que me permito subrayar para su mayor comodidad. Los datos de la sección `.la wea` tienen su
morada a partir de la celda 0; la pila, por su parte, inicia su existencia en el extremo superior
(65.536) y desciende con la debida discreción. Las cadenas de caracteres se almacenan a razón de
un punto de código Unicode por celda, con terminación en 0, gracias a lo cual las tildes y la
letra eñe funcionan con la corrección que usted, con toda justicia, merece.

Los modos de direccionamiento disponibles son los que a continuación se detallan:

| Se escribe | Efecto que produce |
|---|---|
| `wn` | el registro propiamente tal |
| `42` / `0x2A` / `0b101010` / `'a'` | valor inmediato |
| `etiqueta` | valor inmediato equivalente a **la dirección** de la etiqueta |
| `[42]` / `[etiqueta]` | la celda residente en dicha dirección |
| `[wn]` / `[wn+2]` / `[ojete-1]` | la celda señalada por el registro (con el desplazamiento que se sirva indicar) |

## Del repertorio de instrucciones

Tenga usted la bondad de considerar que los mnemónicos no distinguen mayúsculas ni tildes
(`métetelo` ≡ `METETELO` ≡ `metetelo`), y que los apóstrofes son cortésmente ignorados
(`pa'llá` ≡ `palla`). Los comentarios se introducen mediante `#` o `;`.

### Del movimiento de datos

| Wea | Cometido |
|---|---|
| `metetelo dst, src` | MOV — dst = src |
| `chupate dst, [dir]` | LOAD (idéntico al MOV, si bien de lectura más grata) |
| `dejalo en [dir], src` | STORE (mutatis mutandis) |
| `tragate src` | PUSH |
| `vomitate dst` | POP |
| `cambiense a, b` | XCHG |

### De la aritmética (todas dejan `sapeo` debidamente actualizado)

| Wea | Cometido |
|---|---|
| `echale mas dst, src` | ADD |
| `sacale dst, src` | SUB |
| `culialo dst, src` | MUL |
| `partele el pico dst, src` | DIV (truncada, a la usanza de C; la división por cero es declinada con firmeza) |
| `lo que caga dst, src` | MOD |
| `se le paro dst` | INC |
| `se le bajo dst` | DEC |
| `dale vuelta dst` | NEG |

### De la lógica

| Wea | Cometido |
|---|---|
| `las dos weas dst, src` | AND |
| `cualquier wea dst, src` | OR |
| `una o la otra dst, src` | XOR |
| `ni pico dst` | NOT |
| `correlo palla dst, n` | SHL |
| `correlo paca dst, n` | SAR (aritmético) |
| `correlo paca pelao dst, n` | SHR (lógico) |

### De la comparación y los saltos

La instrucción `cachai si a, b` efectúa la comparación (con signo, y sin incurrir en los
infortunios propios del desbordamiento) y deposita su dictamen en `sapeo`. Acto seguido, usted
podrá saltar según le venga en gana:

| Wea | Salta si |
|---|---|
| `arranca pa L` | incondicionalmente (admite registro: salto indirecto) |
| `si po L` | a == b |
| `nica po L` | a != b |
| `re brigido L` | a > b |
| `re penca L` | a < b |
| `brigido noma L` | a >= b |
| `penca noma L` | a <= b |

### De las funciones

| Wea | Cometido |
|---|---|
| `hazme la pega L` | CALL — deposita el retorno en la pila y salta |
| `toma` | RET |
| `abrete N` | ENTER — constituye el marco y reserva N variables locales |
| `cierrate` | LEAVE — disuelve el marco con la debida ceremonia |

En cuanto a la convención de llamada, los argumentos se entregan por la pila de derecha a
izquierda, la limpieza corre por gentileza de quien llama (`echale mas hoyo, N`), y el resultado
es restituido en `pico`. Habiendo ejecutado `abrete 0`: `[ojete+2]` alberga el primer argumento,
`[ojete+1]` la dirección de retorno, y `[ojete-1]` la primera variable local.

### De la entrada y la salida

| Wea | Cometido |
|---|---|
| `sueltate un src` | imprime el número, seguido de un salto de línea |
| `sueltate un cacho src` | imprime el número, sin aditamento alguno |
| `chamulla "..."` / `chamulla etiqueta` / `chamulla reg` | imprime una cadena de caracteres |
| `escupe una letra src` | imprime un carácter (punto de código) |
| `pesca dst` | recibe un entero desde la entrada estándar |
| `pesca una letra dst` | recibe un carácter (-1 en caso de EOF) |
| `desnudate` | vuelca la totalidad de los registros a stderr, para su ilustración |

### Del sistema

| Wea | Cometido |
|---|---|
| `ya wn para` | HALT — concluye honrosamente (exit 0) |
| `conchetumare "msg"` | aborta con mensaje (exit 1), no sin antes lamentar lo ocurrido |
| `pajeandome` | NOP — ocio absoluto |
| `al lote dst, max` | número aleatorio en [0, max) |
| `esperate un cacho ms` | reposa (con un máximo de 60 segundos, por prudencia) |

## De las directivas

| Wea | Cometido |
|---|---|
| `.la wea` | da comienzo a la sección de datos |
| `.la pega` | da comienzo a la sección de código (sección por defecto, para su comodidad) |
| `etiqueta:` | define una etiqueta (de dato o de código, según la sección en que resida) |
| `chamullo "texto"` | cadena en memoria, con terminación en 0 |
| `numerito a, b, c` | enteros consecutivos |
| `puros hoyos N` | reserva N celdas debidamente puestas a cero |
| `dale con NOMBRE = v` | constante |
| `.empezamos en L` | punto de entrada (en su defecto, la etiqueta `inicio`; en defecto de ambos, la primera instrucción) |

## De los errores

En la infortunada eventualidad de que usted incurriese en alguna imprecisión, el sistema tendrá
a bien comunicárselo con el número de línea correspondiente y con el afecto que lo caracteriza.
Le ruego recibir los siguientes ejemplos con espíritu comprensivo:

```
[wea] Conchetumare weon, escribiste una wea que no cacho -> 'pescate' (linea 4)
[wea] CONCHETUMARE! Dividiste por cero. Aweonao. (linea 5)
[wea] Se te fue la pila a la chucha, ql. Recursion infinita o soi weon noma? (linea 3)
[wea] Se acabo el codigo y nunca pusiste 'ya wn para'. Aweonao.
[wea] Al sapeo no se le escribe, solo se mira po ql (linea 3)
```

## De los ejemplos

En el directorio [examples/](examples/) hallará usted, dispuestos para su deleite: `holamundo`,
`fizzbuzz`, `fibonacci`, `factorial` (recursión con marcos de pila en toda regla), `ordena`
(ordenamiento de burbuja in situ, con direccionamiento indexado), `adivina` (entretenimiento
interactivo que hace uso de `pesca` y `al lote`) y `chelas` (las noventa y nueve cervezas en la
pared, pieza clásica que todo lenguaje que se precie ha de saber entonar, ejecutada con singular,
plural y verso final, como el buen gusto lo exige).

## Del realce de sintaxis

Si usted tuviese la gentileza de copiar la carpeta `editor/vscode-wea` en
`%USERPROFILE%\.vscode\extensions\` y de reiniciar Visual Studio Code, los archivos `.wea`
lucirán colores, atención que espero sea de su completo agrado.

## De su construcción interna

La totalidad del compilador y de la máquina virtual ha sido escrita en ensamblador MASM x64,
conforme al siguiente reparto de responsabilidades:

- `src/tablas.asm` — la única fuente de verdad del ISA (frases, opcodes, registros)
- `src/lexer.asm` — reconoce las frases de múltiples palabras mediante *maximal munch* (en cuya
  virtud `sueltate un cacho` prevalece sobre `sueltate un`)
- `src/util.asm` — normalizador (tildes → ascii, mayúsculas → minúsculas), UTF-8, itoa/atoi
- `src/ensamblador.asm` — dos pasadas: disposición de símbolos y literales, y ulterior emisión
- `src/vm.asm` — fetch/decode/execute con jump table; me complace informar que el hardware
  coopera: los registros de 32 bits practican el wrap por iniciativa propia e `idiv` trunca a la
  usanza de C
- `src/compilador.asm` — el AOT: recorre el bytecode y emite texto MASM x64
- `src/runtime.asm` — aquello que los ejecutables compilados tienen a bien invocar (impresión,
  `pesca`, `al lote`, etcétera)
- `src/errores.asm` — el catálogo de amonestaciones
- `src/wea.asm` — la interfaz de línea de órdenes

El bytecode emplea operandos de anchura fija (`modo:u8, reg:u8, valor:i32`), merced a lo cual el
tamaño de cada instrucción se conoce desde la primera pasada, tornando innecesaria toda
relajación de saltos.

---

Muy atentamente,

**Jamonoid**
