package cn.sanxiaoxing.monster_king

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "monster_king/audio_capture"
        private const val EVENT_CHANNEL = "monster_king/audio_capture/pcm"
        private const val REQ_PERMISSIONS = 42
    }

    /** 等待权限结果的回调（同一时间只会有一个权限申请在途）。 */
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> requestAudioPermissions(result)
                    "hasPermission" -> result.success(hasAudioPermission())
                    "start" -> {
                        if (!hasAudioPermission()) {
                            result.error("PERMISSION_DENIED", "麦克风权限未授予", null)
                        } else {
                            AudioCaptureService.start(this)
                            result.success(true)
                        }
                    }
                    "stop" -> {
                        AudioCaptureService.stop(this)
                        result.success(true)
                    }
                    "isCapturing" -> result.success(AudioCaptureService.isCapturing)
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    AudioCaptureBus.listener = { pcm -> events.success(pcm) }
                }

                override fun onCancel(arguments: Any?) {
                    AudioCaptureBus.listener = null
                }
            })
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        AudioCaptureBus.listener = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun hasAudioPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestAudioPermissions(result: MethodChannel.Result) {
        if (hasAudioPermission()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("ALREADY_REQUESTING", "权限申请进行中", null)
            return
        }
        val permissions = mutableListOf(Manifest.permission.RECORD_AUDIO)
        // Android 13+：前台服务常驻通知需要通知权限才能在通知栏可见
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(this, permissions.toTypedArray(), REQ_PERMISSIONS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_PERMISSIONS) {
            // 通知权限可拒绝（仅影响通知栏展示），麦克风权限必须授予
            val micIndex = permissions.indexOf(Manifest.permission.RECORD_AUDIO)
            val granted = micIndex >= 0 &&
                grantResults.getOrNull(micIndex) == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }
}
