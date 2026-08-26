package com.gzyzhy.streamradio.util

import android.content.Context
import android.content.res.Configuration
import kotlinx.coroutines.flow.first
import java.util.Locale

// 语言工具：负责应用语言的选择与应用
object LocaleHelper {

    // 根据语言设置返回应用该语言后的 context。
    // 传 "system" 时表示跟随系统，原样返回。
    fun applyLanguage(context: Context, lang: String): Context {
        if (lang == "system") return context
        // 设置里存的语言代码，映射到 Android Locale
        val locale = when (lang) {
            "zh-Hans" -> Locale("zh", "CN")
            "en" -> Locale("en")
            "fr" -> Locale("fr")
            "ja" -> Locale("ja")
            else -> return context
        }
        val config = Configuration(context.resources.configuration)
        config.setLocale(locale)
        return context.createConfigurationContext(config)
    }

    // 从设置读取当前应用语言（默认 "system"）
    suspend fun getAppLanguage(context: Context): String {
        return SettingsManager(context).appLanguage.first()
    }
}
