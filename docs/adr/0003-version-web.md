# ADR 0003 · Versión web

Fecha: 2026-11-11, rehecho el 2026-11-13 para v2. Estado: **propuesta C'**, cuarta versión tras tres pasadas de revisión de código (2026-11-13; todo lo que encontró, incorporado aquí), con las decisiones de producto del final. Amplía los ADR 0001, 0002 y 0004.

Nota de dominio (2026-11-15): la web pública y las invitaciones pasan a `https://gifthuddle.app`,
la web app a `https://web.gifthuddle.app` y la sincronización a `https://sync.gifthuddle.app`.
Los hosts antiguos de la prueba se retiran: ya no abren la app ni sincronizan.
CORS admite solo los dos orígenes web exactos `https://gifthuddle.app` y `https://web.gifthuddle.app`.
Las invitaciones solo usan `gifthuddle.app`; los QR web solo usan `web.gifthuddle.app`.
Las referencias de abajo usan los dominios vigentes.

## Requisitos de producto (2026-11-13)
- Apuntar y editar **regalos, personas y ocasiones** desde el ordenador, en paralelo a la fase 3 y sin poner en riesgo las tiendas.
- El navegador es **un dispositivo más** de la familia: se empareja **una vez** con un móvil y en «Móviles de la familia» se ve como **«Web»**, no como un móvil.
- Se desbloquea con **una frase o un PIN que elige el usuario**; lo ideal, el mismo PIN que el móvil (no se lee del móvil: se propone).
- La web **no gestiona dispositivos** (no aprueba, no revoca, no invita) y **nunca abre regalos de personas protegidas** ni publica uno en el documento común.

## Por qué ya no vale la opción C (web efímera)
Con v2, cada emparejamiento gasta una credencial, una ficha y avales de cupos compartidos con los móviles: 8 fichas al día por credencial, 16 por lista, 8 altas al día y 64 credenciales por generación, revocadas incluidas. Emparejar en cada visita agota la generación en unas semanas y obliga a tener el móvil a mano cada vez.

## Decisión: C' · identidad persistente en una caja cifrada, documento en memoria
- El navegador guarda en IndexedDB **una caja cifrada** con su identidad: `deviceId`, `DeviceKeys` (semillas Ed25519 y X25519), credencial de servicio, `syncId`, `familyKey`, raíces fijadas del registro (§3), personas bloqueadas, última instantánea y una cola de cambios sin subir.
- Al abrir la web se desbloquea la caja, se baja la instantánea v2 y el documento vive **solo en memoria**. Bloquear descarta la sesión; la caja se queda.
- Solo con conexión. Chrome, Edge y Firefox de escritorio; Safari si sale gratis.
- «Olvidar este ordenador» revoca su propia credencial, borra su guarda y la caja.

## Matriz de amenazas
| Quién | Qué tiene | Qué consigue | Qué lo limita |
|---|---|---|---|
| Ladrón del perfil del navegador | Caja, sal, `guardToken` | Nada sin el PIN | 10 intentos en línea; luego la guarda se suspende; el siguiente desbloqueo con fallos o tras `resume` rota la capacidad y anula la copia |
| Quien conoce `syncId` y `deviceId` (están en el registro) | Ids | Nada | Sin `guardToken` no gasta intentos ni sabe si la guarda existe |
| Worker o su base | `b`, verificador, registro, sobres | No descifra nada: no tiene la caja ni la sal | Puede negar el servicio u omitir los límites |
| Perfil y base del Worker a la vez | Todo lo anterior | Ataque al PIN sin conexión | Límite aceptado; OPRF/OPAQUE, más adelante |
| XSS o despliegue malicioso con la caja abierta | Lo que tiene la web abierta, incluida la `familyKey` | Leer y reescribir `common`; **puede publicar un regalo para una persona protegida** (el Worker no ve el contenido) | No puede aprobar, revocar, invitar, recibir `surpriseKey`, escribir slots ni cambiar registro o paquetes (Worker y registro); CSP, sin scripts externos |
| Un móvil comprometido | Lo mismo y más | Lo mismo y más | Revocación (ADR 0004) |

La regla «nunca publicar un regalo protegido» se garantiza en todos los caminos del **cliente honesto**. Frente a un XSS con la caja abierta no es una garantía criptográfica, igual que frente a un móvil comprometido. Hacerla criptográfica pediría otro protocolo de escritura; no entra.

Nunca se guardan ni se registran `A`, `a`, `b`, `prueba` ni `K`.

## 1. Desbloqueo: caja con guarda de intentos en el Worker
Un PIN corto sobre una caja que solo está en el navegador se rompe sin conexión. La caja necesita además un secreto `b` que guarda el Worker y que solo entrega a quien demuestra el PIN, con un límite de intentos.

**Derivación** (versión 1 de la caja, autenticada en su AAD):
- PIN de **6 cifras o más**, o una frase; UTF-8 tras normalizar a NFC.
- `A = PBKDF2-HMAC-SHA256(PIN, sal, 600.000 iteraciones, 32 bytes)` con WebCrypto; `sal` aleatoria de 16 bytes. Las iteraciones se miden en los navegadores del lote 0. Los parámetros leídos de la caja se acotan antes de calcular nada.
- `a = HKDF-SHA256(A, info "gift-huddle web vault-a v1")` y `prueba = HKDF-SHA256(A, info "gift-huddle web guard-proof v1")`.
- `K = HKDF-SHA256(a ‖ b, info "gift-huddle web vault v1")`.
- Todas las HKDF: sal vacía, salida de 32 bytes, `info` en UTF-8. `b`, `guardToken` y `prueba`: 32 bytes, base64url sin relleno en JSON. Los vectores de prueba fijan PIN, sal y salidas.
- Caja y cada entrada de la cola de cambios: AES-256-GCM con nonce nuevo de 96 bits en **cada escritura**. AAD con codificación canónica (la de `canonicalHeaderBytes`): versión, `syncId`, `deviceId`, versión de la guarda y tipo de entrada.
- En claro, junto a la caja: versión, `syncId`, `deviceId`, `sal`, parámetros, versión de la guarda y `guardToken` (32 bytes aleatorios, la capacidad de acceso a la guarda).

Dentro de la caja sellada se autentican un contador monótono y el hash canónico del mapa completo de entradas cifradas y de `marks`; cada escritura los actualiza en la misma transacción y cada lectura los verifica, rechazando cambios o cajas antiguas sin esta vinculación con un error de integridad. El contador también impide volver a una caja anterior durante la sesión; un retroceso de **todo** el almacén tras reiniciar requeriría un ancla externa para detectarse.

**Guarda en el Worker:** tabla propia dentro de `ListV2Object`, persistida en SQLite (no en memoria). Revocar la web, borrar la lista o retirar la generación la borran a la vez. Estado por web:
- `version` y, durante un cambio de PIN, `pendingVersion`;
- por versión: `SHA-256(guardToken)`, `SHA-256(prueba)` y `b`;
- `failures`, `failedSince`, `nextAttemptAt`, `suspended`, `mustRotate` y la barrera persistida de rotación tras un acierto.

Todo se comprueba y se escribe bajo el cerrojo del objeto. Presupuesto propio: los intentos no gastan las escrituras de la familia.

**Rutas** (`G = /v2/lists/{syncId}/guards/{deviceId}`):
| Ruta | Quién | Qué hace |
|---|---|---|
| `PUT G/prepare` `{version, tokenHash, verifier, secret}` | Credencial de esa web | Guarda una versión nueva como pendiente. `version` = actual + 1; solo una pendiente; la misma `version` con el mismo contenido es idempotente y con otro, `409` |
| `POST G/commit` `{version}` | Credencial de esa web | La pendiente pasa a ser la actual y la anterior se borra. Repetirlo con la ya actual: `200` |
| `POST G/open` `{proofs: [{version, guardToken, prueba}]}` | **Nadie** (la credencial está en la caja) | Ver abajo |
| `POST G/cancel` `{version}` | Credencial de esa web | Borra la versión pendiente (si no es esa, `200` igual); devuelve `{version}` actual (0 si no hay); la actual no cambia |
| `POST G/resume` | Credencial activa, rol `device`, **de esa lista** | Quita la suspensión y pone `failures` a 0, conserva `failedSince` y deja `mustRotate`; no crea guardas ni cambia secretos |

`open` (excepción a la autenticación en `v2-router`, con límite propio por IP de 30/min y el de la guarda):
- Un `guardToken` que no casa con ninguna versión, una guarda que no existe o una lista retirada: `404` uniforme, sin contar nada ni revelar contadores. Para la web, los tres significan «Este ordenador ya no está conectado».
- Antes de `nextAttemptAt` (un intento cada 2 s): `429` con `Retry-After`; no gasta intento.
- Suspendida: `423 guard_suspended`.
- `proofs` lleva una prueba por versión (la actual y, si hay cambio de PIN a medias, la pendiente), cada una con su sal, y **cuenta como un solo intento**. Si alguna casa (comparación de tiempo constante): `failures = 0` y devuelve `{version, b, failedSince, mustRotate}` de esa versión; `failedSince` cuenta los fallos desde el último acierto, incluidos los anteriores a `resume`, y se pone a 0 tras entregarlo.
- Si ninguna casa: `failures + 1`; `403 {error: "wrong_pin", left}`. Al décimo fallo seguido, `suspended = true` y `423`.

Con `mustRotate` o `failedSince > 0`, la web rota automáticamente con el mismo PIN recién escrito y sal, `guardToken` y `b` nuevos, recifrando caja y cola antes de abrir la sesión; si falla, queda bloqueada y lo reintenta al desbloquear. El acierto deja una barrera persistida (`409 guard_rotation_required`) hasta `prepare` + `commit` de una versión nueva: no admite lecturas ni escrituras de la familia; `open` conserva los mismos límites para recuperar tras un corte y `cancel` solo limpia pendientes sin levantar la barrera, y el token anterior da `404` tras el commit.

**Alta** (al terminar de emparejar; la credencial aún está en memoria):
1. La web genera `b`, `guardToken` y `sal`, y hace `PUT G/prepare` con la versión 1.
2. Escribe la caja en IndexedDB, cifrada con `K`, y espera a que la transacción termine.
3. `POST G/commit`.

Si se corta antes del paso 2, la identidad se pierde con la memoria: es un **alta abortada**. La web vuelve a empezar y el móvil enseña la web anterior como «Web (sin terminar)» para revocarla. Gasta una credencial, pero no deja nada abierto: sin caja nadie puede usar `b`. Si se corta entre el 2 y el 3, la caja abre con la versión pendiente y la web repite el `commit`.

**Cambio de PIN** (con la caja abierta):
1. En **una sola transacción** de IndexedDB, la web guarda junto al juego actual un juego pendiente: la caja **y toda la cola** cifradas con `K'` (de `b'`, `guardToken'` y `sal'` nuevos).
2. `PUT G/prepare` con la versión siguiente y luego `POST G/commit`.
3. En otra transacción, el juego pendiente pasa a ser el actual y se borra el viejo.

Al abrir, si hay juego pendiente, se mandan las pruebas de las dos versiones en el mismo `open` y se usa el juego de la versión que conteste el Worker. Si el Worker contesta la vieja, la web abre con ella, hace `POST G/cancel` de la pendiente (con la credencial que ya tiene) y solo entonces borra el juego pendiente local; luego se puede volver a cambiar. Si contesta la nueva, repite `POST G/commit` (idempotente) y solo después termina el paso 3. Nunca se sustituye el único secreto que funciona antes de tener el juego nuevo guardado.

Si un cambio falla, intenta `cancel` y borrar el pendiente local; si la limpieza falla o `cancel` indica que la versión nueva ya es actual, bloquea y conserva el juego necesario para recuperarlo en el próximo desbloqueo.

**Suspensión:** el ordenador no se borra ni se revoca. La web dice «Demasiados intentos. Desbloquéalo desde un móvil». En el móvil, la ficha «Web» tiene «Permitir desbloquear otra vez» (`POST G/resume`). Los errores de PIN nunca borran la caja.

**Errores separados:** `403 wrong_pin`, `423 guard_suspended`, `401` (credencial revocada, solo en rutas con credencial), `404` en `open` (guarda borrada, `guardToken` que no casa o lista retirada) y `410` (lista retirada, en las demás rutas). Solo `401`, `410`, `404` en `open` o la web en `revoked` de su vista (§3) dicen «Este ordenador ya no está conectado».

## 2. Tipo de dispositivo «web» en la ficha firmada
- `DeviceRecord` gana un campo opcional `k`, solo con el valor `"web"`, que entra en lo firmado **solo cuando está**. Las fichas de móvil conservan el mismo mensaje y el mismo resumen (vector de prueba). Un valor desconocido de `k` se rechaza.
- **El tipo es inmutable en la identidad aprobada.** Un `deviceId` con fichas de dos tipos distintos deja de resolverse, igual que con dos claves (ADR 0004, «un id con dos claves distintas»). Una ficha nueva sin `k`, firmada con las mismas claves de una web, no hereda nada: deja ese id ambiguo y fuera. Se aplica a la elección de la ficha actual, la resolución de firmantes, las anclas y `KnownDevice`. `changePerson` conserva el tipo.
- La identidad de firma es **`deviceId` + Ed25519**, independientemente de X25519: cambiar la clave de acuerdo no permite cambiar el tipo ni emitir declaraciones como móvil.
- **Desalojo del registro:** primero se calcula el enlace N1 (sin atravesar revocados). Las identidades no enlazadas se desalojan enteras, con sus fichas y evidencia, antes de quitar fichas enlazadas. Autofirmar un par móvil/web no reserva espacio. La ficha auténtica del ancla y la evidencia de revocaciones tienen prioridad, pero solo la de una revocación cuyo firmante y cuyo revocado se alcanzan por la cadena N1 (con las fichas de esas rutas): una revocación emitida por o dentro de una rama que solo cuelga de un revocado no reserva nada. Después, fuera del cupo ordinario de 16 fichas por id, se reserva primero una ficha (la más reciente), con su ruta, de cada identidad enlazada con marca o con tipos mezclados, y luego el segundo testigo de las que mezclan tipos; se mantiene el tope global de 64. La fusión descarta lo que sobra y nunca falla por espacio.
- **Memoria local del conflicto:** `DeviceRegistry.toLocalStoreJson` guarda `localTypeConflicts` por identidad de firma, y `FamilyStore` la conserva en el fichero cifrado y autenticado del registro. Se recuerda solo un conflicto observado con fichas verificadas en una identidad enlazada o en el propio ancla fijado localmente (aunque su conflicto impida iniciar la cadena). Es necesaria si una presión extrema de identidades avaladas supera incluso el espacio de los testigos: perder uno no puede rehabilitar la identidad al restaurar o reintroducir fichas. La marca bloquea resolución y autoridad, y permanece aunque después se pierda el enlace mientras la identidad conserve fichas. Tiene cota: como mucho una por identidad y 64 en total (primero las enlazadas con fichas, que nunca pasan de 64, así que una identidad enlazada en conflicto nunca se rehabilita; después el ancla, otras enlazadas y las que solo conservan fichas), y se podan las de identidades que ni están enlazadas ni conservan fichas. No es una declaración firmada: `toJson` la excluye y `fromJsonVerified` ignora cualquier marca recibida de la red. Solo `fromLocalStoreJson` la acepta del almacén local autenticado; los registros locales antiguos siguen siendo legibles.
- Una app anterior a este cambio rehace el mensaje sin `k`, la firma no le casa y descarta esa ficha y sus avales: no ve la web ni le manda nada. Es aceptable porque todos los móviles de prueba se actualizan.
- El tipo lo autoriza **el flujo del móvil** que empareja: «Conectar la web» exige `k == "web"` y el flujo normal rechaza una ficha con `k`. No hay prueba criptográfica de que unas claves salieran de un navegador.
- En «Móviles de la familia» (`share_screen.dart`, `family_device_rows.dart`, `device_sheets.dart`) una ficha `k = web` lleva el icono de ordenador y el texto «Web» con su persona. Se revoca como cualquier otro.

## 3. Capacidad restringida
**En el registro (`device_registry.dart`), sustituye a la W1 de la primera versión:**
- **W1. Ninguna declaración firmada por una web cuenta**, en ninguna vista, tampoco en la suya: ni avales ni revocaciones. Lo que no cuenta tampoco protege del desalojo (`_fit`), no suma época, no crea pendientes ni `detached`.
  W1 excluye avales y revocaciones; la **ficha** autofirmada de la web sí entra (es la que representa a la web y la que avalan los móviles).
- **W2. La web lee el registro como lo leería un móvil de confianza.** Un `RegistryView` necesita un ancla, que es solo pública (`RegistryAnchor`: `deviceId` y clave de firma). La web no se ancla en sí misma:
  - **Raíces fijadas:** al emparejar, la web guarda en la caja el ancla del anfitrión, autenticada en persona por el código. Tras cada instantánea coherente, la caja guarda como raíces los móviles activos de esa vista (nunca webs). Una raíz nueva solo entra así, derivada de una raíz que ya estaba, o con otro emparejamiento en persona. Un móvil inventado que avala la web no es raíz: nadie de la familia llega a él.
  - **Ancla en uso:** la primera raíz que no esté revocada. Como un móvil no acepta su propia revocación (ADR 0004), la web la mira aparte: si la vista anclada en esa raíz dice `revokedByOthers`, pasa a la siguiente raíz que siga activa en esa vista. El desalojo (`_fit`), la época, los pendientes y `detached` son los de la vista con esa ancla, sin cambios en su código.
  - **Confirmada:** la web está confirmada si su ficha actual está activa en esa vista. Revocada: si la vista la tiene en `revoked` (`revokedByOthers` es de la raíz y solo sirve para cambiar de ancla). Si su ficha deja de estar activa pero queda una raíz utilizable, queda «sin confirmar»: conserva su identidad y sus cambios pendientes, no sube nada y pide que un móvil la vuelva a confirmar desde su ficha «Web» (un aval nuevo). Si no le queda ninguna raíz utilizable, un aval nuevo no basta (no da un ancla de confianza): hay que emparejarla otra vez en persona. Nunca se confirma sola.
- **W3.** Una web nunca es destinataria ni escritora de sorpresas (`entitled`, `relayable`, `_canHoldKey` y `_cleanFor` la excluyen) y no autentica políticas de nadie. `_unvouchedMembers` y los huérfanos por sorpresas no la incluyen (no tiene sentido pedir que la aprueben para algo que nunca tendrá).
- **W4.** Una web no puede ser anfitriona de una oferta ni originar paquetes de claves (`openFamilyKey` y la rotación futura no aceptan una web como emisora). Sí puede **recibir y aplicar** un paquete `family` válido cuando exista la rotación.

Pruebas con fichas **nuevas y bien firmadas**: quitar `k`, cambiarlo, subir `seq`, fichas históricas, registro restaurado tras desalojo, estrella, cadena, anfitrión revocado, cambio de persona y registro lleno. N1, N2 y N7 siguen igual.

**En el Worker:** la credencial gana un **rol** inmutable (`device` o `web`), que fija el móvil aprobador en `POST I/approve {package, role}`. El Worker además lo contrasta con `answer.guest.k` (coherencia, no prueba: la autoridad es el móvil). Las filas existentes sin rol se leen como `device` (migración; `isCurrentMeta` no debe dar por retirada una lista vieja). Con rol `web`, **lista cerrada** de lo permitido:
- `GET S`, `GET S/slots/...` y WebSocket, como un móvil.
- **`PUT S/common`** (ruta nueva, para cualquier rol): cuerpo `{common}` y nada más (otro campo, `400`), con los mismos límites y la misma codificación base64url que `common` en `PUT S`; `If-Match` con el ETag global (`428` sin él, `412` con otro y el ETag actual). Cambia `common` y la versión en una transacción y avisa por WebSocket como un `PUT`; registro, paquetes y slots se quedan igual. Gasta de las mismas cuotas de escritura por credencial y por lista. `200 {version}` con su ETag. `PUT S` completo con rol `web`: `403`.
- `POST S/revoke` solo con su propio `deviceId`.
- `PUT G/prepare` y `POST G/commit` de su propia guarda.
- Todo lo demás (`DELETE S`, invitaciones, `I/*`, `resume`): `403`.
- `GET S` devuelve el rol en `devices`.

El motor de la web es un **modo restringido** del motor v2: fusiona `common`, lee registro y paquetes, nunca poda ni escribe nada más.

## 4. Publicación desde la web (regla central)
Una sola función decide si un cambio de la web se puede publicar, y se llama al crear el cambio, tras cada instantánea coherente, **antes de cada `PUT`** y otra vez tras un `412`.
- Una persona está **bloqueada** si tiene cualquier registro de política (diga lo que diga, roto o lápida: lo mismo que hace hoy `effectivePolicy` sin autenticar), algún slot en el manifiesto, o la web la vio bloqueada alguna vez (marca guardada en la caja). Que desaparezcan sus slots no la desbloquea.
- Se comprueban la persona **anterior**, la **propuesta** y la **resultante de fusionar**, en todas las escrituras de regalos: crear, editar, mover, cambiar estado u ocasión y las indirectas (p. ej. al borrar una ocasión, `family_controller.dart`). Todas pasan por esa función.
- **La web no guarda un documento fusionado con sus cambios dentro.** Guarda la instantánea remota y, aparte, la cola de cambios: cada entrada es una acción del usuario con todas las escrituras de campo que produce (con su HLC), también las indirectas. Lo que se ve y lo que se sube se construye cada vez: instantánea + entradas admitidas. Tras un `412`, se vuelve a construir desde la instantánea nueva.
- Si alguna escritura de una entrada toca una persona bloqueada, **la entrada entera** se queda **cifrada y apartada** en la caja, con un aviso; ni se descarta ni se convierte en otra cosa, y no entra en lo que se sube.
- Las marcas de «bloqueada alguna vez» se guardan en la caja **antes** de publicar nada.
- Límite: si un móvil protege a una persona y todavía no lo ha publicado, la web no lo puede saber. El cambio de la web llega antes y queda en `common` hasta que la protección lo reconstruya (ADR 0004).

## 5. Emparejar la web
La web no tiene cámara útil; el móvil sí. El QR lo enseña la web:
1. La web genera su identidad en memoria y un `inviteId` aleatorio de 16 bytes. Enseña un QR con `https://web.gifthuddle.app/w#<inviteId>.<huella>`. `huella` = 16 primeros bytes de `SHA-256("gift-huddle web pairing v1" ‖ 0x00 ‖ inviteId (16 bytes) ‖ clave pública Ed25519 (32 bytes) ‖ clave pública X25519 (32 bytes))`, en base64url sin relleno.
2. En el móvil, «Móviles de la familia → Conectar la web»: escanea y pregunta **antes** «¿De quién es este ordenador?». Crea la oferta con **ese** `inviteId` y el id de la persona elegida: `POST S/invites {offer, inviteId, guestPerson}`.
3. `InviteV2Object` **reserva el id de forma global y atómica**, ligado a lista, anfitrión, resumen de la oferta y `guestPerson`: la misma petición repetida es idempotente; otra cualquiera sobre un id reservado, `409` (nunca sobrescribe). Caduca con la invitación. El móvil, ante `409`, pide a la web otro QR.
4. La web consulta `GET J/offer`, que ahora devuelve `{offer, guestPerson, expiresAt}`, con espera aleatoria de 5 a 8 s (unas 12/min como mucho) y `Retry-After`, durante 10 min; un `404` antes de la oferta es «todavía no», no «caducada». Al verla, deja de consultarla.
5. La web responde con su ficha (`k = web`, `p = guestPerson`), su aval (queda como prueba del intercambio; por W1 no da autoridad) y el verificador de su credencial. El móvil rechaza, **antes de revelar el nonce**, una respuesta cuyas claves no den la huella, cuya `p` no sea la elegida o que no lleve `k = web`.
6. Revelar, código de seis cifras en las dos pantallas y aprobar con `role: "web"`. Si algo no casa, se empieza con otro QR. La web no puede enseñar el nombre de la persona antes de tener la `familyKey`; lo enseña al entrar («Este ordenador es de Nora»), y la persona la ha elegido en el móvil la misma persona que compara el código.
7. La web fija el ancla del anfitrión como raíz (§3, W2), pide el PIN, crea la guarda y la caja (§1) y entra.

Presupuesto de invitaciones por IP (30/min, compartido por móvil y web bajo la misma NAT): la web, unas 12/min como mucho; el móvil, las de siempre.

## 6. Sesión
- **Bloqueo:** a los **15 min sin usarla**, a los **5 min con la pestaña oculta**, con «Bloquear», y en `pagehide`. Al volver (`pageshow`, también desde BFCache) se pide desbloquear. Los plazos se comprueban con la hora real al volver a primer plano, no solo con temporizadores.
- **Bloquear:** primero tapa el contenido; luego cancela HTTP, sockets, temporizadores y trabajos de cifrado; invalida los callbacks (contador de generación: lo que llegue de una generación anterior se descarta) y destruye el `ProviderContainer`. No se promete borrar la memoria física: Dart y JavaScript pueden conservar copias.
- **Cambios sin subir:** cada cambio se escribe cifrado en la cola de la caja **antes** de mandarlo; solo se quita cuando su confirmación está guardada. Bloquear no espera a la subida. Al desbloquear, se fusiona con la instantánea, pasa por la regla del §4 y se sube.
- **Varias pestañas:** el Web Lock (`navigator.locks`) se toma **antes** de desbloquear. La segunda pestaña dice «Gift Huddle está abierto en otra pestaña»; «Usar aquí» pide a la otra que se bloquee (por `BroadcastChannel`) y espera a que suelte el lock de verdad. Las escrituras de la caja, los cambios de PIN y las confirmaciones van en orden.
- `navigator.storage.persist()` se pide al crear la caja; si se rechaza, se avisa. Si IndexedDB falla, nunca se dice «guardado».
- Revocada (`401`, `410`, `404` en `open`, o en `revoked` de su vista): «Este ordenador ya no está conectado». Los cambios pendientes se conservan cifrados hasta «Olvidar este ordenador» (decisión de producto 3); nunca se llevan solos a otra familia o generación.

## 7. Plataforma y transporte
- **`DeviceKeysStore` web** separado en dos: identidad, que vive en la caja abierta, y llavero de sorpresas, que en web se niega siempre. Hoy un solo interruptor controla los dos (`device_keys_store.dart`).
- `DeviceKeys` sigue serializando semillas dentro de la caja; las claves no extraíbles de WebCrypto quedan para después.
- `WebSyncTransport.socketV2`: protocolos `gift-huddle.v2` y `bearer.<credencial>`, cierres `4401` y `4404` como en el nativo, reconexión con espera creciente y cancelación al bloquear. HTTP v2 reutiliza `BaseSyncTransport.v2` con Fetch (`credentials: omit`), más `putCommon` y las rutas de la guarda.
- Sin escáner, biometría, compartir ni copia de seguridad en la web (`platform_capabilities`).

## 8. Alcance de la primera web
- **Sí:** Lista, Personas y Ocasiones con su edición (crear, editar, borrar con diálogo), Reparto con «Yo», buscar, presupuesto, idioma y tema, cambiar PIN, «Bloquear» y «Olvidar este ordenador». Maquetación ancha para escritorio (columna de hasta unos 960 px), con el diseño «Tareas» y movimiento.
- **No:** gestionar móviles, invitar, compartir, exportar, copia de seguridad, recuperación, activar o quitar protecciones ni abrir sorpresas.
- **Fotos:** fuera. La app todavía no tiene foto de regalo y se decidió el 2026-11-13 que no hace falta, ni en la app ni en la web, por ahora.

## 9. Alojamiento y cabeceras
- Un Worker solo de recursos estáticos, `gifthuddle-app` (aparte de la web pública), en `https://web.gifthuddle.app` con dominio propio gestionado por wrangler (`app/deploy/web/wrangler.toml`: SPA, sin `workers.dev`, sin vistas previas ni registros). Iba a ser Pages, pero desde 2026 `wrangler pages project create` delega en Workers. `flutter build web --release --no-web-resources-cdn --pwa-strategy=none`: motor, CanvasKit y fuentes propios; sin service worker. Desplegado el 2026-11-13 (versión `10571971`), con el Worker de sincronización en `ffdb3c06`. Desde el 2026-11-14 se compila con `flutter build web --release --wasm --no-web-resources-cdn --pwa-strategy=none` (skwasm, con dart2js de reserva para navegadores sin WasmGC), y `app/web/_headers` añade `Cross-Origin-Embedder-Policy: require-corp`, que junto a COOP `same-origin` deja la página `crossOriginIsolated` para que skwasm pinte en un hilo aparte. Medido con la demo local a 2560 × 1440: con CanvasKit JS, 10 fotogramas de más de 50 ms; con `--wasm` y COEP, ninguno (la guía de diseño de escritorio).
- `index.html` con `<base href="/">` fijo (sin `$FLUTTER_BASE_HREF`) y `base-uri 'self'`: sin base, Flutter pide `main.dart.js` relativo y una ruta de dos segmentos no arranca (lote 0).
- CSP de partida, que el lote 0 comprueba en navegador real: `default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self' https://sync.gifthuddle.app wss://sync.gifthuddle.app; worker-src 'self' blob:; manifest-src 'self'; base-uri 'self'; form-action 'none'; frame-ancestors 'none'; object-src 'none'`. `unsafe-inline` solo en estilos (los genera Flutter); nunca `unsafe-eval`. Trusted Types primero en modo informe; se endurece solo con políticas concretas.
- `Strict-Transport-Security: max-age=63072000; includeSubDomains`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Resource-Policy: same-origin`, `Permissions-Policy` sin cámara, micrófono ni geolocalización.
- Caché: `no-cache` en `index.html`, `flutter_bootstrap.js`, `main.dart.js` y todo lo que no lleve huella; inmutable solo lo que la lleve.
- Sin cookies ni analítica. Auditar que nada ponga cookies con `Domain=gifthuddle.app` (el WebSocket las mandaría al borde) y usar cookies solo de host donde haga falta. Mantener los servicios en sus hosts propios limita el alcance de las cookies.
- Worker: `ALLOWED_ORIGIN` pasa a ser una lista exacta (`https://gifthuddle.app`, `https://web.gifthuddle.app`), en la admisión y en las cabeceras de respuesta, con `Vary: Origin`, `Origin: null` rechazado y los nativos sin `Origin` como hoy. CORS no sustituye a la autenticación.
- El fragmento `#` de `/w` se lee antes del router y se limpia de la URL.

## 10. Lotes
Cada lote, en su rama, con revisión de otro motor y pruebas que hacen el ataque. Los ficheros compartidos con la fase 3 (`device_registry.dart`, `pairing_v2.dart`, `pairing_v2_flow.dart`, `sync_v2_engine.dart`, `sync_transport_v2.dart`, `sync_controller.dart`, `server/src/`) los cambia **solo** esta sesión mientras dure su lote, por turno acordado con la sesión «Gift Huddle orquestación y traspaso»; el contrato de cada uno queda escrito aquí antes de tocarlos.
0. **Prueba de navegador** (sin tocar el motor compartido): `flutter build web` real con la CSP de arriba, rutas profundas, edición de texto, fuentes, IndexedDB, Web Locks, BFCache, PBKDF2 de WebCrypto (medir iteraciones) y AES-GCM, en Chrome, Edge y Firefox.
   Resultado (2026-11-13, Chromium 156): todo pasa con la CSP; PBKDF2 de 600.000 iteraciones tarda unos 130 ms (también por `cryptography`, que usa WebCrypto); `storage.persist()` lo deniega Chrome a una página sin uso previo (se avisa, como dice el §6); Web Locks es exclusivo entre pestañas. Firefox y Edge, en la prueba final.
1. **Caja y sesión** en módulos nuevos, contra interfaces estables: caja, cliente de la guarda, cola de cambios, controlador de sesión, `DeviceKeysStore` web y `socketV2` web. Pruebas en la VM con falsos y vectores Dart ↔ WebCrypto. Revisión de código.
2. **Registro** (`core/sync`, tras los hallazgos 4/9/11/15 en `main`): `k`, tipo inmutable, W1 a W4. Revisión de código.
3. **Worker:** rol y migración, lista cerrada, `PUT S/common`, reserva global de `inviteId`, `guestPerson`, guarda con su máquina de estados y lista de orígenes. Vitest de cada `403`, guarda suspendida a los 10, ritmo, `404` uniforme, cambio de PIN a medias, revocar borra la guarda, dos listas con el mismo id, CORS. Revisión de código y de seguridad.
4. **Motor y emparejamiento:** modo restringido del motor, regla de publicación del §4, invitado web y «Conectar la web» del móvil. Revisión de código.
5. **Interfaz:** en la web, conectar (QR, persona, código), elegir PIN, desbloquear (intentos que quedan, suspendida), bloqueada, otra pestaña, cambios apartados, ajustes reducidos y maquetación ancha. En el móvil, la fila «Web», «Conectar la web» y «Permitir desbloquear otra vez». Textos es/ca/en por ARB. Después, revisión de coherencia visual.
6. **Cierre:** Revisión de seguridad de todo (con los arreglos de la fase 3 que afecten), prueba en navegador real de escritorio, aviso al responsable de mantenimiento antes del primer despliegue, Pages y Worker, emparejar con un móvil real y comprobar la fila «Web».

## Decisiones de producto (2026-11-13)
1. **Fotos:** no hacen falta, ni en la app ni en la web, por ahora.
2. **Tras 10 PIN fallidos:** suspender y volver a permitir desde un móvil, sin perder nada.
3. **Cambios sin subir cuando el ordenador pierde el acceso:** se guardan cifrados hasta «Olvidar este ordenador».

Valores de partida, revisables sin decisión: bloqueo a los 15 min sin usarla y a los 5 min con la pestaña oculta; PIN de 6 cifras como mínimo.

## Seguridad
Antes de fusionar el registro, el Worker o la caja: revisión de seguridad. Desplegar la web y el Worker está autorizado (`web.gifthuddle.app` y `sync.gifthuddle.app`), con aviso al responsable de mantenimiento antes del primero. Siguen abiertos del ADR 0004 la rotación de `familyKey` y los hallazgos 4, 9, 11 y 15 (en curso en otra rama): revocar la web corta el servicio, pero no impide descifrar sobres que consiga por otra vía.
