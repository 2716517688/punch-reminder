import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HeaterService {
  static const _method = MethodChannel('com.example.punch_reminder/heater');
  static const _event = EventChannel('com.example.punch_reminder/heater_status');

  static const double defaultTriggerTemp = 5.0;
  static const double targetTemp = 15.0;

  static StreamController<Map<String, dynamic>>? _controller;
  static StreamSubscription? _eventSub;

  /// 共享广播流，多个页面可同时监听
  static Stream<Map<String, dynamic>> get stream {
    if (_controller == null) {
      _controller = StreamController<Map<String, dynamic>>.broadcast();
      _eventSub = _event.receiveBroadcastStream().listen(
        (e) => _controller?.add(Map<String, dynamic>.from(e)),
        onError: (e, st) => _controller?.addError(e, st),
      );
    }
    return _controller!.stream;
  }

  static Future<double> getTemperature() async {
    final t = await _method.invokeMethod<double>('getTemperature');
    return t ?? -1.0;
  }

  static Future<void> startHeating() => _method.invokeMethod('startHeating');
  static Future<void> stopHeating() => _method.invokeMethod('stopHeating');
  static Future<bool> isHeating() async =>
      await _method.invokeMethod<bool>('isHeating') ?? false;

  // 设置读写
  static Future<bool> getEnabled() async =>
      (await SharedPreferences.getInstance()).getBool('heater_enabled') ?? false;

  static Future<void> setEnabled(bool v) async =>
      (await SharedPreferences.getInstance()).setBool('heater_enabled', v);

  static Future<double> getTriggerTemp() async =>
      (await SharedPreferences.getInstance()).getDouble('heater_trigger_temp') ?? defaultTriggerTemp;

  static Future<void> setTriggerTemp(double v) async =>
      (await SharedPreferences.getInstance()).setDouble('heater_trigger_temp', v);
}
