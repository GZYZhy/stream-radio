package com.gzyzhy.streamradio.ui

import android.content.Context
import android.content.Intent
import com.gzyzhy.streamradio.data.Station
import com.gzyzhy.streamradio.service.RadioPlaybackService

// 播放控制的静态入口（供 UI 调用）
object RadioPlaybackController {

    private var service: RadioPlaybackService? = null

    fun attach(svc: RadioPlaybackService) { service = svc }
    fun detach() { service = null }

    fun play(station: Station) {
        service?.play(station)
    }

    fun toggle() {
        service?.toggle()
    }

    fun stop() {
        service?.stop()
    }

    fun next() {
        service?.next()
    }

    fun previous() {
        service?.previous()
    }

    fun setSleepTimer(minutes: Int?) {
        service?.setSleepTimer(minutes)
    }

    fun toggleFavorite() {
        service?.toggleFavorite()
    }
}
