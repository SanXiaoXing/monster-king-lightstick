import 'package:flutter/material.dart';
import 'package:wanshou/src/rust/api/protocol.dart';

/// 协议验证页：用 buildPacket(2, FlashMob("0004ff")) 重建 LIGHT_FLASH_HEX，
/// 与 Rust 常量 lightFlashHex() 字节级对比，验证 Flutter→Rust→协议层端到端链路。
class ProtocolDemoPage extends StatefulWidget {
  const ProtocolDemoPage({super.key});

  @override
  State<ProtocolDemoPage> createState() => _ProtocolDemoPageState();
}

class _ProtocolDemoPageState extends State<ProtocolDemoPage> {
  String _result = '点击按钮验证协议层';
  bool _loading = false;

  Future<void> _verifyLightFlash() async {
    setState(() {
      _loading = true;
      _result = '验证中...';
    });
    try {
      final body = await lightingCommandBody(
        effect: LightingEffect.flashMob,
        colorHex: '0004ff',
        seed: 0,
      );
      final packet = await buildPacket(seq: 2, commandBodyHex: body);
      final golden = await lightFlashHex();
      final match = packet == golden;
      setState(() {
        _result =
            '重建: $packet\n金标准: $golden\n${match ? "[匹配] 协议层正确" : "[不匹配] 检查协议"}';
      });
    } catch (e) {
      setState(() {
        _result = '错误: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('腕带协议验证')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_result, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _verifyLightFlash,
                child: const Text('验证 LIGHT_FLASH_HEX'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
