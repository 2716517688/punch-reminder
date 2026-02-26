package com.example.punch_reminder

import android.app.Service
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log

class MonitorService : Service() {
    companion object {
        const val TAG = "MonitorService"
        const val PREFS_NAME = "FlutterSharedPreferences"
        const val FXIAOKE_PACKAGE = "com.facishare.fs"

        var statusCallback: ((Map<String, Any>) -> Unit)? = null
        var isRunning = false
            private set
    }

    private lateinit var locationManager: LocationManager
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
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(
            NotificationHelper.FOREGROUND_ID,
            NotificationHelper.buildForegroundNotification(this, "监控中...")
        )
        loadConfig()
        startChecking()
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
        val allPrefs = prefs.getAll()
        Log.d(TAG, "loadConfig: all keys=${allPrefs.keys}")
        Log.d(TAG, "loadConfig: raw office_lat=${allPrefs["flutter.office_lat"]} (${allPrefs["flutter.office_lat"]?.javaClass?.simpleName})")
        Log.d(TAG, "loadConfig: raw office_lng=${allPrefs["flutter.office_lng"]} (${allPrefs["flutter.office_lng"]?.javaClass?.simpleName})")
        officeLat = getDouble("flutter.office_lat", 0.0)
        officeLng = getDouble("flutter.office_lng", 0.0)
        threshold = getDouble("flutter.threshold", 50.0)
        startHour = prefs.getLong("flutter.start_hour", 19).toInt()
        intervalSeconds = prefs.getLong("flutter.interval_seconds", 30).toInt()
        autoLaunch = prefs.getBoolean("flutter.auto_launch", false)
        Log.d(TAG, "loadConfig: office=($officeLat,$officeLng) threshold=$threshold startHour=$startHour interval=${intervalSeconds}s autoLaunch=$autoLaunch")
    }

    private fun getDouble(key: String, default: Double): Double {
        return try {
            val value = prefs.getAll()[key]
            when (value) {
                is Double -> value
                is Float -> value.toDouble()
                is Long -> Double.fromBits(value)
                is String -> value.toDoubleOrNull() ?: default
                else -> default
            }
        } catch (e: Exception) {
            default
        }
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
        if (officeLat == 0.0 && officeLng == 0.0) {
            Log.d(TAG, "doCheck: no office coordinates")
            return
        }
        Log.d(TAG, "doCheck: requesting location...")

        // 优先用 GPS，fallback 到 Network
        val providers = mutableListOf<String>()
        if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            providers.add(LocationManager.GPS_PROVIDER)
        }
        if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
            providers.add(LocationManager.NETWORK_PROVIDER)
        }

        if (providers.isEmpty()) {
            Log.w(TAG, "doCheck: no location provider available")
            // 尝试用最后已知位置
            val lastLoc = getLastKnownLocation()
            if (lastLoc != null) {
                processLocation(lastLoc)
            }
            return
        }

        var gotLocation = false
        val timeoutRunnable = Runnable {
            if (!gotLocation) {
                Log.w(TAG, "doCheck: location timeout, using last known")
                val lastLoc = getLastKnownLocation()
                if (lastLoc != null) processLocation(lastLoc)
            }
        }
        handler.postDelayed(timeoutRunnable, 10_000L)

        for (provider in providers) {
            try {
                locationManager.requestSingleUpdate(provider, object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        if (!gotLocation) {
                            gotLocation = true
                            handler.removeCallbacks(timeoutRunnable)
                            Log.d(TAG, "doCheck: got location from $provider: ${location.latitude}, ${location.longitude}")
                            processLocation(location)
                        }
                    }
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                    override fun onProviderEnabled(provider: String) {}
                    override fun onProviderDisabled(provider: String) {}
                }, Looper.getMainLooper())
            } catch (e: Exception) {
                Log.w(TAG, "doCheck: $provider request failed: ${e.message}")
            }
        }
    }

    @Suppress("MissingPermission")
    private fun getLastKnownLocation(): Location? {
        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER)
        var best: Location? = null
        for (p in providers) {
            try {
                val loc = locationManager.getLastKnownLocation(p)
                if (loc != null && (best == null || loc.time > best.time)) {
                    best = loc
                }
            } catch (_: Exception) {}
        }
        return best
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

        val notifText = when (status) {
            "waiting" -> "等待激活（${startHour}:00后）| 距公司 ${distance.toInt()}米"
            "alert" -> "请打卡！| 距公司 ${distance.toInt()}米"
            else -> "监控中 | 距公司 ${distance.toInt()}米"
        }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        nm.notify(NotificationHelper.FOREGROUND_ID,
            NotificationHelper.buildForegroundNotification(this, notifText))

        Log.d(TAG, "processLocation: distance=${distance.toInt()}m status=$status callback=${statusCallback != null}")
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