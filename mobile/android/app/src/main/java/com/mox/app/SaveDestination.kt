package com.mox.app

/**
 * Where a received file is saved.
 *
 * Photos and videos go to the Camera folder, so they show up in the gallery
 * next to the user's own pictures. Everything else goes to Downloads.
 * Free of Android calls (no Environment.DIRECTORY_* lookups, which are null
 * in JVM unit tests), so it's unit-tested on the JVM.
 */
enum class SaveDestination(val label: String) {
    CAMERA_PHOTO("Camera"),
    CAMERA_VIDEO("Camera"),
    DOWNLOADS("Downloads")
    ;

    /** Value for MediaStore's RELATIVE_PATH column (Android 10+). */
    val relativePath: String
        get() = when (this) {
            // Same values as Environment.DIRECTORY_DCIM and DIRECTORY_DOWNLOADS.
            CAMERA_PHOTO, CAMERA_VIDEO -> "DCIM/Camera"

            DOWNLOADS -> "Download"
        }

    companion object {
        fun forMimeType(mimeType: String?): SaveDestination = when {
            mimeType == null -> DOWNLOADS
            mimeType.startsWith("image/") -> CAMERA_PHOTO
            mimeType.startsWith("video/") -> CAMERA_VIDEO
            else -> DOWNLOADS
        }
    }
}
