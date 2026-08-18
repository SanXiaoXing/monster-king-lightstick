// 主页冒烟测试：渲染、菜单跳转、主题跟随系统。
//
// 测试环境没有蓝牙插件（flutter_blue_plus 未注册），
// DeviceViewModel 的异常会走 onError 分支，不阻塞渲染。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wanshou/app/app.dart';

void main() {
  testWidgets('主页渲染与菜单导航', (WidgetTester tester) async {
    await tester.pumpWidget(const App());
    await tester.pump();

    // 主页元素
    expect(find.text('万兽之王'), findsOneWidget);
    expect(find.text('MONSTER KING'), findsOneWidget);
    expect(find.text('连接设备'), findsOneWidget);
    expect(find.text('调色盘'), findsOneWidget);
    expect(find.text('温馨提示'), findsOneWidget);

    // 进入温馨提示页（菜单在视口下方，先滚动到可见）
    await tester.ensureVisible(find.text('温馨提示'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('温馨提示'));
    await tester.pumpAndSettle();
    expect(find.text('请勿直视强光'), findsOneWidget);

    // 返回主页
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('万兽之王'), findsOneWidget);

    // 卸载以释放主页时钟定时器
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('手机视口下逐页巡检（无溢出/无异常）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 音乐调光页有循环旋转动画，pumpAndSettle 永不收敛，统一用定长 pump
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(const App());
    await tester.pump();

    // 巡检各功能页
    for (final label in ['连接设备', '座位绑定', '调色盘', '音乐调光', '设置']) {
      await tester.ensureVisible(find.text(label));
      await settle();
      await tester.tap(find.text(label));
      await settle();
      // 页面应已打开且无布局异常
      expect(tester.takeException(), isNull, reason: '$label 页不应抛异常');
      await tester.pageBack();
      await settle();
    }

    // 设置 → 灯光效果
    await tester.ensureVisible(find.text('设置'));
    await settle();
    await tester.tap(find.text('设置'));
    await settle();
    await tester.ensureVisible(find.text('灯光效果模式'));
    await settle();
    await tester.tap(find.text('灯光效果模式'));
    await settle();
    expect(find.text('选择灯光效果模式'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });
}
