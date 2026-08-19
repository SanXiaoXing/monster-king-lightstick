package cn.sanxiaoxing.monster_king

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        /** Flutter ↔ 原生 前台服务桥（Dart 侧 audio/data/android_listen_service.dart 门面）。 */
        const val CHANNEL = "cn.sanxiaoxing.monster_king/listen_service"
        private const val REQ_NOTIFICATION_PERMISSION = 1002
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> {
                        startListenService()
                        result.success(null)
                    }
                    "stopService" -> {
                        stopService(Intent(this, AudioListeningService::class.java))
                        result.success(null)
                    }
                    "requestNotificationPermission" -> {
                        requestNotificationPermissionIfNeeded()
                        result.success(null)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizationsIfNeeded()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startListenService() {
        val intent = Intent(this, AudioListeningService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // API 26+ 启动前台服务必须走 startForegroundService
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    /** Android 13+ 通知需运行时授权；拒绝时前台服务仍运行，仅通知不展示。 */
    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQ_NOTIFICATION_PERMISSION,
            )
        }
    }

    /**
     * 电池优化豁免：激进的后台清理会在切后台几秒内杀掉监听进程。
     * 未豁免时弹出系统"允许后台运行"对话框；用户拒绝仍可前台监听。
     */
    private fun requestIgnoreBatteryOptimizationsIfNeeded() {
        val pm = getSystemService(PowerManager::class.java)
        if (pm.isIgnoringBatteryOptimizations(packageName)) return
        try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName"),
                )
            )
        } catch (_: Exception) {
            // 个别 ROM 无此入口：忽略，不影响监听
        }
    }
}
