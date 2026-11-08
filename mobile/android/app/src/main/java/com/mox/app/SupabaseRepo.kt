package com.mox.app

import android.content.ContentResolver
import android.net.Uri
import android.webkit.MimeTypeMap
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Headers.Companion.toHeaders
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okio.BufferedSink
import okio.source
import org.json.JSONArray
import org.json.JSONObject

data class CurrentFile(
    val storagePath: String,
    val originalName: String,
    val mimeType: String?,
    val sizeBytes: Long,
    val uploadedFrom: String,
    val uploadedAt: String
) {
    companion object {
        fun fromJson(o: JSONObject) = CurrentFile(
            storagePath = o.getString("storage_path"),
            originalName = o.getString("original_name"),
            mimeType = o.optString("mime_type").ifEmpty { null },
            sizeBytes = o.getLong("size_bytes"),
            uploadedFrom = o.getString("uploaded_from"),
            uploadedAt = o.getString("uploaded_at")
        )
    }
}

/**
 * Thin REST client for Supabase Storage + PostgREST.
 * No SDK — just OkHttp + org.json so the APK stays small.
 */
class SupabaseRepo(
    private val baseUrl: String = Config.SUPABASE_URL.trimEnd('/'),
    private val key: String = Config.SUPABASE_KEY
) : MoxBackend {
    private val bucket = "mox"
    private val client = OkHttpClient.Builder()
        .callTimeout(10, TimeUnit.MINUTES)
        .readTimeout(2, TimeUnit.MINUTES)
        .writeTimeout(10, TimeUnit.MINUTES)
        .build()

    override suspend fun fetchCurrent(): CurrentFile? = withContext(Dispatchers.IO) {
        val req = Request.Builder()
            .url("$baseUrl/rest/v1/current_file?id=eq.1&select=*")
            .headers(authHeaders())
            .get()
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw IOException("HTTP ${resp.code}")
            val arr = JSONArray(resp.body!!.string())
            if (arr.length() == 0) null else CurrentFile.fromJson(arr.getJSONObject(0))
        }
    }

    override suspend fun uploadFromContentUri(
        resolver: ContentResolver,
        uri: Uri,
        displayName: String,
        sizeBytes: Long,
        mime: String?
    ): CurrentFile = withContext(Dispatchers.IO) {
        require(sizeBytes in 1..Config.MAX_BYTES) {
            if (sizeBytes <= 0) "File is empty." else "File exceeds 500 MB cap."
        }
        val ext = displayName.substringAfterLast('.', "").ifEmpty {
            MimeTypeMap.getSingleton().getExtensionFromMimeType(mime ?: "") ?: "bin"
        }
        val storagePath = "current.$ext"
        val effectiveMime = mime ?: "application/octet-stream"

        val streamBody = object : RequestBody() {
            override fun contentType() = effectiveMime.toMediaType()
            override fun contentLength() = sizeBytes
            override fun writeTo(sink: BufferedSink) {
                resolver.openInputStream(uri)!!.use { input ->
                    sink.writeAll(input.source())
                }
            }
        }

        val uploadReq = Request.Builder()
            .url("$baseUrl/storage/v1/object/$bucket/$storagePath")
            .headers(authHeaders(extra = mapOf("x-upsert" to "true")))
            .post(streamBody)
            .build()
        client.newCall(uploadReq).execute().use { resp ->
            if (!resp.isSuccessful) {
                val msg = resp.body?.string() ?: "HTTP ${resp.code}"
                throw IOException("Upload failed: $msg")
            }
        }

        val row = JSONObject().apply {
            put("id", 1)
            put("storage_path", storagePath)
            put("original_name", displayName)
            put("mime_type", effectiveMime)
            put("size_bytes", sizeBytes)
            put("uploaded_from", "android")
        }
        val upsert = Request.Builder()
            .url("$baseUrl/rest/v1/current_file?on_conflict=id")
            .headers(
                authHeaders(
                    extra = mapOf(
                        "Content-Type" to "application/json",
                        "Prefer" to "resolution=merge-duplicates,return=representation"
                    )
                )
            )
            .post(row.toString().toRequestBody("application/json".toMediaType()))
            .build()
        client.newCall(upsert).execute().use { resp ->
            if (!resp.isSuccessful) throw IOException("Upsert failed: HTTP ${resp.code}")
            val arr = JSONArray(resp.body!!.string())
            CurrentFile.fromJson(arr.getJSONObject(0))
        }
    }

    override suspend fun signedDownloadUrl(path: String, expiresIn: Int): String =
        withContext(Dispatchers.IO) {
            val body = JSONObject().put("expiresIn", expiresIn).toString()
                .toRequestBody("application/json".toMediaType())
            val req = Request.Builder()
                .url("$baseUrl/storage/v1/object/sign/$bucket/$path")
                .headers(authHeaders(extra = mapOf("Content-Type" to "application/json")))
                .post(body)
                .build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) throw IOException("Sign failed: HTTP ${resp.code}")
                val obj = JSONObject(resp.body!!.string())
                "$baseUrl/storage/v1${obj.getString("signedURL")}"
            }
        }

    override suspend fun downloadTo(file: File, current: CurrentFile) {
        withContext(Dispatchers.IO) {
            file.outputStream().use { out -> downloadToStream(out, current) }
        }
    }

    override suspend fun downloadToStream(out: java.io.OutputStream, current: CurrentFile) {
        withContext(Dispatchers.IO) {
            val url = signedDownloadUrl(current.storagePath)
            val req = Request.Builder().url(url).get().build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) throw IOException("Download failed: HTTP ${resp.code}")
                resp.body!!.byteStream().copyTo(out)
            }
        }
    }

    private fun authHeaders(extra: Map<String, String> = emptyMap()) = (
        mapOf(
            "apikey" to key,
            "Authorization" to "Bearer $key"
        ) + extra
        ).toHeaders()
}
