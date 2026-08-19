// 主页冒烟测试：渲染、导航栏 Tab 切换、逐页巡检。
//
// 测试环境没有蓝牙插件（flutter_blue_plus 未注册），
// DeviceViewModel 的异常会走 onError 分支，不阻塞渲染。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wanshou/app/app.dart';

void main() {
  // 音乐页可视化 Ticker 仅在监听时运行；统一用定长 pump 巡检，
  // 不依赖 pumpAndSettle 收敛，避免任何残留动画导致超时。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('主页渲染与导航栏 Tab 切换', (WidgetTester tester) async {
    await tester.pumpWidget(const App());
    await settle(tester);

    // Dock 四个 Tab
    for (final label in ['连接', '调色', '音乐', '设置']) {
      expect(find.text(label), findsWidgets);
    }

    // 默认在连接页
    expect(find.text('附近设备'), findsOneWidget);

    // 切到音乐页
    await tester.tap(find.text('音乐'));
    await settle(tester);
    expect(find.text('音乐律动'), findsOneWidget);

    // 切到调色页
    await tester.tap(find.text('调色'));
    await settle(tester);
    expect(find.text('调色盘'), findsOneWidget);

    // 卸载以释放页面资源
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('手机视口下逐页巡检（无溢出/无异常）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const App());
    await settle(tester);

    // 逐 Tab 巡检
    for (final label in ['连接', '调色', '音乐', '设置']) {
      await tester.tap(find.text(label));
      await settle(tester);
      // 页面应已打开且无布局异常
      expect(tester.takeException(), isNull, reason: '$label 页不应抛异常');
    }

    await tester.pumpWidget(const SizedBox());
  });
}
