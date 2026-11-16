# ADR 0002 · Sincronización automática e invitaciones a distancia

Fecha: 2026-11-09. Estado: aceptada (se prioriza la sincronización). Amplía el ADR 0001, no lo sustituye: el QR en persona y los ficheros `.regalos` siguen funcionando.

## Objetivo
Que dos o más móviles de la misma familia vean los cambios casi al momento, sin cuentas y sin que el servidor pueda leer nada. Que se pueda invitar a alguien que no está delante.

## Piezas
- **Servidor:** Cloudflare Worker (`server/`, TypeScript, Hono opcional) con **un Durable Object por lista** (almacenamiento SQLite del DO, plan gratuito). Mientras no haya dominio se sirve en `*.workers.dev`; después, en `sync.gifthuddle.app`.
- **Cliente:** `app/lib/features/sync/` en la app, sobre `FamilyDoc` y `envelope.dart` (ADR 0001).

## Claves (todas nacen en el móvil)
- `familyKey` (32 bytes, ADR 0001). Nunca sale de los móviles salvo cifrada para otro móvil durante una invitación.
- `authKey = HKDF-SHA256(familyKey, salt = "gift-huddle", info = "sync-auth-v1", 32 bytes)`.
  - El servidor guarda solo `SHA-256(authKey)` como verificador y nunca recibe la `familyKey`.
  - Quien tiene la `familyKey` puede sincronizar; quien no la tiene no puede leer ni escribir.
- `listId`: el de ADR 0001. **No se usa en el servidor**: va en claro en la cabecera de los sobres `.regalos`, así que cualquiera que haya visto uno podría ocupar ese nombre (auditoría M1).
- `syncId = base64url(HKDF-SHA256(familyKey, salt = "gift-huddle", info = "sync-id-v1", 16 bytes))` (22 caracteres). Es el identificador de la lista en el servidor (URLs y nombre del Durable Object). Sin la clave no se puede calcular, ocupar ni consultar.

## API HTTP (JSON salvo indicación; todas con `Authorization: Bearer <base64url(authKey)>` salvo las de invitación marcadas)

| Método y ruta | Qué hace |
|---|---|
| `PUT /v1/lists/{syncId}` con cuerpo `{ "baseVersion": n \| null, "envelope": "<base64url>" }` | Primera subida (`baseVersion: null`): registra el verificador y guarda el sobre con `version: 1`. Si ya existe, exige el verificador correcto y que `baseVersion == version`. Si coincide, guarda con `version + 1`. Si no, responde **409** con `{ "version", "envelope" }` y el cliente fusiona y reintenta. |
| `GET /v1/lists/{syncId}` (cabecera opcional `If-None-Match: "<version>"`) | `200 { "version", "envelope" }` o `304`. |
| `GET /v1/lists/{syncId}/ws` | WebSocket (auth por `Sec-WebSocket-Protocol: bearer.<authKey>`). El servidor envía `{"type":"version","version":n}` cada vez que cambia. El cliente no envía datos por aquí, solo lee. Hibernación de WebSocket del DO para que no cueste en reposo. |
| `DELETE /v1/lists/{syncId}` | Borra la lista y sus invitaciones del servidor (desde Ajustes, «Dejar de sincronizar»). |

- **Límites:**
  - sobre ≤ 2 MiB, igual que `kMaxEnvelopeBytes`;
  - cuerpo JSON ≤ 3 MiB;
  - como mucho 60 escrituras por minuto y lista, y 30 peticiones por minuto e IP a las rutas de invitación; con 429 al pasarse;
  - el verificador se compara en tiempo constante.
- **El servidor nunca descifra.** Guarda un único sobre, el último, y no fusiona: la fusión la hace el cliente (CRDT de ADR 0001). Con `409` y reintento no se pierde nada.
- **Caducidad:** cada acceso actualiza `lastAccess`. Una alarma del DO borra todo si pasan **400 días** sin acceso. Los móviles conservan la lista completa y la vuelven a subir si hace falta (un `GET` con 404 → `PUT` con `baseVersion: null`).

## Invitaciones a distancia (con aprobación y código comparado ANTES de entregar la clave)
1. **A crea la invitación:** `POST /v1/lists/{syncId}/invites` (auth) → `{ inviteId, expiresAt }` (16 bytes aleatorios, 24 h, un solo uso, máx. 10 abiertas). A comparte `https://<host>/i#<inviteId>`: el enlace **no** lleva ninguna clave.
2. **B pide entrar:** genera un par X25519 efímero y hace `POST /v1/invites/{inviteId}/join` **sin auth** con `{ publicKey: B, deviceName }`. Solo cabe una petición por invitación; la segunda recibe 409.
3. **A ofrece su clave pública:** ve la petición (por WebSocket `{"type":"join-request"}` o con `GET /v1/lists/{syncId}/invites/{inviteId}`, con auth), genera su par X25519 efímero y hace `POST /v1/lists/{syncId}/invites/{inviteId}/offer {publicKeyA}` (auth).
4. **Los dos ven el código:** B consulta `GET /v1/invites/{inviteId}/result` (cabecera `X-Public-Key: B`), que responde `202 {status:"pending", publicKeyA}` en cuanto existe la oferta. Los dos móviles muestran el **mismo código de 6 cifras**: `HKDF(publicKeyA ‖ publicKeyB, info = "gift-huddle-verify-v1")` → 20 bits → 6 dígitos. Las personas los comparan (por teléfono o mensaje) y **A confirma solo si coinciden**.
5. **A entrega la clave:** cifra `{listId, familyKey, deviceNameA}` con X25519 → HKDF → AES-256-GCM y hace `POST …/approve { ciphertext, nonce }` (auth). El servidor solo lo acepta si existe la oferta del paso 3 (la `publicKeyA` no se puede cambiar después).
6. **B recoge:** `result` responde `200 { ciphertext, nonce }`. B descifra, rechaza si el secreto compartido sale todo ceros (clave de orden bajo), guarda la clave y descarga la lista. El servidor borra la invitación.
- Rechazar (`POST …/reject`) o caducar mata la invitación. Cualquier fallo de `result` devuelve el mismo 404. `result` se consulta cada 4 s o más, respetando `Retry-After`.
- **Por qué es seguro:** el enlace solo sirve para pedir entrada. La clave solo sale tras la confirmación humana del código, que se calcula sobre las dos claves públicas: si el servidor, o alguien con el enlace, cambia cualquiera de las dos, los códigos no coinciden.
- **No hay revocación todavía en v1** (auditoría L4): un móvil perdido conserva el acceso. La salida, por entonces, era crear una lista nueva. v1 quedó retirada: `/v1/` responde `410 Gone`; la revocación llegó con v2 (credencial por móvil, ADR 0004). Una rotación de clave con auth queda pendiente para después de Navidad.

## Cliente
- **Cuándo sincroniza:**
  - al arrancar, al volver a primer plano y tras cada cambio local (con un retardo de 2 s para agrupar);
  - con el WebSocket abierto mientras la app está en primer plano;
  - sin red, guarda en local y reintenta con espera creciente. Nada bloquea la interfaz.
- **Ciclo de subida:**
  1. `GET` (con `If-None-Match`);
  2. si hay versión nueva: `open` → `merge` → `clock.receive` (captura `HlcDriftException`);
  3. `PUT` con `baseVersion`;
  4. con `409`, fusiona lo que devuelve y reintenta, hasta 3 veces.
- **Estado visible en Ajustes › Sincronización:** «Sincronizado hace 1 min», «Sin conexión, se enviará luego» o «Error».
- **Activación:** encendida por defecto al crear la familia o unirse; se puede apagar. El fichero `.regalos` sigue disponible.
- **Con un solo móvil no se habla con el servidor** (2026-11-12, decisión de producto). Hasta que la familia tiene un segundo móvil emparejado (`FamilyIdentity.paired`) no se sube nada ni se abre el WebSocket; Ajustes › Sincronización dice «Empezará cuando emparejes otro móvil». Los móviles que ya estaban emparejados siguen igual. Solo hay dos salvedades, las dos para conectar a ese segundo móvil:
  - **Invitación:** crear una invitación sube la lista una vez (el servidor la necesita para crearla) y quien invita escucha la petición. Lo que se edite después no sube hasta que alguien entra. Al dar acceso, quien invita queda emparejado y empieza a sincronizar. Si la invitación caduca, se rechaza, se cancela o no llega a crearse sin que nadie haya entrado, quien invitó borra del servidor esa copia. Antes mira, con un `GET` condicional, si otro móvil ha escrito ya en la lista: entonces no la borra, queda emparejado y sincroniza. Que la copia sobra queda apuntado en el móvil desde antes de subirla hasta que se borra, así que si el `DELETE` falla, o la invitación caducó con la app cerrada, se reintenta al arrancar y al volver a la app (revisión de seguridad del 2026-11-12, N7 y N8).
  - **QR:** el QR no avisa de que lo han leído. Quien lo enseña mira, solo con `GET` y sin subir nada, si el otro móvil ya ha subido su primera copia: cada 12 s durante 10 minutos, solo con la app delante, y, después, al arrancar, al volver a la app y tras un cambio local, hasta 3 días desde que se enseñó (pasado ese plazo, la marca de que se enseñó se borra del móvil). Si una de esas consultas falla (sin red, `5xx`, `429`) no hay reintentos con espera creciente ni nada en segundo plano: el estado sigue en «Empezará cuando emparejes otro móvil» y se mira en la siguiente. Al ver esa copia queda emparejado, lo dice con el aviso «Se ha conectado otro móvil» y empieza a sincronizar. Quien lee el QR queda emparejado al momento y sube.
  - Recibir un fichero `.regalos` de otro móvil también empareja y arranca la sincronización.
- **Host configurable:** por defecto `kSyncHost` = `https://sync.gifthuddle.app` y las invitaciones en `https://gifthuddle.app/i#<id>` (App Links con `autoVerify` en Android y `applinks:` en iOS; `web/public/.well-known/`). Se cambian con `--dart-define=SYNC_API_ORIGIN`/`SYNC_HOST` y `SYNC_INVITATION_ORIGIN` (2026-11-12, fase 2b).

## v2 (ADR 0004, fase 2b, 2026-11-12)
Este ADR describe v1. Desde la fase 2b la app habla v2 en cuanto una familia vuelve a conectar sus móviles (ADR 0004, «Fase 2b en la app»): credencial por móvil en lugar de `authKey`, `syncId` aleatorio, instantánea atómica con slots aparte, `If-Match`/ETag y revocación. Lo que cambia de este documento:
- **Emparejar:** el QR «Está aquí» ya no lleva la clave de la familia: lleva el mismo enlace de invitación que «Está lejos», y en los dos casos se compara un código de seis cifras en las dos pantallas (compromiso y revelación). La clave de la familia llega cifrada para la clave persistente del invitado.
- **«Dejar de sincronizar»:** con más móviles en la familia, este móvil **sale de la familia** (revoca su credencial y deja la lista a los demás); solo se borra la lista entera si es el último con acceso (`DELETE` condicional). «Borrar todo» hace lo mismo: con otros móviles ya no borra la lista de todos, porque su `syncId` no vuelve y los dejaba sin salida (revisión de la fase 2b, hallazgo 2). Tras salir, o si la lista ya no está en el servidor, el móvil estrena una generación propia (`syncId`, clave y registro nuevos) y espera a volver a conectar otro móvil.
- **Un solo móvil** sigue sin hablar con el servidor, salvo mientras dura un emparejamiento.
- v1 se queda para los móviles que aún no han vuelto a conectarse y para migrar; su copia en el servidor se borra cuando todos los que escribieron en ella están en v2.

## Lo que cambia para el usuario y la privacidad
- La app pasa de «sin servidor» a «sin cuentas, con los datos cifrados de extremo a extremo». La ficha de tienda y la política de privacidad deben decirlo así.
- El servidor ve el `listId`, el tamaño del sobre, las horas de acceso, la IP y los nombres de dispositivo que viajan en las invitaciones (no los guarda tras usarlos). No ve nombres, regalos ni precios.

## Coste
Gratis dentro del plan gratuito de Workers y Durable Objects (unas 100.000 peticiones al día). Si se superan: el plan de pago de Workers (5 USD al mes).
