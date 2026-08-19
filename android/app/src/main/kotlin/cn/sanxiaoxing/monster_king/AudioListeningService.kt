package cn.sanxiaoxing.monster_king

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * 后台持续监听前台服务（microphone 类型）。
 *
 * 音乐律动采集期间常驻，职责只有两个：
 * 1. 持有 microphone 类型前台服务——Android 11+ 后台麦克风限制要求应用
 *    在后台持有该类型前台服务才能继续采集（锁屏/切后台/被系统回收时，
 *    录音与 Rust 分析/律动/BLE 下发链路都不中断）。
 * 2. 持有 PARTIAL_WAKE_LOCK——息屏后 CPU 保持唤醒，AudioRecord 持续供数。
 *
 * 音频采集本身仍由 Flutter 侧 record 插件完成（同一进程），本服务不碰
 * 录音与荧光棒逻辑，只负责"保活 + 权限持有"。
 */
class AudioListeningService : Service() {

    companion object {
        private const val CHANNEL_ID = "music_listening"
        private const val CHANNEL_NAME = "音乐监听"
        private const val NOTIFICATION_ID = 1001

        /** 安全兜底：超过 6h 自动释放唤醒锁，防异常路径下的电量泄漏。 */
        private const val WAKE_LOCK_TIMEOUT_MS = 6 * 60 * 60 * 1000L
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createNotificationChannel()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            startForegroundCompat()
        } catch (e: SecurityException) {
            // START_STICKY 后台重启时 while-in-use（RECORD_AUDIO）权限不可用，
            // 无法合法持有 microphone 前台类型；直接结束，避免崩溃循环
            stopSelf()
            return START_NOT_STICKY
        }
        acquireWakeLock()
        // 被系统回收后尽量恢复：前台类型已在 manifest 声明，重启即可重新
        // 声明麦克风访问；Flutter 管线若仍在，监听不受影响
        return START_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startForegroundCompat() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // API 29+ 需显式声明前台类型（与 manifest foregroundServiceType 一致）
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "荧光棒律动正在监听音乐"
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_music)
            .setContentTitle("正在监听音乐")
            .setContentText("荧光棒正在根据音乐律动")
            .setContentIntent(openApp)
            .setOngoing(true)
            .build()
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(PowerManager::class.java)
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "monster_king:music_listening",
        ).apply {
            setReferenceCounted(false)
            acquire(WAKE_LOCK_TIMEOUT_MS)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
    }
}
