import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:punch_reminder/monitor_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> log;

  setUp(() {
    log = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.example.punch_reminder/monitor'),
      (MethodCall call) async {
        log.add(call);
        switch (call.method) {
          case 'isRunning':
            return true;
          case 'checkUsagePermission':
            return false;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.example.punch_reminder/monitor'),
      null,
    );
  });

  test('startMonitor invokes native method', () async {
    await MonitorChannel.startMonitor();
    expect(log, hasLength(1));
    expect(log.first.method, 'startMonitor');
  });

  test('stopMonitor invokes native method', () async {
    await MonitorChannel.stopMonitor();
    expect(log, hasLength(1));
    expect(log.first.method, 'stopMonitor');
  });

  test('isRunning returns mocked value', () async {
    final result = await MonitorChannel.isRunning();
    expect(result, isTrue);
    expect(log.first.method, 'isRunning');
  });

  test('reloadConfig invokes native method', () async {
    await MonitorChannel.reloadConfig();
    expect(log, hasLength(1));
    expect(log.first.method, 'reloadConfig');
  });

  test('checkUsagePermission returns mocked value', () async {
    final result = await MonitorChannel.checkUsagePermission();
    expect(result, isFalse);
  });

  test('grantUsagePermission invokes native method', () async {
    await MonitorChannel.grantUsagePermission();
    expect(log, hasLength(1));
    expect(log.first.method, 'grantUsagePermission');
  });
}
