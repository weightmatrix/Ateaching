import SwiftUI
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Notification.Name {
    static let teachingCloudFileChanged = Notification.Name("TeachingCloudFileChanged")
}

@MainActor
final class TeachingCloudSyncStatus: NSObject, ObservableObject {
    static let shared = TeachingCloudSyncStatus()
    @Published private(set) var message = "尚未检查 iCloud"
    @Published private(set) var checkedAt: Date?
    @Published private(set) var isChecking = false
    @Published private(set) var files: [String] = []
    private var query: NSMetadataQuery?
    private var fingerprints: [String: String] = [:]
    private var requestedDownloads: Set<String> = []
    private var timeout: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?

    func start() {
        guard foregroundObserver == nil else { return }
        #if os(macOS)
        let event = NSApplication.didBecomeActiveNotification
        #else
        let event = UIApplication.willEnterForegroundNotification
        #endif
        foregroundObserver = NotificationCenter.default.addObserver(forName: event, object: nil, queue: .main) { _ in
            Task { @MainActor in TeachingCloudSyncStatus.shared.check() }
        }
        check()
    }

    func check() {
        guard !isChecking else { return }
        isChecking = true
        requestedDownloads.removeAll()
        message = "正在检查本机 iCloud 文件状态…"
        Task {
            do {
                let root = try await Task.detached(priority: .utility) { try ArchiveStorage.ensureWorkspace() }.value
                if query == nil {
                    let q = NSMetadataQuery()
                    q.searchScopes = [root]
                    q.predicate = NSCompoundPredicate(orPredicateWithSubpredicates:
                        ["*.json", "*.csv", "*.md", "*.markdown", "setting-students"].map {
                            NSPredicate(format: "%K LIKE[c] %@", NSMetadataItemFSNameKey, $0)
                        })
                    NotificationCenter.default.addObserver(self, selector: #selector(updated), name: .NSMetadataQueryDidFinishGathering, object: q)
                    NotificationCenter.default.addObserver(self, selector: #selector(updated), name: .NSMetadataQueryDidUpdate, object: q)
                    query = q
                    guard q.start() else { query = nil; throw TeachingCloudFileAccess.AccessError.coordination }
                } else { inspect(requestDownload: true) }
                timeout?.cancel()
                timeout = Task {
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled, self.isChecking else { return }
                    self.message = "检查超时，尚未确认文件下载完成；不能确认其他设备最新修改已到达。"
                    self.checkedAt = Date()
                    self.isChecking = false
                }
            } catch {
                message = "iCloud 检查失败：\(error.localizedDescription)"
                checkedAt = Date()
                isChecking = false
            }
        }
    }

    @objc private func updated(_ notification: Notification) { inspect(requestDownload: isChecking) }

    private func inspect(requestDownload: Bool) {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        var pending = 0, uploading = 0, uploaded = 0, errors: [String] = [], details: [String] = []
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let name = url.lastPathComponent
            // Only editable business data; skip images, export PDFs and backup packages.
            guard ["json", "csv", "md", "markdown"].contains(url.pathExtension.lowercased()) || name == "setting-students" else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let error = (item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) as? NSError)
                ?? (item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError)
            if let error { errors.append("\(name)：\(error.localizedDescription)") }
            if status != NSMetadataUbiquitousItemDownloadingStatusCurrent { pending += 1 }
            if requestDownload && requestedDownloads.insert(url.path).inserted {
                do { try FileManager.default.startDownloadingUbiquitousItem(at: url) }
                catch { errors.append("\(name)：\(error.localizedDescription)") }
            }
            let isUploaded = (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? NSNumber)?.boolValue == true
            if isUploaded { uploaded += 1 }
            else { uploading += 1 }
            let date = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
            let fingerprint = "\(date?.timeIntervalSince1970 ?? 0)|\(status ?? "unknown")|\(String(describing: item.value(forAttribute: NSMetadataItemFSSizeKey)))"
            let previous = fingerprints.updateValue(fingerprint, forKey: url.path)
            if previous != fingerprint && status == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                NotificationCenter.default.post(name: .teachingCloudFileChanged, object: nil, userInfo: ["filePath": url.path])
            }
            details.append("\(name)：\(status == NSMetadataUbiquitousItemDownloadingStatusCurrent ? "本机当前" : "待下载")，\(isUploaded ? "iCloud 标记已上传" : "尚未确认上传")")
        }
        files = details.sorted()
        checkedAt = Date()
        if !errors.isEmpty {
            message = errors.prefix(5).joined(separator: "\n")
            isChecking = false
        } else if pending > 0 {
            message = "等待下载 \(pending) 个文件；尚未确认上传 \(uploading) 个。"
        } else {
            message = "本机可读文件 \(details.count) 个；iCloud 标记已上传 \(uploaded) 个，尚未确认上传 \(uploading) 个。此状态不能证明其他设备最新修改已到达。"
            isChecking = false
        }
        if !isChecking { timeout?.cancel() }
    }
}

struct TeachingCloudSyncSettingsView: View {
    @ObservedObject private var status = TeachingCloudSyncStatus.shared
    @State private var recoveryFiles: [URL] = []
    @State private var recoveryError = ""
    @State private var conflictReport: TeachingCloudConflictReport?
    @State private var conflictMessage = ""
    @State private var isResolvingConflict = false
    @State private var showKeepCurrentConfirmation = false
    var body: some View {
        List {
            Section("iCloud 文件检查") {
                Text(status.message).textSelection(.enabled)
                if let date = status.checkedAt { Text("最近检查：\(date.formatted())").font(.footnote) }
                Button(status.isChecking ? "检查中…" : "立即检查并请求下载") { status.check() }.disabled(status.isChecking)
                Text("保存成功表示文件已写入本机 iCloud 目录，不表示另一设备已经收到。文件版本发生变化时停止覆盖，请先导出恢复副本再重新打开原文件核对。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("学生设置历史冲突") {
                Button("检查学生设置版本") { loadStudentConflicts() }.disabled(isResolvingConflict)
                if let report = conflictReport {
                    Text("当前文件：\(report.current.studentCount.map(String.init) ?? "未知")位学生；保存时间：\(report.current.savedAt)")
                    Text("未解决历史版本：\(report.conflicts.count)份")
                    ForEach(Array(report.conflicts.enumerated()), id: \.offset) { index, version in
                        Text("版本\(index + 1)：\(version.studentCount.map(String.init) ?? "未知")位学生；\(version.savedAt)").font(.footnote)
                    }
                    if !report.conflicts.isEmpty {
                        Button("保留当前设置并解除历史冲突") { showKeepCurrentConfirmation = true }
                            .disabled(isResolvingConflict)
                        Text("不会按时间或人数自动选择版本。确认后先在本机保留全部版本副本，再解除历史冲突；当前文件内容不变。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !conflictMessage.isEmpty { Text(conflictMessage).font(.footnote).textSelection(.enabled) }
            }
            Section("文件状态") { ForEach(status.files, id: \.self) { Text($0).font(.footnote) } }
            Section("本机恢复副本") {
                Text("pending 为未保存到原位置的编辑；history 为覆盖前版本。分享副本后可在档案中另存、核对，不自动覆盖原文件。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("刷新恢复副本") { loadRecovery() }
                if !recoveryError.isEmpty { Text(recoveryError).foregroundStyle(.red) }
                ForEach(recoveryFiles, id: \.path) { url in ShareLink(item: url) { Text(url.lastPathComponent).lineLimit(2) } }
            }
        }
        .navigationTitle("iCloud 同步与恢复")
        .task { status.start(); loadRecovery(); loadStudentConflicts() }
        .confirmationDialog("保留当前学生设置？", isPresented: $showKeepCurrentConfirmation, titleVisibility: .visible) {
            Button("备份全部版本并保留当前设置") { keepCurrentStudentSettings() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("当前文件含\(conflictReport?.current.studentCount ?? 0)位学生。历史冲突版本将全部保留为本机恢复副本，之后可在下方刷新并分享。不会合并历史版本里的字段。")
        }
    }
    private func loadStudentConflicts() {
        Task {
            do {
                let report = try await Task.detached(priority: .utility) {
                    // Validate the current business snapshot before offering to keep it.
                    _ = try TeachingStudentSettingsStore.loadSnapshot()
                    return try TeachingCloudConflictResolver.report(at: TeachingStudentSettingsStore.settingsFileURL())
                }.value
                conflictReport = report
                conflictMessage = report.conflicts.isEmpty ? "没有未解决的学生设置冲突。" : "当前文件可以读取；解除冲突前仍禁止覆盖。"
            } catch { conflictMessage = "版本检查失败：\(error.localizedDescription)" }
        }
    }
    private func keepCurrentStudentSettings() {
        guard let report = conflictReport, !isResolvingConflict else { return }
        isResolvingConflict = true
        Task {
            defer { isResolvingConflict = false }
            do {
                try await Task.detached(priority: .utility) { try TeachingCloudConflictResolver.keepCurrent(report) }.value
                conflictMessage = "已保留当前设置，全部版本已备份。"
                NotificationCenter.default.post(name: .teachingCloudFileChanged, object: nil, userInfo: ["filePath": report.url.path])
                loadRecovery()
                loadStudentConflicts()
                status.check()
            } catch { conflictMessage = "冲突处理未完成：\(error.localizedDescription)"; loadRecovery() }
        }
    }
    private func loadRecovery() {
        Task {
            do {
                recoveryFiles = try await Task.detached(priority: .utility) {
                    let root = try TeachingCloudFileAccess.recoveryRoot()
                    let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
                    var files: [URL] = []
                    while let url = enumerator?.nextObject() as? URL {
                        if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { files.append(url) }
                    }
                    return files.sorted { $0.lastPathComponent > $1.lastPathComponent }
                }.value
                recoveryError = ""
            } catch { recoveryError = "读取恢复副本失败：\(error.localizedDescription)" }
        }
    }
}
