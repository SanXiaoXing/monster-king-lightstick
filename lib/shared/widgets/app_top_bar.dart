import 'package:flutter/material.dart';

/// 统一顶栏（项目约定版，对齐 docs/design/ui_layout_rules.md 第 2 节的"所有页面统一用
/// AppTopBar，不要自己写 Row 顶栏"这一核心要求）。
///
/// 与文档的差异（已与用户确认保留项目风格）：
/// - 标题**左对齐 26/w700**（取自 [ThemeData.appBarTheme]，不强制文档的居中 18/w800）。
/// - 操作按钮统一用 [AppIconButton]（36×36，见下），左侧返回亦同。
///
/// 用法：[Scaffold(appBar: AppTopBar(title: '...', actions: [AppIconButton(...)]))]。
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.centerTitle = false,
  });

  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    // 其余样式来自 ThemeData.appBarTheme（bg=surface、标题 26/w700）。
    return AppBar(
      leading: leading,
      title: Text(title),
      centerTitle: centerTitle,
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
