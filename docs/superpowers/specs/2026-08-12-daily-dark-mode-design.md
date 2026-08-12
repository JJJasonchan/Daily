# Daily：暗黑模式设计规格

## 1. 概述

Daily 的暗黑模式**默认跟随系统外观**，同时在设置页提供「跟随系统 / 浅色 / 深色」三选一持久切换。所有视觉适配通过 SwiftUI 语义色与系统材质实现，零硬编码色值，零暗色专属分支代码。颜色模式设置持久化到 `AppSettings.colorSchemeMode`，重启后保持。

### 1.1 范围

- 主窗口（今日列表、侧边栏）
- 菜单栏面板
- 历史记录页
- 设置页
- 外观切换时的过渡行为
- 辅助功能兼容

### 1.2 非范围

- ~~不引入 app 内独立的外观切换开关~~ → 已在设置页添加三选一 Picker
- ~~不持久化外观相关设置~~ → 已持久化到 `AppSettings.colorSchemeMode`
- 不定义 Asset Catalog 色板（语义色已覆盖全部需求）

## 1.3 外观设置实现

- `AppSettings` 新增 `colorSchemeMode` 字段（`ColorSchemeMode` 枚举：`.system` / `.light` / `.dark`，默认 `.system`）
- 设置页 `SettingsView` 使用 `Picker(.segmented)` 展示三选项
- `DailyApp` 在 `Window` 和 `MenuBarExtra` 上应用 `.preferredColorScheme()`
- 菜单栏 NSPanel 的 `appearance` 根据 `colorSchemeMode` 动态设置
- 语义色方案不受影响：任何模式下 `.primary` / `.secondary` / `.tertiary` 始终正确映射

## 2. 颜色语义映射

### 2.1 文本色

| 用途 | 浅色 | 暗色 | 语义 token |
|------|------|------|-----------|
| 任务标题 | 近黑 | 近白 | `.primary` |
| 日期标注、顺延标签、辅助信息 | 中灰 | 中灰 | `.secondary` |
| 已完成任务标题、占位文字 | 浅灰 | 暗灰 | `.tertiary` |
| 删除/危险操作 | 系统红 | 系统红 | `.red` |

### 2.2 背景与材质

| 区域 | 材质 | 说明 |
|------|------|------|
| 主窗口内容区 | `.regularMaterial` | 通过 `VisualEffect` 应用，不叠色 |
| 侧边栏 | `.ultraThinMaterial` | 略亮于内容区，自然分层 |
| 菜单栏面板 | `.menu` + `.ultraThinMaterial` | NSPanel popover，macOS 自动呈现深色半透明底 |
| 设置页 | `Form` 默认背景 | 无额外设置 |

### 2.3 强调与交互色

| 用途 | 语义 token |
|------|-----------|
| 进度条填充、勾选框、今日标记 | `.accentColor`（系统蓝，用户可在系统设置中自定义） |
| 进度条轨道 | `.tertiary` |
| 按钮链接 | `.link` |

### 2.4 Liquid Glass 材质

- 材质使用 `Material` 枚举（`.regular`、`.thin`、`.ultraThin`），不硬编码不透明度或白色
- macOS 26 Liquid Glass 自动跟随系统外观
- "降低透明度"开启时，macOS 自动降级材质为实色

## 3. 模块适配详情

### 3.1 任务列表项

**未完成：**
- 标题 `.primary`，勾选圈 `.secondary` 描边，空心
- 提醒时间 `.secondary` 小字

**已完成：**
- 标题 `.tertiary` + `strikethrough(true)`
- 勾选圈 `.accentColor` 填充，白色对勾不变
- 顺延标签 `.tertiary`

**拖动中：**
- 使用 `.onDrag` 系统默认拖拽预览
- 放下位置用系统分割线指示

**空状态：**
- "今天还没有任务" `.secondary`，居中

**进度条：**
- 轨道 `.tertiary`，填充 `.accentColor`

### 3.2 菜单栏面板

- `NSPanel` 设置 `appearance = nil`（跟随系统）
- 面板内容与主窗口共享 ViewModel，颜色自动同步
- 快速添加输入框占位符 `.tertiary`，输入文字 `.primary`
- "打开主窗口"入口 `.secondary` + SF Symbol 箭头

### 3.3 历史记录页

- 日列表、日选择器使用 `List` / `Table` 默认样式
- 每日完成率数字 `.primary`，进度条 `.accentColor`
- 已完成任务 `.tertiary` + 删除线
- 未完成任务 `.primary`
- "已顺延"标签 `.secondary`
- 无任务日期 "无任务" `.tertiary`

### 3.4 设置页

- `Form` / `Toggle` / `DatePicker` 全部使用系统默认样式
- 通知不可用提示 `.secondary`，附带系统设置入口 `Button`（`.link` 样式）

## 4. 外观切换过渡

- 不做自定义动画，macOS 自身窗口材质和系统控件自然过渡
- 自定义元素（进度条、勾选框）跟随语义色瞬间切换
- 主窗口与菜单栏面板通过共享 ViewModel 同步更新

## 5. 辅助功能兼容

- "增强对比度"：语义色自动提升对比度，无需代码分支
- "降低透明度"：macOS 自动将材质降级为实色
- "减少动态效果"：无额外自定义动画，天然兼容

## 6. 测试要点

- 浅色 ↔ 暗色切换后，主窗口和菜单栏面板同时生效
- 进度条、勾选框、删除线在两种模式下可辨识
- Liquid Glass 材质在两种模式下折射效果正确
- 辅助功能开启后页面可完整操作
