# Daily

Daily 是一款原生、离线的 macOS 每日任务与提醒应用。它使用统一的今日列表，支持单次任务、重复规则、本地通知、历史记录，以及与主窗口共享状态的菜单栏面板。

## 项目结构

```
Sources/
├── DailyApp/              ← SwiftUI 界面层
│   ├── App/               ← 入口（DailyApp、AppDelegate）、AppModel
│   ├── Design/            ← 设计 tokens（ColorTokens、GlassModule、MotionTokens、ProgressRing）
│   └── Features/
│       ├── Shell/         ← AppShellView（NavigationSplitView 主布局）、SidebarView
│       ├── Today/         ← 今日任务页（列表、行组件、编辑器、快速添加）
│       ├── Rules/         ← 重复规则管理页
│       ├── History/       ← 历史记录页
│       ├── Settings/      ← 设置页（外观、提醒、通知权限，即时生效）
│       ├── MenuBar/       ← 菜单栏面板
│       └── QuickCapture/  ← 全局快捷键快速捕获窗口
└── DailyCore/             ← 业务逻辑层
    ├── Domain/            ← LocalDay、TaskTypes
    ├── Models/            ← AppSettings、DailyTask、TaskTemplate
    ├── Persistence/       ← TaskRepository、SwiftDataTaskRepository
    ├── Services/          ← TaskService、DayRolloverService、NotificationService 等
    └── Support/           ← DayProviding

Tests/
├── DailyAppTests/         ← UI 层测试
└── DailyCoreTests/        ← 业务逻辑层测试

scripts/
├── build-app.sh           ← 构建 .app 包
└── test-build-app.sh      ← 构建验证脚本

docs/                      ← 设计文档与验收清单
```

## 环境要求

- macOS 26 或更高版本
- Xcode 26.6；项目清单使用 Swift tools 6.2。本机验证使用 Swift 6.3.3 编译器。

## 测试

```bash
swift test -Xswiftc -warnings-as-errors
```

## 构建

### .app 包

```bash
bash scripts/build-app.sh
```

产物：`build/Daily.app`

### DMG 安装包

```bash
bash scripts/package-dmg.sh
```

产物：`build/Daily.dmg`（已包含 .app 和 Applications 快捷链接，支持拖拽安装）

### 日常更新流程

```bash
swift build -c release          # 编译
bash scripts/build-app.sh        # 生成 .app
bash scripts/package-dmg.sh      # 打包 DMG
```

## 启动

```bash
open build/Daily.app
```

首次启用提醒时，macOS 可能请求通知权限。拒绝权限不会影响任务管理功能，可在应用”设置”中查看当前授权状态并打开系统设置。

数据保存在 `~/Library/Application Support/com.daily.todo/Daily.store`。早期 SwiftPM 开发构建可能生成的 `default.store` 不会自动导入；当前应用尚未发布，因此不执行可能损坏开发数据的自动迁移。

## 手动验收

完整验收项目及本机验证结果见 [`docs/manual-test-checklist.md`](docs/manual-test-checklist.md)。
