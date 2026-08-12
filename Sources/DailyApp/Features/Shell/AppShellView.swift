import DailyCore
import SwiftUI

struct AppShellView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
        } detail: {
            detail
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: editorPresentation) {
            TaskEditorView(model: model, task: editingTask)
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
            placeholder(
                "重复规则",
                systemImage: "repeat",
                description: "管理每天、工作日或指定星期重复的任务。"
            )
        case .history:
            placeholder(
                "历史记录",
                systemImage: "clock.arrow.circlepath",
                description: "查看过去日期的完成与顺延状态。"
            )
        case .settings:
            placeholder(
                "设置",
                systemImage: "gearshape",
                description: "调整提醒和应用行为。"
            )
        }
    }

    private var editingTask: DailyTask? {
        guard let editorTaskID = model.editorTaskID else { return nil }
        return model.todayTasks.first {
            $0.id == editorTaskID && $0.completedAt == nil
        }
    }

    private var editorPresentation: Binding<Bool> {
        Binding(
            get: { model.isPresentingNewTask || editingTask != nil },
            set: { isPresented in
                guard !isPresented else { return }
                model.isPresentingNewTask = false
                model.editorTaskID = nil
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

    private func placeholder(
        _ title: String,
        systemImage: String,
        description: String
    ) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
