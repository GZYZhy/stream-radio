package com.gzyzhy.streamradio.service

import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import com.gzyzhy.streamradio.MainActivity
import com.gzyzhy.streamradio.R
import kotlin.math.abs

// 全局悬浮球服务（App 切后台也能显示）
class FloatingBubbleService : Service() {

    private var windowManager: WindowManager? = null
    private var bubbleView: View? = null
    private var params: WindowManager.LayoutParams? = null

    private var initialX = 0
    private var initialY = 0
    private var touchX = 0f
    private var touchY = 0f

    companion object {
        var isRunning = false
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        // 创建悬浮球 View
        bubbleView = ImageView(this).apply {
            setImageResource(R.drawable.ic_radio)
            setBackgroundColor(0xFF007AFF.toInt())
            setPadding(24, 24, 24, 24)
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 100
            y = 200
        }

        // 触摸移动 + 点击
        bubbleView?.setOnTouchListener { view, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params?.x ?: 0
                    initialY = params?.y ?: 0
                    touchX = event.rawX
                    touchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - touchX
                    val dy = event.rawY - touchY
                    params?.x = initialX + dx.toInt()
                    params?.y = initialY + dy.toInt()
                    windowManager?.updateViewLayout(bubbleView, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    // 判断是点击还是移动
                    val dx = abs(event.rawX - touchX)
                    val dy = abs(event.rawY - touchY)
                    if (dx < 10 && dy < 10) {
                        // 点击：打开 App
                        val intent = Intent(this, MainActivity::class.java).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                        }
                        startActivity(intent)
                    }
                    true
                }
                else -> false
            }
        }

        try {
            windowManager?.addView(bubbleView, params)
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        try {
            bubbleView?.let { windowManager?.removeView(it) }
        } catch (_: Exception) {}
        bubbleView = null
        windowManager = null
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
