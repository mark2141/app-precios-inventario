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

for f in "$DIR"/datos/can_*.jsonl "$DIR"/.tmp/bat.jsonl "$DIR"/.tmp/pan.jsonl \
         "$DIR"/.tmp/car.jsonl "$DIR"/.tmp/flex.jsonl "$DIR"/.tmp/bbb/bbb.jsonl; do
  [ -s "$f" ] || { echo "Archivo vacío o ausente: $f" >&2; exit 1; }
  if command -v jq >/dev/null 2>&1; then jq -e . "$f" >/dev/null; fi
done

grep -q '<meta charset="utf-8">' "$DIR/buscador.html"
grep -q 'window.__PT_QA' "$DIR/buscador.html"
! grep -q '__LOGO__\|__ICON__\|//__DATA__' "$DIR/buscador.html"
cmp -s "$DIR/buscador.html" "$DIR/../para-netlify/index.html"

echo "Verificación estática correcta. Abre la app y confirma window.__PT_QA.ok=true en la prueba de navegador."
