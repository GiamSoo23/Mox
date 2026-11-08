package com.mox.app

import org.json.JSONObject

/**
 * The single row of mox.current_file: the file in the slot right now
 * (shared/PROTOCOL.md §5). Unknown columns are ignored, so newer schemas
 * don't break the app.
 */
data class CurrentFile(
    val id: Int,
    val originalName: String,
    val mimeType: String?,
    val sizeBytes: Long,
    val kind: String,
    val itemCount: Int,
    val sourcePlatform: String,
    val sourceDeviceId: String,
    val uploadedAt: String
) {
    /**
     * Checks the rules of §5. The database enforces them too; this lets the
     * app refuse a bad row with a clear message.
     */
    fun validate() {
        if (id != 1) invalid("id must be 1")
        if (originalName.codePointCount(0, originalName.length) !in 1..255) {
            invalid("the file name must be 1–255 characters")
        }
        if (sizeBytes !in 1..MAX_SIZE) invalid("the size must be between 1 byte and 50 MB")
        val itemsOk = (kind == "file" && itemCount == 1) || (kind == "bundle" && itemCount >= 2)
        if (!itemsOk) invalid("kind $kind can't have $itemCount items")
        if (sourcePlatform !in PLATFORMS) invalid("unknown platform $sourcePlatform")
        if (!UUID_PATTERN.matches(sourceDeviceId)) invalid("the device id isn't a UUID")
    }

    /** "Mac", "Windows", "Android" or "iPhone", for notifications. */
    val sourceName: String
        get() = when (sourcePlatform) {
            "macos" -> "Mac"
            "windows" -> "Windows"
            "android" -> "Android"
            "ios" -> "iPhone"
            else -> sourcePlatform
        }

    companion object {
        const val MAX_SIZE = 52_428_800L
        val PLATFORMS = setOf("macos", "windows", "android", "ios")
        private val UUID_PATTERN = Regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$")

        /** Reads a row as PostgREST returns it. Missing required fields throw. */
        fun fromJson(o: JSONObject) = CurrentFile(
            id = o.getInt("id"),
            originalName = o.getString("original_name"),
            mimeType = o.stringOrNull("mime_type"),
            sizeBytes = o.getLong("size_bytes"),
            kind = o.getString("kind"),
            itemCount = o.getInt("item_count"),
            sourcePlatform = o.getString("source_platform"),
            sourceDeviceId = o.getString("source_device_id"),
            uploadedAt = o.getString("uploaded_at")
        )

        private fun invalid(reason: String): Nothing = throw InvalidRowException(reason)
    }
}

/** The row in the project breaks a protocol rule. */
class InvalidRowException(reason: String) :
    Exception("The current file in your project isn't valid: $reason.")
