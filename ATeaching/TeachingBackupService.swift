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

private struct TeachingBackupObjectEntry: Codable, Hashable {
    let hash: String
    let size: Int64
    let modifiedAt: Date
}

private struct TeachingBackupObjectManifest: Codable {
    let formatVersion: Int
    let generatedAt: Date
    let files: [String: TeachingBackupObjectEntry]
    let directories: [String]
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
    private let objectManifestFileName = "object-manifest.json"

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
    private var verifiedObjectHashes: Set<String> = []

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

    func storedBackupBytes() async throws -> Int64 {
        let snapshots = try await listSnapshots()
        return try estimatedStoredBackupBytes(snapshotManifests: snapshots)
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
        let objectManifest = try await loadObjectManifest(snapshotID: snapshotID)
        let preexistingNumericCopies = try numericCopyPaths(in: workspaceRoot)
        let snapshotInventory = try buildRestoreInventory(in: snapshotContentRoot)
        let workspaceInventory = try buildRestoreInventory(in: workspaceRoot)
        let obsoleteFileCount = workspaceInventory.files.subtracting(snapshotInventory.files).count
        let copyCount = try countEligibleFiles(in: snapshotContentRoot)
        let totalFiles = max(1, obsoleteFileCount + copyCount)
        let progressTracker = FileProgressTracker(totalFiles: totalFiles)
        setProgress(phase: "协调恢复中", completedFiles: 0, totalFiles: totalFiles)
        defer { currentProgressSnapshot = nil }

        try restoreDirectoryContent(
            from: snapshotContentRoot,
            to: workspaceRoot,
            conflictStrategy: .overwrite,
            progressTracker: progressTracker,
            progressPhase: "协调恢复中"
        )
        try removeItemsMissingFromSnapshot(
            sourceRoot: snapshotContentRoot,
            destinationRoot: workspaceRoot,
            progressTracker: progressTracker,
            progressPhase: "清理旧文件"
        )
        if let objectManifest {
            try applyRestoredMetadata(
                objectManifest,
                sourceRelativePath: nil,
                destinationRoot: workspaceRoot
            )
        }
        try verifyRestoredContent(from: snapshotContentRoot, at: workspaceRoot)
        try rejectNewNumericCopies(
            in: workspaceRoot,
            preexisting: preexistingNumericCopies,
            allowedBySnapshot: snapshotInventory.files.union(snapshotInventory.directories)
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
        let objectManifest = try await loadObjectManifest(snapshotID: snapshotID)
        let preexistingNumericCopies = try numericCopyPaths(in: workspaceRoot)
        let snapshotInventory = try buildRestoreInventory(in: snapshotContentRoot)

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
            try restoreItem(
                from: sourceURL,
                to: destinationURL,
                conflictStrategy: strategy,
                progressTracker: progressTracker,
                progressPhase: "部分恢复中",
                progressRelativePath: relativePath
            )
            if strategy == .overwrite,
               (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try removeItemsMissingFromSnapshot(
                    sourceRoot: sourceURL,
                    destinationRoot: destinationURL,
                    progressTracker: nil,
                    progressPhase: "部分恢复清理"
                )
            }
            if strategy != .skip {
                if let objectManifest {
                    try applyRestoredMetadata(
                        objectManifest,
                        sourceRelativePath: relativePath,
                        destinationRoot: destinationURL
                    )
                }
                try verifyRestoredContent(from: sourceURL, at: destinationURL)
            }
        }
        try rejectNewNumericCopies(
            in: workspaceRoot,
            preexisting: preexistingNumericCopies,
            allowedBySnapshot: snapshotInventory.files.union(snapshotInventory.directories)
        )
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
        let buildingRoot = snapshotsRoot.appendingPathComponent(".\(snapshotID).building", isDirectory: true)
        let snapshotContentRoot = buildingRoot.appendingPathComponent("content", isDirectory: true)
        let totalFiles = try countEligibleFiles(in: sourceRoot)
        let progressTracker = FileProgressTracker(totalFiles: totalFiles)
        setProgress(phase: "准备备份", completedFiles: 0, totalFiles: totalFiles)
        defer { currentProgressSnapshot = nil }
        if fileManager.fileExists(atPath: buildingRoot.path) {
            try fileManager.removeItem(at: buildingRoot)
        }
        try fileManager.createDirectory(at: snapshotContentRoot, withIntermediateDirectories: true)
        var didPublishSnapshot = false
        defer {
            if !didPublishSnapshot {
                try? fileManager.removeItem(at: buildingRoot)
            }
        }

        let snapshots = try await listSnapshots()
        let latest = snapshots.first
        let previousContentRoot = latest.flatMap { try? self.snapshotContentRoot(for: $0.id) }
        let objectManifest = try createContentAddressedSnapshot(
            from: sourceRoot,
            to: snapshotContentRoot,
            previousContentRoot: previousContentRoot,
            progressTracker: progressTracker,
            progressPhase: "备份中"
        )
        setProgress(
            phase: "生成校验",
            completedFiles: progressTracker.completedFiles,
            totalFiles: progressTracker.totalFiles
        )

        let stats = (
            fileCount: objectManifest.files.count,
            directoryCount: objectManifest.directories.count,
            totalBytes: objectManifest.files.values.reduce(Int64(0)) { $0 + $1.size }
        )
        let checksums = TeachingBackupChecksumsManifest(
            generatedAt: createdAt,
            fileHashes: objectManifest.files.mapValues(\.hash)
        )
        let objectManifestURL = buildingRoot.appendingPathComponent(objectManifestFileName, isDirectory: false)
        let objectManifestData = try await MainActor.run { try JSONEncoder().encode(objectManifest) }
        try objectManifestData.write(to: objectManifestURL, options: .atomic)

        let checksumURL = buildingRoot.appendingPathComponent("checksums.json", isDirectory: false)
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
        let manifestURL = buildingRoot.appendingPathComponent("manifest.json", isDirectory: false)
        let data = try await MainActor.run { try JSONEncoder().encode(manifest) }
        try data.write(to: manifestURL, options: .atomic)

        try fileManager.moveItem(at: buildingRoot, to: snapshotRoot)
        didPublishSnapshot = true

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

    private func ensureObjectsRoot() throws -> URL {
        let root = try ensureVaultRoot().appendingPathComponent("objects", isDirectory: true)
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
        if let objectManifest = try await loadObjectManifest(snapshotID: snapshotID) {
            var mismatched: [String] = []
            for (relativePath, entry) in objectManifest.files {
                let objectURL = try backupObjectURL(for: entry.hash, createParent: false)
                let contentURL = contentRoot.appendingPathComponent(relativePath, isDirectory: false)
                guard fileManager.fileExists(atPath: objectURL.path),
                      fileManager.fileExists(atPath: contentURL.path) else {
                    mismatched.append(relativePath)
                    if mismatched.count >= 20 { break }
                    continue
                }
                if !verifiedObjectHashes.contains(entry.hash) {
                    guard try sha256Hex(of: objectURL) == entry.hash else {
                        mismatched.append(relativePath)
                        if mismatched.count >= 20 { break }
                        continue
                    }
                    verifiedObjectHashes.insert(entry.hash)
                }
            }
            if !mismatched.isEmpty {
                throw NSError(
                    domain: "TeachingBackup",
                    code: 11,
                    userInfo: [NSLocalizedDescriptionKey: "备份对象完整性校验失败，异常文件：\(mismatched.joined(separator: "，"))"]
                )
            }
            return
        }

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

    private func loadObjectManifest(snapshotID: String) async throws -> TeachingBackupObjectManifest? {
        let url = try snapshotRoot(for: snapshotID)
            .appendingPathComponent(objectManifestFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try await MainActor.run {
            try JSONDecoder().decode(TeachingBackupObjectManifest.self, from: data)
        }
    }

    private func applyRestoredMetadata(
        _ manifest: TeachingBackupObjectManifest,
        sourceRelativePath: String?,
        destinationRoot: URL
    ) throws {
        for (relativePath, entry) in manifest.files {
            let destinationURL: URL
            if let sourceRelativePath {
                guard relativePath == sourceRelativePath || relativePath.hasPrefix(sourceRelativePath + "/") else {
                    continue
                }
                if relativePath == sourceRelativePath {
                    destinationURL = destinationRoot
                } else {
                    let suffixStart = relativePath.index(
                        relativePath.startIndex,
                        offsetBy: sourceRelativePath.count + 1
                    )
                    destinationURL = destinationRoot.appendingPathComponent(
                        String(relativePath[suffixStart...]),
                        isDirectory: false
                    )
                }
            } else {
                destinationURL = destinationRoot.appendingPathComponent(relativePath, isDirectory: false)
            }
            guard fileManager.fileExists(atPath: destinationURL.path) else { continue }
            try fileManager.setAttributes(
                [.modificationDate: entry.modifiedAt],
                ofItemAtPath: destinationURL.path
            )
        }
    }

    private func pruneSnapshotsIfNeeded() async throws {
        let snapshotsRoot = try ensureSnapshotsRoot()
        var manifests = try await listSnapshots()
        let countOverflow = max(0, manifests.count - maxSnapshots)
        if countOverflow > 0 {
            for manifest in manifests.suffix(countOverflow) {
                let root = snapshotsRoot.appendingPathComponent(manifest.id, isDirectory: true)
                if fileManager.fileExists(atPath: root.path) {
                    try fileManager.removeItem(at: root)
                }
            }
            manifests.removeLast(countOverflow)
        }

        try await pruneUnreferencedObjects(snapshotManifests: manifests)
        while manifests.count > 1,
              try estimatedStoredBackupBytes(snapshotManifests: manifests) > maxTotalBackupBytes {
            let oldest = manifests.removeLast()
            let root = snapshotsRoot.appendingPathComponent(oldest.id, isDirectory: true)
            if fileManager.fileExists(atPath: root.path) {
                try fileManager.removeItem(at: root)
            }
            try await pruneUnreferencedObjects(snapshotManifests: manifests)
        }
    }

    private func pruneUnreferencedObjects(
        snapshotManifests: [TeachingBackupSnapshotManifest]
    ) async throws {
        var referencedHashes: Set<String> = []
        let snapshotsRoot = try ensureSnapshotsRoot()
        for snapshot in snapshotManifests {
            let objectManifestURL = snapshotsRoot
                .appendingPathComponent(snapshot.id, isDirectory: true)
                .appendingPathComponent(objectManifestFileName, isDirectory: false)
            guard let data = try? Data(contentsOf: objectManifestURL),
                  let objectManifest = try? await MainActor.run(body: {
                      try JSONDecoder().decode(TeachingBackupObjectManifest.self, from: data)
                  }) else {
                continue
            }
            referencedHashes.formUnion(objectManifest.files.values.map(\.hash))
        }

        let objectsRoot = try ensureObjectsRoot()
        let enumerator = fileManager.enumerator(
            at: objectsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let objectURL = enumerator?.nextObject() as? URL {
            let values = try? objectURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            if !referencedHashes.contains(objectURL.lastPathComponent) {
                try fileManager.removeItem(at: objectURL)
            }
        }

        let prefixes = try fileManager.contentsOfDirectory(
            at: objectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for prefixURL in prefixes {
            let values = try? prefixURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            if try fileManager.contentsOfDirectory(atPath: prefixURL.path).isEmpty {
                try fileManager.removeItem(at: prefixURL)
            }
        }
    }

    private func estimatedStoredBackupBytes(
        snapshotManifests: [TeachingBackupSnapshotManifest]
    ) throws -> Int64 {
        var total = try allocatedFileBytes(in: ensureObjectsRoot())
        let snapshotsRoot = try ensureSnapshotsRoot()
        for snapshot in snapshotManifests {
            let root = snapshotsRoot.appendingPathComponent(snapshot.id, isDirectory: true)
            let objectManifestURL = root.appendingPathComponent(objectManifestFileName, isDirectory: false)
            if fileManager.fileExists(atPath: objectManifestURL.path) {
                for name in ["manifest.json", "checksums.json", objectManifestFileName] {
                    let url = root.appendingPathComponent(name, isDirectory: false)
                    total += try allocatedFileBytes(at: url)
                }
            } else {
                total += try allocatedFileBytes(in: root)
            }
        }
        return total
    }

    private func allocatedFileBytes(in root: URL) throws -> Int64 {
        guard fileManager.fileExists(atPath: root.path) else { return 0 }
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        )
        var total: Int64 = 0
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
            )
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    private func allocatedFileBytes(at url: URL) throws -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
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

    private struct RestoreInventory {
        var files: Set<String> = []
        var directories: Set<String> = []
    }

    private func buildRestoreInventory(in root: URL) throws -> RestoreInventory {
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var inventory = RestoreInventory()
        while let url = enumerator?.nextObject() as? URL {
            try throwIfCancelled()
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            let isDirectory = values?.isDirectory == true
            let relative = relativePath(for: url, base: root)
            guard !shouldExclude(relativePath: relative, isDirectory: isDirectory) else {
                if isDirectory {
                    enumerator?.skipDescendants()
                }
                continue
            }
            if isDirectory {
                inventory.directories.insert(relative)
            } else if values?.isRegularFile == true {
                inventory.files.insert(relative)
            }
        }
        return inventory
    }

    private func restoreDirectoryContent(
        from sourceRoot: URL,
        to destinationRoot: URL,
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
            try restoreItem(
                from: child,
                to: destination,
                conflictStrategy: conflictStrategy,
                progressTracker: progressTracker,
                progressPhase: progressPhase,
                progressRelativePath: childProgressPath
            )
        }
    }

    private func createContentAddressedSnapshot(
        from sourceRoot: URL,
        to destinationRoot: URL,
        previousContentRoot: URL?,
        sourceBaseRoot: URL? = nil,
        progressTracker: FileProgressTracker? = nil,
        progressPhase: String? = nil,
        accumulatedFiles: [String: TeachingBackupObjectEntry] = [:],
        accumulatedDirectories: [String] = []
    ) throws -> TeachingBackupObjectManifest {
        let sourceBaseRoot = sourceBaseRoot ?? sourceRoot
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        var files = accumulatedFiles
        var directories = accumulatedDirectories
        let children = try fileManager.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        for child in children {
            try throwIfCancelled()
            let relative = relativePath(for: child, base: sourceBaseRoot)
            let values = try? child.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            )
            let isDirectory = values?.isDirectory == true
            guard !shouldExclude(relativePath: relative, isDirectory: isDirectory) else { continue }

            let destination = destinationRoot.appendingPathComponent(child.lastPathComponent, isDirectory: false)
            if isDirectory {
                directories.append(relative)
                let nested = try createContentAddressedSnapshot(
                    from: child,
                    to: destination,
                    previousContentRoot: previousContentRoot,
                    sourceBaseRoot: sourceBaseRoot,
                    progressTracker: progressTracker,
                    progressPhase: progressPhase,
                    accumulatedFiles: files,
                    accumulatedDirectories: directories
                )
                files = nested.files
                directories = nested.directories
                continue
            }

            let parent = destination.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let hash = try sha256Hex(of: child)
            let entry = TeachingBackupObjectEntry(
                hash: hash,
                size: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate ?? .distantPast
            )
            let previousURL = previousContentRoot?
                .appendingPathComponent(relative, isDirectory: false)
            let objectURL = try ensureBackupObject(
                hash: hash,
                size: entry.size,
                sourceURL: child,
                reusableURL: previousURL
            )
            try fileManager.linkItem(at: objectURL, to: destination)
            files[relative] = entry

            if let progressTracker {
                progressTracker.completedFiles += 1
                setProgress(
                    phase: progressPhase ?? "备份中",
                    completedFiles: progressTracker.completedFiles,
                    totalFiles: progressTracker.totalFiles,
                    currentRelativePath: relative
                )
            }
        }

        return TeachingBackupObjectManifest(
            formatVersion: 1,
            generatedAt: Date(),
            files: files,
            directories: directories
        )
    }

    private func ensureBackupObject(
        hash: String,
        size: Int64,
        sourceURL: URL,
        reusableURL: URL?
    ) throws -> URL {
        let objectURL = try backupObjectURL(for: hash, createParent: true)
        if fileManager.fileExists(atPath: objectURL.path) {
            let values = try objectURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            let hasValidHash = verifiedObjectHashes.contains(hash)
                ? true
                : try sha256Hex(of: objectURL) == hash
            guard values.isRegularFile == true,
                  Int64(values.fileSize ?? -1) == size,
                  hasValidHash else {
                throw NSError(
                    domain: "TeachingBackup",
                    code: 21,
                    userInfo: [NSLocalizedDescriptionKey: "备份对象库损坏：\(hash)"]
                )
            }
            verifiedObjectHashes.insert(hash)
            return objectURL
        }

        let temporaryURL = objectURL.deletingLastPathComponent()
            .appendingPathComponent(".\(hash).\(UUID().uuidString).tmp", isDirectory: false)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        if let reusableURL,
           fileManager.fileExists(atPath: reusableURL.path),
           try sha256Hex(of: reusableURL) == hash {
            try fileManager.linkItem(at: reusableURL, to: temporaryURL)
        } else {
            try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: objectURL)
        verifiedObjectHashes.insert(hash)
        return objectURL
    }

    private func backupObjectURL(for hash: String, createParent: Bool) throws -> URL {
        let prefix = String(hash.prefix(2))
        let parent = try ensureObjectsRoot().appendingPathComponent(prefix, isDirectory: true)
        if createParent {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        return parent.appendingPathComponent(hash, isDirectory: false)
    }

    private func restoreItem(
        from source: URL,
        to destination: URL,
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
                break
            case .skip:
                return
            case .renameCopy:
                break
            }
        }

        if isDirectory {
            if destinationExists {
                let destinationValues = try destination.resourceValues(forKeys: [.isDirectoryKey])
                guard destinationValues.isDirectory == true else {
                    throw restoreTypeMismatchError(at: destination)
                }
            } else {
                try createCoordinatedDirectory(at: destination)
            }
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
                try restoreItem(
                    from: child,
                    to: target,
                    conflictStrategy: conflictStrategy,
                    progressTracker: progressTracker,
                    progressPhase: progressPhase,
                    progressRelativePath: childProgressPath
                )
            }
        } else {
            let parent = destination.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parent.path) {
                try createCoordinatedDirectory(at: parent)
            }
            if destinationExists {
                let destinationValues = try destination.resourceValues(forKeys: [.isDirectoryKey])
                guard destinationValues.isDirectory != true else {
                    throw restoreTypeMismatchError(at: destination)
                }
            }
            let needsReplacement = destinationExists
                ? try !filesHaveSameContent(source, destination)
                : true
            if needsReplacement {
                try replaceFileCoordinated(from: source, to: destination)
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

    private func removeItemsMissingFromSnapshot(
        sourceRoot: URL,
        destinationRoot: URL,
        progressTracker: FileProgressTracker?,
        progressPhase: String
    ) throws {
        guard fileManager.fileExists(atPath: destinationRoot.path) else { return }
        let sourceInventory = try buildRestoreInventory(in: sourceRoot)
        let destinationInventory = try buildRestoreInventory(in: destinationRoot)

        for relativePath in destinationInventory.files.subtracting(sourceInventory.files).sorted() {
            try throwIfCancelled()
            let destination = destinationRoot.appendingPathComponent(relativePath, isDirectory: false)
            try removeCoordinatedItem(at: destination)
            if let progressTracker {
                progressTracker.completedFiles += 1
                setProgress(
                    phase: progressPhase,
                    completedFiles: progressTracker.completedFiles,
                    totalFiles: progressTracker.totalFiles,
                    currentRelativePath: relativePath
                )
            }
        }

        let obsoleteDirectories = destinationInventory.directories
            .subtracting(sourceInventory.directories)
            .sorted { lhs, rhs in
                let lhsDepth = lhs.split(separator: "/").count
                let rhsDepth = rhs.split(separator: "/").count
                return lhsDepth == rhsDepth ? lhs > rhs : lhsDepth > rhsDepth
            }
        for relativePath in obsoleteDirectories {
            try throwIfCancelled()
            let destination = destinationRoot.appendingPathComponent(relativePath, isDirectory: true)
            let children = try fileManager.contentsOfDirectory(atPath: destination.path)
            if children.isEmpty {
                try removeCoordinatedItem(at: destination)
            }
        }
    }

    private func createCoordinatedDirectory(at destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        if parent.path != destination.path, !fileManager.fileExists(atPath: parent.path) {
            try createCoordinatedDirectory(at: parent)
        }
        try coordinateWriting(at: parent, options: .forMerging) { coordinatedParent in
            let coordinatedDestination = coordinatedParent.appendingPathComponent(
                destination.lastPathComponent,
                isDirectory: true
            )
            if !fileManager.fileExists(atPath: coordinatedDestination.path) {
                try fileManager.createDirectory(at: coordinatedDestination, withIntermediateDirectories: false)
            }
        }
    }

    private func replaceFileCoordinated(from source: URL, to destination: URL) throws {
        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ATeaching-Restore", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let stagedURL = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: false)
        try fileManager.copyItem(at: source, to: stagedURL)
        defer { try? fileManager.removeItem(at: stagedURL) }

        if fileManager.fileExists(atPath: destination.path) {
            try coordinateWriting(at: destination, options: .forReplacing) { coordinatedDestination in
                _ = try fileManager.replaceItemAt(
                    coordinatedDestination,
                    withItemAt: stagedURL,
                    backupItemName: nil,
                    options: []
                )
            }
        } else {
            let parent = destination.deletingLastPathComponent()
            try coordinateWriting(at: parent, options: .forMerging) { coordinatedParent in
                let coordinatedDestination = coordinatedParent.appendingPathComponent(
                    destination.lastPathComponent,
                    isDirectory: false
                )
                if fileManager.fileExists(atPath: coordinatedDestination.path) {
                    _ = try fileManager.replaceItemAt(
                        coordinatedDestination,
                        withItemAt: stagedURL,
                        backupItemName: nil,
                        options: []
                    )
                } else {
                    try fileManager.moveItem(at: stagedURL, to: coordinatedDestination)
                }
            }
        }
    }

    private func removeCoordinatedItem(at destination: URL) throws {
        guard fileManager.fileExists(atPath: destination.path) else { return }
        try coordinateWriting(at: destination, options: .forDeleting) { coordinatedDestination in
            if fileManager.fileExists(atPath: coordinatedDestination.path) {
                try fileManager.removeItem(at: coordinatedDestination)
            }
        }
    }

    private func coordinateWriting(
        at url: URL,
        options: NSFileCoordinator.WritingOptions,
        operation: (URL) throws -> Void
    ) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { coordinatedURL in
            do {
                try operation(coordinatedURL)
            } catch {
                operationError = error
            }
        }
        if let operationError {
            throw operationError
        }
        if let coordinationError {
            throw coordinationError
        }
    }

    private func filesHaveSameContent(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let lhsValues = try lhs.resourceValues(forKeys: [.fileSizeKey])
        let rhsValues = try rhs.resourceValues(forKeys: [.fileSizeKey])
        guard lhsValues.fileSize == rhsValues.fileSize else { return false }
        return try sha256Hex(of: lhs) == sha256Hex(of: rhs)
    }

    private func verifyRestoredContent(from source: URL, at destination: URL) throws {
        let sourceValues = try source.resourceValues(forKeys: [.isDirectoryKey])
        if sourceValues.isDirectory == true {
            let sourceInventory = try buildRestoreInventory(in: source)
            let destinationInventory = try buildRestoreInventory(in: destination)
            let missingFiles = sourceInventory.files.subtracting(destinationInventory.files)
            guard missingFiles.isEmpty else {
                throw restoreVerificationError(paths: Array(missingFiles.prefix(10)))
            }
            for relativePath in sourceInventory.files.sorted() {
                try throwIfCancelled()
                let sourceFile = source.appendingPathComponent(relativePath, isDirectory: false)
                let destinationFile = destination.appendingPathComponent(relativePath, isDirectory: false)
                guard try filesHaveSameContent(sourceFile, destinationFile) else {
                    throw restoreVerificationError(paths: [relativePath])
                }
                try rejectUnresolvedVersions(at: destinationFile)
            }
        } else {
            guard fileManager.fileExists(atPath: destination.path),
                  try filesHaveSameContent(source, destination) else {
                throw restoreVerificationError(paths: [destination.lastPathComponent])
            }
            try rejectUnresolvedVersions(at: destination)
        }
    }

    private func rejectUnresolvedVersions(at url: URL) throws {
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        guard conflicts.isEmpty else {
            throw NSError(
                domain: "TeachingBackup",
                code: 14,
                userInfo: [NSLocalizedDescriptionKey: "恢复后发现 iCloud 文件版本冲突：\(url.path)"]
            )
        }
    }

    private func numericCopyPaths(in root: URL) throws -> Set<String> {
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var paths: Set<String> = []
        while let url = enumerator?.nextObject() as? URL {
            try throwIfCancelled()
            if hasNumericCopySuffix(url.lastPathComponent) {
                paths.insert(relativePath(for: url, base: root))
            }
        }
        return paths
    }

    private func hasNumericCopySuffix(_ name: String) -> Bool {
        let pathExtension = (name as NSString).pathExtension
        let stem = pathExtension.isEmpty ? name : (name as NSString).deletingPathExtension
        guard let separator = stem.lastIndex(of: " ") else { return false }
        let suffix = stem[stem.index(after: separator)...]
        guard let number = Int(suffix), number >= 2 else { return false }
        return !stem[..<separator].isEmpty
    }

    private func rejectNewNumericCopies(
        in root: URL,
        preexisting: Set<String>,
        allowedBySnapshot: Set<String>
    ) throws {
        let unexpected = try numericCopyPaths(in: root)
            .subtracting(preexisting)
            .subtracting(allowedBySnapshot)
        guard unexpected.isEmpty else {
            throw NSError(
                domain: "TeachingBackup",
                code: 15,
                userInfo: [
                    NSLocalizedDescriptionKey: "恢复期间产生了数字冲突副本，已停止：\(unexpected.sorted().prefix(10).joined(separator: "，"))"
                ]
            )
        }
    }

    private func restoreVerificationError(paths: [String]) -> NSError {
        NSError(
            domain: "TeachingBackup",
            code: 13,
            userInfo: [
                NSLocalizedDescriptionKey: "恢复后内容校验失败：\(paths.sorted().joined(separator: "，"))"
            ]
        )
    }

    private func restoreTypeMismatchError(at destination: URL) -> NSError {
        NSError(
            domain: "TeachingBackup",
            code: 12,
            userInfo: [
                NSLocalizedDescriptionKey: "恢复目标类型冲突，已停止以避免删除重建：\(destination.path)"
            ]
        )
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
