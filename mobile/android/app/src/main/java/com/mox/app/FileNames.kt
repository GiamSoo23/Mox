package com.mox.app

import java.util.Locale

/** Pure helpers for file names and sizes. No Android calls, so they're unit-tested on the JVM. */
object FileNames {
    private val unsafeCharacters = Regex("[^A-Za-z0-9._-]")

    /**
     * Makes a name safe to write to shared storage by replacing anything
     * other than ASCII letters, digits, '.', '_' and '-' with '_'.
     */
    fun sanitize(name: String): String = name.replace(unsafeCharacters, "_")
}

/**
 * A human-readable size: "512 B", "1.5 KB", "3.2 MB". Uses one decimal and
 * the device's locale (so "1,5 KB" in Spanish).
 */
fun humanBytes(bytes: Long, locale: Locale = Locale.getDefault()): String {
    if (bytes < 1024) return "$bytes B"
    val units = listOf("KB", "MB", "GB")
    var value = bytes.toDouble() / 1024.0
    var unit = 0
    while (value >= 1024 && unit < units.lastIndex) {
        value /= 1024.0
        unit++
    }
    return String.format(locale, "%.1f %s", value, units[unit])
}
