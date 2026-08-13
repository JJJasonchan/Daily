# Daily Scheduling, Shortcut, Accessibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct planned-date instance generation and notification timing, make Quick Capture consistently use Command-Shift-N with permission feedback, restore native keyboard focus visuals, and synchronize the application icon and neutral visual tokens.

**Architecture:** A task instance's `dayKey` is its execution date. Future one-time instances are stored immediately but excluded from today's query; recurring instances are created only when their recurrence matches the current day. Notification rebuild receives all incomplete instances from today onward so future reminders survive activation. Quick Capture matching is isolated in a testable value type while AppDelegate owns local/global monitors and reports unavailable global access through AppModel.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, SwiftData, UserNotifications, XCTest, SwiftPM.

## Global Constraints

- Preserve all pre-existing dirty worktree changes.
- Keep the minimum target at macOS 26.
- Use native SwiftUI/AppKit focus and accessibility behavior.
- Do not add dependencies.
- Add regression tests before production changes.

---

### Task 1: Planned task generation and notification rebuild

**Files:**
- Modify: `Sources/DailyCore/Services/TaskService.swift`
- Modify: `Sources/DailyCore/Services/DayRolloverService.swift`
- Modify: `Sources/DailyCore/Services/NotificationService.swift`
- Modify: `Sources/DailyCore/Persistence/TaskRepository.swift`
- Modify: `Sources/DailyCore/Persistence/SwiftDataTaskRepository.swift`
- Modify: repository test doubles
- Test: `Tests/DailyCoreTests/TaskServiceTests.swift`
- Test: `Tests/DailyCoreTests/NotificationServiceTests.swift`
- Test: `Tests/DailyCoreTests/DayRolloverServiceTests.swift`

**Interfaces:**
- Consumes: `TaskDraft.scheduledDay`, `RecurrenceRule.matches`, `DailyTask.dayKey`.
- Produces: `TaskRepository.dailyTasks(from:)` and correct future instance/reminder behavior.

- [ ] Add failing tests proving future one-time tasks use the planned `dayKey`, future recurring rules do not create today's instance, edits move incomplete instances, future reminders use calendar triggers, and rebuild retains future tasks.
- [ ] Run focused tests and confirm failures describe the current defects.
- [ ] Implement the minimum repository, task-service, rollover, and notification changes.
- [ ] Run focused tests until green, then run all DailyCore tests.

### Task 2: Quick Capture shortcut and permission feedback

**Files:**
- Modify: `Sources/DailyApp/App/DailyApp.swift`
- Modify: `Sources/DailyApp/App/AppModel.swift`
- Test: `Tests/DailyAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: AppKit local/global key monitors and `AXIsProcessTrusted()`.
- Produces: `QuickCaptureShortcut.matches(keyCode:modifierFlags:)` and an AppModel permission message.

- [ ] Add failing tests for Command-Shift-N matching and permission failure presentation.
- [ ] Run focused tests and confirm the current implementation fails.
- [ ] Add local/global monitors, use `kVK_ANSI_N`, and report missing accessibility permission without disabling the local shortcut.
- [ ] Run focused tests until green.

### Task 3: Native focus and neutral visual treatment

**Files:**
- Modify: SwiftUI views containing `focusEffectDisabled`.
- Modify: `Sources/DailyApp/Design/ColorTokens.swift`
- Modify: `Sources/DailyApp/Design/ProgressRing.swift`

**Interfaces:**
- Consumes: native SwiftUI focus effects and semantic `Color.primary`/`Color.secondary`.
- Produces: visible keyboard focus and a black/white/neutral progress treatment in both appearances.

- [ ] Remove focus-effect suppression from focusable controls and containers.
- [ ] Replace accent/red progress treatment with semantic neutral tokens.
- [ ] Compile with warnings as errors.

### Task 4: Icon synchronization and macOS verification

**Files:**
- Regenerate: `AppIcon.icns`
- Regenerate: `Sources/DailyApp/Resources/AppIcon.icns`
- Verify: `build/Daily.app`
- Update: `docs/manual-test-checklist.md`

**Interfaces:**
- Consumes: tracked `icon.iconset` PNG files.
- Produces: identical source and bundled ICNS resources.

- [ ] Generate ICNS from `icon.iconset` and synchronize both tracked ICNS copies.
- [ ] Run the full test suite, release app build, package safety test, plist validation, signature verification, and hash checks.
- [ ] Launch the built bundle and manually inspect light, dark, Reduce Motion, Reduce Transparency, Increase Contrast, keyboard focus, and Quick Capture behavior without changing persistent system settings when unavailable.
- [ ] Record only directly observed PASS/FAIL results; leave unsafe or inaccessible system-state checks BLOCKED.

