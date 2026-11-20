// Línea de tiempo del emparejamiento de la web a partir de un HAR guardado con DevTools (pestaña Red, «Save all as HAR»).
// Uso: node app/tool/har_pairing_timeline.mjs <fichero.har>
// Solo imprime segundos desde la primera petición, método, estado, ruta con los ids sustituidos (J, S), duración y,
// en /offer, /result y /checkpoint, los nombres de los campos y si vienen vacíos. Nunca imprime ids, nonces, claves ni
// cuerpos. El HAR sí los contiene: no lo subas a ningún sitio y bórralo al terminar.
import fs from "node:fs";

const h = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const es = h.log.entries.filter((e) => /sync\.gifthuddle\.app/.test(e.request.url));
if (es.length === 0) { console.log("No hay peticiones a sync.gifthuddle.app en el HAR."); process.exit(0); }
const t0 = Date.parse(es[0].startedDateTime);
const shape = (e) => {
  const txt = e.response.content?.text;
  if (!txt) return "";
  try {
    const j = JSON.parse(e.response.content.encoding === "base64" ? Buffer.from(txt, "base64").toString() : txt);
    return Object.entries(j).map(([k, v]) => `${k}=${v === null ? "null" : typeof v === "object" ? "{…}" : typeof v}`).join(" ");
  } catch { return ""; }
};
for (const e of es) {
  const u = new URL(e.request.url);
  const path = u.pathname.replace(/\/v2\/invites\/[^/]+/, "/v2/invites/J").replace(/\/v2\/lists\/[^/]+/, "/v2/lists/S");
  const last = path.split("/").pop();
  const body = e.request.method === "GET" && ["offer", "result", "checkpoint"].includes(last) ? shape(e) : "";
  console.log(
    ((Date.parse(e.startedDateTime) - t0) / 1000).toFixed(2).padStart(7), e.request.method.padEnd(7),
    String(e.response.status).padEnd(4), (path + (u.search ? "?" + [...u.searchParams.keys()].join("&") : "")).padEnd(34),
    `${Math.round(e.time)} ms`.padStart(8), body,
  );
}
