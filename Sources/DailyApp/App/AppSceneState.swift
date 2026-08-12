import Foundation

@MainActor
final class AppSceneState {
    let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    var windowModel: AppModel { model }
    var menuBarModel: AppModel { model }

    func activate() async {
        await model.start()
    }
}

@MainActor
final class AppCommandRouter {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func focusQuickAdd() {
        model.requestQuickAddFocus()
    }

    func navigate(to destination: AppModel.Destination) {
        model.destination = destination
    }
}
