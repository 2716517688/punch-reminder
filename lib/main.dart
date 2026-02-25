import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'location_service.dart';
import 'notification_service.dart';
import 'settings_page.dart';

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
  double _threshold = 50;
  int _startHour = 19;
  int _intervalSeconds = 30;
  bool _autoLaunch = false;
  bool _monitoring = false;
  String _status = '未启动';
  double? _currentDistance;
  StreamSubscription<Map<String, dynamic>?>? _updateSub;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _listenUpdates();
  }

  @override
  void dispose() {
    _updateSub?.cancel();
    super.dispose();
  }

  void _listenUpdates() {
    _updateSub = LocationService.onUpdate.listen((data) {
      if (data == null || !mounted) return;
      setState(() {
        _currentDistance = data['distance'] as double?;
        final triggered = data['triggered'] as bool? ?? false;
        final now = DateTime.now();
        if (now.hour < _startHour) {
          _status = '等待激活（${_startHour}:00后）';
        } else if (triggered) {
          _status = '请打卡！';
        } else {
          _status = '监听中';
        }
      });
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final running = await LocationService.isRunning();
    setState(() {
      _officeLat = prefs.getDouble('office_lat');
      _officeLng = prefs.getDouble('office_lng');
      _threshold = prefs.getDouble('threshold') ?? 50;
      _startHour = prefs.getInt('start_hour') ?? 19;
      _intervalSeconds = prefs.getInt('interval_seconds') ?? 30;
      _autoLaunch = prefs.getBool('auto_launch') ?? false;
      _monitoring = running;
      if (_monitoring) _status = '监听中';
    });
  }

  Future<bool> _checkPermissions() async {
    var locPerm = await Permission.location.status;
    if (!locPerm.isGranted) {
      locPerm = await Permission.location.request();
      if (!locPerm.isGranted) {
        _showSnack('需要位置权限');
        return false;
      }
    }
    var bgPerm = await Permission.locationAlways.status;
    if (!bgPerm.isGranted) {
      bgPerm = await Permission.locationAlways.request();
      if (!bgPerm.isGranted) {
        _showSnack('需要后台位置权限（始终允许）');
        return false;
      }
    }
    var notifPerm = await Permission.notification.status;
    if (!notifPerm.isGranted) {
      notifPerm = await Permission.notification.request();
    }
    var batteryPerm = await Permission.ignoreBatteryOptimizations.status;
    if (!batteryPerm.isGranted) {
      batteryPerm = await Permission.ignoreBatteryOptimizations.request();
    }
    final usageGranted = await LocationService.checkUsagePermission();
    if (!usageGranted) {
      await LocationService.grantUsagePermission();
      _showSnack('请在设置中允许「使用情况访问」权限');
    }
    return true;
  }

  Future<void> _startMonitoring({bool silent = false}) async {
    if (_officeLat == null || _officeLng == null) {
      _showSnack('请先在设置中标定公司坐标');
      return;
    }
    if (!await _checkPermissions()) return;

    await LocationService.startMonitoring();
    setState(() {
      _monitoring = true;
      _status = '监听中';
    });
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('monitoring', true);

    if (!silent) _showSnack('开始监听');
  }

  Future<void> _stopMonitoring() async {
    await LocationService.stopMonitoring();
    setState(() {
      _monitoring = false;
      _status = '未启动';
      _currentDistance = null;
    });
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('monitoring', false);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _openSettings() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SettingsPage(
        officeLat: _officeLat,
        officeLng: _officeLng,
        threshold: _threshold,
        startHour: _startHour,
        intervalSeconds: _intervalSeconds,
        autoLaunch: _autoLaunch,
      )),
    );
    await _loadSettings();
    if (_monitoring) {
      LocationService.notifyConfigUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool configured = _officeLat != null;
    final Color statusColor;
    final IconData statusIcon;

    if (!_monitoring) {
      statusColor = Colors.grey;
      statusIcon = Icons.location_off;
    } else if (_status == '请打卡！') {
      statusColor = Colors.red;
      statusIcon = Icons.warning_rounded;
    } else {
      statusColor = Colors.green;
      statusIcon = Icons.shield;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('打卡提醒'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor.withOpacity(0.15),
                ),
                child: Icon(statusIcon, size: 64, color: statusColor),
              ),
              const SizedBox(height: 24),
              Text(
                _status,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: statusColor),
              ),
              const SizedBox(height: 8),
              if (_currentDistance != null)
                Text(
                  '距公司 ${_currentDistance!.toStringAsFixed(0)} 米',
                  style: TextStyle(fontSize: 16, color: Colors.grey[400]),
                ),
              if (!configured)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '请先在设置中标定公司坐标',
                    style: TextStyle(fontSize: 14, color: Colors.orange[300]),
                  ),
                ),
              const SizedBox(height: 48),
              SizedBox(
                width: 200,
                height: 56,
                child: ElevatedButton(
                  onPressed: _monitoring ? _stopMonitoring : () => _startMonitoring(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _monitoring ? Colors.red[700] : Colors.green[700],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Text(
                    _monitoring ? '停止' : '开始监听',
                    style: const TextStyle(fontSize: 20, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
