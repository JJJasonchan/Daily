# Wallpaper Glass Sidebar and Today Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 macOS 系统桌面壁纸驱动 Daily 侧栏的轻微渐变，并以玻璃卡片和全圆环展示今日完成进度。

**Architecture:** 新增独立的壁纸调色组件，读取主屏桌面壁纸 URL、计算并规范化颜色、以可测试的调色板值提供给 SwiftUI。`AppShellView` 持有该状态并注入侧栏；今日页使用独立的完成进度呈现模型和圆环视图，不修改 `AppModel` 的任务数据或 SwiftData 持久化。

**Tech Stack:** Swift 6.2、SwiftUI、AppKit、Observation、XCTest、macOS 26。

## Global Constraints

- 目标平台为 macOS 26 或更高版本，保留 SwiftUI `Glass` API 的既有使用方式。
- 使用 `NSWorkspace.shared.desktopImageURL(for:)` 读取当前主屏壁纸；不得保存、上传或将壁纸原图绘制到界面。
- 颜色必须限制为中低饱和度和可读的亮度区间；无法读取或解码壁纸时回退为中性色调色板。
- 仅使用公开 AppKit 通知：应用重新激活、活动空间切换、显示器参数变化时刷新壁纸颜色。
- 透明度降低辅助功能下禁用壁纸渐变与模糊，使用不透明窗口背景和高对比边框；动态效果降低时不播放进度补间。
- 保留当前工作区未提交的改动；未获得明确授权不得创建提交。

---

## File Structure

- Create: `Sources/DailyApp/Design/WallpaperPalette.swift` — 壁纸 URL 读取、平均色采样、颜色限制、可观察调色板状态与刷新通知。
- Create: `Sources/DailyApp/Design/TodayCompletionProgress.swift` — 今日完成量的纯呈现模型、全圆环 SwiftUI 视图。
- Modify: `Sources/DailyApp/Features/Shell/AppShellView.swift` — 创建调色板状态并注入侧栏。
- Modify: `Sources/DailyApp/Features/Shell/SidebarView.swift` — 绘制壁纸色渐变、玻璃导航状态、76% 等效卡片表面。
- Modify: `Sources/DailyApp/Features/Today/TodayView.swift` — 在标题区使用新的全圆完成环。
- Modify: `Sources/DailyApp/Design/GlassModule.swift` — 提供可配置玻璃覆盖层，且保持减少透明度回退。
- Create: `Tests/DailyAppTests/WallpaperPaletteTests.swift` — 验证颜色限制、回退值与刷新事件。
- Create: `Tests/DailyAppTests/TodayCompletionProgressTests.swift` — 验证空、部分完成和全部完成时的进度文本与比例。

### Task 1: 可测试的壁纸调色板

**Files:**
- Create: `Sources/DailyApp/Design/WallpaperPalette.swift`
- Test: `Tests/DailyAppTests/WallpaperPaletteTests.swift`

**Interfaces:**
- Consumes: `NSWorkspace.desktopImageURL(for:)`、`NSScreen.main`、`NSApplication.didBecomeActiveNotification`、`NSWorkspace.activeSpaceDidChangeNotification`、`NSApplication.didChangeScreenParametersNotification`。
- Produces: `WallpaperPalette`、`WallpaperPaletteProviding`、`WallpaperPaletteStore`；侧栏仅通过 `WallpaperPalette` 获取 `topColor`、`bottomColor` 和 `cardTint`。

- [ ] **Step 1: 写入失败测试，定义规范化颜色和回退要求**

```swift
@MainActor
final class WallpaperPaletteTests: XCTestCase {
    func testPaletteClampsSaturatedBrightSourceIntoReadableRange() {
        let palette = WallpaperPalette.from(
            red: 1,
            green: 0.05,
            blue: 0.02
        )

        XCTAssertLessThanOrEqual(palette.saturation, 0.34)
        XCTAssertGreaterThanOrEqual(palette.brightness, 0.30)
        XCTAssertLessThanOrEqual(palette.brightness, 0.76)
    }

    func testUnavailableWallpaperUsesNeutralFallback() {
        XCTAssertEqual(WallpaperPalette.fallback, .from(red: 0.52, green: 0.58, blue: 0.66))
    }
}
```

- [ ] **Step 2: 运行调色板测试，确认失败原因是类型尚不存在**

Run: `swift test --filter WallpaperPaletteTests -Xswiftc -warnings-as-errors`

Expected: 编译失败，提示 `WallpaperPalette` 未定义。

- [ ] **Step 3: 实现纯颜色值、取样协议和主屏壁纸存储器**

```swift
struct WallpaperPalette: Equatable, Sendable {
    let hue: Double
    let saturation: Double
    let brightness: Double

    static let fallback = WallpaperPalette.from(red: 0.52, green: 0.58, blue: 0.66)

    static func from(red: Double, green: Double, blue: Double) -> WallpaperPalette {
        let color = NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
        var hue = CGFloat.zero
        var saturation = CGFloat.zero
        var brightness = CGFloat.zero
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return WallpaperPalette(
            hue: Double(hue),
            saturation: min(max(Double(saturation), 0.12), 0.34),
            brightness: min(max(Double(brightness), 0.30), 0.76)
        )
    }

    var topColor: Color {
        Color(hue: hue, saturation: saturation, brightness: min(brightness + 0.06, 0.88))
    }

    var bottomColor: Color {
        Color(hue: hue, saturation: saturation * 0.72, brightness: max(brightness - 0.08, 0.22))
    }

    var cardTint: Color {
        Color(hue: hue, saturation: saturation * 0.45, brightness: min(brightness + 0.12, 0.88))
    }
}

@MainActor
protocol DesktopImageURLProviding {
    func desktopImageURL() -> URL?
}

@MainActor
protocol WallpaperImageSampling {
    func averageRGB(at url: URL) -> (red: Double, green: Double, blue: Double)?
}

@MainActor
protocol WallpaperPaletteProviding: AnyObject {
    var palette: WallpaperPalette { get }
    func refresh()
}
```

`SystemDesktopImageURLProvider.desktopImageURL()` 以 `NSScreen.main` 调用 `NSWorkspace.shared.desktopImageURL(for:)`。`SystemWallpaperImageSampler.averageRGB(at:)` 将 `NSImage(contentsOf:)` 绘制为 `1 × 1` 的 `NSBitmapImageRep`，从 `colorAt(x: 0, y: 0)` 读取 RGB。`WallpaperPaletteStore` 从两个协议取得 URL 和 RGB；任何 URL、图像或位图失败均赋值 `WallpaperPalette.fallback`。构造时注册三个公开通知，在 `deinit` 移除观察者。测试通过协议注入返回固定 URL 或 `nil` 的桌面壁纸 URL 提供者，避免测试访问用户系统壁纸。

- [ ] **Step 4: 运行调色板测试，确认通过**

Run: `swift test --filter WallpaperPaletteTests -Xswiftc -warnings-as-errors`

Expected: `WallpaperPaletteTests` 全部通过。

### Task 2: 在主壳层注入并绘制玻璃侧栏

**Files:**
- Modify: `Sources/DailyApp/Features/Shell/AppShellView.swift`
- Modify: `Sources/DailyApp/Features/Shell/SidebarView.swift`
- Modify: `Sources/DailyApp/Design/GlassModule.swift`
- Test: `Tests/DailyAppTests/WallpaperPaletteTests.swift`

**Interfaces:**
- Consumes: `WallpaperPaletteProviding.palette`、`GlassModule`、`AppModel.destination`。
- Produces: `AppShellView(model:wallpaperPalette:)` 的侧栏注入路径，以及 `sidebarGlassSurface(palette:)` 私有视图修饰逻辑。

- [ ] **Step 1: 添加刷新传播的失败测试**

```swift
func testRefreshPublishesPaletteFromProvider() {
    let provider = WallpaperURLProviderStub(url: fixtureURL)
    let store = WallpaperPaletteStore(urlProvider: provider, imageSampler: FixedImageSampler(red: 0.2, green: 0.5, blue: 0.8))

    store.refresh()

    XCTAssertEqual(store.palette, WallpaperPalette.from(red: 0.2, green: 0.5, blue: 0.8))
}
```

- [ ] **Step 2: 运行调色板测试，确认状态发布测试失败**

Run: `swift test --filter WallpaperPaletteTests.testRefreshPublishesPaletteFromProvider -Xswiftc -warnings-as-errors`

Expected: 失败，提示 `WallpaperPaletteStore` 缺少可注入初始化方法或 `refresh()` 行为。

- [ ] **Step 3: 注入调色板状态并实现侧栏材质层**

```swift
@State private var wallpaperPalette = WallpaperPaletteStore()

NavigationSplitView {
    SidebarView(model: model, wallpaperPalette: wallpaperPalette.palette)
}
```

在 `SidebarView` 根视图背景中叠放：`LinearGradient`（取 `palette` 派生的两个低透明度色阶）、`Rectangle().fill(.ultraThinMaterial)` 和 1 px 半透明边界。导航选中态使用 `palette.cardTint.opacity(0.22)`，悬停态使用白色或黑色的 0.06 透明度层。

为 `GlassModule` 新增 `surfaceTint: Color? = nil` 与 `surfaceOpacity: Double = 0.76` 参数：正常模式将 `shape.fill(surfaceTint?.opacity(surfaceOpacity) ?? .clear)` 置于 `glassEffect` 下方；减少透明度模式保持 `windowBackgroundColor` 实色，并按对比度设置描边。`SidebarTodayCard` 传入 `surfaceTint: palette.cardTint`、`surfaceOpacity: 0.76`，保留现有无任务文案和无障碍标签。

- [ ] **Step 4: 运行调色板测试，确认刷新与回退均通过**

Run: `swift test --filter WallpaperPaletteTests -Xswiftc -warnings-as-errors`

Expected: 调色板限制、回退、注入刷新测试全部通过。

### Task 3: 全圆今日完成进度组件

**Files:**
- Create: `Sources/DailyApp/Design/TodayCompletionProgress.swift`
- Create: `Tests/DailyAppTests/TodayCompletionProgressTests.swift`

**Interfaces:**
- Consumes: `completed: Int`、`total: Int`、SwiftUI 的 `accessibilityReduceMotion`。
- Produces: `TodayCompletionProgress(completed:total:)` 与 `TodayCompletionRing(progress:motion:)`；`TodayView` 用它替换当前的半圆 `ProgressRing`。

- [ ] **Step 1: 写入失败测试，锁定显示数据**

```swift
final class TodayCompletionProgressTests: XCTestCase {
    func testEmptyProgressHasZeroFractionAndReadableLabels() {
        let progress = TodayCompletionProgress(completed: 0, total: 0)
        XCTAssertEqual(progress.fraction, 0)
        XCTAssertEqual(progress.percentageText, "0%")
        XCTAssertEqual(progress.countText, "0 / 0 tasks")
    }

    func testPartialProgressRoundsPercentageAndKeepsCounts() {
        let progress = TodayCompletionProgress(completed: 2, total: 3)
        XCTAssertEqual(progress.fraction, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(progress.percentageText, "67%")
        XCTAssertEqual(progress.accessibilityValue, "今日完成 2 项，共 3 项，67%")
    }

    func testCompletedProgressCapsTheRingAtOne() {
        XCTAssertEqual(TodayCompletionProgress(completed: 5, total: 3).fraction, 1)
    }
}
```

- [ ] **Step 2: 运行进度测试，确认失败原因是呈现模型尚不存在**

Run: `swift test --filter TodayCompletionProgressTests -Xswiftc -warnings-as-errors`

Expected: 编译失败，提示 `TodayCompletionProgress` 未定义。

- [ ] **Step 3: 实现呈现模型和全圆环**

```swift
struct TodayCompletionProgress: Equatable, Sendable {
    let completed: Int
    let total: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }

    var percentageText: String { "\(Int((fraction * 100).rounded()))%" }
    var countText: String { "\(completed) / \(total) tasks" }
    var accessibilityValue: String { "今日完成 \(completed) 项，共 \(total) 项，\(percentageText)" }
}
```

`TodayCompletionRing` 使用两层 `Circle().trim(from:to:)`：底环透明度 0.16，进度环从 0 到 `progress.fraction`，旋转 -90 度，圆角端点。中心使用“今日完成”、百分比和时钟图标；底部显示 `countText`。将传入的 `MotionSpec` 用于 `fraction` 与数字变化动画；当 `reduceMotion` 为真时使用 `MotionTokens.reduced`。

- [ ] **Step 4: 运行进度测试，确认通过**

Run: `swift test --filter TodayCompletionProgressTests -Xswiftc -warnings-as-errors`

Expected: 空、部分、超过总数的进度测试全部通过。

### Task 4: 接入今日页并执行完整验证

**Files:**
- Modify: `Sources/DailyApp/Features/Today/TodayView.swift`
- Test: `Tests/DailyAppTests/TodayCompletionProgressTests.swift`
- Test: `Tests/DailyAppTests/WallpaperPaletteTests.swift`

**Interfaces:**
- Consumes: `TodayCompletionProgress(completed:total:)`、`TodayCompletionRing(progress:motion:)`、`TodayView.effectiveCompletedCount`。
- Produces: 标题区右上全圆环；完成、撤销、添加或删除任务后按 UI 当前有效完成状态更新。

- [ ] **Step 1: 运行既有模型测试，确认今日数量来源保持正确**

Run: `swift test --filter AppModelTests.testTwoCompletedTasksOutOfFourHaveHalfCompletion -Xswiftc -warnings-as-errors`

Expected: 通过；该测试已经验证 `completedCount == 2`、`todayTasks.count == 4`、`completionFraction == 0.5`，此任务不改变 `AppModel` 的任务计算逻辑。

- [ ] **Step 2: 将标题区半圆仪表替换为全圆进度**

```swift
let progress = TodayCompletionProgress(
    completed: effectiveCompletedCount,
    total: model.todayTasks.count
)

TodayCompletionRing(
    progress: progress,
    motion: motion
)
.animation(motion.animation, value: progress)
```

移除当前头部中基于 `ProgressRing` 的半圆、指针和庆祝表情偏移。保留日期块布局；进度环右对齐、宽度不挤压窄窗口的日期内容。`TodayCompletionRing` 组合为单个无障碍元素，标签为“今日完成”，值为 `progress.accessibilityValue`。

- [ ] **Step 3: 运行全部单元测试和应用构建**

Run: `swift test -Xswiftc -warnings-as-errors && bash scripts/test-build-app.sh`

Expected: 所有 `DailyCoreTests` 与 `DailyAppTests` 通过，`build/Daily.app` 构建成功。

- [ ] **Step 4: 手工验收主窗口外观**

Run: `open build/Daily.app`

Expected: 更换系统桌面壁纸后，切换应用或空间时侧栏渐变更新；侧栏卡片保持可读；开启“减少透明度”后没有模糊效果；完成、撤销、添加和删除任务时首页圆环与数字同步更新。
