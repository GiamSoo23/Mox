package com.mox.app

import org.junit.Assert.assertEquals
import org.junit.Test

class MoxSettingsTest {
    @Test
    fun `settings survive the JSON that gets encrypted`() {
        val settings = MoxSettings(
            projectUrl = "https://abcdefghijklmnopqrst.supabase.co",
            publishableKey = "sb_publishable_EXAMPLEKEYexamplekey_1234",
            email = "mox+desk@mox.invalid",
            password = "correct-horse-battery-staple-42"
        )
        assertEquals(settings, MoxSettings.fromJson(settings.toJson()))
    }
}
