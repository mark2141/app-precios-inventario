#!/usr/bin/env bash
# Verificaciones rápidas después de ejecutar actualizar.sh.
set -euo pipefail
export LC_ALL=C
DIR="$(cd "$(dirname "$0")" && pwd)"

if command -v gawk >/dev/null 2>&1; then AWK_BIN=gawk
elif command -v awk >/dev/null 2>&1; then AWK_BIN=awk
else echo "Falta awk/gawk" >&2; exit 1
fi

bash -n "$DIR/actualizar.sh"
"$AWK_BIN" -v SECTIONS=X -f "$DIR/parse.awk" /dev/null >/dev/null
"$AWK_BIN" -v SEC=X -f "$DIR/parse_bbb.awk" /dev/null /dev/null >/dev/null 2>&1
"$AWK_BIN" -f "$DIR/qa_match.awk" /dev/null >/dev/null 2>&1
"$AWK_BIN" -v ALLOW_EMPTY=1 -f "$DIR/validar_jsonl.awk" /dev/null >/dev/null 2>&1

# Cada PDF de Max Movil debe tener exactamente una entrada en el mapa, y el mapa
# no debe conservar archivos que ya no existen. Evita publicar inventarios
# parciales por un simple cambio de nombre.
MAP="$DIR/datos/bbb_map.txt"
[ -s "$MAP" ] || { echo "Mapa vacío o ausente: $MAP" >&2; exit 1; }
declare -A MAPEADOS
while IFS='|' read -r nombre seccion; do
  case "$nombre" in ''|'#'*) continue;; esac
  [ -n "$seccion" ] || { echo "Mapeo sin sección: $nombre" >&2; exit 1; }
  [ -z "${MAPEADOS[$nombre]:-}" ] || { echo "Mapeo repetido: $nombre" >&2; exit 1; }
  MAPEADOS["$nombre"]="$seccion"
done < "$MAP"
for pdf in "$DIR"/../pdfs-bbb/*.pdf; do
  [ -e "$pdf" ] || { echo "No hay PDF de Max Movil" >&2; exit 1; }
  nombre=$(basename "$pdf" .pdf)
  [ -n "${MAPEADOS[$nombre]:-}" ] || { echo "PDF de Max Movil sin mapeo: $nombre" >&2; exit 1; }
done
for nombre in "${!MAPEADOS[@]}"; do
  [ -f "$DIR/../pdfs-bbb/$nombre.pdf" ] || { echo "Mapeo sin PDF: $nombre" >&2; exit 1; }
done

for f in "$DIR"/datos/can_*.jsonl "$DIR"/.tmp/bat.jsonl "$DIR"/.tmp/pan.jsonl \
         "$DIR"/.tmp/car.jsonl "$DIR"/.tmp/flex.jsonl "$DIR"/.tmp/bbb/bbb.jsonl; do
  [ -s "$f" ] || { echo "Archivo vacío o ausente: $f" >&2; exit 1; }
  if command -v jq >/dev/null 2>&1; then jq -e . "$f" >/dev/null; fi
  check_id=0; check_dup=0
  case "$f" in
    */datos/can_*.jsonl) check_id=1;;
    */.tmp/bbb/bbb.jsonl) check_id=1; check_dup=1;;
  esac
  "$AWK_BIN" -v LABEL="$(basename "$f")" -v CHECK_ID="$check_id" \
    -v CHECK_SEMANTIC_DUP="$check_dup" -v MAX_PRICE="${MAX_PRECIO:-500}" \
    -f "$DIR/validar_jsonl.awk" "$f"
done

HEM_TOTAL=$(wc -l < "$DIR/.tmp/bat.jsonl")
HEM_TOTAL=$((HEM_TOTAL + $(wc -l < "$DIR/.tmp/pan.jsonl") + $(wc -l < "$DIR/.tmp/car.jsonl") + $(wc -l < "$DIR/.tmp/flex.jsonl")))
CAN_TOTAL=$(cat "$DIR"/datos/can_*.jsonl | wc -l)
BBB_TOTAL=$(wc -l < "$DIR/.tmp/bbb/bbb.jsonl")
[ "$HEM_TOTAL" -ge "${MIN_HEM_ITEMS:-5000}" ] || { echo "Caída anormal de HEM: $HEM_TOTAL items" >&2; exit 1; }
[ "$CAN_TOTAL" -ge "${MIN_CAN_ITEMS:-500}" ] || { echo "Caída anormal de Canguro: $CAN_TOTAL items" >&2; exit 1; }
[ "$BBB_TOTAL" -ge "${MIN_BBB_ITEMS:-3000}" ] || { echo "Caída anormal de Max Movil: $BBB_TOTAL items" >&2; exit 1; }

# Se respeta la misma valvula que actualizar.sh: si no, permitir un aviso alla
# solo trasladaria el bloqueo a aqui.
if [ "${PERMITIR_PROBLEMAS:-0}" = "1" ]; then
  echo "PERMITIR_PROBLEMAS=1: no se revisan los avisos de los parsers." >&2
else
  for f in "$DIR"/.tmp/{bat,pan,car,flex}.qa.log; do
    if grep -vE '(^META|ANEXADO|^$)' "$f" | grep -q .; then
      echo "El parser reportó problemas en $f" >&2; exit 1
    fi
  done
  for f in "$DIR"/.tmp/bbb/*.qa.log; do
    if grep -vE '(^META|SIN ESPACIADO|PRECIO CERO|^$)' "$f" | grep -q .; then
      echo "El parser reportó problemas en $f" >&2; exit 1
    fi
  done
fi

grep -q '<meta charset="utf-8">' "$DIR/buscador.html"
grep -q 'window.__PT_QA' "$DIR/buscador.html"
! grep -q '__LOGO__\|__ICON__\|//__DATA__' "$DIR/buscador.html"
! grep -Eqi '</?script' "$DIR/.tmp/data.js"
cmp -s "$DIR/buscador.html" "$DIR/../para-netlify/index.html"

echo "Verificación correcta: HEM=$HEM_TOTAL, Canguro=$CAN_TOTAL, Max Movil=$BBB_TOTAL."
echo "Abre la app y confirma window.__PT_QA.ok=true en la prueba de navegador."
