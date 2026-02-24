import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'notification_service.dart';

class LocationService {
  static StreamSubscription<Position>? _positionSub;
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
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        final distance = Geolocator.distanceBetween(
          officeLat, officeLng, pos.latitude, pos.longitude,
        );
        final now = DateTime.now();
        final isActiveTime = now.hour >= startHour;
        final isLeaving = distance > thresholdMeters;

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
    });

    // 立即检查一次
    _checkTimer!.tick;
    _immediateCheck(officeLat, officeLng, thresholdMeters, startHour, onUpdate);
  }

  static Future<void> _immediateCheck(
    double officeLat, double officeLng, double threshold,
    int startHour, void Function(double, Position, bool) onUpdate,
  ) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final distance = Geolocator.distanceBetween(
        officeLat, officeLng, pos.latitude, pos.longitude,
      );
      final now = DateTime.now();
      onUpdate(distance, pos, now.hour >= startHour && distance > threshold);
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
    _positionSub?.cancel();
    _positionSub = null;
    _checkTimer?.cancel();
    _checkTimer = null;
    _stopPersistentReminder();
    _alerted = false;
  }
}
