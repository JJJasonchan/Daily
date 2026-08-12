import SwiftUI

@main
@MainActor
struct DailyApp: App {
    @State private var model: AppModel

    init() {
        _model = State(initialValue: AppDependencies.live().appModel)
    }

    var body: some Scene {
        Window("Daily", id: "main") {
            AppShellView(model: model)
                .task {
                    await model.start()
                }
                .onDisappear {
                    model.stopObservingLifecycle()
                }
        }
        .defaultSize(width: 980, height: 680)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
