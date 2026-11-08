package com.mox.app

import org.json.JSONObject

/**
 * What the phone needs to reach its owner's Supabase project
 * (shared/PROTOCOL.md §1). Comes from the pairing QR. The password is a
 * secret, so [SettingsStore] keeps it encrypted.
 */
data class MoxSettings(
    val projectUrl: String,
    val publishableKey: String,
    val email: String,
    val password: String
) {
    fun toJson(): String = JSONObject()
        .put("projectUrl", projectUrl)
        .put("publishableKey", publishableKey)
        .put("email", email)
        .put("password", password)
        .toString()

    companion object {
        fun fromJson(json: String): MoxSettings {
            val o = JSONObject(json)
            return MoxSettings(
                projectUrl = o.getString("projectUrl"),
                publishableKey = o.getString("publishableKey"),
                email = o.getString("email"),
                password = o.getString("password")
            )
        }
    }
}
