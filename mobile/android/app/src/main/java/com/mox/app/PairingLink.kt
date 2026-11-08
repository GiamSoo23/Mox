package com.mox.app

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

/**
 * A pairing link (shared/PROTOCOL.md §8): what the desktop's QR code carries.
 * Pure Kotlin, unit-tested against shared/fixtures/pairing/, the same files
 * the Mac and the pairing page test against.
 */
data class PairingLink(
    val projectUrl: String,
    val publishableKey: String,
    val email: String,
    val password: String,
    val desktopName: String?
) {
    fun toSettings() = MoxSettings(projectUrl, publishableKey, email, password)

    companion object {
        const val SUPPORTED_VERSION = "1"
        private const val HANDOFF_PREFIX = "mox://pair?"
        private val REQUIRED = listOf("v", "u", "k", "e", "p")
        private val PROJECT_URL = Regex("^https://[A-Za-z0-9.-]+(:\\d+)?$")

        /** Parses either form: the https pairing link or the mox://pair? hand-off. */
        fun parse(link: String): PairingLink = validated(decode(rawParameters(link)))

        internal fun rawParameters(link: String): String {
            val text = link.trim()
            val raw = when {
                text.startsWith(HANDOFF_PREFIX) -> text.removePrefix(HANDOFF_PREFIX)
                text.contains('#') -> text.substringAfter('#')
                else -> fail(PairingException.Reason.NO_PARAMETERS)
            }
            if (raw.isEmpty()) fail(PairingException.Reason.NO_PARAMETERS)
            return raw
        }

        internal fun decode(raw: String): Map<String, String> {
            val params = LinkedHashMap<String, String>()
            for (part in raw.split('&')) {
                if (part.isEmpty()) continue
                val key = part.substringBefore('=')
                val value = if ('=' in part) part.substringAfter('=') else ""
                if (key in params) fail(PairingException.Reason.DUPLICATE_KEY, key)
                params[key] = percentDecode(value)
            }
            return params
        }

        /**
         * Percent-decodes UTF-8 and never turns '+' into a space (§8.2).
         * java.net.URLDecoder does, which would break emails like
         * mox+desk@example.com, so it isn't used here.
         */
        internal fun percentDecode(value: String): String {
            val bytes = ByteArrayOutputStream()
            var i = 0
            while (i < value.length) {
                if (value[i] == '%') {
                    val byte = value.substring(i + 1, minOf(i + 3, value.length))
                        .takeIf { it.length == 2 }?.toIntOrNull(16)
                        ?: fail(PairingException.Reason.BAD_ENCODING)
                    bytes.write(byte)
                    i += 3
                } else {
                    val codePoint = value.codePointAt(i)
                    bytes.write(String(Character.toChars(codePoint)).toByteArray(Charsets.UTF_8))
                    i += Character.charCount(codePoint)
                }
            }
            return try {
                Charsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes.toByteArray()))
                    .toString()
            } catch (e: CharacterCodingException) {
                fail(PairingException.Reason.BAD_ENCODING)
            }
        }

        private fun validated(params: Map<String, String>): PairingLink {
            for (key in REQUIRED) {
                if (params[key].isNullOrEmpty()) fail(PairingException.Reason.MISSING, key)
            }
            if (params["v"] != SUPPORTED_VERSION) fail(PairingException.Reason.UNSUPPORTED_VERSION)

            val projectUrl = params.getValue("u").removeSuffix("/")
            if (!PROJECT_URL.matches(projectUrl)) fail(PairingException.Reason.BAD_PROJECT_URL)

            val key = params.getValue("k")
            // A secret key must never be accepted or stored on a phone.
            if (key.startsWith("sb_secret_")) fail(PairingException.Reason.SECRET_KEY)
            if (!key.startsWith("sb_publishable_")) fail(PairingException.Reason.BAD_KEY)

            val email = params.getValue("e")
            if (email.split('@').size != 2 ||
                email.length > 254
            ) {
                fail(PairingException.Reason.BAD_EMAIL)
            }

            val password = params.getValue("p")
            if (password.length !in 16..128) fail(PairingException.Reason.BAD_PASSWORD)

            val name = params["n"]?.takeIf { it.isNotEmpty() }
            if (name != null && name.codePointCount(0, name.length) > 64) {
                fail(PairingException.Reason.NAME_TOO_LONG)
            }
            return PairingLink(projectUrl, key, email, password, name)
        }

        private fun fail(reason: PairingException.Reason, detail: String? = null): Nothing =
            throw PairingException(reason, detail)
    }
}

/** A pairing link that can't be used. [message] is written for people. */
class PairingException(val reason: Reason, detail: String? = null) :
    Exception(reason.message + (detail?.let { " ($it)" } ?: "")) {
    enum class Reason(val message: String) {
        NO_PARAMETERS("This pairing link is incomplete. Scan the QR code again."),
        BAD_ENCODING("This pairing link is damaged. Scan the QR code again."),
        DUPLICATE_KEY("This pairing link repeats a value."),
        MISSING("This pairing link is incomplete. Scan the QR code again."),
        UNSUPPORTED_VERSION(
            "This link needs a newer version of Mox. Update the app and scan again."
        ),
        BAD_PROJECT_URL("The project address in this link isn't valid."),
        SECRET_KEY("This link contains a secret key, which must never be shared."),
        BAD_KEY("This link doesn't contain a publishable key."),
        BAD_EMAIL("The Mox user in this link isn't valid."),
        BAD_PASSWORD("The Mox user's password in this link isn't valid."),
        NAME_TOO_LONG("The computer name in this link is too long.")
    }
}
