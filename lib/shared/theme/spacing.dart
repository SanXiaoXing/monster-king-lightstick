/// 统一间距系统（对齐 docs/design/ui_layout_rules.md 第 1 节）。
///
/// 全项目间距是一套固定"乐高"，不要随手写 13 / 17 / 23。
/// 外层容器左右 [pageMargin]、卡片内 [cardPadding] 是铁律；
/// 垂直节奏用 [gap12]（紧）/ [gap16]（松）两档，不要混用其它值。
class Spacing {
  Spacing._();

  /// 页面左右页边距。
  static const double pageMargin = 20;

  /// 卡片内边距（普通）。
  static const double cardPadding = 16;

  /// 列表项之间（紧）。
  static const double gap12 = 12;

  /// 卡片 / 区块之间（松）。
  static const double gap16 = 16;

  /// 卡片内部行间距 / 字段之间。
  static const double gap10 = 10;

  /// 小元素间距（胶囊内 / 按钮间）。
  static const double gap8 = 8;

  /// 字段标签 → 控件。
  static const double gap6 = 6;

  /// 标签内图标 ↔ 文字。
  static const double gap4 = 4;

  /// 滚动内容底部留白，容纳 FAB / 主创建按钮，避免被遮挡。
  static const double bottomSafe = 120;
}
