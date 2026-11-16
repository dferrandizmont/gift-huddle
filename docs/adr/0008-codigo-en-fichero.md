# ADR 0008 — Código de recuperación en un fichero con contraseña

Estado: aceptado (1.0.2) por Daniel el 16-11 tras una revisión técnica independiente;
perfil de Argon2 m=65536/t=3/p=1 confirmado por la medición del 16-11 (abajo).
Complementa ADR 0007; no lo cambia. Sin cambios en el Worker ni en la cápsula.

## Contexto

El código de recuperación (ADR 0007) son 32 bytes aleatorios E que se enseñan
una sola vez como 24 palabras BIP-39 (o QR v1). De E salen `recoveryId`,
`readCap` y la clave Argon2id de la cápsula. Apuntar 24 palabras a mano cuesta
y se hace mal. Daniel eligió el 16-11 la «opción A»: poder guardar además el
código en un fichero protegido con contraseña. Rechazó restaurar una copia
`.gifthuddle` en un móvil vacío (opción B): necesita la aprobación de otro móvil
y crearía identidades duplicadas.

## Decisión

Decisiones de producto de Daniel (16-11): el fichero **complementa** a las
palabras (se enseñan siempre; el fichero es opcional y solo en esa pantalla);
la contraseña es **opcional y por defecto no se pone**, como el kit de
emergencia de Bitwarden, con un aviso claro y una casilla «Proteger con
contraseña»; guardar con el selector o «Comprobar un fichero» cuentan como
código comprobado.

El fichero GHK v1 contiene **solo E**, en una de dos variantes:

* **Abierta** (por defecto): E en claro con una suma de control. Equivale a las
  24 palabras impresas: quien tenga el fichero recupera la lista y entra como
  ese móvil.
* **Protegida**: E cifrada con una contraseña que elige la persona.

E se interpreta **exactamente como la entropía del código de ADR 0007**,
con sus derivaciones HKDF v2 (`recoveryId`, `readCap`) y la clave de la cápsula
v2. La versión del contenedor (GHK v1), la del QR (v1) y la de la cápsula (v2)
son independientes y ninguna cambia implícitamente a otra.

Abrir el fichero con su contraseña devuelve E y, desde ahí, la restauración es
la de escribir las palabras: `RecoveryCode(E)` → mismo `recoveryId`, mismo
`readCap`, misma cápsula, mismo diario de restauración. El fichero no lleva la
cápsula, ni datos de la lista, ni el `recoveryId` (redundante y permitiría
correlacionar copias), ni fecha o revisión (debe seguir valiendo cuando la
cápsula se actualice). Fichero + contraseña nunca da más acceso que las
palabras de la misma E.

### Variante abierta

```
47 48 4B 01 || uint16BE(len(header)) || header || E[32] || check[8]
```

Cabecera canónica exacta `{"k":"recovery-file-open","v":1}`. `check` = los 8
primeros bytes de SHA-256(UTF8(`gift-huddle-recovery-file-open-v1`) || 00 ||
E): detecta un fichero dañado antes de ir al servidor (no es secreto ni
autenticación). Longitud total exacta = 6 + len(header) + 32 + 8. Mismas reglas
de lectura que la protegida (abajo) salvo lo de `kdf` y sal. Abrirla no pide
nada; la app enseña una confirmación antes de restaurar. No pasa por Argon2.

### Criptografía (variante protegida)

* Contraseña P: se normaliza a **NFC** antes de validar su longitud, comparar las
  dos entradas y codificar en UTF-8, al crear y al abrir. Sin recortar, sin
  cambiar mayúsculas, sin NFKC. NFC lo hace la plataforma (Android
  `java.text.Normalizer.Form.NFC`, iOS `precomposedStringWithCanonicalMapping`)
  por el canal nativo existente; sin dependencias nuevas. El core Dart recibe la
  cadena ya normalizada y lo documenta; las pruebas de la capa de aplicación
  cubren entradas NFD.
* Clave: Argon2id v=0x13, contraseña UTF8(NFC(P)), sal aleatoria de 16 bytes
  nueva en cada escritura, salida 32 bytes, secret vacío, associated data =
  UTF8(`gift-huddle-recovery-file-v1`). Perfil **m=65536 KiB, t=3, p=1** (unas
  5 veces el coste de la cápsula, porque aquí la entrada es una contraseña
  humana). Si las mediciones (abajo) no caben en el presupuesto, el perfil
  pasa a **m=65536, t=2, p=1** y se fija aquí antes de publicar. El perfil
  elegido es **exacto**: el lector GHK v1 rechaza cualquier otro valor (ni
  más débil ni más fuerte: un m enorme sería un DoS). Un perfil futuro irá con
  otra versión del contenedor y los lectores publicados se conservan.
* Cifrado: AES-256-GCM, nonce aleatorio de 12 bytes nuevo, tag 16 bytes. Texto
  claro = los 32 bytes de E, sin JSON ni compresión ni checksum (el tag
  autentica).
* Separación de dominio: magia, `k` y AD de Argon2id propios. Ningún derivado
  HKDF de ADR 0007 se usa como clave aquí. No se reutiliza el lector GHR v1.
* Una sola derivación a la vez en la app, en otro isolate, con progreso
  indeterminado; cancelar la descarta sin efectos.

### Medición (puerta de aceptación)

Antes de fusionar se mide en release (AOT) el perfil en el OnePlus 10 Pro, el
Pixel 10 Pro y el móvil más modesto disponible (OnePlus 8T u otro Android
antiguo compatible), y en el iPhone en cuanto haya build de Mac: tiempo de la
derivación, memoria máxima del proceso, comportamiento al pasar a segundo
plano y dos derivaciones seguidas. Presupuesto: **≤ 8 s en el Android más
modesto medido** y sin cierres por memoria. Los resultados se anotan en este
ADR. La restauración completa (fichero + cápsula + red) se mide aparte.

Resultados del 16-11 (APK de perfil AOT aparte, `DartArgon2id` en un isolate,
mismos parámetros y AD; tiempos de la primera y segunda derivación seguidas):

| Móvil | 64 MiB, t=3 | 64 MiB, t=2 | 19 MiB, t=2 (cápsula) | VmHWM del proceso |
|---|---|---|---|---|
| OnePlus 10 Pro (NE2215, 2022) | 1307 / 860 ms | 704 ms | 155 ms | 190 → 449 MB |
| OnePlus 8T (KB2003, 2020) | 1063 / 850 ms | 566 ms | 217 ms | 138 → 310 MB |

Muy por debajo del presupuesto, sin cierres: se mantiene **t=3**. La memoria
máxima sube unos 150-250 MB con dos derivaciones seguidas (el GC no devuelve
enseguida los 64 MiB del isolate); por eso hay una sola derivación a la vez.
Pendiente: un iPhone (sin Mac en esta sesión) y un Android de gama baja si
aparece uno; no se esperan más de unos pocos segundos.

### Formato binario (variante protegida)

```
47 48 4B 01 || uint16BE(len(header)) || header || nonce[12] || ciphertext[32] || tag[16]
```

«GHK» + versión 1; no choca con `RG` (sobres), `RX` (intercambio) ni `GHR` 01/02
(copia v1, cápsula). AAD del GCM = todos los bytes hasta el final de la
cabecera. Cabecera = JSON canónico exacto (el mismo `canonicalJsonOf`):

```json
{"k":"recovery-file","kdf":{"a":"argon2id","m":65536,"p":1,"t":3},"s":"<sal base64url sin relleno>","v":1}
```

Reglas de lectura, todas **antes** de derivar:

* Lectura acotada en la plataforma: se rechaza sin materializar todo lo que
  supere 512 bytes. Se trabaja sobre una copia inmutable de los bytes.
* Magia exacta; versión ≠ 1 → «versión más nueva, actualiza la app» (sin probar
  otros formatos). `k` decide la variante (`recovery-file` o
  `recovery-file-open`); otro `k` se rechaza.
* Cabecera ≤ 256 bytes, UTF-8 estricto, objeto JSON; campos exactos en el objeto
  y en `kdf` (ni más ni menos), tipos exactos (enteros, no flotantes); al
  re-serializar canónicamente debe dar **los mismos bytes** (rechaza claves
  duplicadas, espacios y desorden).
* `s` base64url canónica: decodifica a 16 bytes exactos y al re-codificar da la
  misma cadena.
* Longitud total exacta = 6 + len(header) + 12 + 32 + 16 (rechaza truncados y
  bytes finales).

Cualquier fallo anterior a Argon2 es «no es un fichero de recuperación válido»;
un fallo de GCM es «contraseña incorrecta o fichero dañado» (indistinguibles a
propósito). Tras abrir, E debe medir 32 bytes.

Vectores normativos: [0008-vector-fichero.json](0008-vector-fichero.json),
generados de forma independiente (Python `argon2-cffi`/libargon2 con AD y
`cryptography` AESGCM) con [`tool/recovery_file_vectors.py`](../../tool/recovery_file_vectors.py),
con E, sal y nonce públicos de prueba. Positivos: la
variante abierta (con negativos de `check` y longitud), una contraseña ASCII, una con «ñ» y tilde en NFC y la misma en NFD que, tras NFC,
da la misma clave (este caso se prueba en la capa de aplicación). Negativos:
magia, versión, `k`, cada campo de `kdf`, campo extra, clave duplicada,
cabecera no canónica, sal no canónica o de otra longitud, truncado, bytes
finales, alteración de cabecera, nonce, ciphertext y tag, contraseña errónea.
Dart debe reproducir los bytes exactos y abrirlos.

### Contraseña (si se elige)

Por defecto la casilla «Proteger con contraseña» está desactivada y el texto
dice que quien tenga el fichero puede recuperar la lista, y que con contraseña
robarlo no basta pero olvidarla lo inutiliza. Si se activa: **al menos 15
caracteres** (runas tras NFC), como mucho 128, sin reglas de mayúsculas,
números ni símbolos, rechazada si es un carácter o un bloque corto repetido,
solo números, una fila o secuencia de teclado, contiene el nombre de la app, o
está en una **lista corta local** de frases frecuentes en es/ca/en escrita para
la app (sin descargas ni red). La longitud es un filtro, no una garantía. Se escribe dos veces. Texto de ayuda: usar el gestor de
contraseñas o varias palabras **elegidas al azar**. Campo oculto con botón de
ver, sin autocorrección, sugerencias ni aprendizaje del teclado
(`enableIMEPersonalizedLearning: false`), con pegado permitido y
`AutofillHints.newPassword` (al restaurar, `AutofillHints.password`) para que
un gestor la guarde. Las reglas de creación no se aplican al abrir: un fichero
ya emitido se abre con su contraseña aunque las reglas cambien. No se guarda
pista ni la contraseña.

Si se olvida la contraseña, el fichero no sirve y nadie puede abrirlo. Siguen
valiendo las 24 palabras. Para otro fichero hay que cambiar el código.

### Entrega y sesión

Solo se puede guardar mientras se enseñan las palabras (crear o cambiar el
código), con el código que la pantalla recibió de `takeCodeDisplay`; nunca se
vuelve a leer E de `readMaterial` para reintentar ni se exporta una candidata
sin activar. La entrega única es una restricción de interfaz: el móvil conserva
E para el mantenimiento, no la borra. Mientras la pantalla siga viva se pueden
guardar varias copias (sal y nonce nuevos cada vez; la protección real es la de
la copia con la contraseña más débil). Abrir el selector deja la app en segundo
plano sin cerrar la sesión; si el proceso muere, la entrega ya está consumida y
no se reabre (igual que hoy con las palabras: queda «Sin comprobar» hasta
comprobar o cambiar el código). Cualquier confirmación tardía pasa por
`confirmCode`, que revalida identidad, E vigente, retirada y `transferred`; un
resultado antiguo del selector nunca confirma un código nuevo.

### Dónde se guarda

* **Selector de ficheros del sistema** (principal): Android
  `ACTION_CREATE_DOCUMENT`; iOS `UIDocumentPickerViewController(forExporting:)`.
  Tras escribir, la app relee **el documento de destino** (en iOS la URL
  devuelta, con acceso de seguridad y coordinación de ficheros) con lectura
  acotada, lo parsea y lo abre con la clave recién derivada (GCM, sin segundo
  Argon2) y comprueba que da la misma E.
* **Hoja de compartir** (secundaria): con el fichero temporal de la carpeta de
  exportación. Se borra al volver a la pantalla tras un margen, en el siguiente
  arranque si quedó (cierre abrupto) y en «Borrar todo».
* Nunca en la galería ni en el portapapeles. Nombre traducido por ARB con fecha
  y hora para no chocar: `gift-huddle-recuperacion-AAAAMMDD-HHMM.gifthuddle`.
  Extensión `.gifthuddle` reutilizada y tipo `application/vnd.gifthuddle`: ya se
  abre desde Archivos en ambos sistemas; los bytes deciden el formato. El texto
  avisa de que el fichero es personal y no se envía a la familia.

### Comprobado / «Sin comprobar»

`wordsConfirmed` pasa a significar «posesión del código verificada» (el nombre
interno no cambia; se documenta). Cuenta como comprobado:

* el paso actual de tres palabras;
* guardar con el selector del sistema cuando la relectura del destino abre y da
  la misma E;
* **«Comprobar un fichero»**: elegir el fichero guardado (también uno enviado
  por la hoja de compartir) y escribir su contraseña; si da la E vigente,
  `confirmCode`. Esta comprobación no exporta nada y vale después de la entrega.

Compartir por sí solo no cuenta. Los textos no dicen que se comprobaron las
palabras ni que exista una copia externa duradera: dicen que el código está
comprobado.

### Restaurar y abrir desde Archivos

* Bienvenida: junto a «Tengo un código de recuperación», «Recuperar con
  fichero» → selector del sistema (`ACTION_OPEN_DOCUMENT` / document picker,
  nuevos en el canal nativo) → contraseña → derivación con progreso → E → el
  mismo flujo de restauración que con las palabras. Restaurar marca el código
  como comprobado (ya pasa con palabras). Con la variante abierta no hay paso
  de contraseña: se enseña una confirmación y se restaura.
* Distribuidor por magia **antes** del importador actual
  (`IncomingShareController._importBytes` → hoy todo va a `importEnvelopeBytes`):
  GHK va al flujo de recuperación; el resto, igual que hoy. Mismo trato desde el
  selector, el arranque en frío y un intent con la app abierta. Recibir un
  fichero nunca arranca Argon2 ni red: siempre pide la contraseña.
* Respeta el bloqueo local, una restauración pendiente y una familia existente:
  con familia, dice que el fichero sirve para un móvil vacío y no hace nada más.
  Una sola operación de fichero de recuperación a la vez; si llega otro mientras
  se procesa uno, se pregunta antes de cambiarlo.
* Las pantallas de crear y escribir la contraseña van con la protección de
  pantalla del flujo: en Android FLAG_SECURE (sin capturas); en iPhone **no se
  pueden bloquear las capturas**, solo se cubre la vista previa del selector de
  apps (`secure_screen.dart`).

### Cambiar o quitar el código

El fichero guarda E, así que hereda la semántica de ADR 0007 sin excepciones:

| Estado | Fichero y palabras viejos |
|---|---|
| Rotación preparada, sin confirmar | Siguen valiendo hasta el commit. La E nueva aún no se entrega ni se guarda. |
| Candidata cancelada o expirada | Sigue valiendo la E anterior; la candidata no es recuperable. |
| Cambio de persona o retirada pendiente (offline) | La cápsula vieja sigue accesible hasta confirmar DELETE. No hay invalidación offline. |
| Rotación o retirada confirmada | Pierden el acceso remoto igual; el rechazo del localizador dura la retención de 400 días. |
| Traslado por `claim` (`transferred` en el móvil anterior) | **E se conserva**: fichero y palabras siguen abriendo la cápsula actualizada. Trasladar no expulsa a quien guarda el código. |

Cambiar el código no remedia un compromiso previo: borrar la cápsula no borra
copias descargadas ni claves ya extraídas (ADR 0007). La pantalla de cambiar el
código avisa: «Los ficheros y las palabras anteriores dejarán de servir».

## Riesgos y por qué se aceptan

* **Variante abierta = palabras impresas.** Quien llegue al fichero (Drive,
  correo, una copia del móvil) entra sin más. Decisión de Daniel por sencillez y
  porque no se puede perder por olvido; el aviso lo dice y la casilla de
  contraseña está a un toque. Es incoherente a propósito con bloquear capturas:
  una captura acaba sola en la galería y en la nube; el fichero se guarda donde
  la persona elige.
* **Fichero protegido robado = ataque sin conexión a la contraseña** (el tag GCM verifica
  cada intento). Argon2 64 MiB y la política de contraseña lo encarecen; una
  contraseña previsible cae igual. Las palabras siguen siendo la vía fuerte.
* **Disponibilidad:** el fichero no contiene los datos. Depende del Worker, de la
  retención de la lista y de que exista una cápsula. Guardarlo años no conserva
  la familia años.
* **Dependencia circular:** fichero y contraseña deben seguir accesibles sin
  este móvil (no solo en su almacenamiento ni en un gestor que dependa de él).
  El texto lo dice.
* **Dispositivo comprometido** (teclado malicioso, accesibilidad, volcado de
  memoria): puede obtener P o E. Se limpian controladores al salir; las cadenas
  de Dart no se pueden borrar de forma segura.
* **Copias externas:** correo, nubes y gestores guardan versiones. «Borrar todo»
  solo limpia lo que controla la app.
* **Autenticidad:** GCM prueba que quien lo creó conocía la contraseña, no quién
  fue. El flujo existente sigue validando cápsula, identidad y contexto.
* **Metadatos:** nombre y extensión revelan que existe una recuperación de Gift
  Huddle, no E.
* **Coste de Argon2** en móviles viejos: medido antes de publicar (arriba).

## Fuera de alcance

Exportar el fichero después de la entrega, pista de contraseña, cambiar la
contraseña de un fichero, restaurar desde la web, cambios en el Worker.
