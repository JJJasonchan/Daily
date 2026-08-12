# Daily

Daily 是一款原生、离线的 macOS 每日任务与提醒应用。它使用统一的今日列表，支持单次任务、重复规则、本地通知、历史记录，以及与主窗口共享状态的菜单栏面板。

## 环境要求

- macOS 26 或更高版本
- Xcode 26.6；项目清单使用 Swift tools 6.2。本机验证使用 Swift 6.3.3 编译器。

## 测试

```bash
swift test -Xswiftc -warnings-as-errors
```

## 构建应用包

```bash
bash scripts/build-app.sh
```

脚本会执行 Release 构建，生成 `build/Daily.app`，并使用 ad-hoc 签名后验证应用包。`build/` 是本地产物，不提交到 Git。

## 启动

```bash
open build/Daily.app
```

首次启用提醒时，macOS 可能请求通知权限。拒绝权限不会影响任务管理功能，可在应用“设置”中查看当前授权状态并打开系统设置。

数据保存在 `~/Library/Application Support/com.daily.todo/Daily.store`。早期 SwiftPM 开发构建可能生成的 `default.store` 不会自动导入；当前应用尚未发布，因此不执行可能损坏开发数据的自动迁移。

## 手动验收

完整验收项目及本机验证结果见 [`docs/manual-test-checklist.md`](docs/manual-test-checklist.md)。
