import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'location_service.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
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
      _showSnack('标定成功: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}');
    } catch (e) {
      setState(() => _status = '标定失败: $e');
    }
  }

  Future<void> _startMonitoring({bool silent = false}) async {
    if (_officeLat == null || _officeLng == null) {
      _showSnack('请先标定公司坐标');
      return;
    }
    if (!await _checkPermissions()) return;

    setState(() {
      _monitoring = true;
      _status = '监听中（$_startHour:00 后激活）';
    });
    await _saveSettings();

    LocationService.startMonitoring(
      officeLat: _officeLat!,
      officeLng: _officeLng!,
      thresholdMeters: _threshold,
      startHour: _startHour,
      onUpdate: (distance, pos, triggered) {
        if (!mounted) return;
        setState(() {
          _currentDistance = distance;
          final now = DateTime.now();
          if (now.hour < _startHour) {
            _status = '等待中（$_startHour:00 后激活），距公司 ${distance.toStringAsFixed(0)}m';
          } else if (triggered) {
            _status = '⚠️ 已离开公司 ${distance.toStringAsFixed(0)}m，请打卡！';
          } else {
            _status = '监听中，距公司 ${distance.toStringAsFixed(0)}m';
          }
        });
      },
    );

    if (!silent) _showSnack('开始监听');
  }

  void _stopMonitoring() {
    LocationService.stopMonitoring();
    setState(() {
      _monitoring = false;
      _status = '已停止';
      _currentDistance = null;
    });
    _saveSettings();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('打卡提醒')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      _monitoring ? Icons.location_on : Icons.location_off,
                      size: 48,
                      color: _monitoring ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    Text(_status, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16)),
                    if (_officeLat != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '公司: ${_officeLat!.toStringAsFixed(6)}, ${_officeLng!.toStringAsFixed(6)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _calibrateOffice,
              icon: const Icon(Icons.my_location),
              label: Text(_officeLat == null ? '标定公司坐标' : '重新标定'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('离开阈值: '),
                Expanded(
                  child: Slider(
                    value: _threshold,
                    min: 50, max: 500, divisions: 9,
                    label: '${_threshold.toInt()}m',
                    onChanged: (v) => setState(() => _threshold = v),
                    onChangeEnd: (_) => _saveSettings(),
                  ),
                ),
                Text('${_threshold.toInt()}m'),
              ],
            ),
            Row(
              children: [
                const Text('激活时间: '),
                Expanded(
                  child: Slider(
                    value: _startHour.toDouble(),
                    min: 17, max: 22, divisions: 5,
                    label: '$_startHour:00',
                    onChanged: (v) => setState(() => _startHour = v.toInt()),
                    onChangeEnd: (_) => _saveSettings(),
                  ),
                ),
                Text('$_startHour:00后'),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _monitoring ? _stopMonitoring : _startMonitoring,
              icon: Icon(_monitoring ? Icons.stop : Icons.play_arrow),
              label: Text(_monitoring ? '停止监听' : '开始监听'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: _monitoring ? Colors.red[700] : Colors.green[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
