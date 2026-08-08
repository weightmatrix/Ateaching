import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
import ImageIO
import WebKit
#elseif os(iOS)
import UIKit
import WebKit
#endif

extension Notification.Name {
    static let teachingNotebookDidPersistChange = Notification.Name("TeachingNotebookDidPersistChange")
    static let teachingRequestCloseNotebook = Notification.Name("TeachingRequestCloseNotebook")
}

// MARK: - NodeMarkdown编辑器页面 - v1 - 独立Web渲染骨架并预留后续原生编辑覆盖层
struct NodeMarkdownEditorView: View {
    let fileURL: URL
    var isReadOnlyRendered = false
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var document = NodeMarkdownDocument()
    @State private var documentIndex = NodeMarkdownDocumentIndex()
    @State private var fileMeta = NodeMarkdownFileMeta()
    @State private var isLoading = false
    @State private var statusMessage = ""
    @State private var rowsSnapshot = ""
    @State private var isLargeFileMode = false
    @State private var loadedFileSizeBytes: Int64 = 0
    @State private var saveState: MarkdownSaveState = .clean
    @State private var documentRevision: UInt64 = 0
    @State private var persistedDocumentRevision: UInt64 = 0
    @State private var showSettingsSheet = false
    @State private var showTOCPopover = false
    @State private var showExportActionDialog = false
    @State private var tocExpandMode: NodeMarkdownTOCExpandMode = .l3
    @State private var preferredSchemeOverride: NodeMarkdownPreferredScheme?
    @State private var searchText = ""
    @State private var committedSearchText = ""
    @State private var showSearchPopover = false
    @State private var searchResults: [NodeMarkdownSearchResult] = []
    @State private var activeSearchResultIndex: Int?
    @State private var activeSearchRowIndex: Int?
    @State private var pendingExportFormat: NodeMarkdownExportFormat = .pdf
    @State private var pendingRebuildTask: Task<Void, Never>?
    @State private var pendingTextKitParseTask: Task<Void, Never>?
    @State private var textKitParseGeneration: UInt64 = 0
    @State private var diskLoadGeneration: UInt64 = 0
    @State private var pendingRealtimeCoursePushTask: Task<Void, Never>?
    @State private var textKitDraft = ""
    @State private var textKitDraftRowMetadata: [NodeMarkdownTextKitRowMetadata] = []
    @State private var latestLegacyDocumentSnapshot: NodeMarkdownLegacyDocumentSnapshot?
    @State private var activeEditorRowIndex: Int?
    @State private var textKit2FocusLocation: NodeMarkdownTextFocusLocation?
    @State private var bottomEditorText = ""
    @State private var isUpdatingBottomEditorText = false
    @State private var showDrawingBoardSheet = false
    @State private var drawingBoardTargetRowIndex: Int?
    @State private var showLessonChecklistSheet = false
    @State private var lessonCompletionFiles: [URL] = []
    @State private var courseChecklistPickingTarget: TeachingLessonChecklistPickingTarget?
    @State private var pendingCourseInsertAnchor: TeachingCourseInsertAnchor?
    @State private var pendingClassUpdateCount = 0
    @State private var dirtyPackageItems: [TeachingCoursePackageChangeTracker.PackageDisplayItem] = []
    @State private var newPackageItems: [TeachingCoursePackageChangeTracker.PackageDisplayItem] = []
    @State private var selectedNewPackageIDs: Set<String> = []
    @State private var pendingCutPackageNodes: [NodeMarkdownNode] = []
    @State private var pendingCutPackageOriginalIndex: Int?
    @State private var showPendingCutGuardAlert = false
    @State private var pendingCutGuardMessage = ""
    @State private var packageChangeTracker = TeachingCoursePackageChangeTracker()
    @State private var showClassUpdateSheet = false
    @State private var showNewPackagePlacementSheet = false
    @State private var classUpdatePreview = TeachingCourseUpdatePreview(dirtyPackageCount: 0, newPackageCount: 0, chapterTargets: [])
    @State private var selectedUpdateChapterPath = ""
    @State private var selectedUpdateAnchorID = ""
    @State private var showReflectionSheet = false
    @State private var reflectionFiles: [URL] = []
    @State private var reflectionIndex = 0
    @State private var reflectionShowStudentInfo = false
    @State private var reflectionExportImageToken = 0
    @State private var showSyncFailureSheet = false
    @State private var syncFailureMessages: [String] = []
    @State private var isTextInputSessionActive = false
    @State private var isClosingClassSessionWithSync = false
    @State private var didRestoreImageUndoStashForSession = false
    @State private var externalTextSyncToken = 0
    @State private var classSessionRefreshToken = 0
    @State private var isNotebookWriteOperationInProgress = false
    @State private var legacyDraftCommitController = NodeMarkdownLegacyDraftCommitController()
    @State private var hasUncommittedLegacyDraft = false
    @StateObject private var annotationController = TeachingAnnotationController()
    private let editorInstanceID = UUID().uuidString

    @ObservedObject private var settingsCenter = NodeMarkdownSettingsCenter.shared
    private let phase150FeatureEnabled = NodeMarkdownFeatureFlags.phase150PackEnabled
    var body: some View {
        ZStack(alignment: .topLeading) {
            editorBackgroundColor
                .ignoresSafeArea()

            editorSurface
            if isLoading {
                ProgressView()
                    .padding(8)
            }
            searchFloatingPanel
            textKit2FocusLocationPanel
            if isNotebookWriteOperationInProgress {
                Rectangle()
                    .fill(.black.opacity(0.001))
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .overlay { ProgressView() }
            }
            TeachingAnnotationCanvasHost(controller: annotationController)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .allowsHitTesting(annotationController.isActive)
        }
        .navigationTitle("Node-\(fileURL.lastPathComponent)")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .cancellationAction) {
                Button("返回") {
                    closeReadOnlyClassSessionIfNeeded()
                }
            }
            #endif
            if isClassSessionEditor {
                ToolbarItemGroup(placement: .navigation) {
                    classSessionToolbar
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                searchButton
                colorSchemeButton
                styleButton
                tocButton
                if !isReadOnlyRendered {
                    exportMenu
                    saveButton
                }
            }
        }
        .task {
            tocExpandMode = NodeMarkdownTOCExpandMode(rawValue: NodeMarkdownSettingsStore.loadTOCExpandModeRawValue()) ?? .l3
            loadFromDiskIfNeeded()
            refreshPendingClassUpdateCount()
        }
        .task {
            await autoSaveLoop()
        }
        .onChange(of: settingsCenter.documentStyle) { _, _ in
            refreshTextKitDraftFromDocument(forceExternalSync: true)
            scheduleSnapshotRebuild()
        }
        .onChange(of: tocExpandMode) { _, newValue in
            NodeMarkdownSettingsStore.saveTOCExpandModeRawValue(newValue.rawValue)
        }
        .onChange(of: showSettingsSheet) { _, isPresented in
            guard !isPresented else { return }
            refreshTextKitDraftFromDocument(forceExternalSync: true)
            scheduleSnapshotRebuild()
            TeachingDebugLogStore.append("settings sheet dismissed, applied latest style", category: "NodeMarkdown.Settings")
        }
        .onChange(of: saveState, handleSaveStateChange)
        .onChange(of: isTextInputSessionActive, handleTextInputSessionChange)
        .onReceive(NotificationCenter.default.publisher(for: .teachingClassSessionDidChange)) { notification in
            if let changedPath = notification.userInfo?["filePath"] as? String {
                let standardizedChangedPath = URL(fileURLWithPath: changedPath).standardizedFileURL.path
                guard standardizedChangedPath == fileURL.standardizedFileURL.path else { return }
            }
            classSessionRefreshToken &+= 1
            refreshPendingClassUpdateCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .teachingNotebookDidPersistChange)) { notification in
            guard let changedPath = notification.userInfo?["filePath"] as? String else { return }
            guard URL(fileURLWithPath: changedPath).standardizedFileURL.path == fileURL.standardizedFileURL.path else { return }
            if let sourceID = notification.userInfo?["sourceEditorID"] as? String,
               sourceID == editorInstanceID {
                return
            }
            guard !isLoading else { return }
            guard saveState == .clean,
                  documentRevision == persistedDocumentRevision,
                  !hasUncommittedLegacyDraft,
                  !isNotebookWriteOperationInProgress else {
                statusMessage = "检测到外部文件变化；当前编辑内容优先，未自动重载。"
                return
            }
            reloadFromDisk()
            refreshPendingClassUpdateCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .teachingRequestCloseNotebook)) { notification in
            guard let targetPath = notification.userInfo?["filePath"] as? String else { return }
            guard URL(fileURLWithPath: targetPath).standardizedFileURL.path == fileURL.standardizedFileURL.path else { return }
            guard pendingCutPackageNodes.isEmpty else {
                presentPendingCutGuard(message: "存在未粘贴的剪切包，不能关闭。请先粘贴或回退剪切。")
                return
            }
            if isClassSessionEditor {
                closeClassSessionAfterSync(finishClass: false)
                return
            }
            dismiss()
        }
        .onDisappear {
            legacyDraftCommitController.commitPendingEditing()
            guard !isClosingClassSessionWithSync else {
                Task {
                    await TeachingCourseEditingAnchorStore.shared.setActiveRow(filePath: fileURL.path, rowIndex: nil)
                }
                return
            }
            if isClassSessionEditor {
                _ = packageChangeTracker.finishTrackingPreviousRow(
                    newRowIndex: nil,
                    document: document,
                    structuralIndex: documentIndex
                )
                refreshLocalPackageListsAndLight()
            }
            guard pendingCutPackageNodes.isEmpty else {
                presentPendingCutGuard(message: "存在未粘贴的剪切包，不能关闭。请先粘贴或回退剪切。")
                return
            }
            if !isReadOnlyRendered,
               TeachingClassSessionCenter.shared.shouldAutoFinishOnDisappear(for: fileURL.path) {
                saveAndSyncClassSessionForWindowClose(finishClass: true)
            } else if isClassSessionEditor {
                saveAndSyncClassSessionForWindowClose(finishClass: false)
            } else {
                // 普通编辑器由这里落盘；上课编辑器已由上面的保存同步事务负责，
                // 不得再并发启动第二次整文档写入。
                saveBeforeClosing()
            }
            Task {
                await TeachingCourseEditingAnchorStore.shared.setActiveRow(filePath: fileURL.path, rowIndex: nil)
            }
        }
        .confirmationDialog("选择导出方式", isPresented: $showExportActionDialog, titleVisibility: .visible) {
            Button("导出到微信") {
                exportToWeChat(format: pendingExportFormat)
            }
            Button("保存到文件") {
                exportToFiles(format: pendingExportFormat)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前格式：\(pendingExportFormat.rawValue)")
        }
        .preferredColorScheme(preferredColorScheme)
        .sheet(isPresented: $showSettingsSheet) {
            NodeMarkdownSettingsSheet(
                documentStyle: Binding(
                    get: { settingsCenter.documentStyle },
                    set: { settingsCenter.updateDocumentStyle($0) }
                ),
                quickInputSettings: Binding(
                    get: { settingsCenter.quickInputSettings },
                    set: { settingsCenter.updateQuickInputSettings($0) }
                )
            )
            .nodeMarkdownAdaptiveSheetSize(width: 620, height: 700)
        }
        .sheet(isPresented: $showDrawingBoardSheet) {
            #if os(macOS)
            if phase150FeatureEnabled {
                NodeMarkdownDrawingBoardSheet(
                    onComplete: { drawingURL in
                        guard let drawingURL else { return }
                        insertDrawingAsset(drawingURL: drawingURL)
                    }
                )
            }
            #else
            Text("iOS 暂不支持画图板")
                .padding()
            #endif
        }
        .sheet(isPresented: $showLessonChecklistSheet) {
            TeachingLessonChecklistPickerView(
                lessonCompletionFiles: lessonCompletionFiles,
                onPick: { rows, checklistPath in
                    showLessonChecklistSheet = false
                    applyCoursePickedRows(rows, completionChecklistPath: checklistPath)
                },
                onClose: {
                    showLessonChecklistSheet = false
                    pendingCourseInsertAnchor = nil
                }
            )
        }
        .sheet(
            item: $courseChecklistPickingTarget,
            onDismiss: {
                pendingCourseInsertAnchor = nil
            }
        ) { target in
            NavigationStack {
                ChecklistDocumentEditorView(
                    fileURL: URL(fileURLWithPath: target.id),
                    mode: .coursePicking,
                    onCoursePick: { rows in
                        courseChecklistPickingTarget = nil
                        applyCoursePickedRows(rows, completionChecklistPath: target.id)
                    }
                )
                .frame(minWidth: 720, minHeight: 520)
            }
        }
        .sheet(isPresented: $showClassUpdateSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("本次更新预览")
                        .font(.headline)
                    Text("脏包：\(max(classUpdatePreview.dirtyPackageCount, dirtyPackageItems.count))")
                    Text("新包（将进入上课收集）：\(max(classUpdatePreview.newPackageCount, newPackageItems.count))")
                    // 上课期间母本有更新机制暂停。上课中教师不修改母本，母本不会比随堂更新。
                    // 若需恢复，取消下面注释：
                    // if classUpdatePreview.sourceUpdatePackageCount > 0 {
                    //     Text("母本有更新：\(classUpdatePreview.sourceUpdatePackageCount)")
                    // }
                    if classUpdatePreview.conflictPackageCount > 0 {
                        Text("双方冲突：\(classUpdatePreview.conflictPackageCount)")
                            .foregroundStyle(.red)
                    }
                    if !dirtyPackageItems.isEmpty {
                        Divider()
                        Text("脏包实时列表")
                            .font(.subheadline.weight(.semibold))
                        List(dirtyPackageItems) { item in
                            Text(item.title.isEmpty ? "(空标题H3)" : item.title)
                                .font(.body)
                        }
                        .frame(minHeight: 120, maxHeight: 180)
                    }
                    if !newPackageItems.isEmpty {
                        Divider()
                        Text("新包实时列表")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 10) {
                            Button("全选") {
                                selectedNewPackageIDs = Set(newPackageItems.map(\.id))
                            }
                            .buttonStyle(.plain)
                            Button("全不选") {
                                selectedNewPackageIDs.removeAll()
                            }
                            .buttonStyle(.plain)
                            Text("已选 \(selectedNewPackageIDs.count) / \(newPackageItems.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        List(newPackageItems) { item in
                            Button {
                                if selectedNewPackageIDs.contains(item.id) {
                                    selectedNewPackageIDs.remove(item.id)
                                } else {
                                    selectedNewPackageIDs.insert(item.id)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: selectedNewPackageIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedNewPackageIDs.contains(item.id) ? Color.accentColor : .secondary)
                                    Text(item.title.isEmpty ? "(空标题H3)" : item.title)
                                        .font(.body)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(minHeight: 120, maxHeight: 180)
                    }
                    if classUpdatePreview.newPackageCount > 0 && !classUpdatePreview.chapterTargets.isEmpty {
                        Divider()
                        newPackagePlacementControls
                    }
                    Spacer()
                }
                .padding(16)
                .navigationTitle("更新")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showClassUpdateSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("执行更新") {
                            showClassUpdateSheet = false
                            if !selectedNewPackageIDs.isEmpty, !classUpdatePreview.chapterTargets.isEmpty {
                                showNewPackagePlacementSheet = true
                            } else {
                                runClassUpdate()
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showNewPackagePlacementSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("已选新包：\(selectedNewPackageIDs.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    newPackagePlacementControls
                    Spacer()
                }
                .padding(16)
                .frame(minWidth: 520, minHeight: 260)
                .navigationTitle("新包插入位置")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("返回") {
                            showNewPackagePlacementSheet = false
                            showClassUpdateSheet = true
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            showNewPackagePlacementSheet = false
                            runClassUpdate()
                        }
                        .disabled(selectedUpdateChapterPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showReflectionSheet) {
            reflectionSheetContent
        }
        .sheet(isPresented: $showSyncFailureSheet) {
            NavigationStack {
                List(syncFailureMessages, id: \.self) { message in
                    Text(message)
                        .font(.body)
                }
                .navigationTitle("更新失败明细")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { showSyncFailureSheet = false }
                    }
                }
            }
        }
        .alert("剪切包未处理", isPresented: $showPendingCutGuardAlert) {
            Button("回退剪切") {
                rollbackPendingCutPackageToOriginalLocation()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(pendingCutGuardMessage)
        }
    }

    private var saveIconName: String {
        switch saveState {
        case .clean: return "checkmark.circle"
        case .dirty: return "circle.fill"
        case .saving: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var saveIconColor: Color {
        switch saveState {
        case .clean:
            return .secondary
        case .dirty, .failed:
            return appHighlightBlue
        case .saving:
            return appHighlightBlue.opacity(0.75)
        }
    }

    private var saveButtonTier: AppButtonTier {
        saveState == .clean ? .regular : .prominent
    }

    private var preferredColorScheme: ColorScheme? {
        switch settingsCenter.documentStyle.preferredScheme {
        case .system:
            guard let preferredSchemeOverride else { return nil }
            return preferredSchemeOverride == .dark ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var editorBackgroundColor: Color {
        if settingsCenter.documentStyle.useSystemBackground {
            #if os(macOS)
            return Color(nsColor: .textBackgroundColor)
            #else
            return Color(uiColor: .systemBackground)
            #endif
        }
        return settingsCenter.documentStyle.editorBackgroundColor
    }

    private func loadFromDiskIfNeeded() {
        guard !isLoading else { return }
        reloadFromDisk()
    }

    /// 普通字符输入保持UUID、level和行序不变，可以直接复用索引。
    /// 只有无法证明是单行内容变化时，才比较结构并按需重建。
    private func synchronizeDocumentIndex(
        previousDocument: NodeMarkdownDocument,
        currentDocument: NodeMarkdownDocument,
        activeRowIndex: Int?,
        force: Bool = false
    ) {
        if force
            || documentIndex.nodeCount != previousDocument.nodes.count
            || previousDocument.nodes.count != currentDocument.nodes.count {
            documentIndex.rebuild(from: currentDocument.nodes)
            return
        }

        if let activeRowIndex,
           previousDocument.nodes.indices.contains(activeRowIndex),
           currentDocument.nodes.indices.contains(activeRowIndex) {
            let previous = previousDocument.nodes[activeRowIndex]
            let current = currentDocument.nodes[activeRowIndex]
            if previous.id == current.id, previous.level == current.level {
                return
            }
        }

        let structureChanged = zip(previousDocument.nodes, currentDocument.nodes).contains { previous, current in
            previous.id != current.id || previous.level != current.level
        }
        if structureChanged {
            documentIndex.rebuild(from: currentDocument.nodes)
        }
    }

    private func reloadFromDisk() {
        invalidatePendingTextKitParsing()
        // 磁盘加载和编辑器文本解析是两种不同事务。样式刷新、
        // 输入回调或草稿提交可以废弃旧解析，但绝不能把正在进行的
        // 首次磁盘加载一起废弃，否则isLoading没有收尾机会。
        diskLoadGeneration &+= 1
        let loadGeneration = diskLoadGeneration
        isLoading = true
        statusMessage = ""
        let targetURL = fileURL
        let styleSnapshot = settingsCenter.documentStyle
        let fileSizeBytes = ((try? FileManager.default.attributesOfItem(atPath: targetURL.path)[.size] as? NSNumber)?.int64Value) ?? 0
        let largeFileThreshold: Int64 = 2 * 1024 * 1024

        Task(priority: .userInitiated) {
            let loaded: (NodeMarkdownDocument, NodeMarkdownFileMeta)
            do {
                loaded = try NodeMarkdownFileManager.read(fileURL: targetURL)
            } catch {
                loaded = (
                    NodeMarkdownDocument(
                        nodes: [
                            NodeMarkdownNode(level: 1, text: "")
                        ]
                    ),
                    NodeMarkdownFileMeta(
                        title: targetURL.deletingPathExtension().lastPathComponent,
                        type: "nodemarkdown"
                    )
                )
            }
            var parsedDocument = loaded.0
            _ = parsedDocument.ensureTrailingBlankLine(defaultLevel: 1)
            restoreImageUndoStashForOpeningIfNeeded(document: parsedDocument)
            let rows = NodeMarkdownHTMLBuilder.buildRows(document: parsedDocument, style: styleSnapshot)
            let openingAnchorRowIndex = await TeachingCourseEditingAnchorStore.shared.activeRow(filePath: targetURL.path)
            if openingAnchorRowIndex != nil {
                await TeachingCourseEditingAnchorStore.shared.setActiveRow(filePath: targetURL.path, rowIndex: nil)
            }

            guard loadGeneration == diskLoadGeneration else {
                // 只有更新的磁盘加载才能使本次结果失效。旧任务
                // 退出时不改动新任务的loading状态。
                return
            }

            document = parsedDocument
            documentIndex.rebuild(from: parsedDocument.nodes)
            fileMeta = loaded.1
            rowsSnapshot = rows
            textKitDraft = NodeMarkdownPlainTextCodec.serialize(document: parsedDocument)
            textKitDraftRowMetadata = makeTextKitRowMetadata(for: parsedDocument)
            // 编辑器通常先于异步磁盘读取创建。正文与Node身份装载完成后必须同时
            // 推进外部同步版本，否则TextKit会把这次真实载入误判成“没有新文档”。
            externalTextSyncToken &+= 1
            let safeOpeningRowIndex = openingAnchorRowIndex.flatMap { rowIndex in
                parsedDocument.nodes.indices.contains(rowIndex) ? rowIndex : nil
            }
            activeSearchRowIndex = safeOpeningRowIndex
            activeEditorRowIndex = safeOpeningRowIndex
            preferredSchemeOverride = nil
            loadedFileSizeBytes = fileSizeBytes
            isLargeFileMode = fileSizeBytes >= largeFileThreshold
            isLoading = false
            documentRevision = 0
            persistedDocumentRevision = 0
            saveState = .clean
            if isLargeFileMode {
                statusMessage = "已启用大文件模式（\(ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file))）"
            }
            rebuildSearchResults()
            packageChangeTracker.establishBaseline(document: document)
            if isClassSessionEditor {
                packageChangeTracker.beginTrackingRow(
                    rowIndex: activeEditorRowIndex,
                    document: document,
                    structuralIndex: documentIndex
                )
                refreshLocalPackageListsAndLight()
            } else {
                dirtyPackageItems = []
                newPackageItems = []
            }
        }
    }

    @ViewBuilder
    private var editorSurface: some View {
        if isReadOnlyRendered {
            readOnlyRenderSurface
        } else if NodeMarkdownFeatureFlags.textKit2EditorEnabled {
            textKit2EditorSurface
        } else {
            textKitEditorSurface
        }
    }

    private var readOnlyRenderSurface: some View {
        #if os(iOS)
        NodeMarkdownReadOnlyRenderView(
            rowsHTML: rowsSnapshot,
            baseURL: fileURL.deletingLastPathComponent()
        )
        .ignoresSafeArea(edges: .bottom)
        #else
        NodeMarkdownReadOnlyRenderView(rowsHTML: rowsSnapshot)
            .ignoresSafeArea(edges: .bottom)
        #endif
    }

    private var textKit2EditorSurface: some View {
        NodeMarkdownTextKit2Editor(
            text: $textKitDraft,
            workingDirectoryURL: fileURL.deletingLastPathComponent(),
            documentStyle: settingsCenter.documentStyle,
            activeRowIndex: activeSearchRowIndex,
            activeMatchLocationInRow: activeSearchMatchLocationInRow,
            editingRowIndex: activeEditorRowIndex,
            searchQuery: searchQuery,
            rowMetadata: textKitDraftRowMetadata,
            externalTextSyncToken: externalTextSyncToken,
            quickInputSettings: settingsCenter.quickInputSettings,
            onTextChange: { newText in
                queueTextKitParse(with: newText)
            },
            onTextChangeWithRowMetadata: { newText, rowMetadata in
                queueTextKitParse(with: newText, rowMetadataSnapshot: rowMetadata)
            },
            onRequestInsertImageAtRow: { rowIndex in
                prepareImageTextAtRow(rowIndex)
            },
            onRequestDeleteNodePackageAtRow: { rowIndex in
                deleteNodePackageAtRow(rowIndex)
            },
            onRequestCutNodePackageAtRow: { rowIndex in
                cutNodePackageAtRow(rowIndex)
            },
            onRequestPasteNodePackageAfterRow: { rowIndex in
                pasteNodePackageAfterRow(rowIndex)
            },
            canPasteNodePackage: {
                !pendingCutPackageNodes.isEmpty
            },
            onRequestDeleteProtectedH3AtRow: { rowIndex in
                deleteProtectedH3PackageAtRow(rowIndex)
            },
            onRequestOpenDrawingBoardAtRow: { rowIndex in
                openDrawingBoardAtRow(rowIndex)
            },
            onActiveRowChange: { rowIndex in
                handleActiveEditorRowChange(rowIndex)
            },
            onFocusLocationChange: { location in
                textKit2FocusLocation = location
            },
            onInputSessionStateChange: { isActive in
                isTextInputSessionActive = isActive
            }
        )
    }

    private var textKitEditorSurface: some View {
        NodeMarkdownTextKitEditor(
            text: $textKitDraft,
            workingDirectoryURL: fileURL.deletingLastPathComponent(),
            documentStyle: settingsCenter.documentStyle,
            activeRowIndex: activeSearchRowIndex,
            activeMatchLocationInRow: activeSearchMatchLocationInRow,
            editingRowIndex: activeEditorRowIndex,
            searchQuery: searchQuery,
            rowMetadata: textKitDraftRowMetadata,
            externalTextSyncToken: externalTextSyncToken,
            quickInputSettings: settingsCenter.quickInputSettings,
            legacyDraftCommitController: legacyDraftCommitController,
            onTextChange: { newText in
                queueTextKitParse(with: newText)
            },
            onRequestInsertImageAtRow: { rowIndex in
                prepareImageTextAtRow(rowIndex)
            },
            onRequestDeleteNodePackageAtRow: { rowIndex in
                deleteNodePackageAtRow(rowIndex)
            },
            onRequestCutNodePackageAtRow: { rowIndex in
                cutNodePackageAtRow(rowIndex)
            },
            onRequestPasteNodePackageAfterRow: { rowIndex in
                pasteNodePackageAfterRow(rowIndex)
            },
            canPasteNodePackage: {
                !pendingCutPackageNodes.isEmpty
            },
            onRequestDeleteProtectedH3AtRow: { rowIndex in
                deleteProtectedH3PackageAtRow(rowIndex)
            },
            onRequestOpenDrawingBoardAtRow: { rowIndex in
                openDrawingBoardAtRow(rowIndex)
            },
            onActiveRowChange: { rowIndex in
                handleActiveEditorRowChange(rowIndex)
            },
            onTextChangeWithRowMetadata: nil,
            onLegacyDocumentSnapshot: { snapshot in
                queueLegacyDocumentSnapshot(snapshot)
            },
            onCommitEditingNode: { draft in
                commitLegacyEditingNode(draft)
            },
            onEditingDraftDirtyChange: { isDirty in
                handleLegacyEditingDraftDirtyChange(isDirty)
            },
            onInputSessionStateChange: { isActive in
                isTextInputSessionActive = isActive
            }
        )
    }

    @ViewBuilder
    private var searchFloatingPanel: some View {
        if shouldShowSearchFloatingPanel {
            NodeMarkdownSearchFloatingPanelView(
                query: searchQuery,
                results: searchResults,
                activeIndex: activeSearchResultIndex,
                onSelect: { index in
                    selectSearchResult(at: index)
                },
                onClose: {
                    clearSearchState()
                    showSearchPopover = false
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 10)
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var textKit2FocusLocationPanel: some View {
        if shouldShowTextKit2FocusLocationOverlay {
            textKit2FocusLocationOverlay
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
                .allowsHitTesting(false)
        }
    }

    private var reflectionSheetContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                reflectionToolbar
                    .padding(12)
                reflectionEditorContent
            }
            .navigationTitle("课反")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showReflectionSheet = false }
                }
            }
        }
        .singleListAdaptivePresentation(minWidth: 900, minHeight: 620)
    }

    private var reflectionToolbar: some View {
        HStack(spacing: 8) {
            Button { stepReflection(delta: -1) } label: { Image(systemName: "chevron.left") }
                .appGlassButtonStyle()
                .disabled(reflectionFiles.isEmpty || reflectionShowStudentInfo)
            Button { stepReflection(delta: 1) } label: { Image(systemName: "chevron.right") }
                .appGlassButtonStyle()
                .disabled(reflectionFiles.isEmpty || reflectionShowStudentInfo)
            Button { reflectionShowStudentInfo.toggle() } label: {
                Label(reflectionShowStudentInfo ? "课" : "主", systemImage: reflectionShowStudentInfo ? "doc.text" : "person.text.rectangle")
            }
                .appGlassButtonStyle()
                .disabled(studentInfoReflectionURL == nil)
            Spacer()
            Button { reflectionExportImageToken += 1 } label: {
                Label("导出", systemImage: "square.and.arrow.up.on.square")
            }
            .appGlassButtonStyle()
            .disabled(currentReflectionFileURL == nil)
        }
    }

    @ViewBuilder
    private var reflectionEditorContent: some View {
        if let currentURL = currentReflectionFileURL {
            SingleListDocumentEditorView(
                fileURL: currentURL,
                externalExportImageToken: reflectionExportImageToken,
                showsReflectionSiblingNavigation: false
            )
                .id(currentURL.path)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(macOS)
                .frame(minHeight: 520)
            #endif
        } else {
            ContentUnavailableView("无可用文件", systemImage: "doc")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(macOS)
                .frame(minHeight: 520)
            #endif
        }
    }

    private func handleSaveStateChange(oldValue: MarkdownSaveState, newValue: MarkdownSaveState) {
        guard newValue == .dirty else { return }
        scheduleRealtimeCourseUpdatePush()
    }

    private func handleTextInputSessionChange(oldValue: Bool, newValue isActive: Bool) {
        guard !isActive else { return }
        guard saveState == .dirty else { return }
        scheduleRealtimeCourseUpdatePush()
    }

    private func markDocumentDirty() {
        documentRevision &+= 1
        saveState = .dirty
        scheduleRealtimeCourseUpdatePush()
    }

    private func handleLegacyEditingDraftDirtyChange(_ isDirty: Bool) {
        guard hasUncommittedLegacyDraft != isDirty else { return }
        hasUncommittedLegacyDraft = isDirty
        if isDirty {
            // 活动行已经和落盘文档不同，不等失焦就进入未保存状态。
            markDocumentDirty()
        }
    }

    private func beginExclusiveNotebookOperation() {
        isNotebookWriteOperationInProgress = true
        // 外部插包期间用透明遮罩阻止继续输入，但保留活动行、第一响应者和视野。
        // 清空焦点会让TextKit重新滚到文首或活动行，是此前“随堂一插入就跳”的根因。
    }

    private func endExclusiveNotebookOperation() {
        isNotebookWriteOperationInProgress = false
    }

    private func saveToDisk() {
        // 已经在保存的任务由版本检查负责追赶最新修改，
        // 不再并发启动第二个写入任务。
        guard saveState != .saving else { return }
        commitPendingDraftBeforeSyncIfNeeded()
        // Command+S在没有新修改时是纯空操作，不进入saving，
        // 也不启动后续脏包同步。失败状态仍允许用户重试。
        if saveState == .clean, documentRevision == persistedDocumentRevision {
            return
        }
        guard canPersistCurrentDocument() else { return }
        restoreH3SourceLinksFromDiskIfNeeded()
        restoreReferencedImageAssets()
        saveState = .saving
        let targetURL = fileURL
        let documentSnapshot = document
        let revisionSnapshot = documentRevision
        let writeKey = TeachingCourseWriteCoordinator.key(forNotebookURL: targetURL)
        var metaSnapshot = fileMeta
        if metaSnapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metaSnapshot.title = targetURL.deletingPathExtension().lastPathComponent
        }
        if metaSnapshot.type.lowercased() == "nodesmarkdown" {
            metaSnapshot.type = "nodemarkdown"
        }
        if metaSnapshot.type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metaSnapshot.type = "nodemarkdown"
        }

        Task(priority: .utility) {
            await TeachingCourseWriteCoordinator.shared.acquire(key: writeKey)
            guard revisionSnapshot == documentRevision else {
                await TeachingCourseWriteCoordinator.shared.release(key: writeKey)
                // 旧任务排队时又产生了新编辑。旧快照不能写入，
                // 但也不能把saving永久留下；先明确回到dirty，
                // 再由同一串行入口保存最新版本。
                saveState = .dirty
                saveToDisk()
                return
            }
            do {
                var persistenceDocument = documentSnapshot
                if let diskDocument = try? NodeMarkdownFileManager.read(fileURL: targetURL).0 {
                    _ = persistenceDocument.touchChangedH3Packages(comparedTo: diskDocument)
                    persistenceDocument.propagateChildMtimeToH3Roots()
                }
                try NodeMarkdownFileManager.write(document: persistenceDocument, meta: metaSnapshot, to: targetURL)
                await TeachingCourseWriteCoordinator.shared.release(key: writeKey)
                guard revisionSnapshot == documentRevision else {
                    saveState = .dirty
                    scheduleRealtimeCourseUpdatePush()
                    return
                }
                persistedDocumentRevision = revisionSnapshot
                document = persistenceDocument
                saveState = .clean
                statusMessage = ""
                fileMeta = metaSnapshot
                postNotebookPersistedChangeIfNeeded()
                if isClassSessionEditor { syncDirtyPackagesAfterClassSave() }
            } catch {
                await TeachingCourseWriteCoordinator.shared.release(key: writeKey)
                saveState = .failed
                statusMessage = error.localizedDescription
            }
        }
    }

    private func persistCurrentDocumentToDiskForSync(cleanForFinalization: Bool = false) async throws {
        commitPendingDraftBeforeSyncIfNeeded()
        guard canPersistCurrentDocument() else {
            let message = pendingCutGuardMessage.isEmpty
                ? "当前Node身份检查未通过，禁止保存"
                : pendingCutGuardMessage
            throw NSError(domain: "NodeMarkdown", code: 9001, userInfo: [NSLocalizedDescriptionKey: message])
        }
        if cleanForFinalization {
            cleanEmptyNodesBeforePersist()
        }
        restoreH3SourceLinksFromDiskIfNeeded()
        var metaSnapshot = fileMeta
        if metaSnapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metaSnapshot.title = fileURL.deletingPathExtension().lastPathComponent
        }
        if metaSnapshot.type.lowercased() == "nodesmarkdown" {
            metaSnapshot.type = "nodemarkdown"
        }
        if metaSnapshot.type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metaSnapshot.type = "nodemarkdown"
        }
        restoreReferencedImageAssets()
        let revisionSnapshot = documentRevision
        let documentSnapshot = document
        let writeKey = TeachingCourseWriteCoordinator.key(forNotebookURL: fileURL)
        await TeachingCourseWriteCoordinator.shared.acquire(key: writeKey)
        guard revisionSnapshot == documentRevision else {
            await TeachingCourseWriteCoordinator.shared.release(key: writeKey)
            try await persistCurrentDocumentToDiskForSync(cleanForFinalization: cleanForFinalization)
            return
        }
        do {
            var persistenceDocument = documentSnapshot
                if let diskDocument = try? NodeMarkdownFileManager.read(fileURL: fileURL).0 {
                    _ = persistenceDocument.touchChangedH3Packages(comparedTo: diskDocument)
                    persistenceDocument.propagateChildMtimeToH3Roots()
                }
                try NodeMarkdownFileManager.write(document: persistenceDocument, meta: metaSnapshot, to: fileURL)
            await TeachingCourseWriteCoordinator.shared.release(key: writeKey)
            if documentRevision == revisionSnapshot {
                document = persistenceDocument
            }
        } catch {
            await TeachingCourseWriteCoordinator.shared.release(key: writeKey)
            throw error
        }
        persistedDocumentRevision = revisionSnapshot
        if documentRevision == revisionSnapshot {
            saveState = .clean
        }
        fileMeta = metaSnapshot
        postNotebookPersistedChangeIfNeeded()
    }

    private func cleanEmptyNodesBeforePersist() {
        let previousDocument = document
        let previousActiveRowIndex = activeEditorRowIndex
        let activeNodeID = previousActiveRowIndex.flatMap { rowIndex in
            document.nodes.indices.contains(rowIndex) ? document.nodes[rowIndex].id : nil
        }
        let precedingNodeID = previousActiveRowIndex.flatMap { rowIndex -> UUID? in
            guard rowIndex > 0 else { return nil }
            return document.nodes[rowIndex - 1].id
        }
        let removedCount = NodeMarkdownPackageCleaner.cleanDocument(&document)
        guard removedCount > 0 else { return }
        synchronizeDocumentIndex(
            previousDocument: previousDocument,
            currentDocument: document,
            activeRowIndex: nil,
            force: true
        )
        let activeNodeRow = activeNodeID.flatMap { documentIndex.row(for: $0) }
        let precedingNodeRow = precedingNodeID.flatMap { documentIndex.row(for: $0) }
        activeEditorRowIndex = activeNodeRow ?? precedingNodeRow
        if activeNodeID != nil, activeNodeRow == nil, let precedingNodeRow {
            legacyDraftCommitController.focusAtEnd(ofRow: precedingNodeRow)
        }
        if activeEditorRowIndex == nil {
            textKit2FocusLocation = nil
        }
        refreshTextKitDraftFromDocument(forceExternalSync: true)
        scheduleSnapshotRebuild()
        // 若被清掉的正是焦点空行，保留第一响应者。旧管线的绝对选择位置会
        // 在外部文本替换时收紧到上一行末尾；新管线按保留下来的上一Node恢复。
    }

    private func restoreH3SourceLinksFromDiskIfNeeded() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let diskPayload = try? NodeMarkdownFileManager.read(fileURL: fileURL) else { return }
        let restoredCount = document.restoreMissingH3SourceLinks(from: diskPayload.0)
        guard restoredCount > 0 else { return }
        textKitDraftRowMetadata = textKitRowMetadata
    }

    private func syncDirtyPackagesAfterClassSave() {
        guard let student = resolveStudentForNotebook() else { return }
        Task(priority: .userInitiated) {
            do {
                // Command+S只落盘当前Node快照，不清洗并重载整篇随堂笔记。
                // 同步引擎在每个H3包写回母本前已经统一调用cleanPackage，
                // 因此这里再执行cleanDocument只会改变编辑器行布局并使视野跳动。
                // 下课和关闭仍走cleanForFinalization=true，负责最终整篇整理。
                try await persistCurrentDocumentToDiskForSync(cleanForFinalization: false)
                let summary = try await TeachingCoursePackageSyncExecutor.syncDirtyPackages(
                    student: student,
                    placementTarget: nil,
                    allowedNewPackageIDs: []
                )
                await MainActor.run {
                    let syncedDirtyIDs = Set(
                        summary.packageResults
                            .filter {
                                $0.success
                                    && !$0.isNewPackage
                                    && $0.reason != "mother-source update pending; active notebook preserved"
                            }
                            .map(\.sourceID)
                            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    )
                    packageChangeTracker.removeDirtyPackages(sourceIDs: syncedDirtyIDs, document: document)
                    refreshLocalPackageListsAndLight()
                    refreshPendingClassUpdateCount()
                    if dirtyPackageItems.isEmpty {
                        pendingClassUpdateCount = newPackageItems.count
                    }
                    if statusMessage.isEmpty {
                        statusMessage = "已保存并同步脏包。"
                    }
                }
            } catch {
                await MainActor.run {
                    statusMessage = "已保存，脏包同步失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func syncAllClassSessionPackagesForClose(student: TeachingStudentItem) async throws -> TeachingCourseSyncSummary {
        try await TeachingCoursePackageSyncExecutor.syncDirtyPackages(
            student: student,
            placementTarget: nil,
            allowedNewPackageIDs: nil
        )
    }

    private func saveAndSyncClassSessionForClose() async throws {
        commitPendingDraftBeforeSyncIfNeeded()
        try await persistCurrentDocumentToDiskForSync(cleanForFinalization: true)
        saveState = .clean
        guard let student = resolveStudentForNotebook() else { return }
        let summary = try await syncAllClassSessionPackagesForClose(student: student)
        let failed = summary.packageResults.filter { !$0.success }
        if failed.isEmpty {
            packageChangeTracker.resetLocalQueues()
            dirtyPackageItems = []
            newPackageItems = []
            pendingClassUpdateCount = packageChangeTracker.resetPendingCount()
            statusMessage = "同步完成：回传\(summary.updatedSourcePackageCount) 新收集\(summary.collectedNewPackageCount) 冲突\(summary.conflictPackageCount)"
        } else {
            syncFailureMessages = failed.map { item in
                let title = item.packageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayTitle = title.isEmpty ? "(空标题H3)" : title
                return "\(displayTitle)：\(item.reason)"
            }
            showSyncFailureSheet = true
            throw NSError(
                domain: "NodeMarkdown",
                code: 9102,
                userInfo: [NSLocalizedDescriptionKey: "同步部分失败：失败\(failed.count)个包"]
            )
        }
    }

    private func saveAndSyncClassSessionForWindowClose(finishClass: Bool) {
        guard pendingCutPackageNodes.isEmpty else { return }
        guard let student = resolveStudentForNotebook() else { return }
        let session = TeachingClassSessionCenter.shared.session
        Task(priority: .userInitiated) {
            do {
                try await persistCurrentDocumentToDiskForSync(cleanForFinalization: true)
                _ = try await syncAllClassSessionPackagesForClose(student: student)
                if finishClass {
                    session?.onFinishClass()
                } else {
                    session?.onExitSession()
                }
                TeachingClassSessionCenter.shared.end()
            } catch {
                await MainActor.run {
                    statusMessage = "关闭前同步失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func commitPendingDraftBeforeSyncIfNeeded() {
        legacyDraftCommitController.commitPendingEditing()
        pendingTextKitParseTask?.cancel()
        let serialized = NodeMarkdownPlainTextCodec.serialize(document: document)
        guard textKitDraft != serialized else { return }
        let previousDocument = document
        var parsed: NodeMarkdownDocument
        if !NodeMarkdownFeatureFlags.textKit2EditorEnabled,
           let snapshot = latestLegacyDocumentSnapshot,
           snapshot.plainText == textKitDraft {
            parsed = NodeMarkdownPlainTextCodec.parse(
                snapshot: snapshot,
                previousNodes: previousDocument.nodes
            )
        } else {
            parsed = NodeMarkdownPlainTextCodec.parse(
                text: textKitDraft,
                previousNodes: previousDocument.nodes,
                rowMetadata: textKitDraftRowMetadata
            )
        }
        _ = parsed.restoreMissingH3SourceLinks(from: previousDocument)
        let touchedH3IDs = parsed.touchChangedH3Packages(comparedTo: previousDocument)
        parsed.propagateChildMtimeToH3Roots()
        document = parsed
        synchronizeDocumentIndex(
            previousDocument: previousDocument,
            currentDocument: parsed,
            activeRowIndex: activeEditorRowIndex
        )
        cleanupUnusedImageAssets(previousDocument: previousDocument, currentDocument: parsed)
        _ = packageChangeTracker.recordTouchedH3Packages(h3NodeIDs: touchedH3IDs, document: parsed)
        if isClassSessionEditor {
            _ = packageChangeTracker.recordParseMutation(
                previousDocument: previousDocument,
                currentDocument: parsed,
                activeRowIndex: activeEditorRowIndex
            )
            refreshLocalPackageListsAndLight()
        }
        markDocumentDirty()
        scheduleSnapshotRebuild()
        rebuildSearchResults()
    }

    private func queueTextKitParse(with newText: String) {
        queueTextKitParse(with: newText, rowMetadataSnapshot: textKitDraftRowMetadata)
    }

    /// 旧管线结构操作的唯一入口。正文和Node身份已经封装在同一份带版本快照中，
    /// 父页不得再分别读取`textKitDraft`和`textKitDraftRowMetadata`来拼装一次修改。
    private func queueLegacyDocumentSnapshot(_ snapshot: NodeMarkdownLegacyDocumentSnapshot) {
        guard !isNotebookWriteOperationInProgress else { return }
        latestLegacyDocumentSnapshot = snapshot
        textKitDraft = snapshot.plainText
        textKitDraftRowMetadata = snapshot.rowMetadata
        if snapshot.plainText == NodeMarkdownPlainTextCodec.serialize(document: document),
           snapshot.rowMetadata == textKitRowMetadata {
            return
        }

        let previousDocument = document
        let activeRowIndexSnapshot = activeEditorRowIndex
        pendingTextKitParseTask?.cancel()
        textKitParseGeneration &+= 1
        let parseGeneration = textKitParseGeneration
        pendingTextKitParseTask = Task {
            let parseDelay: UInt64 = isLargeFileMode ? 180_000_000 : 50_000_000
            try? await Task.sleep(nanoseconds: parseDelay)
            guard !Task.isCancelled,
                  parseGeneration == textKitParseGeneration,
                  latestLegacyDocumentSnapshot?.sessionID == snapshot.sessionID,
                  latestLegacyDocumentSnapshot?.revision == snapshot.revision else { return }

            var parsed = NodeMarkdownPlainTextCodec.parse(
                snapshot: snapshot,
                previousNodes: previousDocument.nodes
            )
            _ = parsed.restoreMissingH3SourceLinks(from: previousDocument)
            let touchedH3IDs = parsed.touchChangedH3Packages(comparedTo: previousDocument)
            guard !Task.isCancelled,
                  parseGeneration == textKitParseGeneration,
                  latestLegacyDocumentSnapshot?.sessionID == snapshot.sessionID,
                  latestLegacyDocumentSnapshot?.revision == snapshot.revision else { return }

            document = parsed
            synchronizeDocumentIndex(
                previousDocument: previousDocument,
                currentDocument: parsed,
                activeRowIndex: activeRowIndexSnapshot
            )
            textKitDraft = snapshot.plainText
            textKitDraftRowMetadata = makeTextKitRowMetadata(for: parsed)
            cleanupUnusedImageAssets(previousDocument: previousDocument, currentDocument: parsed)
            _ = packageChangeTracker.recordTouchedH3Packages(h3NodeIDs: touchedH3IDs, document: parsed)
            if isClassSessionEditor {
                _ = packageChangeTracker.recordParseMutation(
                    previousDocument: previousDocument,
                    currentDocument: parsed,
                    activeRowIndex: activeRowIndexSnapshot
                )
                refreshLocalPackageListsAndLight()
            }
            markDocumentDirty()
            scheduleSnapshotRebuild()
            rebuildSearchResults()
        }
    }

    /// 旧管线失焦提交只按UUID更新一个Node。正文已经不含`### `等层级前缀，
    /// 因此level和Source信息必须来自编辑暂存，不能再从Content反推。
    private func commitLegacyEditingNode(_ draft: NodeMarkdownLegacyEditingNodeDraft) {
        guard let nodeID = UUID(uuidString: draft.nodeID),
              let rowIndex = documentIndex.row(for: nodeID),
              document.nodes.indices.contains(rowIndex) else {
            statusMessage = "编辑行身份已失效，本次内容未写入。"
            return
        }

        let previousDocument = document
        let previousNode = previousDocument.nodes[rowIndex]
        let requestedLevel = max(1, min(12, draft.level))
        let level = previousNode.level == 3
            && !previousNode.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !previousNode.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? 3
            : requestedLevel
        let sourceID: String
        let sourceFile: String
        if level == 3 {
            sourceID = draft.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? previousNode.sourceID
                : draft.sourceID
            sourceFile = draft.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? previousNode.sourceFile
                : draft.sourceFile
        } else {
            sourceID = ""
            sourceFile = ""
        }

        guard previousNode.level != level
                || previousNode.text != draft.content
                || previousNode.sourceID != sourceID
                || previousNode.sourceFile != sourceFile else { return }

        pendingTextKitParseTask?.cancel()
        latestLegacyDocumentSnapshot = nil
        var updatedDocument = previousDocument
        updatedDocument.nodes[rowIndex].level = level
        updatedDocument.nodes[rowIndex].text = draft.content
        updatedDocument.nodes[rowIndex].sourceID = sourceID
        updatedDocument.nodes[rowIndex].sourceFile = sourceFile
        var updatedIndex = documentIndex
        if previousNode.level != level {
            updatedIndex.rebuild(from: updatedDocument.nodes)
        }
        updatedDocument.touchMutation(
            at: rowIndex,
            changedLevelOrText: true,
            structuralIndex: updatedIndex
        )
        _ = updatedDocument.touchChangedH3Packages(
            comparedTo: previousDocument,
            affectedRowIndex: rowIndex
        )
        document = updatedDocument
        documentIndex = updatedIndex
        textKitDraft = NodeMarkdownPlainTextCodec.serialize(document: updatedDocument)
        textKitDraftRowMetadata = makeTextKitRowMetadata(for: updatedDocument)
        cleanupUnusedImageAssets(previousDocument: previousDocument, currentDocument: updatedDocument)
        if isClassSessionEditor {
            _ = packageChangeTracker.recordDocumentMutation(
                previousDocument: previousDocument,
                currentDocument: updatedDocument
            )
            refreshLocalPackageListsAndLight()
        }
        markDocumentDirty()
        scheduleSnapshotRebuild()
        rebuildSearchResults()
    }

    private func queueTextKitParse(
        with newText: String,
        rowMetadataSnapshot: [NodeMarkdownTextKitRowMetadata]
    ) {
        guard !isNotebookWriteOperationInProgress else { return }
        latestLegacyDocumentSnapshot = nil
        // 正文与行身份必须在同一次主线程事务中发布，禁止出现新正文配旧元数据。
        textKitDraft = newText
        textKitDraftRowMetadata = rowMetadataSnapshot
        if newText == NodeMarkdownPlainTextCodec.serialize(document: document),
           rowMetadataSnapshot == textKitRowMetadata {
            return
        }
        let previousDocument = document
        let activeRowIndexSnapshot = activeEditorRowIndex
        pendingTextKitParseTask?.cancel()
        textKitParseGeneration &+= 1
        let parseGeneration = textKitParseGeneration
        pendingTextKitParseTask = Task {
            let parseDelay: UInt64 = isLargeFileMode ? 180_000_000 : 50_000_000
            try? await Task.sleep(nanoseconds: parseDelay)
            guard !Task.isCancelled, parseGeneration == textKitParseGeneration else { return }
            var parsed = NodeMarkdownPlainTextCodec.parse(
                text: newText,
                previousNodes: previousDocument.nodes,
                rowMetadata: rowMetadataSnapshot
            )
            _ = parsed.restoreMissingH3SourceLinks(from: previousDocument)
            let touchedH3IDs = parsed.touchChangedH3Packages(comparedTo: previousDocument)
            parsed.propagateChildMtimeToH3Roots()
            await MainActor.run {
                guard !Task.isCancelled, parseGeneration == textKitParseGeneration else { return }
                document = parsed
                synchronizeDocumentIndex(
                    previousDocument: previousDocument,
                    currentDocument: parsed,
                    activeRowIndex: activeRowIndexSnapshot
                )
                textKitDraftRowMetadata = textKitRowMetadata
                cleanupUnusedImageAssets(previousDocument: previousDocument, currentDocument: parsed)
                _ = packageChangeTracker.recordTouchedH3Packages(h3NodeIDs: touchedH3IDs, document: parsed)
                if isClassSessionEditor {
                    _ = packageChangeTracker.recordParseMutation(
                        previousDocument: previousDocument,
                        currentDocument: parsed,
                        activeRowIndex: activeRowIndexSnapshot
                    )
                    refreshLocalPackageListsAndLight()
                }
                markDocumentDirty()
                scheduleSnapshotRebuild()
                rebuildSearchResults()
            }
        }
    }

    private func scheduleSnapshotRebuild() {
        let documentSnapshot = document
        let styleSnapshot = settingsCenter.documentStyle
        pendingRebuildTask?.cancel()
        pendingRebuildTask = Task {
            let rebuildDelay: UInt64 = isLargeFileMode ? 220_000_000 : 60_000_000
            try? await Task.sleep(nanoseconds: rebuildDelay)
            guard !Task.isCancelled else { return }
            let rows = NodeMarkdownHTMLBuilder.buildRows(document: documentSnapshot, style: styleSnapshot)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                rowsSnapshot = rows
                rebuildSearchResults()
            }
        }
    }

    private func saveBeforeClosing() {
        if !pendingCutPackageNodes.isEmpty {
            statusMessage = "存在未粘贴的剪切包，请先粘贴或撤销后再退出"
            return
        }
        commitPendingDraftBeforeSyncIfNeeded()
        guard saveState == .dirty else { return }
        saveToDisk()
    }

    private func autoSaveLoop() async {
        while !Task.isCancelled {
            let autoSaveInterval: UInt64 = isLargeFileMode ? 120_000_000_000 : 60_000_000_000
            try? await Task.sleep(nanoseconds: autoSaveInterval)
            guard !Task.isCancelled else { return }
            guard saveState == .dirty else { continue }
            guard !isTextInputSessionActive else { continue }
            saveToDisk()
        }
    }

    private func scheduleRealtimeCourseUpdatePush() {
        guard isTeachingNotebookFile else { return }
        pendingRealtimeCoursePushTask?.cancel()
        pendingRealtimeCoursePushTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard saveState == .dirty else { return }
                guard !isTextInputSessionActive else { return }
                saveToDisk()
            }
        }
    }

    private var isTeachingNotebookFile: Bool {
        let name = fileURL.lastPathComponent.lowercased()
        return name.hasPrefix("随堂笔记_") && name.hasSuffix(".csv")
    }

    private func postNotebookPersistedChangeIfNeeded() {
        guard isTeachingNotebookFile else { return }
        NotificationCenter.default.post(
            name: .teachingNotebookDidPersistChange,
            object: nil,
            userInfo: [
                "filePath": fileURL.path,
                "sourceEditorID": editorInstanceID
            ]
        )
    }

    private func refreshTextKitDraftFromDocument(forceExternalSync: Bool = false) {
        invalidatePendingTextKitParsing()
        textKitDraft = NodeMarkdownPlainTextCodec.serialize(document: document)
        textKitDraftRowMetadata = textKitRowMetadata
        if forceExternalSync {
            externalTextSyncToken &+= 1
        }
    }

    /// 外部插包、结构操作和磁盘重载会更换整份Node快照；旧编辑回调从这一刻起永久失效。
    private func invalidatePendingTextKitParsing() {
        pendingTextKitParseTask?.cancel()
        pendingTextKitParseTask = nil
        latestLegacyDocumentSnapshot = nil
        textKitParseGeneration &+= 1
    }

    private var headings: [NodeMarkdownHeading] {
        document.nodes.enumerated().compactMap { index, node in
            guard (1...6).contains(node.level) else { return nil }
            let title = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return NodeMarkdownHeading(nodeID: node.id, level: node.level, title: title, rowIndex: index)
        }
    }

    private var textKitRowMetadata: [NodeMarkdownTextKitRowMetadata] {
        makeTextKitRowMetadata(for: document)
    }

    private func makeTextKitRowMetadata(
        for sourceDocument: NodeMarkdownDocument
    ) -> [NodeMarkdownTextKitRowMetadata] {
        sourceDocument.nodes.map { node in
            NodeMarkdownTextKitRowMetadata(
                nodeID: node.id.uuidString,
                level: node.level,
                sourceID: node.sourceID,
                sourceFile: node.sourceFile
            )
        }
    }

    private var searchQuery: String {
        committedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeSearchMatchLocationInRow: Int? {
        guard let activeSearchResultIndex,
              searchResults.indices.contains(activeSearchResultIndex) else { return nil }
        return searchResults[activeSearchResultIndex].matchLocationInRow
    }

    private var shouldShowSearchFloatingPanel: Bool {
        !searchResults.isEmpty
    }

    private var shouldShowTextKit2FocusLocationOverlay: Bool {
        NodeMarkdownFeatureFlags.textKit2EditorEnabled
            && TeachingDebugLogStore.isTextKit2FocusLocationOverlayEnabled()
            && textKit2FocusLocation != nil
    }

    private var isClassSessionEditor: Bool {
        activeClassSession != nil
    }

    private var activeClassSession: TeachingClassSessionCenter.Session? {
        _ = classSessionRefreshToken
        guard let session = TeachingClassSessionCenter.shared.session else { return nil }
        let currentPath = fileURL.standardizedFileURL.path
        guard session.notebookPath == currentPath else { return nil }
        return session
    }

    private func closeReadOnlyClassSessionIfNeeded() {
        if isClassSessionEditor {
            closeClassSessionAfterSync(finishClass: false)
            return
        }
        dismiss()
    }

    private func closeClassSessionAfterSync(finishClass: Bool) {
        guard !isClosingClassSessionWithSync else { return }
        guard pendingCutPackageNodes.isEmpty else {
            presentPendingCutGuard(message: "存在未粘贴的剪切包，不能关闭。请先粘贴或回退剪切。")
            return
        }
        isClosingClassSessionWithSync = true
        TeachingClassSessionCenter.shared.markToolbarFinishing()
        statusMessage = finishClass ? "正在保存并同步后下课..." : "正在保存并同步后退出..."
        let session = activeClassSession
        Task(priority: .userInitiated) {
            do {
                try await saveAndSyncClassSessionForClose()
                await MainActor.run {
                    if finishClass {
                        session?.onFinishClass()
                    } else {
                        session?.onExitSession()
                    }
                    finalizeImageUndoStashAfterSuccessfulClose()
                    TeachingClassSessionCenter.shared.end()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isClosingClassSessionWithSync = false
                    statusMessage = "关闭前同步失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private var classSessionToolbar: some View {
        Group {
            Button {
                loadLessonCompletionFiles()
            } label: {
                Label("随堂", systemImage: "book.closed")
            }
            .buttonStyle(.plain)
            .focusable(false)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        freezeCourseInsertAnchorIfNeeded()
                    }
            )

            Button {
                requestClassUpdatePreview()
            } label: {
                Label("更新", systemImage: "arrow.clockwise")
                    .overlay(alignment: .topTrailing) {
                        if hasPendingCutPackage {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 4, y: -4)
                                .accessibilityLabel("剪切包待处理")
                        }
                    }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(pendingClassUpdateCount > 0 ? appHighlightBlue : .clear)
            )
            .foregroundStyle(pendingClassUpdateCount > 0 ? .white : .primary)

            if activeClassSession?.kind == .teaching {
                Button {
                    openReflectionInNode()
                } label: {
                    Label("课反", systemImage: "square.and.pencil")
                }
                .buttonStyle(.plain)
            }

            if !isReadOnlyRendered {
                Button {
                    closeClassSessionAfterSync(finishClass: true)
                } label: {
                    Label("下课", systemImage: "stop.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

            Button {
                closeReadOnlyClassSessionIfNeeded()
            } label: {
                Label("退出", systemImage: "xmark")
            }
            .buttonStyle(.plain)

            TeachingAnnotationToolbarControl(controller: annotationController)
        }
    }

    private func loadLessonCompletionFiles() {
        do {
            // 手势按下阶段应当已经冻结；键盘快捷触发等路径在这里补一次。
            freezeCourseInsertAnchorIfNeeded()
            let storedActiveRow: Int? = {
                guard case let .node(nodeID) = pendingCourseInsertAnchor else { return nil }
                return documentIndex.row(for: nodeID)
            }()
            Task {
                await TeachingCourseEditingAnchorStore.shared.setActiveRow(
                    filePath: fileURL.path,
                    rowIndex: storedActiveRow
                )
            }
            guard let student = resolveStudentForNotebook() else {
                pendingCourseInsertAnchor = nil
                statusMessage = "无法识别当前学生，无法加载完成清单。"
                showLessonChecklistSheet = true
                return
            }
            lessonCompletionFiles = try TeachingCourseWorkflowService
                .lessonCompletionChecklistFiles(student: student)
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            if lessonCompletionFiles.isEmpty {
                statusMessage = "未找到完成清单，请先执行上课准备。"
                showLessonChecklistSheet = true
            } else if lessonCompletionFiles.count == 1, let onlyFile = lessonCompletionFiles.first {
                courseChecklistPickingTarget = TeachingLessonChecklistPickingTarget(id: onlyFile.path)
                statusMessage = "已自动进入唯一完成清单。"
            } else {
                showLessonChecklistSheet = true
            }
        } catch {
            pendingCourseInsertAnchor = nil
            statusMessage = "读取教案清单失败：\(error.localizedDescription)"
        }
    }

    /// toolbar按钮会在action之前让NSTextView失焦，因此必须在按下阶段冻结。
    /// 活动行只是历史位置；只有输入会话仍然有效时，它才是插入锚点。
    /// ESC或其他失焦已经结束输入会话，即使活动行回调尚未清空，也必须使用文末。
    private func freezeCourseInsertAnchorIfNeeded() {
        guard pendingCourseInsertAnchor == nil else { return }
        let activeNodeID = activeEditorRowIndex.flatMap { rowIndex in
            document.nodes.indices.contains(rowIndex) ? document.nodes[rowIndex].id : nil
        }
        pendingCourseInsertAnchor = TeachingCourseInsertAnchor.resolve(
            isEditing: isTextInputSessionActive,
            activeNodeID: activeNodeID
        )
    }

    private func applyCoursePickedRows(_ rows: [ChecklistTemplateRow], completionChecklistPath: String?) {
        guard !rows.isEmpty else {
            pendingCourseInsertAnchor = nil
            statusMessage = "未选择可插入的H3包。"
            return
        }
        guard let student = resolveStudentForNotebook() else {
            statusMessage = "无法识别当前学生，插入失败。"
            return
        }
        commitPendingDraftBeforeSyncIfNeeded()
        let insertionAnchor = pendingCourseInsertAnchor ?? .documentEnd
        let insertionActiveNodeID: UUID? = {
            guard case let .node(nodeID) = insertionAnchor else { return nil }
            return nodeID
        }()
        pendingCourseInsertAnchor = nil
        beginExclusiveNotebookOperation()
        statusMessage = "正在插入教案内容..."
        Task(priority: .userInitiated) {
            do {
                try await persistCurrentDocumentToDiskForSync()
                let summary = try await TeachingCourseWorkflowService.insertLessonPackagesIntoNotebook(
                    student: student,
                    pickedRows: rows,
                    completionChecklistFileURL: completionChecklistPath.flatMap { URL(fileURLWithPath: $0) },
                    insertionAnchorOverride: insertionAnchor,
                    usesStoredActiveRow: false
                )
                await MainActor.run {
                    let undoHint = summary.canUndo ? "（可撤销）" : ""
                    statusMessage = "插入完成：成功\(summary.insertedPackageCount) 跳过\(summary.skippedPackageCount)\(undoHint)"
                    refreshNotebookFromDiskAfterExternalWrite(
                        preserveActiveNodeID: insertionActiveNodeID,
                        failureMessagePrefix: "插入完成，但刷新失败"
                    )
                    endExclusiveNotebookOperation()
                }
            } catch {
                await MainActor.run {
                    endExclusiveNotebookOperation()
                    statusMessage = "插入失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func refreshNotebookFromDiskAfterExternalWrite(
        preserveActiveNodeID: UUID?,
        failureMessagePrefix: String,
        avoidsTextReplacementWhenLayoutIsUnchanged: Bool = false
    ) {
        do {
            let previousDocument = document
            let loaded = try NodeMarkdownFileManager.read(fileURL: fileURL)
            var parsedDocument = loaded.0
            _ = parsedDocument.ensureTrailingBlankLine(defaultLevel: 1)
            if avoidsTextReplacementWhenLayoutIsUnchanged,
               documentsHaveSameEditorLayout(previousDocument, parsedDocument) {
                applyMetadataOnlyNotebookReload(
                    parsedDocument: parsedDocument,
                    parsedMeta: loaded.1,
                    previousDocument: previousDocument,
                    preserveActiveNodeID: preserveActiveNodeID
                )
                return
            }
            document = parsedDocument
            synchronizeDocumentIndex(
                previousDocument: previousDocument,
                currentDocument: parsedDocument,
                activeRowIndex: nil,
                force: true
            )
            fileMeta = loaded.1
            rowsSnapshot = NodeMarkdownHTMLBuilder.buildRows(
                document: parsedDocument,
                style: settingsCenter.documentStyle
            )
            documentRevision = 0
            persistedDocumentRevision = 0
            saveState = .clean
            activeEditorRowIndex = preserveActiveNodeID.flatMap { documentIndex.row(for: $0) }
            if activeEditorRowIndex == nil {
                textKit2FocusLocation = nil
            }
            // 先按UUID恢复活动Node，再发布整篇外部文本。两套TextKit管线由此在
            // 同一次刷新中拿到正确行身份，不会先用旧行号滚动、再二次纠正。
            refreshTextKitDraftFromDocument(forceExternalSync: true)
            rebuildSearchResults()
            _ = packageChangeTracker.reconcileAfterExternalReload(
                previousDocument: previousDocument,
                currentDocument: document
            )
            if isClassSessionEditor {
                packageChangeTracker.beginTrackingRow(
                    rowIndex: activeEditorRowIndex,
                    document: document,
                    structuralIndex: documentIndex
                )
            }
            refreshLocalPackageListsAndLight()
        } catch {
            statusMessage = "\(failureMessagePrefix)：\(error.localizedDescription)"
            reloadFromDisk()
        }
    }

    /// 保存与更新不能因为Cache或Source字段变化而替换整篇NSTextStorage。
    /// UUID、层级和正文均相同时，屏幕上的文字布局就是同一份文档。
    private func documentsHaveSameEditorLayout(
        _ lhs: NodeMarkdownDocument,
        _ rhs: NodeMarkdownDocument
    ) -> Bool {
        lhs.nodes.count == rhs.nodes.count && zip(lhs.nodes, rhs.nodes).allSatisfy { current, other in
            current.id == other.id
                && current.level == other.level
                && current.text == other.text
        }
    }

    private func applyMetadataOnlyNotebookReload(
        parsedDocument: NodeMarkdownDocument,
        parsedMeta: NodeMarkdownFileMeta,
        previousDocument: NodeMarkdownDocument,
        preserveActiveNodeID: UUID?
    ) {
        document = parsedDocument
        // 正文和结构没有变化，索引与textKitDraft保持原样；只发布不可见的同步元数据。
        textKitDraftRowMetadata = makeTextKitRowMetadata(for: parsedDocument)
        fileMeta = parsedMeta
        documentRevision = 0
        persistedDocumentRevision = 0
        saveState = .clean
        activeEditorRowIndex = preserveActiveNodeID.flatMap { documentIndex.row(for: $0) }
        if activeEditorRowIndex == nil {
            textKit2FocusLocation = nil
        }
        _ = packageChangeTracker.reconcileAfterExternalReload(
            previousDocument: previousDocument,
            currentDocument: parsedDocument
        )
        if isClassSessionEditor {
            packageChangeTracker.beginTrackingRow(
                rowIndex: activeEditorRowIndex,
                document: parsedDocument,
                structuralIndex: documentIndex
            )
        }
        refreshLocalPackageListsAndLight()
        rebuildSearchResults()
    }

    private func resolveStudentForNotebook() -> TeachingStudentItem? {
        guard fileURL.lastPathComponent.hasPrefix("随堂笔记_") else { return nil }
        guard let students = try? TeachingStudentSettingsStore.loadStudents() else { return nil }
        let folderName = fileURL.deletingLastPathComponent().lastPathComponent
        return students.first(where: { $0.name == folderName })
    }

    private func refreshPendingClassUpdateCount() {
        guard isClassSessionEditor else {
            pendingClassUpdateCount = 0
            dirtyPackageItems = []
            newPackageItems = []
            return
        }
        let student = (isClassSessionEditor ? resolveStudentForNotebook() : nil)
        packageChangeTracker.schedulePendingRefresh(student: student) { count in
            pendingClassUpdateCount = max(count, packageChangeTracker.localPendingCount())
        }
    }

    private func refreshLocalPackageListsAndLight() {
        dirtyPackageItems = packageChangeTracker.dirtyPackageDisplayItems(document: document)
        newPackageItems = packageChangeTracker.newPackageDisplayItems(document: document)
        let availableIDs = Set(newPackageItems.map(\.id))
        if selectedNewPackageIDs.isEmpty, !availableIDs.isEmpty {
            selectedNewPackageIDs = availableIDs
        } else {
            selectedNewPackageIDs = selectedNewPackageIDs.intersection(availableIDs)
        }
        pendingClassUpdateCount = packageChangeTracker.localPendingCount()
    }

    private var selectedUpdateChapterTarget: TeachingCourseUpdateChapterTarget? {
        classUpdatePreview.chapterTargets.first(where: { $0.relativePath == selectedUpdateChapterPath })
    }

    private var newPackagePlacementControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("新包落位")
                .font(.subheadline.weight(.semibold))
            Picker("目标章", selection: $selectedUpdateChapterPath) {
                ForEach(classUpdatePreview.chapterTargets) { target in
                    Text(target.displayName).tag(target.relativePath)
                }
            }
            .pickerStyle(.menu)

            Picker("插入位置", selection: $selectedUpdateAnchorID) {
                Text("章末").tag("")
                ForEach(selectedUpdateChapterTarget?.anchors ?? []) { anchor in
                    Text("跟在：\(anchor.displayName)").tag(anchor.sourceID)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func requestClassUpdatePreview() {
        commitPendingDraftBeforeSyncIfNeeded()
        guard let student = resolveStudentForNotebook() else {
            statusMessage = "无法识别当前学生，更新失败。"
            return
        }
        statusMessage = "正在分析更新包..."
        Task(priority: .userInitiated) {
            do {
                try await persistCurrentDocumentToDiskForSync()
                let preview = try await packageChangeTracker.loadPreview(student: student)
                await MainActor.run {
                    classUpdatePreview = preview
                    refreshLocalPackageListsAndLight()
                    let localDirtyCount = dirtyPackageItems.count
                    let localNewCount = newPackageItems.count
                    let previewDirtyCount = preview.dirtyPackageCount
                    let previewNewCount = preview.newPackageCount
                    let displayDirtyCount = max(previewDirtyCount, localDirtyCount)
                    let displayNewCount = max(previewNewCount, localNewCount)
                    pendingClassUpdateCount = max(
                        pendingClassUpdateCount,
                        preview.totalPendingCount
                    )
                    if !newPackageItems.isEmpty {
                        selectedNewPackageIDs = Set(newPackageItems.map(\.id))
                    }
                    if let first = preview.chapterTargets.first {
                        selectedUpdateChapterPath = first.relativePath
                        selectedUpdateAnchorID = ""
                    } else {
                        selectedUpdateChapterPath = ""
                        selectedUpdateAnchorID = ""
                    }
                    TeachingDebugLogStore.append(
                        "open update sheet counts | local(dirty:\(localDirtyCount),new:\(localNewCount)) preview(dirty:\(previewDirtyCount),new:\(previewNewCount),source:\(preview.sourceUpdatePackageCount),conflict:\(preview.conflictPackageCount)) display(dirty:\(displayDirtyCount),new:\(displayNewCount)) pending:\(pendingClassUpdateCount)",
                        category: "TeachingCourse.UpdatePreview"
                    )
                    showClassUpdateSheet = true
                    statusMessage = "更新预览就绪。"
                }
            } catch {
                await MainActor.run {
                    statusMessage = "更新预览失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func runClassUpdate() {
        commitPendingDraftBeforeSyncIfNeeded()
        guard let student = resolveStudentForNotebook() else {
            statusMessage = "无法识别当前学生，更新失败。"
            return
        }
        let placementTarget: TeachingCourseUpdatePlacementTarget? = {
            guard !selectedNewPackageIDs.isEmpty,
                  !selectedUpdateChapterPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let anchor = selectedUpdateAnchorID.trimmingCharacters(in: .whitespacesAndNewlines)
            return TeachingCourseUpdatePlacementTarget(
                sourceFile: selectedUpdateChapterPath,
                anchorSourceID: anchor.isEmpty ? nil : anchor
            )
        }()
        let preservedActiveNodeID = activeEditorRowIndex.flatMap { rowIndex in
            document.nodes.indices.contains(rowIndex) ? document.nodes[rowIndex].id : nil
        }
        beginExclusiveNotebookOperation()
        statusMessage = "正在回传更新..."
        Task(priority: .userInitiated) {
            do {
                // 更新只清洗实际回传的H3包。整篇空行整理属于下课/关闭，
                // 在这里执行会改变焦点上方布局并造成不必要的视野跳动。
                try await persistCurrentDocumentToDiskForSync(cleanForFinalization: false)
                let summary = try await TeachingCoursePackageSyncExecutor.syncDirtyPackages(
                    student: student,
                    placementTarget: placementTarget,
                    allowedNewPackageIDs: selectedNewPackageIDs
                )
                await MainActor.run {
                    pendingClassUpdateCount = packageChangeTracker.resetPendingCount()
                    packageChangeTracker.acceptSuccessfulSyncResults(
                        summary.packageResults,
                        document: document
                    )
                    let failed = summary.packageResults.filter { !$0.success }
                    refreshNotebookFromDiskAfterExternalWrite(
                        preserveActiveNodeID: preservedActiveNodeID,
                        failureMessagePrefix: "更新完成，但刷新失败",
                        avoidsTextReplacementWhenLayoutIsUnchanged: true
                    )
                    endExclusiveNotebookOperation()
                    if failed.isEmpty {
                        statusMessage = "更新完成：回传\(summary.updatedSourcePackageCount) 新收集\(summary.collectedNewPackageCount) 冲突\(summary.conflictPackageCount)"
                    } else {
                        syncFailureMessages = failed.map { item in
                            let title = item.packageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            let displayTitle = title.isEmpty ? "(空标题H3)" : title
                            return "\(displayTitle)：\(item.reason)"
                        }
                        showSyncFailureSheet = true
                        statusMessage = "更新部分失败：成功\(summary.packageResults.count - failed.count)，失败\(failed.count)"
                    }
                }
            } catch {
                await MainActor.run {
                    endExclusiveNotebookOperation()
                    statusMessage = "更新失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func openReflectionInNode() {
        do {
            let studentFolder = fileURL.deletingLastPathComponent()
            reflectionFiles = try FileManager.default.contentsOfDirectory(
                at: studentFolder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            .filter {
                $0.pathExtension.lowercased() == "csv"
                    && $0.lastPathComponent.hasPrefix("上课信息_")
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            reflectionIndex = max(0, reflectionFiles.count - 1)
            reflectionShowStudentInfo = false
            showReflectionSheet = true
        } catch {
            statusMessage = "读取上课信息失败：\(error.localizedDescription)"
        }
    }

    private var studentInfoReflectionURL: URL? {
        let studentFolder = fileURL.deletingLastPathComponent()
        let studentName = studentFolder.lastPathComponent
        let direct = studentFolder.appendingPathComponent("学生信息_\(studentName).CSV", isDirectory: false)
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        return try? FileManager.default.contentsOfDirectory(
            at: studentFolder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .first(where: {
            $0.pathExtension.lowercased() == "csv"
                && $0.lastPathComponent.hasPrefix("学生信息_")
        })
    }

    private var currentReflectionFileURL: URL? {
        if reflectionShowStudentInfo {
            return studentInfoReflectionURL
        }
        guard reflectionFiles.indices.contains(reflectionIndex) else { return studentInfoReflectionURL }
        return reflectionFiles[reflectionIndex]
    }

    private func stepReflection(delta: Int) {
        guard !reflectionFiles.isEmpty else { return }
        let count = reflectionFiles.count
        reflectionIndex = (reflectionIndex + delta + count) % count
    }

    private var searchButton: some View {
        Button {
            showSearchPopover.toggle()
        } label: {
            Image(systemName: "magnifyingglass")
        }
        .appGlassButtonStyle()
        .help("搜索")
        .keyboardShortcut("f", modifiers: .command)
        .popover(isPresented: $showSearchPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("搜索")
                    .font(.headline)
                TextField("输入关键词", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        performSearch()
                    }
                Text("共 \(searchResults.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        findPrevious()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .appGlassButtonStyle()
                    .disabled(searchResults.isEmpty)
                    Button {
                        findNext()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .appGlassButtonStyle()
                    .disabled(searchResults.isEmpty)
                    Spacer()
                    Button {
                        performSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    .appGlassButtonStyle(.prominent)
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(12)
            .frame(width: 240)
        }
    }

    private var colorSchemeButton: some View {
        Button {
            toggleColorScheme()
        } label: {
            Image(systemName: effectiveIsDarkMode ? "moon.stars.fill" : "sun.max.fill")
        }
        .appGlassButtonStyle()
        .disabled(settingsCenter.documentStyle.preferredScheme != .system)
        .help("深浅切换")
    }

    private var styleButton: some View {
        Button {
            showSettingsSheet = true
        } label: {
            Image(systemName: "textformat")
        }
        .appGlassButtonStyle()
        .help("文档样式")
    }

    private var tocButton: some View {
        Button {
            showTOCPopover = true
        } label: {
            Image(systemName: "list.bullet.indent")
        }
        .appGlassButtonStyle()
        .help("TOC")
        .popover(isPresented: $showTOCPopover, arrowEdge: .bottom) {
            NodeMarkdownTOCPanelView(
                headings: headings,
                expandMode: $tocExpandMode,
                allowsReordering: activeClassSession?.kind == .teaching,
                onMove: moveNodePackageFromTOC
            ) { selected in
                activeSearchRowIndex = selected.rowIndex
                showTOCPopover = false
            }
            .frame(width: 300, height: 360)
            .padding(12)
        }
    }

    private var exportMenu: some View {
        Menu {
            Button("导出为PDF") { beginExport(format: .pdf) }
            Button("导出PDF分H1") { beginExport(format: .h1PDF) }
            Button("导出PDF分文件") { beginExport(format: .splitPDF) }
            Button("导出为黑白PDF") { beginExport(format: .monochromePDF) }
            Button("导出黑白PDF分H1") { beginExport(format: .monochromeH1PDF) }
            Button("导出PDF黑白分文件") { beginExport(format: .monochromeSplitPDF) }
            Button("导出为HTML") { beginExport(format: .html) }
            Button("导出为MD") { beginExport(format: .markdown) }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .appGlassControlChrome(.prominent)
        .help("导出")
    }

    private var saveButton: some View {
        Button {
            saveToDisk()
        } label: {
            Image(systemName: saveIconName)
                .foregroundStyle(saveIconColor)
                .overlay(alignment: .topTrailing) {
                    if hasPendingCutPackage {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -4)
                            .accessibilityLabel("剪切包待处理")
                    }
                }
        }
        .appGlassButtonStyle(saveButtonTier)
        .help(hasPendingCutPackage ? "保存（存在未粘贴剪切包）" : "保存")
        .keyboardShortcut("s", modifiers: .command)
    }

    private var hasPendingCutPackage: Bool {
        !pendingCutPackageNodes.isEmpty
    }

    private var cleanupButton: some View {
        Button {
            cleanEmptyNodes()
        } label: {
            Image(systemName: "trash.slash")
        }
        .appGlassButtonStyle()
        .help("清理空节点")
    }

    private var drawingBoardButton: some View {
        Button {
            #if os(macOS)
            showDrawingBoardSheet = true
            #else
            statusMessage = "iOS 暂不支持画图板"
            #endif
        } label: {
            Image(systemName: "pencil.and.scribble")
        }
        .appGlassButtonStyle()
        .help("画图")
    }

    private var effectiveIsDarkMode: Bool {
        switch preferredColorScheme {
        case .dark:
            return true
        case .light:
            return false
        case .none:
            return systemColorScheme == .dark
        case .some:
            return false
        }
    }

    private func toggleColorScheme() {
        guard settingsCenter.documentStyle.preferredScheme == .system else { return }
        if preferredSchemeOverride == nil {
            preferredSchemeOverride = systemColorScheme == .dark ? .light : .dark
            return
        }
        preferredSchemeOverride = preferredSchemeOverride == .dark ? .light : .dark
    }

    private func findNext() {
        guard !searchResults.isEmpty else { return }
        let nextIndex: Int
        if let activeSearchResultIndex {
            nextIndex = (activeSearchResultIndex + 1) % searchResults.count
        } else {
            nextIndex = 0
        }
        selectSearchResult(at: nextIndex)
    }

    private func findPrevious() {
        guard !searchResults.isEmpty else { return }
        let previousIndex: Int
        if let activeSearchResultIndex {
            previousIndex = (activeSearchResultIndex - 1 + searchResults.count) % searchResults.count
        } else {
            previousIndex = max(0, searchResults.count - 1)
        }
        selectSearchResult(at: previousIndex)
    }

    private func selectSearchResult(at index: Int) {
        guard searchResults.indices.contains(index) else { return }
        activeSearchResultIndex = index
        activeSearchRowIndex = searchResults[index].rowIndex
    }

    private func performSearch() {
        committedSearchText = searchText
        rebuildSearchResults()
    }

    private func rebuildSearchResults() {
        let query = searchQuery
        guard !query.isEmpty else {
            searchResults = []
            activeSearchResultIndex = nil
            activeSearchRowIndex = nil
            return
        }

        let previousMatch: (rowIndex: Int, location: Int)? = {
            guard let activeSearchResultIndex, searchResults.indices.contains(activeSearchResultIndex) else { return nil }
            let previous = searchResults[activeSearchResultIndex]
            return (previous.rowIndex, previous.matchLocationInRow)
        }()

        searchResults = nodeMarkdownBuildSearchResults(in: document.nodes, query: query)
        guard !searchResults.isEmpty else {
            activeSearchResultIndex = nil
            activeSearchRowIndex = nil
            return
        }

        if let previousMatch,
           let matchedIndex = searchResults.firstIndex(where: {
               $0.rowIndex == previousMatch.rowIndex && $0.matchLocationInRow == previousMatch.location
           }) {
            activeSearchResultIndex = matchedIndex
            activeSearchRowIndex = previousMatch.rowIndex
        } else if let previousMatch,
                  let matchedIndex = searchResults.firstIndex(where: { $0.rowIndex == previousMatch.rowIndex }) {
            activeSearchResultIndex = matchedIndex
            activeSearchRowIndex = previousMatch.rowIndex
        } else {
            activeSearchResultIndex = 0
            activeSearchRowIndex = searchResults[0].rowIndex
        }
    }

    private func clearSearchState() {
        searchText = ""
        committedSearchText = ""
        searchResults = []
        activeSearchResultIndex = nil
        activeSearchRowIndex = nil
    }

    @ViewBuilder
    private var bottomEditorPanel: some View {
        if let activeEditorRowIndex, document.nodes.indices.contains(activeEditorRowIndex) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("行内编辑（3行）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("L\(document.nodes[activeEditorRowIndex].level)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                NodeMarkdownThreeLineEditor(text: $bottomEditorText)
                    .frame(height: 78)
                    .padding(6)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if containsFormula(bottomEditorText) {
                    NodeMarkdownFormulaPreviewView(source: bottomEditorText)
                        .frame(height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var textKit2FocusLocationOverlay: some View {
        if let textKit2FocusLocation {
            HStack(spacing: 18) {
                Text("行 \(textKit2FocusLocation.rowIndex.map { String($0 + 1) } ?? "-")")
                if let column = textKit2FocusLocation.column {
                    Text("列 \(column + 1)")
                }
                Text("offset \(textKit2FocusLocation.location)")
                if textKit2FocusLocation.length > 0 {
                    Text("选中 \(textKit2FocusLocation.length)")
                }
            }
            .font(.system(size: 34, weight: .bold, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 5)
        }
    }

    private func cleanEmptyNodes() {
        let previousDocument = document
        let removed = document.removeEmptyNodes(keepProtectedH3: true)
        refreshTextKitDraftFromDocument(forceExternalSync: true)
        if removed > 0 {
            documentIndex.rebuild(from: document.nodes)
            if isClassSessionEditor {
                _ = packageChangeTracker.recordParseMutation(
                    previousDocument: previousDocument,
                    currentDocument: document,
                    activeRowIndex: activeEditorRowIndex
                )
                refreshLocalPackageListsAndLight()
            }
            markDocumentDirty()
            scheduleSnapshotRebuild()
            rebuildSearchResults()
            statusMessage = "已清理空节点：\(removed)"
        }
    }

    private func handleActiveEditorRowChange(_ rowIndex: Int?) {
        guard activeEditorRowIndex != rowIndex else { return }
        if isClassSessionEditor {
            _ = packageChangeTracker.finishTrackingPreviousRow(
                newRowIndex: rowIndex,
                document: document,
                structuralIndex: documentIndex
            )
            packageChangeTracker.beginTrackingRow(
                rowIndex: rowIndex,
                document: document,
                structuralIndex: documentIndex
            )
            refreshLocalPackageListsAndLight()
        }
        activeEditorRowIndex = rowIndex
        Task {
            await TeachingCourseEditingAnchorStore.shared.setActiveRow(filePath: fileURL.path, rowIndex: rowIndex)
        }
        guard let rowIndex, document.nodes.indices.contains(rowIndex) else { return }
        isUpdatingBottomEditorText = true
        bottomEditorText = document.nodes[rowIndex].text
        isUpdatingBottomEditorText = false
    }

    private func applyBottomEditorTextChange(_ newValue: String) {
        guard !isUpdatingBottomEditorText else { return }
        guard let rowIndex = activeEditorRowIndex, document.nodes.indices.contains(rowIndex) else { return }
        guard document.nodes[rowIndex].text != newValue else { return }
        let previousDocument = document
        document.updateText(at: rowIndex, to: newValue, structuralIndex: documentIndex)
        if isClassSessionEditor {
            _ = packageChangeTracker.recordDocumentMutation(
                previousDocument: previousDocument,
                currentDocument: document
            )
            refreshLocalPackageListsAndLight()
        }
        cleanupUnusedImageAssets(previousDocument: previousDocument, currentDocument: document)
        refreshTextKitDraftFromDocument(forceExternalSync: true)
        markDocumentDirty()
        scheduleSnapshotRebuild()
        rebuildSearchResults()
    }

    private func containsFormula(_ text: String) -> Bool {
        text.contains("$")
    }

    private func deleteNodePackageAtRow(_ rowIndex: Int) {
        commitPendingDraftBeforeSyncIfNeeded()
        guard document.nodes.indices.contains(rowIndex) else { return }
        guard let packageRange = packageRangeForNodePackage(at: rowIndex) else { return }
        let previousDocument = document
        let removedNodes = Array(document.nodes[packageRange])

        let removedRoot = document.nodes[packageRange.lowerBound]
        document.nodes.removeSubrange(packageRange)
        if document.nodes.isEmpty {
            document.nodes = [NodeMarkdownNode(level: 1, text: "")]
        }
        _ = document.ensureTrailingBlankLine(defaultLevel: min(12, max(1, document.nodes.last?.level ?? 1)))
        documentIndex.rebuild(from: document.nodes)
        clearEditorFocusAfterPackageDeletion()
        cleanupUnusedImageAssets(previousDocument: previousDocument, currentDocument: document)

        if isClassSessionEditor {
            _ = packageChangeTracker.recordRemovedNodePackage(
                removedNodes: removedNodes,
                previousDocument: previousDocument,
                currentDocument: document
            )
        } else if removedRoot.level == 3,
                  removedRoot.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = packageChangeTracker.recordNewPackageDeletion(h3NodeID: removedRoot.id.uuidString)
        }

        refreshTextKitDraftFromDocument(forceExternalSync: true)
        markDocumentDirty()
        scheduleSnapshotRebuild()
        rebuildSearchResults()
        refreshLocalPackageListsAndLight()
        statusMessage = "已删除节点包"
    }

    private func cutNodePackageAtRow(_ rowIndex: Int) {
        guard let packageRange = packageRangeForNodePackage(at: rowIndex) else { return }
        let previousDocument = document
        pendingCutPackageNodes = Array(document.nodes[packageRange])
        pendingCutPackageOriginalIndex = packageRange.lowerBound
        document.nodes.removeSubrange(packageRange)
        if document.nodes.isEmpty {
            document.nodes = [NodeMarkdownNode(level: 1, text: "")]
        }
        _ = document.ensureTrailingBlankLine(defaultLevel: min(12, max(1, document.nodes.last?.level ?? 1)))
        documentIndex.rebuild(from: document.nodes)
        refreshTextKitDraftFromDocument(forceExternalSync: true)
        if isClassSessionEditor {
            _ = packageChangeTracker.recordRemovedNodePackage(
                removedNodes: pendingCutPackageNodes,
                previousDocument: previousDocument,
                currentDocument: document
            )
        }
        markDocumentDirty()
        scheduleSnapshotRebuild()
        rebuildSearchResults()
        refreshLocalPackageListsAndLight()
        statusMessage = "已剪切节点包"
    }

    private func pasteNodePackageAfterRow(_ rowIndex: Int) {
        guard !pendingCutPackageNodes.isEmpty else {
            statusMessage = "没有可粘贴的节点包"
            return
        }
        guard document.nodes.indices.contains(rowIndex) else { return }
        guard let packageRange = packageRangeForNodePackage(at: rowIndex) else { return }
        if let collision = NodeMarkdownIdentityPolicy.firstCollision(
            inserting: pendingCutPackageNodes,
            into: document
        ) {
            statusMessage = "粘贴已停止：目标文档已存在UUID \(collision.uuidString)"
            return
        }
        let previousDocument = document
        let insertIndex = packageRange.upperBound
        document.nodes.insert(contentsOf: pendingCutPackageNodes, at: insertIndex)
        pendingCutPackageNodes = []
        pendingCutPackageOriginalIndex = nil
        _ = document.ensureTrailingBlankLine(defaultLevel: min(12, max(1, document.nodes.last?.level ?? 1)))
        documentIndex.rebuild(from: document.nodes)
        refreshTextKitDraftFromDocument(forceExternalSync: true)
        if isClassSessionEditor {
            _ = packageChangeTracker.recordParseMutation(
                previousDocument: previousDocument,
                currentDocument: document,
                activeRowIndex: activeEditorRowIndex
            )
        }
        markDocumentDirty()
        scheduleSnapshotRebuild()
        rebuildSearchResults()
        refreshLocalPackageListsAndLight()
        statusMessage = "已粘贴节点包"
    }

    /// 目录拖动与剪切粘贴使用完全相同的“节点包”边界。源包从原位置移除后，
    /// 插入目标包之后；整个事务只发布一次文档快照和一次全局显示刷新。
    private func moveNodePackageFromTOC(sourceID: UUID, after targetID: UUID) -> Bool {
        guard sourceID != targetID else { return false }
        commitPendingDraftBeforeSyncIfNeeded()
        guard let sourceRow = documentIndex.row(for: sourceID),
              let targetRow = documentIndex.row(for: targetID),
              document.nodes.indices.contains(sourceRow),
              document.nodes.indices.contains(targetRow),
              document.nodes[sourceRow].level <= 3,
              document.nodes[targetRow].level <= 3,
              let sourceRange = packageRangeForNodePackage(at: sourceRow),
              !sourceRange.contains(targetRow) else {
            statusMessage = "不能把节点包移动到自身内部。"
            return false
        }

        let previousDocument = document
        let movingNodes = Array(document.nodes[sourceRange])
        document.nodes.removeSubrange(sourceRange)

        let reducedIndex = NodeMarkdownDocumentIndex(nodes: document.nodes)
        guard let reducedTargetRow = reducedIndex.row(for: targetID),
              let reducedTargetRange = reducedIndex.subtreeRange(startingAt: reducedTargetRow) else {
            document = previousDocument
            documentIndex.rebuild(from: document.nodes)
            statusMessage = "移动失败：找不到目标节点。"
            return false
        }
        document.nodes.insert(contentsOf: movingNodes, at: reducedTargetRange.upperBound)
        guard document != previousDocument else { return false }

        documentIndex.rebuild(from: document.nodes)
        if isClassSessionEditor {
            _ = packageChangeTracker.recordParseMutation(
                previousDocument: previousDocument,
                currentDocument: document,
                activeRowIndex: nil
            )
        }
        activeEditorRowIndex = nil
        textKit2FocusLocation = nil
        refreshTextKitDraftFromDocument(forceExternalSync: true)
        pendingRebuildTask?.cancel()
        pendingRebuildTask = nil
        rowsSnapshot = NodeMarkdownHTMLBuilder.buildRows(
            document: document,
            style: settingsCenter.documentStyle
        )
        markDocumentDirty()
        rebuildSearchResults()
        refreshLocalPackageListsAndLight()
        statusMessage = "已移动节点包"
        return true
    }

    private func packageRangeForNodePackage(at rowIndex: Int) -> Range<Int>? {
        guard document.nodes.indices.contains(rowIndex),
              documentIndex.nodeCount == document.nodes.count else { return nil }
        return documentIndex.subtreeRange(startingAt: rowIndex)
    }

    private func isProtectedH3PackageRoot(at rowIndex: Int) -> Bool {
        guard document.nodes.indices.contains(rowIndex) else { return false }
        let node = document.nodes[rowIndex]
        return node.level == 3
            && !node.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !node.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func deleteProtectedH3PackageAtRow(_ rowIndex: Int) {
        commitPendingDraftBeforeSyncIfNeeded()
        guard document.nodes.indices.contains(rowIndex) else { return }
        let node = document.nodes[rowIndex]
        guard node.level == 3 else {
            statusMessage = "母本删除仅支持H3节点"
            return
        }
        let sourceFile = node.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        if sourceFile.isEmpty {
            let previousDocument = document
            let localRemoved = document.removeH3Package(startingAt: rowIndex)
            guard localRemoved > 0 else {
                statusMessage = "删除失败"
                return
            }
            documentIndex.rebuild(from: document.nodes)
            clearEditorFocusAfterPackageDeletion()
            cleanupUnusedImageAssets(previousDocument: previousDocument, currentDocument: document)
            _ = packageChangeTracker.recordNewPackageDeletion(h3NodeID: node.id.uuidString)
            refreshTextKitDraftFromDocument(forceExternalSync: true)
            markDocumentDirty()
            scheduleSnapshotRebuild()
            rebuildSearchResults()
            refreshLocalPackageListsAndLight()
            statusMessage = pendingClassUpdateCount == 0 ? "" : "已删除新包"
            return
        }
        statusMessage = "该H3包已绑定母本，不允许直接删除"
        let sourceID = node.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceID.isEmpty else { return }

        #if os(macOS)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "母本删除"
        alert.informativeText = "将删除母本对应H3包，并删除当前文档中的该H3包。"
        alert.addButton(withTitle: "确认删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        #endif

        guard let sourceURL = resolveSourceFileURL(node.sourceFile) else {
            statusMessage = "母本删除失败：源文件路径无效"
            return
        }
        let sourceBackup = (try? Data(contentsOf: sourceURL))
        let sourceDeleted = deleteH3PackageInSourceFile(sourceID: sourceID, sourceURL: sourceURL)
        if !sourceDeleted {
            statusMessage = "母本删除失败：未找到对应源文件或节点"
            return
        }

        let previousDocument = document
        let localRemoved = document.removeH3Package(startingAt: rowIndex)
        guard localRemoved > 0 else {
            if let sourceBackup {
                try? sourceBackup.write(to: sourceURL, options: .atomic)
            }
            statusMessage = "本地删除失败，母本已回滚"
            return
        }
        documentIndex.rebuild(from: document.nodes)
        clearEditorFocusAfterPackageDeletion()
        cleanupUnusedImageAssets(previousDocument: previousDocument, currentDocument: document)
        refreshTextKitDraftFromDocument(forceExternalSync: true)
        markDocumentDirty()
        scheduleSnapshotRebuild()
        rebuildSearchResults()
        refreshLocalPackageListsAndLight()
        statusMessage = "已删除母本与当前文档H3包"
    }

    private func clearEditorFocusAfterPackageDeletion() {
        activeEditorRowIndex = nil
        textKit2FocusLocation = nil
        #if os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }

    private func deleteH3PackageInSourceFile(sourceID: String, sourceURL: URL) -> Bool {
        guard let loaded = try? NodeMarkdownFileManager.read(fileURL: sourceURL) else { return false }
        var sourceDocument = loaded.0
        let sourceMeta = loaded.1

        let targetIndex = sourceDocument.nodes.firstIndex {
            $0.level == 3 && $0.id.uuidString.caseInsensitiveCompare(sourceID) == .orderedSame
        }
        guard let targetIndex else { return false }
        guard sourceDocument.removeH3Package(startingAt: targetIndex) > 0 else { return false }

        do {
            try NodeMarkdownFileManager.write(document: sourceDocument, meta: sourceMeta, to: sourceURL)
            return true
        } catch {
            return false
        }
    }

    private func resolveSourceFileURL(_ rawSourceFile: String) -> URL? {
        let trimmed = rawSourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let asPath = NSString(string: trimmed)
        if asPath.isAbsolutePath {
            return URL(fileURLWithPath: trimmed)
        }
        if trimmed.hasPrefix("档案/") {
            let suffix = String(trimmed.dropFirst("档案/".count))
            if !suffix.isEmpty,
               let archiveRoot = try? ArchiveStorage.ensureArchiveRoot() {
                return archiveRoot.appendingPathComponent(suffix, isDirectory: false)
            }
        }
        if let workspace = try? ArchiveStorage.ensureWorkspace() {
            let lessonPlanURL = workspace
                .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
                .appendingPathComponent(ArchiveStorage.teachingPlanFolderName, isDirectory: true)
                .appendingPathComponent(trimmed, isDirectory: false)
            if FileManager.default.fileExists(atPath: lessonPlanURL.path) {
                return lessonPlanURL
            }
        }
        return fileURL.deletingLastPathComponent().appendingPathComponent(trimmed, isDirectory: false)
    }

    private func imageInsertScope(for h3Node: NodeMarkdownNode) -> NodeMarkdownImageScope {
        let sourceFile = h3Node.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sourceFile.isEmpty {
            return NodeMarkdownImageResourceManager.formalScope(
                sourceFile: sourceFile,
                notebookFileURL: fileURL
            )
        }
        if let lessonChapterScope = NodeMarkdownImageResourceManager.formalScopeForCurrentLessonChapter(fileURL: fileURL) {
            return lessonChapterScope
        }
        let packageID = h3Node.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? h3Node.id.uuidString
            : h3Node.sourceID
        return NodeMarkdownImageResourceManager.temporaryScope(
            packageID: packageID,
            notebookFileURL: fileURL
        )
    }

    private func isTemporaryImageScope(_ scope: NodeMarkdownImageScope) -> Bool {
        if case .h3Temporary = scope { return true }
        return false
    }

    /// 图片文件由父页面按H3作用域落盘，但正文插入必须回到发起请求的TextKit管线执行。
    /// 这样图片粘贴仍是一次本行编辑，不需要父页面强制替换整篇文档。
    private func prepareImageTextAtRow(_ rowIndex: Int) -> String? {
        // 图片写入必须建立在编辑器刚刚提交的完整Node草稿上。
        // 这保证Tab/Shift+Tab更新过的level、UUID及来源字段不会被父文档旧值覆盖。
        commitPendingDraftBeforeSyncIfNeeded()
        guard document.nodes.indices.contains(rowIndex) else { return nil }
        guard let h3Index = documentIndex.owningH3Row(for: rowIndex), document.nodes.indices.contains(h3Index) else {
            statusMessage = "未定位到所属H3包"
            return nil
        }
        let h3Node = document.nodes[h3Index]
        guard h3Node.level == 3 else {
            statusMessage = "未定位到所属H3包"
            return nil
        }
        #if os(macOS)
        let selectedURL: URL
        if let pastedImageURL = NodeMarkdownImageAssetService.pastedImageURL() {
            selectedURL = pastedImageURL
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.image]
            guard panel.runModal() == .OK, let panelURL = panel.url else { return nil }
            selectedURL = panelURL
        }
        let shouldRemovePastedTemporaryImage = NodeMarkdownImageAssetService.isTemporaryPastedImageURL(selectedURL)
        defer {
            if shouldRemovePastedTemporaryImage {
                try? FileManager.default.removeItem(at: selectedURL)
            }
        }

        let imageScope = imageInsertScope(for: h3Node)
        guard let imageInsert = NodeMarkdownImageAssetService.insertImage(
            selectedURL: selectedURL,
            scope: imageScope
        ) else {
            statusMessage = "插入图片失败"
            return nil
        }

        let updatedText = appendingImageSnippet(
            imageInsert.htmlSnippet,
            to: document.nodes[rowIndex].text
        )
        statusMessage = isTemporaryImageScope(imageScope) ? "已插入图片到暂存区" : "已插入图片"
        return updatedText
        #else
        return nil
        #endif
    }

    private func openDrawingBoardAtRow(_ rowIndex: Int) {
        #if os(macOS)
        guard document.nodes.indices.contains(rowIndex) else { return }
        guard !isRowInNewPackage(rowIndex) else {
            statusMessage = "新包不允许画图"
            return
        }
        drawingBoardTargetRowIndex = rowIndex
        showDrawingBoardSheet = true
        #else
        statusMessage = "iOS 暂不支持画图板"
        #endif
    }

    private func insertDrawingAsset(drawingURL: URL) {
        #if os(macOS)
        defer {
            drawingBoardTargetRowIndex = nil
            try? FileManager.default.removeItem(at: drawingURL)
        }
        guard let rowIndex = drawingBoardTargetRowIndex, document.nodes.indices.contains(rowIndex) else {
            statusMessage = "未定位到画图插入行"
            return
        }
        guard let h3Index = documentIndex.owningH3Row(for: rowIndex), document.nodes.indices.contains(h3Index) else {
            statusMessage = "未定位到所属H3包"
            return
        }
        let sourceFile = document.nodes[h3Index].sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceFile.isEmpty else {
            statusMessage = "该包未绑定母本，不能插入画图"
            return
        }
        guard let imageInsert = NodeMarkdownImageAssetService.insertTransparentPNGImage(
            selectedURL: drawingURL,
            sourceFile: sourceFile,
            notebookFileURL: fileURL
        ) else {
            statusMessage = "插入画图失败"
            return
        }
        let updatedText = appendingImageSnippet(
            imageInsert.htmlSnippet,
            to: document.nodes[rowIndex].text
        )
        document.updateText(
            at: rowIndex,
            to: updatedText,
            structuralIndex: documentIndex
        )
        refreshTextKitDraftFromDocument(forceExternalSync: true)
        markDocumentDirty()
        scheduleSnapshotRebuild()
        rebuildSearchResults()
        statusMessage = "已插入画图"
        #else
        statusMessage = "iOS 暂不支持画图板"
        #endif
    }

    /// “洗教案”留下的图片占位只在行首有结构含义。真正插入图片或画图时，
    /// 用真实Markdown链接替换这个占位，不能把花朵标签继续写进正文。
    private func appendingImageSnippet(_ snippet: String, to source: String) -> String {
        let placeholder = "🌼{图片}🌼"
        let leadingWhitespaceCount = source.prefix { $0.isWhitespace }.count
        let contentStart = source.index(source.startIndex, offsetBy: leadingWhitespaceCount)
        var base = source
        if source[contentStart...].hasPrefix(placeholder) {
            let markerEnd = source.index(contentStart, offsetBy: placeholder.count)
            base = String(source[markerEnd...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !base.isEmpty else { return snippet }
        return "\(base) \(snippet)"
    }

    private func cleanupUnusedImageAssets(previousDocument: NodeMarkdownDocument, currentDocument: NodeMarkdownDocument) {
        _ = NodeMarkdownImageResourceManager.restoreReferencedStashedImages(
            currentDocument: currentDocument,
            notebookFileURL: fileURL
        )
        _ = NodeMarkdownImageResourceManager.deleteRemovedManagedImages(
            previousDocument: previousDocument,
            currentDocument: currentDocument,
            notebookFileURL: fileURL
        )
    }

    private func restoreReferencedImageAssets() {
        _ = NodeMarkdownImageResourceManager.restoreReferencedStashedImages(
            currentDocument: document,
            notebookFileURL: fileURL
        )
    }

    private func restoreImageUndoStashForOpeningIfNeeded(document: NodeMarkdownDocument) {
        guard !didRestoreImageUndoStashForSession else { return }
        didRestoreImageUndoStashForSession = true
        _ = NodeMarkdownImageResourceManager.restoreReferencedStashedImages(
            currentDocument: document,
            notebookFileURL: fileURL
        )
    }

    private func finalizeImageUndoStashAfterSuccessfulClose() {
        NodeMarkdownImageResourceManager.finalizeUndoImageStash(
            currentDocument: document,
            notebookFileURL: fileURL
        )
    }

    private func isRowInNewPackage(_ rowIndex: Int) -> Bool {
        guard let h3Index = documentIndex.owningH3Row(for: rowIndex), document.nodes.indices.contains(h3Index) else {
            return false
        }
        let h3Node = document.nodes[h3Index]
        guard h3Node.level == 3 else { return false }
        return h3Node.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func canPersistCurrentDocument() -> Bool {
        guard pendingCutPackageNodes.isEmpty else {
            presentPendingCutGuard(message: "存在未粘贴的剪切包，不能保存。请先粘贴或回退剪切。")
            return false
        }
        do {
            try NodeMarkdownIdentityPolicy.validateForPersistence(document)
        } catch {
            presentPendingCutGuard(message: error.localizedDescription)
            return false
        }
        return true
    }

    private func presentPendingCutGuard(message: String) {
        pendingCutGuardMessage = message
        showPendingCutGuardAlert = true
        statusMessage = message
    }

    private func rollbackPendingCutPackageToOriginalLocation() {
        guard !pendingCutPackageNodes.isEmpty else { return }
        if let collision = NodeMarkdownIdentityPolicy.firstCollision(
            inserting: pendingCutPackageNodes,
            into: document
        ) {
            statusMessage = "剪切回退已停止：文档已存在UUID \(collision.uuidString)"
            return
        }
        let insertIndex = max(0, min(pendingCutPackageOriginalIndex ?? document.nodes.count, document.nodes.count))
        let previousDocument = document
        document.nodes.insert(contentsOf: pendingCutPackageNodes, at: insertIndex)
        pendingCutPackageNodes = []
        pendingCutPackageOriginalIndex = nil
        _ = document.ensureTrailingBlankLine(defaultLevel: min(12, max(1, document.nodes.last?.level ?? 1)))
        documentIndex.rebuild(from: document.nodes)
        refreshTextKitDraftFromDocument(forceExternalSync: true)
        if isClassSessionEditor {
            _ = packageChangeTracker.recordParseMutation(
                previousDocument: previousDocument,
                currentDocument: document,
                activeRowIndex: activeEditorRowIndex
            )
            refreshLocalPackageListsAndLight()
        }
        markDocumentDirty()
        scheduleSnapshotRebuild()
        rebuildSearchResults()
        statusMessage = "已回退剪切包"
    }

    @MainActor
    private func beginExport(format: NodeMarkdownExportFormat) {
        commitPendingDraftBeforeSyncIfNeeded()
        pendingExportFormat = format
        exportToFiles(format: format)
    }

    @MainActor
    private func exportToWeChat(format: NodeMarkdownExportFormat) {
        do {
            try TeachingDocumentExportService.exportToWeChat(
                sourceFileURL: fileURL,
                descriptor: format.exportDescriptor
            ) {
                try renderExportData(format: format)
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @MainActor
    private func exportToFiles(format: NodeMarkdownExportFormat) {
        do {
            if format.isSplitFileExport {
                let count = try TeachingDocumentExportService.saveFilesToDirectory(
                    sourceFileURL: fileURL
                ) {
                    try renderSplitPDFExportFiles(monochrome: format == .monochromeSplitPDF)
                }
                if count > 0 {
                    statusMessage = "已导出\(count)个PDF文件"
                }
                return
            }
            try TeachingDocumentExportService.saveToFile(
                sourceFileURL: fileURL,
                descriptor: format.exportDescriptor
            ) {
                try renderExportData(format: format)
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @MainActor
    private func renderExportData(format: NodeMarkdownExportFormat) throws -> Data {
        switch format {
        case .markdown:
            let meta = normalizedFileMetaForExport()
            return Data(NodeMarkdownFileManager.serialize(document: document, meta: meta).utf8)
        case .html:
            return try NodeMarkdownHTMLExporter.renderData(
                sourceFileURL: fileURL,
                document: document,
                style: settingsCenter.documentStyle
            )
        case .pdf, .h1PDF, .monochromePDF, .monochromeH1PDF:
            #if os(macOS)
            return try awaitPDFData(
                monochrome: format == .monochromePDF || format == .monochromeH1PDF,
                paginationMode: format == .h1PDF || format == .monochromeH1PDF
                    ? .h1StartsNewPage
                    : .natural
            )
            #else
            return Data()
            #endif
        case .splitPDF, .monochromeSplitPDF:
            throw NSError(
                domain: "NodeMarkdownExport",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "分文件PDF必须通过批量导出入口生成。"]
            )
        }
    }

    @MainActor
    private func renderSplitPDFExportFiles(monochrome: Bool) throws -> [TeachingDocumentExportFile] {
        #if os(macOS)
        let sections = NodeMarkdownH1FileSectionBuilder.build(
            document: document,
            sourceBaseName: fileURL.deletingPathExtension().lastPathComponent
        )
        let style = monochrome
            ? settingsCenter.documentStyle.monochromeExportStyle
            : settingsCenter.documentStyle
        return try sections.map { section in
            let data = try NodeMarkdownPDFExporter.renderData(
                sourceFileURL: fileURL,
                document: section.document,
                style: style,
                paginationMode: .natural
            )
            return TeachingDocumentExportFile(
                fileName: (monochrome ? "黑白打印专用-" : "") + section.fileBaseName + ".pdf",
                data: data
            )
        }
        #else
        throw CocoaError(.featureUnsupported)
        #endif
    }

    private func normalizedFileMetaForExport() -> NodeMarkdownFileMeta {
        var meta = fileMeta
        if meta.title.isEmpty {
            meta.title = fileURL.deletingPathExtension().lastPathComponent
        }
        if meta.type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            meta.type.lowercased() == "nodesmarkdown" {
            meta.type = "nodemarkdown"
        }
        return meta
    }

    #if os(macOS)
    @MainActor
    private func awaitPDFData(
        monochrome: Bool = false,
        paginationMode: NodeMarkdownPDFPaginationMode = .natural
    ) throws -> Data {
        try NodeMarkdownPDFExporter.renderData(
            sourceFileURL: fileURL,
            document: document,
            style: monochrome
                ? settingsCenter.documentStyle.monochromeExportStyle
                : settingsCenter.documentStyle,
            paginationMode: paginationMode
        )
    }
    #endif
}

// MARK: - NodeMarkdown设置页 - v1 - 提供背景主题12层图标与共享快捷输入配置入口
private struct NodeMarkdownSettingsSheet: View {
    @Binding var documentStyle: NodeMarkdownDocumentStyle
    @Binding var quickInputSettings: MarkdownQuickInputSettings
    @State private var showQuickInputSheet = false
    @State private var selectedStyleRole = NodeMarkdownStyleRole.h1
    @State private var activeColorRole: NodeMarkdownStyleRole?
    @State private var activeFontRole: NodeMarkdownStyleRole?
    @State private var fontOptions: [MarkdownFontOption] = [
        MarkdownFontOption(postScriptName: appleSystemMonospacedFontName, displayName: "Apple 系统等宽", isChinese: false),
        MarkdownFontOption(postScriptName: "PingFangSC-Regular", displayName: "苹方-简 常规", isChinese: true)
    ]
    @Environment(\.dismiss) private var dismiss

    private let paletteItems = markdownPresetPalette()
    private let editableStyleRoles = NodeMarkdownStyleRole.orderedByLevel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("编辑器主题")
                        .font(.headline)
                    Toggle("背景跟随深浅色", isOn: Binding(
                        get: { documentStyle.useSystemBackground },
                        set: { documentStyle.useSystemBackground = $0 }
                    ))
                    ColorPicker("背景色", selection: Binding(
                        get: { documentStyle.editorBackgroundColor },
                        set: {
                            documentStyle.editorBackgroundColor = $0
                            documentStyle.useSystemBackground = false
                        }
                    ))
                    .disabled(documentStyle.useSystemBackground)
                    Button {
                        documentStyle.useSystemBackground = true
                    } label: {
                        Label("清除背景色", systemImage: "eraser")
                    }
                    .appGlassButtonStyle()
                    .help("恢复为跟随深浅色背景")
                    Picker("深浅模式", selection: Binding(
                        get: { documentStyle.preferredScheme },
                        set: { documentStyle.preferredScheme = $0 }
                    )) {
                        Text("跟随系统").tag(NodeMarkdownPreferredScheme.system)
                        Text("固定浅色").tag(NodeMarkdownPreferredScheme.light)
                        Text("固定深色").tag(NodeMarkdownPreferredScheme.dark)
                    }
                    .pickerStyle(.segmented)

                    Divider()

                    Text("层级样式")
                        .font(.headline)

                    VStack(spacing: 6) {
                        ForEach(editableStyleRoles) { role in
                            Button {
                                selectedStyleRole = role
                            } label: {
                                HStack {
                                    Text(role.rawValue)
                                    Spacer()
                                    Text("\(Int(documentStyle.style(for: role).fontSize.rounded())) pt")
                                        .foregroundStyle(.secondary)
                                    Image(systemName: selectedStyleRole == role ? "chevron.down" : "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(selectedStyleRole == role ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        let editingRole = selectedStyleRole
                        let styleBinding = styleBinding(for: editingRole)

                        Button {
                            activeFontRole = editingRole
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedFontDisplayName(for: styleBinding.wrappedValue.fontName))
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .frame(maxWidth: 320, alignment: .leading)
                        }
                        .buttonStyle(.bordered)

                        HStack {
                            Text("字号")
                            Spacer()
                            Text("\(Int(styleBinding.wrappedValue.fontSize.rounded()))")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { styleBinding.wrappedValue.fontSize },
                                set: {
                                    var style = styleBinding.wrappedValue
                                    style.fontSize = max(1, min(100, $0))
                                    styleBinding.wrappedValue = style
                                }
                            ),
                            in: 1...100,
                            step: 1
                        )

                        HStack {
                            Text("段前间距")
                            Spacer()
                            Text("\(Int(styleBinding.wrappedValue.paragraphSpacingBefore.rounded()))")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { styleBinding.wrappedValue.paragraphSpacingBefore },
                                set: {
                                    var style = styleBinding.wrappedValue
                                    style.paragraphSpacingBefore = max(1, min(100, $0))
                                    styleBinding.wrappedValue = style
                                }
                            ),
                            in: 1...100,
                            step: 1
                        )

                        HStack {
                            Text("段后间距")
                            Spacer()
                            Text("\(Int(styleBinding.wrappedValue.paragraphSpacingAfter.rounded()))")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { styleBinding.wrappedValue.paragraphSpacingAfter },
                                set: {
                                    var style = styleBinding.wrappedValue
                                    style.paragraphSpacingAfter = max(1, min(100, $0))
                                    styleBinding.wrappedValue = style
                                }
                            ),
                            in: 1...100,
                            step: 1
                        )

                        HStack {
                            Text("同级行距")
                            Spacer()
                            Text("\(Int(styleBinding.wrappedValue.peerLineSpacing.rounded()))")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { styleBinding.wrappedValue.peerLineSpacing },
                                set: {
                                    var style = styleBinding.wrappedValue
                                    style.peerLineSpacing = max(1, min(100, $0))
                                    styleBinding.wrappedValue = style
                                }
                            ),
                            in: 1...100,
                            step: 1
                        )

                        HStack(spacing: 8) {
                            ForEach(paletteItems) { palette in
                                let isSelected = isPaletteSelected(palette, style: styleBinding.wrappedValue)
                                Button {
                                    var style = styleBinding.wrappedValue
                                    style.color = palette.color
                                    if palette.semanticColor == .adaptiveBlackWhite {
                                        style.semanticColor = .adaptiveBlackWhite
                                    } else {
                                        style.semanticColor = nil
                                    }
                                    styleBinding.wrappedValue = style
                                } label: {
                                    Circle()
                                        .fill(palette.color)
                                        .frame(width: 18, height: 18)
                                        .overlay(
                                            Circle().stroke(Color.white.opacity(0.6), lineWidth: 1)
                                        )
                                        .overlay(
                                            Group {
                                                if isSelected {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(palette.title)
                            }

                            Button {
                                activeColorRole = editingRole
                            } label: {
                                Image(systemName: "paintpalette")
                            }
                            .appGlassButtonStyle()
                            .help("自选颜色")
                        }

                        Toggle("加粗", isOn: Binding(
                            get: { styleBinding.wrappedValue.isBold },
                            set: {
                                var style = styleBinding.wrappedValue
                                style.isBold = $0
                                styleBinding.wrappedValue = style
                            }
                        ))

                        Toggle("下划线", isOn: Binding(
                            get: { styleBinding.wrappedValue.isUnderline },
                            set: {
                                var style = styleBinding.wrappedValue
                                style.isUnderline = $0
                                styleBinding.wrappedValue = style
                            }
                        ))

                        Toggle("背景条", isOn: Binding(
                            get: { styleBinding.wrappedValue.hasBackgroundBar },
                            set: {
                                var style = styleBinding.wrappedValue
                                style.hasBackgroundBar = $0
                                styleBinding.wrappedValue = style
                            }
                        ))
                    }
                    .id(selectedStyleRole)

                    Divider()

                    HStack {
                        Text("12层图标")
                            .font(.headline)
                        Spacer()
                        Button {
                            resetDefaultIcons()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .appGlassButtonStyle()
                        .help("重置图标")
                    }

                    ForEach(1...12, id: \.self) { level in
                        HStack(spacing: 12) {
                            Text(displayMarker(for: level))
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .frame(width: 22, alignment: .center)
                            Text("L\(level)")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .frame(width: 32, alignment: .leading)
                            TextField("行编号符号", text: Binding(
                                get: { symbol(for: level) },
                                set: { updateSymbol($0, for: level) }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    Divider()

                    HStack {
                        Text("共享快捷输入")
                            .font(.headline)
                        Spacer()
                        Button {
                            showQuickInputSheet = true
                        } label: {
                            Image(systemName: "bolt.circle")
                        }
                            .appGlassButtonStyle()
                        .help("编辑快捷输入")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Node 设置")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .appGlassButtonStyle(.prominent)
                    .help("完成")
                }
            }
        }
        .sheet(isPresented: $showQuickInputSheet) {
            MarkdownQuickInputSettingsView(
                settings: $quickInputSettings,
                onFinish: { showQuickInputSheet = false }
            )
            .nodeMarkdownAdaptiveSheetSize(width: 560, height: 520)
        }
        .sheet(isPresented: Binding(
            get: { activeColorRole != nil },
            set: { if !$0 { activeColorRole = nil } }
        )) {
            if let role = activeColorRole {
                let style = styleBinding(for: role)
                MarkdownRoleCustomColorSheet(
                    roleTitle: role.rawValue,
                    selectedColor: Binding(
                        get: { style.wrappedValue.renderedColor },
                        set: { value in
                            var current = style.wrappedValue
                            current.color = value
                            current.semanticColor = nil
                            style.wrappedValue = current
                        }
                    )
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { activeFontRole != nil },
            set: { if !$0 { activeFontRole = nil } }
        )) {
            if let role = activeFontRole {
                let style = styleBinding(for: role)
                MarkdownFontSelectorView(
                    title: "\(role.rawValue) 字体",
                    fontOptions: nodeFontOptionsForSelector(currentFontName: style.wrappedValue.fontName),
                    selectedFontName: Binding(
                        get: { style.wrappedValue.fontName },
                        set: { newFont in
                            var current = style.wrappedValue
                            current.fontName = newFont
                            style.wrappedValue = current
                        }
                    )
                )
            }
        }
        .task {
            let resolved = markdownAvailableFontOptions()
            guard !resolved.isEmpty else { return }
            fontOptions = resolved
        }
    }

    private func symbol(for level: Int) -> String {
        let index = level - 1
        guard documentStyle.iconConfig.symbols.indices.contains(index) else { return "circle.fill" }
        return documentStyle.iconConfig.symbols[index]
    }

    private func updateSymbol(_ value: String, for level: Int) {
        let index = level - 1
        guard documentStyle.iconConfig.symbols.indices.contains(index) else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        documentStyle.iconConfig.symbols[index] = trimmed.isEmpty ? "circle.fill" : trimmed
    }

    private func resetDefaultIcons() {
        documentStyle.iconConfig = NodeMarkdownLevelIconConfig()
    }

    private func displayMarker(for level: Int) -> String {
        let marker = symbol(for: level)
        return NodeMarkdownRenderStyleCache.markerDisplayText(from: marker)
    }

    private func isPaletteSelected(_ palette: MarkdownPaletteItem, style: NodeMarkdownRoleStyle) -> Bool {
        if palette.semanticColor == .adaptiveBlackWhite {
            return style.semanticColor == .adaptiveBlackWhite
        }
        if style.semanticColor != nil {
            return false
        }
        return NodeMarkdownHTMLBuilder.webHexColor(style.renderedColor) == NodeMarkdownHTMLBuilder.webHexColor(palette.color)
    }

    private func selectedFontDisplayName(for fontName: String) -> String {
        if let matched = fontOptions.first(where: { $0.postScriptName == fontName }) {
            return matched.displayName
        }
        return markdownLocalizedFontDisplayName(postScriptName: fontName)
    }

    private func nodeFontOptionsForSelector(currentFontName: String) -> [MarkdownFontOption] {
        var chineseOptions = fontOptions.filter(\.isChinese)
        let currentDisplay = selectedFontDisplayName(for: currentFontName)
        if !chineseOptions.contains(where: { $0.postScriptName == currentFontName }) {
            chineseOptions.insert(
                MarkdownFontOption(
                    postScriptName: currentFontName,
                    displayName: "\(currentDisplay)（当前）",
                    isChinese: markdownContainsChinese(currentDisplay)
                ),
                at: 0
            )
        }
        if chineseOptions.isEmpty {
            chineseOptions = fontOptions
        }
        return chineseOptions
    }

    private func styleBinding(for role: NodeMarkdownStyleRole) -> Binding<NodeMarkdownRoleStyle> {
        Binding(
            get: { documentStyle.style(for: role) },
            set: { newStyle in
                documentStyle.update(newStyle, for: role)
            }
        )
    }
}

private enum NodeMarkdownExportFormat: String {
    case pdf = "PDF"
    case h1PDF = "PDF分H1"
    case splitPDF = "PDF分文件"
    case monochromePDF = "黑白PDF"
    case monochromeH1PDF = "黑白PDF分H1"
    case monochromeSplitPDF = "PDF黑白分文件"
    case html = "HTML"
    case markdown = "MD"

    var fileExtension: String {
        switch self {
        case .pdf, .h1PDF, .splitPDF, .monochromePDF, .monochromeH1PDF, .monochromeSplitPDF: return "pdf"
        case .html: return "html"
        case .markdown: return "md"
        }
    }

    var contentType: UTType {
        switch self {
        case .pdf, .h1PDF, .splitPDF, .monochromePDF, .monochromeH1PDF, .monochromeSplitPDF: return .pdf
        case .html: return .html
        case .markdown: return .plainText
        }
    }

    var isSplitFileExport: Bool {
        self == .splitPDF || self == .monochromeSplitPDF
    }

    var exportDescriptor: TeachingDocumentExportDescriptor {
        TeachingDocumentExportDescriptor(
            displayName: rawValue,
            fileExtension: fileExtension,
            contentType: contentType,
            suggestedFileNamePrefix: suggestedFileNamePrefix,
            suggestedFileNameSuffix: suggestedFileNameSuffix
        )
    }

    private var suggestedFileNameSuffix: String {
        switch self {
        case .pdf: return ""
        case .h1PDF: return "_分H1"
        case .splitPDF: return "_分文件"
        case .monochromePDF: return ""
        case .monochromeH1PDF: return "_分H1"
        case .monochromeSplitPDF: return "_分文件"
        case .html, .markdown: return ""
        }
    }

    var suggestedFileNamePrefix: String {
        switch self {
        case .monochromePDF, .monochromeH1PDF, .monochromeSplitPDF:
            return "黑白打印专用-"
        default:
            return ""
        }
    }
}

private struct NodeMarkdownHeading: Identifiable, Hashable {
    let nodeID: UUID
    let level: Int
    let title: String
    let rowIndex: Int
    var id: UUID { nodeID }
}

private enum NodeMarkdownTOCExpandMode: String, CaseIterable, Identifiable {
    case l1
    case l3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .l1:
            return "L1"
        case .l3:
            return "L3"
        }
    }
}

private struct NodeMarkdownSearchResult: Identifiable, Hashable {
    let rowIndex: Int
    let matchLocationInRow: Int
    let matchLength: Int
    let snippet: String
    var id: String { "\(rowIndex)-\(matchLocationInRow)-\(matchLength)" }
}

private func nodeMarkdownBuildSearchResults(in nodes: [NodeMarkdownNode], query: String) -> [NodeMarkdownSearchResult] {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return [] }
    return nodes.enumerated().compactMap { index, node -> NodeMarkdownSearchResult? in
        let text = node.text
        guard !text.isEmpty else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let match = nsText.range(of: normalized, options: [.caseInsensitive], range: range)
        guard match.location != NSNotFound, match.length > 0 else { return nil }
        return NodeMarkdownSearchResult(
            rowIndex: index,
            matchLocationInRow: match.location,
            matchLength: match.length,
            snippet: text
        )
    }
}

private struct NodeMarkdownTOCPanelView: View {
    let headings: [NodeMarkdownHeading]
    @Binding var expandMode: NodeMarkdownTOCExpandMode
    let allowsReordering: Bool
    let onMove: (UUID, UUID) -> Bool
    let onSelect: (NodeMarkdownHeading) -> Void
    @State private var searchText = ""
    @State private var expandedL1NodeIDs: Set<UUID> = []
    @State private var dropTargetNodeID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("搜索", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $expandMode) {
                    ForEach(NodeMarkdownTOCExpandMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 104)
            }
            if headings.isEmpty {
                Text("暂无目录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(displayHeadings) { heading in
                            headingRow(heading)
                        }
                    }
                }
            }
        }
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayHeadings: [NodeMarkdownHeading] {
        if !searchQuery.isEmpty {
            return headings.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
        }
        switch expandMode {
        case .l3:
            return headings.filter { $0.level <= 3 }
        case .l1:
            return headings.filter { heading in
                if heading.level == 1 { return true }
                guard heading.level > 1 else { return false }
                guard let root = parentL1(for: heading) else { return false }
                return expandedL1NodeIDs.contains(root.nodeID)
            }
        }
    }

    private func parentL1(for heading: NodeMarkdownHeading) -> NodeMarkdownHeading? {
        guard heading.level > 1 else {
            return heading.level == 1 ? heading : nil
        }
        var found: NodeMarkdownHeading?
        for item in headings {
            guard item.rowIndex <= heading.rowIndex else { break }
            if item.level == 1 {
                found = item
            }
        }
        return found
    }

    private func hasChildren(in heading: NodeMarkdownHeading) -> Bool {
        guard heading.level == 1 else { return false }
        guard let index = headings.firstIndex(of: heading) else { return false }
        guard headings.indices.contains(index + 1) else { return false }
        for item in headings[(index + 1)...] {
            if item.level == 1 { return false }
            return true
        }
        return false
    }

    private func showChevron(for heading: NodeMarkdownHeading) -> Bool {
        expandMode == .l1 && searchQuery.isEmpty && heading.level == 1 && hasChildren(in: heading)
    }

    private func shouldSelectAfterTap(_ heading: NodeMarkdownHeading) -> Bool {
        guard showChevron(for: heading) else { return true }
        if expandedL1NodeIDs.contains(heading.nodeID) {
            expandedL1NodeIDs.remove(heading.nodeID)
        } else {
            expandedL1NodeIDs.insert(heading.nodeID)
        }
        return false
    }

    @ViewBuilder
    private func headingRow(_ heading: NodeMarkdownHeading) -> some View {
        let row = Button {
            guard shouldSelectAfterTap(heading) else { return }
            onSelect(heading)
        } label: {
            HStack(spacing: 6) {
                if showChevron(for: heading) {
                    Image(systemName: expandedL1NodeIDs.contains(heading.nodeID) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Spacer()
                        .frame(width: 10, height: 10)
                }
                Text(heading.title)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 3)
            .padding(.leading, CGFloat(max(0, heading.level - 1)) * 10)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(dropTargetNodeID == heading.nodeID ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)

        if allowsReordering, heading.level <= 3, searchQuery.isEmpty {
            row
                .draggable(heading.nodeID.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    guard let rawID = items.first,
                          let sourceID = UUID(uuidString: rawID) else { return false }
                    return onMove(sourceID, heading.nodeID)
                } isTargeted: { isTargeted in
                    dropTargetNodeID = isTargeted ? heading.nodeID : nil
                }
        } else {
            row
        }
    }
}

private struct NodeMarkdownSearchFloatingPanelView: View {
    let query: String
    let results: [NodeMarkdownSearchResult]
    let activeIndex: Int?
    let onSelect: (Int) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 16, height: 16)
                }
                .appGlassButtonStyle(.danger)
                Spacer()
            }
            if results.isEmpty {
                Text("无匹配项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(results.enumerated()), id: \.offset) { item in
                            let index = item.offset
                            let result = item.element
                            Button {
                                onSelect(index)
                            } label: {
                                Text(markdownSearchHighlightedSnippet(result.snippet, query: query))
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(index == activeIndex ? Color.blue.opacity(0.16) : Color.clear)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(10)
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
    }
}

private enum NodeMarkdownWebAssets {
    static var baseURL: URL? {
        Bundle.main.resourceURL
    }

    static func scriptTag(fileName: String) -> String {
        markdownWebScriptTag(fileName: fileName)
    }

    static func inlineScriptTag(fileName: String) -> String {
        guard let url = markdownWebAssetURL(fileName: fileName),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return scriptTag(fileName: fileName)
        }
        return "<script>\n\(source)\n</script>"
    }

    static func katexStyleTag() -> String {
        let inlineStyle = markdownWebInlineKaTeXStyleTag()
        if !inlineStyle.isEmpty {
            return inlineStyle
        }
        if let url = markdownWebAssetURL(fileName: "katex.min.css") {
            return "<link rel=\"stylesheet\" href=\"\(url.absoluteString)\" />"
        }
        return ""
    }
}

// MARK: - NodeMarkdown HTML构建器 - v1 - 构建轻量静态HTML避免全量复杂脚本
enum NodeMarkdownHTMLBuilder {
    static func buildRows(
        document: NodeMarkdownDocument,
        style: NodeMarkdownDocumentStyle,
        exportScheme: NodeMarkdownPreferredScheme? = nil
    ) -> String {
        let displayStyle = style.platformDisplayStyle
        let styleCache = NodeMarkdownRenderStyleCache(style: displayStyle, exportScheme: exportScheme)
        return document.nodes.enumerated().map { index, node in
            let previousNode = index > 0 ? document.nodes[index - 1] : nil
            let level = max(1, min(12, node.level))
            let previousLevel = previousNode.map { max(1, min(12, $0.level)) }
            let spacingBefore = NodeMarkdownRenderContract.interRowSpacing(
                previousLevel: previousLevel,
                previousRoleStyle: previousLevel.map { displayStyle.style(forLevel: $0) },
                currentLevel: level,
                currentRoleStyle: displayStyle.style(forLevel: level)
            )
            return buildRow(
                index: index,
                node: node,
                styleCache: styleCache,
                spacingBefore: spacingBefore
            )
        }
        .joined(separator: "\n")
    }

    static func documentHTML(
        initialRowsHTML: String,
        backgroundHex: String? = nil,
        baseURL: URL? = nil,
        inlineAssets: Bool = false
    ) -> String {
        let bodyBackground = backgroundHex ?? "transparent"
        let baseTag = baseURL.map { "<base href=\"\(htmlAttributeEscape($0.absoluteString))\" />" } ?? ""
        let katexScriptTag = inlineAssets
            ? NodeMarkdownWebAssets.inlineScriptTag(fileName: "katex.min.js")
            : NodeMarkdownWebAssets.scriptTag(fileName: "katex.min.js")
        let autoRenderScriptTag = inlineAssets
            ? NodeMarkdownWebAssets.inlineScriptTag(fileName: "auto-render.min.js")
            : NodeMarkdownWebAssets.scriptTag(fileName: "auto-render.min.js")
        let markedScriptTag = inlineAssets
            ? NodeMarkdownWebAssets.inlineScriptTag(fileName: "marked.min.js")
            : NodeMarkdownWebAssets.scriptTag(fileName: "marked.min.js")
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        \(baseTag)
        \(NodeMarkdownWebAssets.katexStyleTag())
        <style>
        html, body {
            margin: 0;
            padding: 0;
            background: \(bodyBackground);
            font-family: -apple-system, BlinkMacSystemFont, "SF Mono", "Menlo", monospace;
            line-height: 1.4;
        }
        .container {
            padding-left: 2ch;
            padding-right: 2ch;
            box-sizing: border-box;
        }
        .row {
            position: relative;
            display: flex;
            align-items: flex-start;
            min-height: 0;
            margin: 0;
            white-space: pre-wrap;
            word-break: break-word;
            line-height: var(--node-line-height, 1.4);
        }
        .row.has-bgbar::before {
            content: "";
            position: absolute;
            z-index: 0;
            left: var(--bgbar-left, 0px);
            right: 0;
            top: max(0px, calc((var(--first-line-height, 1em) - var(--bgbar-height, 1em)) / 2));
            height: var(--bgbar-height, 1em);
            border-radius: var(--bgbar-radius-x, 1em) / var(--bgbar-radius-y, 50%);
            background: linear-gradient(90deg, var(--bgbar-start) 0%, var(--bgbar-end) 100%);
            border: var(--decoration-border, 0 solid transparent);
            box-sizing: border-box;
            pointer-events: none;
        }
        .icon {
            width: var(--marker-advance, 1em);
            margin-right: 0;
            opacity: 0.9;
            text-align: center;
            flex: 0 0 auto;
            user-select: none;
            -webkit-user-select: none;
            pointer-events: none;
            line-height: var(--first-line-height, 1.4em);
            z-index: 1;
        }
        .text {
            flex: 1 1 auto;
            min-width: 0;
            z-index: 1;
            font-family: inherit;
        }
        .text p {
            display: inline;
            margin: 0;
            color: inherit;
            font-family: inherit;
            font-size: inherit;
        }
        .text img {
            vertical-align: middle;
        }
        .text > *:first-child {
            margin-top: 0;
        }
        .text > *:last-child {
            margin-bottom: 0;
        }
        .row:hover {
            opacity: 0.92;
        }
        .row.active-search {
            outline: 1px solid rgba(69, 140, 255, 0.70);
            background: rgba(69, 140, 255, 0.14) !important;
        }
        .text mark {
            background: #F0C847;
            border-radius: 8px;
            border: var(--decoration-border, 0 solid transparent);
            box-sizing: border-box;
            padding: 0 0.2em;
            color: inherit;
        }
        .text .katex {
            vertical-align: middle;
        }
        .text .katex-display {
            margin: 0 !important;
        }
        .icon {
            display: inline-flex;
            align-items: center;
            justify-content: center;
        }
        .row.editing .icon,
        .row.editing .text {
            opacity: 0;
        }
        </style>
        \(katexScriptTag)
        \(autoRenderScriptTag)
        \(markedScriptTag)
        <script>
        window.__activeSearchIndex = null;
        window.__editingRowIndex = null;
        window.__schedulePostLayout = null;
        window.__layoutThrottleMs = 33;
        window.__layoutThrottleTimer = null;
        window.__lastLayoutEmitAt = 0;
        window.__needsFullLayoutSnapshot = true;
        window.__pendingLayoutOptions = { partial: false, targetIndex: null };
        window.__lastVisibleLayoutByIndex = {};
        window.__visibleRowMap = {};
        window.__visibleObserver = null;
        window.__scrollIdleTimer = null;
        window.__scrollIdleDelayMs = 120;
        window.__layoutRowEqual = function(lhs, rhs) {
            if (!lhs || !rhs) { return false; }
            return Math.abs(lhs.x - rhs.x) < 0.25 &&
                Math.abs(lhs.width - rhs.width) < 0.25 &&
                Math.abs(lhs.y - rhs.y) < 0.25 &&
                Math.abs(lhs.height - rhs.height) < 0.25;
        };
        window.__registerVisibleObserver = function(root) {
            if (!root) { return; }
            if (window.__visibleObserver) {
                window.__visibleObserver.disconnect();
                window.__visibleObserver = null;
            }
            window.__visibleRowMap = {};
            if (typeof window.IntersectionObserver !== 'function') {
                root.querySelectorAll('.row').forEach(function(row) {
                    const indexValue = Number(row.getAttribute('data-node-index'));
                    if (Number.isFinite(indexValue)) {
                        window.__visibleRowMap[String(indexValue)] = true;
                    }
                });
                return;
            }
            window.__visibleObserver = new IntersectionObserver(function(entries) {
                entries.forEach(function(entry) {
                    const row = entry.target;
                    const indexValue = Number(row.getAttribute('data-node-index'));
                    if (!Number.isFinite(indexValue)) { return; }
                    const key = String(indexValue);
                    if (entry.isIntersecting) {
                        window.__visibleRowMap[key] = true;
                    } else {
                        delete window.__visibleRowMap[key];
                    }
                });
            }, {
                root: null,
                rootMargin: '400px 0px 400px 0px',
                threshold: 0
            });
            root.querySelectorAll('.row').forEach(function(row) {
                window.__visibleObserver.observe(row);
            });
        };
        window.__layoutRowMapFromArray = function(rows) {
            const map = {};
            rows.forEach(function(row) {
                map[String(row.index)] = row;
            });
            return map;
        };
        window.__collectRowsForLayout = function(root, partial, targetIndex) {
            if (partial && targetIndex !== null) {
                const set = new Set();
                for (let index = targetIndex - 1; index <= targetIndex + 1; index += 1) {
                    const node = root.querySelector('.row[data-node-index="' + index + '"]');
                    if (node) {
                        set.add(node);
                    }
                }
                return Array.from(set);
            }
            const keys = Object.keys(window.__visibleRowMap || {});
            if (keys.length > 0) {
                const list = [];
                keys.forEach(function(key) {
                    const node = root.querySelector('.row[data-node-index="' + key + '"]');
                    if (node) {
                        list.push(node);
                    }
                });
                if (list.length > 0) {
                    return list;
                }
            }
            return Array.from(root.querySelectorAll('.row'));
        };
        window.__emitRowLayout = function(options) {
            const opts = options || {};
            const partial = opts.partial === true;
            const targetIndex = Number.isFinite(opts.targetIndex) ? Number(opts.targetIndex) : null;
            const root = document.getElementById('rows');
            if (!root) { return; }
            const rootRect = root.getBoundingClientRect();
            const payload = [];
            const layoutRows = window.__collectRowsForLayout(root, partial, targetIndex);
            layoutRows.forEach(function(row) {
                const indexValue = Number(row.getAttribute('data-node-index'));
                if (!Number.isFinite(indexValue)) { return; }
                const rowRect = row.getBoundingClientRect();
                const paddingLeft = parseFloat(row.getAttribute('data-padding-left') || '0') || 0;
                const barStartX = Math.max(0, rowRect.left - rootRect.left + paddingLeft);
                const barWidth = Math.max(0, rowRect.width - paddingLeft);
                payload.push({
                    index: indexValue,
                    x: barStartX,
                    width: barWidth,
                    y: rowRect.top,
                    height: rowRect.height
                });
            });
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.rowLayout) {
                const currentMap = window.__layoutRowMapFromArray(payload);
                const previousMap = window.__lastVisibleLayoutByIndex || {};
                if (!partial && window.__needsFullLayoutSnapshot) {
                    window.__needsFullLayoutSnapshot = false;
                    window.__lastVisibleLayoutByIndex = currentMap;
                    window.webkit.messageHandlers.rowLayout.postMessage({
                        partial: false,
                        rows: payload,
                        removed: []
                    });
                    return;
                }
                const isTargetPartial = partial && targetIndex !== null;
                const changedRows = [];
                payload.forEach(function(row) {
                    const previous = previousMap[String(row.index)];
                    if (!window.__layoutRowEqual(previous, row)) {
                        changedRows.push(row);
                    }
                });
                const removed = [];
                if (!isTargetPartial) {
                    Object.keys(previousMap).forEach(function(key) {
                        if (!(key in currentMap)) {
                            const indexValue = Number(key);
                            if (Number.isFinite(indexValue)) {
                                removed.push(indexValue);
                            }
                        }
                    });
                }
                if (changedRows.length === 0 && removed.length === 0) {
                    return;
                }
                if (isTargetPartial) {
                    const mergedMap = Object.assign({}, previousMap);
                    payload.forEach(function(row) {
                        mergedMap[String(row.index)] = row;
                    });
                    window.__lastVisibleLayoutByIndex = mergedMap;
                } else {
                    window.__lastVisibleLayoutByIndex = currentMap;
                }
                window.webkit.messageHandlers.rowLayout.postMessage({
                    partial: true,
                    rows: changedRows,
                    removed: removed
                });
            }
        };
        window.__queueRowLayout = function(options) {
            const opts = options || {};
            const nextPartial = opts.partial === true;
            const nextTargetIndex = Number.isFinite(opts.targetIndex) ? Number(opts.targetIndex) : null;
            if (!window.__pendingLayoutOptions) {
                window.__pendingLayoutOptions = { partial: false, targetIndex: null };
            }
            if (!nextPartial) {
                window.__pendingLayoutOptions = { partial: false, targetIndex: null };
            } else if (window.__pendingLayoutOptions.partial) {
                window.__pendingLayoutOptions.targetIndex = nextTargetIndex;
            } else {
                window.__pendingLayoutOptions = { partial: true, targetIndex: nextTargetIndex };
            }
            const now = (window.performance && typeof window.performance.now === 'function')
                ? window.performance.now()
                : Date.now();
            const elapsed = now - window.__lastLayoutEmitAt;
            const scheduleEmit = function() {
                if (window.__schedulePostLayout !== null) {
                    cancelAnimationFrame(window.__schedulePostLayout);
                }
                window.__schedulePostLayout = requestAnimationFrame(function() {
                    window.__schedulePostLayout = null;
                    window.__lastLayoutEmitAt = (window.performance && typeof window.performance.now === 'function')
                        ? window.performance.now()
                        : Date.now();
                    const emitOptions = window.__pendingLayoutOptions || { partial: false, targetIndex: null };
                    window.__pendingLayoutOptions = { partial: false, targetIndex: null };
                    window.__emitRowLayout(emitOptions);
                });
            };
            if (elapsed >= window.__layoutThrottleMs && window.__layoutThrottleTimer === null) {
                scheduleEmit();
                return;
            }
            if (window.__layoutThrottleTimer !== null) {
                return;
            }
            const delay = Math.max(0, window.__layoutThrottleMs - elapsed);
            window.__layoutThrottleTimer = setTimeout(function() {
                window.__layoutThrottleTimer = null;
                scheduleEmit();
            }, delay);
        };
        window.__escapeHTML = function(value) {
            return String(value || '')
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;')
                .replace(/'/g, '&#39;');
        };
        window.__decodeEntities = function(value) {
            const textarea = document.createElement('textarea');
            textarea.innerHTML = String(value || '');
            return textarea.value;
        };
        window.__sanitizeRenderedSource = function(value) {
            return String(value || '').split(String.fromCharCode(0xFFFC)).join('');
        };
        window.__nodeMarkdownDisplayScale = \(nodeMarkdownHTMLDisplayScaleLiteral());
        window.__renderMarkdownInRows = function(root) {
            if (!root) { return; }
            root.querySelectorAll('.text').forEach(function(textElement) {
                const source = window.__sanitizeRenderedSource(window.__decodeEntities(textElement.getAttribute('data-markdown') || ''));
                const fallback = window.__escapeHTML(source);
                if (!source) {
                    textElement.innerHTML = '';
                    return;
                }
                try {
                    if (window.marked && typeof window.marked.parseInline === 'function') {
                        textElement.innerHTML = window.marked.parseInline(source, { gfm: true, breaks: true });
                    } else if (window.marked && typeof window.marked.parse === 'function') {
                        textElement.innerHTML = window.marked.parse(source, { gfm: true, breaks: true });
                    } else if (typeof window.marked === 'function') {
                        if (typeof window.marked.parse === 'function') {
                            textElement.innerHTML = window.marked.parse(source, { gfm: true, breaks: true });
                        } else {
                            textElement.innerHTML = window.marked(source);
                        }
                    } else {
                        textElement.innerHTML = fallback;
                    }
                } catch (_) {
                    textElement.innerHTML = fallback;
                }
            });
        };
        window.__normalizeImagesInRows = function(root) {
            if (!root) { return; }
            const scale = Number(window.__nodeMarkdownDisplayScale || 1);
            root.querySelectorAll('img').forEach(function(img) {
                const next = img.nextSibling;
                if (next && next.nodeType === Node.TEXT_NODE) {
                    const widthText = String(next.nodeValue || '');
                    const trimmed = widthText.trimStart();
                    const leadingLength = widthText.length - trimmed.length;
                    if (trimmed.startsWith('{width=')) {
                        const endIndex = trimmed.indexOf('}');
                        const widthValue = endIndex > 7 ? trimmed.slice(7, endIndex) : '';
                        const rawWidth = Number(widthValue);
                        if (Number.isFinite(rawWidth) && rawWidth > 0 && String(Math.floor(rawWidth)) === widthValue) {
                            img.dataset.nodeMarkdownOriginalWidth = String(rawWidth);
                            img.setAttribute('width', String(Math.max(1, Math.round(rawWidth * scale))));
                            img.dataset.nodeMarkdownScaledWidth = '1';
                            next.nodeValue = widthText.slice(0, leadingLength) + trimmed.slice(endIndex + 1);
                        }
                    }
                }
                const widthAttr = Number(img.getAttribute('width'));
                if (Number.isFinite(widthAttr) && widthAttr > 0 && img.dataset.nodeMarkdownScaledWidth !== '1') {
                    img.dataset.nodeMarkdownOriginalWidth = String(widthAttr);
                    img.setAttribute('width', String(Math.max(1, Math.round(widthAttr * scale))));
                    img.dataset.nodeMarkdownScaledWidth = '1';
                }
                img.style.maxWidth = '100%';
                img.style.height = 'auto';
                img.style.display = img.style.display || 'inline-block';
            });
        };
        window.__renderMathInRows = function(root) {
            if (!root || typeof window.renderMathInElement !== 'function') { return; }
            window.renderMathInElement(root, {
                delimiters: [
                    { left: '$$', right: '$$', display: true },
                    { left: '\\\\[', right: '\\\\]', display: true },
                    { left: '$', right: '$', display: false },
                    { left: '\\\\(', right: '\\\\)', display: false }
                ],
                throwOnError: false
            });
        };
        window.__postProcessRows = function() {
            const root = document.getElementById('rows');
            if (!root) { return; }
            window.__renderMarkdownInRows(root);
            window.__normalizeImagesInRows(root);
            window.__renderMathInRows(root);
            window.__queueRowLayout();
        };
        window.__postProcessRowAtIndex = function(index) {
            const root = document.getElementById('rows');
            if (!root || !Number.isFinite(index)) { return; }
            const row = root.querySelector('.row[data-node-index="' + index + '"]');
            if (!row) { return; }
            window.__renderMarkdownInRows(row);
            window.__normalizeImagesInRows(row);
            window.__renderMathInRows(row);
            window.__queueRowLayout({ partial: true, targetIndex: index });
        };
        window.__setActiveSearch = function(index) {
            const root = document.getElementById('rows');
            if (!root) { return; }
            root.querySelectorAll('.row.active-search').forEach(function(node) {
                node.classList.remove('active-search');
            });
            window.__activeSearchIndex = index;
            const target = root.querySelector('.row[data-node-index="' + index + '"]');
            if (target) {
                target.classList.add('active-search');
                target.scrollIntoView({behavior: 'smooth', block: 'center'});
            }
        };
        window.__clearActiveSearch = function() {
            const root = document.getElementById('rows');
            if (!root) { return; }
            root.querySelectorAll('.row.active-search').forEach(function(node) {
                node.classList.remove('active-search');
            });
            window.__activeSearchIndex = null;
        };
        window.__setEditingRow = function(index) {
            const root = document.getElementById('rows');
            if (!root) { return; }
            root.querySelectorAll('.row.editing').forEach(function(node) {
                node.classList.remove('editing');
            });
            window.__editingRowIndex = index;
            const target = root.querySelector('.row[data-node-index="' + index + '"]');
            if (target) {
                target.classList.add('editing');
            }
            window.__queueRowLayout({ partial: true, targetIndex: index });
        };
        window.__clearEditingRow = function() {
            const root = document.getElementById('rows');
            if (!root) { return; }
            root.querySelectorAll('.row.editing').forEach(function(node) {
                node.classList.remove('editing');
            });
            const previousIndex = window.__editingRowIndex;
            window.__editingRowIndex = null;
            if (Number.isFinite(previousIndex)) {
                window.__postProcessRowAtIndex(previousIndex);
            } else {
                window.__queueRowLayout();
            }
        };
        window.__updateRows = function(rowsHTML) {
            const root = document.getElementById('rows');
            if (root) {
                root.innerHTML = rowsHTML;
                window.__needsFullLayoutSnapshot = true;
                window.__lastVisibleLayoutByIndex = {};
                window.__registerVisibleObserver(root);
                window.__postProcessRows();
                if (window.__activeSearchIndex !== null) {
                    window.__setActiveSearch(window.__activeSearchIndex);
                }
                if (window.__editingRowIndex !== null) {
                    window.__setEditingRow(window.__editingRowIndex);
                }
            }
        };
        document.addEventListener('DOMContentLoaded', function() {
            const root = document.getElementById('rows');
            window.__registerVisibleObserver(root);
            window.__postProcessRows();
        });
        window.addEventListener('resize', function() {
            window.__queueRowLayout();
        });
        window.addEventListener('scroll', function() {
            window.__queueRowLayout({ partial: true, targetIndex: window.__editingRowIndex });
            if (window.__scrollIdleTimer !== null) {
                clearTimeout(window.__scrollIdleTimer);
            }
            window.__scrollIdleTimer = setTimeout(function() {
                window.__scrollIdleTimer = null;
                window.__queueRowLayout({ partial: false, targetIndex: null });
            }, window.__scrollIdleDelayMs);
        }, {passive: true});
        document.addEventListener('click', function(event) {
            let target = event.target;
            while (target && !target.classList.contains('row')) {
                target = target.parentElement;
            }
            if (!target) { return; }
            const index = target.getAttribute('data-node-index');
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nodeTap) {
                window.webkit.messageHandlers.nodeTap.postMessage(index);
            }
        });
        </script>
        </head>
        <body>
            <div class="container" id="rows">\(initialRowsHTML)</div>
        </body>
        </html>
        """
    }

    private static func nodeMarkdownHTMLDisplayScaleLiteral() -> String {
        #if os(iOS)
        return "0.5"
        #else
        return "1"
        #endif
    }

    static func updateRowsScript(rowsHTML: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [rowsHTML], options: []),
              let arrayLiteral = String(data: data, encoding: .utf8),
              arrayLiteral.count >= 2 else {
            return nil
        }
        let valueLiteral = String(arrayLiteral.dropFirst().dropLast())
        return "window.__updateRows(\(valueLiteral));"
    }

    static func updateActiveSearchScript(rowIndex: Int?) -> String {
        guard let rowIndex else { return "window.__clearActiveSearch();" }
        return "window.__setActiveSearch(\(rowIndex));"
    }

    static func updateEditingRowScript(rowIndex: Int?) -> String {
        guard let rowIndex else { return "window.__clearEditingRow();" }
        return "window.__setEditingRow(\(rowIndex));"
    }

    private static func buildRow(
        index: Int,
        node: NodeMarkdownNode,
        styleCache: NodeMarkdownRenderStyleCache,
        spacingBefore: CGFloat
    ) -> String {
        let level = max(1, min(12, node.level))
        let cachedStyle = styleCache.style(for: level)
        let leftIndent = max(0, level - 1) * 18
        let iconSymbol = htmlEscape(styleCache.iconSymbolGlyph(for: level))
        let escapedText = htmlEscape(node.text)
        let escapedMarkdown = htmlAttributeEscape(node.text)
        let rowClass = cachedStyle.hasBackgroundBar ? "row has-bgbar" : "row"
        let bgbarAttr = cachedStyle.hasBackgroundBar ? "1" : "0"
        let spacingCSS = "margin-top:\(Int(max(0, spacingBefore).rounded()))px;"
        return """
        <div class="\(rowClass)" data-node-index="\(index)" data-padding-left="\(leftIndent)" data-pdf-bgbar="\(bgbarAttr)" data-pdf-bgcolor="\(cachedStyle.backgroundColorHex)" style="padding-left:\(leftIndent)px;cursor:text;--marker-advance:\(cachedStyle.markerAdvance)px;\(spacingCSS)\(cachedStyle.rowCSS)">
            <span class="icon" style="color:\(cachedStyle.colorHex);font-size:\(cachedStyle.iconFontSize)px">\(iconSymbol)</span>
            <div class="text" data-markdown="\(escapedMarkdown)" style="color:\(cachedStyle.colorHex);font-size:\(cachedStyle.fontSize)px;font-weight:\(cachedStyle.fontWeight);\(cachedStyle.textDecorationCSS)">\(escapedText)</div>
        </div>
        """
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func htmlAttributeEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\n", with: "&#10;")
            .replacingOccurrences(of: "\r", with: "&#13;")
    }

    fileprivate static func webHexColor(
        _ color: Color,
        exportScheme: NodeMarkdownPreferredScheme? = nil
    ) -> String {
        #if os(macOS)
        let resolved: NSColor
        if let exportScheme,
           let appearance = NSAppearance(named: exportScheme == .dark ? .darkAqua : .aqua) {
            var exportResolved: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                exportResolved = NSColor(color).usingColorSpace(.sRGB)
            }
            resolved = exportResolved ?? NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
        } else {
            resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
        }
        let r = Int(round(resolved.redComponent * 255))
        let g = Int(round(resolved.greenComponent * 255))
        let b = Int(round(resolved.blueComponent * 255))
        #elseif os(iOS)
        let resolved: UIColor
        if let exportScheme {
            let traits = UITraitCollection(userInterfaceStyle: exportScheme == .dark ? .dark : .light)
            resolved = UIColor(color).resolvedColor(with: traits)
        } else {
            resolved = UIColor(color)
        }
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let r = Int(round(red * 255))
        let g = Int(round(green * 255))
        let b = Int(round(blue * 255))
        #endif
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    static func exportBackgroundHex(for style: NodeMarkdownDocumentStyle) -> String {
        let exportScheme = style.preferredScheme.resolvedExportScheme
        guard !style.useSystemBackground else {
            return exportScheme == .dark ? "#000000" : "#FFFFFF"
        }
        return webHexColor(style.editorBackgroundColor, exportScheme: exportScheme)
    }

}

// MARK: - NodeMarkdown渲染样式缓存 - v1 - 预计算12层字体颜色权重避免重复转换
private struct NodeMarkdownRenderStyleCache {
    struct CachedStyle {
        var colorHex: String
        var fontSize: Int
        var iconFontSize: Int
        var fontWeight: String
        var textDecorationCSS: String
        var rowCSS: String
        var hasBackgroundBar: Bool
        var backgroundColorHex: String
        var markerAdvance: Int
    }

    private let iconConfig: NodeMarkdownLevelIconConfig
    private let renderContract = NodeMarkdownRenderContract.default
    private let cached: [Int: CachedStyle]

    init(style: NodeMarkdownDocumentStyle, exportScheme: NodeMarkdownPreferredScheme? = nil) {
        iconConfig = style.iconConfig
        var map: [Int: CachedStyle] = [:]
        for level in 1...12 {
            let roleStyle = style.style(forLevel: level)
            let colorHex = NodeMarkdownHTMLBuilder.webHexColor(roleStyle.renderedColor, exportScheme: exportScheme)
            let backgroundColorHex = NodeMarkdownRenderContract.backgroundWebHex(fromHex: colorHex)
            let fontSize = Int(roleStyle.fontSize.rounded())
            let lineStyle = renderContract.lineStyle(
                level: level,
                prefix: NodeMarkdownPrefixCodec.encode(level: level),
                documentStyle: style
            )
            map[level] = CachedStyle(
                colorHex: colorHex,
                fontSize: fontSize,
                iconFontSize: fontSize,
                fontWeight: roleStyle.isBold ? "700" : "500",
                textDecorationCSS: roleStyle.isUnderline ? "text-decoration-line:underline;text-decoration-color:#007AFF;" : "",
                rowCSS: Self.rowCSS(
                    for: roleStyle,
                    backgroundColorHex: backgroundColorHex,
                    usesMonochromeDecorationBorders: style.usesMonochromeDecorationBorders
                ),
                hasBackgroundBar: roleStyle.hasBackgroundBar,
                backgroundColorHex: backgroundColorHex,
                markerAdvance: Int(ceil(lineStyle.contentX - lineStyle.markerX))
            )
        }
        cached = map
    }

    func style(for level: Int) -> CachedStyle {
        cached[level] ?? cached[1] ?? CachedStyle(colorHex: "#FFFFFF", fontSize: 15, iconFontSize: 15, fontWeight: "500", textDecorationCSS: "", rowCSS: "", hasBackgroundBar: false, backgroundColorHex: "#FFFFFF", markerAdvance: 22)
    }

    private static func rowCSS(
        for roleStyle: NodeMarkdownRoleStyle,
        backgroundColorHex: String,
        usesMonochromeDecorationBorders: Bool
    ) -> String {
        let fontSize = max(1, roleStyle.fontSize)
        let firstLineHeight = ceil(fontSize * 1.4)
        let barHeight = ceil(fontSize)
        var css = "--node-line-height:1.4;--first-line-height:\(Int(firstLineHeight))px;"
        css += usesMonochromeDecorationBorders
            ? "--decoration-border:1px solid #000000;"
            : "--decoration-border:0 solid transparent;"
        guard roleStyle.hasBackgroundBar else { return css }
        let backgroundBar = NodeMarkdownRenderContract.default.backgroundBar
        let start = NodeMarkdownRenderContract.webRGBA(fromHex: backgroundColorHex, alpha: backgroundBar.startAlpha)
        let end = NodeMarkdownRenderContract.webRGBA(fromHex: backgroundColorHex, alpha: backgroundBar.endAlpha)
        css += "--bgbar-left:0px;--bgbar-height:\(Int(barHeight))px;--bgbar-radius-x:1em;--bgbar-radius-y:50%;--bgbar-start:\(start);--bgbar-end:\(end);"
        return css
    }

    func iconSymbol(for level: Int) -> String {
        iconConfig.symbol(for: level)
    }

    static func markerDisplayText(from raw: String) -> String {
        NodeMarkdownRenderContract.markerDisplayText(from: raw)
    }

    func iconSymbolGlyph(for level: Int) -> String {
        NodeMarkdownRenderContract.markerDisplayText(from: iconConfig.symbol(for: level))
    }
}

private extension View {
    @ViewBuilder
    func nodeMarkdownAdaptiveSheetSize(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        frame(width: width, height: height)
        #else
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
    }
}

#if os(iOS)
private struct NodeMarkdownReadOnlyRenderView: UIViewRepresentable {
    let rowsHTML: String
    let baseURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.keyboardDismissMode = .onDrag
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = NodeMarkdownHTMLBuilder.documentHTML(initialRowsHTML: rowsHTML)
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator {
        var loadedHTML = ""
    }
}
#else
private struct NodeMarkdownReadOnlyRenderView: View {
    let rowsHTML: String

    var body: some View {
        ScrollView {
            Text(rowsHTML)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }
}
#endif

#if os(macOS)
private struct NodeMarkdownThreeLineEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.drawsBackground = false
        textView.delegate = context.coordinator
        textView.string = text
        textView.textContainerInset = NSSize(width: 2, height: 2)
        textView.isVerticallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.maximumNumberOfLines = 3
        textView.textContainer?.heightTracksTextView = false

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            context.coordinator.isProgrammatic = true
            textView.string = text
            context.coordinator.isProgrammatic = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var isProgrammatic = false

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammatic, let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

private struct NodeMarkdownFormulaPreviewView: NSViewRepresentable {
    let source: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let escaped = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8" />
        \(NodeMarkdownWebAssets.katexStyleTag())
        </head>
        <body style="margin:8px;background:transparent;font-family:-apple-system;">
        <div id="formula"></div>
        \(NodeMarkdownWebAssets.scriptTag(fileName: "katex.min.js"))
        \(NodeMarkdownWebAssets.scriptTag(fileName: "auto-render.min.js"))
        \(NodeMarkdownWebAssets.scriptTag(fileName: "marked.min.js"))
        <script>
        const source = '\(escaped)';
        const root = document.getElementById('formula');
        if (window.marked && root) {
            root.innerHTML = marked.parse(source);
        } else if (root) {
            root.textContent = source;
        }
        if (window.renderMathInElement) {
            renderMathInElement(root, {throwOnError:false});
        }
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: NodeMarkdownWebAssets.baseURL)
    }
}

#else

private struct NodeMarkdownThreeLineEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
    }
}

private struct NodeMarkdownFormulaPreviewView: View {
    let source: String

    var body: some View {
        ScrollView {
            Text(source)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
    }
}

#endif
