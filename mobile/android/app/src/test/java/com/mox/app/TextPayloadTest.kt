package com.mox.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class TextPayloadTest {
    @Test
    fun `text survives the round trip, accents and emoji included`() {
        val text = "Hola, ¿qué tal? 👋\nSecond line"
        assertEquals(text, TextPayload.decode(TextPayload.encode(text)))
    }

    @Test
    fun `blank text is refused`() {
        assertThrows(MoxException::class.java) { TextPayload.encode("  \n ") }
    }

    @Test
    fun `text over 1 MB is refused`() {
        assertThrows(MoxException::class.java) {
            TextPayload.encode("a".repeat(TextPayload.MAX_BYTES + 1))
        }
    }

    @Test
    fun `the preview is one short line`() {
        assertEquals("a b c", TextPayload.preview("  a\n b\t\tc "))
        assertEquals(10, TextPayload.preview("x".repeat(50), max = 10).length)
    }
}
