# 000 — 自定义推页转场：AppRouter 接入「淡入 + 微移」过渡

- **Status**: DONE（2026-08-19 已实施，`flutter analyze lib` 0 问题；executor diff 经逐字核对）
- **Commit**: 0d466b8
- **Severity**: MEDIUM
- **Category**: Cohesion & tokens / Missed opportunities（转场词汇统一）
- **Estimated scope**: 1 文件（`lib/app/router/app_router.dart`），约 20 行改动

## Problem

`AppRouter.page<T>()` 目前直接返回 `MaterialPageRoute`，转场由平台默认决定：
Android M3 是 `ZoomPageTransitionBuilder`（缩放 + 淡入，且会通过 `secondaryAnimation`
让底层路由一起动），iOS 是原生侧滑。两者都不是本 App 的既定页面切换词汇。

本 App 的页面级切换词汇表（唯一锚点）在 `home_page.dart:66-87`：
Dock Tab 切换 = `AnimatedOpacity` + `AnimatedSlide`，`Curves.easeOutCubic`、
`320ms`、位移 `Offset(±0.06, 0)`，且 `disableAnimations` 时 `Duration.zero`。
推页转场与 Tab 切换是同一类「页面切换」，必须说同一种语言。

现状代码（`lib/app/router/app_router.dart:1-13`，逐字）：

```dart
import 'package:flutter/material.dart';

/// 集中路由表：页面跳转统一走这里，不手写 MaterialPageRoute。
///
/// `ponytail:` 页面不多，暂不引 go_router；需要深链/嵌套导航时再升级。
class AppRouter {
  AppRouter._();

  /// 通用推页入口。
  static Route<T> page<T>(Widget page) {
    return MaterialPageRoute<T>(builder: (_) => page);
  }
}
```

唯一调用点今天只有 `settings_page.dart:35`（`Navigator.push(AppRouter.page(const TipsPage()))`），
但 `AppRouter.page` 是**全 App 唯一推页入口**，改这一处，所有未来推页自动继承同一转场。

## Target

`page<T>()` 改为 `PageRouteBuilder`，转场 = 淡入 + 从 `Offset(0.06, 0)`（推入方向）滑入，
与 `home_page._buildPage` 完全同源。退出（pop）走同一 builder 反向执行（`reverseTransitionDuration`）。
减少动态（`MediaQuery.disableAnimations`）时不做任何过渡、瞬时切换——对齐
`home_page.dart:68,76-82` 与 `glass_tab_bar.dart:194-199` 已确立的仓库惯例（不重新争论该决策）。

目标代码（整文件替换后）：

```dart
import 'package:flutter/material.dart';

/// 集中路由表：页面跳转统一走这里，不手写 MaterialPageRoute。
///
/// `ponytail:` 页面不多，暂不引 go_router；需要深链/嵌套导航时再升级。
class AppRouter {
  AppRouter._();

  /// 通用推页入口：与主页 Tab 切换同源的「淡入 + 朝推入方向微移」转场。
  /// 词汇表对齐 home_page._buildPage：Curves.easeOutCubic、320ms、Offset(±0.06, 0)。
  /// 减少动态（disableAnimations）时瞬时切换，不做任何过渡。
  static Route<T> page<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final reduceMotion =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        if (reduceMotion) return child;
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position:
                Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
                    .animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}
```

数值来源（AUDIT.md，不得近似）：
- 进入 → `ease-out`（`Curves.easeOutCubic` 即仓库既有 ease-out 曲线，非新发明）。
- 页面级（模态/抽屉类）时长 200–500ms 预算内：入场取仓库既有 `320ms`，出场取 `200ms`。
- 位移取仓库既有 `Offset(±0.06, 0)`，不硬编码像素。

## Repo conventions to follow

- 页面切换词汇表锚点：`lib/features/home/presentation/pages/home_page.dart:66-87`——`AnimatedOpacity` + `AnimatedSlide`、`Curves.easeOutCubic`、`Duration(milliseconds: 320)`、`Offset(±0.06, 0)`。本计划是它的推页同构，不要另造曲线或时长。
- 减少动态惯例：`home_page.dart:68`（`MediaQuery.maybeOf(context)?.disableAnimations`）与 `glass_tab_bar.dart:194-199`（`didChangeDependencies` 里读取）——仓库已定型为「直接去掉运动」，本计划照此执行（`if (reduceMotion) return child;`）。
- 路由集中入口惯例：`lib/app/router/app_router.dart` 头注释已声明「页面跳转统一走这里，不手写 MaterialPageRoute」，本改动延续该约定。

## Steps

1. 打开 `lib/app/router/app_router.dart`。保留 import、类注释与 `AppRouter._()` 不变，仅把 `page<T>()` 方法体（现第 10–12 行 `return MaterialPageRoute<T>(builder: (_) => page);`）整体替换为上节 Target 的 `PageRouteBuilder` 版本。`pageBuilder` 用 `(_, __, ___) => page`，确保 `T` 泛型不变（调用点无需改动）。
2. 不要动 `secondaryAnimation`——有意不用它：底层路由在推页期间保持静止（Android 默认 builder 会让底层路由缩放淡出，与本 App 的克制感不符）。不要把"未使用参数"当 lint 报错改掉。
3. 运行 `flutter analyze`，确认 0 问题后完成。

## Boundaries

- 只改 `lib/app/router/app_router.dart` 一个文件。`plans/` 下的文档不算。
- 不要碰 `home_page.dart` 的 Tab 切换（已正确）、`glass_tab_bar.dart`、`sliding_segment.dart`。
- 不要引入 go_router 或任何新依赖（`pubspec.yaml` 不动）。
- 不要改 `AppRouter.page<T>` 的签名与调用点（今日唯一调用点 `settings_page.dart:35` 应原样通过编译）。
- 不要动 `TipsPage` 及其导航逻辑、不要加 Hero。
- 若打开文件后发现与上述摘录不一致（自 commit `0d466b8` 以来有漂移），**停下来汇报**，不要即兴改。

## Verification

- **Mechanical**: 在仓库根目录运行 `flutter analyze`，预期 0 issues（repo 使用 `flutter_lints ^6.0.0`）。可选 `flutter test`——`test/widget_test.dart` 会构建整个 App，应保持通过（无路由相关测试，不新增测试）。
- **Feel check**: 运行 App →「设置」Tab → 点「温馨提示」推页，确认：
  - 新页面**淡入的同时从右侧 6% 滑入**，320ms 内先快后慢（`easeOutCubic` 起速感），与 Dock Tab 切换的手感一致，而非 Android 默认的居中放大。
  - 返回（pop）在 200ms 内反向滑出，进出路径对称、方向一致。
  - 快速连点 推→退→推：转场可被打断并重定向，不跳变（`PageRouteBuilder` 的 `animation` 由框架管理，天然可中断）。
  - 系统开启「移除动画」（或 `adb shell settings put secure animator_duration_scale 0`）：推页/退页**瞬时切换**，无任何位移或闪烁。
- **Done when**: `flutter analyze` 0 问题；推页/退页手感匹配 320/200ms + `easeOutCubic` + `0.06` 词汇表；减少动态下瞬时切换；Android 与 iOS 表现一致（此前 Android 是 zoom-fade、iOS 是原生侧滑，现在统一）。
