# Inventario de Repuestos PacificTech

Buscador estático de precios de HEM Móvil, Canguro y Max Movil.
No usa servidor, base de datos ni dependencias JavaScript: los datos se extraen
de las listas, se incrustan en un único HTML y se copian a `para-netlify/`.

Max Movil se identifica como `BBB` dentro del código: es la llave de los datos
(`const BBB=[...]`), de `pdfs-bbb/`, de los `.qa.log` y de `qa_match.awk`. El
nombre que se muestra en pantalla sale de `lbl` en la tabla `DISTS` de
`buscador/app_template.html`; para renombrar un distribuidor basta con cambiar
ahí, sin tocar los datos.

## Fuente canónica

El código mantenido está en `buscador/`. La carpeta
`InventarioRepuestos-PacificTech/` y el ZIP del mismo nombre son una exportación
anterior y no deben editarse ni publicarse como la versión actual.

## Dependencias

- Bash.
- `pdftotext` de Poppler.
- `gawk` o un `awk` moderno.
- Utilidades habituales: `grep`, `sed`, `sort`, `paste`, `date` y `wc`.

El script prefiere `gawk` y usa `awk` como alternativa. Se puede seleccionar un
binario explícitamente con `AWK_BIN=/ruta/al/awk bash actualizar.sh`.

## Actualizar el inventario

1. Reemplazar los PDF de HEM en esta carpeta.
2. Reemplazar o agregar los PDF de Max Movil en `pdfs-bbb/`. Todo nombre nuevo
   debe añadirse a `buscador/datos/bbb_map.txt`. La actualización se aborta si
   encuentra un PDF sin mapeo o un mapeo cuyo PDF ya no existe.
3. Actualizar los `buscador/datos/can_*.jsonl` cuando cambie Canguro, y escribir
   la fecha de esa captura en `buscador/datos/fecha_canguro.txt` (AAAA.MM.DD).
   Es un archivo aparte a propósito: la fecha de modificación de los `.jsonl`
   cambia al copiar o restaurar la carpeta y haría pasar por fresca una lista
   vieja.
4. Ejecutar:

   ```bash
   cd buscador
   bash actualizar.sh
   bash verificar.sh
   ```

5. Revisar los archivos `buscador/.tmp/*.qa.log` y, sobre todo,
   `buscador/.tmp/matches.qa.log`. Diferencias grandes de precio pueden indicar
   una coincidencia incorrecta aun cuando el proceso no reporte un error.
6. Publicar únicamente el contenido de `para-netlify/`.

`verificar.sh` también valida la estructura y los precios de todos los JSONL,
la unicidad de códigos/SKU, cantidades mínimas por proveedor y los reportes de
los parsers. Las cantidades mínimas pueden ajustarse con `MIN_HEM_ITEMS`,
`MIN_CAN_ITEMS` y `MIN_BBB_ITEMS` cuando exista un cambio legítimo grande.

## Reglas de comparación

Una comparación requiere coincidencia de:

- tipo de repuesto;
- variante exacta (por ejemplo, cámara frontal no equivale a trasera);
- modelo normalizado del equipo;
- calidad normalizada.

Solo se unifican aliases conocidos como `ORI`/`ORG`, `INCEL`/`INCELL` y
`AMOLED`/`OLED`. Otras calidades solo se comparan si sus textos coinciden. Para
calcular un ahorro primero se toma la oferta más barata de cada distribuidor;
por eso nunca se presenta como ahorro una diferencia interna de un proveedor.

Cuidado con los nombres que coinciden pero designan piezas distintas. El caso
conocido es la placa: el `FPC DE PLACA` de HEM es el conector que se suelda
(todos los modelos valen $0.75) y el `FLEX DE PLACA` de Max Movil es el flexible
de interconexión completo ($3 a $6). Son variantes separadas y no se cruzan.
Antes de mapear una sección nueva de Max Movil al nombre de una sección de HEM,
conviene comparar los precios: si un distribuidor cobra un precio plano y el
otro varía por modelo, casi siempre son piezas diferentes.

## Privacidad del despliegue

`robots.txt`, `noindex` y los encabezados de Netlify reducen la indexación y el
almacenamiento en caché, pero **no son autenticación**. Cualquier persona que
conozca la URL puede descargar los precios incrustados en el HTML. Si los costos
deben ser privados, el sitio debe publicarse detrás de control de acceso de
Netlify u otro proxy autenticado; no se debe confiar solamente en esta carpeta.
