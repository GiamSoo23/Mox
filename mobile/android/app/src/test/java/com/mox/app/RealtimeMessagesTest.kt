package com.mox.app

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RealtimeMessagesTest {
    @Test
    fun `the websocket url uses wss and the publishable key`() {
        assertEquals(
            "wss://abcd.supabase.co/realtime/v1/websocket?apikey=sb_publishable_x&vsn=1.0.0",
            RealtimeMessages.websocketUrl("https://abcd.supabase.co/", "sb_publishable_x")
        )
    }

    @Test
    fun `joining asks for changes to the slot, with the token`() {
        val message = JSONObject(RealtimeMessages.join("jwt"))
        assertEquals(RealtimeMessages.TOPIC, message.getString("topic"))
        assertEquals("phx_join", message.getString("event"))
        val payload = message.getJSONObject("payload")
        assertEquals("jwt", payload.getString("access_token"))
        val change = payload.getJSONObject(
            "config"
        ).getJSONArray("postgres_changes").getJSONObject(0)
        assertEquals("mox", change.getString("schema"))
        assertEquals("current_file", change.getString("table"))
    }

    @Test
    fun `a heartbeat goes to the phoenix topic`() {
        val message = JSONObject(RealtimeMessages.heartbeat(7))
        assertEquals("phoenix", message.getString("topic"))
        assertEquals("heartbeat", message.getString("event"))
        assertEquals("7", message.getString("ref"))
    }

    @Test
    fun `only a change on our topic counts`() {
        val topic = RealtimeMessages.TOPIC
        assertTrue(
            RealtimeMessages.isChange(
                """{"topic":"$topic","event":"postgres_changes","payload":{}}"""
            )
        )
        assertFalse(
            RealtimeMessages.isChange("""{"topic":"$topic","event":"phx_reply","payload":{}}""")
        )
        assertFalse(RealtimeMessages.isChange("""{"topic":"other","event":"postgres_changes"}"""))
        assertFalse(RealtimeMessages.isChange("not json"))
    }
}
