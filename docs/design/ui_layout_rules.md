> 本文定义 SnapClaim 界面"如何排布"的统一约定（间距、卡片、列表、表单、导航、对话框）。
> 与 `ui_display_rules.md`（状态/取色/刷新）互补；新增任何页面或组件前，先读这两份。

---

## 速查：一份标准页面的骨架

绝大多数页面（首页 / 历史 / 详情 / 编辑 / 我的）都是同一套骨架：

```
Scaffold(
  backgroundColor: c.bg,
  body: Column(
    children: [
      AppTopBar(title: '...'),              // 顶部栏（自带 SafeArea）
      Expanded(                             // 占满剩余高度，内部可滚动
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 120),  // 左右 20，底部 120 留给 FAB/底栏
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [ ... 卡片 / 列表 / 区块 ... ],
          ),
        ),
      ),
    ],
  ),
)
```

> 例外：底部三栏外壳 `MainShell` 用 `Stack` + `extendBody` 实现悬浮玻璃，不用此骨架（见第 8 节）。

---

# 1. 间距系统（节奏感的根基）

> 全项目间距是一套固定"乐高"，不要随手写 13、17、23。

| 用途 | 值 | 出现位置 |
|------|----|----------|
| 页面左右页边距 | `20` | 所有 `SingleChildScrollView`（左 20 右 20） |
| 卡片内边距（普通） | `16` | `claim_card` / `mine_row` 容器（`all(16)` 或 `symmetric(16,14)`） |
| 卡片内边距（汇总） | `18` | `SummaryCard` |
| 区块之间垂直间距 | `12` / `16` | 列表项之间 `12`；卡片之间 `16` |
| 卡片内部行间距 | `10` / `12` | 明细行之间 `10`；`SummaryCard` 标题→金额 `12` |
| 字段之间 | `16` / `20` | `FieldLabel`→控件 `6`；字段组之间 `20` |
| 小元素间距（图标↔文字） | `4` / `6` / `8` | 标签 `4`、胶囊内 `6`、按钮间 `8` |
| 滚动内容底部留白 | `120` | 容纳 FAB 与主创建按钮，避免被遮挡 |

规律：
- **外层容器左右 20**、**卡片内 16** 是铁律。
- 垂直节奏用 `12`（紧）/ `16`（松）两档，不要混用其它值。
- 列表项之间一律 `SizedBox(height: 12)`（见 `home_page.dart:123`、`history_page.dart:121`）。

---

# 2. 顶部栏 AppTopBar

> 所有页面顶部统一用 `AppTopBar`，不要自己写 Row 顶栏。

规则（`app_top_bar.dart`）：
- 结构：左槽 `leadingWidth` + 居中标题 `Expanded(center)` + 右槽 `trailingWidth`。
- 默认左右槽宽 **72**，保证标题居中；右侧放两个按钮时把 `trailingWidth` 提到 **88**（见 `detail_page.dart:77-78`）。
- 本身包 `SafeArea(bottom: false)`，左右内边距 `fromLTRB(20, 8, 20, 14)`。
- 标题字号：普通 `18`、首页用 `displayFont` 时 `20` 并加 `letterSpacing: 0.5`。
- 左侧返回用 `AppIconButton(icon: Icons.chevron_left)`；右侧操作按钮也用 `AppIconButton`（36×36，见下）。

`AppIconButton` 规格：
```
36 × 36，圆角 10，底色 c.bgSecondary，1px c.border，图标 c.fg
```

---

# 3. 卡片规范

> 普通卡片一律用 `cardDecoration(c)`（圆角 16 + 细边框），不要各自写 `BoxDecoration`。

三种用法：
1. **独立卡片容器**（`claim_card.dart`、`mine_page.dart` 各块）：
   ```dart
   Container(
     width: double.infinity,
     padding: const EdgeInsets.all(16),
     decoration: cardDecoration(c),
     child: ...,
   )
   ```
2. **可点击卡片**（`claim_card.dart`）：外层 `Material(color: c.card)` + `InkWell(borderRadius: 16)` 包住带 `cardDecoration` 的容器，保证水波纹在圆角内。
3. **整卡可点 + 圆角裁剪**：`detail_page` 的版本信息块也是 `Material` + `InkWell` + `cardDecoration`。

卡片内部通用排布：
- 左侧图标块：`44×44` 圆角 `12`，底 `c.accentBg`、图标 `c.accent`（如 `claim_card.dart:32-40`）。
- 横向行：图标块 `SizedBox(width:12)` 文本列 `Expanded`，右侧信息列。
- 文本列左对齐、右信息列 `crossAxisAlignment: end`。

---

# 4. 列表与分组

## 4.1 列表项之间
- 一律 `SizedBox(height: 12)`（`home_page.dart:123`、`history_page.dart:121`、`detail_page.dart:179`）。

## 4.2 分组标题
- 历史页按年月分组：`Padding(top:8, bottom:10)` + `fontSize:12, w600, c.fgMuted`（`history_page.dart:78-87`）。

## 4.3 滑动操作
- 历史卡片：`Dismissible` 左滑归档（`endToStart`，阈值 `0.35`），背景用 `SwipeBackground`；滑出时 `HapticFeedback.mediumImpact()` 同帧反馈（`history_page.dart:91-108`）。
- 编辑页明细：`DismissibleRecordRow` 左滑删除，删除后 `setState` 移除（不弹确认）。
- 规则：**明确的"提交"动作（滑动归档/删除/添加）才给触感反馈**，且要 `if (!mounted) return` 守卫。

## 4.4 空状态
- 统一用 `EmptyHint(icon, text, card: true/false)`（`empty_hint.dart`），不要自己写占位。

---

# 5. 表单布局

> 详情/编辑页的"只读/可编辑表单"是同一套：卡片内 `FieldLabel` + 控件。

字段块结构（`detail_page.dart:106-160`、`editor_page.dart:358-403`）：
```
Container(padding:16, cardDecoration) ─ Column
  ├─ FieldLabel('报销单名称')            // 11, w600, c.fgMuted
  ├─ SizedBox(height:6)
  ├─ 控件（Text / DateRangePill）
  ├─ SizedBox(height:16~20)
  ├─ FieldLabel('出差日期')
  ├─ SizedBox(height:6)
  └─ DateRangePill / Row(DatePill → arrow → DatePill)
```

- `FieldLabel`：小标题 `fontSize:11, w600, c.fgMuted`，统一放字段上方。
- 日期胶囊 `DatePill` / `DateRangePill`：`padding(12,8)`、底 `c.bgSecondary`、圆角 `10`、`1px c.border`，可点则外层包 `PressScale`。
- 可编辑输入：`TextField` 用下划线边框（`enabledBorder`/`focusedBorder` 用 `c.border` / `c.accent`），`isDense:true`、`contentPadding(vertical:6)`。
- 条件字段：如 `excessAmount > 0` 才显示对应块（`detail_page.dart:143`、`claim_card.dart:82`）。

---

# 6. 标签与胶囊体系

> 分类标签有一套统一体系，按场景选款，不要随手拼 Container。

| 组件 | 场景 | 样式 |
|------|------|------|
| `CategoryBadge` | 明细行右侧小徽章 | `padding(7,3)`、圆角 `6`、分类底色描边，字 `10` |
| `CategoryTagChip(solid:true)` | 卡片内标签行（`RecTagsRow`） | 实心分类色底、白字、`9.5`、圆角 `4` |
| `CategoryTagChip(solid:false)` | 编辑/详情顶部汇总（`TagSummary`） | 描边 + 圆点、`padding(10,4)`、圆角 `999`、字 `11` |
| `DatePill`/`DateRangePill` | 日期选择 | 见第 5 节 |
| `SummaryPill` | 汇总卡内分类金额 | 网格两列，圆角胶囊 |
| `_ExcessAmountPill` | 超标金额 | 警示色胶囊、`10` 字、圆角 `999` |

- 标签行用 `Wrap(spacing:4/8, runSpacing:4/8)` 自动换行（`chips.dart:115`、`chips.dart:139`）。
- 实心标签（卡片内）字用 `Colors.white`；描边标签字用 `c.fg`。

---

# 7. 网格

- 汇总卡分类明细：`GridView` + `shrinkWrap:true` + `NeverScrollableScrollPhysics()`（嵌在滚动页内必须这两个，否则无限高报错），两列 `crossAxisCount:2`，`mainAxisExtent:34`，间距 `12/10`（`summary_card.dart:55-68`）。
- 手动添加类型选择：`Wrap` 流布局，`spacing:8, runSpacing:8`，每个 chip `padding(12,8)` 圆角 `10`（`editor_page.dart:554-623`）。

---

# 8. 底部导航 MainShell（Liquid Glass）

> 三栏外壳是特例骨架，用 `Stack` + 悬浮玻璃，不用第 0 节的普通骨架。

规则（`main_shell.dart`）：
- `Scaffold(extendBody: true)` —— 让 body 延伸到底栏下方，供 `BackdropFilter` 模糊。
- `body: Stack(fit:expand)` 同时放三个页面，非选中页 `IgnorePointer` + `AnimatedOpacity(0)` + `AnimatedSlide`（切换 320ms `easeOutCubic`，减少动态时 `Duration.zero`）。
- 底栏 `_GlassTabBar`：
  - 外层 `SafeArea(top:false)`，高度 `64 + 16`，`Padding.fromLTRB(40,0,40,16)` 收窄整体宽度。
  - 胶囊 `ClipRRect(28)` + `BackdropFilter(blur 28)` + 半透明底色（亮色 `F8FAFC@0.92`、暗色 `2A2722@0.78`）+ `1px` 描边 + 投影。
  - 选中胶囊 `_SelectedPill`：用 `LayoutBuilder` 算每格宽，**临界阻尼弹簧**（stiffness 246 / damping 31.4 ≈ 0.4s）滑动，从当前屏幕值出发可被打断重定向。
  - 菜单项 `_GlassTab`：`Expanded` + `Column` 图标(`22`)+文字(`10.5`)，选中 `Colors.white`、未选 `c.fgMuted`，图标 `AnimatedSwitcher` 在实心/描边间淡入缩放切换。

---

# 9. 浮动按钮 FAB（FabMenu）

> 编辑页右下角"添加"用 `FabMenu` 扇形菜单，不是普通 `FloatingActionButton`。

布局常量（`fab_menu.dart:37-44`）—— 不要改：
```
_fabSize   = 56     // 主按钮直径
_itemSize  = 48     // 子项直径
_fabRight  = 18     // 距右
_fabBottom = 26     // 距底
_arcRadius = 96     // 主→子中心距离（保证 45° 扇形不重叠）
```
- 展开 `380ms`，减少动态时直接跳到目标值（不级联）。
- 遮罩用 Glassmorphism（`BackdropFilter`），点击空白收起。

首页主创建按钮 `CreateCta`：居中 `140×140` 圆形，accent 渐变 + 呼吸光环（减少动态时停转），按下 `AnimatedScale(0.94)` 即时反馈（`create_cta.dart`）。

---

# 10. 对话框 / 弹窗

> 所有 `AlertDialog` 统一外观，不要裸写。

规范（散见 `editor_page.dart` / `mine_page.dart`）：
- `backgroundColor: c.card`，`shape: RoundedRectangleBorder(borderRadius: 20)`。
- 标题 `fontSize:17, w700, c.fg`；正文 `fontSize:14, c.fgMuted, height:1.5`。
- 按钮：`TextButton`（取消/次要，`c.fgMuted`）+ `FilledButton`（主操作，`c.accent`）。
- **危险操作**（覆盖导入）用 `FilledButton(backgroundColor: c.danger)` 并加明确文案（`mine_page.dart:511-516`）。
- 内容多时用 `Column(mainAxisSize:min)`，字段用 `ResultLine` 标签/值分行。
- 表单类弹窗（手动添加）内用 `Wrap` 类型网格 + 底部 `actions` 取消/添加。

---

# 11. 设置页（我的）布局

> 「我的」是"卡片分组 + 行列表"范式，可复用于任何设置/分组列表页。

结构（`mine_page.dart`）：
```
SingleChildScrollView(padding 20, bottom 120)
  ├─ OwedCard（顶部强调卡）
  ├─ SizedBox(16)
  ├─ 卡片(cardDecoration)
  │    ├─ Row(标题 + Spacer + 年份/说明)
  │    ├─ SizedBox(12)
  │    └─ Row(StatCell, SizedBox(10), StatCell) ×2   // 两列统计格
  ├─ SizedBox(16)
  ├─ 卡片 ─ Column
  │    ├─ MineRow / MineDivider / MineRow ...
  ├─ SizedBox(16)
  └─ ... 更多分组卡片
```

- `MineRow`：左 `36×36` 圆角 `10` 图标块（`c.bgSecondary`, 图标 `c.fgMuted`）+ `12` + 标题列（`14,w600,c.fg` + 可选副标题 `12,c.fgMuted`）+ `trailing`（右箭头 `c.fgSoft`）。
- `MineHeader`：同图标块 + 标题，作分组小标题。
- `MineDivider`：`Divider(height:1, color:c.border, indent:16, endIndent:16)` 分隔行。
- 统计格 `StatCell`：两列等宽用 `Row` + `SizedBox(width:10)`。

---

# 12. 文本层级（字号体系）

> 形成稳定的"字号阶梯"，不要随心设字号。

| 角色 | 字号 | 字重 | 颜色 | 示例 |
|------|------|------|------|------|
| 大标题（金额） | `32` | `w800` | `c.accent` | `SummaryCard` 总额 |
| 页面强调标题 | `22` | `w800` | `c.fg` | 首页"新建报销" |
| 顶栏标题 | `18`/`20` | `w800` | `c.fg` | `AppTopBar` |
| 卡片标题 | `14`/`15` | `w600` | `c.fg` | 报销单名 |
| 正文/副标题 | `12`/`13` | `w500` | `c.fgMuted` | 票据数、副标题 |
| 小标签 | `10`/`11` | `w600` | 场景色 | 分类、徽章 |
| 金额（卡内） | `14` | `w700` | `c.accent` | `ClaimCard` 退补 |

- 强调数字（金额）常用 `letterSpacing: -0.03` 收紧、`height:1`。
- 标题/分组多用 `w600`/`w800`；说明文字 `c.fgMuted`。

---

# 13. 安全区域 / 键盘 / 留白（落实到布局）

- 顶栏 `SafeArea(bottom:false)`，底栏 `SafeArea(top:false)`。
- 滚动内容底部统一 `padding 120`：首页给主创建按钮、编辑/详情/我的给 FAB/底栏留位。
- `MainShell.extendBody:true` + 内容延伸，玻璃模糊才生效。
- 键盘弹起交给 Scaffold 默认 `resizeToAvoidBottomInset`，无需 `SingleChildScrollView` 额外处理。
- 大屏/横屏：**未做**独立布局分支，无 `OrientationBuilder`；布局以 `Expanded`/`SizedBox` + 固定 `20` 页边距为主，靠流式自适应。

---

# 新增页面速查清单（布局核对）

- [ ] 用 `Scaffold(backgroundColor: c.bg)` + `Column[AppTopBar, Expanded(SingleChildScrollView(padding 20,120))]`
- [ ] 左右页边距 `20`，卡片内 `16`，区块间距 `12`/`16`
- [ ] 卡片用 `cardDecoration(c)`，圆角 `16`；可点卡片 `Material`+`InkWell`
- [ ] 列表项之间 `SizedBox(height:12)`；空态用 `EmptyHint`
- [ ] 顶部栏 `AppIconButton` 36×36；标题居中、左右槽 72（多按钮提 88）
- [ ] 表单：`FieldLabel` + 控件 + `SizedBox(6/16)`，日期用 `DatePill` 系列
- [ ] 分类标签按场景选 `CategoryBadge`/`TagChip(solid)`/`TagSummary`
- [ ] 网格必须 `shrinkWrap + NeverScrollableScrollPhysics`
- [ ] 对话框统一 `c.card` + 圆角 `20`；危险操作 `c.danger`
- [ ] 设置类页用 `MineRow`+`MineDivider`+`cardDecoration` 分组
- [ ] 底部留白 `120`；底栏 `SafeArea(top:false)`；勿覆盖键盘默认行为
- [ ] FAB 用 `FabMenu`（56/48/96 常量）；首页 CTA 用 `CreateCta`
