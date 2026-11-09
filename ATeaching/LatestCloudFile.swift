import Foundation
import CryptoKit

/// Last saved version wins. Retry/download time never becomes the edit time.
nonisolated enum LatestCloudFile {
    private static let accessLock = NSRecursiveLock()
    struct Snapshot {
        let data: Data
        let modifiedAt: Date
        var digest: String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    }
    static func prefers(_ candidate: Snapshot, over current: Snapshot) -> Bool {
        if candidate.modifiedAt != current.modifiedAt { return candidate.modifiedAt > current.modifiedAt }
        return candidate.digest > current.digest
    }
    static func ready(_ url: URL) throws {
        var freshURL = url
        freshURL.removeAllCachedResourceValues()
        let values = try freshURL.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemDownloadingErrorKey])
        if let error = values.ubiquitousItemDownloadingError { throw error }
        if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            throw NSError(domain: "LatestCloudFile", code: 1, userInfo: [NSLocalizedDescriptionKey: "等待 iCloud 当前版本下载：\(url.lastPathComponent)"])
        }
    }
    /// Must be called inside a coordinated write. Read all candidates before pruning any version.
    private static func resolve(_ url: URL) throws -> Snapshot {
        try ready(url)
        var winner = Snapshot(data: try Data(contentsOf: url), modifiedAt: (try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast)
        let current = winner
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        for version in conflicts {
            let candidate = Snapshot(data: try Data(contentsOf: version.url), modifiedAt: version.modificationDate ?? .distantPast)
            if prefers(candidate, over: winner) { winner = candidate }
        }
        if winner.digest != current.digest || winner.modifiedAt != current.modifiedAt {
            try winner.data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: winner.modifiedAt], ofItemAtPath: url.path)
        }
        if !conflicts.isEmpty {
            for version in conflicts { version.isResolved = true }
            try NSFileVersion.removeOtherVersionsOfItem(at: url)
        }
        return winner
    }
    static func read(_ url: URL) throws -> Snapshot {
        accessLock.lock(); defer { accessLock.unlock() }
        try ready(url)
        var error: NSError?
        var result: Result<Snapshot, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &error) { coordinated in
            result = Result { try resolve(coordinated) }
        }
        if let error { throw error }
        guard let result else { throw NSError(domain: "LatestCloudFile", code: 2) }
        return try result.get()
    }
    /// Returns the authoritative snapshot, which can be a newer remote edit.
    static func write(_ data: Data, to url: URL, editedAt: Date) throws -> Snapshot {
        accessLock.lock(); defer { accessLock.unlock() }
        if FileManager.default.fileExists(atPath: url.path) { try ready(url) }
        var error: NSError?
        var result: Result<Snapshot, Error>?
        let options: NSFileCoordinator.WritingOptions = FileManager.default.fileExists(atPath: url.path) ? .forMerging : .forReplacing
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &error) { coordinated in
            result = Result {
                let incoming = Snapshot(data: data, modifiedAt: editedAt)
                if FileManager.default.fileExists(atPath: coordinated.path) {
                    let existing = try resolve(coordinated)
                    if prefers(existing, over: incoming) { return existing }
                    if existing.digest == incoming.digest { return existing }
                }
                try data.write(to: coordinated, options: .atomic)
                try FileManager.default.setAttributes([.modificationDate: editedAt], ofItemAtPath: coordinated.path)
                return incoming
            }
        }
        if let error { throw error }
        guard let result else { throw NSError(domain: "LatestCloudFile", code: 2) }
        return try result.get()
    }
}
