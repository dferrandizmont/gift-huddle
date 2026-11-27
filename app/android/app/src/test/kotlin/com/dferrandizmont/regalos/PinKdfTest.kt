package com.dferrandizmont.regalos

import java.util.HexFormat
import org.junit.Assert.assertArrayEquals
import org.junit.Test

class PinKdfTest {
    @Test
    fun matchesTheStoredPinVector() {
        val hex = HexFormat.of()
        val salt = hex.parseHex("ff0080017f00ffee")
        val expected = hex.parseHex("fe0f3887a197fb0450990cc6c1818d1a8758b5c8ec4f84f519fcea035b541b28")
        assertArrayEquals(expected, PinKdf.derive("000042", salt, 200_000))
    }
}
