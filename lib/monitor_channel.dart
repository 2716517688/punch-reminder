import 'package:flutter/services.dart';

class MonitorChannel {
  static const _method = MethodChannel('com.example.punch_reminder/monitor');
  static const _event = EventChannel('com.example.punch_reminder/status');

  static Future<void> startMonitor() async {
    await _method.invokeMethod('startMonitor');
  }

  static Future<void> stopMonitor() async {
    await _method.invokeMethod('stopMonitor');
  }

  static Future<bool> isRunning() async {
    return await _method.invokeMethod<bool>('isRunning') ?? false;
  }

  static Future<void> reloadConfig() async {
    await _method.invokeMethod('reloadConfig');
  }

  static Future<bool> checkUsagePermission() async {
    return await _method.invokeMethod<bool>('checkUsagePermission') ?? false;
  }

  static Future<void> grantUsagePermission() async {
    await _method.invokeMethod('grantUsagePermission');
  }

  /// Native → Flutter 状态流
  static Stream<Map<String, dynamic>> get statusStream {
    return _event.receiveBroadcastStream().map((data) {
      return Map<String, dynamic>.from(data as Map);
    });
  }
}
