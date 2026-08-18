#!/usr/bin/env bash
# Regenera buscador.html a partir de:
#   - los PDF de HEM Movil que estan en la carpeta Precios (se parsean automaticamente)
#   - los datos de Canguro en buscador/datos/can_*.jsonl (transcritos del catalogo web)
# Uso (Git Bash): cd ~/Downloads/Precios/buscador && bash actualizar.sh
# Luego pedirle a Claude: "publica buscador/buscador.html en el mismo artifact"
set -euo pipefail
export LC_ALL=C
DIR="$(cd "$(dirname "$0")" && pwd)"
PDFS="$DIR/.."
TMP="$DIR/.tmp"; mkdir -p "$TMP"

# GNU awk es el entorno original, pero los parsers tambien funcionan con awk
# POSIX moderno. Esto permite regenerar en equipos donde el binario se llama
# simplemente "awk" (por ejemplo esta instalacion de Linux).
if [ -n "${AWK_BIN:-}" ]; then
  command -v "$AWK_BIN" >/dev/null 2>&1 || { echo "No se encontro AWK_BIN=$AWK_BIN" >&2; exit 1; }
elif command -v gawk >/dev/null 2>&1; then
  AWK_BIN=gawk
elif command -v awk >/dev/null 2>&1; then
  AWK_BIN=awk
else
  echo "Falta awk/gawk; instalalo antes de actualizar el inventario." >&2; exit 1
fi
command -v pdftotext >/dev/null 2>&1 || {
  echo "Falta pdftotext (Poppler); instalalo antes de actualizar el inventario." >&2; exit 1
}
# Algunas compilaciones incluyen `-table`; Poppler oficial solo ofrece
# `-layout`. Para estas listas ambos conservan las filas y producen los mismos
# conteos, por lo que se selecciona la mejor opción disponible.
if pdftotext -h 2>&1 | grep -q -- '-table'; then PDF_TABLE_OPT=-table
else PDF_TABLE_OPT=-layout
fi

# Tope de precio plausible, compartido por los dos parsers y por el validador.
MAX_PRECIO="${MAX_PRECIO:-500}"
# Los avisos de extraccion abortan la actualizacion a proposito: publicar medio
# inventario es peor que no publicarlo. Pero un aviso cosmetico no puede dejar
# al taller sin poder actualizar precios un sabado, asi que hay valvula:
#   PERMITIR_PROBLEMAS=1 bash actualizar.sh
# No cubre los fallos estructurales (PDF sin mapeo o sin fecha): esos hacen
# desaparecer una categoria entera y hay que arreglarlos de verdad.
PERMITIR_PROBLEMAS="${PERMITIR_PROBLEMAS:-0}"

SEC_BAT="IPHONE|NOKIA|XIAOMI|HUAWEI|HONOR|SAMSUNG|LG|REALME|TECNO|TABLET|IPH ORIGINAL(CONDICIÓN DE BATERÍA)"
SEC_PAN="PANTALLA COMPLETA|PANTALLA SOLA|PANTALLA DE TABLET|LISTA DE PRECIO DE TACTIL|LISTA DE PRECIO DE MEMORIA"
SEC_CAR="CARATULA|TAPA"
SEC_FLEX="AURICULAR|BANDEJA DE CHIP|BOTÓN FÍSICO DE POWER Y VOLUMEN|BUZZER/TIMBRE/ALTAVOZ|CABLE ANTENA|FLASH|FLEX ANTENA SEÑAL|FLEX CABLE ALTAVOZ|FLEX CABLE BLUETOOTH|FLEX DE AURICULAR|FLEX DE CAMARA FRONTAL|FLEX DE CAMARA TRASERA|FLEX DE HUELLA|FLEX DE MICROFONO|FLEX DE PANTALLA(CENTRO)|FLEX DE POWER Y VOLUMEN|FLEX DE POWER(ENCENDIDO)|FLEX DE SENSOR|FLEX DE VOLUMEN|FLEX HOME|FLEX RETROCESO|FLEX WIFI ANTENA|FLEX(PLACA) DE CARGA|FLEXIBLE PORCENTAJE IPH|FPC DE ANTENA|FPC DE BATERIA|FPC DE LCD|FPC DE PLACA|HOME FÍSICO|JACK AUDIO AURICULAR|LECTOR DE CHIP|LECTOR DE HUELLA|LENTE DE CAMARA|MICROFONO|MOTOR VIBRATOR DE CAMARA FRONTAL|NFC PLACA DE CARGA INALAMBRICA|PIN DE CARGA|PLACA DE MICROFONO|PLACA DE PANTALLA|VIBRADOR"

extrae() { # $1=pdf  $2=clave  $3=secciones
  local pdf="$PDFS/$1" key="$2" sec="$3"
  pdftotext "$PDF_TABLE_OPT" -enc UTF-8 "$pdf" "$TMP/$key.txt"
  "$AWK_BIN" -v SECTIONS="$sec" -v MAX_PRICE="$MAX_PRECIO" -f "$DIR/parse.awk" "$TMP/$key.txt" > "$TMP/$key.jsonl" 2> "$TMP/$key.qa.log"
  grep -q '^META FECHA ' "$TMP/$key.qa.log" || {
    echo "La lista HEM $pdf no contiene una fecha reconocible." >&2; exit 1
  }
  local prob; prob=$(grep -cvE '^META|ANEXADO' "$TMP/$key.qa.log" || true)
  echo "  HEM $key: $(wc -l < "$TMP/$key.jsonl") repuestos, $prob problemas (ver $TMP/$key.qa.log)"
  if [ "$prob" -ne 0 ]; then
    if [ "$PERMITIR_PROBLEMAS" = "1" ]; then
      echo "    (PERMITIR_PROBLEMAS=1: se continúa pese a $prob problema(s))"
    else
      echo "Se aborta por problemas de extracción en HEM $key." >&2
      echo "Revisa $TMP/$key.qa.log; si los avisos son aceptables, repite con PERMITIR_PROBLEMAS=1." >&2
      exit 1
    fi
  fi
}

echo "Extrayendo listas de HEM Movil..."
extrae "HEM-PRECIOS DE BATERIAS.pdf"  bat  "$SEC_BAT"
extrae "HEM-PRECIOS DE PANTALLA.pdf"  pan  "$SEC_PAN"
extrae "HEM-CARATULAS Y TAPAS.pdf"    car  "$SEC_CAR"
extrae "HEM-PRECIOS DE FLEXIBLES.pdf" flex "$SEC_FLEX"

# ---- Max Movil (identificador interno: BBB) ---------------------------------
# Un PDF por tipo de repuesto en Precios/pdfs-bbb/. Para agregar una lista nueva
# basta con copiar el PDF ahi y sumar una linea a datos/bbb_map.txt: el nombre
# del archivo (sin .pdf) a la izquierda, la seccion a la derecha. Las secciones
# se llaman igual que las de HEM a proposito, para que la app las clasifique igual.
# Excepcion: "FLEX DE PLACA" NO se llama "FPC DE PLACA" como en HEM, porque no
# es la misma pieza (ver el bloque de cruces al final del archivo).
BBB_MAP_FILE="$DIR/datos/bbb_map.txt"
[ -s "$BBB_MAP_FILE" ] || { echo "Falta el mapa de Max Movil: $BBB_MAP_FILE" >&2; exit 1; }

echo "Extrayendo listas de Max Movil..."
TB="$TMP/bbb"; mkdir -p "$TB"; rm -f "$TB"/*.jsonl "$TB"/*.qa.log
BBB_SIN_MAPEO=0; BBB_SIN_FECHA=0; BBB_PROBLEMAS=0
for pdf in "$PDFS"/pdfs-bbb/*.pdf; do
  [ -e "$pdf" ] || { echo "  (no hay PDFs en $PDFS/pdfs-bbb)"; break; }
  b=$(basename "$pdf" .pdf)
  sec=$("$AWK_BIN" -F'|' -v n="$b" '$0 !~ /^#/ && $1==n{print $2; exit}' "$BBB_MAP_FILE")
  if [ -z "$sec" ]; then
    echo "  !! SIN MAPEO, se omite: $b   (agrégalo a $BBB_MAP_FILE)"
    BBB_SIN_MAPEO=$((BBB_SIN_MAPEO+1)); continue
  fi
  # La extracción tabular define las filas y -layout sirve de diccionario para
  # recuperar espacios. Si Poppler no ofrece -table, -layout cumple ambos roles.
  pdftotext -layout -enc UTF-8 "$pdf" "$TB/$b.lay.txt"
  pdftotext "$PDF_TABLE_OPT" -enc UTF-8 "$pdf" "$TB/$b.tab.txt"
  "$AWK_BIN" -v SEC="$sec" -v MAX_PRICE="$MAX_PRECIO" -f "$DIR/parse_bbb.awk" "$TB/$b.lay.txt" "$TB/$b.tab.txt" \
    > "$TB/$b.jsonl" 2> "$TB/$b.qa.log"
  if ! grep -q '^META FECHA ' "$TB/$b.qa.log"; then
    echo "  !! SIN FECHA reconocible: $b"
    BBB_SIN_FECHA=$((BBB_SIN_FECHA+1))
  fi
  prob=$(grep -cvE '^META|SIN ESPACIADO|PRECIO CERO' "$TB/$b.qa.log" || true)
  BBB_PROBLEMAS=$((BBB_PROBLEMAS+prob))
  printf '  Max Movil %-42s %5s repuestos, %s problemas\n' "$sec" "$(wc -l < "$TB/$b.jsonl")" "$prob"
done
[ "$BBB_SIN_MAPEO" -eq 0 ] || {
  echo "Se aborta la actualización: hay $BBB_SIN_MAPEO PDF(s) de Max Movil sin mapeo." >&2
  exit 1
}
[ "$BBB_SIN_FECHA" -eq 0 ] || {
  echo "Se aborta la actualización: hay $BBB_SIN_FECHA PDF(s) de Max Movil sin fecha." >&2
  exit 1
}
if [ "$BBB_PROBLEMAS" -ne 0 ]; then
  if [ "$PERMITIR_PROBLEMAS" = "1" ]; then
    echo "  (PERMITIR_PROBLEMAS=1: se continúa pese a $BBB_PROBLEMAS problema(s))"
  else
    echo "Se aborta la actualización: Max Movil reportó $BBB_PROBLEMAS problema(s) de extracción." >&2
    echo "Revisa $TB/*.qa.log; si los avisos son aceptables, repite con PERMITIR_PROBLEMAS=1." >&2
    exit 1
  fi
fi
cat "$TB"/*.jsonl > "$TB/bbb.jsonl" 2>/dev/null || : > "$TB/bbb.jsonl"
# Se usa la fecha mas antigua entre todas las listas: una sola lista vieja debe
# hacer que el estado global de Max Movil se considere viejo.
FBBB=$(grep -h 'META FECHA' "$TB"/*.qa.log 2>/dev/null | sed 's/META FECHA //; s/\r//' \
       | awk -F/ '{printf "%04d.%02d.%02d\n", $3, $2, $1}' | sort | head -1)
[ -z "$FBBB" ] && FBBB="0000.00.00"
echo "  Max Movil total: $(wc -l < "$TB/bbb.jsonl") repuestos (lista del $FBBB)"

echo "Leyendo datos de Canguro..."
CAN_FILES=(
  "$DIR/datos/can_bat.jsonl"   "$DIR/datos/can_lcd.jsonl"   "$DIR/datos/can_flex.jsonl"
  "$DIR/datos/can_pin.jsonl"   "$DIR/datos/can_tapas.jsonl" "$DIR/datos/can_touch.jsonl"
  "$DIR/datos/can_herr.jsonl"
)
echo "  Canguro: $(cat "${CAN_FILES[@]}" | wc -l) repuestos"

# Fecha de la captura de Canguro, en formato AAAA.MM.DD. Se declara a mano en
# datos/fecha_canguro.txt porque la fecha de modificacion del archivo miente:
# copiar la carpeta o restaurarla desde un respaldo la adelanta sin que los
# precios hayan cambiado, y la app mostraria como fresca una lista vieja. Si el
# archivo falta se usa el mtime mas reciente, como antes, pero avisando.
FCANF="$DIR/datos/fecha_canguro.txt"
if [ -s "$FCANF" ]; then
  FCAN=$(tr -d ' \t\r\n' < "$FCANF")
else
  FCAN=$(for f in "${CAN_FILES[@]}"; do date -r "$f" +%Y.%m.%d; done | sort -r | head -1)
  echo "  !! falta $FCANF; se usa la fecha del archivo mas reciente ($FCAN)"
fi
case "$FCAN" in
  [0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9]) ;;
  *) echo "Fecha de Canguro invalida: '$FCAN' (se espera AAAA.MM.DD)" >&2; exit 1 ;;
esac

# Los textos de proveedores se incrustan dentro de un <script>. Convertir estos
# caracteres a escapes Unicode evita que una descripción como </script> pueda
# cerrar el bloque y alterar el HTML generado.
js_safe() {
  "$AWK_BIN" '{
    gsub(/&/, "\\u0026")
    gsub(/</, "\\u003c")
    gsub(/>/, "\\u003e")
    print
  }' "$@"
}

{
  printf 'const RAW={'
  for x in bat pan car flex; do printf '"%s":[' "$x"; js_safe "$TMP/$x.jsonl" | paste -sd,; printf '],'; done
  printf '"_end":1};\n'
  printf 'const FECHAS={'
  for x in bat pan car flex; do
    f=$(grep -m1 'META FECHA' "$TMP/$x.qa.log" | sed 's/META FECHA //; s/\r//')
    printf '"%s":"%s",' "$x" "$f"
  done
  printf '"_end":""};\n'
  printf 'const FECHA_CANGURO="%s";\n' "$FCAN"
  printf 'const CANGURO=['
  js_safe "${CAN_FILES[@]}" | paste -sd,
  printf '];\n'
  printf 'const FECHA_BBB="%s";\n' "$FBBB"
  printf 'const BBB=['
  js_safe "$TB/bbb.jsonl" | paste -sd,
  printf '];\n'
} > "$TMP/data.js"

# inyecta los datos, el logo y el icono de app (todo como data URI) en la plantilla
"$AWK_BIN" -v LOGOF="$DIR/datos/logo.datauri.txt" -v ICONF="$DIR/datos/icon.datauri.txt" '
  /<script src="data.js"><\/script>/{next}
  /^\/\/__DATA__$/{while((getline l < "'"$TMP"'/data.js")>0) print l; next}
  /__LOGO__/{ getline logo < LOGOF; close(LOGOF); sub(/__LOGO__/, logo); print; next }
  /__ICON__/{ getline ico < ICONF; close(ICONF); sub(/__ICON__/, ico); print; next }
  {print}' "$DIR/app_template.html" > "$DIR/buscador.html"
echo "Listo: $DIR/buscador.html ($(wc -c < "$DIR/buscador.html") bytes)"

# Copia lista para subir a Netlify. Netlify sirve index.html en la raiz del sitio,
# asi que el archivo va renombrado; robots.txt y _headers evitan que lo indexen
# los buscadores (la lista lleva precios de costo).
NET="$PDFS/para-netlify"; mkdir -p "$NET"
cp "$DIR/buscador.html" "$NET/index.html"
printf 'User-agent: *\nDisallow: /\n' > "$NET/robots.txt"
printf '/\n  Content-Type: text/html; charset=UTF-8\n  Cache-Control: private, no-store\n\n/index.html\n  Content-Type: text/html; charset=UTF-8\n  Cache-Control: private, no-store\n\n/*\n  X-Robots-Tag: noindex, nofollow, noarchive\n  Referrer-Policy: no-referrer\n  X-Content-Type-Options: nosniff\n  X-Frame-Options: DENY\n' > "$NET/_headers"
echo "Carpeta para Netlify actualizada: $NET  (arrastrala a app.netlify.com/drop)"

# ---- revision de los cruces entre distribuidores ----------------------------
# El error mas caro de esta app no es un precio mal leido, es cruzar dos piezas
# distintas y anunciar un ahorro que no existe. Aqui se listan los cruces
# ordenados por diferencia de precio: los pareos malos casi siempre estan
# arriba, asi que revisar las primeras lineas a mano alcanza para confiar.
MQA="$TMP/matches.qa.log"; : > "$MQA"
cruces() { # $1=etiqueta  $2..=tripletas dist/sec/archivo
  local lbl="$1"; shift
  { echo; echo "##### $lbl"; } >> "$MQA"
  "$AWK_BIN" -f "$DIR/qa_match.awk" "$@" 2>>"$MQA" | sort -rn >> "$MQA"
}
HF="$TMP/flex.jsonl"; BF="$TB/bbb.jsonl"; CD="$DIR/datos"
cruces "PANTALLAS" \
  dist=HEM sec="PANTALLA COMPLETA" "$TMP/pan.jsonl" \
  dist=BBB sec="PANTALLA" "$BF" dist=Canguro sec="LCD" "$CD/can_lcd.jsonl"
cruces "FLEX DE CARGA" \
  dist=HEM sec="FLEX(PLACA) DE CARGA" "$HF" \
  dist=BBB sec="FLEX DE CARGA" "$BF" dist=Canguro sec="FLEX DE CARGA" "$CD/can_flex.jsonl"
cruces "PIN DE CARGA" \
  dist=HEM sec="PIN DE CARGA" "$HF" \
  dist=BBB sec="PIN DE CARGA" "$BF" dist=Canguro sec="PIN DE CARGA" "$CD/can_pin.jsonl"
cruces "POWER Y VOLUMEN" \
  dist=HEM sec="FLEX DE POWER Y VOLUMEN|FLEX DE POWER(ENCENDIDO)|FLEX DE VOLUMEN|BOTÓN FÍSICO DE POWER Y VOLUMEN" "$HF" \
  dist=BBB sec="FLEX DE POWER Y VOLUMEN|BOTON FISICO DE POWER Y VOLUMEN" "$BF" \
  dist=Canguro sec="FLEX DE POWER" "$CD/can_flex.jsonl"
cruces "HUELLA" \
  dist=HEM sec="LECTOR DE HUELLA|FLEX DE HUELLA" "$HF" dist=BBB sec="FLEX DE HUELLA" "$BF"
cruces "CAMARA" \
  dist=HEM sec="FLEX DE CAMARA FRONTAL|FLEX DE CAMARA TRASERA" "$HF" \
  dist=BBB sec="FLEX DE CAMARA FRONTAL|FLEX DE CAMARA TRASERA" "$BF"
cruces "LENTE DE CAMARA" \
  dist=HEM sec="LENTE DE CAMARA" "$HF" dist=BBB sec="LENTE DE CAMARA" "$BF"
cruces "BANDEJA / LECTOR DE CHIP" \
  dist=HEM sec="BANDEJA DE CHIP|LECTOR DE CHIP" "$HF" dist=BBB sec="BANDEJA DE CHIP" "$BF"
cruces "ALTAVOZ / BUZZER" \
  dist=HEM sec="BUZZER/TIMBRE/ALTAVOZ|FLEX CABLE ALTAVOZ" "$HF" \
  dist=BBB sec="BUZZER/TIMBRE/ALTAVOZ" "$BF"
cruces "AURICULAR" \
  dist=HEM sec="AURICULAR|FLEX DE AURICULAR|JACK AUDIO AURICULAR" "$HF" \
  dist=BBB sec="FLEX DE AURICULAR" "$BF"
cruces "ANTENA" \
  dist=HEM sec="CABLE ANTENA|FLEX WIFI ANTENA|FLEX ANTENA SEÑAL|FPC DE ANTENA" "$HF" \
  dist=BBB sec="FLEX ANTENA SEÑAL" "$BF"
# HEM y Max Movil llaman "placa" a piezas distintas: el "FPC DE PLACA" de HEM es
# el conector que se suelda a la placa (los 21 modelos valen $0.75 exactos) y el
# "FLEX DE PLACA" de Max Movil es el flexible de interconexion completo ($3-$6).
# Cruzarlos anunciaba un ahorro inexistente de $4.25. Ahora son variantes
# separadas; este bloque se conserva para comprobar que siguen sin cruzarse.
cruces "PLACA (FPC de HEM y flex de Max Movil no deben cruzarse)" \
  dist=HEM sec="FPC DE PLACA" "$HF" dist=BBB sec="FLEX DE PLACA" "$BF"
echo "Cruces entre distribuidores: $(grep -c '%' "$MQA") -> $MQA"
echo "  (revisa las primeras lineas de cada seccion: mayor diferencia = mas sospechoso)"
echo "Revisa los .qa.log de HEM si algun archivo reporta problemas > 0."
