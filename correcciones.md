# Referencia del lenguaje Wea

## Keywords

| Keyword | Qué es |
|---|---|
| `dale x = v` | declara la variable `x` en el scope actual |
| `que wea si (cond) { }` | if |
| `si nicagando ql { }` | else (también encadena: `si nicagando que wea si (...)`) |
| `mientras (cond) { }` | while |
| `pa cada wea{ }` | for-each sobre listas o textos |
| `pega nombre(params) { }` | define una función |
| `toma expr` | return (`toma` a secas devuelve `niuno`) |
| `ya wn para` | break |
| `sigue noma` | continue (también `sigue nomás`) |
| `la pulenta` | true |
| `mula ql` | false |
| `niuno` | null |
| `y` / `o` / `no` | and / or / not (con cortocircuito) |
| `po` | terminador opcional de sentencia (cero o más) |
| `pico ...` / `# ...` | comentario de línea |

Los keywords se reconocen sin importar mayúsculas ni tildes (`Dale Con` ≡ `dale con`,
`suéltate un` ≡ `sueltate un`). Los identificadores de usuario SÍ distinguen tildes.

## Operadores (de menor a mayor precedencia)

1. `=` asignación (a variable o a `lista[i]`)
2. `o`
3. `y`
4. `==` `!=` (igualdad profunda: las listas se comparan elemento a elemento)
5. `<` `<=` `>` `>=` (números entre sí, textos entre sí)
6. `+` `-` (`+` concatena si cualquiera de los dos es texto; suma listas)
7. `*` `/` `%`
8. `no` / `-` unario
9. llamadas `f(...)` e índices `x[i]`

## Semántica

- **Números**: double de 64 bits. Se imprimen sin decimales cuando son enteros.
- **Textos**: UTF-8. `largo()`, los índices y `pa cada` cuentan por codepoint.
- **Listas**: semántica de referencia (asignar no copia). Índice base 0.
- **Verdad**: `chiva`, `niuno`, `0`, `""` y `[]` son falsos; el resto verdadero.
- **`y`/`o`** devuelven el operando, no un booleano (`chiva o "x"` → `"x"`).
- **Scopes**: cada bloque `{ }` crea un scope. `dale con` declara en el scope
  actual; `=` busca la variable hacia afuera.
- **Pegas**: clausuras de verdad — capturan el entorno donde se definieron.
- **Recursión**: máximo 1000 niveles y después te vai en la volá.

## Builtins

| Pega | Aridad | Qué hace |
|---|---|---|
| `sueltate un(...)` | variádica | imprime los args separados por espacio + salto de línea |
| `pesca()` | 0 | lee una línea de stdin; `niuno` en EOF |
| `largo(x)` | 1 | codepoints de un texto / elementos de una lista |
| `apaña(lista, x)` | 2 | push al final; devuelve la lista (alias: `apana`) |
| `saca(lista, i)` | 2 | saca y devuelve el elemento `i` |
| `numero(x)` | 1 | a número; `niuno` si no se puede (alias: `número`) |
| `texto(x)` | 1 | a texto |
| `tipo(x)` | 1 | `"numerito"`, `"palabras"`, `"veredicto"`, `"niuno"`, `"lista"` o `"pega"` |
| `al lote(n)` | 1 | entero al azar en `[0, n)` |


## Gramática (aproximada)

```
programa    → sentencia*
sentencia   → dale_con | si | mientras | pa_cada | pega | toma
            | ya_wn_para | sigue_noma | expresion fin
dale_con    → "dale con" IDENT "=" expresion fin
si          → "que wea si" "(" expresion ")" bloque ("si nicagando" (si | bloque))?
mientras    → "mientras" "(" expresion ")" bloque
pa_cada     → "pa cada" IDENT "en" expresion bloque
pega        → "pega" IDENT "(" params? ")" bloque
toma        → "toma" expresion? fin
bloque      → "{" sentencia* "}"
fin         → "po"* (NEWLINE | EOF | "}")
expresion   → asignacion
asignacion  → logica_o ("=" asignacion)?
logica_o    → logica_y ("o" logica_y)*
logica_y    → igualdad ("y" igualdad)*
igualdad    → comparacion (("==" | "!=") comparacion)*
comparacion → suma (("<" | "<=" | ">" | ">=") suma)*
suma        → producto (("+" | "-") producto)*
producto    → unaria (("*" | "/" | "%") unaria)*
unaria      → ("no" | "-") unaria | postfijo
postfijo    → primaria ("(" args? ")" | "[" expresion "]")*
primaria    → NUMERO | TEXTO | "la pulenta" | "chiva" | "niuno"
            | IDENT | "(" expresion ")" | "[" args? "]"
```
