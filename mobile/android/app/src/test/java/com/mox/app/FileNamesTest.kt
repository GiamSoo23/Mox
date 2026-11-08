package com.mox.app

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

class FileNamesTest {
    @Test
    fun `safe names are left alone`() {
        assertEquals("IMG_0001.jpg", FileNames.sanitize("IMG_0001.jpg"))
        assertEquals("report-v2.final.pdf", FileNames.sanitize("report-v2.final.pdf"))
    }

    @Test
    fun `spaces and punctuation become underscores`() {
        assertEquals(
            "Screenshot_2026-11-07_at_14.32.10.png",
            FileNames.sanitize("Screenshot 2026-11-07 at 14.32.10.png")
        )
    }

    @Test
    fun `path separators can't escape the folder`() {
        assertEquals(".._.._etc_passwd", FileNames.sanitize("../../etc/passwd"))
    }

    @Test
    fun `non-ASCII letters are replaced`() {
        assertEquals("Bandera_de_Espa_a.jpeg", FileNames.sanitize("Bandera de España.jpeg"))
    }

    @Test
    fun `sizes under 1 KB are shown in bytes`() {
        assertEquals("0 B", humanBytes(0))
        assertEquals("1023 B", humanBytes(1023))
    }

    @Test
    fun `larger sizes use one decimal and the right unit`() {
        assertEquals("1.0 KB", humanBytes(1024, Locale.US))
        assertEquals("1.5 MB", humanBytes(1_572_864, Locale.US))
        assertEquals("50.0 MB", humanBytes(52_428_800, Locale.US))
        assertEquals("2.0 GB", humanBytes(2L * 1024 * 1024 * 1024, Locale.US))
    }

    @Test
    fun `the decimal separator follows the locale`() {
        assertEquals("1,5 MB", humanBytes(1_572_864, Locale.forLanguageTag("es-ES")))
    }
}
