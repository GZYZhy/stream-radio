package com.gzyzhy.streamradio.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

// 最新 release 信息（来自 GitHub API）
data class LatestRelease(val version: String, val notes: String)

// 检查更新：请求 GitHub releases/latest，返回最新 release 信息；失败返回 null
object UpdateChecker {

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    suspend fun fetchLatestRelease(): LatestRelease? = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder()
                .url("https://api.github.com/repos/GZYZhy/stream-radio/releases/latest")
                // GitHub API 强制要求带 User-Agent，否则返回 403
                .header("User-Agent", "StreamRadio-Updater/1.0")
                .build()
            client.newCall(request).execute().use { resp ->
                if (!resp.isSuccessful) return@withContext null
                val json = JSONObject(resp.body?.string() ?: "")
                val version = json.optString("tag_name").takeIf { it.isNotBlank() }
                    ?: return@withContext null
                LatestRelease(version = version, notes = json.optString("body"))
            }
        } catch (_: Exception) {
            null
        }
    }
}
