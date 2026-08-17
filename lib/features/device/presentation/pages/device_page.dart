import 'package:flutter/material.dart';

import '../../data/device_repository.dart';
import '../../domain/lightstick.dart';
import '../device_view_model.dart';
import '../widgets/device_status_card.dart';

/// 设备连接页（初始界面）。
///
/// 顶部状态卡实时显示蓝牙/连接状态，主按钮一键扫描并连接宝宝剑，
/// 下方列出扫描到的设备供手动选择。
class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  late final DeviceViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = DeviceViewModel(DeviceRepository())..init();
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _onPrimaryPressed() async {
    if (_vm.status.isConnected) {
      await _vm.disconnect();
      return;
    }
    // 未连接：先扫描，发现设备则自动连接第一个
    await _vm.scan();
    if (_vm.devices.isNotEmpty) {
      await _vm.connect(_vm.devices.first);
    } else if (mounted && _vm.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未发现宝宝剑设备，请确认设备已开机并靠近')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('连接宝宝剑')),
      body: ListenableBuilder(
        listenable: _vm,
        builder: (context, _) {
          final status = _vm.status;
          final connected = status.isConnected;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DeviceStatusCard(status: status),
              const SizedBox(height: 24),
              // 主按钮：未连接时扫描并连接，已连接时断开
              FilledButton.icon(
                onPressed: _vm.scanning ? null : _onPrimaryPressed,
                icon: connected
                    ? const Icon(Icons.bluetooth_disabled)
                    : const Icon(Icons.bluetooth_searching),
                label: Text(connected ? '断开连接' : '连接蓝牙'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              if (_vm.scanning) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
              if (_vm.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _vm.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              Text('附近设备', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_vm.devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('点击"连接蓝牙"扫描附近宝宝剑', textAlign: TextAlign.center),
                )
              else
                ..._vm.devices.map(_deviceTile),
            ],
          );
        },
      ),
    );
  }

  Widget _deviceTile(Lightstick device) {
    final isActive = device.address == _vm.activeDevice?.address;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.light_mode),
        title: Text(device.name ?? '未命名设备'),
        subtitle: Text(
          '${device.address}${device.rssi != null ? '  ·  ${device.rssi} dBm' : ''}',
        ),
        trailing: isActive
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.chevron_right),
        onTap: isActive || _vm.scanning ? null : () => _vm.connect(device),
      ),
    );
  }
}
