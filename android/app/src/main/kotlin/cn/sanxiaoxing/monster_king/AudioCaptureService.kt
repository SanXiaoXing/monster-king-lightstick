package cn.sanxiaoxing.monster_king

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * 麦克风采集与 Flutter 之间的进程内总线。
 *
 * Service 在采集线程产出 PCM 块，经主线程 Handler 派发给当前监听者
 * （MainActivity 的 EventChannel sink）。Activity 销毁后 sink 置空，
 * 采集线程继续运行并丢帧，Flutter 引擎回到前台重新 listen 即恢复。
 */
object AudioCaptureBus {
    private val mainHandler = Handler(Looper.getMainLooper())

    /** 主线程上设置的 PCM 监听者（EventChannel sink 转发）。 */
    @Volatile
    var listener: ((ByteArray) -> Unit)? = null

    /** 采集线程调用：有监听者才拷贝派发，无监听者直接丢帧（零拷贝）。 */
    fun dispatch(pcm: ByteArray) {
        val l = listener ?: return
        mainHandler.post { l(pcm) }
    }
}

/**
 * 麦克风前台服务：锁屏/退后台后持续用 AudioRecord 采集 PCM，
 * 经 [AudioCaptureBus] 推给 Flutter 侧音频分析器。
 *
 * 采集参数与 Dart 侧 AudioAnalyzer 对齐：44.1kHz 单声道 PCM16。
 * 音源优先 [MediaRecorder.AudioSource.UNPROCESSED]（不施加 AGC/噪声抑制，
 * 避免音乐被通话向处理压扁失真），不支持时退回 MIC。
 */
class AudioCaptureService : Service() {

    companion object {
        const val ACTION_START = "cn.sanxiaoxing.monster_king.audio.START"
        const val ACTION_STOP = "cn.sanxiaoxing.monster_king.audio.STOP"

        private const val CHANNEL_ID = "audio_capture"
        private const val NOTIFICATION_ID = 1001
        private const val SAMPLE_RATE = 44100
        // 单次读取约 20ms 的样本（44100 * 0.02 * 2 字节，向上取偶）
        private const val CHUNK_BYTES = 1764

        /** 采集会话是否存活（Dart 侧 isCapturing 查询用）。 */
        @Volatile
        var isCapturing = false
            private set

        fun start(context: Context) {
            val intent = Intent(context, AudioCaptureService::class.java).setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, AudioCaptureService::class.java).setAction(ACTION_STOP)
            )
        }
    }

    @Volatile
    private var running = false
    private var captureThread: Thread? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopCapture()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                if (!running) startCapture()
            }
        }
        return START_STICKY
    }

    private fun startCapture() {
        startForegroundWithNotification()
        acquireWakeLock()
        running = true
        isCapturing = true
        captureThread = Thread({ captureLoop() }, "audio-capture").apply { start() }
    }

    private fun captureLoop() {
        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBuf <= 0) {
            stopSelf()
            return
        }
        // 音源候选：UNPROCESSED 无通话向处理，部分机型不支持则退回 MIC
        val recorder = listOf(
            MediaRecorder.AudioSource.UNPROCESSED,
            MediaRecorder.AudioSource.MIC,
        ).firstNotNullOfOrNull { source ->
            try {
                AudioRecord(
                    source, SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                    // 缓冲取 4 倍下限，抗调度抖动
                    maxOf(minBuf * 4, CHUNK_BYTES * 4),
                ).takeIf { it.state == AudioRecord.STATE_INITIALIZED }
            } catch (_: Exception) {
                null
            }
        }
        if (recorder == null) {
            stopSelf()
            return
        }

        val chunk = ByteArray(CHUNK_BYTES)
        try {
            recorder.startRecording()
            while (running) {
                val n = recorder.read(chunk, 0, chunk.size)
                if (n > 0) {
                    AudioCaptureBus.dispatch(if (n == chunk.size) chunk else chunk.copyOf(n))
                }
            }
        } catch (_: Exception) {
            // 采集异常（设备被抢占等）：安静退出，由 Dart 侧重连机制重启会话
        } finally {
            try {
                recorder.stop()
            } catch (_: Exception) {
            }
            recorder.release()
        }
    }

    private fun stopCapture() {
        running = false
        isCapturing = false
        captureThread?.join(500)
        captureThread = null
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun startForegroundWithNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID, "音乐监听",
                    // LOW：常驻通知不出声不震动
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }

        // 点通知回到 App
        val contentIntent = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // 通知上的「停止」按钮
        val stopIntent = PendingIntent.getService(
            this, 1,
            Intent(this, AudioCaptureService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("正在监听音乐")
            .setContentText("荧光棒正在根据音乐律动")
            .setContentIntent(contentIntent)
            .addAction(0, "停止", stopIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "monster_king:audio_capture",
        ).apply {
            // 超时兜底 12 小时，防异常路径忘记释放
            acquire(12 * 60 * 60 * 1000L)
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
    }

    override fun onDestroy() {
        running = false
        isCapturing = false
        releaseWakeLock()
        super.onDestroy()
    }
}
