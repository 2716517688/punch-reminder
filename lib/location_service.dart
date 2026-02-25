import 'dart:async';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'notification_service.dart';

class LocationService {
  static Timer? _checkTimer;
  static bool _alerted = false;
  static const String _fxiaoxiaokePackage = 'com.fxiaoke.sales';
  static const _channel = MethodChannel('com.example.punch_reminder/usage');

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

  /// 检测纷享销客最近几分钟内是否被使用过
  static Future<bool> _isFxiaoxiaokeOpened() async {
    try {
      return await _channel.invokeMethod<bool>('isAppUsedRecently', {
        'packageName': _fxiaoxiaokePackage,
        'minutes': 2,
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  static void startMonitoring({
    required double officeLat,
    required double officeLng,
    required double thresholdMeters,
    required int startHour,
    int intervalSeconds = 30,
    bool autoLaunch = false,
    required void Function(double distance, Position pos, bool triggered) onUpdate,
  }) {
    stopMonitoring();
    _alerted = false;

    _checkTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) async {
      await _doCheck(officeLat, officeLng, thresholdMeters, startHour, autoLaunch, onUpdate);
    });

    _doCheck(officeLat, officeLng, thresholdMeters, startHour, autoLaunch, onUpdate);
  }

  static Future<void> _doCheck(
    double officeLat, double officeLng, double threshold,
    int startHour, bool autoLaunch, void Function(double, Position, bool) onUpdate,
  ) async {
    try {
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
        if (autoLaunch) {
          _launchFxiaoxiaoke();
        }
      }

      if (_alerted) {
        final opened = await _isFxiaoxiaokeOpened();
        if (opened) {
          _alerted = false;
          _stopPersistentReminder();
        }
      }

      onUpdate(distance, pos, _alerted && isActiveTime);
    } catch (_) {}
  }

  static Future<void> _launchFxiaoxiaoke() async {
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

  static void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _stopPersistentReminder();
    _alerted = false;
  }
}
