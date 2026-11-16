# ADR 0007 — Recuperación personal con código

Estado: aceptado para lote 5, contrato cerrado v2. Complementa ADR 0004/0005;
no activa ADR 0006 (`RENEWAL_ENABLED=false`). Una generación v2 móvil activa.
La recuperación devuelve lo sincronizado y autorizado para esa persona. No
recupera cambios que nunca salieron del dispositivo ni sus propias sorpresas.
R-c sigue siendo una copia externa independiente, de formato anterior.

## Criptografía y representación

Las 24 palabras inglesas BIP-39 codifican exactamente 32 bytes aleatorios E
(no semilla BIP-39, contraseña elegida ni PBKDF2). El QR v1 existente codifica
esa misma entropía; su versión no es la de la cápsula. Base64url siempre sin
relleno, canónico. Enteros en [0, 9007199254740991], sin flotantes.

HKDF-SHA256 RFC 5869: IKM=E, salt=UTF8(`gift-huddle-recovery-hkdf-v2`),
L=32. Sin terminadores ni prefijos implícitos. Dos expansiones independientes:

* info=UTF8(`gift-huddle-recovery-id-v2`): `recoveryId=base64url(OKM)`.
* info=UTF8(`gift-huddle-recovery-read-cap-v2`): `readCap=base64url(OKM)`.

El Worker guarda solo `readVerifier=base64url(SHA256(UTF8(
`gift-huddle-recovery-read-verifier-v2`) || 00 || decode(readCap)))`;
comparación constante. Nunca usar recoveryId como autorización ni estos OKM
como clave AES. No registrar capacidad, palabras, credenciales ni cuerpos.

Clave AES: Argon2id v=0x13, contraseña E, sal aleatoria 16 bytes nueva por
escritura, m=19456 KiB, t=2, p=1, salida 32 bytes, secret vacío y associated
data=UTF8(`gift-huddle-recovery-capsule-v2`). Estos parámetros son **exactos**;
no se aceptan negociaciones ni valores debilitados. AES-256-GCM, nonce aleatorio
nuevo de 12 bytes, tag 16 bytes. Comprimir JSON canónico UTF-8 con DEFLATE crudo.
JSON canónico: claves de objetos ordenadas recursivamente, arrays conservan orden,
compacto, sin espacios; mismo `canonicalJsonOf` que los sobres del motor.
Vectores normativos: [0007-vector-recuperacion.json](0007-vector-recuperacion.json).

Binario: `47 48 52 02 || uint16BE(header.length) || header || nonce[12]
|| ciphertext || tag[16]`. AAD = todos los bytes hasta el final de header.
Cabecera JSON canónica exacta (sin campos adicionales):

```json
{"k":"capsule","kdf":{"a":"argon2id","m":19456,"p":1,"t":2},"rid":"<recoveryId>","r":1,"s":"<sal>","v":2}
```

La ordenación canónica determina los bytes reales (r antes de rid). `r` empieza
en 1 y sube exactamente uno en cada sustitución, incluida claim. La respuesta
HTTP transporta el binario completo como `capsule=base64url(binario)` y repite
`v:2,recoveryId,revision`; deben coincidir con la cabecera. El cliente compara
además rid derivado y revisión esperada antes de Argon2. No reinterpretar GHR01,
payload v1 ni futuras versiones. Límite de **todo el binario**, no solo ciphertext:
1048576 bytes, cabecera <=1024; comprobar antes de parsear/derivar. Contenido
descomprimido <=4194304 bytes, decodificador incremental con tope antes de
materializar salida. Sellar comprueba ambos límites antes de Argon2. Error sin
recortar claves, contextos ni pruebas. R-c conserva sus límites independientes.

## Contenido mínimo y correspondencia real con Dart

`RecoveryCapsulePayload.toJson()` fija el esquema exacto siguiente. Todos los
campos se requieren, incluidos null, arrays y mapas vacíos. No documento común,
fotos, scopes descifrados ni slots: se descargan del servicio. No importar tipos
de aplicación/Flutter en core; los adaptadores de lotes posteriores hacen estas
conversiones explícitas:

| Campo | Tipo de cápsula / origen real |
|---|---|
| v=2, kind="capsule" | Discriminantes independientes de R-c |
| identity | `SyncIdentityV2.toJson`: v,l,d,sid,from?; listId, deviceId/nodo y generación; de `FamilyStore.readSyncV2` |
| deviceName, peerName, paired | String, String?, bool; `FamilyIdentity` de family_store.dart; node debe ser identity.deviceId |
| personId | String?; `FamilyIdentity.selfRecipientId`, igual a persona aprobada de `KnownDevice`; nunca elección nueva |
| deviceKeys | `DeviceKeys.toJson`: v,x,e,c; semillas X25519/Ed25519 y credencial actual |
| familyKey | `FamilyKey.toBase64Url`, clave histórica/bootstrap de FamilyStore; no sustituye el llavero común |
| registry | `DeviceRegistry.toLocalStoreJson`, declaraciones firmadas y localTypeConflicts; verificar sin descartar declaraciones al abrir |
| anchor | {deviceId,signingKey}; `RegistryAnchor`, coincide con identity y DeviceKeys; no raíz elegida por servidor |
| commonKeys | `RecoveryCommonKeys`: {keyring,revision,lastKid}; `CommonKeyState.keyring/revision/lastKid` de common_v2.dart |
| commonKeys.keyring | `FamilyKeyring.toJson` íntegro: `FamilyKeyEntry` con candidata completa (`FamilyCandidate`, descriptor/contexto/generación, firma, audiencia), own, senders (`AudienceMember`), historical, compromised y references; incluye legacy histórica, no poda |
| surpriseKeys | `SurpriseKeyring.toJson` íntegro autorizado, épocas históricas, audiencia y estado; quitar TODAS las épocas de personId antes de sellar; rechazar si aparecen al abrir |
| commonKeysMarked, commonFormatFloor | bool, 1 o 2; `FamilyStore.commonKeysMarked/readCommonFormatFloor`; irreversibles por máximo/OR |
| resume | `RecoveryResumeState`, esquema siguiente; obligaciones durables de `V2SyncState`, `CommonKeyState` y relojes/slots locales |
| transition | `RecoveryTransitionState`, `{v:1,v1Proof,legacyV1Pending,pendingV2,personChangePending,protectionPending,renewalPending,localResourcesPending}`; todos obligatorios |

`transition.v1Proof` es null o `RecoveryV1Proof` exacto
`{v:1,listId,key,since}`: conversión de `FamilyStore.readV1ProofKey()`
`{l,k,s}`, conservando lista, clave v1 y milisegundos originales. listId debe
coincidir con identity.listId; since es entero seguro no negativo. Al instalar,
`saveV1ProofKey({l:listId,k:key,s:since})`; nunca renovar el plazo vigente
que usa el controlador de emparejamiento. Una prueba caducada se elimina según
esa política, sin transformar su clave en clave v2. Versiones futuras, campos
ausentes o fechas inválidas se rechazan, sin fabricar una fecha nueva.

`resume={versionFloor,hlc,slotRevisions,minSlotRevisions,knownMembers,
pendingRevocations,pendingUnbackedRevocations,revocationOperations,
keyPackageOutbox,commonKeyOutbox,commonFormatV2,commonMigration,commonMigrationPut}`.
versionFloor es V2SyncState.version (entero, nunca null para una lista remota);
hlc es `Hlc.pack()` del máximo local del escritor recuperado; slotRevisions guarda máximos de
`SlotHeader.revision` del escritor recuperado por persona, minSlotRevisions
conserva los suelos autenticados de emparejamiento por clave `persona/escritor`
(la misma clave que usa `SyncV2Engine` al verificar slots). Los tres conjuntos son arrays
de ids ordenados sin duplicados. revocationOperations copia el mapa de registros
firmados de V2SyncState; ambos outbox copian paquetes JSON completos (`KeyBundle`
y `FamilyKeyBundle`). Los tres flags de corte se conservan. Son intenciones,
no permisos: revalidar antes de ejecutarlas.

No copiar `V2SyncState.slotVersions/ignoredSlots/deferred/health`, created,
`CommonKeyState.blocked`, ETag de transporte ni WebSockets: son cachés; created
se instala true, se fuerza descarga completa y se reconstruyen los bloqueos.
No restaurar un slotVersion que haría saltarse una descarga en instalación vacía.
`RetainedCommon` y `CommonBlock` en common_v2.dart describen recursos/bloqueos
locales, no sustituyen los bytes. La publicación debe fallar explícitamente si
existen contextos de renovación, una migración pendiente o recursos necesarios
solo locales (`FamilyStore.readRetainedCommons/readRetainedBytes`, scopes/colas
no sincronizados) que impiden ofrecer recuperación completa; no inventar una
referencia que el Worker no pueda satisfacer. Las marcas de migración quedan en
el formato para reanudar una restauración interrumpida y para rechazar el caso.

Inventario normativo del exportador (5.3/5.4), en contexto fijado por
`GenerationStore.open(sid)` y bajo cola/lock de familia. No basta construir un
DTO con flags por defecto: debe inspeccionar todos los almacenes siguientes.

| Almacén / estado | Tratamiento |
|---|---|
| FamilyStore identidad, syncV2, clave, registro; DeviceKeysStore claves y llavero de sorpresas | Incluidos según tabla; sin épocas propias |
| FamilyStore commonKeys, marcas y suelo; syncV2State | Llaveros y obligaciones incluidos; cachés reconstruidas según arriba |
| FamilyStore slots, documento, scopes, overflow | Descargar bytes remotos; extraer máximos HLC/revisión locales; bloquear si hay bytes/cambios necesarios aún no confirmados en remoto |
| FamilyStore readV1ProofKey | Incluir prueba tipada con fecha original, o null |
| FamilyStore readLegacyV1 | Si no null, `legacyV1Pending=true`: bloquear hasta absorber/retirar v1 y cerrar durablemente el recuerdo; no se exporta su clave ni se simula completado |
| FamilyStore readPendingV2 | `pendingV2=true`; terminar instalación antes de capturar |
| FamilyStore diario `_selfPersonChangeKey` y obligación de invalidación remota | `personChangePending=true` hasta cumplir ambas; no copiar el diario a otra identidad |
| FamilyStore `family.protection` | `protectionPending=true`; recuperar y terminar antes de capturar |
| GenerationStore.journal / RenewalJournalStore, generaciones retenidas o renovación pendiente | `renewalPending=true`; resolver antes de publicar; la cápsula solo cubre una generación |
| FamilyStore retainedCommons/retainedBytes, orphans, colas y recursos solo locales | `localResourcesPending=true` si son necesarios y no se pueden reconstruir del servicio con pruebas; resolver antes de publicar |
| Secretos de cifrado local, PIN/biometría, preferencias, ficheros de transporte | No transferir; crear protección local nueva y reconstruir transporte |
| Diario de recuperación/mantenimiento y activación remota en solitario | No exportar cuerpos recursivos; resolver fase dependiente y capturar estado coherente; si no es posible, bloquear |

Todos los indicadores de transition son booleanos obligatorios. Cualquiera true,
o cualquiera de commonMigration/commonMigrationPut, impide sellar/publicar.
Un lector que encuentre esos indicadores conserva staging y marca incompleta;
no instala una familia editable. No se soporta recuperación remota durante una
migración pendiente; incluir la prueba de continuidad no elimina ese bloqueo.

Al abrir se verifican firmas del registro, igualdad de lista/ancla/claves,
identidad móvil y persona aprobada. Las candidatas conservan sus procedencias;
el motor vuelve a validar confianza/audiencia/contexto al utilizarlas, según
ADR 0005 (parsear llavero no da autoridad). Después se consulta el registro
actual y se fusiona por unión verificada, nunca sustituyendo estado más nuevo.
Una cápsula íntegra no certifica permisos actuales: Worker y motor revalidan.

## API HTTP v2 aditiva (sin alterar snapshots ordinarios)

Base `/v2`. `sid` es el syncId existente de 22 caracteres; `rid` recoveryId de
43; `op` aleatorio de 16 bytes base64url canónico (22 caracteres). TLS. Todas las
respuestas llevan `Cache-Control: no-store`; JSON `Content-Type: application/json`.
Errores usan el envoltorio existente `{"error":"codigo"}`. Authorization es
`Bearer <credencial de servicio de 32 bytes base64url>`; el router pasa solo su
SHA256 al DO, igual que hoy. `X-Recovery-Cap: <readCap>` nunca va en URL.
`If-Match: "N"` es CAS de **cápsula**, separado de versión de snapshot. `ETag`
devuelto es `"revision"`. Sin enumeración pública ni acceso desde identidad web.

| Método y ruta | Autorización y cuerpo | Resultado |
|---|---|---|
| GET /lists/:sid/recoveries | Móvil activo de la lista; sin cuerpo ni cap | 200 `{v:2,recoveries:[{deviceId,recoveryId,revision,state}]}`; <=4 filas, sin ETag |
| PUT /lists/:sid/recoveries/:rid | Móvil activo propietario; If-Match "0" + X-Recovery-Operation: op para crear, "N" para reemplazar; `{v:2,deviceId,readVerifier,capsule}` | 201 alta / 200 reemplazo, `{v:2,recoveryId,revision}` + ETag |
| DELETE /lists/:sid/recoveries/:rid | Cualquier móvil activo de la lista, If-Match "N", sin cuerpo | 204; sin rehabilitar credencial ni borrar claves locales |
| GET /recoveries/:rid | X-Recovery-Cap; sin Authorization ni cuerpo | 200 `{v:2,recoveryId,revision,capsule}` + ETag |
| POST /recoveries/:rid/claim | X-Recovery-Cap + Bearer credencial actual recuperada, If-Match "N"; `{v:2,operationId,newCredentialVerifier,capsule}` | 200 `{v:2,recoveryId,revision,operationId,deviceId}` + ETag |
| POST /lists/:sid/recoveries/:rid/rotation | Móvil activo propietario; If-Match "N"; `{v:2,operationId,newRecoveryId,readVerifier,capsule}` | 201 `{v:2,recoveryId:newRecoveryId,revision:1,operationId}`; prepara sustitución de código |
| POST /lists/:sid/recoveries/:rid/rotation/:op/commit | Móvil activo propietario; If-Match "N"; `{v:2}` | 200 `{v:2,recoveryId:newRecoveryId,revision:1,operationId}`; activa sustitución |

El listado autenticado contiene solo la recuperación activa de cada móvil;
state es `active` o `rotationPending` (rid/revisión de la vieja, no de la candidata).
`RecoveryMetadata` fija cada fila. Nunca ciphertext, capacidades, verificadores,
recibos ni lápidas. Nora puede obtener rid/CAS y hacer DELETE de la recuperación
del móvil perdido sin conocer sus palabras. Si cambia CAS, relee y vuelve a
confirmar la intención sobre esa recuperación; no borra otra identidad. Web:
403 mobile_required tras autenticar, tanto listado como DELETE; un visitante
sin credencial no puede consultar ni borrar. GET público no enumera nada.

Worker inspecciona estructura/cabecera y tamaños, no descifra. deviceId de PUT
debe ser el llamante; no se cambia propietario ni readVerifier en reemplazo.
Una recuperación por identidad y cuatro por lista. Cada write exige r=N+1 y
rid coincidente. Claim conserva readVerifier, propietario y claves públicas;
newCredentialVerifier es SHA256 de la credencial NUEVA que el cliente guardó y
selló en capsule. Worker comprueba 32 bytes canónicos y que difiera del actual,
de TODA credencial registrada (incluidas revocadas), de todo verificador
retirado/denegado y de cualquier reserva de invitación de esta lista;
la coherencia cifrada solo la puede comprobar el cliente. Una revisión agotada
falla, nunca vuelve a cero. Un rid eliminado no se reutiliza; alta usa E nueva.

Claim en UN bloqueo/transacción de almacenamiento del DO de lista: autenticar
capacidad, comprobar recurso vigente y titular no revocado/web, resolver el
recibo según la precedencia de abajo y, para una operación nueva, autenticar
credencial vigente ligada inmutablemente al móvil y comprobar CAS, tamaño/cupos
y operación; sustituir verificador de credencial, cápsula, revisión y recibo
idempotente juntos. En ESA transacción registrar el
verificador antiguo como retirado con causa claim y deviceId; invalidar todas
las invitaciones del móvil como anfitrión O invitado (incluidas aprobadas),
sus reservas, resultados y checkpoints. Solo la limpieza de localizadores
queda fuera de la transacción de estado. Avanzar también versión ordinaria
de lista para notificar el cambio. Cada vía de autorización, incluso
publicInvite offer/answer/result/checkpoint, approve, guard y renovación,
rechaza verificadores retirados. answer y approve también rechazan que el
verificador propuesto esté retirado/registrado/reservado por otra invitación;
los futuros cambios de credencial aplican la misma regla. No basta cambiar
Credential.verifier ni consultar solo active(). El historial no se elimina al
borrar la recuperación. Nunca volver a registrar una credencial retirada.

WebSockets: attachment durable `{deviceId,credentialVerifier}` (o época de
credencial equivalente). Revalidar frente al estado actual antes de CADA
envío, incluido notify y socket hibernado, y al recibir; attachments antiguos
sin vínculo se cierran. Tras commit cerrar sockets antiguos antes de responder,
código 4410, motivo `credential_replaced`; el gate de envío ya protege una caída
inmediata después del commit y antes del cierre. No enviarles ni versiones.
Ningún cambio de Ed25519, X25519,
deviceId, persona ni avales: no es revocación criptográfica completa.

Guardar recibo durable por recuperación: op, `base64url(SHA256(UTF8(
canonicalJsonOf({body: <cuerpo completo>, expectedRevision: N}))))`, oldVerifier
y respuesta exacta/ETag. Antes de comprobar credencial vigente/CAS para un
reintento, autenticar cap y comprobar que el recurso no está retirado y la
identidad sigue móvil, activa y no revocada. Si oldVerifier y op coinciden con
el recibo vigente, comparar la huella: idéntica devuelve el recibo exacto,
sin otra rotación; diferente (otros bytes/CAS) da 409
recovery_operation_conflict, antes de considerar credential_replaced. Con
credencial retirada por claim y otra op, o sin coincidencia con oldVerifier
del recibo vigente, dar 403 credential_replaced. Nunca usar este bypass
en otras rutas. Se conserva el último recibo hasta la siguiente claim o borrado;
si hubo claim posterior, un intento anterior da credential_replaced tras cap
válida (o 404 si se retiró la recuperación), no vuelve a
ejecutarse. Actualizaciones ordinarias conservan el recibo. Recibos no devuelven
secretos. El cliente guarda la revisión del recibo y descarga la actual si avanzó.
Revocación posterior siempre bloquea replay; no reaparece una credencial cortada.

Errores: 400 invalid_recovery (forma, versión, base64, cabecera), 401 unauthorized
(credencial ausente/desconocida en rutas de lista), 403 mobile_required, revoked
o credential_replaced (definido abajo; en claim según la precedencia del recibo),
404 not_found (GET/claim inexistente,
cap incorrecta, lista retirada, identidad revocada/web: mismo cuerpo y cabeceras),
409 recovery_exists/recovery_limit/recovery_operation_conflict/
recovery_credential_conflict/recovery_retired/recovery_not_active/
recovery_rotation_cancelled/recovery_rotation_expired/recovery_history_full,
412 precondition_failed (CAS),
413 recovery_too_large, 428 precondition_required, 429 rate_limited + Retry-After.
En claim cap errónea siempre da 404 antes de errores de credencial/CAS; con
recuperación activa, cap correcta y credencial desconocida, 401. Para credencial retirada por claim,
oldVerifier y op del recibo vigente coincidentes dan recibo si la huella es
idéntica o 409 recovery_operation_conflict si difiere; otra op da 403
credential_replaced. Revocación y retirada del recurso prevalecen con 404.
Sin diferencias de contenido para sondear
rid; no prometer tiempo de respuesta constante entre objetos.

Orden normativo de validación en GET/claim: (1) límite de tráfico y tamaño,
gramática de ruta, headers y JSON superficial, independientes de la existencia
del rid; errores de sintaxis uniformes 400/413 incluso para rid desconocido.
(2) Resolver localizador y autenticar cap contra la lista autoritativa, comprobar
estado visible y titular móvil activo. Inexistente, retirada, revocada/web o cap
incorrecta: mismo 404, sin ETag, Retry-After específico del recurso ni metadatos.
(3) Con cap válida y recuperación activa, cotejar Bearer de claim y op con
oldVerifier y op del recibo vigente antes de exigir credencial vigente: huella
idéntica devuelve recibo; distinta da 409 recovery_operation_conflict. Una
credencial retirada por claim sin esa coincidencia da 403 credential_replaced;
en otro caso autenticar Bearer vigente. (4) Validar op,
CAS requerido y valor, cabecera/cuerpo y nuevo verificador, cupos; transacción
con revalidación. No emitir 401/409/412/428 ni ETag antes de (2). Tras (2), una
candidata sigue esta matriz, sin pasar a autenticación ni mutación de claim:

| Capacidad de la candidata | GET | claim |
|---|---|---|
| Correcta | 200 con cápsula y ETag | 409 recovery_not_active |
| Incorrecta | 404 sin ETag | 404 sin ETag |

En rutas de lista: sintaxis/límites, autenticar credencial, rol/revocación,
recurso/recibo y CAS; nunca revelar metadatos a web o credencial retirada.

## Localizador, límites y retirada

Namespace DO localizador EU, idFromName(rid). Solo contiene sid, estado de
enlace, reservationId y fechas de reserva/alarma; no blob, clave, persona,
credencial ni readVerifier. Limitar IP antes de obtenerlo.
GET/claim jamás crean filas/alarmas por rid desconocido. Cada lectura consulta
la fila autoritativa del DO de lista y sus permisos actuales; no caché de blob.
Los clientes nunca dan sid al leer/claim; el localizador resuelve el descubrimiento.

No hay transacción entre dos DO. Máquina del localizador: ausente → reserved
→ linked → retired; reserved también puede pasar a retired. Mientras exista la
marca retired no se reabre ni cambia sid; su retención acotada se detalla abajo.
Cada alta/rotation prepare escribe primero en lista una
intención durable `{rid,sid,reservationId,operationId,fingerprint,state}` bajo
CAS y cupos; reservationId es aleatorio de 16 bytes, no reutilizable. Después
RPC reserve(rid,sid,reservationId), commit del blob con ese token en la lista,
RPC confirm con el mismo token. Solo una intención válida por rid; reintento
idéntico repara cada fase. Confirm con otro token o tras retirada se rechaza,
sin revivir el enlace. Lectura reserved consulta la lista: antes del commit
404, después funciona aun si se perdió confirm.

La alarma de 24 h NO libera por tiempo sin más: consulta autoritativamente la
lista por rid/token. Si hay blob activo o candidato, confirma el enlace, aunque
hayan pasado 24 h. Si no hay blob, la lista debe cancelar la intención en una
transacción que impida un commit tardío con ese token; solo tras ese acuse el
localizador pasa a retired. Si hay tombstone, retira el enlace. Si no se puede
comprobar, conserva reserved y reintenta con backoff acotado. Cancelación y
commit compiten dentro del DO de lista; solo uno gana. Intención cancelada
consume identificador histórico y rid no se reutiliza. No liberar una reserva
cuando el DO de lista esté inaccesible, ni reubicarla en otra lista.

Recibo de alta: clave `(rid,operationId)`, huella SHA256 del JSON canónico
`{body:<cuerpo completo>,expectedRevision:0}` (misma codificación que claim),
verificador del creador y respuesta 201 exacta con ETag. Persiste hasta retirar
la lista, incluso tras reemplazo/borrado; replay solo por el propietario activo
con la misma credencial vigente, op/huella/CAS, antes del CAS ordinario. Devuelve
ese 201, repara el localizador según estado actual, sin reabrir un rid retirado;
el cliente consulta GET actual antes de marcar preparada. Op con otros bytes
da 409 recovery_operation_conflict. Si cambió credencial no hay bypass.

Borrado hace primero tombstone en lista, después retira enlace; reintento puede
completar limpieza. DELETE guarda recibo por rid y CAS original, con principal
y respuesta 204 sin ETag; repetición por ese mismo móvil aún activo con CAS
original devuelve 204, incluso después de cerrar candidata. Otro CAS da 412,
otro principal no obtiene replay y recibe 404 si ya no existe recurso activo.
Revocar borra/desactiva recuperaciones de esa identidad en la misma
transacción que revoca; limpieza de localizadores es posterior e idempotente.
Un enlace obsoleto no elude las comprobaciones del DO de lista.

| Recurso | Límite cerrado |
|---|---|
| Binario cifrado / contenido descomprimido | 1 MiB / 4 MiB |
| Recuperaciones activas | 1/identidad, 4/lista |
| Blobs activos | 4 MiB/lista; sustitución temporal <=1 MiB extra, una a la vez |
| Cuerpo HTTP PUT/claim/rotation prepare | 1400832 bytes (base64 + metadatos); limitar streaming antes de JSON |
| Cuerpo HTTP rotation commit | 4096 bytes, esquema exacto `{v:2}`; demás controles <=4096; GET/DELETE sin cuerpo (cualquier byte: 400) |
| Identificadores asignados durante toda la vida | 32/identidad y 256/lista, incluidos activos, candidatos, reservas y retirados; cada asignación reserva su lápida (<=256) |
| Recibos históricos | 512/lista, cada uno <=4096 bytes; reservar plazas terminales antes de aceptar alta/prepare |
| Verificadores retirados por claim | 256/lista; permanentes, además de los límites existentes de credenciales/denegados |
| Metadatos históricos de recuperación | <=4 MiB/lista, incluyendo intenciones, lápidas, recibos, verificadores e índices; reservar espacio terminal antes de mutar |
| Lecturas/claim por IP | 30/minuto, además del límite global existente; antes de localizar |
| Mutaciones por lista | 6/minuto, incluyendo claim y DELETE |
| Altas, sustituciones y prepare | 6/día UTC/identidad y 24/día UTC/lista; replay exacto no consume cuota |
| Reserva exclusiva de claim | 2/día UTC/identidad y 8/día UTC/lista, independiente del cupo anterior; replay exacto no consume cuota |
| Retención | Vida de la lista, sin caducidad independiente |

Los subcupos se vinculan a deviceId, no al verificador reemplazable: cambiar
credencial no los reinicia. Un móvil no puede consumir el cupo diario de los
demás ni todos los ids históricos. El cupo exclusivo de claim no se puede
gastar con PUT/prepare. Se mantiene el límite compartido de 6 mutaciones/minuto;
su agotamiento solo retrasa la recuperación hasta la ventana siguiente.
DELETE de emergencia no consume cupo diario de altas/sustituciones. 429 no
modifica estado. Contadores son durables/acotados, no una fila por rid fallido.
Antes de aceptar una operación se comprueban TODOS los cupos, incluida la plaza
y bytes de su futuro cierre: agotamiento histórico da 409 recovery_history_full
sin mutar ni compactar hashes. Claim reserva la entrada retirada antes de
cambiar credencial. Altas/prepare reservan lápida y recibos de cancelación,
expiración, commit y DELETE; una plaza reutilizable para el último recibo claim
por recuperación. DELETE/revocación y limpieza usan esas reservas y siempre
pueden cerrar recursos existentes, aunque se agotó el cupo para operaciones
nuevas. Fallos sintácticos/desconocidos no crean historial. Nunca podar un
verificador ni una lápida para permitir reutilización. Al agotarse se necesita
una generación nueva mediante el procedimiento autorizado, no un bucle de retry.
Todo replay (alta, DELETE, prepare, commit, claim) queda exento de las 6
mutaciones/minuto y los cupos diarios, pero sujeto al límite de tráfico por
IP/credencial y global existente. Conflictos no son replays; consumen tráfico,
sin consumir cupo de escritura ni reservar historial.
La retirada existente tras 400 días de inactividad elimina blobs, recibos y
verificadores junto a la lista; los enlaces se limpian por RPC/reintento/alarma
acotada y mientras tanto responden 404. GET de recuperación no renueva actividad
de lista; las mutaciones autenticadas aceptadas siguen la política existente.
Una cápsula no prolonga la lista ni evita su retirada. El servidor conoce lista,
identidad, tamaños, revisiones y accesos, nunca palabras ni claves privadas.

**Retención de retiradas (B3/B4, 2026-11-15).** Los marcadores de `syncId` y
localizador `rid` retirados duran 400 días desde su retirada, con un plazo que
no se renueva al recibir peticiones. Después se borran y esos identificadores
pueden volver a reclamarse mediante un alta nueva; no hay una prohibición
perpetua de reutilización. Una marca antigua que carece de plazo solo recibe
`ahora + 400 días` en su primer despertar tras la actualización (petición,
RPC o alarma). Si el objeto no despierta, puede seguir almacenada más tiempo;
los despertares siguientes no reinician el plazo.

Es un compromiso aceptado para no acumular identificadores retirados para
siempre: los `syncId` nuevos tienen 128 bits aleatorios y los `rid` se derivan
criptográficamente de la entropía del código, por lo que una colisión accidental
es despreciable. Saber un id antiguo puede permitir ocuparlo tras ese plazo
(riesgo de disponibilidad aceptado), pero no entrega las palabras, claves ni
contenido borrado del servicio. Siguen siendo necesarias la capacidad de
lectura y las comprobaciones criptográficas de cápsula, identidad y revisiones;
conocer un id no basta para fabricar una cápsula válida para el código anterior.
No se promete invalidación perpetua más allá de esos 400 días ni se pueden
retirar las copias o claves que alguien ya hubiera guardado. Los clientes crean
una generación y un código nuevos tras una retirada, nunca reutilizan los ids
como mecanismo de reactivación. Véase también ADR 0004, «Borrado y caducidad».

Antes de activar renovación: las rutas de recuperación actualmente no pasan por
`recordActivity` ni por la congelación de escrituras de renovación. Hay que
integrar y probar la actividad por participante, la exclusión y las barreras
de renovación para PUT/claim/prepare/commit/DELETE antes de habilitarla (ADR 0006).

Un answer pendiente reserva su verificador. Si el mismo invitado responde otra
invitación con el mismo verificador antes de 24 h, se libera atómicamente la
anterior (incluidos localizador y checkpoint). Cancelar también libera la reserva.
Otro invitado, una invitación aprobada o una credencial activa, revocada o retirada
no permiten reutilizar el verificador; answer y approve mantienen esa prohibición.

Pruebas de aceptación del Worker (bloqueo de salida 5.2):

* Credencial antigua tras claim rechazada en todas las rutas de lista, guard,
  renovación e invitación; answer/approve no la registran como propuesta nueva.
  Cubrir invitación aprobada, anfitrión e invitado, result y checkpoint pendiente,
  socket abierto e hibernado, notify después de caer inmediatamente tras commit.
  Tras cap válida, oldVerifier y op del recibo vigente coincidentes: huella
  idéntica devuelve recibo exacto; cuerpo/CAS alterado da 409
  recovery_operation_conflict. Otra op con credencial retirada da 403
  credential_replaced. Probar las tres ramas sin otra mutación y comprobar que
  revocación o retirada posterior prevalecen con 404 en todas ellas. Nuevo
  verificador colisionando con activo, revocado, retirado o reserva falla atómicamente.
* Nora descubre y borra recuperación perdida sin palabras; web y visitante no
  obtienen listado ni DELETE. CAS cambiado no borra otra recuperación.
* Caídas tras intención, reserva, blob y antes de confirm; avanzar >24 h y
  reiniciar ambos DO; lista inaccesible mantiene reserva, commit compitiendo con
  cancelación y confirm tardía con token ajeno/retirado no reviven rid.
* Alta idéntica, DELETE con CAS original y prepare/commit después de commit,
  cancelación y expiración dan exactamente los resultados anteriores; no doble
  cobro de cuota y sí límite de tráfico. Reabrir almacenamiento entre intentos.
* Agotar cada cupo histórico antes de aceptar mutación, sin cambios parciales;
  DELETE/revocación aún cierran con plazas reservadas. PUT, claim y prepare
  rechazan cuerpo >1400832; commit >4096, GET/DELETE con cuerpo se rechazan.
* Matriz de rid inexistente/activo/retirado/revocado, cap errónea y credencial,
  CAS u op erróneos: antes de autenticar cap mismo 404 sin ETag; sintaxis inválida
  produce el mismo 400/413 con independencia de existencia. Matriz de candidata:
  cap correcta, GET 200 con cápsula/ETag y claim 409 recovery_not_active;
  cap incorrecta, GET y claim 404 sin ETag ni recovery_not_active.
* Migración vieja/nueva en el mismo móvil: respuesta de claim perdida, vieja
  reconecta por HTTP o WS y recibe credential_replaced; revocación posterior
  prevalece; red/5xx/desconocida nunca se confunden con traslado.

## Activar recuperación en una familia de un solo móvil (5.3/5.4)

«Crear código de recuperación» autoriza explícitamente activar la sincronización
v2 aunque no haya otro móvil emparejado. No depende de `paired=true`, no inventa
un segundo dispositivo ni inicia una renovación. Si la familia sigue en v1,
se ejecuta la migración existente de `ensureV2Family` de
pairing_v2_controller.dart por esta acción explícita, mediante su variante
interna bajo lock descrita abajo; no se activa servidor en segundo plano sin ella.
`paired` sigue describiendo emparejamiento, no disponibilidad remota. Persistir
por separado `remoteSyncEnabled=true` por generación y usar esa intención para
arranque/reanudación del motor sin el gate actual de «otro móvil». Esta
integración se implementa en 5.3/5.4, no en este lote de formato.

El Worker YA dispone de la llamada mínima: `SyncV2Transport.createList`,
`PUT /v2/lists/:sid`, Bearer del único móvil, `If-Match: "0"`, cuerpo snapshot
`{deviceId,common,registry,keyPackages,slots,minCommonFormat?}`. El método
`ListV2Object.create` registra al creador y snapshot en una transacción, versión
1 / 201; no exige invitación. `SyncV2Engine.ensureCreated` ya cifra el común,
prepara candidatos/paquetes y guarda created/version. No hace falta una ruta
nueva de bootstrap. Este ADR sí añade listado/recuperación y errores descritos
arriba; no cambiar create para tratar 412 o 401 como prueba de propiedad.

Protocolo mínimo durable, bajo la misma cola de familia. La entrada de activación
o reanudación es la única propietaria del lock y lo adquiere una vez. Dentro usa
una variante interna de `ensureV2Family` que presupone el lock adquirido
(adaptando la actual `_ensureV2Family`); esa variante no vuelve a tomar la cola.
Nunca llamar al wrapper público `ensureV2Family` dentro del lock: la cola no es
reentrante. Cualquier última vuelta v1 que necesite la cola se ejecuta antes de
adquirirla; dentro se vuelve a cargar y validar el estado. La misma regla rige
las fases reanudadas y las llamadas al motor.

1. Antes de migrar o hacer red, guardar diario cifrado de activación con op,
   familia origen, intención explícita y fase. Si hay PendingV2, terminar según
   generation_v2.dart; fijar la identidad resultante, claves y sid antes de red.
   No cambiar key/sid al reintentar una creación remota que pudo aceptarse.
   La migración local previa a toda red mantiene su semántica existente si se
   corta antes de instalar la identidad. Resolver LegacyV1 si existía.
2. Adoptar la instalación v2 completa con `GenerationStore.adoptCurrent()` y
   fijar contexto con open(sid); nunca usar prepare() de renovación ni crear
   otro namespace en cada intento. Persistir remoteSyncEnabled y fase
   `createPrepared`, con el snapshot cifrado exacto y CAS 0, antes de enviarlo.
   Formato 2: candidato/llavero/outbox durables antes del snapshot, suelo 2 y
   commonKeysMarked completados recuperablemente al confirmar aceptación,
   según CommonV2Bootstrap; no retroceder a formato 1 tras respuesta perdida.
3. Ejecutar ensureCreated usando ese snapshot preparado (el adaptador 5.3/5.4
   debe permitir reenviarlo). 201: persistir `V2SyncState.created=true`,
   version=1 y aceptación de paquetes/marcas antes de avanzar. Timeout: conservar
   diario, claves, bytes y CAS; reenviar. 412: GET autenticado completo, verificar
   registro, identidad, generación y formato, unir estado y solo entonces
   marcar created/version actual y finalizar bootstrap. La rama stale actual
   por sí sola no demuestra que los datos estén recuperables. 401, retirada,
   colisión de identidad o formato no soportado: atención, sin reemplazar lista.
4. Hacer vueltas ordinarias hasta confirmar común, slots y paquetes autorizados,
   incluidas colas/outboxes y revocaciones; create empieza sin slots y no basta
   por sí solo. Conservar aparte los ámbitos propios que nunca se recuperan.
   Volver a leer y validar lo publicado: no basta que no haya error de PUT.
5. Solo cuando el inventario no bloquee, generar/persistir E y alta op/cuerpo/CAS
   y publicar cápsula; GET + abrir confirma «preparada». Capturar los máximos
   de la última vuelta. Un corte entre creación y cápsula reanuda fase 4 o 5
   en la misma generación. Sin red queda pendiente, nunca «código preparado».

Al arrancar resolver este diario antes de ediciones/publicación concurrentes;
no volver a crear la familia ni perder ediciones locales por un timeout.
Cancelar el alta de cápsula no borra la generación ni sus datos en el Worker.
La disponibilidad depende de sincronización vigente, no de mantener otra app
abierta. Aceptación: familia v1 nunca emparejada, sola, activa v2 y crea código
sin bloquear la cola; cortes antes/después de cada escritura de migración,
activación y del 201, con reapertura y reanudación bajo un único lock, misma
identidad/claves/sid una vez fijados y sin duplicar creación remota. Se recupera
desde almacenes vacíos.

## App antigua tras un claim (5.2/5.3/5.4)

La última app `app.gifthuddle` puede crear el código con este mismo protocolo;
la nueva `es.gifthuddle.app` lo introduce incluso en el mismo móvil. No hay
Intent ni canal local en este contrato. Claim retira la credencial de la vieja
y conserva la identidad criptográfica en la nueva.

Nuevo error propio: HTTP 403 `{"error":"credential_replaced"}`, sin ETag ni
datos, cuando el verificador presentado coincide con una entrada histórica
retirada POR CLAIM y su móvil no está revocado. Se aplica en toda ruta que
acepte esa credencial, también handshake WS; cierre WS 4410 con ese motivo.
Solo prueba conocimiento de la credencial retirada; no autoriza ninguna lectura
ni mutación. Si el móvil fue revocado después, prevalece `revoked` en rutas de
lista (conocimiento del verificador conocido), y 404 indistinguible en
GET/claim de recuperación; no convertir revocación en traslado. Credencial
desconocida sigue dando 401 unauthorized, red/timeout/5xx no dan este error.
En claim se autentica primero cap y se comprueba recurso/titular vigente:
revocación o retirada dan 404 y prevalecen sobre el recibo. Tras cap válida,
oldVerifier y op coincidentes con el recibo vigente dan recibo si la huella es
idéntica, o 409 recovery_operation_conflict si cambia cuerpo/CAS; solo después,
una credencial retirada sin esa coincidencia da 403 credential_replaced.
Cap incorrecta sigue dando 404, sin distinguir esas causas.

Al recibir credential_replaced, la vieja persiste estado `transferred` por sid
antes de cualquier nueva edición, retry o trabajo en cola. Bajo lock suspende
motor, WS, alarmas y reintentos, importaciones y todas las mutaciones locales
(incluidas tareas ya encoladas que deben comprobar el gate al ejecutar).
Muestra «Esta lista se ha pasado a otro móvil o app», de solo lectura de su
copia local; arranque honra la marca antes de abrir controladores. No borra
documentos, claves, outboxes, cambios aún no enviados ni crea otra credencial
o generación. No se reactiva por timeout, conectividad ni un botón de retry;
salir de este estado requiere una acción explícita de nueva incorporación,
sin sobrescribir la copia conservada. Los textos definitivos y ARB es/ca/en
son tarea de interfaz posterior.

Revoked sigue el flujo de revocación existente, con causa propia; no se etiqueta
como traslado. Un fallo de red mantiene pendiente con backoff, sin marcar
transferred. Si la vieja estaba offline, puede editar hasta enterarse del
claim: no se promete bloquearla a distancia sin conexión; al recibir el rechazo
conserva esos cambios solo locales para no perderlos, sin enviarlos ni borrar.
Una caída tras commit del claim o antes de persistir transferred se resuelve
con el siguiente rechazo; nunca se permite al Worker aceptar su credencial.

`transferred` garantiza el comportamiento de una app cooperativa. Quien conserve
las palabras puede derivar la capacidad, descargar y descifrar la cápsula nueva
y obtener la credencial vigente sin otro claim: readVerifier, código y claves
de firma se conservan. No hay expulsión criptográfica del poseedor del código;
exigirla requiere ampliar el protocolo de transferencia.

## Restauración durable del cliente (lotes 5.3/5.4)

Diario cifrado separado de la familia activa; no borrar una familia existente.
Cada transición se persiste **antes** de la llamada/instalación dependiente:

1. `located`: guardar E en almacén seguro y rid, operación local, revisión y
   binario descargados; abrir y verificar esquema/identidad/ancla/llaveros.
2. `verified`: con credencial recuperada consultar servicio actual, registro,
   generación, formato y renovación; verificar y unir pruebas sin retroceder.
   No arrancar motor normal sobre documento vacío. Revocado/retirado bloquea.
3. `claimPrepared`: generar credencial nueva con
   `DeviceKeys.withNewServiceCredential`, op aleatorio, revisión esperada, nueva
   cápsula r+1 con esa credencial, sal y nonce. Guardar EXACTAMENTE credencial
   vieja/nueva, cuerpo, CAS y op en una escritura durable ANTES del POST.
4. `claimConfirmed`: POST idéntico hasta obtener recibo; tras respuesta perdida
   no generar otra credencial/op. Si falla CAS, releer/abrir actual y reconciliar;
   si nueva cápsula tiene la credencial propia se reconoce instalación pendiente,
   si otra claim ganó detenerse y revalidar. Persistir recibo antes de descargar.
5. `downloading`: con credencial nueva descargar snapshot completo, paquetes y
   slots, verificar firmas/audiencias/contextos y descifrar lo autorizado. Guardar
   staging, suelos, registro unido y progreso antes de cada petición posterior.
   Falta de claves/paquetes conserva staging y da recuperación incompleta, jamás
   ámbito vacío. Repetir lectura hasta snapshot coherente y permisos actuales.
6. `installPrepared`: guardar intención de instalación y namespace completo en
   `GenerationStore`/almacenes fijados; `FamilyStore`, `DeviceKeysStore` y
   `GenerationDirectory` se activan recuperablemente en cola/lock de familia.
   Antes de activar el namespace restaurado, instalar en él durablemente
   `remoteSyncEnabled=true` por generación, derivado de la recuperación remota
   validada; no requiere otro campo cifrado en la cápsula ni cambiar paired.
   El arranque y la reanudación del motor consumen esa marca incluso si
   `paired=false`, también después de reiniciar.
   Recuperar diario antes de exponer familia/ediciones o tratar Gone.
7. `active`: recalcular HLC sobre todos los documentos y máximo guardado; común
   y slots del mismo escritor usan revisión > máximo entre cápsula, local y
   remoto. OR de marcas y máximo de suelo de formato; unión de registro.
   Solo ahora activar motor automáticamente. Persistir éxito antes de limpiar
   secretos redundantes del diario; conservar material de actualización seguro.

Destino y consumidor de los suelos (obligatorio en 5.3/5.4): añadir al contexto
de FamilyStore un almacén cifrado durable `recoveryRevisionFloors` por sid y
`persona/escritor`; instalar `resume.slotRevisions` con escritor
identity.deviceId, combinando por máximo con slots remotos y locales. Mantener
aparte minSlotRevisions en V2SyncState para validación de lecturas. El adaptador
que sella slots DEBE pasar el máximo guardado a la asignación de revisión
(ampliar SlotSet.nextRevision o su llamante); el cálculo actual con solo slot
y reloj NO consume este suelo y no satisface el contrato. Persistir el suelo
asignado junto a la intención de PUT antes de publicar; tras reiniciar no
reutilizar revisión. Conservarlo aunque desaparezca el slot. Para común usar
CommonKeyState.revision y máximo remoto, y HLC inicializado por máximo de
resume.hlc y documentos/slots recuperados. Desbordamiento bloquea, no reinicia.

Al reiniciar se repite la acción idempotente de la última fase durable; nunca se
vuelve a publicar como creador de lista. Persistir incompleta/needsAttention con
causa concreta ante formato futuro, renovación o contexto no soportado. Una
copia remota vieja no gana al estado local más reciente.

Prueba de suficiencia obligatoria que bloquea la salida de 5.3/5.4: exportar
desde FamilyStore/DeviceKeysStore/GenerationStore reales (backend de prueba),
restaurar a otros vacíos y arrancar el motor real, solo con las palabras.
No sustituirla por roundtrip del DTO ni por el vector criptográfico. Fixture:
común formato 2, varios escritores, sorpresas autorizadas e históricas,
llavero con procedencias, cápsula antigua seguida de varias rotaciones con el
titular desconectado, ambos outboxes no vacíos, revocaciones pendientes,
HLC y suelos mayores que los slots actuales. Afirmar cero PUT hasta completar
descarga/validación inicial, unión verificada actual, y siguiente publicación
con HLC/revisiones estrictamente superiores a todos los máximos. Paquetes
ausentes deben producir incompleta con staging conservado, sin ámbitos vacíos.
Inyectar cortes por fase, reapertura desde disco, CAS perdido y claim concurrente.
Cubrir además una familia nunca emparejada (`paired=false`): recuperación desde
almacenes vacíos, reinicio tras instalar la marca durable remoteSyncEnabled y
sincronización automática de una edición posterior, sin segundo móvil ni nueva
activación explícita. Un corte antes de persistir la marca no permite activar
el namespace; reanudar installPrepared debe completarla antes de exponerlo.
Estos adaptadores y esa prueba se delegan explícitamente; este lote no demuestra
todavía restauración completa. El vector sirve de interoperabilidad del formato.

## Mantenimiento y cambio de código

Intención persistente por identidad con dirtyCounter, hash del contenido,
expectedRevision, cuerpo sellado exacto pendiente y última revisión verificada.
Marcar dirty en la misma operación recuperable que cambia claves/llaveros,
credencial, persona aprobada, registro relevante, contexto, suelos o formato.
Capturar snapshot coherente bajo lock; no quitar dirty por una escritura anterior
si cambió el contador. Antes de PUT guardar cuerpo y CAS. Respuesta perdida:
GET y comparar bytes/revisión; nunca regenerar nonce para adivinar aceptación.
CAS perdido: descargar y verificar, revalidar identidad, reconstruir sin perder
claves ni bajar suelos. Respetar Retry-After y reintentar al volver conexión.
Preparada solo tras GET + abrir revisión confirmada; pendiente mientras quede
dirty; necesita atención con causa si no puede completarse.

Cambio de persona: ampliar el diario existente `prepareSelfPersonChange` con
obligación durable `recoveryInvalidation={rid,expectedRevision,status}` ANTES de
purgar claves/cambiar identidad. Si hay candidata de rotación, se incluye su
cancelación por DELETE de la activa. Fases: `remotePending` → DELETE confirmado
→ `retired` → persona nueva aprobada → alta con E NUEVA. El cerrojo de publicación
se instala con el diario y cubre cualquier operación de red en curso. Offline
puede empezar el cambio LOCAL seguro, pero queda «invalidación remota pendiente»;
la vieja cápsula sigue accesible hasta DELETE. No afirmar que se invalidó, ni
publicar nueva persona, claves, paquetes o cápsula antes del acuse. La nueva
persona no se considera aprobada por ese cambio local. Al reconectar, primero
resolver DELETE (listar/releer CAS si perdió carrera con PUT/claim), después
continuar aprobación. Si la credencial fue sustituida, estado transferred y
conservar obligación, sin mutar con credencial retirada. Tras DELETE, una caída
repite el CAS original y recibe 204. No borrar el diario de persona hasta
transferir/cumplir durablemente la obligación, aunque terminó la purga local.
La app no reactiva el código anterior ni reutiliza sus palabras. El rechazo
del localizador retirado dura los 400 días descritos en «Retención de retiradas».
Solo tras persona aprobada y sin bloqueos puede crearse código nuevo. No hay
operación de suspensión/reactivación ni promesa de invalidación offline.

Cambio de código por mantenimiento: publicar nueva E como sustitución preparada de la
misma identidad (reserva localizador nuevo), verificar por GET, luego conmutar
en DO de lista y retirar anterior; una única recuperación activa, vieja vigente
hasta confirmación, candidata temporal <=1 MiB. Las dos rutas `rotation` cierran
esta operación: antes de preparar se guardan ambas E, op, cuerpo y CAS en el
diario. Preparar exige r=1 y rid nuevo en la cabecera, mismo propietario y límite
diario; a lo sumo una candidata por lista, expira a 24 h sin afectar a la vieja.
GET con la capacidad nueva puede descargar la candidata para comprobarla;
claim sobre candidata devuelve 409 recovery_not_active y jamás cambia credencial.
Tras GET + abrir se guarda intención de commit. Commit comprueba móvil vigente,
propietario, op y CAS de la vieja y, en una transacción del DO de lista, retira
vieja y activa candidata. No vuelve a cifrar ni cambia la credencial. El recibo
de commit se conserva en la lápida vieja hasta retirada de lista; reintento
idéntico autenticado devuelve el mismo resultado. Preparar también es idempotente
por op y huella del cuerpo/CAS, igual que claim. El recibo prepare conserva
huella, resultado y estado hasta retirada de lista: replay en prepared devuelve
201 original, tras commit devuelve 200 y recibo de commit (sin recrear candidata),
tras cancelación 409 recovery_rotation_cancelled, tras expiración 409
recovery_rotation_expired. Mismo op con otros bytes/CAS siempre 409
recovery_operation_conflict tras autenticar. Commit repetido devuelve recibo
200 exacto; si nunca hubo commit, cancelada/expirada da su 409 terminal. Ningún
replay vuelve a reservar ni a cobrar escritura. PUT/claim sobre la vieja que
avance CAS cancela la candidata; revalidar y preparar otra, sin inutilizar la
vieja. Revocar o DELETE elimina también la candidata. Un fallo de limpieza del
localizador viejo no le da acceso porque la lista ya lo retiró. Para mantenimiento
no sustituir rotation por DELETE seguido de PUT; el cambio de persona sí exige
retirada y código nuevo según el protocolo anterior. Nunca aceptar dos
recuperaciones activas para la misma identidad.

Filtración de palabras equivale a filtración de credenciales. Borrar cápsula no
borra copias extraídas. Requiere identidad segura, revocación y rotaciones según
ADR 0004/0005; reemplazar credencial corta Worker pero conserva X25519/Ed25519.
No guardar palabras en URL, logs, analítica ni portapapeles automático.

Fuera: miembro latente, revocación criptográfica automática, crear/restaurar en
web, seguimiento entre generaciones y renovación automática. Web ya emparejada
sigue funcionando. Familias v1 solo migran/activan servicio por acción explícita
de emparejar o crear código (incluido el caso de un solo móvil);
R-c complementa disponibilidad remota y no promete archivo eterno con 24 palabras.
