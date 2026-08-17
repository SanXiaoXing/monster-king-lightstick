import 'package:flutter/material.dart';

import '../../domain/device_state.dart';

/// 设备状态卡片：展示蓝牙适配器状态 + 连接状态 + 当前设备。
class DeviceStatusCard extends StatelessWidget {
  const DeviceStatusCard({super.key, required this.status});

  final BluetoothStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(
              theme,
              icon: Icons.bluetooth,
              label: '蓝牙',
              value: _adapterLabel(status.adapter),
              color: status.adapter == BluetoothAdapterState.on
                  ? Colors.green
                  : theme.colorScheme.error,
            ),
            const SizedBox(height: 8),
            _row(
              theme,
              icon: Icons.link,
              label: '连接',
              value: _connectionLabel(status.connection),
              color: status.isConnected ? Colors.green : theme.colorScheme.error,
            ),
            if (status.deviceName != null) ...[
              const SizedBox(height: 8),
              _row(
                theme,
                icon: Icons.devices,
                label: '设备',
                value: status.deviceName!,
                color: theme.colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text('$label：', style: theme.textTheme.bodyMedium),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _adapterLabel(BluetoothAdapterState s) => switch (s) {
        BluetoothAdapterState.unknown => '未知',
        BluetoothAdapterState.unsupported => '不支持',
        BluetoothAdapterState.unauthorized => '未授权',
        BluetoothAdapterState.off => '已关闭',
        BluetoothAdapterState.turningOn => '正在打开…',
        BluetoothAdapterState.on => '已开启',
        BluetoothAdapterState.turningOff => '正在关闭…',
      };

  String _connectionLabel(DeviceConnectionState s) => switch (s) {
        DeviceConnectionState.disconnected => '未连接',
        DeviceConnectionState.connecting => '连接中…',
        DeviceConnectionState.connected => '已连接',
        DeviceConnectionState.disconnecting => '断开中…',
        DeviceConnectionState.error => '连接错误',
      };
}
