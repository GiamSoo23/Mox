package com.mox.app

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundles (PROTOCOL.md §9) against shared/fixtures/bundles/, like the Mac. */
class BundlesTest {
    @Test
    fun `valid fixtures unpack to their files`() {
        val zips = Fixtures.files("bundles/valid", "zip")
        assertTrue(zips.isNotEmpty())
        for (zip in zips) {
            val json = JSONObject(zip.resolveSibling(zip.nameWithoutExtension + ".json").readText())
            val files = json.getJSONArray("files")
            val expected = List(files.length()) { files.getString(it) }
            assertEquals(zip.name, expected, Bundles.read(zip.readBytes()).map { it.path })
        }
    }

    @Test
    fun `invalid fixtures are refused`() {
        val zips = Fixtures.files("bundles/invalid", "zip")
        assertEquals(9, zips.size)
        for (zip in zips) {
            assertThrows(zip.name, Bundles.Refused::class.java) { Bundles.read(zip.readBytes()) }
        }
    }

    @Test
    fun `what Android writes reads back the same`() {
        val files = listOf(
            "IMG_0001.jpg" to ByteArray(300) { it.toByte() },
            "Fotos/año nuevo.txt" to "hola 👋".toByteArray()
        )
        val entries = Bundles.read(Bundles.write(files))
        assertEquals(files.map { it.first }, entries.map { it.path })
        assertEquals("hola 👋", String(entries[1].data))
        assertEquals("año nuevo.txt", entries[1].name)
    }

    @Test
    fun `the row name counts the files`() {
        assertEquals("Mox – 5 files.zip", Bundles.fileName(5))
    }
}
