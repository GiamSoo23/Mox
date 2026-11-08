package com.mox.app

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The v1 row as PostgREST returns it. v2 rows are covered by the shared fixtures (#12). */
class CurrentFileTest {
    private val row = """
        {
          "id": 1,
          "storage_path": "current.jpg",
          "original_name": "IMG_0001.jpg",
          "mime_type": "image/jpeg",
          "size_bytes": 2048,
          "uploaded_from": "mac",
          "uploaded_at": "2026-11-08T03:48:08.315078+00:00"
        }
    """.trimIndent()

    @Test
    fun `parses every field of a v1 row`() {
        val file = CurrentFile.fromJson(JSONObject(row))
        assertEquals("current.jpg", file.storagePath)
        assertEquals("IMG_0001.jpg", file.originalName)
        assertEquals("image/jpeg", file.mimeType)
        assertEquals(2048L, file.sizeBytes)
        assertEquals("mac", file.uploadedFrom)
        assertEquals("2026-11-08T03:48:08.315078+00:00", file.uploadedAt)
    }

    @Test
    fun `a null mime_type is null, not the string "null" (#56)`() {
        val json = JSONObject(row).put("mime_type", JSONObject.NULL)
        assertNull(CurrentFile.fromJson(json).mimeType)
    }

    @Test
    fun `a missing or empty mime_type is null`() {
        assertNull(CurrentFile.fromJson(JSONObject(row).apply { remove("mime_type") }).mimeType)
        assertNull(CurrentFile.fromJson(JSONObject(row).put("mime_type", "")).mimeType)
    }
}
