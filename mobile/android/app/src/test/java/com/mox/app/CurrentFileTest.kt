package com.mox.app

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** v2 rows against shared/fixtures/rows/, the same files CI inserts into the real schema. */
class CurrentFileTest {
    private fun row(name: String) = JSONObject(Fixtures.text(java.io.File(Fixtures.root, name)))

    @Test
    fun `every valid row fixture parses and validates`() {
        val files = Fixtures.files("rows/valid", "json")
        assertTrue(files.size >= 4)
        for (file in files) CurrentFile.fromJson(JSONObject(Fixtures.text(file))).validate()
    }

    @Test
    fun `every invalid row fixture is refused`() {
        val files = Fixtures.files("rows/invalid", "json")
        assertTrue(files.size >= 11)
        for (file in files) {
            try {
                // Either it doesn't parse (missing device id) or validate() refuses it.
                CurrentFile.fromJson(JSONObject(Fixtures.text(file))).validate()
                fail("${file.name} was accepted")
            } catch (expected: Exception) {
                // refused, as it should be
            }
        }
    }

    @Test
    fun `fields of a valid row`() {
        val file = CurrentFile.fromJson(row("rows/valid/bundle-from-android.json"))
        assertEquals("bundle", file.kind)
        assertEquals(5, file.itemCount)
        assertEquals("Android", file.sourceName)
        assertEquals("a2b3c4d5-e6f7-4a8b-9c0d-1e2f3a4b5c6d", file.sourceDeviceId)
    }

    @Test
    fun `a null mime_type is null, not the string null (#56)`() {
        assertNull(CurrentFile.fromJson(row("rows/valid/no-mime-type.json")).mimeType)
    }
}
