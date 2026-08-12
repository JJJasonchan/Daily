# Daily 暗黑模式实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Daily app 的所有硬编码颜色替换为 SwiftUI 语义色与系统材质，完全跟随系统外观，零暗色专属分支代码。

**Architecture:** 这是一个对原有实现计划 `docs/superpowers/plans/2026-08-12-daily-macos-app.md` 的修正补丁。不引入新文件，不改架构。修改范围：Global Constraints + 各 Task 中的颜色/材质代码片段。

**Tech Stack:** SwiftUI semantic color tokens, Material enum, macOS 26 Liquid Glass

## Global Constraints

从原计划中删除这一条：

> Primary colors are black, white, and neutral gray; semantic system colors are reserved for warnings and errors.

替换为：

> 所有颜色使用 SwiftUI 语义 token（`.primary`、`.secondary`、`.tertiary`、`.quaternary`、`.accentColor`）；所有材质使用 `Material` 枚举（`.regular`、`.thin`、`.ultraThin`）；禁止硬编码 `Color.white`、`Color.black`、`Color.gray` 或任何 RGB/十六进制色值。颜色语义映射遵循 `docs/superpowers/specs/2026-08-12-daily-dark-mode-design.md`。

---

## 各 Task 颜色修正

以下是对原有计划各 Task 中需要修正的颜色/材质引用。仅列出有变更的步骤，其他步骤不变。

### Task 4: TodayView — 修正颜色引用

原计划中 `TodayView`、`TaskRow`、`QuickAddView` 的代码片段中，涉及颜色和材质的部分需修正。

**修正点：**

```swift
// 原: .foregroundStyle(.black) / .foregroundStyle(.white)
// 改: .foregroundStyle(.primary) / .foregroundStyle(.secondary) / .foregroundStyle(.tertiary)

// 原: Color.gray / Color.gray.opacity(0.5)
// 改: .foregroundStyle(.secondary) / .foregroundStyle(.tertiary)

// 原: Color.black / Color.white 作为背景
// 改: Material.regular / Material.ultraThin / Material.thin

// 原: .accentColor 只用于警告/错误
// 改: .accentColor 用于进度条填充、勾选框、今日标记（语义已修正）
```

**具体映射表（Tasks 4-10 通用）：**

| 原计划中可能的写法 | 替换为 | 使用场景 |
|---|---|---|
| `.foregroundStyle(.black)` | `.foregroundStyle(.primary)` | 任务标题、完成率数字 |
| `.foregroundStyle(.gray)` | `.foregroundStyle(.secondary)` | 日期标注、顺延标签、辅助文字 |
| `.foregroundStyle(.gray.opacity(0.4))` | `.foregroundStyle(.tertiary)` | 已完成任务、占位文字 |
| `Color.white` 背景 | `Material.regular` | 主窗口内容区 |
| `Color.black.opacity(...)` 背景 | `Material.ultraThin` | 侧边栏 |
| `Color.blue` | `.tint(.accentColor)` 或 `.accentColor` | 进度条填充、勾选框 |
| `Color.red` | `.foregroundStyle(.red)` | 删除操作（保持不变，`.red` 是语义色） |
| `Color.green` | `.foregroundStyle(.green)` | 保持（如有） |

### Task 8: GlassModule — 确认材质用法

原 `GlassModule.swift` 中的 `glassEffect` / `GlassEffectContainer` 用法不变。确保调用方不额外叠加 `.background(Color.white)` 或 `.background(Color.black)`。

### Task 10: MenuBar — 修正 NSPanel 外观

菜单栏面板的 `NSPanel` 配置中增加：

```swift
panel.appearance = nil  // 跟随系统外观，不锁定
```

原始计划未指定此设置，暗黑模式下必须显式设为 `nil`，否则面板可能不随系统切换。

### Task 11: 测试清单 — 增加暗黑模式验证项

在 `docs/manual-test-checklist.md` 中增加：

- [ ] 系统外观切换为深色后，主窗口文本、进度条、勾选框、材质全部切换
- [ ] 系统外观切换为深色后，菜单栏面板同步切换
- [ ] 辅助功能 → 增强对比度开启后，两种外观下文字可辨识
- [ ] 辅助功能 → 降低透明度开启后，材质降级为实色，界面可操作
- [ ] 通知权限相关文本在两种外观下可读

---

## 自检

1. **Spec 覆盖：** 文本色（`.primary`/`.secondary`/`.tertiary`）、材质（`Material` 枚举）、菜单栏面板 `appearance=nil`、过渡行为、辅助功能都已覆盖。
2. **无占位符：** 所有映射表条目具体到 token 级别。
3. **类型一致：** 所有颜色 token 均为标准 SwiftUI API，无自定义类型。
