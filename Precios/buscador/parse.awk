# Parser de listas de precios HEM MOVIL (texto extraído con pdftotext -table)
# Geometría por "chunk" (segmento entre encabezados de columna / saltos de página).
# Uso: LC_ALL=C gawk -v SECTIONS="SEC1|SEC2" -f parse.awk archivo.txt > items.jsonl 2> qa.log
BEGIN {
  ns = split(SECTIONS, sa, "|"); for (i=1;i<=ns;i++) SEC[sa[i]] = 1
  QUAL = "^(ORI|INCELL|OLED|AMOLED|AAAA|TW|COPY|TOP|TFT|COG|COF|GX|ZY)"
  nc = split("NEGRO BLANCO AZUL ROJO VERDE DORADO MORADO ROSADO AMARILLO GRIS SLIVER SILVER CELESTE NARANJA MARRON MARRÓN TORNASOL FUSIA FUCSIA VIOLETA ROSA PLATEADO TITANIO GRAFITO VINO TURQUESA", ca, " ")
  for (i=1;i<=nc;i++) COLORV[ca[i]] = 1
  nl = 0; np = 1
  # Tope de precio plausible. Debe coincidir con el de validar_jsonl.awk y
  # parse_bbb.awk; se centraliza desde actualizar.sh con MAX_PRECIO.
  MAX_PRICE = (MAX_PRICE == "" ? 500 : MAX_PRICE + 0)
}
function squeeze(s) { gsub(/[ \t]+/, " ", s); gsub(/^ | $/, "", s); return s }
function jesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
# índice de byte hasta la columna visual dcol (CJK ocupa 2 columnas, 3 bytes)
function bytecol(line, dcol,   i, w, n2, ch) {
  i = 1; w = 0; n2 = length(line)
  while (i <= n2 && w < dcol) {
    ch = substr(line, i, 1)
    if (ch >= "\360") { i += 4; w += 2 }
    else if (ch >= "\340") { i += 3; w += 2 }
    else if (ch >= "\300") { i += 2; w += 1 }
    else { i += 1; w += 1 }
  }
  return i - 1
}
function isqualtok(t) { return toupper(t) ~ QUAL }
function iscolortok(t,   u2, k2) {
  u2 = toupper(t)
  if (u2 in COLORV) return 1
  for (k2 = 4; k2 <= length(u2) - 4; k2++)
    if ((substr(u2, 1, k2) in COLORV) && (substr(u2, k2 + 1) in COLORV)) return 1
  return 0
}
function unbal(s) { return gsub(/\(/, "(", s) - gsub(/\)/, ")", s) }

{
  gsub(/\r/, "")
  n = split($0, parts, "\f")
  for (k = 1; k <= n; k++) {
    if (k > 1) np++
    nl++; L[nl] = parts[k]; PG[nl] = np
  }
}

END {
  # ---- pasada 1: chunks y geometría ----
  ch = 1; segCols = 0; segHdr = -1
  for (i = 1; i <= nl; i++) {
    line = L[i]
    if (i > 1 && PG[i] != PG[i-1]) { ch++; chunkCols[ch] = segCols; chunkHdr[ch] = segHdr }
    if (line ~ /MODELO/ && line ~ /PRECIO/) {
      m1 = index(line, "MODELO")
      if (index(substr(line, m1 + 6), "MODELO") > 0) {
        segCols = 2
        p1 = index(substr(line, m1), "PRECIO") + m1 - 1
        segHdr = p1 + 5
      } else { segCols = 1; segHdr = -1 }
      ch++; chunkCols[ch] = segCols; chunkHdr[ch] = segHdr
      CHOF[i] = ch; ISHDR[i] = 1
      continue
    }
    if (!(ch in chunkCols)) { chunkCols[ch] = segCols; chunkHdr[ch] = segHdr }
    CHOF[i] = ch
    s = squeeze(line)
    if (s == "" || s ~ /\.\.\.\./ || s ~ /WHATSAPP|WECHAT|^HEM/ || (toupper(s) in SEC)) continue
    # votos: runs de >=2 espacios seguidos de no-dígito (inicio col. derecha)
    rest2 = line; off = 0
    while (match(rest2, /   */)) {
      rs = off + RSTART
      nxt = substr(rest2, RSTART + RLENGTH, 1)
      re = off + RSTART + RLENGTH - 1
      off += RSTART + RLENGTH - 1
      rest2 = substr(rest2, RSTART + RLENGTH)
      if (nxt != "" && nxt !~ /[0-9]/ && nxt != "-" && rs > 8) {
        nruns[ch]++; runS[ch, nruns[ch]] = rs; runE[ch, nruns[ch]] = re
      }
    }
  }
  nch = ch
  prevSplit = -1
  for (c = 1; c <= nch; c++) {
    chunkSplit[c] = -1
    if (chunkCols[c] == 2) {
      delete cov; best = 0
      for (j = 1; j <= nruns[c]; j++)
        for (x = runS[c, j]; x <= runE[c, j]; x++) { cov[x]++; if (cov[x] > best) best = cov[x] }
      if (best >= 3) {
        # bloque contiguo más ancho de posiciones con cobertura máxima
        blo = 0; bhi = 0; lo = 0
        for (x = 1; x <= 301; x++) {
          if (x <= 300 && cov[x] == best) { if (!lo) lo = x }
          else if (lo) { if (x - lo > bhi - blo + 1) { blo = lo; bhi = x - 1 } ; lo = 0 }
        }
        chunkSplit[c] = int((blo + bhi) / 2)
      } else if (chunkHdr[c] > 0) chunkSplit[c] = chunkHdr[c]
      else if (prevSplit > 0) chunkSplit[c] = prevSplit
      prevSplit = chunkSplit[c]
      printf "META GEOM chunk %d: cols=2 split=%d (votos=%d)\n", c, chunkSplit[c], best > "/dev/stderr"
    }
  }
  # ---- pasada 2 ----
  curSec = ""; memoria = 0; ne = 0; rbase = -1; lastCh = 0
  for (i = 1; i <= nl; i++) {
    line = L[i]; CURLN = i
    if (CHOF[i] != lastCh) { lastCh = CHOF[i]; rbase = -1 }
    if (ISHDR[i]) { flushall(1); continue }
    split2 = chunkSplit[CHOF[i]]
    s = squeeze(line)
    if (s == "") continue
    if (s ~ /^HEM ?MOVIL/) continue
    if (s ~ /^FECHA DE ACTUALIZACION/) { split(s, fa, ": *"); printf "META FECHA %s\n", fa[2] > "/dev/stderr"; continue }
    if (s ~ /WHATSAPP|WECHAT/) continue
    if (s == "Contenido") continue
    if (s ~ /\.\.\.\./) continue
    u = toupper(s)
    if (u in SEC) { flushall(1); curSec = u; memoria = (u ~ /MEMORIA/); secFresh = 1; printf "META SECCION L%d: %s\n", i, u > "/dev/stderr"; continue }
    if (secFresh && s ~ /^\(/) { printf "META NOTA %s: %s\n", curSec, s > "/dev/stderr"; secFresh = 0; continue }
    if (s !~ /MODELO/) secFresh = 0
    if (s ~ /^LISTA DE PRECIO/) continue
    if (memoria && u ~ /^USB +MICRO$/) continue
    if (curSec == "") { printf "L%d: FUERA DE SECCION [%s]\n", i, s > "/dev/stderr"; continue }
    # Esta tabla muy corta no aporta votos suficientes y el encabezado deja el
    # corte dentro de "IPH". La segunda columna comienza en la 31.
    if (curSec == "FLEX CABLE ALTAVOZ" && split2 > 0) split2 = 30
    CURSPLIT = split2
    if (split2 > 0) {
      bc = bytecol(line, split2)
      half(0, substr(line, 1, bc))
      half(1, substr(line, bc + 1))
    } else half(0, line)
  }
  flushall(1)
  for (j = 1; j <= ne; j++) {
    if (eBad[j]) continue
    printf "{\"sec\":\"%s\",\"modelo\":\"%s\",\"calidad\":\"%s\",\"colores\":\"%s\",\"precio\":%s}\n", \
      jesc(eSec[j]), jesc(squeeze(eMod[j])), jesc(squeeze(eQual[j])), jesc(squeeze(eCol[j])), ePrec[j]
  }
}

function cursecfor(col) {
  if (memoria) return (col == 0 ? "MEMORIA USB" : "MEMORIA MICRO SD")
  return curSec
}
function emit(col,   m, q, c, p) {
  m = squeeze(model[col]); q = squeeze(qual[col]); c = squeeze(colors[col]); p = price[col]
  if (m == "" && q == "" && c == "") { clearcol(col); return }
  ne++
  eSec[ne] = cursecfor(col); eMod[ne] = m; eQual[ne] = q; eCol[ne] = c; ePrec[ne] = p; eBad[ne] = 0
  if (m == "") { eBad[ne] = 1; printf "L%d: DESCARTADO sin modelo (cal=%s col=%s p=%s)\n", CURLN, q, c, p > "/dev/stderr" }
  else if (p == "") { eBad[ne] = 1; printf "L%d: SIN PRECIO: [%s] sec=%s\n", CURLN, m, cursecfor(col) > "/dev/stderr" }
  else if (p + 0 <= 0 || p + 0 > MAX_PRICE) { eBad[ne] = 1; printf "L%d: PRECIO RARO %s: [%s]\n", CURLN, p, m > "/dev/stderr" }
  lastIdx[col] = ne
  clearcol(col)
}
function clearcol(col) { model[col]=""; qual[col]=""; colors[col]=""; price[col]=""; open[col]=0 }
# annexMode: si una entrada abierta sin precio es solo-modelo, anexarla a la última cerrada
function flushcol(col, annexMode,   m) {
  if (!open[col]) return
  m = squeeze(model[col])
  if (annexMode && price[col] == "" && m != "" && squeeze(qual[col]) == "" && squeeze(colors[col]) == "" && lastIdx[col] > 0) {
    eMod[lastIdx[col]] = eMod[lastIdx[col]] (eMod[lastIdx[col]] ~ /[\/(]$/ || m ~ /^\// ? "" : " ") m
    printf "L%d: ANEXADO(flush) a cerrada: [%s]\n", CURLN, eMod[lastIdx[col]] > "/dev/stderr"
    clearcol(col)
    return
  }
  emit(col)
}
function flushall(annexMode) { flushcol(0, annexMode); flushcol(1, annexMode); lastIdx[0]=0; lastIdx[1]=0 }

function classify(col, text, isnew,   n, t, i2, tok, phase, parenbal, parenbuf, parendest) {
  n = split(text, t, / +/)
  phase = isnew ? "model" : "cont"
  parenbal = 0; parenbuf = ""; parendest = ""
  for (i2 = 1; i2 <= n; i2++) {
    tok = t[i2]
    if (tok == "-" || tok == "COLOR") continue
    if (parenbal > 0) {
      parenbuf = parenbuf " " tok
      parenbal += unbal(tok)
      if (parenbal <= 0) { if (parendest == "q") qual[col] = qual[col] " " parenbuf; else model[col] = model[col] " " parenbuf; parenbal = 0 }
      continue
    }
    if (tok ~ /^\(/ && !isqualtok(tok)) {
      parenbal = unbal(tok)
      parendest = (tok ~ /CON|COMPLETO|BATERIA|MARCO/ || squeeze(qual[col]) != "") ? "q" : "m"
      if (parenbal <= 0) { if (parendest == "q") qual[col] = qual[col] " " tok; else model[col] = model[col] " " tok; parenbal = 0 }
      else parenbuf = tok
      continue
    }
    if (isqualtok(tok) && (phase != "model" || i2 > 1)) { qual[col] = qual[col] " " tok; phase = "qual"; continue }
    if (iscolortok(tok) && (phase != "model" || i2 > 1)) { colors[col] = colors[col] " " tok; phase = "color"; continue }
    if (phase == "qual" && tok !~ /\//) { qual[col] = qual[col] " " tok }
    else model[col] = model[col] " " tok
  }
}

function half(col, text,   s2, ind, hasprice, pval, rest, base, margin, li, n3, t3, i3, allq, allc, anytok) {
  sub(/[ \t]+$/, "", text)
  s2 = squeeze(text)
  if (s2 == "" || s2 == "-" || s2 == "- -") return
  match(text, /[^ ]/); ind = RSTART - 1
  hasprice = 0; pval = ""
  if (match(text, /   *[0-9]+(\.[0-9]+)?$/) || match(text, / +[0-9]+\.[0-9]+$/)) {
    pval = substr(text, RSTART); gsub(/ /, "", pval)
    if (pval !~ /\./ && length(pval) >= 4) { rest = text; hasprice = 0; pval = "" }  # año en modelo, no precio
    else { rest = substr(text, 1, RSTART - 1); hasprice = 1 }
  } else rest = text
  rest = squeeze(rest)
  if (s2 ~ /^[0-9]+(\.[0-9]+)?$/) {
    if (open[col]) { price[col] = s2; emit(col) }
    else { pendingPrice[col] = s2; pendingText[col] = ""; printf "META PRECIO ANTES DE MODELO L%d: %s\n", CURLN, s2 > "/dev/stderr" }
    return
  }
  if (col == 0) base = 0; else { if (rbase < 0 || ind < rbase) rbase = ind; base = rbase }
  margin = (ind <= base + 3)
  li = lastIdx[col]
  # composición de tokens (para reglas de anexado)
  n3 = split(rest, t3, / +/); allq = (n3 > 0); allc = (n3 > 0); anytok = 0; anyqc = 0
  for (i3 = 1; i3 <= n3; i3++) { if (t3[i3] == "-") continue; anytok++; if (!isqualtok(t3[i3])) allq = 0; else anyqc = 1; if (!iscolortok(t3[i3])) allc = 0; else anyqc = 1 }
  # Algunas extracciones -layout colocan precio/colores una linea antes del
  # modelo. Se conserva temporalmente y se completa con la siguiente linea.
  if (!open[col] && pendingPrice[col] != "" && !hasprice && rest != "") {
    classify(col, rest, 1)
    if (pendingText[col] != "") colors[col] = pendingText[col]
    price[col] = pendingPrice[col]; pendingPrice[col] = ""; pendingText[col] = ""; emit(col)
    return
  }
  if (margin) {
    if (open[col]) {
      if (rest != "") classify(col, rest, 0)
      if (hasprice) { price[col] = pval; emit(col) }
    } else if (li > 0 && eMod[li] ~ /[\/(]$/ && !hasprice && rest != "") {
      eMod[li] = eMod[li] rest
      printf "L%d: ANEXADO a cerrada: [%s]\n", CURLN, eMod[li] > "/dev/stderr"
    } else if (li > 0 && !hasprice && rest ~ /^[\/(]/) {
      eMod[li] = eMod[li] (rest ~ /^\// ? "" : " ") rest
      printf "L%d: ANEXADO(paren/slash) a cerrada: [%s]\n", CURLN, eMod[li] > "/dev/stderr"
    } else if (li > 0 && !hasprice && allq) {
      eQual[li] = eQual[li] " " rest
      printf "L%d: ANEXADO(calidad) a cerrada: [%s] + [%s]\n", CURLN, eMod[li], rest > "/dev/stderr"
    } else if (li > 0 && !hasprice && CURSPLIT <= 0 && squeeze(eQual[li]) != "" && anytok > 0 && !anyqc) {
      eMod[li] = eMod[li] (eMod[li] ~ /[\/(]$/ || rest ~ /^\// ? "" : " ") rest
      printf "L%d: ANEXADO(1col) a cerrada: [%s]\n", CURLN, eMod[li] > "/dev/stderr"
    } else if (li > 0 && !hasprice && anytok > 0 && anytok <= 2 && !allc && rest !~ /[0-9]$/ ) {
      eMod[li] = eMod[li] " " rest
      printf "L%d: ANEXADO(corto) a cerrada: [%s]\n", CURLN, eMod[li] > "/dev/stderr"
    } else {
      classify(col, rest, 1)
      if (hasprice) { price[col] = pval; emit(col) } else open[col] = 1
    }
  } else {
    if (!open[col] && hasprice && allc) {
      pendingPrice[col] = pval; pendingText[col] = rest
      printf "META COLORES/PRECIO ANTES DE MODELO L%d: [%s] p=%s\n", CURLN, rest, pval > "/dev/stderr"
    } else if (open[col]) {
      classify(col, rest, 0)
      if (hasprice) { price[col] = pval; emit(col) }
    } else if (li > 0 && unbal(eQual[li]) > 0) {
      eQual[li] = eQual[li] " " rest
      printf "L%d: ANEXADO(paren-cal) a cerrada: [%s]\n", CURLN, eQual[li] > "/dev/stderr"
    } else if (li > 0 && unbal(eMod[li]) > 0) {
      eMod[li] = eMod[li] " " rest
      printf "L%d: ANEXADO(paren-mod) a cerrada: [%s]\n", CURLN, eMod[li] > "/dev/stderr"
    } else if (li > 0 && (rest ~ /^\(/ || allq)) {
      if (rest ~ /CON|COMPLETO|BATERIA|MARCO/ || allq || squeeze(eQual[li]) != "") eQual[li] = eQual[li] " " rest
      else eMod[li] = eMod[li] " " rest
      if (hasprice) printf "L%d: CONT-CERRADA con precio %s descartado [%s]\n", CURLN, pval, rest > "/dev/stderr"
      else printf "L%d: ANEXADO(indent) a cerrada: [%s] + [%s]\n", CURLN, eMod[li], rest > "/dev/stderr"
    } else if (li > 0 && allc && !hasprice) {
      eCol[li] = eCol[li] " " rest
      printf "L%d: ANEXADO(color) a cerrada: [%s] + [%s]\n", CURLN, eMod[li], rest > "/dev/stderr"
    } else if (li > 0 && rest ~ /^\//) {
      eMod[li] = eMod[li] rest
      printf "L%d: ANEXADO(indent-slash): [%s]\n", CURLN, eMod[li] > "/dev/stderr"
    } else {
      printf "L%d: HUERFANA INDENTADA [%s]%s\n", CURLN, rest, (hasprice ? " p=" pval : "") > "/dev/stderr"
    }
  }
}
