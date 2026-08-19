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
      pageBuilder: (_, _, _) => page,
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
