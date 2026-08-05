import SwiftUI
import Foundation

struct BackupManagementView: View {
    @State private var snapshots: [TeachingBackupSnapshotManifest] = []
    @State private var statusMessage = ""
    @State private var isRunningBackup = false
    @State private var backupProgress: TeachingBackupProgressSnapshot?
    @State private var manualBackupTask: Task<Void, Never>?
    @State private var backupProgressPollingTask: Task<Void, Never>?
    @State private var didLoad = false

    var body: some View {
        List {
            Section("操作") {
                if isRunningBackup {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: backupProgress?.fractionCompleted ?? 0)
                        Text(progressDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let currentPath = backupProgress?.currentRelativePath, !currentPath.isEmpty {
                            Text("当前文件：\(currentPath)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Button(role: .destructive) {
                            cancelManualBackup()
                        } label: {
                            Label("取消当前备份", systemImage: "xmark.circle")
                        }
                    }
                } else {
                    Button {
                        runManualBackup()
                    } label: {
                        Label("全量备份（马上执行）", systemImage: "externaldrive.badge.plus")
                    }
                    .disabled(isRunningBackup)
                }
            }

            Section("备份快照（最多100份）") {
                if snapshots.isEmpty {
                    Text("暂无备份")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshots) { snapshot in
                        NavigationLink {
                            BackupSnapshotDetailView(snapshot: snapshot)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Self.dateFormatter.string(from: snapshot.createdAt))
                                    .font(.body)
                                Text("\(snapshot.trigger.displayName) · 文件\(snapshot.fileCount) · 目录\(snapshot.directoryCount)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Text("体积 \(Self.byteFormatter.string(fromByteCount: snapshot.totalBytes)) · 耗时 \(Self.durationString(snapshot.durationSeconds))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            TeachingStatusMessageSection(message: statusMessage)
        }
        .navigationTitle("备份管理")
        .task {
            guard !didLoad else { return }
            didLoad = true
            reloadSnapshots()
        }
        .onDisappear {
            backupProgressPollingTask?.cancel()
        }
    }

    private var progressDescription: String {
        guard let backupProgress else {
            return "正在准备..."
        }
        return "\(backupProgress.phase) · \(backupProgress.completedFiles)/\(backupProgress.totalFiles)"
    }

    private func runManualBackup() {
        guard !isRunningBackup else { return }
        isRunningBackup = true
        statusMessage = ""
        backupProgress = TeachingBackupProgressSnapshot(
            phase: "准备备份",
            completedFiles: 0,
            totalFiles: 1,
            currentRelativePath: nil
        )
        startBackupProgressPolling()

        manualBackupTask = Task {
            do {
                _ = try await TeachingBackupService.shared.performFullBackup(trigger: .manualFull)
                await MainActor.run {
                    finishManualBackup()
                    statusMessage = "全量备份完成。"
                    reloadSnapshots()
                }
            } catch is CancellationError {
                await MainActor.run {
                    finishManualBackup()
                    statusMessage = "备份已取消。"
                }
            } catch {
                await MainActor.run {
                    finishManualBackup()
                    statusMessage = "备份失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func cancelManualBackup() {
        manualBackupTask?.cancel()
        statusMessage = "正在取消备份..."
    }

    private func finishManualBackup() {
        isRunningBackup = false
        manualBackupTask = nil
        backupProgress = nil
        backupProgressPollingTask?.cancel()
        backupProgressPollingTask = nil
    }

    private func startBackupProgressPolling() {
        backupProgressPollingTask?.cancel()
        backupProgressPollingTask = Task {
            while !Task.isCancelled {
                let snapshot = await TeachingBackupService.shared.currentBackupProgress()
                await MainActor.run {
                    if isRunningBackup {
                        backupProgress = snapshot ?? backupProgress
                    }
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    private func reloadSnapshots() {
        Task {
            do {
                let loaded = try await TeachingBackupService.shared.listSnapshots()
                await MainActor.run {
                    snapshots = loaded
                }
            } catch {
                await MainActor.run {
                    statusMessage = "加载备份失败：\(error.localizedDescription)"
                }
            }
        }
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    static func durationString(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return "<1s"
        }
        return String(format: "%.1fs", seconds)
    }
}

private struct BackupSnapshotDetailView: View {
    let snapshot: TeachingBackupSnapshotManifest

    @State private var treeNodes: [BackupSnapshotTreeNode] = []
    @State private var expandedPaths: Set<String> = []
    @State private var selectedPaths: Set<String> = []
    @State private var fullDiff: TeachingBackupDiffSummary?
    @State private var partialDiff: TeachingBackupDiffSummary?
    @State private var statusMessage = ""
    @State private var isRestoringFull = false
    @State private var isRestoringPartial = false
    @State private var restoreProgress: TeachingBackupProgressSnapshot?
    @State private var restoreTask: Task<Void, Never>?
    @State private var restoreProgressPollingTask: Task<Void, Never>?
    @State private var isLoadingDiff = false
    @State private var diffSearchText = ""
    @State private var diffFilter: BackupDiffFilter = .all
    @State private var expandedFullDiffPaths: Set<String> = []
    @State private var expandedPartialDiffPaths: Set<String> = []
    @State private var partialRestoreStrategy: TeachingBackupRestoreConflictStrategy = .overwrite
    @State private var showFullRestoreConfirm = false
    @State private var didLoad = false

    var body: some View {
        List {
            Section("快照信息") {
                Text("时间：\(BackupManagementView.dateFormatter.string(from: snapshot.createdAt))")
                Text("来源：\(snapshot.trigger.displayName)")
                Text("文件：\(snapshot.fileCount) 目录：\(snapshot.directoryCount)")
                Text("体积：\(BackupManagementView.byteFormatter.string(fromByteCount: snapshot.totalBytes))")
                Text("耗时：\(BackupManagementView.durationString(snapshot.durationSeconds))")
                Text("校验文件：\(snapshot.checksummedFileCount)")
            }

            Section("恢复操作") {
                Picker("冲突策略", selection: $partialRestoreStrategy) {
                    ForEach(TeachingBackupRestoreConflictStrategy.allCases) { strategy in
                        Text(strategy.displayName).tag(strategy)
                    }
                }
                .pickerStyle(.segmented)

                if isRestoringFull || isRestoringPartial {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: restoreProgress?.fractionCompleted ?? 0)
                        Text(restoreProgressDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let currentPath = restoreProgress?.currentRelativePath, !currentPath.isEmpty {
                            Text("当前文件：\(currentPath)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Button(role: .destructive) {
                            cancelRestoreTask()
                        } label: {
                            Label("取消当前恢复", systemImage: "xmark.circle")
                        }
                    }
                } else {
                    Button(role: .destructive) {
                        showFullRestoreConfirm = true
                    } label: {
                        Label("全量恢复", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRestoringFull || isRestoringPartial)

                    Button {
                        runPartialRestore()
                    } label: {
                        Label("部分恢复（已选\(selectedPaths.count)项）", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(selectedPaths.isEmpty || isRestoringFull || isRestoringPartial)
                }
            }

            Section("内容浏览（树形，可展开）") {
                if treeNodes.isEmpty {
                    Text("此快照为空")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(treeNodes) { node in
                        BackupSnapshotTreeRow(
                            node: node,
                            selectedPaths: $selectedPaths,
                            expandedPaths: $expandedPaths
                        )
                    }
                }
            }

            Section("恢复前差异预览") {
                if isLoadingDiff {
                    ProgressView()
                } else {
                    TextField("搜索路径", text: $diffSearchText)
                        .textFieldStyle(.roundedBorder)

                    Picker("类型过滤", selection: $diffFilter) {
                        ForEach(BackupDiffFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    diffPreviewGroup(
                        title: "全量恢复预览",
                        summary: fullDiff,
                        nodes: fullDiffTreeNodes,
                        expandedPaths: $expandedFullDiffPaths,
                        searchText: diffSearchText,
                        emptyText: "此快照与当前工作区没有差异。"
                    )

                    diffPreviewGroup(
                        title: "部分恢复预览",
                        summary: partialDiff,
                        nodes: partialDiffTreeNodes,
                        expandedPaths: $expandedPartialDiffPaths,
                        searchText: diffSearchText,
                        emptyText: selectedPaths.isEmpty ? "请先在上方勾选文件或目录。" : "当前筛选条件下无差异。"
                    )
                }
            }

            TeachingStatusMessageSection(message: statusMessage)
        }
        .navigationTitle("备份内容")
        .task {
            guard !didLoad else { return }
            didLoad = true
            loadItemsAndDiff()
        }
        .onChange(of: diffSearchText) {
            syncDiffExpansionPaths()
        }
        .onChange(of: diffFilter) {
            syncDiffExpansionPaths()
        }
        .onChange(of: fullDiff) {
            syncDiffExpansionPaths()
        }
        .onChange(of: partialDiff) {
            syncDiffExpansionPaths()
        }
        .onChange(of: selectedPaths) {
            refreshPartialDiff()
        }
        .alert("确认全量恢复", isPresented: $showFullRestoreConfirm) {
            Button("取消", role: .cancel) {}
            Button("恢复", role: .destructive) {
                runFullRestore()
            }
        } message: {
            Text("将覆盖 iCloud 根目录内部所有内容，是否继续？")
        }
        .onDisappear {
            restoreProgressPollingTask?.cancel()
        }
    }

    private var fullDiffTreeNodes: [BackupDiffTreeNode] {
        BackupDiffTreeNode.build(from: fullDiff, filter: diffFilter, searchText: diffSearchText)
    }

    private var partialDiffTreeNodes: [BackupDiffTreeNode] {
        BackupDiffTreeNode.build(from: partialDiff, filter: diffFilter, searchText: diffSearchText)
    }

    @ViewBuilder
    private func diffPreviewGroup(
        title: String,
        summary: TeachingBackupDiffSummary?,
        nodes: [BackupDiffTreeNode],
        expandedPaths: Binding<Set<String>>,
        searchText: String,
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !nodes.isEmpty {
                    Button("展开") {
                        expandedPaths.wrappedValue = Set(BackupDiffTreeNode.directoryPaths(from: nodes))
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    Button("收起") {
                        expandedPaths.wrappedValue.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            if let summary {
                Text("新增 \(summary.createCount) · 覆盖 \(summary.overwriteCount) · 删除 \(summary.deleteCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("暂无数据")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if nodes.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                Text("当前结果：\(BackupDiffTreeNode.leafCount(from: nodes)) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(nodes) { node in
                    BackupDiffTreeRow(
                        node: node,
                        expandedPaths: expandedPaths,
                        searchText: searchText
                    )
                }
            }
        }
    }

    private func loadItemsAndDiff() {
        isLoadingDiff = true
        Task {
            do {
                let loaded = try await TeachingBackupService.shared.listSnapshotItems(snapshotID: snapshot.id)
                let full = try await TeachingBackupService.shared.previewFullRestoreDiff(snapshotID: snapshot.id)
                await MainActor.run {
                    treeNodes = BackupSnapshotTreeNode.buildTree(from: loaded)
                    expandedPaths = Set(treeNodes.filter { $0.isDirectory }.map(\.relativePath))
                    fullDiff = full
                    partialDiff = nil
                    syncDiffExpansionPaths()
                    isLoadingDiff = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = "加载快照内容失败：\(error.localizedDescription)"
                    isLoadingDiff = false
                }
            }
        }
    }

    private func refreshPartialDiff() {
        guard !selectedPaths.isEmpty else {
            partialDiff = nil
            return
        }
        isLoadingDiff = true
        let selected = Array(selectedPaths)
        Task {
            do {
                let diff = try await TeachingBackupService.shared.previewPartialRestoreDiff(
                    snapshotID: snapshot.id,
                    relativePaths: selected
                )
                await MainActor.run {
                    partialDiff = diff
                    syncDiffExpansionPaths()
                    isLoadingDiff = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = "部分恢复预览失败：\(error.localizedDescription)"
                    isLoadingDiff = false
                }
            }
        }
    }

    private func runFullRestore() {
        isRestoringFull = true
        statusMessage = ""
        restoreProgress = TeachingBackupProgressSnapshot(
            phase: "准备恢复",
            completedFiles: 0,
            totalFiles: 1,
            currentRelativePath: nil
        )
        startRestoreProgressPolling()
        restoreTask = Task {
            do {
                try await TeachingBackupService.shared.restoreFull(snapshotID: snapshot.id)
                let refreshedFull = try await TeachingBackupService.shared.previewFullRestoreDiff(snapshotID: snapshot.id)
                await MainActor.run {
                    finishRestoreTask()
                    statusMessage = "全量恢复完成。"
                    fullDiff = refreshedFull
                    partialDiff = nil
                    selectedPaths.removeAll()
                    syncDiffExpansionPaths()
                }
            } catch is CancellationError {
                await MainActor.run {
                    finishRestoreTask()
                    statusMessage = "恢复已取消。"
                }
            } catch {
                await MainActor.run {
                    finishRestoreTask()
                    statusMessage = "全量恢复失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func runPartialRestore() {
        isRestoringPartial = true
        statusMessage = ""
        let paths = Array(selectedPaths)
        let strategy = partialRestoreStrategy
        restoreProgress = TeachingBackupProgressSnapshot(
            phase: "准备恢复",
            completedFiles: 0,
            totalFiles: 1,
            currentRelativePath: nil
        )
        startRestoreProgressPolling()
        restoreTask = Task {
            do {
                try await TeachingBackupService.shared.restorePartial(
                    snapshotID: snapshot.id,
                    relativePaths: paths,
                    strategy: strategy
                )
                let refreshedFull = try await TeachingBackupService.shared.previewFullRestoreDiff(snapshotID: snapshot.id)
                let refreshedPartial = try await TeachingBackupService.shared.previewPartialRestoreDiff(
                    snapshotID: snapshot.id,
                    relativePaths: paths
                )
                await MainActor.run {
                    finishRestoreTask()
                    statusMessage = "部分恢复完成。"
                    fullDiff = refreshedFull
                    partialDiff = refreshedPartial
                    syncDiffExpansionPaths()
                }
            } catch is CancellationError {
                await MainActor.run {
                    finishRestoreTask()
                    statusMessage = "恢复已取消。"
                }
            } catch {
                await MainActor.run {
                    finishRestoreTask()
                    statusMessage = "部分恢复失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func syncDiffExpansionPaths() {
        expandedFullDiffPaths = Set(BackupDiffTreeNode.directoryPaths(from: fullDiffTreeNodes))
        expandedPartialDiffPaths = Set(BackupDiffTreeNode.directoryPaths(from: partialDiffTreeNodes))
    }

    private var restoreProgressDescription: String {
        guard let restoreProgress else {
            return "正在准备..."
        }
        return "\(restoreProgress.phase) · \(restoreProgress.completedFiles)/\(restoreProgress.totalFiles)"
    }

    private func startRestoreProgressPolling() {
        restoreProgressPollingTask?.cancel()
        restoreProgressPollingTask = Task {
            while !Task.isCancelled {
                let snapshot = await TeachingBackupService.shared.currentBackupProgress()
                await MainActor.run {
                    if isRestoringFull || isRestoringPartial {
                        restoreProgress = snapshot ?? restoreProgress
                    }
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    private func cancelRestoreTask() {
        restoreTask?.cancel()
        statusMessage = "正在取消恢复..."
    }

    private func finishRestoreTask() {
        isRestoringFull = false
        isRestoringPartial = false
        restoreTask = nil
        restoreProgress = nil
        restoreProgressPollingTask?.cancel()
        restoreProgressPollingTask = nil
    }
}

private enum BackupDiffFilter: String, CaseIterable, Identifiable {
    case all
    case create
    case overwrite
    case delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .create:
            return "新增"
        case .overwrite:
            return "覆盖"
        case .delete:
            return "删除"
        }
    }

    func contains(_ kind: BackupDiffKind) -> Bool {
        switch self {
        case .all:
            return true
        case .create:
            return kind == .create
        case .overwrite:
            return kind == .overwrite
        case .delete:
            return kind == .delete
        }
    }
}

private enum BackupDiffKind: Hashable {
    case create
    case overwrite
    case delete

    var icon: String {
        switch self {
        case .create:
            return "plus.circle.fill"
        case .overwrite:
            return "pencil.circle.fill"
        case .delete:
            return "trash.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .create:
            return .green
        case .overwrite:
            return .orange
        case .delete:
            return .red
        }
    }
}

private struct BackupDiffTreeNode: Identifiable, Hashable {
    let relativePath: String
    let name: String
    let kind: BackupDiffKind?
    var children: [BackupDiffTreeNode]

    var id: String { relativePath }
    var isDirectory: Bool { !children.isEmpty }

    static func build(
        from summary: TeachingBackupDiffSummary?,
        filter: BackupDiffFilter,
        searchText: String
    ) -> [BackupDiffTreeNode] {
        guard let summary else { return [] }
        var entries: [(String, BackupDiffKind)] = []
        entries.append(contentsOf: summary.createPaths.map { ($0, .create) })
        entries.append(contentsOf: summary.overwritePaths.map { ($0, .overwrite) })
        entries.append(contentsOf: summary.deletePaths.map { ($0, .delete) })

        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        entries = entries.filter { path, kind in
            guard filter.contains(kind) else { return false }
            if keyword.isEmpty { return true }
            return path.localizedCaseInsensitiveContains(keyword)
        }

        var root = BackupDiffTreeBuilder(path: "", name: "", kind: nil)
        for (path, kind) in entries {
            root.insert(path: path, kind: kind)
        }
        return root.children.values
            .map { $0.makeNode() }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    static func directoryPaths(from nodes: [BackupDiffTreeNode]) -> [String] {
        var result: [String] = []
        for node in nodes {
            if node.isDirectory {
                result.append(node.relativePath)
                result.append(contentsOf: directoryPaths(from: node.children))
            }
        }
        return result
    }

    static func leafCount(from nodes: [BackupDiffTreeNode]) -> Int {
        nodes.reduce(0) { partial, node in
            if node.isDirectory {
                return partial + leafCount(from: node.children)
            }
            return partial + 1
        }
    }
}

private struct BackupDiffTreeBuilder {
    var path: String
    var name: String
    var kind: BackupDiffKind?
    var children: [String: BackupDiffTreeBuilder] = [:]

    mutating func insert(path: String, kind: BackupDiffKind) {
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return }
        insert(components: components, kind: kind)
    }

    private mutating func insert(components: [String], kind: BackupDiffKind) {
        guard let first = components.first else { return }
        let childPath = path.isEmpty ? first : path + "/" + first
        var child = children[first] ?? BackupDiffTreeBuilder(path: childPath, name: first, kind: nil)
        if components.count == 1 {
            child.kind = kind
        } else {
            child.insert(components: Array(components.dropFirst()), kind: kind)
        }
        children[first] = child
    }

    func makeNode() -> BackupDiffTreeNode {
        let childNodes = children.values
            .map { $0.makeNode() }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        return BackupDiffTreeNode(
            relativePath: path,
            name: name,
            kind: kind,
            children: childNodes
        )
    }
}

private struct BackupDiffTreeRow: View {
    let node: BackupDiffTreeNode
    let expandedPaths: Binding<Set<String>>
    let searchText: String

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: expandedBinding) {
                ForEach(node.children) { child in
                    BackupDiffTreeRow(
                        node: child,
                        expandedPaths: expandedPaths,
                        searchText: searchText
                    )
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.secondary)
                    highlightedText(node.name, keyword: searchText)
                        .font(.system(size: 13))
                        .lineLimit(1)
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: node.kind?.icon ?? "doc")
                    .foregroundStyle(node.kind?.color ?? .secondary)
                highlightedText(node.name, keyword: searchText)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer()
                highlightedText(node.relativePath, keyword: searchText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 20)
        }
    }

    private var expandedBinding: Binding<Bool> {
        Binding(
            get: { expandedPaths.wrappedValue.contains(node.relativePath) },
            set: { expanded in
                if expanded {
                    expandedPaths.wrappedValue.insert(node.relativePath)
                } else {
                    expandedPaths.wrappedValue.remove(node.relativePath)
                }
            }
        )
    }

    private func highlightedText(_ text: String, keyword: String) -> Text {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Text(text) }
        var attributed = AttributedString(text)
        let nsText = text as NSString
        var searchRange = NSRange(location: 0, length: nsText.length)
        while true {
            let found = nsText.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )
            guard found.location != NSNotFound else { break }
            if let stringRange = Range(found, in: text),
               let attributedRange = Range<AttributedString.Index>(stringRange, in: attributed) {
                attributed[attributedRange].foregroundColor = .orange
                attributed[attributedRange].font = .body.bold()
            }
            let nextLocation = found.location + found.length
            guard nextLocation < nsText.length else { break }
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }
        return Text(attributed)
    }
}

private struct BackupSnapshotTreeNode: Identifiable, Hashable {
    let relativePath: String
    let name: String
    let isDirectory: Bool
    var children: [BackupSnapshotTreeNode]

    var id: String { relativePath }

    static func buildTree(from items: [TeachingBackupSnapshotItem]) -> [BackupSnapshotTreeNode] {
        var root = BackupSnapshotTreeBuilder(path: "", name: "", isDirectory: true)
        for item in items {
            let components = item.relativePath.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            root.insert(components: components, isDirectory: item.isDirectory)
        }
        return root.children.values
            .map { $0.makeNode() }
            .sorted {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory && !$1.isDirectory
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }
}

private struct BackupSnapshotTreeBuilder {
    var path: String
    var name: String
    var isDirectory: Bool
    var children: [String: BackupSnapshotTreeBuilder] = [:]

    mutating func insert(components: [String], isDirectory: Bool) {
        guard let first = components.first else { return }
        let childPath = path.isEmpty ? first : path + "/" + first
        var child = children[first] ?? BackupSnapshotTreeBuilder(
            path: childPath,
            name: first,
            isDirectory: components.count > 1
        )
        if components.count == 1 {
            child.isDirectory = isDirectory
        } else {
            child.isDirectory = true
            child.insert(components: Array(components.dropFirst()), isDirectory: isDirectory)
        }
        children[first] = child
    }

    func makeNode() -> BackupSnapshotTreeNode {
        let childrenNodes = children.values
            .map { $0.makeNode() }
            .sorted {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory && !$1.isDirectory
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        return BackupSnapshotTreeNode(
            relativePath: path,
            name: name,
            isDirectory: isDirectory,
            children: childrenNodes
        )
    }
}

private struct BackupSnapshotTreeRow: View {
    let node: BackupSnapshotTreeNode
    @Binding var selectedPaths: Set<String>
    @Binding var expandedPaths: Set<String>

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: expandedBinding) {
                ForEach(node.children) { child in
                    BackupSnapshotTreeRow(
                        node: child,
                        selectedPaths: $selectedPaths,
                        expandedPaths: $expandedPaths
                    )
                }
            } label: {
                rowLabel
            }
        } else {
            rowLabel
                .padding(.leading, 20)
        }
    }

    private var expandedBinding: Binding<Bool> {
        Binding(
            get: { expandedPaths.contains(node.relativePath) },
            set: { expanded in
                if expanded {
                    expandedPaths.insert(node.relativePath)
                } else {
                    expandedPaths.remove(node.relativePath)
                }
            }
        )
    }

    private var rowLabel: some View {
        HStack(spacing: 8) {
            Button {
                toggleSelection()
            } label: {
                Image(systemName: selectedPaths.contains(node.relativePath) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedPaths.contains(node.relativePath) ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(node.name)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer()
            Image(systemName: node.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(.secondary)
        }
    }

    private func toggleSelection() {
        if selectedPaths.contains(node.relativePath) {
            selectedPaths.remove(node.relativePath)
        } else {
            selectedPaths.insert(node.relativePath)
        }
    }
}
