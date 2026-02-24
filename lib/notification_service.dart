import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'punch_reminder';
  static const _channelName = '打卡提醒';
  static const _reminderId = 1;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);

    // 创建高优先级通知渠道
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: '下班打卡提醒',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    _initialized = true;
  }

  static Future<void> showReminder() async {
    if (!_initialized) await init();
    const details = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '下班打卡提醒',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ongoing: true,
      autoCancel: false,
      ticker: '打卡提醒',
    );
    await _plugin.show(
      _reminderId,
      '⏰ 别忘了打卡！',
      '你已离开公司，请打开纷享销客打卡',
      const NotificationDetails(android: details),
    );
  }

  static Future<void> cancelReminder() async {
    await _plugin.cancel(_reminderId);
  }
}
