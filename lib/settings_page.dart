import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

class SettingsPage extends StatefulWidget {
  final double? officeLat;
  final double? officeLng;
  final double threshold;
  final int startHour;
  final int intervalSeconds;

  const SettingsPage({
    super.key,
    this.officeLat,
    this.officeLng,
    this.threshold = 50,
    this.startHour = 19,
    this.intervalSeconds = 30,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late double? _officeLat;
  late double? _officeLng;
  late double _threshold;
  late int _startHour;
  late int _intervalSeconds;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _officeLat = widget.officeLat;
    _officeLng = widget.officeLng;
    _threshold = widget.threshold;
    _startHour = widget.startHour;
    _intervalSeconds = widget.intervalSeconds;
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (_officeLat != null) prefs.setDouble('office_lat', _officeLat!);
    if (_officeLng != null) prefs.setDouble('office_lng', _officeLng!);
    prefs.setDouble('threshold', _threshold);
    prefs.setInt('start_hour', _startHour);
    prefs.setInt('interval_seconds', _intervalSeconds);
    _changed = true;
  }

  Future<void> _calibrateOffice() async {
    _showSnack('正在获取位置...');
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      setState(() {
        _officeLat = pos.latitude;
        _officeLng = pos.longitude;
      });
      await _saveSettings();
      _showSnack(
        '标定成功: ${pos.latitude.toStringAsFixed(6)}, '
        '${pos.longitude.toStringAsFixed(6)}',
      );
    } catch (e) {
      _showSnack('标定失败: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  String _intervalLabel(int seconds) {
    if (seconds < 60) return '${seconds}秒';
    return '${seconds ~/ 60}分钟';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _changed),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 公司坐标
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('公司坐标', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_officeLat != null)
                    Text(
                      '${_officeLat!.toStringAsFixed(6)}, ${_officeLng!.toStringAsFixed(6)}',
                      style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                    )
                  else
                    Text('未标定', style: TextStyle(color: Colors.orange[300])),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _calibrateOffice,
                      icon: const Icon(Icons.my_location),
                      label: Text(_officeLat == null ? '标定公司坐标' : '重新标定'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 离开阈值
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('离开阈值: ${_threshold.toInt()} 米',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Slider(
                    value: _threshold,
                    min: 0, max: 100, divisions: 10,
                    label: '${_threshold.toInt()}m',
                    onChanged: (v) => setState(() => _threshold = v),
                    onChangeEnd: (_) => _saveSettings(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 激活时间
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('激活时间: $_startHour:00 后',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Slider(
                    value: _startHour.toDouble(),
                    min: 17, max: 22, divisions: 5,
                    label: '$_startHour:00',
                    onChanged: (v) => setState(() => _startHour = v.toInt()),
                    onChangeEnd: (_) => _saveSettings(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 刷新间隔
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('坐标刷新间隔: ${_intervalLabel(_intervalSeconds)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Slider(
                    value: _intervalSeconds.toDouble(),
                    min: 10, max: 120, divisions: 11,
                    label: _intervalLabel(_intervalSeconds),
                    onChanged: (v) => setState(() => _intervalSeconds = v.toInt()),
                    onChangeEnd: (_) => _saveSettings(),
                  ),
                  Text('间隔越短越灵敏，但更耗电',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
