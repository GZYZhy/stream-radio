package com.gzyzhy.streamradio.data

import java.util.UUID

// 电台模型
data class Station(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val url: String,
    val isFavorite: Boolean = false
)

// 订阅源
data class Subscription(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val url: String
)

// 音频质量信息
data class AudioQuality(
    val codec: String? = null,
    val bitrateKbps: Int? = null,
    val sampleRateHz: Int? = null,
    val channelCount: Int? = null
) {
    val summary: String
        get() {
            val parts = mutableListOf<String>()
            codec?.let { parts.add(it) }
            bitrateKbps?.let { parts.add("$it kbps") }
            sampleRateHz?.let { parts.add(formatSampleRate(it)) }
            channelCount?.let { parts.add(channelText(it)) }
            return parts.joinToString(" · ")
        }

    val isEmpty: Boolean get() = summary.isEmpty()

    companion object {
        fun formatSampleRate(hz: Int): String {
            return if (hz % 1000 == 0) "${hz / 1000} kHz"
            else String.format("%.1f kHz", hz / 1000.0)
        }

        fun channelText(n: Int): String = when (n) {
            1 -> "单声道"
            2 -> "立体声"
            else -> "$n 声道"
        }
    }
}

// 连通性检查结果
data class ConnectivityResult(
    val ok: Boolean,
    val durationMs: Int,
    val message: String? = null
)
