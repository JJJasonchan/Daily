import Carbon.HIToolbox
import Sparkle
import SwiftUI

@MainActor
private var sharedQuickCapture: QuickCaptureWindow?
@MainActor
private var sharedModel: AppModel?
@MainActor
private var sharedUpdaterController: SPUStandardUpdaterController?

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var globalMonitor: Any?

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
    }

    private func registerGlobalShortcut() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains([.command, .shift]),
                  event.keyCode == 40 // K key
            else { return }
            Task { @MainActor in
                sharedQuickCapture?.show()
            }
        }
    }
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
        sharedModel = model
        sharedUpdaterController = deps.updaterController
    }

    var body: some Scene {
        Window("Daily", id: "main") {
            AppShellView(model: sceneState.windowModel)
                .focusEffectDisabled()
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
                .focusEffectDisabled()
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
            destinationButton("设置", destination: .settings, key: "4")
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
