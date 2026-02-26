import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:punch_reminder/main.dart';
import 'package:punch_reminder/settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Mock MonitorChannel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.example.punch_reminder/monitor'),
      (MethodCall call) async {
        switch (call.method) {
          case 'isRunning':
            return false;
          case 'checkUsagePermission':
            return true;
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

  group('HomePage', () {
    testWidgets('shows app title', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const PunchReminderApp());
      await tester.pumpAndSettle();
      expect(find.text('打卡提醒'), findsOneWidget);
    });

    testWidgets('shows initial status as 未启动', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const PunchReminderApp());
      await tester.pumpAndSettle();
      expect(find.text('未启动'), findsOneWidget);
    });

    testWidgets('shows 开始监听 button when not monitoring', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const PunchReminderApp());
      await tester.pumpAndSettle();
      expect(find.text('开始监听'), findsOneWidget);
    });

    testWidgets('shows calibration hint when no office coords', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const PunchReminderApp());
      await tester.pumpAndSettle();
      expect(find.text('请先在设置中标定公司坐标'), findsOneWidget);
    });

    testWidgets('no calibration hint when office coords set', (tester) async {
      SharedPreferences.setMockInitialValues({
        'office_lat': 39.9,
        'office_lng': 116.4,
      });
      await tester.pumpWidget(const PunchReminderApp());
      await tester.pumpAndSettle();
      expect(find.text('请先在设置中标定公司坐标'), findsNothing);
    });

    testWidgets('tapping 开始监听 without coords shows snackbar', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const PunchReminderApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始监听'));
      await tester.pumpAndSettle();
      expect(find.text('请先在设置中标定公司坐标'), findsWidgets);
    });

    testWidgets('settings icon navigates to SettingsPage', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const PunchReminderApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      expect(find.text('设置'), findsOneWidget);
    });
  });

  group('SettingsPage', () {
    testWidgets('shows 未标定 when no coords', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(home: SettingsPage()),
      );
      await tester.pumpAndSettle();
      expect(find.text('未标定'), findsOneWidget);
      expect(find.text('标定公司坐标'), findsOneWidget);
    });

    testWidgets('shows coords when provided', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsPage(officeLat: 39.900000, officeLng: 116.400000),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('39.900000, 116.400000'), findsOneWidget);
      expect(find.text('重新标定'), findsOneWidget);
    });

    testWidgets('shows default threshold 50m', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(home: SettingsPage()),
      );
      await tester.pumpAndSettle();
      expect(find.text('离开阈值: 50 米'), findsOneWidget);
    });

    testWidgets('shows default start hour 19:00', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(home: SettingsPage()),
      );
      await tester.pumpAndSettle();
      expect(find.text('激活时间: 19:00 后'), findsOneWidget);
    });

    testWidgets('shows custom settings values', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsPage(
            threshold: 80,
            startHour: 20,
            intervalSeconds: 60,
            autoLaunch: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('离开阈值: 80 米'), findsOneWidget);
      expect(find.text('激活时间: 20:00 后'), findsOneWidget);
      expect(find.text('坐标刷新间隔: 1分钟'), findsOneWidget);
    });

    testWidgets('auto launch switch exists', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(home: SettingsPage()),
      );
      await tester.pumpAndSettle();
      // Drag the ListView down to reveal the switch
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.textContaining('纷享销客'), findsWidgets);
    });

    testWidgets('back button returns to previous page', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
              child: const Text('Go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(find.text('设置'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Go'), findsOneWidget);
    });
  });
}
