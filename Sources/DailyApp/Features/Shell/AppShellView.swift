import DailyCore
import SwiftUI

struct AppShellView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
        } detail: {
            detail
                .background(.ultraThinMaterial)
        }
        .preferredColorScheme(model.colorSchemeMode.swiftUIColorScheme)
        .navigationSplitViewStyle(.balanced)
        .focusEffectDisabled()
        .sheet(isPresented: editorPresentation) {
            if let editingTemplate {
                TaskEditorView(model: model, template: editingTemplate)
            } else {
                TaskEditorView(model: model, task: editingTask)
            }
        }
        .alert("Daily", isPresented: errorPresentation) {
            Button("好") {
                model.clearError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.destination {
        case .today:
            TodayView(model: model)
        case .rules:
            RulesView(model: model)
        case .history:
            HistoryView(model: model)
        case .settings:
            SettingsView(model: model)
        }
    }

    private var editingTask: DailyTask? {
        guard let editorTaskID = model.editorTaskID else { return nil }
        return model.todayTasks.first {
            $0.id == editorTaskID && $0.completedAt == nil
        }
    }

    private var editingTemplate: TaskTemplate? {
        guard let editorTemplateID = model.editorTemplateID else { return nil }
        return model.templates.first { $0.id == editorTemplateID }
    }

    private var editorPresentation: Binding<Bool> {
        Binding(
            get: {
                model.isPresentingNewTask || editingTask != nil || editingTemplate != nil
            },
            set: { isPresented in
                guard !isPresented else { return }
                model.isPresentingNewTask = false
                model.editorTaskID = nil
                model.editorTemplateID = nil
            }
        )
    }

    private var errorPresentation: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.clearError()
                }
            }
        )
    }
}
