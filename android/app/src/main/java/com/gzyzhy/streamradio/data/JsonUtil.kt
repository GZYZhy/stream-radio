package com.gzyzhy.streamradio.data

import org.json.JSONArray
import org.json.JSONObject

// 手动 JSON 序列化/反序列化（避免引入序列化插件）
object JsonUtil {

    // Station 列表 → JSON 字符串
    fun stationsToJson(list: List<Station>): String {
        val arr = JSONArray()
        for (s in list) {
            val obj = JSONObject().apply {
                put("id", s.id)
                put("name", s.name)
                put("url", s.url)
                put("isFavorite", s.isFavorite)
            }
            arr.put(obj)
        }
        return arr.toString()
    }

    // JSON 字符串 → Station 列表
    fun stationsFromJson(json: String): List<Station> {
        val list = mutableListOf<Station>()
        val arr = JSONArray(json)
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            list.add(
                Station(
                    id = obj.optString("id"),
                    name = obj.optString("name"),
                    url = obj.optString("url"),
                    isFavorite = obj.optBoolean("isFavorite", false)
                )
            )
        }
        return list
    }

    // Subscription 列表 → JSON
    fun subscriptionsToJson(list: List<Subscription>): String {
        val arr = JSONArray()
        for (s in list) {
            val obj = JSONObject().apply {
                put("id", s.id)
                put("name", s.name)
                put("url", s.url)
            }
            arr.put(obj)
        }
        return arr.toString()
    }

    // JSON → Subscription 列表
    fun subscriptionsFromJson(json: String): List<Subscription> {
        val list = mutableListOf<Subscription>()
        val arr = JSONArray(json)
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            list.add(
                Subscription(
                    id = obj.optString("id"),
                    name = obj.optString("name"),
                    url = obj.optString("url")
                )
            )
        }
        return list
    }
}
