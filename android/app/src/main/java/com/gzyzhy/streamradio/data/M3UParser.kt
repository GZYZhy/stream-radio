package com.gzyzhy.streamradio.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

// m3u 解析器：与 iOS 版一致的宽松逻辑
object M3UParser {

    // 内置示例电台（默认空，让用户自行导入或添加）
    val builtin: List<Station> = emptyList()

    // 解析 m3u 文本
    fun parse(text: String): List<Station> {
        val result = mutableListOf<Station>()
        var pendingName: String? = null
        val seen = mutableSetOf<String>()
        val cleaned = text.replace("﻿", "")

        for (rawLine in cleaned.lines()) {
            val line = rawLine.trim()
            if (line.isEmpty()) continue
            val upper = line.uppercase()
            if (upper == "#EXTM3U" || line.startsWith("#Update:")) continue

            if (line.startsWith("#EXTINF:")) {
                val commaIndex = line.lastIndexOf(',')
                pendingName = if (commaIndex >= 0) {
                    line.substring(commaIndex + 1).trim().ifEmpty { null }
                } else null
            } else if (line.startsWith("#")) {
                continue
            } else {
                // 地址行
                val url = line.trim { it == '"' }
                val lower = url.lowercase()
                if (!lower.startsWith("http://") && !lower.startsWith("https://")) continue
                if (seen.contains(url)) continue
                seen.add(url)
                val name = pendingName ?: fallbackName(url)
                result.add(Station(name = name, url = url))
                pendingName = null
            }
        }
        return result
    }

    private fun fallbackName(url: String): String {
        val file = url.substringAfterLast('/').substringBefore('?')
        return file.ifEmpty { url }
    }
}

// 连通性检查
object ConnectivityChecker {

    private val client = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(5, TimeUnit.SECONDS)
        .build()

    suspend fun check(urlString: String, timeoutSec: Long = 5): ConnectivityResult =
        withContext(Dispatchers.IO) {
            val start = System.currentTimeMillis()
            try {
                // HEAD 优先
                val headRequest = Request.Builder()
                    .url(urlString)
                    .head()
                    .header("User-Agent", "Mozilla/5.0 RadioPlayer/1.0")
                    .header("Icy-MetaData", "1")
                    .build()
                client.newCall(headRequest).execute().use { resp ->
                    val code = resp.code
                    if (code in 200..399) {
                        return@withContext ConnectivityResult(
                            ok = true,
                            durationMs = (System.currentTimeMillis() - start).toInt()
                        )
                    }
                }
            } catch (_: Exception) {}

            // GET 兜底
            try {
                val getRequest = Request.Builder()
                    .url(urlString)
                    .header("User-Agent", "Mozilla/5.0 RadioPlayer/1.0")
                    .header("Icy-MetaData", "1")
                    .build()
                client.newCall(getRequest).execute().use { resp ->
                    val code = resp.code
                    val body = resp.body
                    body?.byteStream()?.use { stream ->
                        val buf = ByteArray(4096)
                        var total = 0
                        while (total < 4096) {
                            val n = stream.read(buf)
                            if (n < 0) break
                            total += n
                        }
                    }
                    val duration = (System.currentTimeMillis() - start).toInt()
                    if (code in 200..399) {
                        return@withContext ConnectivityResult(ok = true, durationMs = duration)
                    }
                    if (code in intArrayOf(401, 403, 404, 405, 416)) {
                        return@withContext ConnectivityResult(
                            ok = true, durationMs = duration, message = "HTTP $code"
                        )
                    }
                    return@withContext ConnectivityResult(
                        ok = false, durationMs = duration, message = "HTTP $code"
                    )
                }
            } catch (e: Exception) {
                return@withContext ConnectivityResult(
                    ok = false,
                    durationMs = (System.currentTimeMillis() - start).toInt(),
                    message = e.message
                )
            }
        }

    // 下载文本（订阅 m3u 用）
    suspend fun downloadText(urlString: String): String = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url(urlString)
            .header("User-Agent", "Mozilla/5.0 RadioPlayer/1.0")
            .build()
        client.newCall(request).execute().use { resp ->
            val body = resp.body?.string() ?: ""
            body
        }
    }
}
