import SwiftUI

// MARK: - 教案管理页面 - v3 - 增加教案设置入口并保持最近访问目录记录
struct LessonPlanManagementView: View {
    let showRootBackButton: Bool
    let showTopActionButtons: Bool
    let externalCreateToken: Int
    let externalSettingsToken: Int

    init(
        showRootBackButton: Bool = true,
        showTopActionButtons: Bool = true,
        externalCreateToken: Int = 0,
        externalSettingsToken: Int = 0
    ) {
        self.showRootBackButton = showRootBackButton
        self.showTopActionButtons = showTopActionButtons
        self.externalCreateToken = externalCreateToken
        self.externalSettingsToken = externalSettingsToken
    }

    private struct NodeNavigationTarget: Identifiable, Hashable {
        let id: String
    }

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    @State private var rootURL: URL?
    @State private var currentDirectoryURL: URL?
    @State private var entries: [ArchiveEntry] = []
    @State private var isLoading = false
    @State private var statusMessage = ""

    @State private var showCreateLessonAlert = false
    @State private var lessonFolderName = ""
    @State private var showCreateChapterAlert = false
    @State private var chapterName = ""
    @State private var nodeNavigationTarget: NodeNavigationTarget?
    @State private var showLessonPlanSystemSettings = false
    @State private var renameTarget: ArchiveEntry?
    @State private var renameName = ""
    @State private var showRenameInput = false
    @State private var showRenameConfirmation = false
    @State private var deleteTarget: ArchiveEntry?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 10)
            }
            if entries.isEmpty, !isLoading {
                ContentUnavailableView("暂无教案", systemImage: "book.closed")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(entry.isDirectory ? appHighlightBlue : .orange)
                            .frame(width: 36, height: 36)
                        Text(entry.name)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if entry.isDirectory {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openEntry(entry)
                    }
                    .contextMenu {
                        Button("改名") {
                            beginRename(entry)
                        }
                        Button("删除", role: .destructive) {
                            deleteTarget = entry
                            showDeleteConfirmation = true
                        }
                    }
                }
                .listStyle(.plain)
            }
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle("教案")
        .task {
            if rootURL == nil && !isLoading {
                loadRoot()
            }
        }
        .alert("新建教案", isPresented: $showCreateLessonAlert) {
            TextField("教案名称", text: $lessonFolderName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                createLessonFolder()
            }
        } message: {
            Text("根目录仅支持新建教案文件夹。")
        }
        .alert("新建章教案", isPresented: $showCreateChapterAlert) {
            TextField("章教案文件名", text: $chapterName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                createChapter()
            }
        } message: {
            Text("将在当前教案目录下创建NodeMarkdown教案文件。")
        }
        .alert(renameInputTitle, isPresented: $showRenameInput) {
            TextField(renameInputPlaceholder, text: $renameName)
            Button("取消", role: .cancel) {
                renameTarget = nil
            }
            Button("下一步") {
                DispatchQueue.main.async {
                    showRenameConfirmation = true
                }
            }
        } message: {
            Text("填写新名称后，还需要再次确认关联影响。")
        }
        .alert("确认改名", isPresented: $showRenameConfirmation) {
            Button("取消", role: .cancel) {
                renameTarget = nil
            }
            Button("确认改名", role: .destructive) {
                renameLessonItem()
            }
        } message: {
            Text(renameImpactMessage)
        }
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {
                deleteTarget = nil
            }
            Button("确认删除", role: .destructive) {
                deleteLessonItem()
            }
        } message: {
            Text(deleteImpactMessage)
        }
        .navigationDestination(item: $nodeNavigationTarget) { target in
            NodeMarkdownEditorView(fileURL: URL(fileURLWithPath: target.id))
        }
        .sheet(isPresented: $showLessonPlanSystemSettings) {
            TeachingLessonPlanSystemSettingsView()
        }
        .onChange(of: externalCreateToken) { _, _ in
            guard !showTopActionButtons else { return }
            openCreatePrompt()
        }
        .onChange(of: externalSettingsToken) { _, _ in
            guard !showTopActionButtons else { return }
            showLessonPlanSystemSettings = true
        }
    }

    private var isAtRoot: Bool {
        guard let currentDirectoryURL else { return true }
        return LessonPlanStorage.isAtRoot(currentDirectoryURL)
    }

    private var canGoUp: Bool {
        !isAtRoot
    }

    private var canCreateLessonFolder: Bool {
        isAtRoot
    }

    private var canCreateChapter: Bool {
        guard let currentDirectoryURL else { return false }
        return LessonPlanStorage.directoryDepth(of: currentDirectoryURL) == 1
    }

    private var breadcrumbTitle: String {
        guard let rootURL, let currentDirectoryURL else { return "教案" }
        let rootPath = rootURL.standardizedFileURL.path
        let currentPath = currentDirectoryURL.standardizedFileURL.path
        guard currentPath.hasPrefix(rootPath) else { return "教案" }
        let suffix = String(currentPath.dropFirst(rootPath.count))
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        if suffix.isEmpty {
            return "教案"
        }
        return "教案 / \(suffix.joined(separator: " / "))"
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            if showRootBackButton || canGoUp {
                Button {
                    goUpOneLevel()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .appGlassButtonStyle()
                .disabled(!canGoUp)
            }

            Text(breadcrumbTitle)
                .font(.title3)
                .fontWeight(.semibold)

            Spacer()

            if showTopActionButtons {
                if canCreateLessonFolder {
                    Button {
                        lessonFolderName = ""
                        showCreateLessonAlert = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .appGlassButtonStyle(.prominent)
                    .help("新建教案")
                }

                if canCreateChapter {
                    Button {
                        chapterName = ""
                        showCreateChapterAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .appGlassButtonStyle(.prominent)
                    .help("新建章教案")
                }

                Button {
                    refreshCurrentDirectory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .appGlassButtonStyle()
                .help("刷新")

                Button {
                    showLessonPlanSystemSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .appGlassButtonStyle()
                .help("教案设置")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func loadRoot() {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = ""
        Task(priority: .userInitiated) {
            do {
                let payload = try LessonPlanStorage.loadRootEntries()
                rootURL = payload.0
                currentDirectoryURL = payload.0
                entries = payload.1
            } catch {
                statusMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func loadDirectory(_ directoryURL: URL) {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = ""
        Task(priority: .userInitiated) {
            do {
                entries = try LessonPlanStorage.loadEntries(in: directoryURL)
                currentDirectoryURL = directoryURL
            } catch {
                statusMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func refreshCurrentDirectory() {
        if let currentDirectoryURL {
            loadDirectory(currentDirectoryURL)
        } else {
            loadRoot()
        }
    }

    private func openEntry(_ entry: ArchiveEntry) {
        if entry.isDirectory {
            guard LessonPlanStorage.directoryDepth(of: entry.url) <= 1 else {
                statusMessage = "仅支持一级教案目录。"
                return
            }
            if LessonPlanStorage.directoryDepth(of: entry.url) == 1 {
                recordRecentLessonFolder(entry.url.lastPathComponent)
            }
            loadDirectory(entry.url)
            return
        }

        recordRecentLessonFolder(entry.url.deletingLastPathComponent().lastPathComponent)

        #if os(macOS)
        openWindow(id: "nodemarkdown-editor", value: entry.url.path)
        #else
        nodeNavigationTarget = NodeNavigationTarget(id: entry.url.path)
        #endif
    }

    private func goUpOneLevel() {
        guard let rootURL, let currentDirectoryURL else { return }
        if currentDirectoryURL.standardizedFileURL.path == rootURL.standardizedFileURL.path {
            return
        }
        let parent = currentDirectoryURL.deletingLastPathComponent()
        loadDirectory(parent)
    }

    private func createLessonFolder() {
        guard let currentDirectoryURL else { return }
        let name = lessonFolderName
        Task(priority: .userInitiated) {
            do {
                try LessonPlanStorage.createLessonFolder(named: name, in: currentDirectoryURL)
                refreshCurrentDirectory()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func createChapter() {
        guard let currentDirectoryURL else { return }
        let name = chapterName
        Task(priority: .userInitiated) {
            do {
                let fileURL = try LessonPlanStorage.createChapterFile(named: name, in: currentDirectoryURL)
                recordRecentLessonFolder(currentDirectoryURL.lastPathComponent)
                refreshCurrentDirectory()
                #if os(macOS)
                openWindow(id: "nodemarkdown-editor", value: fileURL.path)
                #else
                nodeNavigationTarget = NodeNavigationTarget(id: fileURL.path)
                #endif
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func beginRename(_ entry: ArchiveEntry) {
        renameTarget = entry
        renameName = entry.isDirectory
            ? entry.name
            : entry.url.deletingPathExtension().lastPathComponent
        showRenameInput = true
    }

    private func renameLessonItem() {
        guard let target = renameTarget else { return }
        let newName = renameName
        Task(priority: .userInitiated) {
            do {
                try LessonPlanStorage.renameItem(at: target.url, to: newName)
                renameTarget = nil
                statusMessage = target.isDirectory ? "教案改名完成。" : "章教案改名完成。"
                refreshCurrentDirectory()
            } catch {
                statusMessage = "改名失败：\(error.localizedDescription)"
            }
        }
    }

    private func deleteLessonItem() {
        guard let target = deleteTarget else { return }
        guard TeachingClassSessionCenter.shared.session == nil else {
            statusMessage = "正在上课或笔记中，不能删除教案。请先关闭当前会话。"
            deleteTarget = nil
            return
        }
        Task(priority: .userInitiated) {
            do {
                try LessonPlanStorage.deleteItem(at: target.url)
                deleteTarget = nil
                statusMessage = target.isDirectory ? "教案已移入回收站。" : "章教案已移入回收站。"
                refreshCurrentDirectory()
            } catch {
                statusMessage = "删除失败：\(error.localizedDescription)"
            }
        }
    }

    private var renameInputTitle: String {
        renameTarget?.isDirectory == true ? "教案改名" : "章教案改名"
    }

    private var renameInputPlaceholder: String {
        renameTarget?.isDirectory == true ? "教案名称" : "章教案名称"
    }

    private var renameImpactMessage: String {
        guard let target = renameTarget else { return "" }
        if target.isDirectory {
            return "改名整个教案会同步修改所有学生随堂笔记、完成清单、学生备份、教案模板、同步记录和图片链接。确认将“\(target.name)”改为“\(renameName)”？"
        }
        return "改名章教案会同步修改所有引用它的随堂笔记、完成清单、学生备份、同步记录、同名图片目录和图片链接。确认将“\(target.name)”改为“\(renameName)”？"
    }

    private var deleteImpactMessage: String {
        guard let target = deleteTarget else { return "" }
        if target.isDirectory {
            return "删除教案“\(target.name)”会把其中全部章教案和图片移入回收站；现有随堂笔记、完成清单和同步记录中的母本引用将失效。确认继续？"
        }
        return "删除章教案“\(target.name)”后，现有随堂笔记、完成清单和同步记录中指向它的母本引用将失效。文件将移入回收站。确认继续？"
    }

    private func openCreatePrompt() {
        if canCreateChapter {
            chapterName = ""
            showCreateChapterAlert = true
            return
        }
        if canCreateLessonFolder {
            lessonFolderName = ""
            showCreateLessonAlert = true
            return
        }
        statusMessage = "仅支持在根目录创建教案，或在一级教案目录创建章教案。"
    }

    private func recordRecentLessonFolder(_ folderID: String) {
        do {
            try TeachingStudentSettingsStore.recordRecentLessonPlanFolder(folderID)
        } catch {
            statusMessage = "最近教案记录失败：\(error.localizedDescription)"
        }
    }
}
