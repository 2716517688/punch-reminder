package com.example.punch_reminder

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat

object NotificationHelper {
    const val CHANNEL_BG = "punch_reminder_bg"
    const val CHANNEL_ALERT = "punch_reminder_alert"
    const val FOREGROUND_ID = 888
    const val ALERT_ID = 1

    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val bgChannel = NotificationChannel(
                CHANNEL_BG, "打卡提醒后台服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "后台定位监控服务"
                setSound(null, null)
                enableVibration(false)
            }

            val alertChannel = NotificationChannel(
                CHANNEL_ALERT, "打卡提醒",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "下班打卡提醒"
                enableVibration(true)
            }

            nm.createNotificationChannel(bgChannel)
            nm.createNotificationChannel(alertChannel)
        }
    }

    fun buildForegroundNotification(context: Context, text: String): android.app.Notification {
        return NotificationCompat.Builder(context, CHANNEL_BG)
            .setContentTitle("打卡提醒")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    fun showAlert(context: Context) {
        val notification = NotificationCompat.Builder(context, CHANNEL_ALERT)
            .setContentTitle("⏰ 别忘了打卡！")
            .setContentText("你已离开公司，请打开纷享销客打卡")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(ALERT_ID, notification)
    }

    fun cancelAlert(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(ALERT_ID)
    }
}
