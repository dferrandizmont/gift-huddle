package com.dferrandizmont.regalos

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.text.Normalizer
import java.io.InputStream
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Actividad principal.
 *
 * - FlutterFragmentActivity: lo exige local_auth para la huella.
 * - Sin miniatura en el selector de apps. Las capturas en primer plano se
 *   permiten en las prereleases. Desde la 1.0.6, la versión de tienda ya no
 *   bloquea toda la app: Flutter pide `setSecure` solo mientras se ve una
 *   pantalla con regalos (`GiftsSecureScope`). `secureScreen` ya no se pide.
 * - `setSecure`: pone o quita FLAG_SECURE solo mientras se ven las palabras o el QR
 *   del código de recuperación (también en las prereleases).
 * - Recibe los ficheros .regalos que se abren o comparten con la app y se los
 *   pasa a Flutter por un MethodChannel (sin plugins de terceros).
 * - Por el mismo canal, abre en el navegador el enlace a la politica de privacidad.
 * - Fichero de recuperación (ADR 0008): guarda con ACTION_CREATE_DOCUMENT y
 *   relee el destino, abre con ACTION_OPEN_DOCUMENT con lectura acotada y
 *   normaliza contraseñas a NFC. Cancelar devuelve null, no un error.
 */
class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null
    private var pinKdfChannel: MethodChannel? = null

    /** Versión de tienda (`STORE_BUILD`): FLAG_SECURE siempre puesto. */
    private var secureAlways = false

    /** Pantalla sensible a la vista (las palabras del código de recuperación). */
    private var secureTemporary = false

    /** Fichero recibido al arrancar, hasta que Flutter lo pide. */
    private var initialFile: ByteArray? = null

    /** Si el fichero de arranque todavia se esta leyendo. */
    private var initialLoading = false

    /** Peticion de Flutter que espera al fichero de arranque. */
    private var initialRequest: MethodChannel.Result? = null

    /**
     * Peticiones de Flutter que esperan la respuesta del permiso de camara.
     * Todas reciben la respuesta real del dialogo en curso (antes, la segunda
     * recibia `false` al momento). `true`: esperan el texto del resultado
     * (`requestCameraPermissionStatus`); `false`, el si o no de siempre.
     */
    private val cameraRequests = mutableListOf<Pair<MethodChannel.Result, Boolean>>()

    /**
     * Si hay una peticion nativa del permiso sin contestar. Solo hay una a la
     * vez: las demas esperan su respuesta (nunca se lanza otra encima, que
     * Android contestaria vacia y se llevaria las respuestas de todas).
     */
    private var cameraPending = false

    /** Si la actividad se pauso desde la peticion: el dialogo llego a salir. */
    private var cameraDialogShown = false

    /**
     * Si la ultima peticion termino en un «no» con el dialogo a la vista (para
     * saber si el siguiente ya es para siempre). Cualquier otro final (dado,
     * interrumpido, error) lo borra: solo cuentan dos «no» seguidos.
     */
    private var cameraDeniedBefore = false

    /** Sube con cada peticion nativa: la recuperacion solo vale para la suya. */
    private var cameraGeneration = 0

    /** La recuperacion programada en onResume para la peticion en curso. */
    private var cameraRecovery: Runnable? = null

    /** La lectura de ficheros va en un hilo de fondo, nunca en el principal. */
    /**
     * Lecturas de ficheros que llegan por intents: como mucho dos hilos y dos
     * en cola (una app no puede acumular hilos con content:// colgados); lo
     * que no cabe se rechaza y entrega null.
     */
    private val reader = ThreadPoolExecutor(
        1, 2, 30L, TimeUnit.SECONDS, ArrayBlockingQueue(2), ThreadPoolExecutor.AbortPolicy()
    )

    /** Una lectura entrante a la vez; la que llega mientras, null. */
    private val incomingGate = IncomingReadGate()

    /**
     * El selector del fichero de recuperación tiene su propio hilo: un
     * content:// colgado de un intent externo nunca bloquea un guardado.
     */
    private val pickerIo = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Selector del sistema abierto para el fichero de recuperación. */
    private var pickerRequest: PickerRequest? = null

    /**
     * Selector que estaba abierto cuando se recreó la Activity (o murió el
     * proceso): su Flutter ya no espera respuesta. Solo se guarda el tipo,
     * nunca los bytes.
     */
    private var orphanPickerKind: String? = null

    /**
     * [save] = bytes que se escriben en el destino; null = solo abrir. Se
     * resuelve una sola vez, pase lo que pase.
     */
    private class PickerRequest(
        private val result: MethodChannel.Result,
        val save: ByteArray?,
        val maxBytes: Int,
    ) {
        private val done = AtomicBoolean(false)

        val kind: String get() = if (save != null) PickerOutcome.CREATE else PickerOutcome.OPEN

        fun reply(block: (MethodChannel.Result) -> Unit) {
            if (!done.compareAndSet(false, true)) return
            try {
                block(result)
            } catch (e: Exception) {
                // El motor ya no escucha (Activity destruida).
            }
        }
    }

    private val documentPicker = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { outcome ->
        val request = pickerRequest
        pickerRequest = null
        val orphan = orphanPickerKind
        orphanPickerKind = null
        val uri = outcome.data?.data
        val action = PickerOutcome.decide(
            hasRequest = request != null,
            orphanKind = orphan,
            ok = outcome.resultCode == Activity.RESULT_OK,
            hasUri = uri != null,
        )
        when (action) {
            PickerOutcome.Action.CANCELLED -> request?.reply { it.success(null) }
            PickerOutcome.Action.IGNORE_ORPHAN -> Unit
            PickerOutcome.Action.DELETE_ORPHAN -> {
                // Documento creado vacío para un Flutter que ya no existe: no
                // hay E que escribir; se borra para no dejar un fichero roto.
                val created = uri ?: return@registerForActivityResult
                try {
                    pickerIo.execute { deleteIfEmpty(created) }
                } catch (e: Exception) {
                    // Se queda vacío: no contiene nada.
                }
            }
            PickerOutcome.Action.PROCESS -> process(request!!, uri!!)
        }
    }

    private fun process(request: PickerRequest, uri: Uri) {
        try {
            pickerIo.execute {
                var bytes: ByteArray? = null
                var error: String? = null
                try {
                    val save = request.save
                    if (save != null) writeDocument(uri, save)
                    bytes = readBounded(uri, request.maxBytes)
                } catch (e: BoundedRead.TooLargeException) {
                    error = "too_large"
                } catch (e: Exception) {
                    error = "read_failed"
                }
                val read = bytes
                val failure = error
                mainHandler.post {
                    request.reply {
                        if (failure != null) it.error(failure, null, null) else it.success(read)
                    }
                }
            }
        } catch (e: Exception) {
            request.reply { it.error("read_failed", null, null) }
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        val kind = pickerRequest?.kind ?: orphanPickerKind
        if (kind != null) outState.putString(PICKER_KIND, kind)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Se permiten las capturas de pantalla (se usan para pruebas y revisiones).
        // Lo que sí se oculta es la miniatura del selector de apps (Android 13+).
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(false)
        }
        super.onCreate(savedInstanceState)
        disableFocusHighlight(window.decorView)
        orphanPickerKind = savedInstanceState?.getString(PICKER_KIND)
        // Al recrear la actividad el intent es el mismo: no se vuelve a importar.
        if (savedInstanceState == null) {
            val uri = sharedUri(intent)
            if (uri != null) {
                initialLoading = true
                readAsync(uri) { bytes ->
                    initialFile = bytes
                    initialLoading = false
                    initialRequest?.success(initialFile)
                    if (initialRequest != null) initialFile = null
                    initialRequest = null
                }
            }
        }
    }

    override fun onPause() {
        // Antes de Android 13 se protege la miniatura al salir. En depuración
        // no se usa FLAG_SECURE para permitir las capturas y herramientas de QA.
        val debuggable = (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU && !debuggable) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        if (cameraPending) cameraDialogShown = true
        super.onPause()
    }

    override fun onResume() {
        // El dialogo se cierra con la respuesta antes de volver aqui. Si se
        // volvio sin respuesta (se perdio), se da la peticion por terminada
        // para que la siguiente pueda lanzar otra: Flutter mira el permiso.
        if (cameraPending && cameraDialogShown) {
            val generation = cameraGeneration
            cameraRecovery?.let { mainHandler.removeCallbacks(it) }
            val recovery = Runnable {
                if (cameraPending && cameraGeneration == generation) {
                    answerCamera(if (hasCamera()) CAMERA_GRANTED else CAMERA_CANCELLED)
                }
            }
            cameraRecovery = recovery
            mainHandler.postDelayed(recovery, CAMERA_LOST_MS)
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU && !secureAlways && !secureTemporary) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        super.onResume()
        // Antes de que la ventana pinte y reparta el foco (si el foco llega
        // antes, el resalte ya queda calculado), y otra vez por si la vista de
        // Flutter aún no estaba.
        disableFocusHighlight(window.decorView)
        window.decorView.post { disableFocusHighlight(window.decorView) }
    }

    override fun onStart() {
        super.onStart()
        disableFocusHighlight(window.decorView)
    }

    /**
     * Quita el resalte de foco que Android pinta por defecto (Android 8+) sobre
     * la vista con foco cuando llega una tecla (teclado físico, o Gboard con
     * borrar o intro). La FlutterView ocupa toda la pantalla: sin esto, una
     * sola tecla dejaba un velo gris translúcido sobre toda la app, hasta que
     * se salía y se volvía. El foco con teclado de verdad (botones, campos y
     * desplegables) lo pinta Flutter por su cuenta (`FocusRingOverlay`).
     */
    private fun disableFocusHighlight(view: View) {
        view.setDefaultFocusHighlightEnabled(false)
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) disableFocusHighlight(view.getChildAt(i))
        }
    }

    override fun onDestroy() {
        // Su Flutter se va con la Activity: la petición se cierra como
        // cancelada (una sola vez) y el resultado tardío no escribe nada.
        pickerRequest?.reply { it.success(null) }
        pickerRequest = null
        reader.shutdown()
        pickerIo.shutdown()
        // Nadie va a contestar ya: que Flutter no espere para siempre.
        answerCamera(CAMERA_CANCELLED)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pinKdfChannel = PinKdf.register(flutterEngine.dartExecutor.binaryMessenger)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeInitialFile" -> {
                    if (initialLoading) {
                        initialRequest = result
                    } else {
                        result.success(initialFile)
                        initialFile = null
                    }
                }
                "deviceModel" -> result.success(deviceModelName())
                "openUrl" -> result.success(openInBrowser(call.arguments as? String))
                "openUserUrl" -> result.success(openUserLink(call.arguments as? String))
                // El permiso de camara se pide aqui, una sola vez, antes de
                // crear el lector: el lector de QR lo volvia a pedir al volver
                // del dialogo (no marca que ya lo esta pidiendo).
                "cameraPermission" -> result.success(hasCamera())
                "requestCameraPermission" -> requestCamera(result, asStatus = false)
                // Igual, pero dice granted, denied, permanentlyDenied o cancelled.
                "requestCameraPermissionStatus" -> requestCamera(result, asStatus = true)
                "openAppSettings" -> result.success(openAppSettings())
                "secureScreen" -> {
                    // Versión de tienda: sin capturas ni grabaciones, siempre.
                    secureAlways = true
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                "setSecure" -> {
                    // Solo mientras se ven las palabras o el QR de recuperación,
                    // también en las prereleases. En la versión de tienda el
                    // flag ya está siempre y no se quita.
                    secureTemporary = call.arguments as? Boolean ?: false
                    if (secureTemporary) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else if (!secureAlways) {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                "saveDocument" -> startPicker(call, result, save = true)
                "openDocument" -> startPicker(call, result, save = false)
                "normalizeNfc" -> {
                    val text = call.arguments as? String
                    if (text == null) {
                        result.error("bad_args", null, null)
                    } else {
                        result.success(Normalizer.normalize(text, Normalizer.Form.NFC))
                    }
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pinKdfChannel?.setMethodCallHandler(null)
        pinKdfChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /**
     * Abre el selector del sistema: guardar (ACTION_CREATE_DOCUMENT, escribe
     * y relee el destino) o abrir (ACTION_OPEN_DOCUMENT). Uno a la vez.
     */
    private fun startPicker(call: MethodCall, result: MethodChannel.Result, save: Boolean) {
        if (pickerRequest != null) {
            result.error("busy", null, null)
            return
        }
        val maxBytes = call.argument<Int>(if (save) "maxReadBytes" else "maxBytes") ?: 0
        if (maxBytes <= 0 || maxBytes > MAX_BYTES) {
            result.error("bad_args", null, null)
            return
        }
        val bytes: ByteArray?
        val intent: Intent
        if (save) {
            bytes = call.argument<ByteArray>("bytes")
            val name = call.argument<String>("name")
            if (bytes == null || name.isNullOrEmpty() || name.contains('/')) {
                result.error("bad_args", null, null)
                return
            }
            intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType(call.argument<String>("mime") ?: "application/octet-stream")
                .putExtra(Intent.EXTRA_TITLE, name)
        } else {
            bytes = null
            intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType("*/*")
        }
        pickerRequest = PickerRequest(result, bytes, maxBytes)
        try {
            documentPicker.launch(intent)
        } catch (e: Exception) {
            pickerRequest = null
            result.error("unavailable", null, null)
        }
    }

    /**
     * Borra el documento solo si mide 0 bytes: uno que la persona eligió
     * sobrescribir y que ya tenía contenido nunca se borra.
     */
    private fun deleteIfEmpty(uri: Uri) {
        try {
            val empty = try {
                contentResolver.openInputStream(uri)?.use { it.read() < 0 } ?: false
            } catch (e: Exception) {
                false
            }
            if (empty) DocumentsContract.deleteDocument(contentResolver, uri)
        } catch (e: Exception) {
            // Se queda como está.
        }
    }

    /** Escribe [bytes] en el documento recién creado; si falla, lo borra. */
    private fun writeDocument(uri: Uri, bytes: ByteArray) {
        try {
            val stream = try {
                contentResolver.openOutputStream(uri, "wt")
            } catch (e: Exception) {
                null
            } ?: contentResolver.openOutputStream(uri, "w") ?: throw IOException("no output")
            stream.use {
                it.write(bytes)
                it.flush()
            }
        } catch (e: Exception) {
            // Se queda vacío o a medias si no se puede borrar: la relectura lo
            // rechaza igual.
            deleteIfEmpty(uri)
            throw e
        }
    }

    /**
     * Lee [uri] entero solo si mide como mucho [max] bytes. Mira antes el
     * tamaño declarado y, al leer, corta en cuanto pasa del tope: un fichero
     * mayor nunca se materializa.
     */
    private fun readBounded(uri: Uri, max: Int): ByteArray {
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val i = c.getColumnIndex(OpenableColumns.SIZE)
                    if (i >= 0 && !c.isNull(i) && c.getLong(i) > max) {
                        throw BoundedRead.TooLargeException()
                    }
                }
            }
        } catch (e: BoundedRead.TooLargeException) {
            throw e
        } catch (e: Exception) {
            // Sin tamaño declarado: se acota al leer.
        }
        val input = contentResolver.openInputStream(uri) ?: throw IOException("no input")
        return input.use { BoundedRead.exact(it, max) }
    }


    private fun hasCamera(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestCamera(result: MethodChannel.Result, asStatus: Boolean) {
        if (hasCamera()) {
            cameraDeniedBefore = false
            result.success(if (asStatus) CAMERA_GRANTED else true)
            return
        }
        cameraRequests.add(result to asStatus)
        // Ya hay una peticion nativa en curso: esta espera su respuesta. Que
        // Flutter deje de esperar (su plazo) no la termina.
        if (cameraPending) return
        cameraPending = true
        cameraDialogShown = false
        cameraGeneration++
        try {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                CAMERA_REQUEST
            )
        } catch (e: Exception) {
            answerCamera(CAMERA_CANCELLED)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CAMERA_REQUEST) return
        val outcome = when {
            // Sin resultados: la peticion se interrumpio (otro dialogo, la
            // actividad se recreo...). No es un «no».
            grantResults.isEmpty() -> if (hasCamera()) CAMERA_GRANTED else CAMERA_CANCELLED
            grantResults[0] == PackageManager.PERMISSION_GRANTED -> CAMERA_GRANTED
            // «Para siempre» solo si el sistema ya no ensena el dialogo: sin
            // rationale y, ademas, el «no» llego sin que saliera (la actividad
            // no se pauso) o es el segundo seguido. Cerrar el dialogo tocando
            // fuera (Android 11+) tambien da rationale falso y es un «no» normal.
            !ActivityCompat.shouldShowRequestPermissionRationale(
                this,
                Manifest.permission.CAMERA
            ) && (!cameraDialogShown || cameraDeniedBefore) -> CAMERA_PERMANENTLY_DENIED
            else -> CAMERA_DENIED
        }
        val shownDenial = cameraDialogShown &&
            (outcome == CAMERA_DENIED || outcome == CAMERA_PERMANENTLY_DENIED)
        answerCamera(outcome, shownDenial)
    }

    /**
     * Termina la peticion en curso: contesta a todas las que esperan con
     * [outcome], anula su recuperacion y apunta si fue un «no» con dialogo.
     */
    private fun answerCamera(outcome: String, shownDenial: Boolean = false) {
        cameraPending = false
        cameraDialogShown = false
        cameraDeniedBefore = shownDenial
        cameraRecovery?.let { mainHandler.removeCallbacks(it) }
        cameraRecovery = null
        val waiting = cameraRequests.toList()
        cameraRequests.clear()
        for ((result, asStatus) in waiting) {
            try {
                result.success(if (asStatus) outcome else outcome == CAMERA_GRANTED)
            } catch (e: Exception) {
                // Ya contestada o el motor se fue: nada que hacer.
            }
        }
    }

    /** Abre la pagina de la app en los ajustes del sistema (dar el permiso a mano). */
    private fun openAppSettings(): Boolean = try {
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (e: Exception) {
        false
    }

    /** Modelo del movil para proponerlo como nombre ("OnePlus NE2213"); no lleva datos de la persona. */
    private fun deviceModelName(): String {
        val model = (Build.MODEL ?: "").trim()
        val maker = (Build.MANUFACTURER ?: "").trim()
        if (model.isEmpty()) return maker
        if (maker.isEmpty() || model.startsWith(maker, ignoreCase = true)) return model
        return maker.replaceFirstChar { it.uppercase() } + " " + model
    }

    /**
     * Abre un enlace https en el navegador del sistema (la politica de
     * privacidad de Acerca de) o un mailto: en la app de correo (el soporte).
     * La app no se conecta a nada: lo hace el navegador o el correo. Devuelve
     * false si el enlace no es https ni mailto o no hay con que abrirlo.
     */
    private fun openInBrowser(url: String?): Boolean {
        if (url == null) return false
        // Check the original authority before parsing: explicit ports are forbidden.
        val allowedHttps = Regex(
            "^https://gifthuddle\\.app(?:[/?#]|$)",
            RegexOption.IGNORE_CASE
        ).containsMatchIn(url)
        if (!allowedHttps && !url.startsWith("mailto:")) return false
        val uri = Uri.parse(url)
        return try {
            when (uri.scheme) {
                "https" -> startActivity(
                    Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE)
                )
                "mailto" -> startActivity(Intent(Intent.ACTION_SENDTO, uri))
                else -> return false
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Abre un enlace de regalo. Vuelve a validar la autoridad antes de que
     * Android interprete la URL y excluye el dominio de los App Links.
     */
    private fun openUserLink(url: String?): Boolean {
        if (url == null || url.length > 2048) return false
        val unsafeCharacters = Regex("""[\\\p{Z}\p{Cf}\u0000-\u001f\u007f-\u009f]""")
        if (unsafeCharacters.containsMatchIn(url)) return false
        val shape = Regex(
            """https://(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+""" +
                """(?:[A-Za-z]{2,63}|[Xx][Nn]--[A-Za-z0-9-]{0,58}[A-Za-z0-9])(?:[/?#].*)?"""
        )
        if (!shape.matches(url)) return false
        val uri = Uri.parse(url)
        if (uri.scheme != "https") return false
        val host = uri.host?.lowercase() ?: return false
        if (host == "gifthuddle.app" || host.endsWith(".gifthuddle.app")) return false
        return try {
            startActivity(
                Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE)
            )
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: SecurityException) {
            false
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val uri = sharedUri(intent) ?: return
        readAsync(uri) { bytes ->
            if (bytes != null) {
                val ch = channel
                if (ch != null) {
                    ch.invokeMethod("onFile", bytes)
                } else {
                    initialFile = bytes
                }
            }
        }
    }

    /** El content:// de un intent VIEW o SEND, o null. Nunca file://. */
    private fun sharedUri(intent: Intent?): Uri? {
        if (intent == null) return null
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
            else -> null
        }
        return if (uri != null && uri.scheme == "content") uri else null
    }

    /** Lee [uri] en el hilo de fondo y entrega el resultado en el principal. */
    private fun readAsync(uri: Uri, deliver: (ByteArray?) -> Unit) {
        // Una sola lectura entrante a la vez y una sola entrega: el resultado
        // o, si el content:// se cuelga, null al pasar el tope de tiempo, con
        // el Future cancelado y el stream cerrado.
        val token = incomingGate.begin()
        if (token == null) {
            deliver(null)
            return
        }
        val stream = CancellableStream<InputStream>()
        var future: Future<*>? = null
        val timeout = Runnable {
            if (incomingGate.end(token)) {
                future?.cancel(true)
                // Lo que se publique después se cierra sin leer.
                stream.cancel()?.let { open ->
                    // Cerrar puede bloquear: fuera del hilo principal.
                    Thread {
                        try {
                            open.close()
                        } catch (e: Exception) {
                            // Ya estaba cerrado.
                        }
                    }.start()
                }
                deliver(null)
            }
        }
        try {
            future = reader.submit {
                val bytes = readBytes(uri, stream)
                mainHandler.post {
                    if (incomingGate.end(token)) {
                        mainHandler.removeCallbacks(timeout)
                        deliver(bytes)
                    }
                }
            }
            mainHandler.postDelayed(timeout, INCOMING_READ_TIMEOUT_MS)
        } catch (e: Exception) {
            if (incomingGate.end(token)) deliver(null)
        }
    }

    /**
     * Lee los bytes de [uri] con [BoundedRead.incoming]: un fichero de
     * recuperación se corta en 513 bytes (Flutter lo rechaza por grande) y un
     * sobre en 2 MiB (null si pasa); null también ante cualquier error.
     */
    private fun readBytes(uri: Uri, slot: CancellableStream<InputStream>): ByteArray? {
        return try {
            val input = contentResolver.openInputStream(uri) ?: return null
            // Si el tope ya venció mientras se abría, se cierra sin leer.
            if (!slot.publish(input)) return null
            try {
                input.use { BoundedRead.incoming(it) }
            } finally {
                slot.release(input)
            }
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        private const val CHANNEL = "com.dferrandizmont.regalos/incoming"
        private const val CAMERA_REQUEST = 7301
        private const val CAMERA_GRANTED = "granted"
        private const val CAMERA_DENIED = "denied"
        private const val CAMERA_PERMANENTLY_DENIED = "permanentlyDenied"
        private const val CAMERA_CANCELLED = "cancelled"

        /** Tras volver a la actividad sin respuesta, cuanto se espera aun. */
        private const val CAMERA_LOST_MS = 1_000L
        private const val MAX_BYTES = BoundedRead.MAX_ENVELOPE_BYTES
        private const val PICKER_KIND = "recoveryPickerKind"
        private const val INCOMING_READ_TIMEOUT_MS = 30_000L
    }
}
