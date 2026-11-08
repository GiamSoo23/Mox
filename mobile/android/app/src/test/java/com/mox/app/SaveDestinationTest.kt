package com.mox.app

import org.junit.Assert.assertEquals
import org.junit.Test

class SaveDestinationTest {
    @Test
    fun `photos and screenshots go to the Camera folder`() {
        for (mime in listOf("image/jpeg", "image/png", "image/heic", "image/webp")) {
            assertEquals(mime, SaveDestination.CAMERA_PHOTO, SaveDestination.forMimeType(mime))
        }
    }

    @Test
    fun `videos go to the Camera folder`() {
        assertEquals(SaveDestination.CAMERA_VIDEO, SaveDestination.forMimeType("video/mp4"))
        assertEquals(SaveDestination.CAMERA_VIDEO, SaveDestination.forMimeType("video/quicktime"))
    }

    @Test
    fun `everything else goes to Downloads`() {
        for (mime in listOf("application/pdf", "application/zip", "text/plain", "audio/mpeg")) {
            assertEquals(mime, SaveDestination.DOWNLOADS, SaveDestination.forMimeType(mime))
        }
    }

    @Test
    fun `an unknown MIME type goes to Downloads`() {
        assertEquals(SaveDestination.DOWNLOADS, SaveDestination.forMimeType(null))
    }

    @Test
    fun `relative paths match the shared folders`() {
        assertEquals("DCIM/Camera", SaveDestination.CAMERA_PHOTO.relativePath)
        assertEquals("DCIM/Camera", SaveDestination.CAMERA_VIDEO.relativePath)
        assertEquals("Download", SaveDestination.DOWNLOADS.relativePath)
    }

    @Test
    fun `labels are what the notification shows`() {
        assertEquals("Camera", SaveDestination.CAMERA_PHOTO.label)
        assertEquals("Downloads", SaveDestination.DOWNLOADS.label)
    }
}
