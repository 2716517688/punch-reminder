import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'monitor_channel.dart';
import 'settings_page.dart';
import 'heater_service.dart';

void _log(String tag, String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  final line = '[$ts] $tag: $msg';
  debugPrint(line);
  dev.log(msg, name: tag);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _log('App', 'main() started');
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

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  double? _officeLat;
  double? _officeLng;
  double _threshold = 50;
  int _startHour = 19;
  int _intervalSeconds = 30;
  bool _autoLaunch = false;
  bool _monitoring = false;
  String _status = '未启动';
  double? _currentDistance;
  StreamSubscription? _statusSub;
  Timer? _distanceTimer;
  DateTime? _lastEventChannelUpdate;
  DateTime? _lastDistancePoll;
  int _eventChannelCount = 0;
  int _distancePollCount = 0;
  String _lastProvider = '';
  bool _punchedToday = false;
  double _batteryTemp = -1;
  bool _heating = false;
  bool _heaterEnabled = false;
  double _heaterTrigger = HeaterService.defaultTriggerTemp;
  StreamSubscription? _heaterSub;

  @override
  void initState() {
    super.initState();
    _log('HomePage', 'initState()');
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _listenStatus();
    _initHeater();
  }

  @override
  void dispose() {
    _log('HomePage', 'dispose()');
    WidgetsBinding.instance.removeObserver(this);
    _statusSub?.cancel();
    _distanceTimer?.cancel();
    _heaterSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log('Lifecycle', 'state=$state');
    if (state == AppLifecycleState.resumed && !_monitoring) {
      _log('Lifecycle', 'App resumed (not monitoring), refreshing distance');
      _updateDistance();
    }
  }

  void _listenStatus() {
    _log('EventChannel', 'subscribing to statusStream');
    _statusSub = MonitorChannel.statusStream.listen((data) {
      _eventChannelCount++;
      _lastEventChannelUpdate = DateTime.now();
      _log('EventChannel', '#$_eventChannelCount data=$data');
      if (!mounted) {
        _log('EventChannel', 'widget not mounted, skipping');
        return;
      }
      setState(() {
        _currentDistance = (data['distance'] as num?)?.toDouble();
        _lastProvider = 'EventChannel';
        final status = data['status'] as String? ?? 'monitoring';
        final triggered = data['triggered'] as bool? ?? false;
        _log('EventChannel', 'distance=$_currentDistance status=$status triggered=$triggered');
        _punchedToday = data['punchedToday'] as bool? ?? _punchedToday;
        switch (status) {
          case 'waiting':
            _status = '等待激活（${_startHour}:00后）';
            break;
          case 'alert':
            _status = '请打卡！';
            break;
          default:
            _status = '监听中';
        }
      });
    }, onError: (e) {
      _log('EventChannel', 'ERROR: $e');
    }, onDone: () {
      _log('EventChannel', 'stream closed');
    });
  }

  Future<void> _initHeater() async {
    _heaterEnabled = await HeaterService.getEnabled();
    _heaterTrigger = await HeaterService.getTriggerTemp();
    _heaterSub = HeaterService.stream.listen((data) {
      if (!mounted) return;
      final temp = (data['temperature'] as num?)?.toDouble() ?? -1;
      final heating = data['heating'] as bool? ?? false;
      setState(() {
        _batteryTemp = temp;
        _heating = heating;
      });
      _autoHeaterControl(temp, heating);
    });
  }

  void _autoHeaterControl(double temp, bool heating) {
    if (!_heaterEnabled || temp < 0) return;
    if (temp <= _heaterTrigger && !heating) {
      _log('Heater', 'temp=${temp}°C <= trigger=${_heaterTrigger}°C, starting');
      HeaterService.startHeating();
    } else if (temp >= HeaterService.targetTemp && heating) {
      _log('Heater', 'temp=${temp}°C >= target=${HeaterService.targetTemp}°C, stopping');
      HeaterService.stopHeating();
    }
  }

  Future<void> _loadSettings() async {
    _log('Settings', 'loading...');
    final prefs = await SharedPreferences.getInstance();
    final running = await MonitorChannel.isRunning();
    _log('Settings', 'isRunning=$running');
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
    _log('Settings', 'office=($_officeLat,$_officeLng) threshold=$_threshold startHour=$_startHour interval=${_intervalSeconds}s autoLaunch=$_autoLaunch');
    // 监听中时依赖 Service 推送，不启动 Flutter 端定时器和主动轮询
    if (!_monitoring) {
      _updateDistance();
      _startDistanceTimer();
    } else {
      _distanceTimer?.cancel();
      _log('DistanceTimer', 'skipped: Service is running, using EventChannel');
    }
    // 主动查询今日是否已签退
    try {
      final punched = await MonitorChannel.checkPunchedToday(_startHour);
      _log('Settings', 'checkPunchedToday=$punched');
      if (punched != _punchedToday) {
        setState(() { _punchedToday = punched; });
      }
    } catch (e) {
      _log('Settings', 'checkPunchedToday error: $e');
    }
    // 刷新加热设置
    _heaterEnabled = await HeaterService.getEnabled();
    _heaterTrigger = await HeaterService.getTriggerTemp();
  }

  void _startDistanceTimer() {
    _distanceTimer?.cancel();
    final interval = _intervalSeconds > 0 ? _intervalSeconds : 30;
    _log('DistanceTimer', 'starting with interval=${interval}s');
    _distanceTimer = Timer.periodic(Duration(seconds: interval), (_) {
      _log('DistanceTimer', 'tick, updating distance');
      _updateDistance();
    });
  }

  Future<void> _updateDistance() async {
    if (_officeLat == null || _officeLng == null) {
      _log('Distance', 'skip: no office coords');
      return;
    }
    _distancePollCount++;
    _log('Distance', 'poll #$_distancePollCount requesting position...');
    final sw = Stopwatch()..start();
    try {
      final perm = await Permission.location.status;
      _log('Distance', 'location permission=$perm');
      if (!perm.isGranted) {
        _log('Distance', 'permission not granted, skip');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      sw.stop();
      _log('Distance', 'got position in ${sw.elapsedMilliseconds}ms: lat=${pos.latitude} lng=${pos.longitude} accuracy=${pos.accuracy}m');
      final distance = Geolocator.distanceBetween(
        _officeLat!, _officeLng!, pos.latitude, pos.longitude,
      );
      _lastDistancePoll = DateTime.now();
      _log('Distance', 'calculated distance=${distance.toStringAsFixed(1)}m');
      if (!mounted) return;
      setState(() {
        _currentDistance = distance;
        _lastProvider = 'Geolocator';
      });
    } catch (e) {
      sw.stop();
      _log('Distance', 'ERROR after ${sw.elapsedMilliseconds}ms: $e');
      // Fallback: try last known position
      try {
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null) {
          final distance = Geolocator.distanceBetween(
            _officeLat!, _officeLng!, lastPos.latitude, lastPos.longitude,
          );
          _log('Distance', 'fallback lastKnown: lat=${lastPos.latitude} lng=${lastPos.longitude} distance=${distance.toStringAsFixed(1)}m');
          _lastDistancePoll = DateTime.now();
          if (!mounted) return;
          setState(() {
            _currentDistance = distance;
            _lastProvider = 'LastKnown';
          });
        } else {
          _log('Distance', 'fallback: no last known position');
        }
      } catch (e2) {
        _log('Distance', 'fallback ERROR: $e2');
      }
    }
  }

  Future<bool> _checkPermissions() async {
    _log('Permissions', 'checking...');
    var locPerm = await Permission.location.status;
    _log('Permissions', 'location=$locPerm');
    if (!locPerm.isGranted) {
      locPerm = await Permission.location.request();
      _log('Permissions', 'location after request=$locPerm');
      if (!locPerm.isGranted) {
        _showSnack('需要位置权限');
        return false;
      }
    }
    var bgPerm = await Permission.locationAlways.status;
    _log('Permissions', 'locationAlways=$bgPerm');
    if (!bgPerm.isGranted) {
      bgPerm = await Permission.locationAlways.request();
      _log('Permissions', 'locationAlways after request=$bgPerm');
      if (!bgPerm.isGranted) {
        _showSnack('需要后台位置权限（始终允许）');
        return false;
      }
    }
    var notifPerm = await Permission.notification.status;
    _log('Permissions', 'notification=$notifPerm');
    if (!notifPerm.isGranted) {
      notifPerm = await Permission.notification.request();
    }
    var batteryPerm = await Permission.ignoreBatteryOptimizations.status;
    _log('Permissions', 'battery=$batteryPerm');
    if (!batteryPerm.isGranted) {
      batteryPerm = await Permission.ignoreBatteryOptimizations.request();
    }
    final usageGranted = await MonitorChannel.checkUsagePermission();
    _log('Permissions', 'usageStats=$usageGranted');
    if (!usageGranted) {
      await MonitorChannel.grantUsagePermission();
      _showSnack('请在设置中允许「使用情况访问」权限');
    }
    _log('Permissions', 'all checks done');
    return true;
  }

  Future<void> _startMonitoring({bool silent = false}) async {
    _log('Monitor', 'startMonitoring called');
    if (_officeLat == null || _officeLng == null) {
      _log('Monitor', 'no office coords, abort');
      _showSnack('请先在设置中标定公司坐标');
      return;
    }
    if (!await _checkPermissions()) return;
    _log('Monitor', 'calling native startMonitor');
    await MonitorChannel.startMonitor();
    _distanceTimer?.cancel();
    _log('DistanceTimer', 'stopped: Service takes over');
    setState(() {
      _monitoring = true;
      _status = '监听中';
    });
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('monitoring', true);
    _log('Monitor', 'started successfully');
    if (!silent) _showSnack('开始监听');
  }

  Future<void> _stopMonitoring() async {
    _log('Monitor', 'stopMonitoring called');
    await MonitorChannel.stopMonitor();
    setState(() {
      _monitoring = false;
      _status = '未启动';
      _currentDistance = null;
    });
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('monitoring', false);
    _log('Monitor', 'stopped, restarting distance timer');
    _startDistanceTimer();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _openSettings() async {
    _log('Nav', 'opening settings');
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SettingsPage(
        officeLat: _officeLat,
        officeLng: _officeLng,
        threshold: _threshold,
        startHour: _startHour,
        intervalSeconds: _intervalSeconds,
        autoLaunch: _autoLaunch,
        punchedToday: _punchedToday,
      )),
    );
    _log('Nav', 'returned from settings, reloading');
    await _loadSettings();
    if (_monitoring) {
      await MonitorChannel.reloadConfig();
      _log('Nav', 'reloaded native config');
    }
  }
  String _debugInfo() {
    final ecAge = _lastEventChannelUpdate != null
        ? '${DateTime.now().difference(_lastEventChannelUpdate!).inSeconds}s ago'
        : 'never';
    final pollAge = _lastDistancePoll != null
        ? '${DateTime.now().difference(_lastDistancePoll!).inSeconds}s ago'
        : 'never';
    return 'EC: #$_eventChannelCount ($ecAge)\n'
        'Poll: #$_distancePollCount ($pollAge)\n'
        'Source: $_lastProvider\n'
        'Interval: ${_intervalSeconds}s';
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
        title: const Text('打卡提醒 [DEBUG]'),
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
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor.withOpacity(0.15),
                ),
                child: Icon(statusIcon, size: 64, color: statusColor),
              ),
              const SizedBox(height: 24),
              Text(_status,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: statusColor)),
              const SizedBox(height: 8),
              if (_currentDistance != null)
                Text('距公司 ${_currentDistance!.toStringAsFixed(0)} 米',
                  style: TextStyle(fontSize: 16, color: Colors.grey[400])),
              if (_batteryTemp >= 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _heating
                        ? '🔥 ${_batteryTemp.toStringAsFixed(1)}°C 加热中'
                        : '🌡️ ${_batteryTemp.toStringAsFixed(1)}°C',
                    style: TextStyle(
                      fontSize: 14,
                      color: _heating ? Colors.orange : Colors.grey[500],
                    ),
                  ),
                ),
              if (!configured)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('请先在设置中标定公司坐标',
                    style: TextStyle(fontSize: 14, color: Colors.orange[300])),
                ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber, width: 1),
                ),
                child: Text(_debugInfo(),
                  style: const TextStyle(fontSize: 12, color: Colors.amber, fontFamily: 'monospace')),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 200, height: 56,
                child: ElevatedButton(
                  onPressed: _monitoring ? _stopMonitoring : () => _startMonitoring(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _monitoring ? Colors.red[700] : Colors.green[700],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: Text(_monitoring ? '停止' : '开始监听',
                    style: const TextStyle(fontSize: 20, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
