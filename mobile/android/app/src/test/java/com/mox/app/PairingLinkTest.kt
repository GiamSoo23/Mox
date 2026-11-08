package com.mox.app

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs PairingLink against shared/fixtures/pairing/, like the Mac and the pairing page do. */
class PairingLinkTest {
    @Test
    fun `parses every valid fixture exactly`() {
        val links = Fixtures.files("pairing/valid", "txt")
        assertTrue(links.size >= 6)
        for (file in links) {
            val expected =
                JSONObject(Fixtures.text(java.io.File(file.path.removeSuffix(".txt") + ".json")))
            val parsed = PairingLink.parse(Fixtures.text(file))
            assertEquals(file.name, expected.getString("projectUrl"), parsed.projectUrl)
            assertEquals(file.name, expected.getString("publishableKey"), parsed.publishableKey)
            assertEquals(file.name, expected.getString("email"), parsed.email)
            assertEquals(file.name, expected.getString("password"), parsed.password)
            val name = if (expected.isNull(
                    "desktopName"
                )
            ) {
                null
            } else {
                expected.getString("desktopName")
            }
            assertEquals(file.name, name, parsed.desktopName)
        }
    }

    @Test
    fun `refuses every invalid fixture`() {
        val links = Fixtures.files("pairing/invalid", "txt")
        assertTrue(links.size >= 12)
        for (file in links) {
            assertThrows(file.name, PairingException::class.java) {
                PairingLink.parse(Fixtures.text(file))
            }
        }
    }

    @Test
    fun `a secret key and a newer version get their own errors`() {
        val secret = assertThrows(PairingException::class.java) {
            PairingLink.parse(
                Fixtures.text(java.io.File(Fixtures.root, "pairing/invalid/secret-key.txt"))
            )
        }
        assertEquals(PairingException.Reason.SECRET_KEY, secret.reason)
        val future = assertThrows(PairingException::class.java) {
            PairingLink.parse(
                Fixtures.text(java.io.File(Fixtures.root, "pairing/invalid/future-version.txt"))
            )
        }
        assertEquals(PairingException.Reason.UNSUPPORTED_VERSION, future.reason)
    }

    @Test
    fun `percent-decoding keeps plus signs and refuses broken input`() {
        assertEquals("mox+desk@example.com", PairingLink.percentDecode("mox+desk%40example.com"))
        assertEquals("Gregory’s MacBook", PairingLink.percentDecode("Gregory%E2%80%99s%20MacBook"))
        assertThrows(PairingException::class.java) { PairingLink.percentDecode("%E0%A4%A") }
        assertThrows(PairingException::class.java) { PairingLink.percentDecode("%ZZ") }
        assertThrows(PairingException::class.java) { PairingLink.percentDecode("%FF") }
    }

    @Test
    fun `the pairing link becomes the settings to store`() {
        val link = PairingLink.parse(
            Fixtures.text(java.io.File(Fixtures.root, "pairing/valid/basic.txt"))
        )
        val settings = link.toSettings()
        assertEquals(link.projectUrl, settings.projectUrl)
        assertEquals(link.password, settings.password)
    }
}
