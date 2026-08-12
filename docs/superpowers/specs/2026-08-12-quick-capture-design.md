# Quick Capture Design

**Date**: 2026-08-12

## Goal

Add a glass quick-add bar in TodayView toolbar, and a global shortcut (`Command-Shift-N`) to invoke a floating glass quick-capture window that works even when Daily is not in the foreground.

## Scope

### In

- **A. Toolbar glass quick-add bar**: Replace the existing toolbar quick-add TextField with a wide glass-background input bar with emoji prefix, spanning full toolbar width.
- **B. Global floating quick-capture window**: A borderless glass window invoked via `Command-Shift-N`, centered on screen, for quick task entry from outside the app.
- Reuse existing `AppModel.add(TaskDraft)` for persistence.

### Out

- MenuBarContentView changes — stays as-is.
- The existing "新建任务" toolbar button and keyboard shortcut `Command-N` — unchanged.

---

## A. Toolbar Glass Quick-Add Bar

**File**: `Sources/DailyApp/Features/Today/TodayView.swift`

### Layout

```
┌──────────────────────────────────────────────────────────┐
│  📝  新任务（回车添加）                         [+] 新建  │
└──────────────────────────────────────────────────────────┘
```

- Left section: glass background (`glassModule(interactive: true)`), full width TextField with emoji prefix `📝`, placeholder "新任务（回车添加）"
- Right section: existing `[+] 新建` button (unchanged)
- Enter key submits, clears field

### Implementation

- Extract `QuickAddBar` as a private `@ViewBuilder` component within TodayView
- Reuse existing `submitQuickAdd()` method
- `@FocusState` on the TextField, focusable via `Command-Shift-A`

---

## B. Global Floating Quick-Capture Window

**Files**:
- `Sources/DailyApp/Features/QuickCapture/QuickCaptureWindow.swift` (new)
- `Sources/DailyApp/App/DailyApp.swift` (modify AppDelegate)

### Layout

```
       ┌───────────────────────┐
       │  ⚡ 快速添加           │
       │                       │
       │  📝 任务标题          │
       │                       │
       │          [Esc 关闭]   │
       └───────────────────────┘
         (glass background,
          centered, ~380×160)
```

### Behavior

1. User presses `Command-Shift-N` from anywhere
2. A borderless glass `NSWindow` appears, centered on the active screen
3. TextField auto-focused; user types title, presses Enter
4. Task is added via shared `AppModel` instance
5. Window closes; brief success feedback shown (haptic or brief status text)
6. Esc closes without adding
7. Window is key and accepts first responder

### Technical Notes

- Use `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` in AppDelegate
- Requires Accessibility permissions (macOS gate); prompt user if not granted
- Window uses `.glassEffect` / `.glassModule` for visual consistency
- Window is `.nonactivatingPanel` style so it doesn't steal focus permanently
- Shared AppModel accessed via `AppSceneState`

---

## Validation

- Build succeeds with `swift build`
- `Command-Shift-N` opens the quick-capture window from any app
- Enter submits and closes; Esc closes
- TodayView toolbar shows full-width glass quick-add bar
- No regressions on existing task add/edit flow
