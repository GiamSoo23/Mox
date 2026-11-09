package com.mox.app

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * The few Supabase Realtime messages Mox needs (shared/PROTOCOL.md §4.7).
 * An event only means "the slot changed": the row is always read again, so
 * nothing here depends on what the event carries.
 */
object RealtimeMessages {
    const val TOPIC = "realtime:mox-current-file"

    fun websocketUrl(projectUrl: String, publishableKey: String): String =
        projectUrl.trimEnd('/').replaceFirst("https://", "wss://") +
            "/realtime/v1/websocket?apikey=$publishableKey&vsn=1.0.0"

    fun join(accessToken: String): String {
        val change = JSONObject()
            .put("event", "*")
            .put("schema", "mox")
            .put("table", "current_file")
        val config = JSONObject()
            .put("broadcast", JSONObject().put("ack", false).put("self", false))
            .put("presence", JSONObject().put("key", ""))
            .put("postgres_changes", JSONArray().put(change))
            .put("private", false)
        val payload = JSONObject().put("config", config).put("access_token", accessToken)
        return JSONObject()
            .put("topic", TOPIC)
            .put("event", "phx_join")
            .put("payload", payload)
            .put("ref", "1")
            .put("join_ref", "1")
            .toString()
    }

    fun heartbeat(ref: Int): String = JSONObject()
        .put("topic", "phoenix")
        .put("event", "heartbeat")
        .put("payload", JSONObject())
        .put("ref", ref.toString())
        .toString()

    /** True when [text] says the slot changed. Anything malformed is ignored. */
    fun isChange(text: String): Boolean = try {
        val message = JSONObject(text)
        message.optString("topic") == TOPIC && message.optString("event") == "postgres_changes"
    } catch (_: JSONException) {
        false
    }
}
