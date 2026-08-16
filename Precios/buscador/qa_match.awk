# Revision de los emparejamientos entre distribuidores.
#
# La app cruza repuestos de distintos distribuidores por "clave de equipo"
# (deviceKeys en app_template.html) y muestra cuanto se ahorra comprando en uno
# u otro. Un cruce equivocado hace que la app anuncie un ahorro que no existe,
# que es el error mas caro que puede cometer. Este script reproduce esa logica
# y saca los cruces ordenados por diferencia de precio: los casos raros casi
# siempre estan arriba, asi que revisando las primeras lineas a mano se gana
# confianza sobre los miles restantes.
#
# Uso: LC_ALL=C gawk -v TIPO=pantalla -f qa_match.awk \
#        dist=HEM sec="PANTALLA COMPLETA|PANTALLA SOLA" hem.jsonl \
#        dist=BBB sec="PANTALLA"                        bbb.jsonl
# (los pares dist=/sec= aplican al archivo que les sigue)

BEGIN {
  CAL = "^(ORI|ORG|ORIGINAL|INCELL|INCEL|OLED|AMOLED|AAAA|AAA|AA|TW|COPY|TOP|TFT|COG|COF|GX|ZY|JK|YK|JH|RJ|GAGETJH|GAGEJH|DIAG|SOFT|DD|MX|BIS|BISEL|CONBIS|CONBISEL)$"
  RUIDO = "^(LCD|BAT|BATERIA|BATERIAS|FLEX|CARGA|POWER|INTER|INTERCONEXION|PIN|DE|PARA|TAPA|TAPAS|TOUCH|PUNTA|CAUT|CAUTIN|REP|REPUESTO|MENBRANA|SAM|SAMSUNG|XIA|XIAOMI|HUA|HUAWEI|APP|W|CON|MARCO|COMPLETO|INTERNA|CAJA|BLANCA|FACE|ID|SERIE|HUELLA|AURICULAR|AURICULA|ANTENA|BUZZER|TIMBRE|ALTAVOZ|VIDRIO|VIDRIOS|CAMARA|CAMARAS|BANDEJA|SIM|PLACA|BOTON|FISICO|FRONTAL|TRASERA|VOLUMEN|VULUMEN|VOLUME|HOME|MOTOR|LENTE|SOLO|SET|SENAL|SEÑAL|AA|GX|JK|JH|GAGETJH|GAGEJH|RJ|NUEVO|VESION|VERCION|VERSION|UNIVESAL|SURTIDO|VARIADO)$"
  COLOR = "^(NEGRO|NEGRA|NEG|BLANCO|BLANCA|AZUL|AZ|ROJO|RJO|VERDE|VD|DORADO|DORADA|MORADO|MORADA|ROSADO|ROSA|AMARILLO|GRIS|SILVER|SLIVER|CELESTE|CELETE|NARANJA|MARRON|MARRÓN|TORNASOL|FUSIA|FUCSIA|VIOLETA|PLATEADO|TITANIO|GRAFITO|VINO|TURQUESA|CREMA|LILA|BEIGE)$"
  na = split("RM:REDMI RED:REDMI REDMI:REDMI HON:HONOR IPHONE:IPH IPH:IPH IP:IPH MOTOROLA:MOTO", aa, " ")
  for (i = 1; i <= na; i++) { split(aa[i], kv, ":"); ALIAS[kv[1]] = kv[2] }
}

function jget(line, campo,   s) {          # extractor de campo JSON plano
  if (!match(line, "\"" campo "\":\"[^\"]*\"")) return ""
  s = substr(line, RSTART, RLENGTH); sub("\"" campo "\":\"", "", s); sub(/"$/, "", s)
  return s
}
function jnum(line, campo,   s) {
  if (!match(line, "\"" campo "\":[0-9.]+")) return ""
  s = substr(line, RSTART, RLENGTH); sub("\"" campo "\":", "", s)
  return s + 0
}

# Canonicaliza solo aliases conocidos. Una calidad desconocida conserva su
# texto, de modo que GX, YK, GAGETJH y SOFT DIAG nunca colapsen en la misma clave.
function cantok(t) {
  if (t == "ORI" || t == "ORG") return "ORIGINAL"
  if (t == "INCEL") return "INCELL"
  if (t == "AMOLED") return "OLED"
  if (t == "GAGEJH") return "GAGETJH"
  return t
}
function calkey(t,   u, n, a, i, out) {
  u = toupper(t); gsub(/[^A-Z0-9]+/, " ", u); gsub(/^ +| +$/, "", u)
  n = split(u, a, / +/); out = ""
  for (i = 1; i <= n; i++) if (a[i] != "") out = out (out ? " " : "") cantok(a[i])
  return out
}
# BBB y Canguro llevan la calidad dentro de la descripcion. Esta funcion extrae
# solo los indicadores que las funciones calBBB/calCanguro usan en la app.
function embeddedcal(t, dist_,   u, n, a, i, tok, out, prev, cm, sm, cb) {
  u = toupper(t)
  cm = (u ~ /(^| )C\/M( |$)|CON MARCO/); sm = (u ~ /(^| )S\/M( |$)|SIN MARCO/)
  cb = (u ~ /CON ?BIS(EL)?/)
  gsub(/[^A-Z0-9]+/, " ", u); n = split(u, a, / +/); out = ""
  for (i = 1; i <= n; i++) {
    tok = a[i]
    if (!(tok ~ CAL)) continue
    # CON/BISEL/MARCO se agregan como compuesto mas abajo.
    if (tok == "BIS" || tok == "BISEL" || tok == "CONBIS" || tok == "CONBISEL") continue
    tok = cantok(tok)
    if (index(" " out " ", " " tok " ") == 0) out = out (out ? " " : "") tok
  }
  if (cm) out = out (out ? " " : "") "CON MARCO"
  else if (sm) out = out (out ? " " : "") "SIN MARCO"
  else if (cb) out = out (out ? " " : "") "CON BISEL"
  return out
}

# Misma identidad de variante que variantKey() en la app. La seccion es parte
# de la clave para impedir cruces frontal/trasera, bandeja/lector, etc.
function variant(sc,   u) {
  u = toupper(sc)
  if (u == "PANTALLA" || u == "LCD" || u == "PANTALLA COMPLETA") return "completa"
  if (u == "PANTALLA SOLA") return "sola"
  if (u ~ /FLEX\(PLACA\) DE CARGA|FLEX DE CARGA/) return "flex-carga"
  if (u == "PIN DE CARGA") return "pin-carga"
  if (u ~ /CAMARA TRASERA/) return "trasera"
  if (u ~ /CAMARA FRONTAL/) return "frontal"
  if (u == "LENTE DE CAMARA") return "lente-camara"
  # El conector FPC de HEM y el flex de placa de Max Movil no son la misma pieza.
  if (u == "FPC DE PLACA") return "fpc-placa"
  if (u == "FLEX DE PLACA") return "flex-placa"
  if (u == "LECTOR DE CHIP") return "lector-chip"
  if (u == "BANDEJA DE CHIP") return "bandeja-chip"
  if (u == "LECTOR DE HUELLA") return "lector-huella"
  if (u == "FLEX DE HUELLA") return "flex-huella"
  if (u == "FLEX CABLE ALTAVOZ") return "flex-altavoz"
  if (u == "BUZZER/TIMBRE/ALTAVOZ") return "altavoz"
  if (u == "JACK AUDIO AURICULAR") return "jack-auricular"
  if (u == "FLEX DE AURICULAR") return "flex-auricular"
  if (u == "AURICULAR") return "auricular"
  if (u == "FLEX WIFI ANTENA") return "wifi-antena"
  if (u == "FPC DE ANTENA") return "fpc-antena"
  if (u == "CABLE ANTENA") return "cable-antena"
  if (u == "FLEX ANTENA SEÑAL") return "antena-senal"
  if (u == "FLEX DE POWER Y VOLUMEN") return "power-volumen"
  if (u == "BOTÓN FÍSICO DE POWER Y VOLUMEN" || u == "BOTON FISICO DE POWER Y VOLUMEN") return "boton-fisico"
  if (u == "FLEX DE POWER(ENCENDIDO)" || u == "FLEX DE POWER") return "flex-power"
  if (u == "FLEX DE VOLUMEN") return "flex-volumen"
  return u
}

# misma logica que deviceKeys() en la app
function claves(modelo, out,   s, np, partes, i, j, nt, toks, tok, ctx, nctx, k, n, redmiNote) {
  s = toupper(modelo)
  redmiNote = (s ~ /(^| )(XIAOMI|XIA|REDMI|RM|POCO)( |$)/)
  sub(/ \/ .*/, "", s)
  gsub(/\([^)]*\)/, " ", s)
  gsub(/(^| )(C\/M|S\/M)( |$)/, " ", s)
  gsub(/[^A-Z0-9\/+ .-]/, " ", s)
  np = split(s, partes, "/")
  n = 0; nctx = 0
  for (i = 1; i <= np; i++) {
    nt = split(partes[i], toks, /[ .]+/)
    delete cur; ncur = 0
    for (j = 1; j <= nt; j++) {
      tok = toks[j]; if (tok == "") continue
      if (tok in ALIAS) tok = ALIAS[tok]
      if (tok ~ CAL || tok ~ RUIDO || tok ~ COLOR) continue
      cur[++ncur] = tok
    }
    if (!ncur) continue
    # "A52 4G/5G": el fragmento suelto hereda el contexto del anterior
    if (i > 1 && ncur == 1 && nctx > 1 && cur[1] ~ /^[0-9]/) {
      for (j = nctx; j >= 1; j--) cur[j + 1] = cur[j]
      for (j = 1; j < nctx; j++) cur[j] = ctx[j]
      ncur = nctx
    }
    k = ""; for (j = 1; j <= ncur; j++) k = k (j > 1 ? " " : "") cur[j]
    if (k ~ /^NOTE [0-9]/) k = (redmiNote ? "REDMI" : "SAMSUNG") " " k
    nctx = ncur; for (j = 1; j <= ncur; j++) ctx[j] = cur[j]
    if (length(k) >= 2) out[++n] = k
  }
  return n
}

# Las secciones se comparan literales, no como regex: nombres como
# "FLEX(PLACA) DE CARGA" traen parentesis que un regex interpretaria como grupo.
FNR == 1 {
  CURDIST = dist
  delete SECOK; nsec = split(sec, sl, "|")
  for (si = 1; si <= nsec; si++) SECOK[sl[si]] = 1
  ANYSEC = (sec == "")
}

{
  sc = jget($0, "sec")
  if (!ANYSEC && !(sc in SECOK)) next
  mod = jget($0, "modelo"); pr = jnum($0, "precio")
  if (mod == "" || pr == "") next
  cal = jget($0, "calidad")
  ck = (cal != "" ? calkey(cal) : embeddedcal(mod, CURDIST))
  vk = variant(sc)

  delete ks; nk = claves(mod, ks)
  for (i = 1; i <= nk; i++) {
    g = vk "\t" ks[i] "\t" ck
    if (!((g SUBSEP CURDIST) in MINP) || pr < MINP[g, CURDIST]) {
      MINP[g, CURDIST] = pr; MINM[g, CURDIST] = mod
    }
    DISTS_[g, CURDIST] = 1
    GRUPOS[g] = 1
  }
  TOT[CURDIST]++
  DLIST[CURDIST] = 1
}

END {
  nd = 0; for (d in DLIST) DL[++nd] = d
  for (g in GRUPOS) {
    npres = 0; delete pres
    for (i = 1; i <= nd; i++) if ((g SUBSEP DL[i]) in DISTS_) pres[++npres] = DL[i]
    if (npres < 2) continue
    lo = ""; hi = ""
    for (i = 1; i <= npres; i++) {
      p = MINP[g, pres[i]]
      if (lo == "" || p < lo) { lo = p; lod = pres[i]; lom = MINM[g, pres[i]] }
      if (hi == "" || p > hi) { hi = p; hid = pres[i]; him = MINM[g, pres[i]] }
    }
    ncruces++
    if (lo <= 0) continue
    dif = hi - lo; pct = dif / lo * 100
    split(g, gg, "\t")
    printf "%7.1f%%  $%-7.2f dif   [%s]  cal=%-6s  %s $%.2f  <->  %s $%.2f  |  %s  ||  %s\n",
      pct, dif, gg[2], (gg[3] == "" ? "-" : gg[3]), lod, lo, hid, hi, lom, him
  }
  printf "\n=== %d cruces entre distribuidores ", ncruces > "/dev/stderr"
  for (i = 1; i <= nd; i++) printf "| %s: %d items ", DL[i], TOT[DL[i]] > "/dev/stderr"
  printf "\n" > "/dev/stderr"
}
