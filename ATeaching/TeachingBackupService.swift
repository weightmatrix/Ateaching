import CryptoKit
import Foundation

enum TeachingBackupTrigger: String, Codable, CaseIterable {
    case manualFull
    case dailyFirstLaunch
    case hourly
    case classStart
    case classEnd
    case preRestoreSafety

    var displayName: String {
        switch self {
        case .manualFull:
            return "手动全量"
        case .dailyFirstLaunch:
            return "每日首次打开"
        case .hourly:
            return "每小时"
        case .classStart:
            return "上课"
        case .classEnd:
            return "下课"
        case .preRestoreSafety:
            return "恢复前安全快照"
        }
    }
}

enum TeachingBackupRestoreConflictStrategy: String, Codable, CaseIterable, Identifiable {
    case overwrite
    case skip
    case renameCopy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .overwrite:
            return "覆盖"
        case .skip:
            return "跳过"
        case .renameCopy:
            return "重命名副本"
        }
    }
}

struct TeachingBackupSnapshotManifest: Codable, Hashable, Identifiable {
    let id: String
    let createdAt: Date
    let trigger: TeachingBackupTrigger
    let fileCount: Int
    let directoryCount: Int
    let totalBytes: Int64
    let durationSeconds: TimeInterval
    let checksummedFileCount: Int

    init(
        id: String,
        createdAt: Date,
        trigger: TeachingBackupTrigger,
        fileCount: Int,
        directoryCount: Int,
        totalBytes: Int64,
        durationSeconds: TimeInterval,
        checksummedFileCount: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.trigger = trigger
        self.fileCount = fileCount
        self.directoryCount = directoryCount
        self.totalBytes = totalBytes
        self.durationSeconds = durationSeconds
        self.checksummedFileCount = checksummedFileCount
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case trigger
        case fileCount
        case directoryCount
        case totalBytes
        case durationSeconds
        case checksummedFileCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        trigger = try container.decode(TeachingBackupTrigger.self, forKey: .trigger)
        fileCount = try container.decode(Int.self, forKey: .fileCount)
        directoryCount = try container.decode(Int.self, forKey: .directoryCount)
        totalBytes = try container.decode(Int64.self, forKey: .totalBytes)
        durationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .durationSeconds) ?? 0
        checksummedFileCount = try container.decodeIfPresent(Int.self, forKey: .checksummedFileCount) ?? 0
    }
}

struct TeachingBackupSnapshotItem: Identifiable, Hashable {
    var id: String { relativePath }
    let relativePath: String
    let name: String
    let isDirectory: Bool
    let depth: Int
}

struct TeachingBackupDiffSummary: Hashable {
    let createPaths: [String]
    let overwritePaths: [String]
    let deletePaths: [String]

    var createCount: Int { createPaths.count }
    var overwriteCount: Int { overwritePaths.count }
    var deleteCount: Int { deletePaths.count }
}

struct TeachingBackupProgressSnapshot: Hashable {
    let phase: String
    let completedFiles: Int
    let totalFiles: Int
    let currentRelativePath: String?

    var fractionCompleted: Double {
        guard totalFiles > 0 else { return 0 }
        return min(1, max(0, Double(completedFiles) / Double(totalFiles)))
    }
}

private struct TeachingBackupChecksumsManifest: Codable {
    let generatedAt: Date
    let fileHashes: [String: String]
}

private struct TeachingBackupSchedulerState: Codable, Hashable {
    var lastDailyBackupKey: String?
    var lastHourlyBackupKey: String?
}

actor TeachingBackupService {
    static let shared = TeachingBackupService()

    private let fileManager = FileManager.default
    private let maxSnapshots = 100
    private let maxTotalBackupBytes: Int64 = 20 * 1024 * 1024 * 1024

    private let excludedDirectoryNames: Set<String> = [
        "tmp",
        "temp",
        "cache",
        "caches",
        "logs",
        ".trash"
    ]

    private let excludedFileExtensions: Set<String> = [
        "tmp",
        "temp",
        "log",
        "lock"
    ]
    private var currentProgressSnapshot: TeachingBackupProgressSnapshot?

    func listSnapshots() async throws -> [TeachingBackupSnapshotManifest] {
        let snapshotsRoot = try ensureSnapshotsRoot()
        let urls = try fileManager.contentsOfDirectory(
            at: snapshotsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var manifests: [TeachingBackupSnapshotManifest] = []
        for url in urls {
            let manifestURL = url.appendingPathComponent("manifest.json", isDirectory: false)
            guard let data = try? Data(contentsOf: manifestURL) else { continue }
            if let manifest = try? await decodeSnapshotManifest(from: data) {
                manifests.append(manifest)
            }
        }
        return manifests.sorted { $0.createdAt > $1.createdAt }
    }

    func currentBackupProgress() -> TeachingBackupProgressSnapshot? {
        currentProgressSnapshot
    }

    @discardableResult
    func performFullBackup(trigger: TeachingBackupTrigger) async throws -> TeachingBackupSnapshotManifest {
        let workspaceRoot = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        return try await createSnapshot(from: workspaceRoot, trigger: trigger)
    }

    func restoreFull(snapshotID: String) async throws {
        _ = try await performFullBackup(trigger: .preRestoreSafety)
        let workspaceRoot = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let snapshotContentRoot = try snapshotContentRoot(for: snapshotID)
        try await validateSnapshotIntegrity(snapshotID: snapshotID)
        let deleteCount = try countEligibleTopLevelItems(in: workspaceRoot)
        let copyCount = try countEligibleFiles(in: snapshotContentRoot)
        let totalFiles = max(1, deleteCount + copyCount)
        let progressTracker = FileProgressTracker(totalFiles: totalFiles)
        setProgress(phase: "恢复前清理", completedFiles: 0, totalFiles: totalFiles)
        defer { currentProgressSnapshot = nil }

        let existingItems = try fileManager.contentsOfDirectory(
            at: workspaceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for item in existingItems {
            try throwIfCancelled()
            let relativePath = relativePath(for: item, base: workspaceRoot)
            guard !shouldExclude(relativePath: relativePath, isDirectory: (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true) else {
                continue
            }
            try fileManager.removeItem(at: item)
            progressTracker.completedFiles += 1
            setProgress(
                phase: "恢复前清理",
                completedFiles: progressTracker.completedFiles,
                totalFiles: progressTracker.totalFiles,
                currentRelativePath: relativePath
            )
        }
        try copyDirectoryContent(
            from: snapshotContentRoot,
            to: workspaceRoot,
            overwrite: true,
            conflictStrategy: .overwrite,
            progressTracker: progressTracker,
            progressPhase: "恢复中"
        )
    }

    func restorePartial(
        snapshotID: String,
        relativePaths: [String],
        strategy: TeachingBackupRestoreConflictStrategy = .overwrite
    ) async throws {
        _ = try await performFullBackup(trigger: .preRestoreSafety)
        let workspaceRoot = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let snapshotContentRoot = try snapshotContentRoot(for: snapshotID)
        try await validateSnapshotIntegrity(snapshotID: snapshotID)

        let collapsedSelection = collapseSelectedPaths(
            normalizeSelected(relativePaths: relativePaths)
        )
        let copyCount = try countSelectedFilesForRestore(
            in: snapshotContentRoot,
            selectedPaths: collapsedSelection
        )
        let progressTracker = FileProgressTracker(totalFiles: copyCount)
        setProgress(phase: "部分恢复中", completedFiles: 0, totalFiles: progressTracker.totalFiles)
        defer { currentProgressSnapshot = nil }
        for relativePath in collapsedSelection {
            try throwIfCancelled()
            let sourceURL = snapshotContentRoot.appendingPathComponent(relativePath, isDirectory: false)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            var destinationURL = workspaceRoot.appendingPathComponent(relativePath, isDirectory: false)
            if fileManager.fileExists(atPath: destinationURL.path), strategy == .renameCopy {
                destinationURL = makeRenamedCopyURL(for: destinationURL)
            }
            try copyItem(
                from: sourceURL,
                to: destinationURL,
                overwrite: strategy == .overwrite,
                conflictStrategy: strategy,
                progressTracker: progressTracker,
                progressPhase: "部分恢复中"
            )
        }
    }

    func listSnapshotItems(snapshotID: String) throws -> [TeachingBackupSnapshotItem] {
        let root = try snapshotContentRoot(for: snapshotID)
        var items: [TeachingBackupSnapshotItem] = []
        try appendItems(from: root, base: root, depth: 0, into: &items)
        return items
    }

    func previewFullRestoreDiff(snapshotID: String) throws -> TeachingBackupDiffSummary {
        let workspaceRoot = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let snapshotRoot = try snapshotContentRoot(for: snapshotID)
        let snapshotMap = try buildFileSignatureMap(in: snapshotRoot)
        let workspaceMap = try buildFileSignatureMap(in: workspaceRoot)

        let createPaths = snapshotMap.keys
            .filter { workspaceMap[$0] == nil }
            .sorted()
        let overwritePaths = snapshotMap.keys
            .filter { key in
                guard let existing = workspaceMap[key], let incoming = snapshotMap[key] else { return false }
                return existing != incoming
            }
            .sorted()
        let deletePaths = workspaceMap.keys
            .filter { snapshotMap[$0] == nil }
            .sorted()
        return TeachingBackupDiffSummary(
            createPaths: createPaths,
            overwritePaths: overwritePaths,
            deletePaths: deletePaths
        )
    }

    func previewPartialRestoreDiff(snapshotID: String, relativePaths: [String]) throws -> TeachingBackupDiffSummary {
        let workspaceRoot = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let snapshotRoot = try snapshotContentRoot(for: snapshotID)
        let snapshotMap = try buildFileSignatureMap(in: snapshotRoot)
        let workspaceMap = try buildFileSignatureMap(in: workspaceRoot)
        let selected = collapseSelectedPaths(
            normalizeSelected(relativePaths: relativePaths)
        )
        let selectedSnapshotKeys = snapshotMap.keys.filter { key in
            selected.contains(where: { key == $0 || key.hasPrefix($0 + "/") })
        }
        let createPaths = selectedSnapshotKeys
            .filter { workspaceMap[$0] == nil }
            .sorted()
        let overwritePaths = selectedSnapshotKeys
            .filter { key in
                guard let existing = workspaceMap[key], let incoming = snapshotMap[key] else { return false }
                return existing != incoming
            }
            .sorted()
        return TeachingBackupDiffSummary(
            createPaths: createPaths,
            overwritePaths: overwritePaths,
            deletePaths: []
        )
    }

    func runDailyFirstOpenBackupIfNeeded() async throws {
        var state = try await loadSchedulerState()
        let key = dailyKey(for: Date())
        guard state.lastDailyBackupKey != key else { return }
        _ = try await performFullBackup(trigger: .dailyFirstLaunch)
        state.lastDailyBackupKey = key
        try await saveSchedulerState(state)
    }

    func runHourlyBackupIfNeeded() async throws {
        var state = try await loadSchedulerState()
        let key = hourlyKey(for: Date())
        guard state.lastHourlyBackupKey != key else { return }
        _ = try await performFullBackup(trigger: .hourly)
        state.lastHourlyBackupKey = key
        try await saveSchedulerState(state)
    }

    func runClassEventBackup(trigger: TeachingBackupTrigger) async throws {
        guard trigger == .classStart || trigger == .classEnd else { return }
        _ = try await performFullBackup(trigger: trigger)
    }

    private func createSnapshot(from sourceRoot: URL, trigger: TeachingBackupTrigger) async throws -> TeachingBackupSnapshotManifest {
        let snapshotsRoot = try ensureSnapshotsRoot()
        let createdAt = Date()
        let start = Date()
        let snapshotID = makeSnapshotID(createdAt: createdAt)
        let snapshotRoot = snapshotsRoot.appendingPathComponent(snapshotID, isDirectory: true)
        let snapshotContentRoot = snapshotRoot.appendingPathComponent("content", isDirectory: true)
        let totalFiles = try countEligibleFiles(in: sourceRoot)
        let progressTracker = FileProgressTracker(totalFiles: totalFiles)
        setProgress(phase: "准备备份", completedFiles: 0, totalFiles: totalFiles)
        defer { currentProgressSnapshot = nil }

        try fileManager.createDirectory(at: snapshotContentRoot, withIntermediateDirectories: true)
        try copyDirectoryContent(
            from: sourceRoot,
            to: snapshotContentRoot,
            overwrite: true,
            conflictStrategy: .overwrite,
            progressTracker: progressTracker,
            progressPhase: "备份中"
        )
        setProgress(
            phase: "生成校验",
            completedFiles: progressTracker.completedFiles,
            totalFiles: progressTracker.totalFiles
        )

        let stats = try computeStats(in: snapshotContentRoot)
        let checksums = try buildChecksumManifest(in: snapshotContentRoot)
        let checksumURL = snapshotRoot.appendingPathComponent("checksums.json", isDirectory: false)
        let checksumData = try await MainActor.run { try JSONEncoder().encode(checksums) }
        try checksumData.write(to: checksumURL, options: .atomic)

        let manifest = await MainActor.run {
            TeachingBackupSnapshotManifest(
                id: snapshotID,
                createdAt: createdAt,
                trigger: trigger,
                fileCount: stats.fileCount,
                directoryCount: stats.directoryCount,
                totalBytes: stats.totalBytes,
                durationSeconds: Date().timeIntervalSince(start),
                checksummedFileCount: checksums.fileHashes.count
            )
        }
        let manifestURL = snapshotRoot.appendingPathComponent("manifest.json", isDirectory: false)
        let data = try await MainActor.run { try JSONEncoder().encode(manifest) }
        try data.write(to: manifestURL, options: .atomic)

        try await pruneSnapshotsIfNeeded()
        return manifest
    }

    private func ensureVaultRoot() throws -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "TeachingBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问应用支持目录"])
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "ATeaching"
        let root = appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("BackupVault", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func ensureSnapshotsRoot() throws -> URL {
        let root = try ensureVaultRoot().appendingPathComponent("snapshots", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func schedulerStateURL() throws -> URL {
        try ensureVaultRoot().appendingPathComponent("scheduler-state.json", isDirectory: false)
    }

    private func loadSchedulerState() async throws -> TeachingBackupSchedulerState {
        let url = try schedulerStateURL()
        guard fileManager.fileExists(atPath: url.path) else { return .init(lastDailyBackupKey: nil, lastHourlyBackupKey: nil) }
        let data = try Data(contentsOf: url)
        return try await MainActor.run {
            try JSONDecoder().decode(TeachingBackupSchedulerState.self, from: data)
        }
    }

    private func saveSchedulerState(_ state: TeachingBackupSchedulerState) async throws {
        let url = try schedulerStateURL()
        let data = try await MainActor.run {
            try JSONEncoder().encode(state)
        }
        try data.write(to: url, options: .atomic)
    }

    private func dailyKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private func hourlyKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMddHH"
        return formatter.string(from: date)
    }

    private func makeSnapshotID(createdAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(formatter.string(from: createdAt))-\(UUID().uuidString.prefix(8))"
    }

    private func snapshotRoot(for snapshotID: String) throws -> URL {
        let snapshotsRoot = try ensureSnapshotsRoot()
        let root = snapshotsRoot.appendingPathComponent(snapshotID, isDirectory: true)
        guard fileManager.fileExists(atPath: root.path) else {
            throw NSError(domain: "TeachingBackup", code: 2, userInfo: [NSLocalizedDescriptionKey: "备份不存在：\(snapshotID)"])
        }
        return root
    }

    private func snapshotContentRoot(for snapshotID: String) throws -> URL {
        let root = try snapshotRoot(for: snapshotID).appendingPathComponent("content", isDirectory: true)
        guard fileManager.fileExists(atPath: root.path) else {
            throw NSError(domain: "TeachingBackup", code: 2, userInfo: [NSLocalizedDescriptionKey: "备份不存在：\(snapshotID)"])
        }
        return root
    }

    private func validateSnapshotIntegrity(snapshotID: String) async throws {
        let root = try snapshotRoot(for: snapshotID)
        let contentRoot = root.appendingPathComponent("content", isDirectory: true)
        let checksumURL = root.appendingPathComponent("checksums.json", isDirectory: false)
        guard fileManager.fileExists(atPath: checksumURL.path) else {
            return
        }
        let data = try Data(contentsOf: checksumURL)
        let checksums = try await MainActor.run {
            try JSONDecoder().decode(TeachingBackupChecksumsManifest.self, from: data)
        }

        var mismatched: [String] = []
        for (relativePath, expectedHash) in checksums.fileHashes {
            let fileURL = contentRoot.appendingPathComponent(relativePath, isDirectory: false)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                mismatched.append(relativePath)
                if mismatched.count >= 20 { break }
                continue
            }
            let actual = try sha256Hex(of: fileURL)
            if actual != expectedHash {
                mismatched.append(relativePath)
                if mismatched.count >= 20 { break }
            }
        }

        if !mismatched.isEmpty {
            throw NSError(
                domain: "TeachingBackup",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "备份完整性校验失败，异常文件：\(mismatched.joined(separator: "，"))"]
            )
        }
    }

    private func pruneSnapshotsIfNeeded() async throws {
        let snapshotsRoot = try ensureSnapshotsRoot()
        let manifests = try await listSnapshots()
        var toRemove: [TeachingBackupSnapshotManifest] = []

        if manifests.count > maxSnapshots {
            toRemove.append(contentsOf: manifests.dropFirst(maxSnapshots))
        }

        var totalBytes = manifests.reduce(Int64(0)) { $0 + $1.totalBytes }
        if totalBytes > maxTotalBackupBytes {
            for manifest in manifests.reversed() {
                if toRemove.contains(where: { $0.id == manifest.id }) { continue }
                toRemove.append(manifest)
                totalBytes -= manifest.totalBytes
                if totalBytes <= maxTotalBackupBytes {
                    break
                }
            }
        }

        let uniqueRemoveIDs = Set(toRemove.map(\.id))
        for snapshotID in uniqueRemoveIDs {
            let root = snapshotsRoot.appendingPathComponent(snapshotID, isDirectory: true)
            if fileManager.fileExists(atPath: root.path) {
                try fileManager.removeItem(at: root)
            }
        }
    }

    private func appendItems(
        from current: URL,
        base: URL,
        depth: Int,
        into items: inout [TeachingBackupSnapshotItem]
    ) throws {
        let urls = try fileManager.contentsOfDirectory(
            at: current,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = values?.isDirectory == true
            let relative = relativePath(for: url, base: base)
            guard !shouldExclude(relativePath: relative, isDirectory: isDirectory) else { continue }
            items.append(
                TeachingBackupSnapshotItem(
                    relativePath: relative,
                    name: url.lastPathComponent,
                    isDirectory: isDirectory,
                    depth: depth
                )
            )
            if isDirectory {
                try appendItems(from: url, base: base, depth: depth + 1, into: &items)
            }
        }
    }

    private final class FileProgressTracker {
        let totalFiles: Int
        var completedFiles: Int = 0

        init(totalFiles: Int) {
            self.totalFiles = max(1, totalFiles)
        }
    }

    private struct FileSignature: Hashable {
        let size: Int64
        let modifiedAt: Date
    }

    private func buildFileSignatureMap(in root: URL) throws -> [String: FileSignature] {
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        var map: [String: FileSignature] = [:]
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            let isDirectory = values?.isDirectory == true
            let relative = relativePath(for: url, base: root)
            guard !shouldExclude(relativePath: relative, isDirectory: isDirectory) else { continue }
            guard values?.isRegularFile == true else { continue }
            map[relative] = FileSignature(
                size: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate ?? .distantPast
            )
        }
        return map
    }

    private func buildChecksumManifest(in root: URL) throws -> TeachingBackupChecksumsManifest {
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var hashes: [String: String] = [:]
        while let url = enumerator?.nextObject() as? URL {
            try throwIfCancelled()
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            let isDirectory = values?.isDirectory == true
            let relative = relativePath(for: url, base: root)
            guard !shouldExclude(relativePath: relative, isDirectory: isDirectory) else { continue }
            guard values?.isRegularFile == true else { continue }
            hashes[relative] = try sha256Hex(of: url)
        }
        return TeachingBackupChecksumsManifest(generatedAt: Date(), fileHashes: hashes)
    }

    private func sha256Hex(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func normalizeSelected(relativePaths: [String]) -> [String] {
        relativePaths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." && !$0.contains("..") }
    }

    private func collapseSelectedPaths(_ paths: [String]) -> [String] {
        let sorted = Set(paths).sorted()
        var collapsed: [String] = []
        for path in sorted {
            if collapsed.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                continue
            }
            collapsed.append(path)
        }
        return collapsed
    }

    private func makeRenamedCopyURL(for originalURL: URL) -> URL {
        let parent = originalURL.deletingLastPathComponent()
        let ext = originalURL.pathExtension
        let nameWithoutExt = ext.isEmpty ? originalURL.lastPathComponent : originalURL.deletingPathExtension().lastPathComponent
        var index = 1
        while true {
            let candidateName = "\(nameWithoutExt) (恢复副本\(index == 1 ? "" : " \(index)"))"
            let candidate = ext.isEmpty
                ? parent.appendingPathComponent(candidateName, isDirectory: false)
                : parent.appendingPathComponent(candidateName).appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func copyDirectoryContent(
        from sourceRoot: URL,
        to destinationRoot: URL,
        overwrite: Bool,
        conflictStrategy: TeachingBackupRestoreConflictStrategy,
        progressTracker: FileProgressTracker? = nil,
        progressPhase: String? = nil,
        progressRelativePath: String? = nil
    ) throws {
        let children = try fileManager.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for child in children {
            try throwIfCancelled()
            let relative = relativePath(for: child, base: sourceRoot)
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard !shouldExclude(relativePath: relative, isDirectory: isDirectory) else { continue }
            let destination = destinationRoot.appendingPathComponent(child.lastPathComponent, isDirectory: false)
            let childProgressPath: String
            if let progressRelativePath, !progressRelativePath.isEmpty {
                childProgressPath = progressRelativePath + "/" + child.lastPathComponent
            } else {
                childProgressPath = relative
            }
            try copyItem(
                from: child,
                to: destination,
                overwrite: overwrite,
                conflictStrategy: conflictStrategy,
                progressTracker: progressTracker,
                progressPhase: progressPhase,
                progressRelativePath: childProgressPath
            )
        }
    }

    private func copyItem(
        from source: URL,
        to destination: URL,
        overwrite: Bool,
        conflictStrategy: TeachingBackupRestoreConflictStrategy,
        progressTracker: FileProgressTracker? = nil,
        progressPhase: String? = nil,
        progressRelativePath: String? = nil
    ) throws {
        try throwIfCancelled()
        let values = try source.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = values.isDirectory == true
        let destinationExists = fileManager.fileExists(atPath: destination.path)

        if destinationExists {
            switch conflictStrategy {
            case .overwrite:
                if overwrite {
                    try fileManager.removeItem(at: destination)
                }
            case .skip:
                return
            case .renameCopy:
                break
            }
        }

        if isDirectory {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let children = try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for child in children {
                try throwIfCancelled()
                let target = destination.appendingPathComponent(child.lastPathComponent, isDirectory: false)
                let childProgressPath: String
                if let progressRelativePath, !progressRelativePath.isEmpty {
                    childProgressPath = progressRelativePath + "/" + child.lastPathComponent
                } else {
                    childProgressPath = child.lastPathComponent
                }
                try copyItem(
                    from: child,
                    to: target,
                    overwrite: overwrite,
                    conflictStrategy: conflictStrategy,
                    progressTracker: progressTracker,
                    progressPhase: progressPhase,
                    progressRelativePath: childProgressPath
                )
            }
        } else {
            let parent = destination.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: destination.path) {
                try fileManager.copyItem(at: source, to: destination)
            }
            if let progressTracker {
                progressTracker.completedFiles += 1
                setProgress(
                    phase: progressPhase ?? "处理中",
                    completedFiles: progressTracker.completedFiles,
                    totalFiles: progressTracker.totalFiles,
                    currentRelativePath: progressRelativePath
                )
            }
        }
    }

    private func computeStats(in root: URL) throws -> (fileCount: Int, directoryCount: Int, totalBytes: Int64) {
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        var fileCount = 0
        var directoryCount = 0
        var totalBytes: Int64 = 0
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey])
            let isDirectory = values?.isDirectory == true
            let relative = relativePath(for: url, base: root)
            guard !shouldExclude(relativePath: relative, isDirectory: isDirectory) else { continue }
            if isDirectory {
                directoryCount += 1
            } else if values?.isRegularFile == true {
                fileCount += 1
                totalBytes += Int64(values?.fileSize ?? 0)
            }
        }
        return (fileCount, directoryCount, totalBytes)
    }

    private func decodeSnapshotManifest(from data: Data) async throws -> TeachingBackupSnapshotManifest {
        try await MainActor.run {
            try JSONDecoder().decode(TeachingBackupSnapshotManifest.self, from: data)
        }
    }

    private func relativePath(for url: URL, base: URL) -> String {
        url.path.replacingOccurrences(of: base.path + "/", with: "")
    }

    private func countEligibleFiles(in root: URL) throws -> Int {
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var count = 0
        while let url = enumerator?.nextObject() as? URL {
            try throwIfCancelled()
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            let isDirectory = values?.isDirectory == true
            let relative = relativePath(for: url, base: root)
            guard !shouldExclude(relativePath: relative, isDirectory: isDirectory) else { continue }
            if values?.isRegularFile == true {
                count += 1
            }
        }
        return max(1, count)
    }

    private func countSelectedFilesForRestore(in root: URL, selectedPaths: [String]) throws -> Int {
        var count = 0
        for relativePath in selectedPaths {
            try throwIfCancelled()
            let sourceURL = root.appendingPathComponent(relativePath, isDirectory: false)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                count += try countEligibleFiles(in: sourceURL)
            } else {
                count += 1
            }
        }
        return max(1, count)
    }

    private func countEligibleTopLevelItems(in root: URL) throws -> Int {
        let items = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var count = 0
        for item in items {
            try throwIfCancelled()
            let relativePath = relativePath(for: item, base: root)
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard !shouldExclude(relativePath: relativePath, isDirectory: isDirectory) else { continue }
            count += 1
        }
        return count
    }

    private func setProgress(
        phase: String,
        completedFiles: Int,
        totalFiles: Int,
        currentRelativePath: String? = nil
    ) {
        currentProgressSnapshot = TeachingBackupProgressSnapshot(
            phase: phase,
            completedFiles: completedFiles,
            totalFiles: max(1, totalFiles),
            currentRelativePath: currentRelativePath
        )
    }

    private func throwIfCancelled() throws {
        if Task.isCancelled {
            throw CancellationError()
        }
    }

    private func shouldExclude(relativePath: String, isDirectory: Bool) -> Bool {
        guard !relativePath.isEmpty else { return false }
        let components = relativePath.split(separator: "/").map { String($0).lowercased() }
        if components.contains(where: { excludedDirectoryNames.contains($0) }) {
            return true
        }
        if !isDirectory {
            let ext = (relativePath as NSString).pathExtension.lowercased()
            if excludedFileExtensions.contains(ext) {
                return true
            }
        }
        return false
    }
}

@MainActor
final class TeachingBackupScheduler {
    static let shared = TeachingBackupScheduler()

    static let classStartedNotification = Notification.Name("TeachingBackupClassStartedNotification")
    static let classEndedNotification = Notification.Name("TeachingBackupClassEndedNotification")

    private var hourlyTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    func bootstrapIfNeeded() {
        guard hourlyTimer == nil else { return }
        installClassEventObservers()
        Task(priority: .utility) {
            try? await TeachingBackupService.shared.runDailyFirstOpenBackupIfNeeded()
            try? await TeachingBackupService.shared.runHourlyBackupIfNeeded()
        }
        startHourlyTimer()
    }

    private func startHourlyTimer() {
        hourlyTimer?.invalidate()
        hourlyTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task(priority: .utility) {
                try? await TeachingBackupService.shared.runHourlyBackupIfNeeded()
            }
        }
    }

    private func installClassEventObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: Self.classStartedNotification, object: nil, queue: .main) { _ in
                Task(priority: .utility) {
                    try? await TeachingBackupService.shared.runClassEventBackup(trigger: .classStart)
                }
            }
        )
        observers.append(
            center.addObserver(forName: Self.classEndedNotification, object: nil, queue: .main) { _ in
                Task(priority: .utility) {
                    try? await TeachingBackupService.shared.runClassEventBackup(trigger: .classEnd)
                }
            }
        )
    }
}
