# ADR 0005 · Rotación de la clave común por época, firma del común, checkpoint al emparejar y slots ajenos

Recuperación personal: [ADR 0007](0007-recuperacion-con-codigo.md) conserva el
llavero completo, sus épocas históricas, procedencias, contextos y suelos de
revisión. Restaurar no autoriza retroceder formato ni confiar en paquetes sin verificar.

Estado: aceptada (decisión de producto, 2026-11-13: «todo antes de tiendas»). Propuesta de la revisión de código, validada antes de su adopción. Completa el ADR 0004 («Pendiente de la 2b») y los puntos «antes de tiendas» de la revisión de seguridad de la fase 2b.

Los enlaces de abajo apuntan al worktree en el que se hizo la revisión; las rutas relativas desde `app/` y `server/` son las mismas.

Nota (2026-11-14): los ficheros de intercambio y las copias se exportan ahora como `.gifthuddle`, con MIME `application/vnd.gifthuddle` y UTI `es.gifthuddle.app.exchange`. Los dos UTI anteriores se conservan como importados en iOS. Se siguen aceptando los `.regalos` antiguos; el contenido determina el formato y no cambia el cifrado. Las menciones a `.regalos` en los ADR anteriores y en las revisiones de seguridad conservan su nombre histórico.

## Plan por lotes (líder)

1. **B1 · Formatos** (`app/lib/core/sync/`, Dart puro): `FamilyCandidate`, `KeyBundle v4` para `scope: family`, sobre común firmado nuevo, llavero común; vectores Dart ↔ WebCrypto.
2. **B2 · Slots ajenos**: el Worker rechaza toda delta de slot que no sea del propio móvil; la app quita la poda remota ajena.
3. **B3 · Motor móvil**: ciclo nuevo (sección 4), candidatas, reparto recuperable, persistencia de intenciones, retención y capacidad.
4. **B4 · Migración y corte**: clave legacy histórica, clave nueva, formato mínimo en el Worker, cerrar el puente v1.
5. **B5 · Web**: llavero común en la caja, abrir por `kid`, firmar el común.
6. **B6 · Ficheros `.regalos`**: contenedor firmado con paquetes; los de recuperación van con la fase 3, lote 5.
7. **B7 · Checkpoint al emparejar**: aprobación nueva, recurso inmutable por invitación en el Worker (hecho: ver «B7 hecho»).

Cada lote pasa por implementación, revisión de seguridad y verificación antes de fusionar.

## Decisiones de B1

Código en `app/lib/core/sync/family_candidate.dart`, `family_key_bundle.dart` y `family_envelope.dart`; vectores en [`0005-vector-clave-comun.json`](0005-vector-clave-comun.json). Incluye los arreglos de la revisión de seguridad (M1-M3, B1-B3, B5-B7, B9).

1. **Contexto de época.** Es el SHA-256 en hexadecimal de `"gift-huddle-epoch-context-v2" ‖ 0x00 ‖ JSON canónico {l, m, r, sid, v:2}`:
   - `m` son los activos con el resumen de su ficha (las webs confirmadas incluidas) y `r`, los revocados y ambiguos.
   - Sale solo de la `RegistryView`, sin cambiar el formato del registro.
   - **No lleva el número de época** (M1): ese número suma el `seq` de revocados y pendientes, que pueden publicar fichas nuevas sin cambiar quién recibe la clave.
   - Cada dispositivo lo recalcula desde su vista. No hay un descriptor firmado aparte: el contexto va dentro de lo que firman el creador, el emisor del paquete y el escritor del sobre.
2. **kid y firma del creador.**
   - El `kid` es SHA-256 en hexadecimal (el orden de texto coincide con el de bytes) sobre lista, generación, número de época (descriptivo), contexto, creador, audiencia y secreto. La audiencia queda inmutable por construcción.
   - **El creador firma la candidata** (M3): Ed25519 con dominio `gift-huddle-family-candidate-v1` sobre {a, c, cr, ctx, e, kid, l, s, sid, v}. Al abrir el paquete se comprueba con la ficha `cr`, que tiene que ser de un móvil del registro.
   - **El creador tiene que ser el nodo enlazado desde el ancla de quien abre** (R1): la ficha `cr` tiene que ser de un móvil y llevar la clave de firma con la que ese id está enlazado por avales (`RegistryView.linkedSigningKey`; vale también un revocado al que se llega). Una ficha autofirmada sin aval, con otro id o con el de un miembro, no sirve; un id ambiguo o no enlazado se rechaza.
   - Garantía: nadie puede acuñar una candidata a nombre de un móvil enlazado sin sus claves; quien reparte solo reenvía candidatas que ese móvil firmó.
   - `FamilyCandidate.signed` y `fromJson` no verifican al creador; al llavero como recibida solo entra lo que sale de `FamilyKeyBundle.open`. B6 (`.regalos`) y B7 (checkpoint) tienen que verificar igual.
3. **Paquete v4.**
   - Lleva `c`, `cr` y `cs` (creador, su ficha y su firma) en la cabecera y en el AAD; el texto cifrado va en `ct`.
   - Exige exactamente sus claves (B5) y base64url canónico.
   - Al abrir comprueba que cada par (móvil, ficha) de la audiencia existe en el registro (M2), además de lo de v3 y el `kid` recalculado.
   - El número de época no se compara con el del registro.
4. **Sellar.**
   - `sealableIn`: misma lista y generación, contexto actual, y audiencia exactamente igual a los activos con su ficha.
   - El llavero elige la de `kid` menor entre las no históricas ni comprometidas. El número de época no cuenta (M1).
   - Solo crea un móvil activo y aprobado con sus propias claves; una web con la vista de su raíz, no (B1).
5. **Sobre común.**
   - Prefijo `RG 0x02`; la cabecera tiene que ser canónica byte a byte, solo con las claves esperadas (se rechazan claves repetidas, `1.0`, `1e0`, `-0`, escapes, espacios y BOM).
   - La clave AES sale de HKDF-SHA256 (sal vacía, `info` = dominio ‖ 0x00 ‖ `kid`) (B7).
   - El escritor tiene que estar en la audiencia de la candidata con su ficha, al sellar y al abrir (B6). `sealFamilyEnvelope` recibe su `KnownDevice` y exige que la clave del firmante sea la suya (B1).
   - Topes: el sobre ≤ 2 MiB y la cabecera ≤ 1 KiB antes de pedir la clave al resolvedor; lo descomprimido ≤ 8 MiB.
6. **Llavero.**
   - Guarda la procedencia: propia, o recibida de qué emisores con su ficha.
   - Las recibidas sin referencias y no buscadas tienen cupo, sellen o no (R4): 8 por creador autenticado y 64 en total. Pasado el cupo se desalojan solo las de ese creador, o las del creador que más tiene: primero las que no sellan y, dentro de cada grupo, de `kid` mayor a menor.
   - Quien llama pasa `wanted`, los `kid` que necesita (p. ej. los de sobres vistos con `peekFamilyEnvelope`); las buscadas no se desalojan ni se podan (R3).
   - Las propias, las referenciadas y las buscadas siempre caben, hasta un tope duro de 256 que da contrapresión (`FamilyKeyringFullException`) en vez de desalojar.
   - `pruneRevoked` quita solo las recibidas sin referencias ni buscadas cuyo creador **y** todos sus emisores están revocados (R2): una clave de antes de la revocación que reenvía un miembro honrado se queda.
7. **Enteros** (B9). En la VM un `1.0` no es entero y se rechaza. En dart2js `1.0` y `1` son el mismo número, y como todo se vuelve a codificar en forma canónica para firmar y para el AAD, el resultado es idéntico. En la cabecera del sobre, que llega en bytes, `1.0` se rechaza en las dos plataformas.

**Pendientes:**

- **B3 (motor)** (hecho: ver «B3 hecho»):
  - Un escritor activo con la clave puede publicar un común bien firmado que no se puede leer (una candidata que solo tiene él, o basura cifrada con una buena). El motor no debe darlo por vacío ni sustituir con él lo que tiene.
  - Cómo se resuelve un escritor con una ficha ya histórica (el resolvedor recibe `writerRecord`).
- **B4 de la revisión de seguridad (en el lote B5)** (hecho: ver «B5 hecho», 7): vectores en WebCrypto o dart2js.
- **B8 de la revisión de seguridad (en B3/B4):** cerrar la vía v3 con `scope: family` (`KeyBundle.sealFamilyKey` y `openFamilyKey` siguen existiendo). Hecho en B3 detrás del interruptor; falta usarlo en el emparejamiento (B7).
- **X25519:** las formas ≥ p sin el bit alto dan secreto de ceros y se rechazan como orden bajo. Las que tienen el bit alto no son puntos de orden bajo según el RFC 7748, que enmascara ese bit; la biblioteca da otro secreto y el paquete se rechaza porque falla el GCM. Confirmado con WebCrypto en B5 («B5 hecho», 7).

## B2 hecho

Sección 7 aplicada en el Worker y en la app; contrato en `server/README.md` («Slot ownership» y `POST S/revoke`).

1. **Worker** (`server/src/list-v2-object.ts`, `slotOwnership`):
   - Toda entrada de la delta de slots, con datos o con `data: null`, exige `role: device` y `deviceId` propio, al crear y al actualizar. Una sola ajena rechaza la petición entera con `403 forbidden_slot`, antes de escribir nada; la web es `403 forbidden_role`. El servidor no sabe de personas ni de épocas: el slot de un revocado, de un huérfano, de una persona borrada o de una época vieja es, para él, el recurso de otro escritor.
   - `If-Match` global exacto, como antes. Un recurso repetido en la delta es `400 bad_request` (ya lo era). Sustituir el slot propio es un `UPSERT` de una fila dentro de la transacción del `PUT`: nunca se borra antes de escribir.
   - `capacity.slots` (`used`, aviso 48, tope 64): los abandonados cuentan y `renew` se enciende desde el aviso.
   - `POST S/revoke` acepta `If-Match` opcional: con él, `412` (y el `ETag` actual) si la versión no es exactamente esa; sin él, incondicional como antes (las explícitas, como «Quitar un móvil», salir de la familia o la web que se revoca a sí misma, y los móviles viejos).
2. **App:**
   - El motor ya no manda `data: null` para slots ajenos (se quita la poda remota de `sync_v2_engine.dart`). Se conserva la distinción: `openScope` ignora lo que no cuenta y `SlotSet.pruned` lo quita solo de la copia local; nada ajeno se destruye en el servidor. `leaveFamily` sigue retirando los slots propios.
   - Los slots que el motor ignora se apuntan en `V2SyncState.ignoredSlots` con su versión y su motivo, y no se vuelven a bajar mientras esa versión no cambie: los de un escritor revocado de verdad (revocación firmada y sin ambigüedad: `linkedSigningKey` no es null), los de un escritor desconocido (`view.device` es null: falso, ambiguo o revocado sin enlace; la entrada dura mientras siga sin conocerse) y los ilegibles. Un id ambiguo puede aclararse, así que no es una revocación definitiva: tras calcular la vista, la entrada de un escritor que ya no está revocado de verdad se borra y el slot se vuelve a bajar en la vuelta siguiente.
   - Antes de sustituir su slot, el motor abre el anterior, fusiona, guarda y vuelve a sellar; si no puede abrirlo, `publishScope` lanza `SlotPublishBlockedException` y no lo reemplaza (ya era así; ahora tiene prueba de motor).
   - Presión de capacidad por `renewSuggested`: `capacity.renew` del servidor o, con un servidor anterior, el manifiesto con 48 slots o más (`kV2WarnSlots`).
   - Las revocaciones condicionales (`revokeUnbackedCredential`, que procesa `_retryPendingUnbackedRevocations`) mandan la versión del `GET` verificado (`revoke(..., ifVersion:)`). Ante `412` (`V2RevokeStaleException`) se vuelve a bajar, verificar y decidir; tras `maxRestarts` seguidos la intención queda pendiente y la vuelta sigue normal (no se aborta); `revokeUnbackedCredential` lo dice con un error de servidor. No hay escape incondicional: una credencial sin respaldo que siga viva un rato es aceptable frente al riesgo de revocar una respaldada. Las explícitas siguen sin precondición. Cierra el `TODO(B2)` del lote 3a.
**Tras la revisión de seguridad (disponibilidad):**

- **M1.** Un slot que no se puede leer ya no tumba la vuelta de la familia: el motor lo cuenta como rechazado, lo apunta como ignorado en esa versión y sigue. El Worker solo guarda slots que `SealedSlot.parse` aceptaría: tamaño exacto (cabecera + 131 164 bytes, medido por la longitud del texto), flags 0 o 1 y revisiones < 2^53.
- **M2.** Con la lista llena (64) o el escritor en su tope (32, `V2_MAX_SLOTS_PER_WRITER` y `kV2MaxSlotsPerWriter`), el motor quita de la delta las altas propias, nunca las sustituciones, y sube igualmente el común, el registro y los paquetes. Lista llena: `V2SyncOutcome.slotsFull` y `renewSuggested`. Escritor en su tope: `writerSlotsFull`, en `V2SyncOutcome` y en `V2Health`, aparte, porque renovar no lo arregla (la interfaz lo enseñará en el lote 6). El tope es 32 y no 16 porque, con 2 o 3 móviles, 16 limitaría las personas protegidas. Además retira sus propios slots de personas borradas y, con la ficha aprobada, el de su propia persona. El Worker limita a 32 los slots de un escritor (`413 too_many_writer_slots`) para que una credencial no agote el cupo de la lista, y `approve` rechaza un id con filas de slot heredadas.

3. **Pruebas:** `server/test/v2.test.ts` («B2: no device touches another writer's slot», «B2: conditional revocation»); `app/test/sync/sync_v2_engine_test.dart`, `v2_health_app_test.dart` y `transport_v2_test.dart` (las que empiezan por «B2»).

**Queda (aplazado):**

- **Recolección ajena de slots.** Si hace falta antes de renovar, con una autorización del propietario del slot ligada a generación, recurso, hash exacto y sustitución concreta (sección 7). Hasta entonces, los abandonados solo se van con la renovación.
- `renewSuggested` ya llega al aviso de `v2_health_notices.dart`; el flujo de renovación en sí es de la fase 3.
- Límite que sigue escrito: mientras cualquier móvil pueda revocar a otro y exista `DELETE` de lista, no hay disponibilidad garantizada frente a un miembro malicioso.

## B3 hecho

Motor de los móviles con la clave común por época. Código en `app/lib/features/sync/application/common_v2.dart` (estado, piezas puras y `CommonV2Cycle`) y `sync_v2_engine.dart`; persistencia en `family_store.dart` y `app_sync_v2_local.dart`.

1. **Interruptor.** `V2SyncState.commonFormatV2` (`cf`), apagado por defecto. Apagado, el motor es el de antes: el común en formato 1 con la `familyKey`, sin paquetes v4 ni llavero común (todas las pruebas anteriores siguen igual). Lo enciende B4 con la migración.
2. **Ciclo encendido** (sección 4):
   1. Operaciones recuperadas.
   2. Instantánea.
   3. Registro verificado y fusionado.
   4. Permisos y cortes. El contexto no depende de las personas, así que el común va después del registro.
   5. `receive` abre los paquetes v4 dirigidos a este móvil con `FamilyKeyBundle.open` y los guarda con `withReceivedCandidate`. Pasa en `wanted` los `kid` del común remoto (`peekFamilyEnvelope`), de los retenidos, del último común y de la intención de reparto, y aplica `pruneRevoked` con ese `wanted`.
   6. Verifica, abre y fusiona el común.
   7. La vista se vuelve a calcular con las personas del común fusionado y siguen las sorpresas, como antes.
   8. `prepare` elige la sellable de `kid` menor o crea una (`FamilyCandidate.generate`).
   9. Reparte esa candidata a su audiencia activa que no tiene paquete **propio** de este móvil (M1), también a los desconectados. Guarda candidata, paquetes (`outbox`) y revisión en una sola escritura, **antes** de sellar. Sella con `sealFamilyEnvelope` y sube con `If-Match`. `accepted` saca de la intención lo que entró.
   - Un `412` vuelve a empezar: abre la candidata del otro y sella con la de `kid` menor.
3. **Referencias** en el llavero:
   - `common`: el último común abierto o publicado.
   - `outbox`: la intención de reparto.
   - `retained:<hash>`: cada retenido con bytes.
   - Por encima de 192 claves (`kCommonKeyringSoftLimit`) se olvidan las que no sellan, sin referencias ni buscadas, de época más baja primero. El tope duro de 256 da `commonKeyringFull`; un paquete que no cabe no corta los demás (B3 de la revisión de seguridad).
4. **Escritor.** `commonWriterResolver(view, registry)`: solo un miembro activo, con su ficha actual o con una ficha anterior del mismo id, del mismo tipo y con la misma clave de firma (selló antes de cambiar de persona). Un pendiente, un ambiguo o un desconocido devuelven null. Vale igual para la web (B5).
5. **Común remoto que no se abre** (`RemoteCommonStatus`; tras la revisión de seguridad, A2):
   - Nunca se sustituye mientras espera. Se sube el registro, los paquetes y los slots con los mismos bytes del común, para que quien tiene la vista atrasada se ponga al día. Mientras espera, los slots no se vuelven a sellar en cada vuelta (B1 de la revisión de seguridad).
   - **Espera sin plazo**, con `V2Health.commonBlocked` y el escritor en `commonBlockedWriter`:
     - `missingKey`: firma válida de un miembro activo, pero falta su candidata;
     - `unknownWriter` de un dispositivo conocido cuya firma vale (N1 de la revisión de seguridad). Antes de esperar se comprueba la firma con `knownWriterKey`: la clave enlazada de ese id o, si no la hay, la de la ficha `wr` del registro, si es de ese id, tiene presencia enlazada y todas sus fichas llevan la misma clave. Si la firma no vale, es `forged` y se sustituye ya, sin nombrar a nadie: cualquier credencial, o el servidor, puede poner un id ajeno en la cabecera.
     - Lo resuelve una persona confirmando o revocando. Al revocar, ese común pasa a `revokedWriter` y se sustituye en esa vuelta.
     - Así dos huérfanos mutuos (cada uno ve al otro fuera) no se pisan el común en vaivén.
   - **Salida automática solo para la basura demostrable**, tras 3 vueltas de `sync()` con el **mismo** común (`kCommonUnreadableRounds`; `CommonBlock` va atado al hash y cuenta una vuelta por `sync()`, no por reintento tras `412`, ni por reloj de pared: B5 de la revisión de seguridad):
     - `unreadable`: escritor autenticado y la candidata exacta en el llavero, y no abre;
     - `unknownWriter` que no se puede autenticar (ningún dispositivo con ese id y una clave clara).
     - Un común ilegible distinto vuelve a empezar la cuenta. El sustituido queda retenido para la recuperación explícita; nada se pierde, porque cada escritor conserva su documento local.
   - **Se sustituye ya**:
     - `forged`: firma que no vale, otra lista, bytes rotos, o un formato 1 después de haber pasado al 2 (M2);
     - `revokedWriter`: solo si la firma vale con la clave enlazada del revocado (B2 de la revisión de seguridad); si no, es `forged`.
     - Lo de un revocado no se fusiona nunca, ni al reintentar. Lo que se aceptó antes de conocer la revocación sigue en el documento local.
   - **Formato posterior** (`RG` con versión > 2, M4): `EnvelopeFormatException` («hay que actualizar»); ni se retiene ni se sustituye.
   - **Contrapartida** (propuesta de la revisión de seguridad, aceptada por el líder): un miembro activo malicioso puede bloquear el común (`missingKey` con una candidata que solo tiene él) hasta que lo revoquen. Cabe en el límite ya escrito en B2: sin coordinador no hay disponibilidad frente a un miembro malicioso.
6. **Retenidos** (M3):
   - Un índice cifrado (`family.retainedcommons`) y un fichero cifrado por retenido con bytes (`family.retained.<hash>`), que solo se lee para reintentar.
   - Cupos separados: 4 que esperan (con bytes), 2 de revocados (con bytes) y 16 falsos (solo el resumen). Un falso nunca desaloja a uno que espera.
   - Orden de escritura: bytes, índice, referencias y, al final, el borrado de lo que sale.
   - Antes de escribir unos bytes se apuntan en un diario del almacén seguro (`family.retainedPending`), porque el almacén de ficheros no se puede listar. Al leer o escribir el índice se borran los apuntados que no están en él (huérfanos de un cierre), y `clear()` borra los del índice y los del diario.
   - Un índice que no se lee, un motivo `opened` o unos bytes que faltan lanzan `CommonStateException`: nada se descarta en silencio (B4 de la revisión de seguridad). Un retenido que se abre pero trae un protocolo desconocido se conserva tal cual.
7. **Reparto y capacidad** (A1 de la revisión de seguridad):
   - Los paquetes v4 ajenos solo se vuelven a subir si sirven (`usefulFamilyPackage`):
     - que se lean;
     - que ni el emisor ni el destinatario estén revocados de verdad;
     - que sus fichas `fr` y `tr` estén en el registro (la del emisor, de un móvil);
     - y que la firma del emisor valga con ellas (`FamilyKeyBundle.verifySender`, nuevo, sin tocar el formato).
   - De cada emisor, como mucho 128, primero los de las candidatas en juego.
   - Los propios solo se retiran cuando son de una candidata con la que ya no va el común que se sube, o si su destinatario ya no está activo con esa ficha.
   - Presupuesto (`budgetPackages`), en número (512) y en bytes (256 KiB):
     1. primero el reparto propio del común (lo único obligatorio);
     2. después los v4 ajenos de las candidatas en juego;
     3. después los v3 más nuevos;
     4. después los v4 ajenos de otras candidatas.
   - Nunca sube una entrada repetida: el Worker rechaza la lista entera (`400 duplicate_package`).
   - Lo propio (v3 y v4 juntos) se ajusta al tope por escritor del Worker quitando los v3 propios más antiguos (`trimOwnPackages`), para que el `PUT` no falle; el reparto v4 no se toca.
   - Solo si el reparto no cabe ni solo hay contrapresión: no se sustituye el común, la intención queda guardada, y salen `commonPackagesFull` y `renewSuggested`.
   - **Worker:** una entrada nueva de `keyPackages` solo entra si `from` es quien llama (`403 forbidden_package`), solo con `v` 3 o 4 (`400 bad_package`), y con un tope **combinado** por escritor de 128 entradas y 64 KiB, la cuarta parte de la lista: hacen falta al menos cuatro credenciales para llenarla y bloquear una rotación (`413 too_many_writer_packages`). Una lista con dos entradas iguales es `400 duplicate_package`. Las guardadas que se reenvían tal cual se conservan y quitar siempre vale (`server/README.md`, «Key package ownership»).
8. **Persistencia.**
   - `CommonKeyState` (llavero, `outbox`, revisión, `lastKid`, bloqueo) va en `family.commonkeys`, cifrado con la clave local y con `writeAtomic`.
   - Una marca en el almacén seguro (`family.commonKeysMarker`) dice que ya se guardó alguna vez. Si con ella falta el estado, hay `CommonStateException` y no un llavero vacío (B4 de la revisión de seguridad). Todo se borra al salir.
   - Cerrar en cualquiera de los guardados nunca deja un común publicado sin su clave guardada. Si el `PUT` entró y se perdió la respuesta, el móvil abre su propio común al volver.
9. **No sellar sin repartir** (B6 de la revisión de seguridad): quien no puede repartir (pendiente, sin aprobar) nunca sella; sube los mismos bytes.
10. **Vía v3.** `KeyBundle.sealFamilyKey` y `openFamilyKey` aceptan `commonFormatV2` y, con él, lanzan. El motor encendido no usa paquetes v3 de la familia.
11. **Pruebas:**
   - `app/test/sync/common_v2_engine_test.dart` (38 casos). Además de los 19 primeros, las sondas de la revisión de seguridad P1-P7 convertidas en pruebas:
     - huérfanos mutuos sin vaivén;
     - inundación v3 y v4 seguida de revocación, que rota igual;
     - paquete ajeno falso;
     - formato 1 tras el 2;
     - falsos que no desalojan al que espera;
     - un segundo ilegible que reinicia la cuenta;
     - formato posterior.
   - Y las que faltaban:
     - dos revocaciones distintas a la vez;
     - `unknownWriter` sin presencia;
     - basura cifrada con la clave buena;
     - primera vuelta en formato 1;
     - escritor con su ficha anterior;
     - tope de retenidos;
     - clave referenciada frente al recorte y a `pruneRevoked`;
     - cierre entre el índice y las referencias;
     - `ensureCreated` encendido;
     - estado perdido o índice dañado;
     - presupuesto de paquetes;
     - el Worker falso con la regla del escritor.
   - `app/test/family/device_keys_store_test.dart` (B3): cifrado, ficheros de retenidos, marca, reapertura y borrado.
   - `server/test/v2.test.ts`, «B3: key packages belong to their writer» (5 casos).

**Queda:**

- **B4** (hecho: ver «B4 hecho»):
  - Encender `commonFormatV2` con la migración coordinada.
  - Importar la `familyKey` como candidata histórica (`withOwnCandidate(..., historical: true)`).
  - Marca local irreversible de formato mínimo y formato mínimo en el Worker.
  - Del formato 1 solo queda la primera vuelta: mientras el móvil no ha abierto ni publicado un formato 2 (`lastKid` nulo), lo abre con la `familyKey` y lo pasa al 2. Después es `forged`.
  - Validar en el Worker el byte de formato del común (hoy acepta cualquier base64url).
- **B5 (web):**
  - Llavero común en la caja y abrir por `kid` con `commonWriterResolver`.
  - Firmar el común con la web y conservar la cola si el común está bloqueado.
  - Como la web no reparte, nunca debe sellar con una candidata cuyo reparto no esté hecho (la regla de B6 de la revisión de seguridad vale también para ella).
  - Hasta entonces, una web no abre el común en formato 2: el corte tiene que ser coordinado.
- **B6:** `.regalos` con paquetes v4. Las candidatas importadas solo entran tras verificar al creador.
- **B7:**
  - El anfitrión sigue sellando la `familyKey` en v3 al aprobar (`pairing_v2_flow.dart`, sin tocar). Con el interruptor tiene que pasar `commonFormatV2: true` y entregar un paquete v4 con el checkpoint.
  - El invitado arranca hoy con el interruptor apagado.
- **Interfaz (lote 6):**
  - Avisos de `commonBlocked` (con `commonBlockedWriter` y «Confirmar» o «Revocar»), `commonPackagesFull`, `commonKeyringFull` y `retainedCommons`, y la recuperación explícita de los retenidos.
  - **Revocar al móvil que emparejó a los demás** los deja huérfanos entre sí: cada uno ve al otro fuera de la familia y el común deja de circular hasta que se reconfirmen uno a uno. La interfaz tiene que avisarlo antes de revocar y guiar la reconfirmación.
  - **Un móvil pendiente** (por ejemplo, tras cambiar de persona) ve `commonBlocked` con el id de un miembro honrado: no tiene la clave porque aún no lo han aprobado, no porque ese miembro haga nada mal. El aviso tiene que explicarlo y no sugerir revocarlo.


## B4 hecho

Migración y corte de una familia v2 que ya existe al formato 2 del común, sin cambiar `syncId`, credenciales ni identidades. Código en `app/lib/features/sync/application/common_v2_cutover.dart` (decisiones y arranque compartido), `sync_v2_engine.dart` (la vuelta), `common_v2.dart` (`importLegacyKey` y `receive(legacyKey:)`) y el Worker (`server/src/list-v2-object.ts`, `v2-contract.ts`; contrato en `server/README.md`, «Common format»).

1. **Bloqueado por defecto.** `kCommonV2Ready = false` (y `SyncV2Engine.commonV2Ready`, que las pruebas encienden). Apagado, el móvil ni anuncia la capacidad ni empieza el corte, así que ninguna familia corta. Se enciende cuando estén B5, **B6** y B7. Seguir un corte ya hecho no depende de él (ver 4).
2. **Capacidad: un campo de la credencial del Worker**, no una ficha firmada.
   - `POST S/capability {commonFormat: 2}`, solo de móviles; monótono e idempotente; sube la versión si cambia. Se ve en `devices[].commonFormat`.
   - Por qué no la ficha: cambiar la ficha gasta declaraciones del cupo de la generación (`knownRecords`) y cambia el contexto de la época de todos. La capacidad no es confianza: un servidor que mienta solo puede retrasar el corte o romper la disponibilidad (activar con un cliente antiguo dentro, que deja de poder leer), nunca leer ni inyectar nada. Encaja en el límite ya escrito de B2.
   - Un móvil activa solo si **todos los miembros activos** de su vista (él incluido, las webs también) tienen una credencial activa que ha anunciado el 2 **y además toda credencial no revocada del servidor** lo ha anunciado, también las que no están en su vista: huérfanas, pendientes o sin respaldo (`membersAnnouncedCommonV2`; revisión de seguridad, M1). El Worker exige lo mismo al subir el mínimo, porque la comprobación de la app solo la cumple el cliente honrado. Una web no puede anunciar hasta B5, así que una familia con web no corta antes.
   - No depende de `meta/protocol` del documento.
3. **Activación recuperable e irreversible** (una vuelta de `sync()` del que activa):
   1. Persiste `V2SyncState.commonMigration` antes de nada.
   2. Importa la `familyKey` como candidata **propia e histórica** (`legacyFamilyCandidate`: creador este móvil, la época y la audiencia de su vista solo como descripción, secreto la propia clave) con la referencia `legacy`, que el recorte y `pruneRevoked` respetan. Abre, nunca sella.
   3. Abre por última vez el común en formato 1 (`receive(legacyKey:)`, estado `legacy`), crea una candidata aleatoria, la guarda con su reparto antes de sellar (B3) y sube el común acumulado en formato 2 con `minCommonFormat: 2`.
   4. Con el `PUT` dentro, la marca irreversible: `SyncV2Local.raiseCommonFormatFloor(2)` (`family.commonFormatFloor` en el almacén seguro, fuera del documento, de `V2SyncState` y de las copias; una marca que no se entiende cuenta como 2) y después el interruptor y fin de la migración pendiente (`CommonV2Bootstrap.finish`).
   - Justo antes del `PUT` se guarda `commonMigrationPut` (revisión de seguridad, B2; decisión del líder: la marca **no** va antes del `PUT`, porque un `409` dejaría marcado al que activa y a la familia sin cortar). Desde ahí este móvil no vuelve a abrir nunca un formato 1: ni el paso 2 del motor ni `receive`. Si el corte no entró, reintenta sellando lo que tiene; lo que otros escribieron en formato 1 vive en sus copias locales y entra cuando siguen el corte.
   - **Recuperación:** un cierre antes del `PUT` deja el servidor en formato 1 y mínimo 1: al volver se reanuda con la misma candidata guardada. Si al reanudar ya no anuncian todos (y el `PUT` no se había intentado), se quita la migración pendiente sin publicar nada. Si el `PUT` entró y se apuntó (`lastKid`), la marca va al empezar la vuelta siguiente, antes de abrir nada, aunque el servidor diga otro mínimo. Si entró sin apuntarse (respuesta perdida), el mínimo 2 del servidor hace que la vuelta siguiente lo **siga** (4). Nunca hay un común publicado sin su clave guardada.
   - **Dos a la vez:** uno gana; el otro recibe `412`, vuelve a leer, ve el mínimo 2 y sigue el corte con el paquete v4 que el ganador le repartió.
4. **Seguir el corte.** Un móvil **sin la marca** (se decide por la marca, no por el interruptor: revisión de seguridad, M2) que ve `minCommonFormat >= 2` en el servidor importa la clave histórica y abre el común con su paquete v4, sin abrir nunca un formato 1. El mínimo no va firmado (revisión de seguridad, B1), así que:
   - con el mínimo 2 y un común que no es formato 2, `SyncFailure.protocol` y nada más (el Worker no lo permitiría: es un servidor que miente);
   - la marca solo se pone cuando `receive` ha comprobado en el común la firma de un miembro activo (`opened`, `missingKey` o `unreadable`, que solo salen tras verificar la firma); si no, `SyncFailure.protocol` sin marcar ni sustituir nada.
   - Es como vuelve el desconectado y cómo termina el que activó y se cerró. Un seguidor sin su paquete v4 espera (`missingKey`) y no sustituye. Un mínimo posterior al que conoce la app, o una marca local posterior, da `EnvelopeFormatException` («hay que actualizar»). Un seguidor que crea su lista nueva en formato 2 y se cierra antes de la marca también la pone así; en ese caso importa la clave histórica, que no abre nada.
5. **Worker.**
   - Byte de formato del común en creación, `PUT S` y `PUT S/common`: `RG` + 3 o más es `400 common_format_unknown` siempre (cierra el pendiente de B3: una credencial ya no puede subir `RG\x03` y bloquear a todos).
   - Mínimo persistido por generación (`Meta.minCommonFormat`): solo sube, en la misma transacción que el primer común de ese formato, desde un móvil y solo si **todas** las credenciales no revocadas, de cualquier rol, lo han anunciado (`409 common_format_unannounced`; revisión de seguridad, M1). Con el 2, menor es `409 common_format_too_old` y lo que no es `RG`, `400`. Con el 1 lo demás se acepta como antes: el móvil que ya cortó lo trata como falso y el que no, no lo abre.
   - Lo guardado admite cualquier entero seguro desde 1 (revisión de seguridad, B4): un mínimo mayor que el que conoce el Worker (una vuelta atrás del código) rechaza las escrituras del común con `409 common_format_unsupported` sin retirar la lista; la cota superior solo vale para lo que llega por la API.
   - Una creación puede nacer con `minCommonFormat: 2` (renovación).
   - En la app, `V2CommonFormatException`; el controlador lo muestra como `SyncIssue.unreadable` hasta que la interfaz tenga su aviso.
6. **Cliente antiguo.** No puede subir el formato 1 (`409`) ni por `PUT S` ni por `PUT S/common`, y lo que lee es un sobre `RG\x02` que su versión no abre (`versión 2 no soportada`): nunca se le sirve nada cifrado también con la clave vieja.
7. **Puente de formato 1 cerrado.** `receive` solo abre el formato 1 con `legacyKey`, que el motor pasa únicamente en la vuelta que activa, y además con `lastKid` nulo. En cualquier otro caso, también con el interruptor encendido sin activación, es `forged`. Con la marca, el motor nunca vuelve al camino del formato 1 (la marca cura un `V2SyncState` perdido).
8. **Absorción legacy/v1 cerrada.** Con la marca, `retireV1(closed: true)` borra la copia v1 del servidor sin leerla ni fusionarla. Quien escribió en v1 y no ha migrado conserva su copia local y la fusiona al emparejarse. El `.regalos` de siempre (sin firma, solo con la `familyKey`) tampoco entra ni se exporta tras la marca (`ShareService`, `EnvelopeFormatException`): **la pantalla de copia falla tras el corte hasta B6**, que lo sustituye.
   - **Emparejar falla tras el corte hasta B7:** el anfitrión con la marca no puede sellar la `familyKey` en v3 (`sealFamilyKey(commonFormatV2: true)` lanza `KeyBundleException`) y se para antes de aprobar: no queda ninguna credencial nueva.
9. **Arranque seguro compartido con el lote 4** (sí se pudo separar): con el interruptor (`CommonV2Bootstrap.prepareFresh`) o con la marca, `ensureCreated` crea la generación directamente en formato 2 con `minCommonFormat: 2`, la candidata guardada antes de sellar y la marca al terminar (`CommonV2Bootstrap.finish`). Una generación nueva no importa la `familyKey`: no tiene nada en formato 1. La marca es por familia (no por `syncId`): tras `startNewGenerationV2` la generación nueva nace ya en formato 2.
10. **Pruebas:**
    - `app/test/sync/common_v2_cutover_test.dart` (30 casos, 10 tras la revisión de seguridad: sondas P1, P2 (dos), P8 y P9, B1 con un formato 2 sin firma de un miembro, web dentro que bloquea en el móvil y en el Worker, `PUT` siempre sin respuesta, `PUT` que no llega mientras otro escribe en formato 1, seguidor sin paquete v4; las de «en el guardado N» comprueban dónde caen): interruptor apagado; corte coordinado de tres; un miembro que no anuncia bloquea; corte interrumpido en cada paso (migración pendiente, cada uno de los 5 guardados de la clave común, la marca, respuesta del `PUT` perdida, sin red antes del `PUT`, reanudar cuando ya no anuncian todos); cliente antiguo que intenta escribir; puente v1 cerrado también con un servidor que baja el mínimo; copia antigua y estado perdido que no rebajan; mínimo posterior; dos que activan a la vez; desconectado que vuelve; arranque de una generación nueva.
    - `common_v2_engine_test.dart`: M2/P4 y M4/P7 ahora con el Worker que rechaza y un servidor que manipula (`setCommonForTesting`); la primera vuelta de B3 pasa a «puente cerrado».
    - `migration_v2_test.dart` (absorción cerrada), `sharing/sharing_test.dart` (`.regalos` antiguo tras la marca), `pairing_v2_flow_test.dart` (emparejar tras el corte falla antes de aprobar).
    - `server/test/v2.test.ts`, «B4: common format cut-over» (7 casos): capacidad, byte de formato, subida del mínimo con todas las credenciales anunciadas, una web viva que bloquea, cliente antiguo, generación que nace en formato 2, y mínimo guardado posterior o dañado.

**Queda:**

- **Activación:** encender `kCommonV2Ready` cuando estén B5, B6 y B7, y probar el corte en los móviles de prueba con la web dentro.
- **B5 (web)** (hecho: ver «B5 hecho»): abrir y firmar el común en formato 2, anunciar la capacidad (abrir `POST S/capability` a las webs en `webAllowed`, del Worker y del falso) y seguir el corte con la marca de la caja.
- **B6:** el `.regalos` nuevo con paquetes v4; el de siempre ya está cerrado tras la marca. Los de **recuperación** (fase 3, lote 5) tienen que llevar la marca y el llavero (con la histórica) y no rebajar nunca el formato al restaurar.
- **B7:** hoy, tras el corte, el anfitrión se para antes de aprobar (ver 8). B7 tiene que entregar el paquete v4 y el **formato mínimo dentro de la aprobación firmada por el anfitrión**, y el invitado nace con la marca puesta, sin abrir nunca un formato 1 (no debe fiarse del mínimo sin firma del servidor para eso).
- **Interfaz (lote 6):** un aviso propio de «actualización necesaria» (hoy `SyncIssue.unreadable`) y, si se quiere, cuántos miembros faltan por anunciar (`CommonCutover.waiting`).
- **Lote 4:** al renovar, el `CommonKeyState` de la generación anterior sigue en el mismo fichero (un `lastKid` de otro `syncId` no hace daño, pero la renovación debería guardar el estado por generación, como pide su diseño).

## B7 hecho

Checkpoint al emparejar (sección 6). Código en `app/lib/core/sync/pairing_v2.dart` (transcript, hashes y JSON canónico, Dart puro), `app/lib/features/sync/application/pairing_v2_flow.dart` (aprobación v4, anfitrión e invitado), `pairing_v2_controller.dart` (instalación), `migration_v2.dart` y `generation_v2.dart` (pendiente con formato), `sync_v2_engine.dart` (`V2SyncOutcome.published`), `sync_transport_v2.dart` y el Worker (`server/src/list-v2-object.ts`, `v2-contract.ts`, `limits.ts`; contrato en `server/README.md`, «Pairing checkpoint»).

1. **Aprobación v4** (`kPairingPackageVersion = 4`), firmada por el anfitrión con dominio `gift-huddle-pairing-approval-v4` ‖ 0 ‖ JSON canónico de todo salvo `sig`. Claves exactas: `v`, `listId`, `syncId`, `inviteId`, `transcriptHash`, `hostRecord`, `guestRecord`, `minVersion`, `commonCheckpointHash`, `registryCheckpointHash`, `minCommonFormat` (1 o 2), `familyKeyPackages` (1 a 4) y `slotFloors`.
   - `transcriptHash` = SHA-256(`gift-huddle-pairing-transcript-v1` ‖ 0 ‖ JSON canónico {i, l, h, c, g, gn, n}): invitación, lista, ficha del anfitrión, compromiso, ficha y nonce del invitado, y nonce revelado.
   - Los hashes del checkpoint = SHA-256(`gift-huddle-pairing-checkpoint-<parte>-v1` ‖ 0 ‖ texto exacto) en base64url: el texto base64url del común y el registro en JSON canónico (claves ordenadas, `jsonEncode`; el Worker hace `JSON.stringify` sobre las claves ordenadas). Vector compartido en `pairing_v2_checkpoint_test.dart` y `server/test/v2.test.ts`.
   - La 3 ya no se acepta (`PairingV2VersionMismatchException`): los dos móviles tienen que estar en esta versión.
2. **Worker.** `POST I/approve` acepta `checkpoint: {common, registry}`. Bajo el mismo cerrojo y el mismo `If-Match`, copia el común y el registro actuales en filas `checkpoint` de esa invitación (en trozos, como el común) y contrasta los dos hashes (`409 checkpoint_mismatch`, sin registrar nada). `GET J/checkpoint` los sirve solo a la credencial del invitado, iguales hasta que la invitación caduca o se cancela. Se borran con la invitación (`DELETE I`, revocación del dueño, alarma de caducidad, retirada). Como mucho 8 vivos por lista, tantos como altas en 24 h (`429 too_many_checkpoints`), y el invitado libera el suyo al instalar (`DELETE J/checkpoint` con su credencial). `GET I` dice `canApprove` (cupo diario, checkpoints y generación) y el anfitrión lo mira antes de publicar la ficha del invitado. Sin `checkpoint` (un anfitrión antiguo) no se copia nada, como antes. El JSON canónico del Worker se escribe por pares ordenados (`canonicalJson`), no por objeto, para que las claves con forma de entero salgan en el mismo orden que en Dart; los números fuera de los enteros seguros no coincidirían (el registro no los tiene) y la aprobación fallaría, sin más.
3. **Anfitrión.** Aprueba exactamente lo que hay en el servidor en `out.version` (`V2SyncOutcome.published`: lo leído si no subió nada, o lo subido), bajo la cola de la familia. Antes de firmar lo autentica: abre el común con sus claves (`openFamilyEnvelope` con su llavero, o `open` con la `familyKey` sin el corte). Si no puede, o falta el reparto, `PairingException` antes de aprobar: no queda ninguna credencial.
   - Con un común en formato 2 entrega los paquetes v4 de esa candidata al invitado (los que ya están en el servidor; la sincronización de `confirm` crea la candidata nueva con el invitado en la audiencia y su reparto) y `minCommonFormat: 2`. Ya no sella la `familyKey` en v3.
   - Sin el corte, la `familyKey` en v3 como hasta ahora, con `minCommonFormat: 1`.
   - Con la marca y un común que no es formato 2: rechaza (servidor que miente).
4. **Invitado** (`finish`):
   1. Comprueba la forma exacta y la firma con la clave del anfitrión de la oferta (la que autenticó el código en persona), y después lista, generación, invitación, transcript y fichas.
   2. Descarga el checkpoint y exige los dos hashes exactos. Si el servidor no lo da, devuelve null: queda pendiente, nunca se instala otra base.
   3. Verifica el registro del checkpoint con su ancla y lo fusiona.
   4. Abre su paquete: v4 con `FamilyKeyBundle.open` (emisor, audiencia, creador enlazado y `kid` del común), o v3.
   5. Autentica y abre el común del checkpoint: es la base.
   6. No lee nada más del servidor (revisión de seguridad, M1): la instantánea de partida (`PairingV2Joined.snapshot`, la que guarda la web en su caja) es el checkpoint verificado con la versión del suelo firmado, sin paquetes ni dispositivos; sus slots salen de los suelos firmados (`slotFloors`), que la web usa como testigo de quién está protegido. Un slot que el servidor ponga después de aprobar ya no cuenta como testigo (no estaba verificado): `web_protection_recovery_test.dart` publica la protección antes de aprobar. La primera vuelta lee lo actual, lo verifica, rechaza una versión anterior a ese suelo y lo fusiona: un común posterior legítimo no obliga a empezar otra vez, y uno viejo con versión nueva no borra la base.
   - Los paquetes que no abren se saltan; hace falta al menos uno válido (B4). El anfitrión pone primero el suyo.
5. **Instalación** (`_install`), en este orden:
   1. `PendingV2` con `commonFormat`.
   2. Registro.
   3. Con el formato 2, el llavero común con la candidata, referenciada como la del común y como `lastKid`, y su marca.
   4. `V2SyncState` (versión, suelos de slots y `commonFormatV2`).
   5. El documento.
   6. La marca irreversible `raiseCommonFormatFloor(2)`.
   7. La identidad.
   - El «compromiso» que queda guardado es el suelo de versión, los suelos de slots, el formato mínimo y `lastKid`; los hashes no se guardan porque la base ya está en el documento.
   - Un cierre después del documento lo termina `finishPendingV2`, que pone la marca antes de la identidad si el pendiente dice 2.
   - Tras el corte el invitado nace con la marca, sin fiarse del mínimo del servidor, y nunca abre un formato 1.
6. **Web.** La web comparte `PairingV2Guest.finish` (`forWeb`): en el formato 1 su caja nace del checkpoint verificado (M1; antes de la revisión guardaba la instantánea actual sin verificar) y libera el checkpoint al terminar `enroll`. Es compatible con `webCommonInstall` de B5, que solo sustituye el común de esa instantánea. Con el formato 2, `enroll` pasa por `webCommonInstall` (B5), que guarda en la caja el llavero común (`PairingV2Joined.commonKeys`), la marca (`commonFormat`) y la base sellada en local; `kWebPairingCommonV2` está encendido desde la integración. Apagado, el anfitrión no crearía la invitación web (`PairingV2Host.start`) ni, si el corte llega en medio, publicaría nada al confirmar (B1). Con el formato 2, `PairingV2Joined.familyKey` es una clave local aleatoria que no abre nada.
7. **Pruebas:**
   - `app/test/sync/pairing_v2_checkpoint_test.dart` (19 casos; los seis primeros en los dos formatos): base exacta y atada a la invitación; común viejo con versión nueva; checkpoint sustituido (común y registro); el servidor retiene el checkpoint; común actual posterior legítimo; invitaciones mezcladas (aprobación y checkpoint de otra); HLC máximo intacto con campos omitidos (como checkpoint y como común actual); tras el corte nace con la marca y no fusiona un formato 1 servido con el mínimo 1; sin corte sigue la v3; el anfitrión no aprueba lo que no abre; la web tras el corte no se aprueba; `PendingV2`; vector del hash.
   - `pairing_v2_flow_test.dart`: la prueba de B4 («falla antes de aprobar») pasa a «tras el corte entrega el paquete v4 y no la v3», y las manipulaciones de la ronda 11 van sobre los campos nuevos.
   - `pairing_v2_app_test.dart`: tras el corte el invitado nace con la marca y el llavero y sincroniza; un reinicio durante la instalación termina con la marca antes de la identidad; «ronda 4» con las versiones 3 y 5.
   - `server/test/v2.test.ts`, «B7: pairing checkpoint» (8 casos, con el tope de 8, `canApprove`, la liberación y el vector con claves enteras).
   - Tras la revisión de seguridad, las sondas P1-P5 como pruebas: P1 en `pairing_v2_app_test.dart` (fallo tras la aprobación y corte antes del documento: credencial nueva y se vuelve a emparejar), P2-P5, B3 y B4 en `pairing_v2_checkpoint_test.dart` (24 casos).

**Queda:**

- **B5 (web):** hecho al integrar: `enroll` usa `webCommonInstall` y `kWebPairingCommonV2` está encendido.
- **Credencial colgada (M3).** Si el invitado falla del todo después de la aprobación (antes de instalar), o si se corta antes del documento y el pendiente (`PendingV2.pairing`) se descarta, cambia solo su credencial de servicio (`DeviceKeys.withNewServiceCredential`; es aleatoria e independiente de la ficha), deshace lo que escribió (llavero común y su marca, estado v2 y registro: B2) y puede volver a emparejar. El intento de emparejar siguiente termina o deshace antes el pendiente. En la familia queda un dispositivo que no se usará: `PairingV2GuestState.leftoverDevice` lo dice para que la interfaz (lote 6) pida quitarlo desde el anfitrión. No se ha hecho la instalación reanudable (habría que guardar cifrados documento, registro y llavero del checkpoint en el pendiente); queda como mejora.
- **Credencial nueva en cada emparejamiento:** un móvil que no está en ninguna lista v2 (ni `replacing` ni ya en v2) estrena credencial de servicio al abrir cada invitación. Así cancelar, `reset()` o cerrar la app entre la aprobación y la instalación tampoco dejan `credential_exists`.
- **Interfaz (lote 6):** `PairingV2GuestState.leftoverDevice` se tiene que mostrar: queda un dispositivo fantasma que el anfitrión tiene que quitar en Ajustes › Móviles de la familia. Mientras siga, su credencial viva y sin anunciar **bloquea el corte de B4** (`membersAnnouncedCommonV2` y el `409 common_format_unannounced` del Worker), así que la interfaz tiene que decirlo y llevar a quitarlo.
- **Despliegue (B5 de la revisión de seguridad):** primero el Worker (acepta `checkpoint` y aprobaciones sin él), y después los móviles y la web a la vez: la aprobación v3 ya no se acepta, así que un móvil nuevo y uno viejo no se emparejan. Coste: `approve` con checkpoint hace dos SHA-256 sobre el común (hasta 2 MiB) y el registro, y escribe una copia; unos milisegundos de CPU por emparejamiento, dentro del plan.
- **Disponibilidad:** ante `checkpoint_mismatch` (p. ej. un común en base64url no canónico que subió otro escritor) el anfitrión reescribe una vez el común y su propio registro verificado (`registry.toJson()`, nunca el del servidor tal cual) con un `PUT` y vuelve a aprobar (B3); si vuelve a fallar, el emparejamiento falla.
- **Revisión de seguridad**: hecha (FIX y después PASS).

## B5 hecho

La web con la clave común por época. Código en `app/lib/features/web_device/application/web_common.dart` (estado en la caja y con qué candidata puede sellar) y `web_sync_engine.dart` (`_readFormat2` y la publicación); el Worker y el falso abren `POST S/capability` a la web.

1. **Llavero común en la caja.** Todo va en `vault.opened.data`, en la **misma escritura atómica** (`saveData`) que el registro (`registryLocal`), las raíces y la instantánea:
   - `commonKeys`: un `CommonKeyState` como el de los móviles (llavero, revisión y `lastKid`), sin `outbox` ni bloqueo, porque la web no reparte ni sustituye. Cada candidata lleva su contexto de época, su audiencia y su procedencia.
   - `snapshot`: la última instantánea **cuyo común se ha abierto**, con `writerKey`, la clave Ed25519 con la que se verificó. Su `kid` es `lastKid` y lleva la referencia `common`, así que el recorte y `pruneRevoked` no la tocan. `savedCommon()` la reabre sin red (también la usa `WebFamilyStore.cascadeDoc`).
   - `seenVersion`: la versión más alta vista con un común cuya firma de un miembro se ha verificado (`opened`, `missingKey`, `unreadable`), aunque no se abriera. Con la de la instantánea es el suelo contra la vuelta atrás. La versión no va firmada: esto solo impide que el número baje, no demuestra frescura (revisión de seguridad, B2).
   - `commonFormatFloor`: la marca irreversible. Una que no se entiende cuenta como 2; con ella y sin `commonKeys` hay `CommonStateException`, nunca un llavero vacío.
2. **Abrir por `kid`.** Solo con el registro verificado desde una raíz y la web confirmada:
   - Abre los paquetes v4 dirigidos a ella con `FamilyKeyBundle.open` (la vista de su raíz) y los guarda con `withReceivedCandidate`, con `wanted` = el `kid` del común remoto y `lastKid`, y después `pruneRevoked` y `trimCommonKeyring` con ese `wanted`. Los v3 (sorpresas) no se abren nunca.
   - Verifica el común con `commonWriterResolver(view, registry)` y lo abre con el llavero por su `kid`. Nunca sustituye por «la última recibida».
   - Lo que no se abre (`missingKey`, `unknownWriter`, `unreadable`, `forged`, `revokedWriter`) no se fusiona ni se sustituye: la instantánea guardada sigue, la web se queda con lo último que abrió (`commonStatus`) y retiene la cola.
3. **Firma y cola separada.** La web sella con `sealFamilyEnvelope` y su `DeviceKeys` como escritor (`view.member(web)`), con la revisión guardada antes de sellar. La única escritura sigue siendo `PUT S/common`. La cola de la web es la de siempre: el filtro de publicación (`webEntryAllowed`) se vuelve a aplicar sobre el común abierto en cada `GET`, tras la rotación y tras cada `412`. Sin clave, sin confirmación o sin reparto, `sync()` vuelve sin publicar y los cambios siguen cifrados en la cola (`commonHeld`). Tras el `PUT`, una entrada solo se confirma si el común que la web abre en la lectura de confirmación ya la contiene (`saved.merge(delta)` no lo cambia); si esa lectura no abre el común, no se confirma ninguna (revisión de seguridad, M1).
4. **Nunca crea, nunca sella sin reparto** (`webSealingCandidate`, B6 de la revisión de seguridad). La web solo vuelve a sellar con la candidata del común remoto que acaba de abrir. Además, esa candidata:
   - está en su llavero y no es histórica ni comprometida;
   - sella desde la vista de su raíz (contexto actual y audiencia exacta, la web incluida);
   - y su reparto está hecho: cada miembro de la audiencia que no es la web, ni el creador, ni el escritor del común remoto tiene un paquete que se lo entrega (`webDeliveredPackage`, propio de la web; el `usefulFamilyPackage` de B3 no cambia). El emisor tiene que ser un miembro activo móvil con su ficha actual o una anterior con la misma clave de firma; la cabecera, idéntica a la candidata (`l`, `sid`, `e`, `ctx`, `kid`, `c`, `cr`, `cs` y audiencia); y la firma del emisor, válida (revisión de seguridad, B1).
   - Así la web no puede publicar con una candidata que algún miembro no tiene; si falta alguno, espera a que un móvil reparta o rote. No recibe sorpresas ni emite paquetes (el Worker ya se lo prohíbe).
5. **Corte de formato.**
   - Con `commonV2Ready` (por defecto `kCommonV2Ready`, apagado) la web anuncia la capacidad con `POST S/capability` una vez y vuelve a leer. Es de mejor esfuerzo: si falla (salvo `unauthorized`), sigue con la lectura y lo intenta en la vuelta siguiente (revisión de seguridad, B3). El Worker (`webAllowed` y `capability`) y `fake_worker_v2.dart` lo aceptan de las webs. Subir el mínimo sigue siendo solo de un móvil (`PUT S`).
   - La web sigue el corte por la marca, no por el interruptor: con `minCommonFormat >= 2` o la marca, un común que no es formato 2 es `SyncFailure.protocol`. La marca solo se pone cuando la firma de un miembro activo del común en formato 2 se ha verificado (abra o falte la clave); si no, `protocol` sin marcar ni guardar nada.
   - Tras la marca nunca abre un formato 1 de la red, ni con un servidor que baje el mínimo. La instantánea guardada solo puede ser formato 1 si se guardó antes de la marca, y esa se reabre de la caja, no de la red.
   - Un mínimo, una marca o un sobre posteriores dan `EnvelopeFormatException` («hay que actualizar»).
   - La web no importa la `familyKey` como candidata histórica: tras la marca no abre formatos 1 ni guarda retenidos. La `familyKey` sigue en la caja sin uso para el común.
6. **PIN, guarda y secreto de la caja no cambian** al rotar: solo cambia `data`. `changePin` copia `data` dentro de la misma cola de la caja, así que un cambio de PIN a la vez que una rotación conserva el llavero (prueba).
7. **Vectores Dart ↔ WebCrypto** (B4 de la revisión de B1):
   - `server/test/webcrypto-vectors.test.ts` reproduce con WebCrypto, sin el Dart, los vectores de [`0005-vector-clave-comun.json`](0005-vector-clave-comun.json) en workerd (V8 + BoringSSL, como Chrome): claves desde las semillas, contexto, `kid`, firma del creador (Ed25519 da la misma firma), el paquete v4 abierto como Leo y sellado de nuevo byte a byte, y el sobre común verificado, abierto (HKDF, AES-GCM, deflate en bruto) y vuelto a cifrar igual.
   - **X25519 de orden bajo**, confirmado: [`0005-vector-x25519.json`](0005-vector-x25519.json), escrito por `app/test/sync/x25519_vector_test.dart`, trae lo que da el Dart para los 12 puntos. WebCrypto rechaza exactamente las siete primeras (secreto de ceros) y da el mismo secreto no nulo en las cinco con el bit alto (el RFC 7748 lo enmascara, y el paquete cae por el GCM).
   - Además, `app/test/web_device/vectors_browser_test.dart` abre los mismos vectores con el Dart compilado a JavaScript y vuelve a sellar el sobre byte a byte con el nonce del vector (`flutter test --platform chrome`; los datos van copiados en `vectors_data.dart`, que `x25519_vector_test.dart` compara con los JSON). En esta máquina el arnés de Chrome no llega a cargar la prueba («Connection closed before test suite loaded»): **hay que pasarla en Chrome en las pruebas manuales** de la web.
8. **Pruebas:**
   - `app/test/web_device/web_common_v2_test.dart` (19 casos; los de la revisión de seguridad: M1 con basura, con `missingKey` y con un común que no lleva el cambio; `412` que vuelve a filtrar y `412` que publica sobre el otro; web sin confirmar; raíz revocada por otro móvil; `seenVersion`; anuncio que falla):
     - corte coordinado con la web dentro (anuncia, sigue con su marca, abre por `kid`, firma, el móvil lo fusiona, caja y PIN iguales);
     - nunca un formato 1 tras la marca, ni con el mínimo bajado;
     - mínimo 2 con un formato 1 o con basura `RG 0x02`: protocolo y sin marca;
     - formato posterior;
     - rotación sin su paquete: espera, cola retenida, nada publicado; con el paquete, publica;
     - dos candidatas en distinto orden;
     - común firmado con otra clave bajo el nombre de un miembro;
     - cambio de PIN concurrente con una rotación;
     - estado perdido con la marca;
     - y sin el interruptor no anuncia y la familia no corta.
   - `app/test/web_device/web_common_test.dart` (10 casos; 2 de `webCommonInstall` y 2 de la B1 de la revisión de seguridad: paquete de un no miembro con el `kid` cambiado y paquete de un miembro con otra cabecera): `webSealingCandidate` (reparto hecho o no, paquete manipulado u otra ficha, sin común, histórica, comprometida, audiencia que ya no sella, revocado) y la marca de la caja.
   - `server/test/v2.test.ts`: la capacidad también desde una web y una familia con web que corta.

**Queda:**

- **B7:** al emparejar una web tras el corte, el invitado nace con `commonFormatFloor: 2`, `commonKeys` (la candidata del paquete v4 del checkpoint, con `lastKid` y la referencia `common`) y una instantánea que reabre sin red, sin abrir nunca un formato 1. La pieza está en B5: `webCommonInstall` (`web_common.dart`) recibe `PairingV2Joined.commonFormat`, `commonKeys` y `common` (la base aprobada) y devuelve los datos de la caja; la base va sellada solo en local con la candidata del checkpoint y firmada por la web (`writerKey`), y la primera vuelta la sustituye por el común remoto si lo abre. `commonKeys` solo puede traer candidatas salidas de `FamilyKeyBundle.open`, `commonFormat` sale de la aprobación firmada y al final se reabre lo sellado con `openSavedCommon` (con el `listId` de la caja y su `syncId`); si no abre, `CommonStateException`. Conectada en `WebPairingGuest.enroll` al integrar B7, con `kWebPairingCommonV2` encendido (pruebas en `web_pairing_test.dart`, «B7+B5»).
- **Interfaz (lote 6):** `commonHeld` y `commonStatus` para el aviso de la web (cambios que esperan a un móvil); hoy la barra de estado solo deja de decir «subiendo». `commonKeyringFull` igual.
- La web no guarda comunes retenidos: lo que no abre lo verá cuando un móvil lo vuelva a sellar con una candidata que ella tiene. No hay salida automática por basura demostrable en la web (eso lo hacen los móviles, que son los que sustituyen).

## B6 hecho

Ficheros `.regalos` de intercambio tras el corte (sección 5, «En los `.regalos` de intercambio»). Código: `app/lib/core/sync/exchange_file.dart` (contenedor, Dart puro), `app/lib/features/sync/application/exchange_v2.dart` (guardar y abrir sobre `SyncV2Local`), `common_v2.dart` (`CommonV2Cycle.sealForFile`, `receiveFile` e `inspectFileCommon`, aditivos), `device_registry.dart` (`RegistryView.explicitlyRevoked`, aditivo) y `share_service.dart`. El motor (`sync_v2_engine.dart`) no se toca. Incluye los arreglos de la revisión de seguridad (A1-A3, M1, B1-B3 y B5).

1. **Contenedor nuevo.** `"RX" | 0x01 | uint32 BE | cabecera JSON | común`. La cabecera lleva exactamente `{kp, l, rec, sid, v}`: paquetes v4 (como mucho 64), lista, **solo las fichas que necesitan el común y los paquetes** (escritor, creador y audiencia; como mucho 64, las fichas que admite un registro; más es `EnvelopeTooLargeException`, «demasiado grande»), generación y versión. El común es el sobre firmado `RG 0x02` de B1. Topes: todo ≤ 2 MiB (lo que acepta `parseShared` como texto), la cabecera ≤ 512 KiB. Una versión posterior del contenedor es `EnvelopeFormatException` («hay que actualizar»).
   - **El contenedor no va firmado** (tampoco hace falta con el punto 3): cada parte se autentica sola y, sobre todo, nada del fichero cambia en quién confía el receptor.
   - Ninguna clave va en claro ni con la `familyKey`. Es otro prefijo que el de siempre (`RG 0x01`) y que el común: una app anterior lo rechaza como «no es un sobre».
2. **Guardar** (`ExchangeV2.export`, solo con la marca del formato 2): sella el documento de ahora con la candidata sellable de `kid` menor (`forSealingIn`) y, si no hay ninguna (p. ej. una revocación local aún sin publicar), crea una con `FamilyCandidate.generate`, guardada con la revisión **antes** de sellar (la regla de B3). Los paquetes son `FamilyKeyBundle.sealForAudience`: el resto de su audiencia que sigue activa con su ficha. Solo un móvil activo y aprobado: un pendiente o un revocado reciben `ExchangeNotAllowedException`. El sellado va fuera del hilo de la interfaz.
3. **Abrir** (`ExchangeV2.receive`, en la cola de la familia). **El registro del fichero no se guarda nunca** (revisión de seguridad, A1-A3: antes se fusionaba antes de autenticar el común, y un revocado podía meter revocaciones firmadas por él, «revocar gana», contra Leo o contra el propio receptor; un revocado de la generación anterior entraba en la nueva; y un desconocido llenaba el registro con fichas basura). Decide la **vista local de antes**:
   1. Lista (`EnvelopeWrongListException`) y generación (`ExchangeGenerationException`), antes de tocar nada.
   2. **Una sola verificación de la firma del común** contra la vista local (`inspectFileCommon`):
      - escritor revocado de verdad: `revokedWriter` si la firma vale con su clave enlazada; si no, falso;
      - escritor activo: su ficha actual, una anterior del registro local o una del fichero, siempre que sea del mismo id, del mismo tipo y con **la misma clave de firma que la enlazada**;
      - escritor que no es activo aquí: `unknownWriter`, autenticado solo si este móvil ya lo conoce (`knownWriterKey`).
      Las revocaciones y los miembros nuevos llegan solo por el servidor o al emparejar.
   3. Solo con un escritor activo y su firma válida: los paquetes del fichero para este móvil **y de esa candidata** (`filePackagesFor`, B5), con `FamilyKeyBundle.open`. Las fichas del fichero se añaden en memoria al registro que usa `open` (audiencia, creador) solo si son de un id ya enlazado con la misma clave y del mismo tipo que ese id tiene aquí (`linkedFileRecords`); como `open` decide con la vista local, una ficha añadida no da derechos.
   4. El común.
   - Todo lo criptográfico (fichas, firma, X25519, AES) va en `runTask`, fuera del hilo de la interfaz; el cierre que viaja al otro aislado no lleva `local`. `ExchangeV2(run:)` permite comprobarlo.
   - **Abierto:** se devuelve el documento y lo fusiona quien llama (`ShareService` con `FamilyController.mergeRemote`). Solo entonces se guarda la candidata que trajo el fichero. Un documento de otro protocolo no entra.
   - **Revocado de verdad:** `ExchangeRevokedWriterException`. Firma que no vale, basura demostrable u otro formato: `EnvelopeAuthException` o `EnvelopeFormatException`. Nada de esto se guarda.
   - **Falta la clave** o el escritor tiene firma comprobada pero no es activo aquí: se guarda el **fichero entero** (con sus paquetes, B1) como retenido de fichero (`RetainedCommon.fromFile`, `'f': true`; el resumen es el del común) y `ExchangeMissingKeyException(kept: true)`. Cada vuelta de `receive` del motor vuelve a abrir sus paquetes (con el registro ya verificado de esa vuelta) y el común y, si abre, lo fusiona y lo quita. Si ya estaba guardado sin paquete para este móvil y llega el mismo común con uno, se sustituyen los bytes. Si no se ha podido guardar (cupo) o no se puede autenticar al escritor, `kept: false`: «sincroniza y vuelve a abrirlo» (B2).
   - No toca el bloqueo (`CommonBlock`) ni `lastKid`: el común del servidor sigue siendo el que cuenta.
4. **Cupo propio de los retenidos de fichero** (`kMaxRetainedFiles = 4`, `capRetained`): un fichero nunca desaloja a un común del servidor; al salir se borran sus bytes. En el bucle de reintento, un `ImportClockDriftException` conserva ese retenido y sigue con los demás (B3).
5. **Revocado ambiguo** (revisión de seguridad, M1): `RegistryView.explicitlyRevoked` separa los revocados con revocación firmada de los ids solo ambiguos, y `reallyRevoked` lo usa. Un revocado que después se hace ambiguo (otra ficha con su clave) sigue revocado; sin clave enlazada su firma no se puede comprobar y lo suyo cuenta como falso (no se espera ni se retiene). Afecta también al común del servidor y a `usefulFamilyPackage` (B3). El motor tiene su propia copia de la regla para los slots (`sync_v2_engine.dart`, `reallyRevoked` local, B2) y no se ha cambiado.
6. **Un fichero antiguo firmado** de un escritor que sigue activo entra si este móvil conserva esa candidata o el fichero trae su paquete de un emisor que sigue activo con su ficha.
7. **El de siempre tras el corte:** `ShareService` lo rechaza con `ExchangeLegacyFileException` (subclase de `EnvelopeFormatException`) sin tocar nada. Se conserva fuera de la app para una recuperación explícita (lote 6) o se vuelve a guardar desde un móvil actualizado. Sin la marca todo sigue como hoy, y un fichero nuevo da `ExchangeNotReadyException`.
8. **Pantalla de copia** (`backup_screen.dart`, y «Enviar» de `share_screen.dart`): sin cambios visuales. Los errores pasan por `shareSendErrorMessage` y `shareErrorMessage`, con textos en es, ca y en: fichero antiguo, móvil sin sincronizar, otra generación, autor revocado, falta la clave (guardado), sincroniza y vuelve a abrirlo (no guardado) y móvil sin aprobar.
9. **No rebaja nada:** guardar o abrir nunca baja la marca ni toca el registro ni las credenciales.
10. **Pruebas:**
    - `app/test/sync/exchange_v2_test.dart` (23 casos). Los de la sección 8 (revocado con la clave vieja, escritor legítimo que reexporta, fichero legacy, generación distinta, falta la clave) y, tras la revisión, las sondas P1-P6 de la revisión de seguridad: un revocado no mete revocaciones contra Leo ni contra el receptor (P1, P5); un revocado que se hace ambiguo sigue revocado (P2, M1); un revocado de la generación anterior no entra en la nueva (P3); un desconocido no llena el registro (P4: más de 64 fichas no se leen; 64 basura con un común bueno entran sin tocar el registro y las vueltas siguen); un común auténtico con fichas ajenas pegadas (P6). Además: todo fichero rechazado deja el registro idéntico, el fichero solo lleva tres fichas, `unknownWriter` autenticado que entra al aprobarlo, un retenido cuyo escritor se revoca después, el cupo de punta a punta con el borrado de bytes, que abrir y guardar pasan por el ejecutor de tareas, fichas de otro tipo descartadas, retenido sin paquete sustituido por uno con paquete y `explicitlyRevoked` sin los ambiguos.
    - `app/test/sharing/sharing_v2_test.dart` (4 casos): `ShareService` con y sin la marca (con `runTask` de verdad, en otro aislado), el de siempre rechazado (también como enlace), falta la clave de punta a punta y los textos de cada error.

**Queda:**

- **Lote 4 (renovación), raíz de A2 frente a un servidor malicioso:** las declaraciones del registro (fichas, avales, revocaciones) no llevan generación, así que un servidor puede servir en la generación nueva las de la anterior (un revocado de antes vuelve a tener ficha y avales). Hay que atar la generación a las declaraciones o cambiar la clave de firma del móvil al renovar. Además el motor une `snap.registry` con el registro local sin atarlo a la generación (`sync_v2_engine.dart`, paso 3 de `_once`).
- **Lote 5 (copia de recuperación):** otro formato, bajo el código de recuperación, con el llavero (la histórica incluida), los contextos y la marca. Puede reutilizar `sealForFile` y `receiveFile` para el común. Al restaurar, la marca solo sube y el registro solo se fusiona.
- **Lote 6 (interfaz):** enseñar los retenidos de fichero aparte y su recuperación explícita, y la de un `.regalos` antiguo sin firma si se quiere ofrecer.
- Un fichero que llega **antes** de que este móvil conozca una revocación se acepta: es el límite de la sección 5. El fichero no puede ocultar ni añadir revocaciones.
- Un retenido de fichero cuya candidata no incluye a este móvil no se abrirá nunca: espera en su cupo hasta que lo desalojen otros cuatro.
- La regla de slots del motor sigue con `linkedSigningKey` para «revocado de verdad» (ver 5).
- Al encender `kCommonV2Ready`, B6 ya no bloquea: guardar y abrir funcionan tras el corte.

---

Recomiendo **A: claves comunes por época, con candidatas y audiencia**, acompañada de **firma del escritor en el común**, un **checkpoint de contenido firmado al emparejar** y **prohibición del borrado de slots ajenos para la primera versión de tiendas**.

La firma es necesaria: conservar claves antiguas para recuperar cambios legítimos también permite fabricar cifrados antiguos. La rotación por sí sola no cierra la escritura por `.regalos`.

**1. Lo que confirma el código actual**

> Estado del código cuando se tomó esta decisión. Todo lo que sigue se corrigió después (ver «B1 hecho» a «B6 hecho» y el punto 7): por ejemplo, el Worker ya rechaza que una credencial cambie o borre (`data: null`) un slot de otro escritor (`slotOwnership` en `server/src/list-v2-object.ts`).

He contrastado los ADR con la implementación:

- El [motor móvil](../../app/lib/features/sync/application/sync_v2_engine.dart:454) sella con una única `local.familyKey`, abre el común antes de procesar paquetes y omite los paquetes `family`.
- [KeyBundle](../../app/lib/core/sync/key_bundle.dart:298) ya permite repartir una clave común mediante X25519 y firma, pero no administra candidatas comunes. Al sellarla, toma como audiencia los miembros actuales; eso no demuestra quién conocía previamente esa misma clave.
- El [motor web](../../app/lib/features/web_device/application/web_sync_engine.dart:517) prueba paquetes `family` ordenados por época y sustituye una única clave. No basta para concurrencia ni para recuperar sobres antiguos.
- La [aprobación de emparejamiento](../../app/lib/features/sync/application/pairing_v2_flow.dart:274) firma clave, revisiones y `minVersion`, pero ningún compromiso del común.
- El [Worker](../../server/src/list-v2-object.ts:538) comprueba la propiedad del slot únicamente cuando `data != null`. La excepción permite borrar cualquiera.
- [Compartir por fichero](../../app/lib/features/sharing/application/share_service.dart:33) sigue usando el sobre simétrico sin firma de escritor.

Hay además dos matices decisivos del ADR 0004: **la época numérica puede bajar** y dos vistas diferentes pueden producir el mismo número. No debe convertirse en un contador global de seguridad.

**2. Comparación de las opciones**

| Opción | Ventajas | Inconvenientes y riesgos | Decisión |
|---|---|---|---|
| **A · Candidatas por época y audiencia** | Tolera rotaciones concurrentes, no depende de un coordinador disponible y aprovecha los mecanismos existentes de sorpresas. | Exige llavero, retención, reparto recuperable, gestión de capacidad y distinguir lectura histórica de autorización para escribir. Copiar literalmente la implementación de sorpresas sería insuficiente. | **Recomendada.** |
| **B · Solo crea quien revoca** | Flujo sencillo cuando hay una única revocación y quien la hace completa todos los pasos. | Dos revocaciones generan claves incompatibles. Elegir una por fecha o id no demuestra que excluya a todos los revocados. El creador puede desaparecer antes de repartirla. Conservar ambas, validar audiencias y permitir reparación termina aproximándose a A. | No la elegiría para este modelo sin coordinador. |
| **C · Doble envoltura** | Puede conservar una capa exterior compatible con parte del código existente. | El secreto interior necesita exactamente la distribución, concurrencia y recuperación de A o B. Añade formatos, descifrados y riesgo de publicar accidentalmente solo la capa antigua. Derivarlo de la `familyKey` conocida no protege nada. | Sin ventaja suficiente. |

**3. Diseño concreto de A**

Adoptaría el esquema de candidatas, pero con **audiencia inmutable por candidata** y un identificador de contexto además del número de época. Esto evita trasladar al común la ambigüedad del contador y depender de haber recibido todas las ampliaciones de audiencia.

El derecho al común sería independiente de la persona y de las sorpresas:

- Puede recibirlo cualquier miembro activo y confirmado, incluidos los móviles sin persona y las webs.
- Solo un móvil activo y aprobado puede crear o repartir candidatas.
- Una web puede recibir claves y firmar comunes, conservando sus restricciones actuales.
- Un pendiente, huérfano o revocado conserva sus datos locales, pero no recibe claves nuevas automáticamente.

Un modelo orientativo:

```text
FamilyCandidate {
  format,
  listId,
  syncId,
  scope: "family",
  epochNumber,
  epochContext,
  kid,
  creator,
  creatorRecord,
  audience: [deviceId + recordDigest, ...],
  secret: 32 bytes
}
```

`secret` es aleatorio e independiente de todas las claves anteriores. `kid` sería SHA-256 completo, con dominio y contexto, para el formato nuevo; no hace falta cambiar los slots de sorpresas existentes.

`epochContext` identifica mediante hash canónico las declaraciones verificadas que sustentan la época y las identidades destinatarias. Su descriptor firmado debe acompañar a la candidata y poder contrastarse con el registro anclado. **No es una raíz nueva de confianza ni se acepta porque venga firmado por cualquier ficha.**

El número conserva utilidad descriptiva; ni `max(epoch)` ni el orden lexicográfico de contextos decide permisos.

La audiencia incluye a todos los destinatarios previstos, aunque aún no hayan recogido su paquete. Nunca se reduce. Para incluir a alguien nuevo se crea otra candidata y se vuelve a sellar el común; no se entrega una candidata existente ampliando silenciosamente su audiencia. El coste es una rotación adicional al incorporar miembros, asumible para esta familia.

La candidata válida para **sellar** debe:

1. Pertenecer al contexto actual verificado.
2. Tener toda su audiencia todavía autorizada.
3. Tener emisor, descriptor y paquetes válidos.
4. No estar marcada como histórica o comprometida.

Entre las disponibles que cumplen eso, gana el `kid` menor. Se conservan las demás para abrir lo que ya se haya publicado.

Para **abrir**, se busca exactamente por generación, contexto y `kid`. Una clave histórica puede seguir descifrando aunque ya no sirva para publicar. Un contexto previamente verificado no se invalida porque el contador actual haya bajado.

Los paquetes usarían un formato nuevo, por ejemplo `KeyBundle v4`:

```text
AAD = dominio v4 || cabecera canónica ||
      pública efímera || pública X25519 del destinatario

cabecera = {
  format, listId, syncId, scope,
  epochNumber, epochContext, kid,
  from, fromRecord, to, toRecord, audience
}

firma = Ed25519(AAD || nonce || ciphertext || tag)
```

Se mantienen X25519, HKDF-SHA256, AES-256-GCM, rechazo del secreto de ceros y comprobación de fichas. El destinatario comprueba también el `kid` derivado de la clave recibida. No se admite que el transporte convierta un paquete de otra generación o ámbito en uno válido.

El común necesita un sobre nuevo, independiente de la versión del documento:

```text
RG | formato nuevo | longitud | cabecera canónica |
nonce | ciphertext | tag | firma Ed25519

cabecera = {
  format, listId, syncId, scope: "family",
  epochNumber, epochContext, kid,
  writer, writerRecord, revision
}
```

- **AAD:** prefijo y cabecera completos.
- **Firma:** dominio propio más todos los bytes anteriores a la firma.
- **Contenido:** `FamilyDoc`, con HLC por campo, lápidas y campos desconocidos conservados.
- **Revisión:** identifica publicaciones del escritor; no sustituye los HLC ni demuestra frescura global.
- Se mantienen límites antes de verificar, descifrar y descomprimir.

La firma se comprueba contra la identidad del escritor y la confianza local actual. Una ficha histórica puede identificar sus mismas claves, pero no devolver autoridad a un revocado o a una identidad ambigua.

Un común nuevo de un escritor actualmente revocado **no se fusiona automáticamente**, aunque su AES-GCM sea correcto. Los datos aceptados y guardados antes de conocer la revocación permanecen en la copia acumulada. Los sobres dudosos se conservan aparte para recuperación explícita; no se convierten en cambios válidos por conocer una clave antigua.

Esto mantiene un límite ya presente en el ADR: no se puede distinguir criptográficamente entre una edición legítima y una del ladrón cuando ambas llevan la firma del mismo dispositivo comprometido.

**4. Rotación, concurrencia y regreso tras semanas sin conexión**

El ciclo móvil debe pasar a este orden:

1. Recuperar operaciones persistidas y cortes pendientes.
2. Leer una instantánea coherente.
3. Verificar y fusionar el registro con el historial local.
4. Resolver permisos del común, sin necesitar descifrarlo ni conocer personas vivas.
5. Abrir y guardar paquetes comunes.
6. Verificar, abrir y fusionar el común.
7. Resolver políticas, paquetes y slots de sorpresas con el documento resultante.
8. Crear candidata común si no existe ninguna válida para sellar.
9. Guardar candidata, descriptor e intención de reparto antes de publicar.
10. Publicar condicionalmente el común acumulado y su material de distribución.

Las operaciones usan la cola existente de familia. La persistencia necesita un registro recuperable de intención: un cierre entre guardar la clave, ampliar el estado y hacer el PUT no puede dejar un cifrado publicado cuya única clave se haya perdido.

**Regla central: quien no ha podido abrir el común remoto no lo reemplaza.** Conserva sus cambios locales y espera el paquete adecuado o la intervención de otro móvil. Crear otra candidata no permite saltarse esa regla.

Con dos móviles concurrentes:

- Ambos pueden crear candidatas desde la misma instantánea.
- Uno publica; el otro obtiene `412`.
- El segundo procesa la nueva clave, abre y fusiona el común publicado.
- Vuelve a sellar la fusión con la candidata válida elegida.
- Si al reunir registros aparece otra revocación, se descartan ambas candidatas para sellar cuando corresponda y se crea una segura.

No hace falta introducir slots comunes por escritor para esta primera entrega: el común único con CAS funciona si se exige lectura y fusión antes de sustituirlo.

Un móvil desconectado conserva su documento y sus claves. Al volver:

- Si sigue activo, recibe una clave actual, abre el común y fusiona sus campos y lápidas.
- No necesita reconstruir todas las épocas intermedias para aportar sus cambios locales.
- Si quedó huérfano, conserva todo y requiere la reconfirmación individual ya prevista.
- Si fue revocado, no se reincorpora solo por poseer una clave vieja.

**Retención y capacidad:** no copiaría el descarte de candidatas antiguas de las sorpresas sin más. Una clave referenciada por un sobre pendiente, una copia retenida o una operación incompleta no se elimina por llegar a un límite.

Tampoco vale el actual recorte de paquetes a los últimos 512 como mecanismo de distribución común. Antes de publicar con una candidata debe quedar asegurado su reparto a los miembros activos, incluidos los desconectados, dentro de los límites del Worker. Se debe reservar capacidad, retirar únicamente material sustituido de forma verificable y aplicar contrapresión si no cabe. Ante saturación se conserva el trabajo local y se solicita renovación; nunca se borra la única vía de apertura.

**5. Migración, web, ficheros y Worker**

La clave actual se importa como una **clave histórica legacy**, asociada al contexto de migración N. Su audiencia histórica no puede reconstruirse con certeza tomando solo los miembros actuales. Por tanto, no sirve como candidata segura de la nueva etapa.

La activación genera una clave aleatoria nueva y resella el común acumulado. Debe persistir primero un estado de migración pendiente y terminar con una marca local irreversible de formato mínimo.

Recomiendo un corte coordinado de los clientes de prueba:

- Actualizar móviles y web antes de activar.
- Conservar las copias locales de quien esté desconectado.
- Un cliente antiguo recibe “actualización necesaria”; no se le sirve un común nuevo cifrado también con la clave vieja.
- La activación no debe depender de `meta/protocol` dentro del documento editable. Usar una capacidad de transporte persistida y una marca local.
- El Worker aplica el formato mínimo tanto en `PUT S` como en `PUT S/common`.
- Se cierra también la absorción automática legacy/v1 para esa generación. Mantener ese puente permitiría introducir cambios mediante una clave anterior.

No hace falta cambiar `syncId`, credenciales ni identidades. La clave local de cifrado del almacén ya es independiente: no hay que recifrar todos los ficheros locales en cada rotación.

En la **web**:

- `familyKey` pasa a un llavero común dentro de la caja.
- Se guardan conjuntamente claves, contexto, registro y referencia de la instantánea.
- Se abre por `kid`, sin sustituir una clave por “la última recibida”.
- Se firma el común con Ed25519 de la web.
- Se conserva la cola separada y se vuelve a aplicar el filtro de publicación tras GET, rotación y `412`.
- Si falta la clave o la confirmación, se retienen los cambios cifrados y no se publica.
- PIN, guarda y secreto de la caja no cambian por rotar la clave común.
- La web sigue sin crear paquetes ni acceder a sorpresas.

En los **`.regalos` de intercambio**:

- Un contenedor versionado transporta el común firmado, las declaraciones necesarias del registro y paquetes X25519 para destinatarios ya autorizados.
- Ninguna clave viaja en claro ni envuelta únicamente con la clave antigua.
- Un receptor procesa primero el registro y sus paquetes; después verifica y fusiona el común.
- Un fichero antiguo firmado puede aportar cambios de un escritor todavía autorizado.
- Un fichero legacy sin firma queda fuera de la importación automática tras el corte. Se conserva para recuperación explícita o se vuelve a exportar desde el móvil actualizado que mantiene la copia.
- Si falta una clave, se conserva el fichero: no se interpreta como documento vacío.

Los `.regalos` **de recuperación** son otro formato y necesitan incluir llavero, contextos y estado de migración bajo el código de recuperación. Restaurar una copia no debe rebajar el formato mínimo ni rehabilitar credenciales revocadas.

El **Worker** conserva su papel de transporte:

- Comprueba formato, tamaños, generación, rol, propiedad del escritor y precondiciones.
- Aplica el formato mínimo persistido y mantiene la atomicidad de común, registro y paquetes.
- No decide cuál es la candidata legítima ni qué vista de confianza debe aceptar cada móvil.
- No puede demostrar que un común cifrado contiene la fusión correcta.

Ve contexto, `kid`, escritor, audiencia, registro, tamaños y tiempos. No ve claves, campos ni regalos. Un revocado conserva lo antiguo y puede leer publicaciones de clientes que todavía ignoran su revocación; no puede abrir lo resellado con una candidata nueva que lo excluye.

**La garantía empieza en cada escritor cuando conoce y aplica la revocación.** Un servidor malicioso puede ocultársela a un móvil desconectado. No existe revocación global instantánea sin comunicación o una autoridad externa.

**6. Frescura al emparejar: checkpoint exacto aprobado por el anfitrión**

No usaría solo un HLC máximo. Se puede conservar el campo con mayor HLC y omitir otros campos o lápidas. Tampoco basta una versión del Worker, aunque el anfitrión firme el número.

Recomiendo una aprobación nueva que firme:

```text
{
  format,
  listId, syncId, inviteId,
  transcriptHash,
  hostRecord, guestRecord,
  minVersion,
  commonCheckpointHash,
  registryCheckpointHash,
  familyKeyPackages,
  slotFloors
}
```

`transcriptHash` liga oferta, respuesta y revelación. Los hashes son SHA-256 con dominio sobre los bytes exactos aprobados. El checkpoint común está cifrado con una candidata que el invitado recibe.

El anfitrión conserva los bytes exactos de su publicación aceptada. Bajo la cola de familia, aprueba ese contenido y el registro que contiene el aval del invitado. No firma “lo que diga el siguiente GET”.

El Worker guarda una **copia inmutable por invitación** del común y registro aprobados, accesible por el invitado autenticado hasta caducar o cancelar. Puede copiarla del estado actual al aprobar, con el mismo `If-Match`, y contrastar sus hashes.

Esto necesita un recurso de checkpoint separado: el común puede ocupar 2 MiB y no cabe en el límite actual de 64 KiB del paquete de aprobación. Deben fijarse cuotas y limpieza por invitación; no aumentar sin más el paquete pequeño.

El invitado:

1. Comprueba la firma con el anfitrión autenticado por el intercambio en persona.
2. Comprueba lista, generación, invitación, transcript y fichas.
3. Descarga el checkpoint y exige ambos hashes exactos.
4. Verifica el registro, abre el paquete y autentica el común.
5. Guarda esa base, sus claves y el compromiso antes de instalar la familia.
6. Lee el estado actual y lo fusiona con la base aprobada.

Así, si el común actual legítimo ya cambió, no obliga a reiniciar el emparejamiento. Y si el servidor ofrece un común viejo con ETag nuevo, no puede borrar la base que el invitado ya recibió y verificó.

El Worker comprueba coherencia y retención; **la app comprueba la seguridad**. Un Worker malicioso puede retener el checkpoint: el emparejamiento queda pendiente, nunca instalado con una base distinta.

La garantía concreta es: **el invitado recibe el estado exacto aprobado por el anfitrión y conserva sus efectos al fusionar**. No demuestra que el anfitrión conozca todas las ediciones de la familia ni que el servidor entregue cambios posteriores. Tampoco resuelve por sí sola todos los ataques de bifurcación durante la vida de la lista.

**7. Slots ajenos: para tiendas, denegar el borrado**

Mi recomendación concreta es que **ningún móvil pueda enviar `data:null` para el slot de otro**, tampoco invocando revocación, persona borrada o época antigua.

| Situación | Tratamiento recomendado |
|---|---|
| Escritor explícitamente revocado | Dejar de aceptar sus nuevas escrituras y aplicar la política local del ADR; conservar el recurso remoto. |
| Persona borrada | Aplicar la lápida y ocultar lo correspondiente. No inferir que el ciphertext ajeno puede eliminarse. |
| Slot de época anterior | Leerlo con su clave histórica. Su propietario lo sustituye al volver y resellar. |
| Pendiente, huérfano o desconectado | Conservarlo; no compactar basándose en su ausencia. |
| Otro móvil afirma haberlo fusionado | No autoriza borrado: su firma prueba que lo afirma, no que el ciphertext sucesor contenga los datos. |

El Worker puede aplicar una regla pequeña y verificable:

```text
Para cualquier delta de slot:
  caller.role == device
  slot.deviceId == caller.deviceId
```

Además:

- `If-Match` global exacto.
- Validación completa antes de modificar nada.
- Rechazo de toda la petición si incluye un borrado ajeno.
- Rechazo de recursos duplicados en una misma delta.
- Sustitución propia atómica; nunca borrar primero y escribir después.
- Mismas reglas en creación y actualización.

La app elimina la poda remota ajena del motor. Conserva la distinción entre “no cuenta para abrir o autenticar políticas” y “se puede destruir físicamente”. Antes de sustituir su slot, abre el anterior, fusiona, guarda y resella; si no puede abrirlo, no lo reemplaza.

**Coste:** los slots abandonados siguen consumiendo el límite de 64. Debe mostrarse presión de capacidad y utilizar la renovación ya prevista, sin borrar la generación antigua hasta asegurar la transferencia o aceptar explícitamente la pérdida. Esa limitación es preferible a introducir un protocolo de borrado distribuido apresurado.

No recomendaría como alternativa rápida “el Worker permite borrar si la credencial del escritor está revocada”: hoy cualquier móvil puede revocar a otro. Un atacante podría encadenar revocación y destrucción de su única copia remota.

Si después se necesita recolección ajena, diseñaría una autorización del **propietario del slot**, ligada a generación, recurso, hash exacto del slot y sustitución concreta. Exigiría fijar una asociación autenticada entre identidad y clave de firma en el servicio. Incluso entonces, una firma de un tercero que diga “lo he fusionado” no prueba la conservación del contenido cifrado.

El límite general debe quedar escrito: mientras cualquier móvil pueda revocar a otros y exista `DELETE` de lista, no se garantiza disponibilidad frente a cualquier miembro malicioso. Esta medida cierra el borrado ajeno por la delta de slots; no redefine todas las facultades administrativas.

**8. Pruebas que deben existir**

| Área | Casos obligatorios |
|---|---|
| Formatos y criptografía | Manipular cada campo del AAD, firma, `kid`, audiencia, generación y ámbito; X25519 de orden bajo; límites y compresión; vectores Dart ↔ WebCrypto. |
| Rotación concurrente | Dos creadores; dos revocaciones distintas; mismo número con registros diferentes; bajada de época; llegada de una candidata menor; candidata cuya audiencia incluye un revocado. |
| Recuperación | Cierre en cada punto de persistencia y publicación; PUT aceptado con respuesta perdida; `412`; outbox llena; reinicio con la misma candidata y reparto recuperable. |
| Conservación | Móvil ausente semanas; común remoto ilegible que no se sobrescribe; fusión por campo entre épocas; borrado frente a edición; claves históricas todavía referenciadas que no se desalojan. |
| Revocación y ficheros | Revocado con clave vieja fabrica un fichero: no entra; escritor legítimo actualizado reexporta su copia; fichero legacy no degrada la familia; generación distinta rechazada. |
| Migración | Corte interrumpido; cliente antiguo intenta escribir; puente v1 cerrado; copia de recuperación antigua no rebaja el formato. |
| Web | Dos candidatas recibidas en distinto orden; bloqueo durante rotación; cola retenida; cambio de PIN concurrente; raíz revocada; prohibición de emitir claves o recibir sorpresas. |
| Emparejamiento | Común viejo con versión nueva; HLC máximo intacto con campos omitidos; checkpoint sustituido; mezcla de invitaciones; servidor retiene checkpoint; común actual posterior legítimo; reinicio durante instalación. |
| Borrado de slots | Ajeno activo, revocado, huérfano y persona borrada: todos rechazados; época antigua también; delta mixta sin efectos parciales; duplicados; sustitución propia atómica; web rechazada. |
| Integración | Tres móviles y una web, particiones, revocaciones, ficheros y reconexión; presión de paquetes/slots; ninguna desaparición silenciosa ni resurrección de lápidas. |

**9. Estimación**

Son días de ingeniería efectiva, incluyendo pruebas de cada pieza, para alguien familiarizado con el repositorio:

| Pieza | Días |
|---|---:|
| Contrato, formatos, candidatas, AAD y firmas | 4–6 |
| Motor móvil, reparto, persistencia y concurrencia | 5–7 |
| Migración y cierre de compatibilidad insegura | 2–4 |
| Web y migración de caja | 2–3 |
| `.regalos` y recuperación | 2–3 |
| Checkpoint de emparejamiento, app y Worker | 3–5 |
| Worker: formato mínimo, slots y capacidad | 2–3 |
| Integración, fallos y navegadores reales | 3–5 |
| Revisión independiente y correcciones | 2–3 |
| **Total** | **25–39** |

Para Navidad queda ajustado con una sola persona; enero ofrece más margen. B y C no reducen mucho ese coste si conservamos los requisitos de concurrencia, recuperación y revocación por fichero. La simplificación que sí reduce riesgo es **aplazar la recolección ajena de slots**, manteniendo la prohibición desde ahora.

Ficheros tocados: ninguno. Revisión estática únicamente; no ejecuté tests, análisis ni builds, ni inicié servicios. `git status --short` terminó limpio. Las garantías y pruebas propuestas todavía requieren implementación y validación.

VERDICT: A
