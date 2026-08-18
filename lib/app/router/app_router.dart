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
