import 'dart:async';
import 'package:flutter/material.dart';
import 'heater_service.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  bool _heaterEnabled = false;
  double _triggerTemp = HeaterService.defaultTriggerTemp;
  double _currentTemp = -1;
  bool _heating = false;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = HeaterService.stream.listen((data) {
      if (!mounted) return;
      setState(() {
        _currentTemp = (data['temperature'] as num?)?.toDouble() ?? -1;
        _heating = data['heating'] as bool? ?? false;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final enabled = await HeaterService.getEnabled();
    final trigger = await HeaterService.getTriggerTemp();
    final heating = await HeaterService.isHeating();
    final temp = await HeaterService.getTemperature();
    setState(() {
      _heaterEnabled = enabled;
      _triggerTemp = trigger;
      _heating = heating;
      _currentTemp = temp;
    });
  }

  Future<void> _toggleHeater(bool v) async {
    await HeaterService.setEnabled(v);
    if (!v) await HeaterService.stopHeating();
    setState(() => _heaterEnabled = v);
  }

  Future<void> _setTrigger(double v) async {
    await HeaterService.setTriggerTemp(v);
    setState(() => _triggerTemp = v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('辅助工具')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 自动加热开关
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('自动加热',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    _heating ? '🔥 加热中 · ${_currentTemp.toStringAsFixed(1)}°C'
                        : _currentTemp >= 0 ? '当前 ${_currentTemp.toStringAsFixed(1)}°C'
                        : '等待温度数据...',
                    style: TextStyle(fontSize: 12, color: _heating ? Colors.orange : Colors.grey[500]),
                  ),
                  value: _heaterEnabled,
                  onChanged: _toggleHeater,
                ),
                if (_heaterEnabled) Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('触发温度: ${_triggerTemp.toStringAsFixed(0)}°C',
                          style: const TextStyle(fontSize: 14)),
                      Slider(
                        value: _triggerTemp,
                        min: 0, max: 15, divisions: 15,
                        label: '${_triggerTemp.toStringAsFixed(0)}°C',
                        onChanged: (v) => setState(() => _triggerTemp = v),
                        onChangeEnd: (v) => _setTrigger(v),
                      ),
                      Text('低于此温度开始加热，升至15°C后停止',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 后续工具在这里加 Card 即可
        ],
      ),
    );
  }
}
