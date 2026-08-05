import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - 清单模板编辑器 - v2 - 负责清单模板任务层级编辑与自动保存
struct ChecklistTemplateEditorView: View {
    let fileURL: URL

    @State private var rows: [ChecklistTemplateRow] = []
    @State private var meta = TemplateMeta(id: UUID().uuidString, title: "", type: TemplateCategory.checklist.metaType, keyCount: 0)
    @State private var statusMessage = ""
    @State private var isLoading = true
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var focusedRowID: String?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(Array(rows.enumerated()), id: \.element.id) { item in
                    let index = item.offset
                    let row = item.element
                    ChecklistTemplateItemRowView(
                        row: row,
                        focusedRowID: $focusedRowID,
                        onTaskChange: { updateTask(index: index, task: $0) },
                        onTab: { adjustLevel(index: index, delta: 1) },
                        onBackTab: { adjustLevel(index: index, delta: -1) },
                        onReturn: { insertSiblingAndFocus(index: index) },
                        onDelete: { removeTask(index: index) }
                    )
                    .listRowSeparator(.visible)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            HStack {
                Button {
                    let newRow = ChecklistTemplateRow(
                        id: UUID().uuidString,
                        task: "",
                        level: 1,
                        status: 0,
                        sourceFile: "",
                        sourceID: ""
                    )
                    rows.append(newRow)
                    focusedRowID = newRow.id
                    requestAutoSave()
                } label: {
                    Image(systemName: "plus")
                }
                .appGlassButtonStyle(.prominent)
                .help("新增任务")

                Spacer()
            }
            .padding(12)

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(AppBackgroundVisualStyle.pageBackground)
        .navigationTitle(meta.title.isEmpty ? fileURL.lastPathComponent : meta.title)
        .task {
            load()
        }
        .onChange(of: rows) { _, _ in
            requestAutoSave()
        }
        .onDisappear {
            autoSaveTask?.cancel()
            save()
        }
    }

    private func load() {
        do {
            let value = try ArchiveStorage.readChecklistTemplate(fileURL: fileURL)
            rows = value.0
            meta = value.1
            isLoading = false
        } catch {
            statusMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func save() {
        guard !isLoading else { return }
        do {
            meta.title = fileURL.deletingPathExtension().lastPathComponent
            try ArchiveStorage.writeChecklistTemplate(fileURL: fileURL, rows: rows, meta: meta)
            statusMessage = "已自动保存"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func updateTask(index: Int, task: String) {
        guard rows.indices.contains(index) else { return }
        rows[index].task = task
    }

    private func adjustLevel(index: Int, delta: Int) {
        guard rows.indices.contains(index) else { return }
        rows[index].level = min(6, max(1, rows[index].level + delta))
    }

    private func insertSiblingAndFocus(index: Int) {
        guard rows.indices.contains(index) else { return }
        let row = rows[index]
        let newRow = ChecklistTemplateRow(
            id: UUID().uuidString,
            task: "",
            level: row.level,
            status: 0,
            sourceFile: "",
            sourceID: ""
        )
        rows.insert(newRow, at: index + 1)
        Task { @MainActor in
            focusedRowID = nil
            focusedRowID = newRow.id
        }
        requestAutoSave()
    }

    private func removeTask(index: Int) {
        guard rows.indices.contains(index) else { return }
        rows.remove(at: index)
        requestAutoSave()
    }

    private func requestAutoSave() {
        guard !isLoading else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                save()
            }
        }
    }
}

// MARK: - 清单模板项 - v2 - 单任务行编辑视图（①②③前缀与层级缩进）
struct ChecklistTemplateItemRowView: View {
    let row: ChecklistTemplateRow
    @Binding var focusedRowID: String?

    let onTaskChange: (String) -> Void
    let onTab: () -> Void
    let onBackTab: () -> Void
    let onReturn: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(levelPrefix(level: row.level))
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.secondary)

            KeyAwareTaskField(
                text: row.task,
                rowID: row.id,
                focusedRowID: $focusedRowID,
                onTextChange: onTaskChange,
                onTab: onTab,
                onBackTab: onBackTab,
                onReturn: onReturn
            )
            .frame(maxWidth: .infinity)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .appGlassButtonStyle(.danger)
        }
        .padding(.vertical, 3)
    }

    private func levelPrefix(level: Int) -> String {
        let symbols = ["①", "②", "③", "④", "⑤", "⑥"]
        let index = min(6, max(1, level)) - 1
        let indent = String(repeating: "  ", count: max(0, level - 1))
        return indent + symbols[index]
    }
}

private struct KeyAwareTaskField: View {
    let text: String
    let rowID: String
    @Binding var focusedRowID: String?
    let onTextChange: (String) -> Void
    let onTab: () -> Void
    let onBackTab: () -> Void
    let onReturn: () -> Void

    var body: some View {
        #if os(macOS)
        MacKeyAwareTaskField(
            text: text,
            isFocused: focusedRowID == rowID,
            onFocused: { focusedRowID = rowID },
            onTextChange: onTextChange,
            onTab: onTab,
            onBackTab: onBackTab,
            onReturn: onReturn
        )
        #else
        TextField("任务", text: Binding(get: { text }, set: onTextChange))
        #endif
    }
}

#if os(macOS)
private struct MacKeyAwareTaskField: NSViewRepresentable {
    let text: String
    let isFocused: Bool
    let onFocused: () -> Void
    let onTextChange: (String) -> Void
    let onTab: () -> Void
    let onBackTab: () -> Void
    let onReturn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        let shouldFocusNow = isFocused && !context.coordinator.wasFocused
        context.coordinator.wasFocused = isFocused
        if shouldFocusNow {
            DispatchQueue.main.async {
                if nsView.window?.firstResponder !== nsView.currentEditor() {
                    nsView.window?.makeFirstResponder(nsView)
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacKeyAwareTaskField
        var wasFocused = false

        init(_ parent: MacKeyAwareTaskField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.onFocused()
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.onTextChange(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                parent.onTab()
                return true
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                parent.onBackTab()
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onReturn()
                return true
            }
            return false
        }
    }
}
#endif
