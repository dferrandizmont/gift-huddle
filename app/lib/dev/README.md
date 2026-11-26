# lib/dev: solo para desarrollo

`main_demo.dart` monta la web (`RegalosApp(webSession: true)`) con una familia
de muestra en memoria: Aritz, Nora y Leo, más 12 personas de relleno con
regalos inventados. Sin red, sin puerta y sin PIN. No lo importa nada de la
app: no entra en la compilación normal.

Desde `app/`:

```sh
flutter build web --release --no-pub --no-web-resources-cdn --pwa-strategy=none -t lib/dev/main_demo.dart -o build/web_demo
flutter build web --release --no-pub --no-web-resources-cdn --pwa-strategy=none --wasm -t lib/dev/main_demo.dart -o build/web_demo_wasm
node tool/serve_web.mjs --dir build/web_demo        # http://localhost:8790/
node tool/serve_web.mjs --dir build/web_demo_wasm
```

Un servidor a la vez (puerto 8790); al acabar, parar su PID.

## Capturas de la app móvil (`main_store_demo.dart`)

Arranca la app móvil con Aritz, Nora y Leo y regalos de muestra en memoria, sin red, sin PIN ni asistente. El
idioma (y el de los datos) con `--dart-define=DEMO_LOCALE=es|ca|en`; el tema sigue al del sistema
(`adb shell cmd uimode night yes|no`). Se instala en un emulador (`GiftHuddle_Phone`, Pixel 7, 1080×2400, o
`GiftHuddle_Tablet`, 1800×3200 a 320 dpi), se lanza con `--ez enable-impeller false` y los AVD con `hw.gpu.mode=swiftshader_indirect` y 4 GB (con la
configuración por defecto el emulador de Windows se cayó varias veces) y se captura con `adb exec-out screencap -p`. Los datos se calculan respecto a hoy: repetir las
capturas si pasa tiempo.

```sh
flutter build apk --debug -t lib/dev/main_store_demo.dart --dart-define=DEMO_LOCALE=es
```

Con `--dart-define=DEMO_LOCK=true` arranca bloqueada con un PIN de muestra (2468): es la captura `04-bloqueo` de las tiendas. Las capturas
de tienda de Android (móvil y tablet) las hace `tool/store_capture_android.py` (cabecera con el uso); las de iOS, el Mac, con los mismos
nombres (`01-navidad`, `02-deseos`, `03-reparto`, `04-bloqueo`, `05-personas`, `06-lista`, `07-oscuro`).

**iOS (simulador, un solo binario).** `flutter build ios --simulator --debug --no-codesign -t lib/dev/main_store_demo.dart` y se instala
en el simulador (iPhone 17 Pro Max e iPad Pro 13). En iOS `Platform.environment` llega vacío, así que el idioma y el bloqueo se eligen con
dos ficheros en la carpeta Documents de la app, que se escriben antes de lanzarla: `demo_locale` (`es`, `ca` o `en`) y `demo_lock` (`true`)
(`xcrun simctl get_app_container <udid> es.gifthuddle.app data`). Un `--dart-define` manda sobre ellos. Barra de estado con
`xcrun simctl status_bar <udid> override --time 9:41 ...`; el tema oscuro, con `xcrun simctl ui <udid> appearance dark`. El iPad se captura en
horizontal (2752 × 2064). Para `02-deseos` en el iPhone, la lista de Nora se desplaza un poco para plegar la cabecera y esconder el «+».

**Deseos (1.0.7).** La demo apunta seis deseos de Nora (ADR 0010) con el atajo de un solo teléfono (`setSelfRecipient('nora')` +
`createOwnWish`) y quita su «Yo» al acabar, y sustituye `wishPlanRowsProvider` para que la lista de Nora se vea como la ve el móvil de
otra persona: deseos libres con «Lo regalo yo» y uno cogido por Aritz (su plan es un regalo más de la lista). Un regalo de Nora lleva la
etiqueta «Sorpresa». La captura `02-deseos` es esa lista (Personas › Nora, sin definir nada más). La sección fija «Sorpresas» solo la ve la
propia persona en su móvil (ADR 0010, decisión 5): la demo no es el móvil de nadie, así que no sale.
