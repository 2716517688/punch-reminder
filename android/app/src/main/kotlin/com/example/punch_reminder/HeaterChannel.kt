package com.example.punch_reminder

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

object HeaterChannel {
    private const val METHOD = "com.example.punch_reminder/heater"
    private const val EVENT = "com.example.punch_reminder/heater_status"

    private val heating = AtomicBoolean(false)
    private var workers: List<Thread> = emptyList()
    private var eventSink: EventChannel.EventSink? = null
    private var monitorThread: Thread? = null

    fun register(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getTemperature" -> result.success(getBatteryTemp(context))
                    "startHeating" -> { startHeating(context); result.success(true) }
                    "stopHeating" -> { stopHeating(); result.success(true) }
                    "isHeating" -> result.success(heating.get())
                    else -> result.notImplemented()
                }
            }

        EventChannel(engine.dartExecutor.binaryMessenger, EVENT)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    startMonitor(context)
                }
                override fun onCancel(args: Any?) {
                    eventSink = null
                    stopMonitor()
                }
            })
    }

    private fun getBatteryTemp(context: Context): Double {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val raw = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
        return if (raw > 0) raw / 10.0 else -1.0
    }

    private fun startHeating(context: Context) {
        if (heating.getAndSet(true)) return
        val cores = Runtime.getRuntime().availableProcessors().coerceAtMost(4)
        workers = (1..cores).map {
            thread(name = "heater-$it", isDaemon = true) {
                while (heating.get()) {
                    // CPU 密集浮点运算
                    var x = 1.0
                    for (i in 0 until 1_000_000) { x = Math.sin(x) * Math.cos(x) + 1.0 }
                }
            }
        }
    }

    private fun stopHeating() {
        heating.set(false)
        workers = emptyList()
    }

    private fun startMonitor(context: Context) {
        stopMonitor()
        monitorThread = thread(name = "heater-monitor", isDaemon = true) {
            while (eventSink != null) {
                try {
                    val temp = getBatteryTemp(context)
                    val data = mapOf("temperature" to temp, "heating" to heating.get())
                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                        eventSink?.success(data)
                    }
                    Thread.sleep(3000)
                } catch (_: InterruptedException) { break }
            }
        }
    }

    private fun stopMonitor() {
        monitorThread?.interrupt()
        monitorThread = null
    }
}
