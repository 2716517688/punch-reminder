import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'location_service.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  await LocationService.initService();
  runApp(const PunchReminderApp());
}

class PunchReminderApp extends StatelessWidget {
  const PunchReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '打卡提醒',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  double? _officeLat;
  double? _officeLng;
  double _threshold = 200;
  int _startHour = 19;
  bool _monitoring = false;
  String _status = '未启动';
  double? _currentDistance;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _officeLat = prefs.getDouble('office_lat');
      _officeLng = prefs.getDouble('office_lng');
      _threshold = prefs.getDouble('threshold') ?? 200;
      _startHour = prefs.getInt('start_hour') ?? 19;
      _monitoring = prefs.getBool('monitoring') ?? false;
    });
    if (_monitoring && _officeLat != null) {
      _startMonitoring(silent: true);
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (_officeLat != null) prefs.setDouble('office_lat', _officeLat!);
    if (_officeLng != null) prefs.setDouble('office_lng', _officeLng!);
    prefs.setDouble('threshold', _threshold);
    prefs.setInt('start_hour', _startHour);
    prefs.setBool('monitoring', _monitoring);
  }

  Future<bool> _checkPermissions() async {
    // 前台位置权限
    var locPerm = await Permission.location.status;
    if (!locPerm.isGranted) {
      locPerm = await Permission.location.request();
      if (!locPerm.isGranted) {
        _showSnack('需要位置权限');
        return false;
      }
    }

    // 后台位置权限
    var bgPerm = await Permission.locationAlways.status;
    if (!bgPerm.isGranted) {
      bgPerm = await Permission.locationAlways.request();
      if (!bgPerm.isGranted) {
        _showSnack('需要后台位置权限（始终允许）');
        return false;
      }
    }

    // 通知权限
    var notifPerm = await Permission.notification.status;
    if (!notifPerm.isGranted) {
      notifPerm = await Permission.notification.request();
    }

    // 请求忽略电池优化（小米/MIUI 关键）
    var batteryPerm = await Permission.ignoreBatteryOptimizations.status;
    if (!batteryPerm.isGranted) {
      batteryPerm = await Permission.ignoreBatteryOptimizations.request();
    }

    return true;
  }

  Future<void> _calibrateOffice() async {
    if (!await _checkPermissions()) return;
    setState(() => _status = '正在获取位置...');
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      setState(() {
        _officeLat = pos.latitude;
        _officeLng = pos.longitude;
        _status = '公司坐标已标定';
      });
      await _saveSettings();
      _showSnack(
        '标定成功: ${pos.latitude.toStringAsFixed(6)}, '
        '${pos.longitude.toStringAsFixed(6)}',
      );
    } catch (e) {
      setState(() => _status = '标定失败: $e');
    }
  }
