# ADR 0006 · Contrato de renovación de generación

La recuperación con palabras se fija en [ADR 0007](0007-recuperacion-con-codigo.md)
para una única generación v2 activa. No sigue renovaciones ni mezcla contextos;
una renovación pendiente bloquea la recuperación completa. RENEWAL_ENABLED sigue false.

Condición previa de activación: las rutas del Worker de recuperación (ADR 0007)
todavía no pasan por `recordActivity` ni por la congelación de escrituras de
renovación. Integrar y probar actividad por participante, exclusión y barreras
para PUT/claim/prepare/commit/DELETE antes de habilitar renovación.

Estado: ronda de cierre del lote 4 (2026-11-14), registro encadenado sobre ADR 0005.
El flujo completo se activa al integrar motor, reconexión, web e interfaz.
Normativa de transporte: [`server/README.md`](../../server/README.md), «API v2 / Renewal control».
Completa el diseño de la fase 3; ante diferencias manda el Worker.

## Registro firmado, formato y confianza (cuarta ronda)

La fuente de verdad pasa a ser el registro append-only de comandos firmados,
no las colecciones de pruebas del control. Cada comando incluye prev obligatorio:
null en reserve inicial; en los siguientes, hash del comando anterior completo.
Se conserva v:1 y se cambia el dominio Ed25519 a
`gift-huddle-renewal-control-v2`, NUL y JSON canónico sin signature. El hash es
base64url sin padding de SHA-256 del UTF-8 del JSON canónico **con signature**.
Se ordenan recursivamente las claves, se conserva el orden de arrays y se usan
enteros seguros. Cambiar CAS o prev exige otra firma. El primero liga origen,
operación y CAS de partida. No se aceptan historyHead, historyCommitment ni archivos
de instantáneas como sustitutos del registro. No hay conversión automática de
controles de rondas anteriores: este contrato todavía no activa el motor.

El formato anterior nunca llegó a producción: el lote 4 sigue fuera de main y el
flujo está desactivado. Comprobado contra main local fc8df2d: no contiene
renewal_protocol.dart, renewal.ts ni este ADR. No existen datos productivos que
migrar ni un lector, escritor o conversor del formato anterior. Se ha comprobado
la ausencia de historyHead/historyCommitment en el código de producción de
renovación. renewal_upgrade_required solo rechaza filas de desarrollo sin cabeza;
no fabrica una cadena. Los almacenes de desarrollo anteriores deben recrearse para
este esquema e índices. Si cambia esa precondición de despliegue, el flujo queda
bloqueado hasta definir una migración explícita revisada, sin borrar operaciones.

El Worker verifica Ed25519 ANTES del append y de cualquier efecto del comando.
La clave queda ligada a la credencial: captura la clave única del creador en el
registro al crear la lista, y la del invitado en la respuesta de emparejamiento
ya almacenada al aprobar su credencial. Una credencial antigua sin clave fijada
se rechaza con `409 renewal_key_binding_required`: nunca se recupera ni se fija
su clave desde el registro mutable, aunque estuviera guardado antes del comando.
La migración futura debe autenticar la credencial y verificar explícitamente su
enlace inmutable; actualizar el cliente o republicar su ficha no la migra. Hasta
que exista esa migración, debe emparejarse de nuevo como identidad nueva.
Ninguna clave recibida en el PUT de renovación selecciona al
verificador: newSigningKey pertenece al destino. Cambiar el registro no sustituye
una clave ya fijada. Firma basura o ajena: 403 renewal_bad_signature sin append.
Esto protege disponibilidad con Worker honesto, no acredita confianza: el móvil
sigue verificando de forma independiente firmas, roles y enlaces históricos.
Todos los números firmados son int seguros en Dart, incluido commonFormat: 2.0
se rechaza antes de firmar. El vector JSON/Worker conserva la firma de 2 entero.

### Condición de activación del Worker

`RENEWAL_ENABLED` está apagado por defecto (`"false"` en wrangler.toml; ausente
también cierra). Solo el valor exacto `"true"` permite intentar `reserve`.
Mientras el motor no esté integrado, debe seguir apagado: el Worker devuelve
`409 renewal_disabled` antes de consultar destino o modificar origen, invitaciones,
actividad, contadores o registro de renovación. La desactivación de la app no
sustituye este bloqueo del servidor.

Antes de encenderlo deben estar integrados motor, reconexión y web, y **todos**
los participantes de servicio activos, incluidas las webs, deben tener enlace
inmutable y anunciar explícitamente soporte del protocolo de renovación.
La comprobación ya existe detrás del interruptor: `reserve` rechaza cualquier
credencial activa sin clave con `renewal_key_binding_required` y cualquiera sin
anuncio con `renewal_capability_required`. No basta la clave ni `commonFormat:2`:
pre.29 recién emparejada tiene clave pero no implementa renovación. El anuncio
autenticado es `POST S/capability {commonFormat:2,renewalProtocol:1}`, persistido
por credencial, monótono e idempotente; no se infiere del registro ni del rol.
Las credenciales revocadas y los participantes exclusivamente locales no requieren
anuncio. Las rutas ordinarias conservan su contrato sin exigir este campo.
El destino además debe conservar la clave inmutable de su creador, idéntica a
`newSigningKey`, y la ficha correspondiente; una ficha mutable no reemplaza ese
enlace. Nunca se activa antes de resolver los enlaces antiguos mediante la
migración autenticada y verificada o un nuevo emparejamiento.

El Worker guarda una fila propia por comando, indexada por operación/altura y
hash, fuera de los 256 KiB del control. La escritura de fila, proyección, CAS y
los efectos de servicio son atómicos. Solo acepta el prev actual. La proyección
conserva head, height, logBytes, fase y referencias hash a los comandos pertinentes;
no contiene arrays de identidades ni copias de vetos. Los reintentos exactos de
la revisión actual conservan la respuesta sin añadir filas. recover es una
transición del mismo registro: sustituye destino y reinicia las ocho ramas activas,
sin archivar ni descartar pruebas. Abort termina con una lápida firmada y otra
operación empieza un registro independiente.

Se añaden revoke (participantDeviceId), resume (sin campos específicos) y capability
(commonFormat:2). revoke, firmado por móvil vigente, revoca la credencial del
servicio e invalida el plan sin copiar identidades. El motor conserva también
la revocación del registro de dispositivos y la publica cuando sea posible. El
comando firmado del registro de renovación basta como prueba durante la barrera;
no exige modificar el registro congelado del origen para poder reproducirlo. Durante la operación los POST
antiguos de revocación/capacidad exigen usar el comando firmado. Una web puede
firmar ack, resume y capability, nunca renovar/cerrar/revocar. resume retira la
exclusión propia e invalida preparación/confirmación; exige revise y acuses nuevos.
Cada participante puede emitir resume UNA vez por operación, incluso tras
replace/recover. Sus peticiones posteriores tampoco recrean el fence de servicio.
Otra vuelta exige revocar esa credencial y emparejar una identidad nueva en el
destino. Así la misma credencial no puede inducir ciclos ilimitados.
Una petición del excluido conserva la protección M4 mediante un fence de servicio
que invalida el CAS de cierre; no inventa eventos firmados. El motor publica resume
antes de volver a trasladar. Una revisión firmada por otro móvil resuelve el fence.

### Páginas y reproducción

`GET S/renewal/log/{operationId}/{head}/{after}` devuelve exactamente
`{sourceSyncId,operationId,head,height,after,next,commands}`. El cursor after es la
altura ya obtenida; next es la altura siguiente, o null exactamente al final.
Cada respuesta queda fijada a head aunque se añadan comandos mientras se descarga.
Máximo 256 comandos y 256 KiB de JSON de comandos por página. Se rechazan páginas
vacías intermedias, repetidas, reordenadas o de otra cabeza/operación/origen.
El motor descarga solo el sufijo desde la altura persistida. Un previous privado
y verificado conserva en memoria estado e índices derivados: con la misma
confianza relevante aplica solo el sufijo y comparte el prefijo inmutable de
comandos sin copiarlo. Si cambia el registro o la confianza, revisa el prefijo
completo, incluidos enlaces, roles, colisiones y revocaciones. Una bifurcación
desde una caché ya consumida también la reconstruye. Sin observación anterior,
o al restaurar comandos persistidos, reproduce desde genesis; nunca confía en
índices JSON. Ed25519 verifica el sufijo nuevo y cualquier clave enlazada cambiada.
Las revocaciones actuales se aplican a todas las identidades. El motor persiste los
comandos y la observación antes de actuar; un JSON sin verificar no construye
previous. Un ancla sola prueba continuidad, no sustituye la evidencia verificada.

La reproducción hace una pasada con índices acumulados de hashes, destinos,
identidades, firmantes de acuses y presupuesto de rescate. El tamaño canónico de
cada comando se calcula una vez; no se canonizan prefijos. El Worker consulta
índices SQL por operación/hash/altura, destino, identidad y firmante, y mantiene
contadores de rescate atómicos. Cada escritura resuelve solo la proyección acotada,
sin cargar ni canonizar el registro histórico entero.

`RenewalControl.fromLog` verifica hashes, enlaces, todas las firmas históricas,
roles, versiones CAS estrictamente crecientes y transiciones deterministas.
Compara TODA la proyección recibida con lo reproducido. Un sufijo nuevo no puede
contener un CAS anterior al último GET persistido (P1); participantes cubren la
confianza viva local y no desaparecen entre planes (P2). El cliente deriva todas
las identidades, acuses, exclusiones, ramas y recuperaciones de los comandos.
No utiliza un subconjunto servido por el Worker como lista completa de pruebas.

### Ancla de continuidad y límite criptográfico

La API exige RenewalLogAnchor (origen, operación, head, altura) persistida o
transmitida por un móvil de confianza; el head del Worker no es un ancla externa.
Con previous exige extensión del prefijo y suelo de CAS. Sin previous, el ancla
móvil sigue siendo obligatoria para rechazar un prefijo antiguo internamente
válido o una bifurcación que sustituya un avance ya conocido por ese móvil.
Una firma/chain no prueba frescura global: sin ninguna observación independiente
es imposible distinguir una cola ocultada junto con su cabeza de una operación
que terminó en ese mismo prefijo. Un ancla antigua tampoco revela avances nunca
observados. El motor debe transmitir las últimas cabezas entre móviles, junto
con confianza y revocaciones; no declarar cerrado ese supuesto sin ese canal.

**B7 no proporciona hoy el ancla de renovación**: su aprobación firma hashes del
común y registro, además de minVersion, pero no operación, cabeza ni altura del
registro de renovación. El checkpoint del destino tampoco ancla el del origen.
El motor y el emparejamiento deberán firmar en la aprobación el origen, operación,
cabeza, altura y suelo CAS observado, ligados al contexto exacto del emparejamiento.
RenewalLogAnchor no contiene el suelo CAS: se transmite y persiste por separado.
Nunca se crea un ancla copiando la cabeza del mismo GET que se quiere verificar.
La garantía será «extiende lo observado por ese móvil», no frescura global.

### Topes y salida de saturación

8 KiB por comando; 256 KiB por proyección; 32 participantes, incluidos locales
y web; 8 ramas activas. Antes de iniciar se comprueba la unión completa de
participantes vivos y locales: más de 32 se rechaza, nunca se recorta el plan.
El presupuesto ordinario es 512 comandos / 512 KiB. Al agotarlo, replace devuelve
409 renewal_log_full recuperable. Revise solo sigue disponible para un plan
invalidado. Cada firmante dispone inicialmente de 64 comandos / 64 KiB. Cada
revocación efectiva reinicia los contadores de TODOS los supervivientes:
40 comandos / 40 KiB, hasta 31 reposiciones. El cierre individual de 32
participantes requiere como máximo 37 comandos: resume, revisión, ready, acuse
propio, 31 pérdidas, prepare y confirm. Incluso con ids de 128 caracteres cabe
en 40 KiB. Una revocación efectiva también retira la exclusión del revocador,
sin darle traslado ni acuse, por lo que conserva salida aunque ya haya usado su
único resume ordinario. La barrera permanece e invalida el plan.
El bloqueo por actividad tiene un marcador durable por participante/operación,
independiente del resume firmado; revisar limpia el bloqueo pendiente, pero no
permite volver a activarlo por GET. No se podan pruebas.

revoke, recover y abort no consumen rescate. Como máximo 31 revocaciones dejan
un superviviente; recover exige creador revocado y permite como máximo otra fila
por creador revocado; abort es terminal. La cota conservadora es:

`512 + 32×64 + (31+…+1)×40 + 2×32 + 1 = 22.465 comandos`.

Por bytes: `512 KiB + 32×64 KiB + 496×40 KiB + 65×8 KiB = 22.920 KiB`,
menos de 22,4 MiB. Los topes globales de 24.576 comandos / 24 MiB contienen toda
la reserva, incluidas las filas exentas. Páginas de 256 comandos / 256 KiB,
hasta 512 páginas por operación; la reserva de bytes y comandos también cabe
en ese número de páginas aun con fragmentación por el límite de bytes.
La prueba máxima agota los cupos antes y después de cada una de las 31
revocaciones. Mide reproducción determinista en escritorio, no carga completa
ni firmas en Android. recover/abort válidos siempre caben en la reserva;
sus condiciones de autorización no se relajan.
No se promete reintento infinito: un firmante que agota su propio rescate deja de
poder emitir más progreso ordinario. Los cupos de contenido/altas son independientes.

La barrera se reproduce por transiciones: prepare la crea; revoke y revise la
conservan. replace/recover pueden extinguir la barrera ACTUAL si no queda ningún
acuse histórico de firmante vigente en ese instante del registro. Si ya era null,
un acuse posterior no la resucita. Los vetos se calculan aplicando las revocaciones
ACTUALES a TODAS las identidades reproducidas, incluidas las de la época activa.

## Identidades, compromisos y acuses

Se adopta la decisión B6: nuevos syncId, deviceId, Ed25519, X25519, credencial de
servicio y clave familiar, independientes de los antiguos. No cambia el formato
de declaraciones. El destino arranca con una raíz nueva y registro vacío salvo
su creador. El registro origen se archiva separado; nunca se fusiona en la
confianza del destino. El protocolo rechaza identidades Ed25519/deviceId que
reutilicen fichas del origen o colisionen entre acuses, y comprueba la identidad
del iniciador contra la reserva. Generar el resto de secretos independientes y
comprobar el checkpoint B7 corresponde al motor y al emparejamiento.

Los valores públicos targetCommitment, inventoryCommitment, receipt y
coverageCommitment son opacos. `renewalCommitment(binding:, kind:, salt:, manifest:)`
fija una construcción local: base64url(SHA-256(dominio, NUL, JSON canónico
`{v:1,binding,salt,manifest}`)), con dominio
`gift-huddle-renewal-<target|inventory|receipt|coverage>-v1` y sal aleatoria de
32 bytes guardada junto al manifiesto **solo en el diario cifrado**. No se envían
cantidades ni hashes predecibles de sorpresas. Una revisión nueva genera nuevos
compromisos y acuses; el compromiso original del destino retenido por revise
conserva su binding original y su sal para comprobarlo.

El manifiesto privado de destino compromete la identidad nueva, sus claves
públicas, verificador de credencial, compromiso de la clave familiar y formato
mínimo 2. El inventario cubre común, lápidas, ámbitos autorizados, slots,
overflow, leftOut, retenidos, congelados y operaciones pendientes. Cada entrada
debe conservar su estado de traslado o su pérdida explícitamente aceptada.

El manifiesto privado de receipt liga las identidades origen/destino, el
checkpoint B7 exacto aprobado, el inventario de aportación local incluida la cola,
la publicación aceptada y la instalación durable. El ack público lleva
newDeviceId, newSigningKey, receipt y destinationVersion, además del binding y
CAS firmados por la identidad **antigua**. Se emite después de fusionar, guardar,
publicar, verificar aceptación y activar de forma recuperable. Emparejar solo no
acredita traslado. El acuse es inmutable por participante/revisión. Un reintento
idéntico conserva su validez; otro destino, operación o revisión lo rechaza.

El manifiesto de coverage compromete el inventario acumulado conservado y las
pérdidas explícitas. `pendingResources:0` es una afirmación del cliente, nunca
prueba de descifrado. Preparar fija la barrera en la versión resultante. Confirmar
liga esa misma snapshotVersion tras absorber y publicar la instantánea final.
Una mutación posterior exige confirmar otra vez con CAS nuevo antes de DELETE.
Revocar conserva la barrera e invalida el cierre: revise, ready y acuses/exclusiones
nuevos. Excluir es individual, con loss:true, y no equivale a traslado sin pérdida.

## Modelo local y API de interfaz

`renewal_state.dart` es una proyección persistible sin textos de interfaz ni
detalles secretos. Fases: idle, proposed, preparing, reserved,
publishingDestination, destinationReady, transferring, preparingClose,
absorbingFinalSnapshot, readyToRetire, retired y recovery. El diario del motor
conserva checkpoints más detallados y acciones pendientes; esta proyección no lo
reemplaza. Una vista futura o corrupta falla y exige recuperación, no vuelve a idle.

Cada participante tiene id antiguo estable, id nuevo cuando existe, tipo móvil/web
y estado pending, pairing, transferring, transferred, needsAttention o
explicitlyLost. Las causas de presión y bloqueos son enums. `retryAt` es un instante
UTC persistido y separado del agotamiento permanente de la operación rechazada.
`renewSuggested` es derivado. Umbrales y lectura offline son tarea del motor;
el modelo acepta observaciones tipadas y no depende del endpoint capacity.

`RenewalApi` es una interfaz abstracta para el próximo motor, sin proveedor activo:

| API | Uso |
|---|---|
| state / changes | Estado actual y stream de proyecciones |
| refresh / resume | Revalidar control / reanudar intenciones durables |
| preview / start(review) | Revisar inventario/capacidad y confirmar inicio |
| reconnect(sourceDeviceId) | Entrar en QR/código presencial |
| excludeParticipant(review, sourceDeviceId) | Aceptar pérdida de un participante |
| revisePlan(review) | Revalidación explícita con nueva revisión |
| replaceDestination(review) | Sustitución explícita, preservando la rama anterior |
| abort(review) | Cancelación firmada sin traslados, ramas con acuses ni barrera; conservar la lápida |
| previewClose / close(review, acceptExplicitLoss) | Revisar bloqueos y pérdidas; cierre normal o excepcional explícito |

`RenewalReview` liga un token de checkpoint local durable, origen, CAS y binding
cuando existe. El motor rechaza confirmaciones desactualizadas con
`RenewalReviewChangedException` y obliga a revisar la vista nueva. `preview` debe
servir también para revisar cambios del plan o exclusiones de una operación ya
abierta. Las actions guardadas en la proyección son pistas visuales; no conceden
permisos. Un cierre con pérdida requiere confirmación separada y nunca se anuncia
como conservación completa. Los manifiestos detallados siguen bajo permisos de
sus ámbitos, sin publicarlos en esta proyección.

## Integración pendiente del motor

1. Ejecutar `generationStore.recover()` antes de Gone y antes de exponer ediciones;
   mantener la cola de familia durante preparación/instalación y recargar la
   memoria tras activar. No llamar al reinicio destructivo de generación.
2. `prepare(operationId:, destinationSyncId:)` y `open(syncId)` mantienen contextos
   fijos. Guardar comandos, control aceptado/versiones, sales, manifiestos,
   reviews y vista con journal.read/save/next, preservando los demás campos de data.
3. Verificar el GET con el registro **del origen**, conservar su suelo y el último
   control aceptado. Revalidar permisos en cada transición; recuperar sin destruir
   ante firma desconocida, falta de claves, 404/410, 412, 429 o conflicto renewal_*.
4. Crear la base mínima del destino de hasta 256 KiB antes de reserve/replace.
   Ante CAS perdido, consultar el control y retirar solo la base no reservada.
   Después de reservar se completa la publicación. ready solo después de comprobarlo todo. Guardar
   `data.destinationReady = true` antes de activate(operationId). No mezclar
   registros, paquetes, slots, llaveros ni identidades entre contextos.
5. Leer origen tras activar mediante un lector que no escriba allí. Aplicar B4:
   sin puente legacy automático, sin interpretar contenido ilegible como vacío.
   Conservar HLC, lápidas, campos desconocidos y material pendiente.
6. Confirmar inventarios autorizados y publicación final antes de prepare/confirm
   y DELETE con ETag confirmado. Guardar pérdidas individuales y confirmación
   excepcional. Tras retirada, journal.archive conserva ambos contextos;
   ni archivos ni ramas se podan automáticamente.

Este lote endurece contrato, almacenamiento, transporte y Worker. El motor y el
emparejamiento de renovación siguen pendientes y el flujo no se activa. Pruebas del contrato: firmas Ed25519 y encadenamiento canónico,
interoperabilidad con transporte/falso Worker, replay, firmas manipuladas,
aislamiento de raíz nueva, permisos, cierre y recuperación del estado local.


## Correcciones de seguridad y persistencia del lote 4

Al avanzar de revisión, `plan.sourceVersion >= previous.version`; ninguna firma
nueva puede preceder al último control persistido ni compartir CAS con otro
comando distinto aceptado. Así se rechaza un revise que recibió 412 y reaparece
por GET con versión superior. Se verifica cobertura de los miembros vivos de la
vista local en fromLog (en la reproducción completa). La ausencia del
control conocido no equivale a aborto: solo abortion, un abort firmado, lo prueba.

Las correspondencias y vetos se derivan del registro completo. transfers conserva
por destino el primer acuse y las revalidaciones; los acuses actuales resuelven
participantes. Revocar el reservante exige replace/recover, nunca revise.

Antes de prepare, confirm y DELETE, el motor debe exigir
`destinationRevocationsSatisfied(destinationView, destinationRegistry: ...)`:
las identidades del MISMO destino requieren revocación explícita firmada.
Las de destinos anteriores son vetos permanentes por id Y clave de firma:
el registro completo del nuevo destino no puede contener ninguna ficha que los
reutilice, ni siquiera sin aval. No se necesita la ficha antigua para cerrar ni
se incorpora esa identidad como miembro. Vista y registro deben corresponder;
el motor comprueba el veto también al emparejar y publicar. Antes de DELETE o
archive del diario, guarda el control firmado y las pruebas de confianza del
origen en el contexto duradero del destino. Los transmite y verifica al conectar
otros móviles: siguen siendo prohibiciones tras cerrar la renovación y borrar
el control remoto. El archivo reducido del diario no sustituye esas pruebas. Vaciar
acuses o quitar avales no basta. Revocar en origen y destino será UNA operación
recuperable con diario, con rotación de la clave común del destino y de los
ámbitos que correspondan. Ninguna fase pendiente concede claves nuevas al
revocado. El Worker no certifica la confianza criptográfica del destino.

Solo se añade un destino a branches si tuvo algún acuse, incluso en una revisión
anterior. replace exige ausencia de traslados, caller trasladado o
needsRevalidation. ready solo lo firma el reservante o un trasladado. abort es de
móvil vigente y solo sin traslados, ramas con acuses ni barrera; deja lápida firmada en abortion,
reintentar devuelve la misma lápida y permite una operación nueva con otro id.
Una lápida recién presentada exige autoridad actual. Si previous ya la aceptó y
persistió, revocar después al firmante no elimina su autenticidad histórica ni
impide empezar otra operación con ese previous.
Invitar y aprobar vuelven a estar permitidos. No hay caducidad tácita.

Revocar y revisar nunca levantan la barrera: su prepare firmado permanece en
barrier. Una sustitución firmada puede levantarla solo si no queda ningún
trasladado legítimo (ningún acuse conservado de credencial vigente); el cliente
exige también la revocación de esas identidades en su vista del origen. La rama
anterior se conserva si recibió acuses. Si queda un trasladado, barrera y prueba
firmada sobreviven hasta un nuevo cierre o sustitución legítima.

No se excluye a un participante ya acusado. Un traslado histórico revocado se
puede resolver como pérdida en la revisión nueva, tras invalidar sus acuses.
Para un participante sin traslado, se exige revocación del servicio o **72 horas**
sin peticiones autenticadas individuales. Este plazo evita la exclusión inmediata;
no prueba pérdida. Credenciales antiguas sin fecha inician el plazo al observarlas
por primera vez; los participantes locales sin credencial lo inician al reservar.
La actividad autenticada de un excluido, mientras no haya confirmación vigente,
fija un bloqueo conservador de servicio y avanza el CAS. Rechaza prepare/confirm y
DELETE hasta un plan nuevo o resume firmado. No retira pruebas del registro ni
inventa una firma. resume retira la exclusión propia y exige revisar y resolver
al participante con acuses nuevos. Un excluido no puede usar revise para ratificar
su exclusión. El motor sigue exigiendo decisión humana individual de pérdida.

Se elige **creación mínima antes de reserve**, manteniendo el binding existente
y evitando un segundo formato de revelación. El router comprueba por RPC interna
que ya existen la credencial móvil creadora vigente y la ficha con
newDeviceId/newSigningKey comprometidos. El origen autentica y aplica CAS antes
de aceptar; falla con renewal_destination_missing si no existe esa base. La
consulta precede al cerrojo del origen para evitar cerrojos cruzados. No comprueba
firmas ni demuestra conservación. El motor verifica la creación con sus propias
credenciales antes de publicar el identificador; ante respuesta perdida lee antes
de borrar, y ante CAS perdido retira exclusivamente su destino no reservado con
DELETE condicional, sin tocar la rama ganadora.

### Correspondencia remota y preparaciones por destino

Una operación remota mantiene `(operationId, sourceSyncId)` en cada sustitución.
Cada target tiene una preparación local independiente.
`GenerationStore.prepareReplacement(operationId:, destinationSyncId:)` selecciona
el origen del diario aunque la generación activa sea un destino; genera secretos
nuevos y persiste la selección completa en UNA escritura cifrada antes de registrar
e instalar el namespace. No se archiva la operación para reutilizar su id:
journal.save sigue prohibiendo sustituir destino/preparación; solo
journal.replaceDestination permite esa transición y valida su historial.

`data.operationContext` conserva el control aceptado, suelo de versión y acciones
remotas globales; el motor guarda ahí esos datos. `data.previousPreparations`
indexa por destino checkpoints, sales, manifiestos, preparación e intenciones
anteriores mientras la operación siga abierta. previousDestinations permite
cambiar el puntero desde un destino anterior. La nueva preparación reinicia
preparationInstalled, destinationReady y activationPrepared; una publicación
anterior no autoriza activarla. Siempre se usa un destino nuevo. El reintento
reutiliza la selección y claves persistidas. recover() instala esa selección tras
interrupción antes o después de cualquier escritura; si aún no fue guardada,
sigue vigente la anterior. No se elimina ningún contexto ni se toma la generación
activa como origen nuevo.

Al terminar, archive retiene solo ids de operación/origen/destino y un hash
canónico del diario: elimina preparaciones completas, checkpoints y secretos
duplicados del archivo. Los contextos siguen registrados y no se podan. El motor
solo archiva después de guardar en sus contextos toda recuperación necesaria.
El borrado confirmado tolera directorio, índices o inventario dañados: persiste la
intención, borra primero todos los secretos y después lista y elimina ficheros
generation.*, family.* y device.*. Se reanuda incluso después del vaciado del
almacén seguro. El contador durable de activación invalida saveDoc de manejadores
no fijados hasta recargarlos; los contextos fijados mantienen su generación.

## Obligaciones pendientes del motor y del emparejamiento

- Declaración de traslado firmada con la clave antigua, ligada a operación,
  revisión, ambas identidades y checkpoint exacto; continuidad de persona y tipo.
- Comprobaciones propias del invitado de claves, anfitrión, registro, código y
  checkpoint; ninguna ficha del destino hereda campos, avales o confianza del origen.
- Persistir el último control y el suelo de versión antes de mostrar acciones;
  comprobar cobertura de participantes vivos en la vista local y todos los CAS.
- Revocación doble con diario y rotación de clave común del destino; exigir el
  predicado de revocaciones antes de prepare, confirm y DELETE. ready es una
  afirmación: el motor comprueba publicación y conservación por separado.
- Serializar ediciones, instalación y activate; recargar atómicamente la memoria
  tras activar. Mantener sales/manifiestos en el diario cifrado y utilizar las
  preparaciones y referencias por destino descritas arriba.
- Cablear eraseAllConfirmed al borrado confirmado del usuario y recover() antes
  de editar, sincronizar o tratar Gone; nunca reiniciar destructivamente el origen.
- Copias y web exportan solo la generación activa. El traslado web conserva cola
  y usa identidad, credencial, guarda y claves nuevas, sin heredar credenciales.
- Ante renewal_branches_full, renewal_frozen o 429, guardar estado y bloqueos;
  respetar Retry-After y no reintentar en bucle. La falta de capacidad no permite
  podar ramas ni claves con referencias de recuperación.

## Pruebas de cierre de esta ronda

Obligaciones adicionales de integración de la revisión de código (el flujo sigue desactivado):

- Obtener ancla y suelo CAS mediante el intercambio autenticado descrito arriba;
  persistir registro completo, última observación y suelo antes de actuar.
- Descargar páginas fijadas a una cabeza y pasar siempre por fromLog. Ni una
  respuesta de escritura, ni una proyección estructural ni un control ausente
  acreditan transición o aborto.
- Conservar claves históricas y pruebas de confianza; aplicar revocaciones
  actuales a todas las correspondencias. Exigir vista y registro coherentes antes
  de preparar, confirmar, borrar, emparejar y publicar.
- Guardar en el destino registro y pruebas del origen ANTES de DELETE y ANTES de
  reducir el diario. Demostrar reinicio y reconexión cuando el origen devuelve 410.
- Reproducir fuera del hilo de interfaz, con límites efectivos de descarga,
  estado e índices conservados dentro del objeto verificado y aplicación solo
  del sufijo si no cambia la confianza relevante. Un cambio de confianza obliga
  a revisar el prefijo; nunca se confía en índices persistidos como JSON.
  **Antes de activar el motor es obligatorio medir carga completa desde cero,
  firmas Ed25519 y memoria en Android release**, incluyendo descarga, parseo,
  hashes, reproducción y GC. Registrar dispositivo, tiempos y pico de memoria;
  una segunda reproducción con objetos en caché no acredita esta obligación.
- Mantener el flujo desactivado hasta integrar y probar estas obligaciones. Si
  apareciesen operaciones del formato antiguo, exigir su migración explícita.

- Worker: append atómico/prev, páginas fijadas a cabeza, idempotencia, cupos ajenos
  llenos, ocho ramas + revocación + recuperación + cierre, M1 por bytes y proyección
  pequeña, regresión de barrera extinguida y protecciones de roles/CAS/cierre.
- Dart: omisión intermedia, cola truncada, reordenación, bifurcación, prefijo
  autoconsistente frente a ancla móvil, con/sin previous; igualdad de reproducción
  paginada y sufijo persistido; correspondencia de Nora después de recover y
  revocación tras replace, con veto de alias sin aval; barrera retenida/extinguida;
  revocación del mismo destino; saturación de bytes y cierre con/sin previous.
- P1/P2 y N2/N3/N6 se verifican contra el registro; las pruebas existentes de
  familia siguen cubriendo M2/M3/B4. El motor no se modifica en esta ronda.

La persistencia y transmisión tras DELETE sigue ABIERTA hasta integrar y probar
el motor: guardar comandos completos, ancla, confianza del origen y revocaciones
actuales en el destino ANTES de DELETE o reducción del diario; reenviar/verificar
al reconectar; aplicar vetos al emparejar, publicar y cerrar. Debe demostrarse con
reinicio, origen retirado y otro móvil reconectado. Un digest del diario reducido
no conserva esas pruebas. Tampoco esta interfaz implementa el canal de anclas.

Las credenciales nuevas, incluida la creadora, exigen clave de firma al
registrarse. Las antiguas sin enlace inmutable no pueden renovar: devuelven
`renewal_key_binding_required` hasta una migración explícita y autenticada.
Nunca se fija ni recupera la clave desde una ficha del registro mutable.
