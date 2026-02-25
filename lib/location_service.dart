import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

class LocationService {
  static bool _alerted = false;
  static const String _fxiaoxiaokePackage = 'com.facishare.fs';
  static const _channel = MethodChannel('com.example.punch_reminder/usage');

  /// 初始化后台服务（App 启动时调用一次）
  static Future<void> initService() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'punch_reminder_bg',
        initialNotificationTitle: '打卡提醒',
        initialNotificationContent: '监控中...',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
      ),
    );
  }

  /// 后台服务入口
  @pragma('vm:entry-point')
  static Future<void> _onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    await NotificationService.init();

    Timer? checkTimer;

    service.on('stop').listen((_) {
      checkTimer?.cancel();
      _stopPersistentReminder();
      service.stopSelf();
    });

    service.on('updateConfig').listen((_) async {
      // 配置更新时重启定时器
      checkTimer?.cancel();
      final prefs = await SharedPreferences.getInstance();
      final interval = prefs.getInt('interval_seconds') ?? 30;
      checkTimer = Timer.periodic(Duration(seconds: interval), (_) => _bgCheck(service));
      _bgCheck(service);
    });

    service.on('dismissAlert').listen((_) {
      _alerted = false;
      _stopPersistentReminder();
    });

    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getInt('interval_seconds') ?? 30;

    checkTimer = Timer.periodic(Duration(seconds: interval), (_) => _bgCheck(service));
    _bgCheck(service);
  }

  /// 后台定位检测
  static Future<void> _bgCheck(ServiceInstance service) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final officeLat = prefs.getDouble('office_lat');
      final officeLng = prefs.getDouble('office_lng');
      final threshold = prefs.getDouble('threshold') ?? 50;
      final startHour = prefs.getInt('start_hour') ?? 19;
      final autoLaunch = prefs.getBool('auto_launch') ?? false;

      if (officeLat == null || officeLng == null) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      final distance = Geolocator.distanceBetween(
        officeLat, officeLng, pos.latitude, pos.longitude,
      );
      final now = DateTime.now();
      final isActiveTime = now.hour >= startHour;
      final isLeaving = distance > threshold;

      if (isActiveTime && isLeaving && !_alerted) {
        _alerted = true;
        _startPersistentReminder();
        // autoLaunch 和 UsageStats 检测通过 invoke 发给前台处理
        if (autoLaunch) {
          service.invoke('launchApp');
        }
      }

      if (_alerted) {
        // 通知前台检查纷享销客是否已打开
        service.invoke('checkApp');
      }

      // 发送状态给前台 UI
      service.invoke('update', {
        'distance': distance,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'triggered': _alerted && isActiveTime,
      });
    } catch (_) {}
  }

  /// 检查使用情况访问权限
  static Future<bool> checkUsagePermission() async {
    try {
      return await _channel.invokeMethod<bool>('checkPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳转到使用情况访问设置
  static Future<void> grantUsagePermission() async {
    try {
      await _channel.invokeMethod('grantPermission');
    } catch (_) {}
  }

  static Future<bool> isFxiaokeOpened() async {
    try {
      return await _channel.invokeMethod<bool>('isAppUsedRecently', {
        'packageName': _fxiaoxiaokePackage,
        'minutes': 2,
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> launchFxiaoke() async {
    try {
      await _channel.invokeMethod('launchApp', {
        'packageName': _fxiaoxiaokePackage,
      });
    } catch (_) {}
  }

  static Timer? _reminderTimer;

  static void _startPersistentReminder() {
    NotificationService.showReminder();
    _reminderTimer?.cancel();
    _reminderTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      NotificationService.showReminder();
    });
  }

  static void _stopPersistentReminder() {
    _reminderTimer?.cancel();
    _reminderTimer = null;
    NotificationService.cancelReminder();
  }

  /// 启动后台监控
  static Future<void> startMonitoring() async {
    _alerted = false;
    final service = FlutterBackgroundService();
    await service.startService();
  }

  /// 停止后台监控
  static Future<void> stopMonitoring() async {
    _alerted = false;
    final service = FlutterBackgroundService();
    service.invoke('stop');
    _stopPersistentReminder();
  }

  /// 通知后台服务配置已更新
  static void notifyConfigUpdate() {
    final service = FlutterBackgroundService();
    service.invoke('updateConfig');
  }

  /// 前台通知后台：纷享销客已打开，停止提醒
  static void dismissAlert() {
    _alerted = false;
    _stopPersistentReminder();
    final service = FlutterBackgroundService();
    service.invoke('dismissAlert');
  }

  /// 监听后台要求启动纷享销客
  static Stream<Map<String, dynamic>?> get onLaunchApp {
    final service = FlutterBackgroundService();
    return service.on('launchApp');
  }

  /// 监听后台要求检查纷享销客
  static Stream<Map<String, dynamic>?> get onCheckApp {
    final service = FlutterBackgroundService();
    return service.on('checkApp');
  }

  /// 监听后台服务状态更新
  static Stream<Map<String, dynamic>?> get onUpdate {
    final service = FlutterBackgroundService();
    return service.on('update');
  }

  /// 服务是否在运行
  static Future<bool> isRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }
}
