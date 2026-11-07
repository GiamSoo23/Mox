package com.mox.app

import android.os.Environment

/**
 * Where a received file is saved.
 *
 * Photos and videos go to the Camera folder, so they show up in the gallery
 * next to the user's own pictures. Everything else goes to Downloads.
 * Kept free of Android runtime calls so it can be unit-tested on the JVM.
 */
enum class SaveDestination(val label: String) {
    CAMERA_PHOTO("Camera"),
    CAMERA_VIDEO("Camera"),
    DOWNLOADS("Downloads")
    ;

    /** Value for MediaStore's RELATIVE_PATH column (Android 10+). */
    val relativePath: String
        get() = when (this) {
            CAMERA_PHOTO, CAMERA_VIDEO -> "${Environment.DIRECTORY_DCIM}/Camera"
            DOWNLOADS -> Environment.DIRECTORY_DOWNLOADS
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
