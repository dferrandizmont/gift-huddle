package com.dferrandizmont.regalos

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.security.GeneralSecurityException
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

internal object PinKdf {
    fun register(messenger: BinaryMessenger): MethodChannel {
        val channel = MethodChannel(
            messenger,
            "com.dferrandizmont.regalos/pin_kdf",
            StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        )
        channel.setMethodCallHandler { call, result ->
            if (call.method != "derive") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val args = call.arguments as? Map<*, *>
            val pin = args?.get("pin") as? String
            val salt = args?.get("salt") as? ByteArray
            val rounds = args?.get("rounds") as? Int
            if (pin == null || pin.length !in 4..6 || pin.any { it !in '0'..'9' } ||
                salt == null || salt.isEmpty() || rounds == null || rounds <= 0
            ) {
                result.error("bad_args", null, null)
                return@setMethodCallHandler
            }
            try {
                result.success(derive(pin, salt, rounds))
            } catch (_: GeneralSecurityException) {
                result.error("pbkdf2_failed", null, null)
            }
        }
        return channel
    }

    fun derive(pin: String, salt: ByteArray, rounds: Int): ByteArray {
        val password = pin.toCharArray()
        val spec = PBEKeySpec(password, salt, rounds, 256)
        password.fill('\u0000')
        return try {
            SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
        } finally {
            spec.clearPassword()
        }
    }
}
