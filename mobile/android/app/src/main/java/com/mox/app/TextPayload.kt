package com.mox.app

/** Plain text sent through the slot (#101, PROTOCOL.md §6). */
object TextPayload {
    /** Texts stay small: they go to the clipboard, not to a folder. */
    const val MAX_BYTES = 1_000_000
    const val FILE_NAME = "Text.txt"
    const val MIME = "text/plain"

    /** The bytes to upload, or an error a person can act on. */
    fun encode(text: String): ByteArray {
        if (text.isBlank()) throw MoxException("There's no text to send.")
        val bytes = text.toByteArray(Charsets.UTF_8)
        if (bytes.size >
            MAX_BYTES
        ) {
            throw MoxException("That text is too long: Mox sends texts up to 1 MB.")
        }
        return bytes
    }

    fun decode(bytes: ByteArray): String = bytes.toString(Charsets.UTF_8)

    /** A short version for notifications. */
    fun preview(text: String, max: Int = 120): String {
        val oneLine = text.trim().replace(Regex("\\s+"), " ")
        return if (oneLine.length <= max) oneLine else oneLine.take(max - 1) + "…"
    }
}
