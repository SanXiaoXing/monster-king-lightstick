# Animation Plans

本目录存放 `improve-animations` 生成的实现计划。每条计划自包含（精确文件路径、
现状代码摘录、目标值、步骤、边界、验证），执行者可零上下文照做。

| # | Plan | Severity | Status |
| --- | --- | --- | --- |
| 000 | 自定义推页转场（AppRouter 接入淡入+微移过渡） | MEDIUM | ✅ DONE（0d466b8 → 已实施并验证） |

## Recommended execution order

1. **000** — 全 App 唯一推页入口，改一处所有未来推页继承同一转场；先做它再评估
   其他页面级显示动画（如连接守卫互换、设备列表骨架→卡片）会更容易对齐。

## Dependencies

- 000 无前置依赖，也不被其他计划依赖。
