package com.example.punch_reminder

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.example.punch_reminder/monitor"
    private val EVENT_CHANNEL = "com.example.punch_reminder/status"
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // MethodChannel: Flutter → Native 指令
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startMonitor" -> {
                        NotificationHelper.createChannels(this)
                        val intent = Intent(this, MonitorService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "stopMonitor" -> {
                        stopService(Intent(this, MonitorService::class.java))
                        result.success(true)
                    }
                    "isRunning" -> {
                        result.success(MonitorService.isRunning)
                    }
                    "reloadConfig" -> {
                        if (MonitorService.isRunning) {
                            // 通知 Service 重新加载配置
                            val intent = Intent(this, MonitorService::class.java)
                            intent.action = "RELOAD_CONFIG"
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "checkUsagePermission" -> {
                        result.success(hasUsagePermission())
                    }
                    "grantUsagePermission" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    "checkPunchedToday" -> {
                        val startHour = call.argument<Int>("startHour") ?: 19
                        result.success(isFxiaokeUsedAfterHour(startHour))
                    }
                    else -> result.notImplemented()
                }
            }

        // EventChannel: Native → Flutter 状态推送
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    MonitorService.statusCallback = { data ->
                        runOnUiThread {
                            eventSink?.success(data)
                        }
                    }
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    MonitorService.statusCallback = null
                }
            })
    }

    private fun isFxiaokeUsedAfterHour(startHour: Int): Boolean {
        return try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val cal = java.util.Calendar.getInstance()
            val now = cal.timeInMillis
            // 今天 0:00 开始查，覆盖全天
            cal.set(java.util.Calendar.HOUR_OF_DAY, 0)
            cal.set(java.util.Calendar.MINUTE, 0)
            cal.set(java.util.Calendar.SECOND, 0)
            cal.set(java.util.Calendar.MILLISECOND, 0)
            val startTime = cal.timeInMillis
            val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, startTime, now)
            stats.any { it.packageName == "com.fxiaoke.sales" && it.lastTimeUsed >= startTime }
        } catch (e: Exception) {
            false
        }
    }

    private fun hasUsagePermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }
}
