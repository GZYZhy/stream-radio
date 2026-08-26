package com.gzyzhy.streamradio.util

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

// 设置管理
class SettingsManager(private val context: Context) {

    private val appearanceKey = stringPreferencesKey("appearanceMode")
    private val autoSyncKey = booleanPreferencesKey("autoSyncOnLaunch")
    private val appLanguageKey = stringPreferencesKey("app_language")

    val appearanceMode: Flow<String> = context.settingsDataStore.data.map {
        it[appearanceKey] ?: "system"
    }

    val autoSyncOnLaunch: Flow<Boolean> = context.settingsDataStore.data.map {
        it[autoSyncKey] ?: false
    }

    val appLanguage: Flow<String> = context.settingsDataStore.data.map {
        it[appLanguageKey] ?: "system"
    }

    suspend fun setAppearanceMode(mode: String) {
        context.settingsDataStore.edit { it[appearanceKey] = mode }
    }

    suspend fun setAppLanguage(value: String) {
        context.settingsDataStore.edit { it[appLanguageKey] = value }
    }

    suspend fun setAutoSyncOnLaunch(value: Boolean) {
        context.settingsDataStore.edit { it[autoSyncKey] = value }
    }
}
