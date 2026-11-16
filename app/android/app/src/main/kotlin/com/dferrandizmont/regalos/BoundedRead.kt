package com.dferrandizmont.regalos

import java.io.ByteArrayOutputStream
import java.io.InputStream

/**
 * Lecturas acotadas de ficheros que llegan de fuera, sin Android para poder
 * probarlas en la JVM (ADR 0008).
 */
object BoundedRead {
    /** Un sobre mide 2 MiB como máximo (más un margen). */
    const val MAX_ENVELOPE_BYTES = 2 * 1024 * 1024 + 1024

    /** Un fichero de recuperación (GHK) mide 512 bytes como máximo. */
    const val MAX_RECOVERY_BYTES = 512

    private val GHK = byteArrayOf(0x47, 0x48, 0x4B)

    /** El fichero pasa del tope: no se ha leído entero. */
    class TooLargeException : Exception()

    /**
     * Un fichero abierto o compartido con la app. Mira primero la magia: un
     * fichero de recuperación se corta en [MAX_RECOVERY_BYTES] + 1 bytes (se
     * pasan así a Flutter, que lo rechaza por grande) sin leer el resto; el
     * resto, hasta [MAX_ENVELOPE_BYTES] o null si pasa.
     */
    fun incoming(input: InputStream): ByteArray? {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(16 * 1024)
        var total = 0
        var limit = MAX_ENVELOPE_BYTES
        var sniffed = false
        while (true) {
            val want = if (!sniffed) GHK.size - total else minOf(buffer.size, limit + 1 - total)
            val n = input.read(buffer, 0, want)
            if (n < 0) break
            out.write(buffer, 0, n)
            total += n
            if (!sniffed && total >= GHK.size) {
                sniffed = true
                val head = out.toByteArray()
                if (head[0] == GHK[0] && head[1] == GHK[1] && head[2] == GHK[2]) {
                    limit = MAX_RECOVERY_BYTES
                }
            }
            if (total > limit) {
                return if (limit == MAX_RECOVERY_BYTES) out.toByteArray() else null
            }
        }
        return out.toByteArray()
    }

    /**
     * Lee [input] entero solo si mide como mucho [max] bytes; nunca lee más
     * de [max] + 1. Lanza [TooLargeException] si pasa.
     */
    fun exact(input: InputStream, max: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(1024)
        var total = 0
        while (true) {
            val n = input.read(buffer, 0, minOf(buffer.size, max + 1 - total))
            if (n < 0) break
            total += n
            if (total > max) throw TooLargeException()
            out.write(buffer, 0, n)
        }
        return out.toByteArray()
    }
}

/**
 * Qué hacer con el resultado del selector del sistema (ADR 0008). Una
 * petición se resuelve una sola vez; si la Activity se recreó (o el proceso
 * murió) mientras estaba abierto, Flutter ya no espera nada: no se escribe ni
 * se entrega nada, y un documento creado vacío se borra.
 */
object PickerOutcome {
    const val CREATE = "create"
    const val OPEN = "open"

    enum class Action { CANCELLED, PROCESS, DELETE_ORPHAN, IGNORE_ORPHAN }

    /**
     * [hasRequest]: hay una petición viva de Flutter. [orphanKind]: la que se
     * guardó al recrear la Activity ([CREATE] u [OPEN]), o null.
     */
    fun decide(hasRequest: Boolean, orphanKind: String?, ok: Boolean, hasUri: Boolean): Action =
        when {
            hasRequest && ok && hasUri -> Action.PROCESS
            hasRequest -> Action.CANCELLED
            orphanKind == CREATE && ok && hasUri -> Action.DELETE_ORPHAN
            else -> Action.IGNORE_ORPHAN
        }
}

/**
 * Lecturas de ficheros que llegan por intents: una a la vez y una sola
 * entrega por lectura (el resultado o el tope de tiempo, lo que llegue
 * antes). Se usa solo desde el hilo principal.
 */
class IncomingReadGate {
    private var current = 0L
    private var busy = false

    /** Empieza una lectura; null si ya hay una pendiente (se entrega null). */
    fun begin(): Long? {
        if (busy) return null
        busy = true
        return ++current
    }

    /** Termina la lectura [token]; true solo la primera vez y si es la vigente. */
    fun end(token: Long): Boolean {
        if (!busy || token != current) return false
        busy = false
        return true
    }
}

/**
 * El stream de una lectura entrante, compartido entre el hilo que lee y el
 * tope de tiempo. Si el tope vence antes de que `openInputStream` devuelva
 * el stream, al publicarlo se cierra sin leer: un proveedor lento nunca
 * ocupa un hilo después de su cancelación.
 */
class CancellableStream<T : java.io.Closeable> {
    private object Empty
    private object Cancelled

    private val state = java.util.concurrent.atomic.AtomicReference<Any?>(Empty)

    /** Publica [value] para leerlo; si ya se canceló, lo cierra y da false. */
    fun publish(value: T): Boolean {
        if (state.compareAndSet(Empty, value)) return true
        try {
            value.close()
        } catch (e: Exception) {
            // Ya cerrado.
        }
        return false
    }

    /** La lectura terminó: suelta [value] (si no se canceló entretanto). */
    fun release(value: T) {
        state.compareAndSet(value, Empty)
    }

    /**
     * Cancela: lo que se publique después se cierra sin leer. Devuelve el
     * stream ya publicado, para cerrarlo fuera del hilo principal, o null.
     */
    @Suppress("UNCHECKED_CAST")
    fun cancel(): T? {
        val old = state.getAndSet(Cancelled)
        return if (old === Empty || old === Cancelled) null else old as T
    }
}
