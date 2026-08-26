package com.gzyzhy.streamradio

import android.app.Application
import android.os.Process
import android.util.Log
import com.gzyzhy.streamradio.data.StationRepository

class RadioApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // 崩溃捕获（诊断用）：把闪退堆栈写入本地，重启后界面弹窗展示
        Thread.setDefaultUncaughtExceptionHandler { _, throwable ->
            try {
                val stack = Log.getStackTraceString(throwable)
                getSharedPreferences("crash_report", MODE_PRIVATE)
                    .edit().putString("last_crash", stack).commit()
            } catch (_: Exception) {
            }
            // 保持默认崩溃行为：终止进程
            Process.killProcess(Process.myPid())
        }
        // 预热仓库
        StationRepository.get(this)
    }
}
