import DailyCore
import SwiftUI

struct AppShellView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Bindable var model: AppModel
    @State private var wallpaperPalette = WallpaperPaletteStore()

    var body: some View {
        NavigationSplitView {
            SidebarView(
                model: model,
                wallpaperPalette: wallpaperPalette.palette
            )
        } detail: {
            detail
                .padding(.top, 8)
                .background {
                    detailBackground
                        .ignoresSafeArea()
                }
                .animation(.easeInOut(duration: 0.28), value: wallpaperPalette.palette)
        }
        .preferredColorScheme(model.colorSchemeMode.swiftUIColorScheme)
        .tint(ColorTokens.accent)
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: editorPresentation) {
            if let editingTemplate {
                TaskEditorView(model: model, template: editingTemplate)
            } else if let editingTask {
                TaskEditorView(model: model, task: editingTask)
            } else {
                TaskEditorView(model: model, startsRecurring: model.isPresentingNewRecurringTask)
            }
        }
        .alert("Daily", isPresented: errorPresentation) {
            Button("好") {
                model.dismissPresentedMessage()
            }
        } message: {
            Text(model.errorMessage ?? model.quickCapturePermissionMessage ?? "")
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
        case .memo:
            MemoListView(model: model)
        case .settings:
            SettingsView(model: model)
        }
    }

    @ViewBuilder
    private var detailBackground: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [
                        wallpaperPalette.palette.topColor.opacity(0.18),
                        wallpaperPalette.palette.bottomColor.opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Rectangle().fill(.regularMaterial)
            }
        }
    }

    private var editingTask: DailyTask? {
        guard let editorTaskID = model.editorTaskID else { return nil }
        return (model.todayTasks + model.upcomingTasks).first {
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
                model.isPresentingNewTask || model.isPresentingNewRecurringTask || editingTask != nil || editingTemplate != nil
            },
            set: { isPresented in
                guard !isPresented else { return }
                model.isPresentingNewTask = false
                model.isPresentingNewRecurringTask = false
                model.editorTaskID = nil
                model.editorTemplateID = nil
            }
        )
    }

    private var errorPresentation: Binding<Bool> {
        Binding(
            get: {
                model.errorMessage != nil || model.quickCapturePermissionMessage != nil
            },
            set: { isPresented in
                if !isPresented {
                    model.dismissPresentedMessage()
                }
            }
        )
    }
}
