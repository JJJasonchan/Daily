import Carbon.HIToolbox
import ApplicationServices
import Sparkle
import SwiftUI

@MainActor
private var sharedQuickCapture: QuickCaptureWindow?
@MainActor
private var sharedQuickMemo: QuickMemoWindow?
@MainActor
private var sharedModel: AppModel?
@MainActor
private var sharedUpdaterController: SPUStandardUpdaterController?

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        registerGlobalShortcut()
        ensureMenuBarPanelFollowsSystemAppearance()
        observeColorSchemeChanges()
    }

    private func ensureMenuBarPanelFollowsSystemAppearance() {
        // MenuBarExtra creates an NSPanel; appearance follows colorSchemeMode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows where window is NSPanel {
                window.appearance = NSAppearance.from(colorSchemeMode: sharedModel?.colorSchemeMode ?? .system)
            }
        }
    }

    private func observeColorSchemeChanges() {
        // When color scheme setting changes, update the menu bar NSPanel appearance
        NotificationCenter.default.addObserver(
            forName: .dailyColorSchemeModeDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                for window in NSApp.windows where window is NSPanel {
                    window.appearance = NSAppearance.from(
                        colorSchemeMode: sharedModel?.colorSchemeMode ?? .system
                    )
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func registerGlobalShortcut() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if QuickCaptureShortcut.matches(event) {
                Task { @MainActor in
                    sharedQuickCapture?.show()
                }
                return nil
            }
            if QuickMemoShortcut.matches(event) {
                Task { @MainActor in
                    sharedQuickMemo?.show()
                }
                return nil
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if QuickCaptureShortcut.matches(event) {
                Task { @MainActor in
                    sharedQuickCapture?.show()
                }
            } else if QuickMemoShortcut.matches(event) {
                Task { @MainActor in
                    sharedQuickMemo?.show()
                }
            }
        }

        if !AXIsProcessTrusted() {
            Task { @MainActor in
                sharedModel?.reportQuickCapturePermissionUnavailable()
            }
        }
    }
}

enum QuickCaptureShortcut {
    static func matches(_ event: NSEvent) -> Bool {
        matches(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
    }

    static func matches(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        var relevantFlags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        relevantFlags.remove(.capsLock)
        return keyCode == UInt16(kVK_ANSI_N)
            && relevantFlags == [.command, .shift]
    }
}

enum QuickMemoShortcut {
    static func matches(_ event: NSEvent) -> Bool {
        matches(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
    }

    static func matches(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        var relevantFlags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        relevantFlags.remove(.capsLock)
        return keyCode == UInt16(kVK_ANSI_M)
            && relevantFlags == [.command, .shift]
    }
}

@MainActor
func showQuickMemoWindow() {
    sharedQuickMemo?.show()
}

@main
@MainActor
struct DailyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @State private var sceneState: AppSceneState

    init() {
        let deps = AppDependencies.live()
        let model = deps.appModel
        _sceneState = State(initialValue: AppSceneState(model: model))
        sharedQuickCapture = QuickCaptureWindow(model: model)
        sharedQuickMemo = QuickMemoWindow(model: model)
        sharedModel = model
        sharedUpdaterController = deps.updaterController
    }

    var body: some Scene {
        Window("Daily", id: "main") {
            AppShellView(model: sceneState.windowModel)
                .background(TransparentTitlebar())
                .task {
                    await sceneState.activate()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task { @MainActor in
                        await sceneState.activate()
                    }
                }
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 980, height: 680)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            DailyCommands(router: AppCommandRouter(model: sceneState.model))
        }

        MenuBarExtra {
            MenuBarContentView(model: sceneState.menuBarModel)
                .task {
                    await sceneState.activate()
                }
        } label: {
            MenuBarStatusLabel(model: sceneState.menuBarModel)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
private struct DailyCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let router: AppCommandRouter

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("快速捕获") {
                sharedQuickCapture?.show()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("快速记录备忘录") {
                sharedQuickMemo?.show()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button("快速添加") {
                showMainWindow()
                router.focusQuickAdd()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }

        CommandGroup(after: .appInfo) {
            Button("检查更新...") {
                sharedUpdaterController?.checkForUpdates(nil)
            }
        }

        CommandGroup(after: .appSettings) {
            Button("设置...") {
                showMainWindow()
                router.navigate(to: .settings)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu("导航") {
            destinationButton("今日", destination: .today, key: "1")
            destinationButton("重复规则", destination: .rules, key: "2")
            destinationButton("历史记录", destination: .history, key: "3")
            destinationButton("备忘录", destination: .memo, key: "4")
            destinationButton("设置", destination: .settings, key: "5")
        }
    }

    private func destinationButton(
        _ title: String,
        destination: AppModel.Destination,
        key: KeyEquivalent
    ) -> some View {
        Button(title) {
            showMainWindow()
            router.navigate(to: destination)
        }
        .keyboardShortcut(key, modifiers: .command)
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
