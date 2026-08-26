package com.gzyzhy.streamradio.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "radio_prefs")

// 电台仓库：增删改移、星标、m3u导入、订阅同步、持久化
class StationRepository(private val context: Context) {

    private val stationsKey = stringPreferencesKey("stations_v1")
    private val subsKey = stringPreferencesKey("subscriptions_v1")

    val stationsFlow: Flow<List<Station>> = context.dataStore.data.map { prefs ->
        prefs[stationsKey]?.let {
            try { JsonUtil.stationsFromJson(it) } catch (_: Exception) { null }
        } ?: M3UParser.builtin
    }

    val subscriptionsFlow: Flow<List<Subscription>> = context.dataStore.data.map { prefs ->
        prefs[subsKey]?.let {
            try { JsonUtil.subscriptionsFromJson(it) } catch (_: Exception) { null }
        } ?: emptyList()
    }

    suspend fun getStations(): List<Station> = stationsFlow.first()
    suspend fun getSubscriptions(): List<Subscription> = subscriptionsFlow.first()

    // ---- 电台增删改移 ----

    suspend fun add(station: Station) {
        val list = getStations().toMutableList()
        list.add(station)
        saveStations(list)
    }

    suspend fun importSelected(stations: List<Station>) {
        val existing = getStations().toMutableList()
        val urls = existing.map { it.url }.toMutableSet()
        for (s in stations) {
            if (s.url !in urls) {
                urls.add(s.url)
                existing.add(s)
            }
        }
        saveStations(existing)
    }

    suspend fun remove(targets: List<Station>) {
        val targetIds = targets.map { it.id }.toSet()
        val list = getStations().filter { it.id !in targetIds }.toMutableList()
        saveStations(list)
    }

    suspend fun update(station: Station, name: String, url: String) {
        val list = getStations().toMutableList()
        val idx = list.indexOfFirst { it.id == station.id }
        if (idx < 0) return
        val newName = name.trim()
        val newURL = url.trim()
        if (newName.isEmpty()) return
        list[idx] = station.copy(name = newName, url = newURL.ifEmpty { station.url })
        saveStations(list)
    }

    suspend fun moveUp(station: Station) {
        val list = getStations().toMutableList()
        val idx = list.indexOfFirst { it.id == station.id }
        if (idx > 0) {
            list[idx] = list[idx - 1].also { list[idx - 1] = list[idx] }
            saveStations(list)
        }
    }

    suspend fun moveDown(station: Station) {
        val list = getStations().toMutableList()
        val idx = list.indexOfFirst { it.id == station.id }
        if (idx >= 0 && idx < list.size - 1) {
            list[idx] = list[idx + 1].also { list[idx + 1] = list[idx] }
            saveStations(list)
        }
    }

    suspend fun toggleFavorite(station: Station) {
        val list = getStations().toMutableList()
        val idx = list.indexOfFirst { it.id == station.id }
        if (idx >= 0) {
            list[idx] = list[idx].copy(isFavorite = !list[idx].isFavorite)
            saveStations(list)
        }
    }

    suspend fun toggleFavoriteByUrl(url: String) {
        val list = getStations().toMutableList()
        val idx = list.indexOfFirst { it.url == url }
        if (idx >= 0) {
            list[idx] = list[idx].copy(isFavorite = !list[idx].isFavorite)
            saveStations(list)
        }
    }

    // ---- 订阅 ----

    suspend fun addSubscription(name: String, url: String) {
        val trimmed = url.trim()
        val list = getSubscriptions().toMutableList()
        if (list.any { it.url == trimmed }) return
        list.add(Subscription(name = name.trim(), url = trimmed))
        saveSubscriptions(list)
    }

    suspend fun removeSubscription(sub: Subscription) {
        val list = getSubscriptions().filter { it.id != sub.id }
        saveSubscriptions(list)
    }

    // 同步全部订阅，返回新增数（-1 表示失败）
    suspend fun syncAllSubscriptions(): Int {
        var total = 0
        for (sub in getSubscriptions()) {
            val n = syncSubscription(sub)
            if (n > 0) total += n
            else if (n < 0) return -1
        }
        return total
    }

    // 同步单个订阅
    private suspend fun syncSubscription(sub: Subscription): Int {
        return try {
            val text = ConnectivityChecker.downloadText(sub.url)
            val parsed = M3UParser.parse(text)
            val existingUrls = getStations().map { it.url }.toSet()
            val fresh = parsed.filter { it.url !in existingUrls }
            if (fresh.isEmpty()) return 0
            importSelected(fresh)
            fresh.size
        } catch (e: Exception) {
            -1
        }
    }

    // ---- 持久化 ----

    private suspend fun saveStations(list: List<Station>) {
        context.dataStore.edit { it[stationsKey] = JsonUtil.stationsToJson(list) }
    }

    private suspend fun saveSubscriptions(list: List<Subscription>) {
        context.dataStore.edit { it[subsKey] = JsonUtil.subscriptionsToJson(list) }
    }

    companion object {
        @Volatile private var instance: StationRepository? = null
        fun get(context: Context): StationRepository =
            instance ?: synchronized(this) {
                instance ?: StationRepository(context.applicationContext).also { instance = it }
            }
    }
}
