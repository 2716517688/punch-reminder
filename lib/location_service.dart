import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:usage_stats/usage_stats.dart';
import 'notification_service.dart';

class LocationService {
  static Timer? _checkTimer;
  static bool _alerted = false;
  static const String _fxiaoxiaokePackage = 'com.fxiaoke.sales';

  static void startMonitoring({
    required double officeLat,
    required double officeLng,
    required double thresholdMeters,
    required int startHour,
    required void Function(double distance, Position pos, bool triggered) onUpdate,
  }) {
    stopMonitoring();
    _alerted = false;

    // 每30秒检查一次
    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _doCheck(officeLat, officeLng, thresholdMeters, startHour, onUpdate);
    });

    // 立即检查一次
    _doCheck(officeLat, officeLng, thresholdMeters, startHour, onUpdate);
  }

  static Future<void> _doCheck(
    double officeLat, double officeLng, double threshold,
    int startHour, void Function(double, Position, bool) onUpdate,
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
      }

      // 已触发提醒后，检测纷享销客是否打开
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

  /// 检测纷享销客最近2分钟内是否被使用过
  static Future<bool> _isFxiaoxiaokeOpened() async {
    try {
      final now = DateTime.now();
      final start = now.subtract(const Duration(minutes: 2));
      final stats = await UsageStats.queryUsageStats(start, now);
      for (final stat in stats) {
        if (stat.packageName == _fxiaoxiaokePackage) {
          final lastUsed = stat.lastTimeUsed;
          if (lastUsed != null) {
            final lastTime = DateTime.fromMillisecondsSinceEpoch(int.parse(lastUsed));
            if (lastTime.isAfter(start)) {
              return true;
            }
          }
        }
      }
    } catch (_) {}
    return false;
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
