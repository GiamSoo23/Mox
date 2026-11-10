package com.mox.app

import android.content.ContentResolver
import android.net.Uri
import java.io.File
import java.io.OutputStream
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.Headers.Companion.toHeaders
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.BufferedSink
import okio.source
import org.json.JSONArray
import org.json.JSONObject

/**
 * The string at [key], or null when it's missing, JSON null or empty.
 * Uses isNull rather than optString: on Android, optString turns JSON null
 * into the string "null" (#56).
 */
internal fun JSONObject.stringOrNull(key: String): String? =
    if (isNull(key)) null else getString(key).ifEmpty { null }

/**
 * Speaks the Mox protocol v2 (shared/PROTOCOL.md) to the owner's Supabase
 * project: Auth, PostgREST (schema `mox`) and Storage. No SDK, just OkHttp
 * and org.json, so the APK stays small.
 */
class SupabaseRepo(private val settings: MoxSettings, private val deviceId: String) : MoxBackend {
    private val baseUrl = settings.projectUrl.trimEnd('/')
    private val bucket = "mox"

    /** v2 always stores the file under this name (#34). */
    private val objectName = "current"
    private val json = "application/json".toMediaType()
    private val client = OkHttpClient.Builder()
        .callTimeout(10, TimeUnit.MINUTES)
        .readTimeout(2, TimeUnit.MINUTES)
        .writeTimeout(10, TimeUnit.MINUTES)
        .build()

    /** No read or call limit; pings notice a connection that died silently. */
    private val realtimeClient = client.newBuilder()
        .callTimeout(0, TimeUnit.MILLISECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .pingInterval(30, TimeUnit.SECONDS)
        .build()

    private val tokenLock = Mutex()
    private var token: String? = null
    private var tokenExpiresAtMs = 0L

    override suspend fun checkSchema() = withContext(Dispatchers.IO) {
        val rows = JSONArray(send { restGet("meta?select=schema_version", it) })
        if (rows.length() == 0) {
            throw MoxException(
                "This code is out of date. On your computer, open Mox, choose Set Up Again, " +
                    "and scan the new code."
            )
        }
        val version = rows.getJSONObject(0).getInt("schema_version")
        if (version !=
            2
        ) {
            throw MoxException("Your project has Mox schema v$version, but this app needs v2.")
        }
    }

    override suspend fun fetchCurrent(): CurrentFile? = withContext(Dispatchers.IO) {
        val rows = JSONArray(send { restGet("current_file?id=eq.1&select=*", it) })
        if (rows.length() ==
            0
        ) {
            null
        } else {
            CurrentFile.fromJson(rows.getJSONObject(0)).also { it.validate() }
        }
    }

    override suspend fun uploadFromContentUri(
        resolver: ContentResolver,
        uri: Uri,
        displayName: String,
        sizeBytes: Long,
        mime: String?
    ): CurrentFile = withContext(Dispatchers.IO) {
        if (sizeBytes <= 0) throw MoxException("The file is empty.")
        if (sizeBytes > CurrentFile.MAX_SIZE) {
            throw MoxException("${humanBytes(sizeBytes)} is too big: Mox sends files up to 50 MB.")
        }
        val effectiveMime = mime ?: "application/octet-stream"
        // Streams from the content URI, so a 50 MB file never sits in memory.
        val body = object : RequestBody() {
            override fun contentType() = effectiveMime.toMediaType()
            override fun contentLength() = sizeBytes
            override fun writeTo(sink: BufferedSink) {
                requireNotNull(resolver.openInputStream(uri)) { "Can't read the shared file." }
                    .use { sink.writeAll(it.source()) }
            }
        }
        // §4.3 then §4.4: bytes first, so other devices never see a row
        // pointing at a file that isn't there yet.
        send { token ->
            Request.Builder()
                .url("$baseUrl/storage/v1/object/$bucket/$objectName")
                .headers(authHeaders(token, "x-upsert" to "true"))
                .post(body)
                .build()
        }
        replaceRow(displayName, effectiveMime, sizeBytes, kind = "file")
    }

    override suspend fun uploadText(text: String): CurrentFile = withContext(Dispatchers.IO) {
        val bytes = TextPayload.encode(text)
        send { token ->
            Request.Builder()
                .url("$baseUrl/storage/v1/object/$bucket/$objectName")
                .headers(authHeaders(token, "x-upsert" to "true"))
                .post(bytes.toRequestBody(TextPayload.MIME.toMediaType()))
                .build()
        }
        replaceRow(TextPayload.FILE_NAME, TextPayload.MIME, bytes.size.toLong(), kind = "text")
    }

    /** §4.4: makes the uploaded bytes the current item. */
    private suspend fun replaceRow(
        name: String,
        mime: String,
        size: Long,
        kind: String
    ): CurrentFile {
        val row = JSONObject()
            .put("id", 1)
            .put("original_name", name)
            .put("mime_type", mime)
            .put("size_bytes", size)
            .put("kind", kind)
            .put("item_count", 1)
            .put("source_platform", "android")
            .put("source_device_id", deviceId)
        val written = send { token ->
            Request.Builder()
                .url("$baseUrl/rest/v1/current_file?on_conflict=id")
                .headers(
                    authHeaders(
                        token,
                        "Content-Profile" to "mox",
                        "Prefer" to "resolution=merge-duplicates,return=representation"
                    )
                )
                .post(row.toString().toRequestBody(json))
                .build()
        }
        return CurrentFile.fromJson(JSONArray(written).getJSONObject(0))
    }

    override suspend fun signedDownloadUrl(expiresIn: Int): String = withContext(Dispatchers.IO) {
        val reply = send { token ->
            Request.Builder()
                .url("$baseUrl/storage/v1/object/sign/$bucket/$objectName")
                .headers(authHeaders(token))
                .post(JSONObject().put("expiresIn", expiresIn).toString().toRequestBody(json))
                .build()
        }
        // signedURL is relative: prefix it with /storage/v1.
        "$baseUrl/storage/v1${JSONObject(reply).getString("signedURL")}"
    }

    override suspend fun downloadTo(file: File) {
        withContext(Dispatchers.IO) { file.outputStream().use { downloadToStream(it) } }
    }

    override suspend fun downloadToStream(out: OutputStream) {
        withContext(Dispatchers.IO) {
            val request = Request.Builder().url(signedDownloadUrl()).get().build()
            client.newCall(request).execute().use { resp ->
                if (!resp.isSuccessful) throw MoxException("Download failed: HTTP ${resp.code}")
                requireNotNull(resp.body).byteStream().copyTo(out)
            }
        }
    }

    // ---- Realtime (§4.7) ------------------------------------------------

    /** What one Realtime connection needs. */
    data class RealtimeSession(val url: String, val token: String, val validForMs: Long)

    suspend fun realtimeSession(): RealtimeSession = withContext(Dispatchers.IO) {
        val current = accessToken(renew = false)
        RealtimeSession(
            RealtimeMessages.websocketUrl(baseUrl, settings.publishableKey),
            current,
            tokenExpiresAtMs - System.currentTimeMillis()
        )
    }

    fun openRealtime(session: RealtimeSession, listener: WebSocketListener): WebSocket =
        realtimeClient.newWebSocket(Request.Builder().url(session.url).build(), listener)

    // ---- Auth (§2) -----------------------------------------------------

    /** Runs a request with a valid token. On 401, signs in again and retries once. */
    private suspend fun send(build: (String) -> Request): String {
        for (attempt in 0..1) {
            val request = build(accessToken(renew = attempt > 0))
            client.newCall(request).execute().use { resp ->
                if (resp.code == 401 && attempt == 0) return@use
                val body = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) {
                    throw MoxException(
                        "Supabase answered HTTP ${resp.code}: ${body.take(200)}"
                    )
                }
                return body
            }
        }
        throw MoxException(
            "This phone's pairing is out of date. On your computer, open Mox, choose Pair a Phone, and scan the code."
        )
    }

    private suspend fun accessToken(renew: Boolean): String = tokenLock.withLock {
        val now = System.currentTimeMillis()
        token?.takeIf { !renew && tokenExpiresAtMs - now > 60_000 }?.let { return it }
        val (fresh, lifetimeSeconds) = signIn()
        token = fresh
        tokenExpiresAtMs = now + lifetimeSeconds * 1000
        fresh
    }

    /** Signs in as the Mox user. Each device keeps its own session. */
    private fun signIn(): Pair<String, Long> {
        val body = JSONObject().put("email", settings.email).put("password", settings.password)
        val request = Request.Builder()
            .url("$baseUrl/auth/v1/token?grant_type=password")
            .header("apikey", settings.publishableKey)
            .post(body.toString().toRequestBody(json))
            .build()
        client.newCall(request).execute().use { resp ->
            if (!resp.isSuccessful) {
                throw MoxException(
                    "This phone's pairing is out of date. On your computer, open Mox, choose Pair a Phone, and scan the code."
                )
            }
            val reply = JSONObject(resp.body?.string().orEmpty())
            return reply.getString("access_token") to reply.getLong("expires_in")
        }
    }

    // ---- Requests (§3) ---------------------------------------------------

    private fun restGet(pathAndQuery: String, token: String): Request = Request.Builder()
        .url("$baseUrl/rest/v1/$pathAndQuery")
        .headers(authHeaders(token, "Accept-Profile" to "mox"))
        .get()
        .build()

    private fun authHeaders(token: String, vararg extra: Pair<String, String>) = (
        mapOf(
            "apikey" to settings.publishableKey,
            "Authorization" to "Bearer $token"
        ) + extra
        ).toHeaders()
}
