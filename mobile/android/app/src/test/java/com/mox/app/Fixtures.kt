package com.mox.app

import java.io.File

/** The shared fixtures in shared/fixtures/ (path set by Gradle: mox.fixtures). */
object Fixtures {
    val root: File =
        File(requireNotNull(System.getProperty("mox.fixtures")) { "mox.fixtures not set" })

    fun files(folder: String, ext: String): List<File> =
        File(root, folder).listFiles { f -> f.extension == ext }.orEmpty().sortedBy { it.name }

    fun text(file: File): String = file.readText().trim()
}
