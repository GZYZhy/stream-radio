package com.gzyzhy.streamradio.data

import android.content.Context
import com.gzyzhy.streamradio.R
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
    // 汇总质量信息（声道描述按当前语言本地化）
    fun summary(context: Context): String {
        val parts = mutableListOf<String>()
        codec?.let { parts.add(it) }
        bitrateKbps?.let { parts.add("$it kbps") }
        sampleRateHz?.let { parts.add(formatSampleRate(it)) }
        channelCount?.let { parts.add(channelText(context, it)) }
        return parts.joinToString(" · ")
    }

    val isEmpty: Boolean get() =
        codec == null && bitrateKbps == null && sampleRateHz == null && channelCount == null

    companion object {
        fun formatSampleRate(hz: Int): String {
            return if (hz % 1000 == 0) "${hz / 1000} kHz"
            else String.format("%.1f kHz", hz / 1000.0)
        }

        // 声道描述本地化：单声道 / 立体声 / n 声道
        fun channelText(context: Context, n: Int): String = when (n) {
            1 -> context.getString(R.string.quality_mono)
            2 -> context.getString(R.string.quality_stereo)
            else -> context.getString(R.string.quality_channels, n)
        }
    }
}

// 连通性检查结果
data class ConnectivityResult(
    val ok: Boolean,
    val durationMs: Int,
    val message: String? = null
)
