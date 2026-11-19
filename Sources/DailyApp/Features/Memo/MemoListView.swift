import AppKit
import DailyCore
import SwiftUI

struct MemoListView: View {
    @Bindable var model: AppModel

    @State private var editorMemoID: UUID?
    @State private var isPresentingEditor = false
    @State private var pendingDeletion: Memo?
    @State private var renameTarget: Memo?
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if model.memos.isEmpty {
                    emptyState
                } else {
                    ForEach(model.memos) { memo in
                        memoRow(memo)
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("备忘录")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentNewMemo()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("新建备忘录")
            }
        }
        .task {
            model.loadMemos()
        }
        .sheet(isPresented: editorPresentation) {
            if let editorMemoID,
               let memo = model.memos.first(where: { $0.id == editorMemoID }) {
                MemoEditorView(model: model, memo: memo)
            } else {
                MemoEditorView(model: model, memo: nil)
            }
        }
        .confirmationDialog(
            "删除这条备忘录？",
            isPresented: deletePresentation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let memo = pendingDeletion else { return }
                pendingDeletion = nil
                Task { @MainActor in
                    await model.deleteMemo(memo)
                }
            }
            Button("取消", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text("删除后无法恢复。")
        }
        .alert("重命名备忘录", isPresented: renamePresentation) {
            TextField("标题", text: $renameText)
            Button("重命名") {
                confirmRename()
            }
            Button("取消", role: .cancel) {
                renameTarget = nil
            }
        } message: {
            Text("将修改备忘录的第一行标题。")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("📝")
                .font(.system(size: 40))

            Text("还没有备忘录")
                .font(.title3.weight(.semibold))

            Text("点击右上角按钮新建，或用 ⌘⇧M 快速记录一条。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                presentNewMemo()
            } label: {
                Label("新建备忘录", systemImage: "square.and.pencil")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .glassModule(interactive: false, cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    private func memoRow(_ memo: Memo) -> some View {
        Button {
            presentEdit(memo)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(memoTitle(memo))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(updatedText(memo))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let preview = memoPreview(memo)
                if !preview.isEmpty {
                    Text(renderedPreview(preview))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassModule(interactive: true, cornerRadius: 14)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("编辑") {
                presentEdit(memo)
            }
            Button("重命名") {
                startRename(memo)
            }
            Button("复制") {
                copyMemo(memo)
            }
            Divider()
            Button("删除", role: .destructive) {
                pendingDeletion = memo
            }
        }
        .accessibilityLabel(memoTitle(memo))
        .accessibilityHint("点击编辑")
    }

    private func memoTitle(_ memo: Memo) -> String {
        guard let first = firstLine(of: memo.body) else { return "无标题" }
        let cleaned = first.replacingOccurrences(
            of: "^#{1,6}\\s*",
            with: "",
            options: .regularExpression
        )
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "无标题" : trimmed
    }

    private func memoPreview(_ memo: Memo) -> String {
        let lines = memo.body.split(separator: "\n", omittingEmptySubsequences: false)
        guard let titleIndex = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else { return "" }
        return lines
            .dropFirst(titleIndex + 1)
            .map(String.init)
            .joined(separator: "\n")
    }

    private func renderedPreview(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: source)) ?? AttributedString(source)
    }

    private func firstLine(of body: String) -> String? {
        body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
    }

    private func updatedText(_ memo: Memo) -> String {
        memo.updatedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func presentNewMemo() {
        editorMemoID = nil
        isPresentingEditor = true
    }

    private func presentEdit(_ memo: Memo) {
        editorMemoID = memo.id
        isPresentingEditor = true
    }

    private func startRename(_ memo: Memo) {
        renameTarget = memo
        renameText = memoTitle(memo)
    }

    private func confirmRename() {
        guard let memo = renameTarget else { return }
        renameTarget = nil
        let newTitle = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else { return }
        rename(memo, to: newTitle)
    }

    private func rename(_ memo: Memo, to newTitle: String) {
        let lines = memo.body.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else { return }
        let hadHeading = lines[index].range(
            of: "^#{1,6}\\s*",
            options: .regularExpression
        ) != nil
        var newLines = lines
        newLines[index] = hadHeading ? "# \(newTitle)" : newTitle
        let newBody = newLines.joined(separator: "\n")
        Task { @MainActor in
            _ = await model.updateMemo(id: memo.id, body: newBody)
        }
    }

    private func copyMemo(_ memo: Memo) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(memo.body, forType: .string)
    }

    private var editorPresentation: Binding<Bool> {
        Binding(
            get: { isPresentingEditor },
            set: { newValue in
                if !newValue {
                    isPresentingEditor = false
                    editorMemoID = nil
                }
            }
        )
    }

    private var deletePresentation: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { newValue in
                if !newValue {
                    pendingDeletion = nil
                }
            }
        )
    }

    private var renamePresentation: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { isPresented in
                if !isPresented {
                    renameTarget = nil
                }
            }
        )
    }
}
