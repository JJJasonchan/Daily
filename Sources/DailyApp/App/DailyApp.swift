import SwiftUI

@main
@MainActor
struct DailyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var sceneState: AppSceneState

    init() {
        let model = AppDependencies.live().appModel
        _sceneState = State(initialValue: AppSceneState(model: model))
    }

    var body: some Scene {
        Window("Daily", id: "main") {
            AppShellView(model: sceneState.windowModel)
                .task {
                    await sceneState.activate()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task { @MainActor in
                        await sceneState.activate()
                    }
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
            Button("快速添加") {
                showMainWindow()
                router.focusQuickAdd()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
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
