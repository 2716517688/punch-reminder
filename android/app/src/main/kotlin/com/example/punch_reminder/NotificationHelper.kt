package com.example.punch_reminder

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat

object NotificationHelper {
    const val CHANNEL_BG = "punch_reminder_bg"
    const val CHANNEL_ALERT = "punch_reminder_alert_v2"
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

            // 删除旧的 alert channel（如果存在）
            nm.deleteNotificationChannel("punch_reminder_alert")

            val alertChannel = NotificationChannel(
                CHANNEL_ALERT, "打卡提醒",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "下班打卡提醒"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                setSound(alarmUri, AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build())
                setBypassDnd(true)
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
        // 点击通知打开 App
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

        val notification = NotificationCompat.Builder(context, CHANNEL_ALERT)
            .setContentTitle("⏰ 别忘了打卡！")
            .setContentText("你已离开公司，请打开纷享销客打卡")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(pendingIntent)
            .setSound(alarmUri)
            .setVibrate(longArrayOf(0, 1000, 500, 1000, 500, 1000))
            .setDefaults(0) // 不用默认，用自定义的声音和震动
            .build()

        // 让通知使用 insistent 标志，持续响铃直到用户处理
        notification.flags = notification.flags or
            android.app.Notification.FLAG_INSISTENT or
            android.app.Notification.FLAG_NO_CLEAR

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(ALERT_ID, notification)
    }

    fun cancelAlert(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(ALERT_ID)
    }
}
