// 行为验证测试：驱动真实页面与状态流转，断言输出结果。
//
// 覆盖：主题切换（跟随系统/浅色/深色）、FX 选择往返、调色盘取色数学
// （色相→hex）、亮度滑杆、连接守卫、座位绑定、音乐响应开关。
//
// 未连接路径用真实 DeviceRepository（插件缺失走 onError 分支）；
// 已连接路径用 _FakeRepo 子类伪造蓝牙状态，验证连接后行为。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wanshou/app/app.dart';
import 'package:wanshou/app/theme/app_theme.dart';
import 'package:wanshou/features/audio/presentation/pages/music_page.dart';
import 'package:wanshou/features/device/data/device_repository.dart';
import 'package:wanshou/features/device/domain/device_state.dart';
import 'package:wanshou/features/device/domain/lightstick.dart';
import 'package:wanshou/features/device/presentation/device_view_model.dart';
import 'package:wanshou/features/device/presentation/pages/device_page.dart';
import 'package:wanshou/features/lighting/presentation/pages/color_picker_page.dart';
import 'package:wanshou/features/lighting/presentation/pages/fx_page.dart';
import 'package:wanshou/features/lighting/presentation/pages/seat_binding_page.dart';
import 'package:wanshou/features/settings/settings_page.dart';

/// 伪造仓库：蓝牙开启；connected=true 时上报一台已连接设备。
class _FakeRepo extends DeviceRepository {
  _FakeRepo({required this.connected});

  final bool connected;

  @override
  Stream<BluetoothAdapterState> get adapterState =>
      Stream.value(BluetoothAdapterState.on);

  @override
  Future<List<Lightstick>> connectedDevices() async => connected
      ? const [Lightstick(address: 'AA:BB:CC:DD:EE:FF', name: '万兽之王 · 应援棒')]
      : const [];

  @override
  Stream<DeviceConnectionState> connectionStateOf(Lightstick device) =>
      Stream.value(DeviceConnectionState.connected);
}

Future<DeviceViewModel> _vm({required bool connected}) async {
  final vm = DeviceViewModel(_FakeRepo(connected: connected));
  await vm.init();
  return vm;
}

Widget _wrap(Widget home) =>
    MaterialApp(theme: buildLightTheme(), home: home);

void main() {
  setUp(() => themeModeNotifier.value = ThemeMode.system);

  testWidgets('主题切换：设置页三档切换驱动 MaterialApp 重建', (tester) async {
    await tester.pumpWidget(const App());
    await tester.pump();

    // 进入设置页
    await tester.ensureVisible(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    ThemeData theme() => Theme.of(tester.element(find.byType(SettingsPage)));

    // 默认跟随系统（测试环境平台亮度为浅色）
    expect(app().themeMode, ThemeMode.system);
    expect(theme().brightness, Brightness.light);

    // 切深色
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.dark);
    expect(theme().brightness, Brightness.dark);

    // 切浅色
    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.light);
    expect(theme().brightness, Brightness.light);

    // 回跟随系统
    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.system);
    expect(theme().brightness, Brightness.light);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('FX 往返：选模式+速度 → 应用 → 设置页摘要与提示更新', (tester) async {
    final vm = await _vm(connected: true);
    addTearDown(vm.dispose);
    await tester.pumpWidget(_wrap(SettingsPage(viewModel: vm)));
    await tester.pump();

    // 进入灯光效果页
    await tester.ensureVisible(find.text('灯光效果模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('灯光效果模式'));
    await tester.pumpAndSettle();
    expect(find.text('选择灯光效果模式'), findsOneWidget);

    // 首行网格直接可见：先选呼吸灯
    await tester.tap(find.text('呼吸灯'));
    await tester.pump();
    // 滑杆在列表下方（懒构建），向上滚动后再断言默认 50%
    await tester.drag(find.byType(FxPage), const Offset(0, -300));
    await tester.pump();
    expect(find.text('50%'), findsOneWidget);
    await tester.tap(find.text('应用效果'));
    await tester.pumpAndSettle();

    // 回到设置页：摘要更新 + 提示
    expect(find.text('当前：呼吸灯'), findsOneWidget);
    expect(find.text('✓ 灯光效果已应用：呼吸灯 速度 50%'), findsOneWidget);
  });

  testWidgets('调色盘：默认 #FF38D3，预设精确命中，色环取色数学正确', (tester) async {
    final vm = await _vm(connected: true);
    addTearDown(vm.dispose);
    await tester.pumpWidget(_wrap(ColorPickerPage(viewModel: vm)));
    await tester.pump();

    // 默认荧光粉
    expect(find.text('#FF38D3'), findsOneWidget);

    // 预设星蓝 → 精确 #48B9FF
    await tester.ensureVisible(find.text('星蓝'));
    await tester.pump();
    await tester.tap(find.text('星蓝'));
    await tester.pump();
    expect(find.text('#48B9FF'), findsOneWidget);

    // 色环取色：点击正下方（相对圆心角度 90°）
    // HSV(90°, S=1, V=1) = RGB(128,255,0) = #80FF00
    final wheelRect = tester.getRect(find.byType(AspectRatio));
    final target =
        wheelRect.center + Offset(0, wheelRect.height * 0.25);
    final g = await tester.startGesture(target);
    await g.moveBy(const Offset(0, 1));
    await g.up();
    await tester.pump();
    expect(find.text('#80FF00'), findsOneWidget);

    // 亮度滑杆左拉 → hex 变暗，不再是满饱和色
    await tester.drag(find.byType(Slider), const Offset(-120, 0));
    await tester.pump();
    expect(find.text('100%'), findsNothing); // 亮度标签不再 100%
    expect(find.text('#80FF00'), findsNothing);
  });

  testWidgets('连接守卫：未连接时应用颜色 → 提示并跳转连接页', (tester) async {
    final vm = await _vm(connected: false);
    addTearDown(vm.dispose);
    await tester.pumpWidget(_wrap(ColorPickerPage(viewModel: vm)));
    await tester.pump();

    await tester.ensureVisible(find.text('应用颜色'));
    await tester.pump();
    await tester.tap(find.text('应用颜色'));
    await tester.pumpAndSettle();

    expect(find.text('请先完成蓝牙连接'), findsOneWidget);
    // 已推入设备连接页
    expect(find.text('连接设备'), findsOneWidget);
    expect(find.byType(DevicePage), findsOneWidget);
  });

  testWidgets('座位绑定：区域+座位号 → 绑定成功提示', (tester) async {
    final vm = await _vm(connected: true);
    addTearDown(vm.dispose);
    await tester.pumpWidget(_wrap(SeatBindingPage(viewModel: vm)));
    await tester.pump();

    await tester.ensureVisible(find.text('看台 B 区'));
    await tester.pump();
    await tester.tap(find.text('看台 B 区'));
    await tester.pump();
    await tester.ensureVisible(find.text('绑定座位'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'A区 12排 08号');
    await tester.tap(find.text('绑定座位'));
    await tester.pump();

    expect(find.text('✓ 座位已绑定：看台 B 区 A区 12排 08号'), findsOneWidget);
  });

  testWidgets('音乐调光：连接后点击切换 响应/暂停 状态', (tester) async {
    final vm = await _vm(connected: true);
    addTearDown(vm.dispose);
    await tester.pumpWidget(_wrap(MusicPage(viewModel: vm)));
    await tester.pump();

    // 默认响应中（旋转动画持续调度帧）
    expect(find.text('Ⅱ　音乐响应中'), findsOneWidget);

    // 点击暂停：文案切换，动画停止（pumpAndSettle 可收敛）
    await tester.tap(find.text('Ⅱ　音乐响应中'));
    await tester.pump();
    expect(find.text('▶　音乐响应已暂停'), findsOneWidget);
    await tester.pumpAndSettle();

    // 再次点击恢复
    await tester.tap(find.text('▶　音乐响应已暂停'));
    await tester.pump();
    expect(find.text('Ⅱ　音乐响应中'), findsOneWidget);
  });

  testWidgets('音乐调光：未连接时点击 → 守卫提示，不切换状态', (tester) async {
    final vm = await _vm(connected: false);
    addTearDown(vm.dispose);
    await tester.pumpWidget(_wrap(MusicPage(viewModel: vm)));
    await tester.pump();

    await tester.tap(find.text('Ⅱ　音乐响应中'));
    // 唱片动画持续旋转，pumpAndSettle 不收敛，用定长 pump
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('请先完成蓝牙连接'), findsOneWidget);
    // 状态未变（音乐页被推入的连接页覆盖为 offstage，需显式查找）
    expect(find.text('Ⅱ　音乐响应中', skipOffstage: false), findsOneWidget);
    expect(find.byType(DevicePage), findsOneWidget);
  });
}
