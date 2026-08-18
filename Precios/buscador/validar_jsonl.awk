# Valida el subconjunto JSONL plano que producen y consumen los parsers.
# No pretende ser un parser JSON general: jq, cuando existe, hace esa parte.

function fail(msg) {
  printf "%s:%d: %s\n", LABEL, FNR, msg > "/dev/stderr"
  errors++
}
function string_field(line, name,   marker, rest) {
  marker = "\"" name "\":\""
  if (index(line, marker) == 0) return ""
  rest = substr(line, index(line, marker) + length(marker))
  sub(/\".*/, "", rest)
  return rest
}
function number_field(line, name,   marker, rest) {
  marker = "\"" name "\":"
  if (index(line, marker) == 0) return ""
  rest = substr(line, index(line, marker) + length(marker))
  sub(/[^0-9.].*/, "", rest)
  return rest
}

BEGIN {
  if (LABEL == "") LABEL = FILENAME
  MAX_PRICE = (MAX_PRICE == "" ? 1000 : MAX_PRICE)
}

{
  if ($0 !~ /^\{.*\}$/) fail("la línea no es un objeto JSON")
  sec = string_field($0, "sec")
  modelo = string_field($0, "modelo")
  precio = number_field($0, "precio")
  if (sec == "") fail("falta sec o está vacía")
  if (modelo == "") fail("falta modelo o está vacío")
  if (precio == "") fail("falta precio numérico")
  else if (precio + 0 <= 0 || precio + 0 > MAX_PRICE)
    fail("precio fuera del rango 0 < precio <= " MAX_PRICE ": " precio)

  codigo = string_field($0, "codigo")
  sku = string_field($0, "sku")
  id = (codigo != "" ? codigo : sku)
  if (CHECK_ID && id == "") fail("falta código/SKU")
  if (id != "") {
    if (id !~ /^[0-9]+$/) fail("código/SKU no numérico: " id)
    signature = modelo SUBSEP precio
    if (id in id_signature) {
      if (id_signature[id] != signature)
        fail("código/SKU reutilizado con otro modelo o precio: " id)
      else id_aliases++
    } else id_signature[id] = signature
  }

  if (CHECK_SEMANTIC_DUP && sec != "" && modelo != "" && precio != "") {
    semantic = sec SUBSEP modelo SUBSEP precio
    if (seen_semantic[semantic]++) semantic_dups++
  }
  rows++
}

END {
  if (rows == 0 && !ALLOW_EMPTY) {
    printf "%s: archivo vacío\n", LABEL > "/dev/stderr"
    errors++
  }
  printf "%s: %d filas revisadas, %d errores", LABEL, rows, errors > "/dev/stderr"
  if (id_aliases) printf ", %d alias de sección con el mismo SKU", id_aliases > "/dev/stderr"
  if (semantic_dups) printf ", %d duplicados semánticos que la app agrupará", semantic_dups > "/dev/stderr"
  printf "\n" > "/dev/stderr"
  if (errors) exit 1
}
