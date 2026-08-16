# Parser de listas de precios MAX MOVIL CENTER (lista "BBB").
#
# Estos PDF traen una tabla simple de 3 columnas: CODIGO | DESCRIPCION | PRECIO.
# El problema es que ninguna extraccion sola sirve:
#   -table  respeta las filas (codigo y precio quedan bien pareados) pero pega
#           palabras: "FLEX DE HUELLAA03SAZUL".
#   -layout respeta el espaciado de las palabras pero desalinea las filas
#           (las columnas quedan corridas varias lineas entre si).
# Asi que se usan las dos: -table define las filas, y el texto de -layout se
# usa como diccionario para recuperar la escritura correcta. La llave es la
# descripcion sin espacios, que es identica en ambas extracciones.
#
# Uso: LC_ALL=C gawk -v SEC="PIN DE CARGA" -f parse_bbb.awk layout.txt table.txt \
#        > items.jsonl 2> qa.log

function key(s) { gsub(/ /, "", s); return s }
function jesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
function limpia(s) {
  gsub(/[\r\f]/, "", s)
  sub(/^ *[0-9]{8} +/, "", s)          # columna de codigo
  sub(/ +[0-9]+(\.[0-9]+)? *$/, "", s) # columna de precio
  gsub(/  +/, " ", s); gsub(/^ +| +$/, "", s)
  return s
}

# ---- archivo 1: -layout, solo para armar el diccionario de escritura ----
NR == FNR {
  d = limpia($0)
  if (d != "" && d ~ /[A-Z]/) DIC[key(d)] = d
  next
}

# ---- archivo 2: -table, define las filas ----
{
  line = $0; gsub(/[\r\f]/, "", line)
  if (line ~ /FECHA/ || line ~ /^ *[0-9]{1,2}\/[0-9]{1,2}\/[0-9]{4}/) {
    if (match(line, /[0-9]{1,2}\/[0-9]{1,2}\/[0-9]{4}/) && !fecha) {
      fecha = substr(line, RSTART, RLENGTH)
      printf "META FECHA %s\n", fecha > "/dev/stderr"
    }
  }
  if (line !~ /^ *[0-9]{8} +/) next

  cod = line; sub(/^ */, "", cod); sub(/ .*/, "", cod)
  if (match(line, / +[0-9]+(\.[0-9]+)? *$/)) {
    precio = substr(line, RSTART); gsub(/ /, "", precio)
  } else {
    printf "L%d: SIN PRECIO [%s]\n", FNR, line > "/dev/stderr"; next
  }
  desc = limpia(line)

  k = key(desc)
  if (k in DIC) desc = DIC[k]
  else printf "L%d: SIN ESPACIADO de referencia, se usa -table: [%s]\n", FNR, desc > "/dev/stderr"

  if (desc == "") { printf "L%d: DESCARTADO sin descripcion (cod=%s)\n", FNR, cod > "/dev/stderr"; next }
  if (precio + 0 <= 0) { printf "L%d: PRECIO CERO (agotado?) [%s] cod=%s\n", FNR, desc, cod > "/dev/stderr"; next }
  if (precio + 0 > 500) { printf "L%d: PRECIO RARO %s [%s]\n", FNR, precio, desc > "/dev/stderr" }

  if (cod in VISTO) { printf "L%d: CODIGO REPETIDO %s [%s]\n", FNR, cod, desc > "/dev/stderr"; next }
  VISTO[cod] = 1

  n++
  printf "{\"sec\":\"%s\",\"codigo\":\"%s\",\"modelo\":\"%s\",\"precio\":%s}\n", \
    jesc(SEC), cod, jesc(desc), precio + 0
}

END { printf "META ITEMS %d\n", n > "/dev/stderr" }
