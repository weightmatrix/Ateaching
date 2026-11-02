import SwiftUI

struct ChecklistDocumentEditorMode: Hashable {
    var hideCompletedItems: Bool
    var allowToggleLevel1AndLevel2: Bool
    var enablesCoursePickingFlow: Bool

    var isCoursePicking: Bool {
        enablesCoursePickingFlow
    }

    static let standard = ChecklistDocumentEditorMode(
        hideCompletedItems: false,
        allowToggleLevel1AndLevel2: true,
        enablesCoursePickingFlow: false
    )

    static let coursePicking = ChecklistDocumentEditorMode(
        hideCompletedItems: true,
        allowToggleLevel1AndLevel2: false,
        enablesCoursePickingFlow: true
    )
}

private enum ChecklistPopupExpandMode: String, CaseIterable, Identifiable {
    case l1
    case l3
    var id: String { rawValue }
}

// MARK: - 任务清单编辑器 - v1 - 档案任务清单文件编辑与勾选完成
struct ChecklistDocumentEditorView: View {
    let fileURL: URL
    let mode: ChecklistDocumentEditorMode
    var onCoursePick: (([ChecklistTemplateRow]) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [ChecklistTemplateRow] = []
    @State private var meta = ChecklistDocumentMeta(id: UUID().uuidString, title: "", templateID: "", createdAt: "", type: "checklist")
    @State private var statusMessage = ""
    @State private var isLoading = true
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var pickedRowIDs: [String] = []
    @State private var searchText = ""
    @State private var expandMode: ChecklistPopupExpandMode = .l3
    @State private var expandedL1IDs: Set<String> = []
    @State private var dropTargetRowID: String?

    init(
        fileURL: URL,
        mode: ChecklistDocumentEditorMode = .standard,
        onCoursePick: (([ChecklistTemplateRow]) -> Void)? = nil
    ) {
        self.fileURL = fileURL
        self.mode = mode
        self.onCoursePick = onCoursePick
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                if mode.isCoursePicking {
                    Picker("折叠", selection: $expandMode) {
                        Text("L1").tag(ChecklistPopupExpandMode.l1)
                        Text("L3").tag(ChecklistPopupExpandMode.l3)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在加载清单...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleRowIndices.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(mode.isCoursePicking ? "暂无可选任务" : "暂无任务")
                        .font(.headline)
                    Text(emptyStateDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if mode.isCoursePicking {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            checklistRows
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                } else {
                    List {
                        checklistRows
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackgroundVisualStyle.pageBackground)
        .navigationTitle(meta.title.isEmpty ? fileURL.lastPathComponent : meta.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    save()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .appGlassButtonStyle(.prominent)
                .help("保存")
                .keyboardShortcut("s", modifiers: .command)
            }
            if mode.isCoursePicking {
                ToolbarItem(placement: .confirmationAction) {
                    Button("插入") {
                        commitCoursePicking()
                    }
                    .disabled(pickedRowIDs.isEmpty)
                }
            }
        }
        .task {
            FrequentDocumentUsage.record(fileURL)
            load()
            loadExpandMode()
        }
        .onChange(of: expandMode) { _, _ in
            saveExpandMode()
        }
        .onChange(of: rows) { _, _ in
            scheduleAutoSave()
        }
        .onDisappear {
            autoSaveTask?.cancel()
            save()
        }
    }

    @ViewBuilder
    private var checklistRows: some View {
        ForEach(visibleRowIDs, id: \.self) { rowID in
            if let index = rows.firstIndex(where: { $0.id == rowID }) {
                checklistRow(at: index)
                    .id(rowID)
            }
        }
    }

    @ViewBuilder
    private func checklistRow(at index: Int) -> some View {
        let targetID = rows[index].id
        let row = ChecklistDocumentRowView(
            row: $rows[index],
            mode: mode,
            showsExpandToggle: shouldShowExpandToggle(for: rows[index]),
            isExpanded: expandedL1IDs.contains(rows[index].id),
            onExpandToggle: { toggleExpand(for: rows[index].id) },
            onCourseHierarchyActivate: { activateCourseH1(at: index) },
            pickIndex: pickedRowIDs.firstIndex(of: rows[index].id).map { $0 + 1 },
            onPickToggle: { togglePickedRow(id: rows[index].id) }
        )
        .listRowSeparator(.visible)

        if mode.isCoursePicking, rows[index].isCoursePickable {
            row
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(dropTargetRowID == targetID ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .draggable(targetID)
                .dropDestination(for: String.self) { draggedIDs, _ in
                    guard let draggedID = draggedIDs.first else { return false }
                    return reorderCourseRow(id: draggedID, relativeTo: targetID)
                } isTargeted: { isTargeted in
                    dropTargetRowID = isTargeted ? targetID : nil
                }
        } else {
            row
        }
    }

    private func reorderCourseRow(id sourceID: String, relativeTo targetID: String) -> Bool {
        guard mode.isCoursePicking,
              let sourceIndex = rows.firstIndex(where: { $0.id == sourceID }),
              let originalTargetIndex = rows.firstIndex(where: { $0.id == targetID }),
              sourceIndex != originalTargetIndex,
              rows[sourceIndex].isCoursePickable,
              rows[originalTargetIndex].isCoursePickable else { return false }

        withAnimation(.easeOut(duration: 0.12)) {
            let moved = rows.remove(at: sourceIndex)
            let destination = rows.firstIndex(where: { $0.id == targetID })
                .map { min($0 + 1, rows.endIndex) } ?? rows.endIndex
            rows.insert(moved, at: destination)
        }
        dropTargetRowID = nil
        let selectedIDs = Set(pickedRowIDs)
        pickedRowIDs = rows.map(\.id).filter { selectedIDs.contains($0) }
        save()
        statusMessage = "已调整教案词条顺序"
        return true
    }

    private func load() {
        do {
            let loaded = try ArchiveStorage.readChecklistDocument(fileURL: fileURL)
            rows = loaded.0
            meta = loaded.1
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
            try ArchiveStorage.writeChecklistDocument(fileURL: fileURL, rows: rows, meta: meta)
            statusMessage = "已保存"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func scheduleAutoSave() {
        guard !isLoading else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                save()
            }
        }
    }

    private var visibleRowIndices: [Int] {
        rows.indices.filter { index in
            guard mode.hideCompletedItems else { return true }
            guard rows[index].status == 0 else { return false }
            let row = rows[index]
            if mode.isCoursePicking,
               row.level == 2,
               row.task.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "node" {
                return false
            }
            if !searchQuery.isEmpty {
                return row.task.localizedCaseInsensitiveContains(searchQuery)
            }
            if !mode.isCoursePicking {
                return true
            }
            switch expandMode {
            case .l3:
                return row.level <= 3
            case .l1:
                if row.level == 1 { return true }
                guard row.level > 1 else { return false }
                guard let parent = parentL1ID(forIndex: index) else { return false }
                return expandedL1IDs.contains(parent)
            }
        }
    }

    private var visibleRowIDs: [String] {
        visibleRowIndices.map { rows[$0].id }
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parentL1ID(forIndex index: Int) -> String? {
        guard rows.indices.contains(index) else { return nil }
        if rows[index].level == 1 { return rows[index].id }
        var cursor = index - 1
        while cursor >= 0 {
            if rows[cursor].level == 1 {
                return rows[cursor].id
            }
            cursor -= 1
        }
        return nil
    }

    private func shouldShowExpandToggle(for row: ChecklistTemplateRow) -> Bool {
        guard mode.isCoursePicking, expandMode == .l1, searchQuery.isEmpty, row.level == 1 else { return false }
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return false }
        guard rows.indices.contains(index + 1) else { return false }
        for item in rows[(index + 1)...] {
            if item.level == 1 { return false }
            if item.level > 1 { return true }
        }
        return false
    }

    private func toggleExpand(for rowID: String) {
        if expandedL1IDs.contains(rowID) {
            expandedL1IDs.remove(rowID)
        } else {
            expandedL1IDs.insert(rowID)
        }
    }

    private func activateCourseH1(at index: Int) {
        guard mode.isCoursePicking,
              rows.indices.contains(index),
              rows[index].level == 1 else { return }
        let h1ID = rows[index].id
        expandedL1IDs.insert(h1ID)

        let sectionEnd = rows[(index + 1)...].firstIndex(where: { $0.level == 1 }) ?? rows.endIndex
        let orderedH3IDs = rows[(index + 1)..<sectionEnd]
            .filter { $0.level == 3 && $0.isCoursePickable }
            .map(\.id)
        guard !orderedH3IDs.isEmpty else {
            statusMessage = "本章没有可插入的未完成H3包。"
            return
        }

        let sectionIDs = Set(orderedH3IDs)
        pickedRowIDs.removeAll { sectionIDs.contains($0) }
        pickedRowIDs.append(contentsOf: orderedH3IDs)
        statusMessage = "已按顺序选中本章 \(orderedH3IDs.count) 个H3包。"
        let selectedRows = orderedH3IDs.compactMap { rowID in
            rows.first(where: { $0.id == rowID })
        }
        TeachingCourseDiagnostic116.record(
            "H1批量选择 h1Index=\(index) h1ID=\(String(h1ID.prefix(8))) "
                + TeachingCourseDiagnostic116.rowSummary(selectedRows)
                + " totalPicked=\(pickedRowIDs.count)"
        )
    }

    private func loadExpandMode() {
        guard mode.isCoursePicking else { return }
        guard let settings = try? TeachingStudentSettingsStore.loadStudentSystemSettings() else { return }
        expandMode = ChecklistPopupExpandMode(rawValue: settings.lessonChecklistExpandMode) ?? .l3
    }

    private func saveExpandMode() {
        guard mode.isCoursePicking else { return }
        guard var settings = try? TeachingStudentSettingsStore.loadStudentSystemSettings() else { return }
        settings.lessonChecklistExpandMode = expandMode.rawValue
        try? TeachingStudentSettingsStore.saveStudentSystemSettings(settings)
    }

    private func togglePickedRow(id: String) {
        guard mode.isCoursePicking else { return }
        guard let row = rows.first(where: { $0.id == id }), row.isCoursePickable else { return }
        if let existing = pickedRowIDs.firstIndex(of: id) {
            pickedRowIDs.remove(at: existing)
        } else {
            pickedRowIDs.append(id)
        }
    }

    private func commitCoursePicking() {
        guard mode.isCoursePicking else { return }
        TeachingCourseDiagnostic116.record(
            "点击插入前 pickedIDs=\(pickedRowIDs.count) documentRows=\(rows.count)"
        )
        let ordered = pickedRowIDs.compactMap { rowID in
            rows.first(where: { $0.id == rowID })
        }.filter { row in
            row.isCoursePickable
        }
        TeachingCourseDiagnostic116.record(
            "清单提交过滤后 " + TeachingCourseDiagnostic116.rowSummary(ordered)
        )
        guard !ordered.isEmpty else {
            pickedRowIDs.removeAll()
            statusMessage = "没有可插入的未完成H3包。"
            TeachingCourseDiagnostic116.record("清单提交终止 reason=ordered为空")
            return
        }
        let markStart = TeachingCourseDiagnostic116.now()
        markPickedRowsDoneBeforeInsert(ordered)
        TeachingCourseDiagnostic116.record(
            "清单预标完成 duration=\(String(format: "%.2f", TeachingCourseDiagnostic116.elapsedMilliseconds(since: markStart)))ms callback即将执行 rows=\(ordered.count)"
        )
        onCoursePick?(ordered)
        TeachingCourseDiagnostic116.record("清单callback返回，准备dismiss")
        dismiss()
    }

    private func markPickedRowsDoneBeforeInsert(_ pickedRows: [ChecklistTemplateRow]) {
        let pickedIDs = Set(pickedRows.map(\.id))
        let pickedPackageKeys = Set(pickedRows.map { row in
            "\(row.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())#\(row.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        })
        var touched = false
        for index in rows.indices where rows[index].level == 3 {
            let key = "\(rows[index].sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())#\(rows[index].sourceID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
            if pickedIDs.contains(rows[index].id) || pickedPackageKeys.contains(key) {
                if rows[index].status != 1 {
                    rows[index].status = 1
                    touched = true
                }
            }
        }
        if touched {
            save()
        }
    }

    private var emptyStateDescription: String {
        if mode.isCoursePicking {
            return "当前清单没有“未完成且可回溯 SourceID/SourceFile 的 L3 项”。可先在模板中补充对应条目，或在更新后再试。"
        }
        return "当前清单为空。"
    }
}

// MARK: - 任务清单行视图 - v1 - 支持层级缩进与完成状态点击
private struct ChecklistDocumentRowView: View {
    @Binding var row: ChecklistTemplateRow
    let mode: ChecklistDocumentEditorMode
    let showsExpandToggle: Bool
    let isExpanded: Bool
    let onExpandToggle: () -> Void
    let onCourseHierarchyActivate: () -> Void
    let pickIndex: Int?
    let onPickToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if showsExpandToggle {
                Button {
                    onExpandToggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "收起本章" : "展开本章")
            } else {
                Color.clear
                    .frame(width: 28, height: 28)
            }
            if mode.isCoursePicking {
                Button {
                    if row.level == 1 {
                        onCourseHierarchyActivate()
                    } else if canToggle {
                        onPickToggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if let pickIndex {
                            if pickIndex <= 50 {
                                Image(systemName: "\(pickIndex).circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .font(.system(size: 16, weight: .medium))
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .font(.system(size: 16, weight: .medium))
                            }
                        } else {
                            if canToggle {
                                Image(systemName: "circle")
                                    .foregroundStyle(Color.secondary)
                                    .font(.system(size: 16, weight: .medium))
                            } else {
                                Color.clear
                                    .frame(width: 18, height: 18)
                            }
                        }
                        Text(row.task)
                            .strikethrough(false)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(row.level != 1 && !canToggle)
            } else {
                Button {
                    row.status = row.status == 0 ? 1 : 0
                } label: {
                    Group {
                        Image(systemName: row.status == 0 ? "circle" : "checkmark.circle.fill")
                            .foregroundStyle(row.status == 0 ? Color.secondary : Color.green)
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canToggle)
                TextField("任务", text: $row.task)
                    .textFieldStyle(.plain)
                    .strikethrough(row.status == 1)
                    .foregroundStyle(row.status == 1 ? .secondary : .primary)
                    .disabled(!canEditText)
            }
        }
        .padding(.leading, CGFloat(max(0, row.level - 1)) * 20)
        .padding(.vertical, 4)
    }

    private var canToggle: Bool {
        if mode.isCoursePicking {
            return row.isCoursePickable
        }
        if mode.allowToggleLevel1AndLevel2 {
            return true
        }
        return row.level >= 3
    }

    private var canEditText: Bool {
        if mode.isCoursePicking {
            return false
        }
        return mode.allowToggleLevel1AndLevel2 || row.level >= 3
    }
}

private extension ChecklistTemplateRow {
    var isCoursePickable: Bool {
        level >= 3
            && status == 0
            && !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
