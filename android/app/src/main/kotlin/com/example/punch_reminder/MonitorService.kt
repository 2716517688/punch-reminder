package com.example.punch_reminder

import android.app.Service
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.location.Location
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import com.google.android.gms.location.*

class MonitorService : Service() {
    companion object {
        const val TAG = "MonitorService"
        const val PREFS_NAME = "FlutterSharedPreferences"
        const val FXIAOKE_PACKAGE = "com.facishare.fs"

        var statusCallback: ((Map<String, Any>) -> Unit)? = null
        var isRunning = false
            private set
    }

    private lateinit var fusedClient: FusedLocationProviderClient
    private lateinit var prefs: SharedPreferences
    private val handler = Handler(Looper.getMainLooper())
    private var checkRunnable: Runnable? = null
    private var alertRunnable: Runnable? = null
    private var alerted = false

    // 配置
    private var officeLat = 0.0
    private var officeLng = 0.0
    private var threshold = 50.0
    private var startHour = 19
    private var intervalSeconds = 30
    private var autoLaunch = false

    override fun onCreate() {
        super.onCreate()
        NotificationHelper.createChannels(this)
        fusedClient = LocationServices.getFusedLocationProviderClient(this)
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(
            NotificationHelper.FOREGROUND_ID,
            NotificationHelper.buildForegroundNotification(this, "监控中...")
        )
        loadConfig()
        if (intent?.action == "RELOAD_CONFIG") {
            // 重新加载配置并重启定时器
            startChecking()
        } else {
            startChecking()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopChecking()
        stopAlertReminder()
        NotificationHelper.cancelAlert(this)
        isRunning = false
        super.onDestroy()
    }

    fun loadConfig() {
        officeLat = prefs.getFloat("flutter.office_lat", 0f).toDouble()
        officeLng = prefs.getFloat("flutter.office_lng", 0f).toDouble()
        threshold = prefs.getFloat("flutter.threshold", 50f).toDouble()
        startHour = prefs.getLong("flutter.start_hour", 19).toInt()
        intervalSeconds = prefs.getLong("flutter.interval_seconds", 30).toInt()
        autoLaunch = prefs.getBoolean("flutter.auto_launch", false)
    }

    private fun startChecking() {
        stopChecking()
        checkRunnable = object : Runnable {
            override fun run() {
                doCheck()
                handler.postDelayed(this, intervalSeconds * 1000L)
            }
        }
        handler.post(checkRunnable!!)
    }

    private fun stopChecking() {
        checkRunnable?.let { handler.removeCallbacks(it) }
        checkRunnable = null
    }

    @Suppress("MissingPermission")
    private fun doCheck() {
        if (officeLat == 0.0 && officeLng == 0.0) return

        fusedClient.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, null)
            .addOnSuccessListener { location: Location? ->
                if (location == null) return@addOnSuccessListener
                processLocation(location)
            }
            .addOnFailureListener {
                Log.w(TAG, "Location failed: ${it.message}")
            }
    }

    private fun processLocation(location: Location) {
        val results = FloatArray(1)
        Location.distanceBetween(officeLat, officeLng, location.latitude, location.longitude, results)
        val distance = results[0].toDouble()

        val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
        val isActiveTime = hour >= startHour
        val isLeaving = distance > threshold

        if (isActiveTime && isLeaving && !alerted) {
            alerted = true
            NotificationHelper.showAlert(this)
            startAlertReminder()
            if (autoLaunch) {
                launchApp(FXIAOKE_PACKAGE)
            }
        }

        if (alerted) {
            if (isAppUsedRecently(FXIAOKE_PACKAGE, 2)) {
                alerted = false
                stopAlertReminder()
                NotificationHelper.cancelAlert(this)
            }
        }

        val status = when {
            !isActiveTime -> "waiting"
            alerted -> "alert"
            else -> "monitoring"
        }

        // 更新前台通知
        val notifText = when (status) {
            "waiting" -> "等待激活（${startHour}:00后）| 距公司 ${distance.toInt()}米"
            "alert" -> "请打卡！| 距公司 ${distance.toInt()}米"
            else -> "监控中 | 距公司 ${distance.toInt()}米"
        }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        nm.notify(NotificationHelper.FOREGROUND_ID,
            NotificationHelper.buildForegroundNotification(this, notifText))

        // 回调给 Flutter UI
        statusCallback?.invoke(mapOf(
            "distance" to distance,
            "lat" to location.latitude,
            "lng" to location.longitude,
            "triggered" to (alerted && isActiveTime),
            "status" to status
        ))
    }

    private fun isAppUsedRecently(packageName: String, minutes: Int): Boolean {
        return try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val now = System.currentTimeMillis()
            val start = now - minutes * 60 * 1000L
            val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, now)
            stats.any { it.packageName == packageName && it.lastTimeUsed >= start }
        } catch (e: Exception) {
            false
        }
    }

    private fun launchApp(packageName: String) {
        try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Launch app failed: ${e.message}")
        }
    }

    private fun startAlertReminder() {
        stopAlertReminder()
        alertRunnable = object : Runnable {
            override fun run() {
                NotificationHelper.showAlert(this@MonitorService)
                handler.postDelayed(this, 60_000L)
            }
        }
        handler.postDelayed(alertRunnable!!, 60_000L)
    }

    private fun stopAlertReminder() {
        alertRunnable?.let { handler.removeCallbacks(it) }
        alertRunnable = null
    }
}
