package com.dferrandizmont.regalos

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Actividad principal.
 *
 * - FlutterFragmentActivity: lo exige local_auth para la huella.
 * - Sin miniatura en el selector de apps. Las capturas en primer plano se
 *   permiten en las prereleases; en la versión de tienda (`--dart-define=
 *   STORE_BUILD=true`) Flutter pide `secureScreen` y se bloquean siempre.
 * - `setSecure`: pone o quita FLAG_SECURE solo mientras se ven las palabras o el QR
 *   del código de recuperación (también en las prereleases).
 * - Recibe los ficheros .regalos que se abren o comparten con la app y se los
 *   pasa a Flutter por un MethodChannel (sin plugins de terceros).
 * - Por el mismo canal, abre en el navegador el enlace a la politica de privacidad.
 */
class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null

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

    /** Peticion de Flutter que espera la respuesta del permiso de camara. */
    private var cameraRequest: MethodChannel.Result? = null

    /** La lectura de ficheros va en un hilo de fondo, nunca en el principal. */
    private val reader = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        // Se permiten las capturas de pantalla (se usan para pruebas y revisiones).
        // Lo que sí se oculta es la miniatura del selector de apps (Android 13+).
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(false)
        }
        super.onCreate(savedInstanceState)
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
        super.onPause()
    }

    override fun onResume() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU && !secureAlways && !secureTemporary) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        super.onResume()
    }

    override fun onDestroy() {
        reader.shutdown()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                // El permiso de camara se pide aqui, una sola vez, antes de
                // crear el lector: el lector de QR lo volvia a pedir al volver
                // del dialogo (no marca que ya lo esta pidiendo).
                "cameraPermission" -> result.success(hasCamera())
                "requestCameraPermission" -> requestCamera(result)
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
                else -> result.notImplemented()
            }
        }
        channel = ch
    }

    private fun hasCamera(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestCamera(result: MethodChannel.Result) {
        if (hasCamera()) {
            result.success(true)
            return
        }
        if (cameraRequest != null) {
            // Ya hay un dialogo abierto: la respuesta llega con el suyo.
            result.success(false)
            return
        }
        cameraRequest = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.CAMERA),
            CAMERA_REQUEST
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CAMERA_REQUEST) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        cameraRequest?.success(granted)
        cameraRequest = null
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
        try {
            reader.execute {
                val bytes = readBytes(uri)
                mainHandler.post { deliver(bytes) }
            }
        } catch (e: Exception) {
            deliver(null)
        }
    }

    /**
     * Lee los bytes de [uri]. Si pasa del tope (un sobre mide 2 MiB como
     * maximo) corta en el acto y devuelve null; tambien ante cualquier error.
     */
    private fun readBytes(uri: Uri): ByteArray? {
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(16 * 1024)
                var total = 0
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    total += n
                    if (total > MAX_BYTES) return@use null
                    out.write(buffer, 0, n)
                }
                out.toByteArray()
            }
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        private const val CHANNEL = "com.dferrandizmont.regalos/incoming"
        private const val CAMERA_REQUEST = 7301
        private const val MAX_BYTES = 2 * 1024 * 1024 + 1024
    }
}
