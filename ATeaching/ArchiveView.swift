import SwiftUI

// MARK: - 档案管理页 - v2 - 提供目录浏览右键管理并支持打开Markdown独立窗口
struct ArchiveView: View {
    private enum FeaturePanel {
        case archive
        case templateManagement
        case autoFill
        case smartCollect
        case recycleBin

        var title: String {
            switch self {
            case .archive: return "档案"
            case .templateManagement: return "模板管理"
            case .autoFill: return "自动填写"
            case .smartCollect: return "智能收集"
            case .recycleBin: return "回收站"
            }
        }

        var systemImage: String {
            switch self {
            case .archive: return "folder"
            case .templateManagement: return "doc.on.doc"
            case .autoFill: return "wand.and.stars"
            case .smartCollect: return "sparkles"
            case .recycleBin: return "trash"
            }
        }
    }

    private struct MarkdownNavigationTarget: Identifiable, Hashable {
        let id: String
    }

    private struct SingleListNavigationTarget: Identifiable, Hashable {
        let id: String
    }

    private struct AutoFillNavigationTarget: Identifiable, Hashable {
        let id: String
    }

    private struct ChecklistNavigationTarget: Identifiable, Hashable {
        let id: String
    }
    
    private struct NodeMarkdownNavigationTarget: Identifiable, Hashable {
        let id: String
    }

    private enum SmartCollectKind: Int, CaseIterable {
        case lessonPlan
        case checklist
        case table
        case markdown
        case other

        var title: String {
            switch self {
            case .lessonPlan: return "教案资料"
            case .checklist: return "清单资料"
            case .table: return "表格资料"
            case .markdown: return "Markdown"
            case .other: return "其他资料"
            }
        }

        var folderName: String {
            switch self {
            case .lessonPlan: return "智能收集-教案资料"
            case .checklist: return "智能收集-清单资料"
            case .table: return "智能收集-表格资料"
            case .markdown: return "智能收集-Markdown"
            case .other: return "智能收集-其他资料"
            }
        }

        var iconName: String {
            switch self {
            case .lessonPlan: return "book.closed.fill"
            case .checklist: return "checklist.checked"
            case .table: return "tablecells.fill"
            case .markdown: return "doc.text.fill"
            case .other: return "tray.full.fill"
            }
        }
    }

    private struct SmartCollectGroup: Identifiable {
        let kind: SmartCollectKind
        let fileNames: [String]

        var id: Int { kind.rawValue }
        var count: Int { fileNames.count }
    }

    private struct SmartCollectMovePreview: Identifiable {
        let sourceURL: URL
        let destinationURL: URL
        let kind: SmartCollectKind

        var id: String { sourceURL.path + "->" + destinationURL.path }
    }

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    // MARK: - 加载结果定义 - v2 - 统一封装档案目录加载状态
    private enum ArchiveLoadResult {
        case initial(URL, [ArchiveEntry])
        case directory(URL, [ArchiveEntry])
        case failure(String)
    }

    @State private var archiveRootURL: URL?
    @State private var currentDirectoryURL: URL?
    @State private var entries: [ArchiveEntry] = []
    @State private var statusMessage = ""
    @State private var isLoading = false
    @State private var isBackgroundRefreshing = false

    @State private var showCreateFolderAlert = false
    @State private var newFolderName = ""
    @State private var showCreateFileSheet = false

    @State private var showRenameAlert = false
    @State private var renameTarget: ArchiveEntry?
    @State private var renameName = ""

    @State private var showDeleteAlert = false
    @State private var deleteTarget: ArchiveEntry?
    @State private var moveTarget: ArchiveEntry?
    @State private var showMovePicker = false
    @State private var showMultiMovePicker = false
    @State private var isMultiSelecting = false
    @State private var selectedEntryIDs: Set<URL> = []
    @State private var showDeleteSelectedAlert = false
    @State private var showCollectSelectedFolderAlert = false
    @State private var collectSelectedFolderName = ""
    @StateObject private var directoryWatcher = ArchiveDirectoryWatcher(onChange: {})
    @State private var selectedPanel: FeaturePanel = .archive
    @State private var autoFillRefreshTrigger = 0
    @State private var recycleRefreshTrigger = 0
    @State private var recycleClearAllTrigger = 0
    @State private var templateToggleMultiSelectTrigger = 0
    @State private var templateCreateTrigger = 0
    @State private var smartCollectGroups: [SmartCollectGroup] = []
    @State private var isRunningSmartCollect = false
    @State private var smartCollectPreviewItems: [SmartCollectMovePreview] = []
    @State private var showSmartCollectPreviewSheet = false
    @State private var markdownNavigationTarget: MarkdownNavigationTarget?
    @State private var singleListNavigationTarget: SingleListNavigationTarget?
    @State private var autoFillNavigationTarget: AutoFillNavigationTarget?
    @State private var checklistNavigationTarget: ChecklistNavigationTarget?
    @State private var nodeMarkdownNavigationTarget: NodeMarkdownNavigationTarget?


    var body: some View {
        VStack(spacing: 0) {
            topFeatureBar
            panelContent
        }
        .background(AppBackgroundVisualStyle.pageBackground)
        .task {
            if archiveRootURL == nil && !isLoading {
                loadArchiveRoot()
            }
        }
        .onChange(of: entries) { _, _ in
            if selectedPanel == .smartCollect {
                runSmartCollectScan()
            }
        }
        .onChange(of: currentDirectoryURL) { _, newValue in
            directoryWatcher.watch(newValue)
            selectedEntryIDs.removeAll()
        }
        .alert("新建文件夹", isPresented: $showCreateFolderAlert) {
            TextField("文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                createFolder()
            }
        } message: {
            Text("将在当前目录下创建文件夹。")
        }
        .alert("改名", isPresented: $showRenameAlert) {
            TextField("新名称", text: $renameName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                renameEntry()
            }
        } message: {
            Text("修改选中文件或文件夹名称。")
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {
                deleteTarget = nil
            }
            Button("移入回收站", role: .destructive) {
                moveToRecycleBin()
            }
        } message: {
            Text("文件将移动到“系统/回收站”，并写入来源CSV。")
        }
        .alert("确认删除所选项目", isPresented: $showDeleteSelectedAlert) {
            Button("取消", role: .cancel) {}
            Button("移入回收站", role: .destructive) {
                moveSelectedToRecycleBin()
            }
        } message: {
            Text("所选文件和文件夹将移动到“系统/回收站”。")
        }
        .alert("组成文件夹", isPresented: $showCollectSelectedFolderAlert) {
            TextField("文件夹名称", text: $collectSelectedFolderName)
            Button("取消", role: .cancel) {}
            Button("创建并移动") {
                collectSelectedIntoFolder()
            }
        } message: {
            Text("将在当前目录新建文件夹，并把所选项目移动进去。")
        }
        .navigationDestination(item: $markdownNavigationTarget) { target in
            MarkdownEditorView(fileURL: URL(fileURLWithPath: target.id))
        }
        .navigationDestination(item: $singleListNavigationTarget) { target in
            SingleListDocumentEditorView(fileURL: URL(fileURLWithPath: target.id))
        }
        .navigationDestination(item: $autoFillNavigationTarget) { target in
            AutoFillDocumentEditorView(fileURL: URL(fileURLWithPath: target.id))
        }
        .navigationDestination(item: $checklistNavigationTarget) { target in
            ChecklistDocumentEditorView(fileURL: URL(fileURLWithPath: target.id))
        }
        .navigationDestination(item: $nodeMarkdownNavigationTarget) { target in
            NodeMarkdownEditorView(fileURL: URL(fileURLWithPath: target.id))
        }
        .sheet(isPresented: $showCreateFileSheet) {
            ArchiveCreateFileSheetView(
                onCancel: {
                    showCreateFileSheet = false
                },
                onCreate: { request in
                    createFile(request: request)
                }
            )
        }
        .sheet(isPresented: $showSmartCollectPreviewSheet) {
            smartCollectPreviewSheet
        }
        .sheet(isPresented: $showMovePicker) {
            if let archiveRootURL, let currentDirectoryURL {
                ArchiveFolderPickerView(
                    rootURL: archiveRootURL,
                    initialURL: currentDirectoryURL,
                    excludedURLs: moveTarget.map { [$0.url.standardizedFileURL] } ?? []
                ) {
                    showMovePicker = false
                    moveTarget = nil
                } onChoose: { targetURL in
                    showMovePicker = false
                    moveEntry(to: targetURL)
                }
            }
        }
        .sheet(isPresented: $showMultiMovePicker) {
            if let archiveRootURL, let currentDirectoryURL {
                ArchiveFolderPickerView(
                    rootURL: archiveRootURL,
                    initialURL: currentDirectoryURL,
                    excludedURLs: Set(selectedEntries.map { $0.url.standardizedFileURL })
                ) {
                    showMultiMovePicker = false
                } onChoose: { targetURL in
                    showMultiMovePicker = false
                    moveSelected(to: targetURL)
                }
            }
        }
        .onAppear {
            directoryWatcher.onChange = {
                refreshCurrentDirectory()
            }
            directoryWatcher.watch(currentDirectoryURL)
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        switch selectedPanel {
        case .archive:
            archivePanelContent
        case .templateManagement:
            TemplateManagementView(
                showTopActionToolbar: false,
                externalToggleMultiSelectToken: templateToggleMultiSelectTrigger,
                externalCreateToken: templateCreateTrigger
            )
        case .autoFill:
            AutoFillManagementView(showNavigationChrome: false, refreshTrigger: autoFillRefreshTrigger)
        case .smartCollect:
            smartCollectPanel
        case .recycleBin:
            RecycleBinView(
                onChanged: { refreshCurrentDirectory() },
                showNavigationChrome: false,
                refreshTrigger: recycleRefreshTrigger,
                clearAllTrigger: recycleClearAllTrigger
            )
        }
    }

    private var archivePanelContent: some View {
        VStack(spacing: 0) {
            headerBar

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 10)
            }

            if entries.isEmpty, !isLoading {
                ContentUnavailableView("档案为空", systemImage: "folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0,
                       entries[index - 1].isDirectory,
                       !entry.isDirectory {
                        Divider()
                    }
                    HStack(spacing: 10) {
                        if isMultiSelecting {
                            Image(systemName: selectedEntryIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(selectedEntryIDs.contains(entry.id) ? appHighlightBlue : .secondary)
                                .frame(width: 24, height: 24)
                        }
                        Image(systemName: entry.iconName)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(entry.isDirectory ? appHighlightBlue : entry.iconColor)
                            .frame(width: 36, height: 36, alignment: .center)
                        Text(entry.name)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer()
                        if entry.isDirectory {
                            Image(systemName: "chevron.right")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                                .frame(width: 24, alignment: .center)
                        }
                    }
                    .frame(minHeight: 44)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isMultiSelecting {
                            toggleSelection(entry)
                        } else {
                            openEntry(entry)
                        }
                    }
                    .contextMenu {
                        Button("改名") {
                            renameTarget = entry
                            renameName = entry.name
                            showRenameAlert = true
                        }
                        Button("删除", role: .destructive) {
                            deleteTarget = entry
                            showDeleteAlert = true
                        }
                        Button("移动") {
                            moveTarget = entry
                            showMovePicker = true
                        }
                    }
                }
                .listStyle(.plain)
            }

            if isMultiSelecting {
                multiSelectionBar
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private var topFeatureBar: some View {
        if usesCollapsedTopBar {
            HStack(spacing: 10) {
                compactFeatureMenu
                Spacer(minLength: 8)
                compactActionMenu
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
        } else {
            HStack(spacing: 10) {
                featureButton(title: "档案", systemImage: "folder", panel: .archive)
                featureButton(title: "模板管理", systemImage: "doc.on.doc", panel: .templateManagement)
                featureButton(title: "自动填写", systemImage: "wand.and.stars", panel: .autoFill)
                featureButton(title: "智能收集", systemImage: "sparkles", panel: .smartCollect)
                featureButton(title: "回收站", systemImage: "trash", panel: .recycleBin)
                Spacer()
                topActionButtons
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    private var compactFeatureMenu: some View {
        Menu {
            featureMenuButton(.archive)
            featureMenuButton(.templateManagement)
            featureMenuButton(.autoFill)
            featureMenuButton(.smartCollect)
            featureMenuButton(.recycleBin)
        } label: {
            Label(selectedPanel.title, systemImage: selectedPanel.systemImage)
                .lineLimit(1)
        }
        .appGlassButtonStyle(.prominent)
        .help("档案功能")
    }

    @ViewBuilder
    private func featureMenuButton(_ panel: FeaturePanel) -> some View {
        Button {
            selectFeaturePanel(panel)
        } label: {
            if selectedPanel == panel {
                Label(panel.title, systemImage: "checkmark")
            } else {
                Label(panel.title, systemImage: panel.systemImage)
            }
        }
    }

    private func selectFeaturePanel(_ panel: FeaturePanel) {
        selectedPanel = panel
        if panel == .smartCollect {
            runSmartCollectScan()
        }
    }

    private func featureButton(title: String, systemImage: String, panel: FeaturePanel) -> some View {
        Button {
            selectFeaturePanel(panel)
        } label: {
            actionLabel(title, systemImage: systemImage)
        }
        .appGlassButtonStyle(selectedPanel == panel ? .prominent : .regular)
        .help(title)
    }

    @ViewBuilder
    private var compactActionMenu: some View {
        Menu {
            switch selectedPanel {
            case .archive:
                Button("新建文件", systemImage: "doc.badge.plus") {
                    showCreateFileSheet = true
                }
                Button("新建文件夹", systemImage: "folder.badge.plus") {
                    newFolderName = ""
                    showCreateFolderAlert = true
                }
                Button(isMultiSelecting ? "完成多选" : "多选", systemImage: isMultiSelecting ? "checkmark.circle.fill" : "checklist") {
                    isMultiSelecting.toggle()
                    if !isMultiSelecting {
                        selectedEntryIDs.removeAll()
                    }
                }
                Button("刷新", systemImage: "arrow.clockwise") {
                    refreshCurrentDirectory()
                }
            case .templateManagement:
                Button("多选", systemImage: "checklist") {
                    templateToggleMultiSelectTrigger += 1
                }
                Button("新建模板", systemImage: "plus") {
                    templateCreateTrigger += 1
                }
            case .autoFill:
                Button("刷新", systemImage: "arrow.clockwise") {
                    autoFillRefreshTrigger += 1
                }
            case .smartCollect:
                Button("扫描", systemImage: "magnifyingglass") {
                    runSmartCollectScan()
                }
                .disabled(isLoading || isRunningSmartCollect)
                Button("整理", systemImage: "square.and.arrow.down.on.square") {
                    showSmartCollectPreview()
                }
                .disabled(isLoading || isRunningSmartCollect || smartCollectGroups.isEmpty)
            case .recycleBin:
                Button("刷新", systemImage: "arrow.clockwise") {
                    recycleRefreshTrigger += 1
                }
                Button("清空", systemImage: "trash.slash", role: .destructive) {
                    recycleClearAllTrigger += 1
                }
            }
        } label: {
            Label("操作", systemImage: "ellipsis.circle")
                .lineLimit(1)
        }
        .appGlassButtonStyle()
        .disabled(selectedPanel == .archive && currentDirectoryURL == nil)
        .help("当前页面操作")
    }

    @ViewBuilder
    private var topActionButtons: some View {
        switch selectedPanel {
        case .archive:
            ArchiveActionButtonsView(
                onCreateFile: {
                    showCreateFileSheet = true
                },
                onCreateFolder: {
                    newFolderName = ""
                    showCreateFolderAlert = true
                },
                onToggleMultiSelect: {
                    isMultiSelecting.toggle()
                    if !isMultiSelecting {
                        selectedEntryIDs.removeAll()
                    }
                },
                onRefresh: {
                    refreshCurrentDirectory()
                },
                isMultiSelecting: isMultiSelecting
            )
            .disabled(currentDirectoryURL == nil)
        case .templateManagement:
            Button {
                templateToggleMultiSelectTrigger += 1
            } label: {
                actionLabel("多选", systemImage: "checklist")
            }
            .appGlassButtonStyle()
            .help("多选")

            Button {
                templateCreateTrigger += 1
            } label: {
                actionLabel("新建", systemImage: "plus")
            }
            .appGlassButtonStyle()
            .help("新建模板")
        case .autoFill:
            Button {
                autoFillRefreshTrigger += 1
            } label: {
                actionLabel("刷新", systemImage: "arrow.clockwise")
            }
            .appGlassButtonStyle()
        case .smartCollect:
            Button {
                runSmartCollectScan()
            } label: {
                actionLabel("扫描", systemImage: "magnifyingglass")
            }
            .appGlassButtonStyle()
            .disabled(isLoading || isRunningSmartCollect)

            Button {
                showSmartCollectPreview()
            } label: {
                actionLabel("整理", systemImage: "square.and.arrow.down.on.square")
            }
            .appGlassButtonStyle()
            .disabled(isLoading || isRunningSmartCollect || smartCollectGroups.isEmpty)
        case .recycleBin:
            Button {
                recycleRefreshTrigger += 1
            } label: {
                actionLabel("刷新", systemImage: "arrow.clockwise")
            }
            .appGlassButtonStyle()

            Button(role: .destructive) {
                recycleClearAllTrigger += 1
            } label: {
                actionLabel("清空", systemImage: "trash.slash")
            }
            .appGlassButtonStyle(.danger)
        }
    }

    private var usesCompactIconOnlyButtons: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private var usesCollapsedTopBar: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact && verticalSizeClass == .regular
        #else
        false
        #endif
    }

    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String) -> some View {
        if usesCompactIconOnlyButtons {
            Image(systemName: systemImage)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Button {
                goUpOneLevel()
            } label: {
                Image(systemName: "chevron.left")
            }
            .appGlassButtonStyle()
            .disabled(!canGoUp)
            .help("返回上级")

            Text(breadcrumbTitle)
                .font(.title3)
                .fontWeight(.semibold)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var selectedEntries: [ArchiveEntry] {
        entries.filter { selectedEntryIDs.contains($0.id) }
    }

    private var multiSelectionBar: some View {
        HStack(spacing: 10) {
            Text("已选 \(selectedEntryIDs.count) 项")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
                showDeleteSelectedAlert = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            .appGlassButtonStyle(.danger)
            .disabled(selectedEntryIDs.isEmpty)

            Button {
                showMultiMovePicker = true
            } label: {
                Label("移动", systemImage: "folder")
            }
            .appGlassButtonStyle()
            .disabled(selectedEntryIDs.isEmpty)

            Button {
                collectSelectedFolderName = "新文件夹"
                showCollectSelectedFolderAlert = true
            } label: {
                Label("组成文件夹", systemImage: "folder.badge.plus")
            }
            .appGlassButtonStyle(.prominent)
            .disabled(selectedEntryIDs.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var smartCollectPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("智能收集")
                    .font(.headline)
                Spacer()
                if isRunningSmartCollect {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if smartCollectGroups.isEmpty {
                ContentUnavailableView(
                    "暂无可收集文件",
                    systemImage: "sparkles",
                    description: Text("点击右上角“扫描”检查当前目录。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(smartCollectGroups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Label("\(group.kind.title) · \(group.count)", systemImage: group.kind.iconName)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(group.fileNames.prefix(6).joined(separator: "、"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.secondary.opacity(0.08))
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var smartCollectPreviewSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("即将执行以下整理变更：\(smartCollectPreviewItems.count) 项")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                if smartCollectPreviewItems.isEmpty {
                    ContentUnavailableView(
                        "无可整理变更",
                        systemImage: "checkmark.circle",
                        description: Text("当前目录无需执行整理。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(smartCollectPreviewItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(item.sourceURL.lastPathComponent, systemImage: item.kind.iconName)
                                .font(.system(size: 14, weight: .semibold))
                            Text("→ \(item.destinationURL.deletingLastPathComponent().lastPathComponent)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("整理预览")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showSmartCollectPreviewSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认整理") {
                        showSmartCollectPreviewSheet = false
                        runSmartCollectOrganize(previewItems: smartCollectPreviewItems)
                    }
                    .disabled(smartCollectPreviewItems.isEmpty || isRunningSmartCollect)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private func runSmartCollectScan() {
        let files = entries.filter { !$0.isDirectory }
        let grouped = Dictionary(grouping: files) { smartCollectKind(for: $0) }
        smartCollectGroups = SmartCollectKind.allCases.compactMap { kind in
            guard let list = grouped[kind], !list.isEmpty else { return nil }
            let names = list
                .map(\.name)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            return SmartCollectGroup(kind: kind, fileNames: names)
        }
        statusMessage = smartCollectGroups.isEmpty
            ? "扫描完成：当前目录无可整理文件。"
            : "扫描完成：发现 \(files.count) 个文件，可按类型整理。"
    }

    private func showSmartCollectPreview() {
        guard let currentDirectoryURL else { return }
        let files = entries.filter { !$0.isDirectory }
        guard !files.isEmpty else {
            statusMessage = "当前目录没有可整理文件。"
            return
        }
        do {
            let previewItems = try makeSmartCollectPreview(files: files, in: currentDirectoryURL)
            smartCollectPreviewItems = previewItems
            if previewItems.isEmpty {
                statusMessage = "预览完成：无需整理。"
                return
            }
            showSmartCollectPreviewSheet = true
            statusMessage = "预览完成：共 \(previewItems.count) 项待整理。"
        } catch {
            statusMessage = "生成预览失败：\(error.localizedDescription)"
        }
    }

    private func runSmartCollectOrganize(previewItems: [SmartCollectMovePreview]) {
        guard !isRunningSmartCollect else { return }
        guard !previewItems.isEmpty else {
            statusMessage = "当前无可整理变更。"
            return
        }

        isRunningSmartCollect = true
        Task(priority: .userInitiated) {
            do {
                let movedCount = try applySmartCollectPreview(previewItems)
                isRunningSmartCollect = false
                statusMessage = "整理完成：已移动 \(movedCount) 个文件。"
                refreshCurrentDirectory()
            } catch {
                isRunningSmartCollect = false
                statusMessage = "整理失败：\(error.localizedDescription)"
            }
        }
    }

    private func makeSmartCollectPreview(files: [ArchiveEntry], in directoryURL: URL) throws -> [SmartCollectMovePreview] {
        let fileManager = FileManager.default
        var reservedPaths = Set<String>()
        var previewItems: [SmartCollectMovePreview] = []
        let sortedFiles = files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        for entry in sortedFiles {
            let kind = smartCollectKind(for: entry)
            let folderURL = directoryURL.appendingPathComponent(kind.folderName, isDirectory: true)
            let preferredURL = folderURL.appendingPathComponent(entry.name, isDirectory: false)
            let destinationURL = uniqueDestinationURL(
                preferredURL: preferredURL,
                fileManager: fileManager,
                reservedPaths: reservedPaths
            )
            guard destinationURL.path != entry.url.path else { continue }
            reservedPaths.insert(destinationURL.path)
            previewItems.append(
                SmartCollectMovePreview(
                    sourceURL: entry.url,
                    destinationURL: destinationURL,
                    kind: kind
                )
            )
        }
        return previewItems
    }

    private func applySmartCollectPreview(_ previewItems: [SmartCollectMovePreview]) throws -> Int {
        let fileManager = FileManager.default
        var movedCount = 0
        var reservedPaths = Set<String>()

        for item in previewItems {
            guard fileManager.fileExists(atPath: item.sourceURL.path) else { continue }
            let folderURL = item.destinationURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: folderURL.path) {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
            let destinationURL = uniqueDestinationURL(
                preferredURL: item.destinationURL,
                fileManager: fileManager,
                reservedPaths: reservedPaths
            )
            guard destinationURL.path != item.sourceURL.path else { continue }
            try fileManager.moveItem(at: item.sourceURL, to: destinationURL)
            reservedPaths.insert(destinationURL.path)
            movedCount += 1
        }

        return movedCount
    }

    private func uniqueDestinationURL(preferredURL: URL, fileManager: FileManager, reservedPaths: Set<String> = []) -> URL {
        if !fileManager.fileExists(atPath: preferredURL.path), !reservedPaths.contains(preferredURL.path) {
            return preferredURL
        }

        let ext = preferredURL.pathExtension
        let baseName = preferredURL.deletingPathExtension().lastPathComponent
        let folderURL = preferredURL.deletingLastPathComponent()
        var index = 2
        while true {
            let candidateName: String
            if ext.isEmpty {
                candidateName = "\(baseName)-\(index)"
            } else {
                candidateName = "\(baseName)-\(index).\(ext)"
            }
            let candidateURL = folderURL.appendingPathComponent(candidateName, isDirectory: false)
            if !fileManager.fileExists(atPath: candidateURL.path), !reservedPaths.contains(candidateURL.path) {
                return candidateURL
            }
            index += 1
        }
    }

    private func smartCollectKind(for entry: ArchiveEntry) -> SmartCollectKind {
        let ext = entry.url.pathExtension.lowercased()
        let metaType = (entry.metaType ?? "").lowercased()
        let lowerName = entry.name.lowercased()

        if ext == "nodemarkdown" || ext == "nmd" || metaType == "nodemarkdown" || metaType == "nodesmarkdown" || metaType == "lessonplan" {
            return .lessonPlan
        }
        if metaType == "checklist" || lowerName.contains("清单") || lowerName.contains("checklist") {
            return .checklist
        }
        if metaType == "singlelist" || metaType == "autosinglelist" || ext == "csv" {
            return .table
        }
        if ext == "md" {
            return .markdown
        }
        return .other
    }

    private var canGoUp: Bool {
        guard let root = archiveRootURL, let current = currentDirectoryURL else { return false }
        return current.standardizedFileURL.path != root.standardizedFileURL.path
    }

    private var breadcrumbTitle: String {
        guard let root = archiveRootURL, let current = currentDirectoryURL else {
            return "档案"
        }

        let rootPath = root.standardizedFileURL.path
        let currentPath = current.standardizedFileURL.path

        guard currentPath.hasPrefix(rootPath) else {
            return "档案"
        }

        let suffix = String(currentPath.dropFirst(rootPath.count))
        let segments = suffix
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        if segments.isEmpty {
            return "档案"
        }

        return "档案 / " + segments.joined(separator: " / ")
    }

    private func loadArchiveRoot() {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = ""

        Task(priority: .userInitiated) {
            let result: ArchiveLoadResult
            do {
                let payload = try ArchiveStorage.loadArchiveEntries()
                result = .initial(payload.0, payload.1)
            } catch {
                result = .failure(error.localizedDescription)
            }
            isLoading = false
            applyLoadResult(result)
        }
    }

    private func loadDirectory(_ directoryURL: URL) {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = ""

        Task(priority: .userInitiated) {
            let result: ArchiveLoadResult
            do {
                let loaded = try ArchiveStorage.loadEntries(in: directoryURL)
                result = .directory(directoryURL, loaded)
            } catch {
                result = .failure(error.localizedDescription)
            }
            isLoading = false
            applyLoadResult(result)
        }
    }

    private func applyLoadResult(_ result: ArchiveLoadResult) {
        switch result {
        case .initial(let rootURL, let loadedEntries):
            archiveRootURL = rootURL
            currentDirectoryURL = rootURL
            applyEntriesIfVisibleListChanged(loadedEntries)
            statusMessage = ""
        case .directory(let directoryURL, let loadedEntries):
            currentDirectoryURL = directoryURL
            applyEntriesIfVisibleListChanged(loadedEntries)
            statusMessage = ""
        case .failure(let message):
            statusMessage = message
        }
    }

    private func applyEntriesIfVisibleListChanged(_ loadedEntries: [ArchiveEntry]) {
        guard archiveVisibleSignature(entries) != archiveVisibleSignature(loadedEntries) else {
            return
        }
        entries = loadedEntries
    }

    private func archiveVisibleSignature(_ values: [ArchiveEntry]) -> [String] {
        values.map { entry in
            [
                entry.isDirectory ? "d" : "f",
                entry.url.standardizedFileURL.path,
                entry.name,
                entry.metaType ?? ""
            ].joined(separator: "|")
        }
    }

    private func refreshCurrentDirectory() {
        guard let currentDirectoryURL else {
            loadArchiveRoot()
            return
        }
        guard !isLoading, !isBackgroundRefreshing else { return }
        isBackgroundRefreshing = true
        Task(priority: .utility) {
            let result: ArchiveLoadResult
            do {
                result = .directory(
                    currentDirectoryURL,
                    try ArchiveStorage.loadEntries(in: currentDirectoryURL)
                )
            } catch {
                result = .failure(error.localizedDescription)
            }
            isBackgroundRefreshing = false
            guard self.currentDirectoryURL?.standardizedFileURL == currentDirectoryURL.standardizedFileURL else {
                return
            }
            applyLoadResult(result)
        }
    }

    private func toggleSelection(_ entry: ArchiveEntry) {
        if selectedEntryIDs.contains(entry.id) {
            selectedEntryIDs.remove(entry.id)
        } else {
            selectedEntryIDs.insert(entry.id)
        }
    }

    private func openEntry(_ entry: ArchiveEntry) {
        if entry.isDirectory {
            loadDirectory(entry.url)
            return
        }

        let fileExtension = entry.url.pathExtension.lowercased()
        let metaType = (ArchiveStorage.readMetaType(fileURL: entry.url) ?? "").lowercased()
        if fileExtension == "md" {
            #if os(macOS)
            openWindow(id: "markdown-editor", value: entry.url.path)
            #else
            markdownNavigationTarget = MarkdownNavigationTarget(id: entry.url.path)
            #endif
            return
        }

        if fileExtension == "csv", metaType == "singlelist" {
            singleListNavigationTarget = SingleListNavigationTarget(id: entry.url.path)
            return
        }

        if fileExtension == "csv", metaType == "autosinglelist" {
            autoFillNavigationTarget = AutoFillNavigationTarget(id: entry.url.path)
            return
        }

        if fileExtension == "csv", metaType == "checklist" {
            checklistNavigationTarget = ChecklistNavigationTarget(id: entry.url.path)
            return
        }

        if (fileExtension == "csv" && (metaType == "nodemarkdown" || metaType == "nodesmarkdown" || metaType == "lessonplan"))
            || fileExtension == "nodemarkdown"
            || fileExtension == "nmd" {
            #if os(macOS)
            openWindow(id: "nodemarkdown-editor", value: entry.url.path)
            #else
            nodeMarkdownNavigationTarget = NodeMarkdownNavigationTarget(id: entry.url.path)
            #endif
        }
    }

    private func goUpOneLevel() {
        guard canGoUp, let root = archiveRootURL, let current = currentDirectoryURL else { return }

        let parentURL = current.deletingLastPathComponent()
        if parentURL.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path) {
            loadDirectory(parentURL)
        }
    }

    private func createFolder() {
        guard let currentDirectoryURL else { return }
        let targetFolderName = newFolderName

        Task(priority: .userInitiated) {
            do {
                try ArchiveStorage.createFolder(named: targetFolderName, in: currentDirectoryURL)
                refreshCurrentDirectory()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func createFile(request: ArchiveCreateFileSheetView.CreateRequest) {
        guard let currentDirectoryURL else { return }
        Task(priority: .userInitiated) {
            do {
                if request.type == .singleListTable {
                    guard let templateURL = request.templateFileURL else { return }
                    let url = try ArchiveStorage.createSingleListDocument(
                        named: request.fileName,
                        templateFileURL: templateURL,
                        in: currentDirectoryURL
                    )
                    singleListNavigationTarget = SingleListNavigationTarget(id: url.path)
                } else if request.type == .autoFill {
                    guard let templateURL = request.templateFileURL else { return }
                    let url = try ArchiveStorage.createAutoFillDocument(
                        named: request.fileName,
                        templateFileURL: templateURL
                    )
                    autoFillNavigationTarget = AutoFillNavigationTarget(id: url.path)
                } else if request.type == .checklist {
                    guard let templateURL = request.templateFileURL else { return }
                    _ = try ArchiveStorage.createChecklistDocument(
                        named: request.fileName,
                        templateFileURL: templateURL,
                        in: currentDirectoryURL
                    )
                } else {
                    try ArchiveStorage.createFile(
                        named: request.fileName,
                        type: request.type,
                        in: currentDirectoryURL
                    )
                }
                showCreateFileSheet = false
                refreshCurrentDirectory()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func renameEntry() {
        guard let renameTarget else { return }
        let newName = renameName

        Task(priority: .userInitiated) {
            do {
                try ArchiveStorage.renameItem(at: renameTarget.url, to: newName)
                self.renameTarget = nil
                refreshCurrentDirectory()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func moveToRecycleBin() {
        guard let deleteTarget else { return }

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try RecycleBinManager.moveToRecycleBin(itemURL: deleteTarget.url)
                }.value
                self.deleteTarget = nil
                refreshCurrentDirectory()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func moveEntry(to targetDirectoryURL: URL) {
        guard let moveTarget else { return }
        Task(priority: .userInitiated) {
            do {
                _ = try ArchiveStorage.moveItem(at: moveTarget.url, to: targetDirectoryURL)
                self.moveTarget = nil
                statusMessage = "移动完成。"
                refreshCurrentDirectory()
            } catch {
                statusMessage = "移动失败：\(error.localizedDescription)"
            }
        }
    }

    private func moveSelected(to targetDirectoryURL: URL) {
        let urls = selectedEntries.map(\.url)
        guard !urls.isEmpty else { return }
        Task(priority: .userInitiated) {
            do {
                _ = try ArchiveStorage.moveItems(at: urls, to: targetDirectoryURL)
                selectedEntryIDs.removeAll()
                isMultiSelecting = false
                statusMessage = "移动完成：\(urls.count) 项。"
                refreshCurrentDirectory()
            } catch {
                statusMessage = "移动失败：\(error.localizedDescription)"
            }
        }
    }

    private func moveSelectedToRecycleBin() {
        let urls = selectedEntries.map(\.url)
        guard !urls.isEmpty else { return }
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    for url in urls {
                        try RecycleBinManager.moveToRecycleBin(itemURL: url)
                    }
                }.value
                selectedEntryIDs.removeAll()
                isMultiSelecting = false
                statusMessage = "删除完成：\(urls.count) 项已移入回收站。"
                refreshCurrentDirectory()
            } catch {
                statusMessage = "删除失败：\(error.localizedDescription)"
            }
        }
    }

    private func collectSelectedIntoFolder() {
        guard let currentDirectoryURL else { return }
        let urls = selectedEntries.map(\.url)
        guard !urls.isEmpty else { return }
        let folderName = collectSelectedFolderName
        Task(priority: .userInitiated) {
            do {
                try ArchiveStorage.createFolder(named: folderName, in: currentDirectoryURL)
                let folderURL = currentDirectoryURL.appendingPathComponent(folderName, isDirectory: true)
                _ = try ArchiveStorage.moveItems(at: urls, to: folderURL)
                selectedEntryIDs.removeAll()
                isMultiSelecting = false
                statusMessage = "已组成文件夹：\(folderName)。"
                refreshCurrentDirectory()
            } catch {
                statusMessage = "组成文件夹失败：\(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    ArchiveView()
}
