import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'notification_service.dart';

class LocationService {
  static Timer? _checkTimer;
  static bool _alerted = false;

  static void startMonitoring({
    required double officeLat,
    required double officeLng,
    required double thresholdMeters,
    required int startHour,
    required void Function(double distance, Position pos, bool triggered) onUpdate,
  }) {
    stopMonitoring();
    _alerted = false;

    // 每30秒检查一次位置
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

      // 如果回到公司范围内，重置提醒
      if (!isLeaving && _alerted) {
        _alerted = false;
        _stopPersistentReminder();
      }

      onUpdate(distance, pos, isActiveTime && isLeaving);
    } catch (_) {}
  }

  static Timer? _reminderTimer;

  static void _startPersistentReminder() {
    // 立即发一次通知
    NotificationService.showReminder();
    // 然后每60秒重复提醒
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
