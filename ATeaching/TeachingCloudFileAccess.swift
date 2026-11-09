import Foundation
import CryptoKit

/// Coordinates local iCloud-provider access. `current` is not an acknowledgement from another device.
nonisolated enum TeachingCloudFileAccess {
    enum AccessError: LocalizedError {
        case waiting(String), conflict(String), changed(String), missingBaseline(String), coordination
        var errorDescription: String? {
            switch self {
            case .waiting(let name): return "\(name) 尚未下载到本机当前版本，已停止读写。请检查 iCloud 后重试。"
            case .conflict(let name): return "\(name) 存在 iCloud 版本冲突，已停止覆盖。"
            case .changed(let name): return "\(name) 已被其他操作修改，已停止覆盖。请保留当前编辑并重新核对文件。"
            case .missingBaseline(let name): return "\(name) 缺少读取基线，已停止覆盖现有文件。"
            case .coordination: return "文件协调未完成，未确认保存成功。"
            }
        }
    }
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func ensureReady(_ url: URL, rejectConflicts: Bool = true) throws {
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
                                                     .ubiquitousItemDownloadingErrorKey])
        if let error = values.ubiquitousItemDownloadingError { throw error }
        if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            throw AccessError.waiting(url.lastPathComponent)
        }
        if rejectConflicts && !(NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty {
            throw AccessError.conflict(url.lastPathComponent)
        }
    }
    static func read(_ url: URL) throws -> Data {
        // Refuse known-unready items before coordination can wait for materialization.
        try ensureReady(url, rejectConflicts: false)
        var error: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { coordinated in
            result = Result { try ensureReady(coordinated, rejectConflicts: false); return try Data(contentsOf: coordinated) }
        }
        if let error { throw error }
        guard let result else { throw AccessError.coordination }
        return try result.get()
    }
    /// expectedDigest nil means creation only; never silently replace an existing file without a baseline.
    static func write(_ data: Data, to url: URL, expectedDigest: String?, allowReplacingEmptyArray: Bool = false) throws {
        do {
            if FileManager.default.fileExists(atPath: url.path) { try ensureReady(url) }
        } catch { throw preservingFailure(error, data: data, url: url) }
        var error: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &error) { coordinated in
            result = Result {
                if FileManager.default.fileExists(atPath: coordinated.path) {
                    try ensureReady(coordinated)
                    let current = try Data(contentsOf: coordinated)
                    let hash = digest(current)
                    let array = (try? JSONSerialization.jsonObject(with: current)) as? [Any]
                    let mayInitializeEmptyArray = expectedDigest == nil && allowReplacingEmptyArray && array?.isEmpty == true
                    guard hash == expectedDigest || current == data || mayInitializeEmptyArray else {
                        if expectedDigest == nil { throw AccessError.missingBaseline(url.lastPathComponent) }
                        throw AccessError.changed(url.lastPathComponent)
                    }
                    // Keep the previous content before replacing it, including for successful writes.
                    if current != data { _ = try preserve(current, original: url, kind: "history") }
                } else if expectedDigest != nil {
                    throw AccessError.changed(url.lastPathComponent)
                }
                try data.write(to: coordinated, options: .atomic)
            }
        }
        do {
            if let error { throw error }
            guard let result else { throw AccessError.coordination }
            try result.get()
        } catch { throw preservingFailure(error, data: data, url: url) }
    }
    private static func preservingFailure(_ error: Error, data: Data, url: URL) -> Error {
        do { _ = try preserve(data, original: url, kind: "pending"); return error }
        catch let recoveryError {
            return NSError(domain: "TeachingCloud", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "保存失败：\(error.localizedDescription)；恢复副本也未保存：\(recoveryError.localizedDescription)。请勿关闭编辑页面。"])
        }
    }
    static func recoveryRoot() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
            .appendingPathComponent("ATeaching/CloudRecovery", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    @discardableResult
    static func preserve(_ data: Data, original: URL, kind: String) throws -> URL {
        let root = try recoveryRoot().appendingPathComponent(kind, isDirectory: true)
        let folder = root.appendingPathComponent(digest(Data(original.standardizedFileURL.path.utf8)), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = kind == "pending" ? "\(digest(data))-\(original.lastPathComponent)"
            : "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString)-\(original.lastPathComponent)"
        let target = folder.appendingPathComponent(name)
        try data.write(to: target, options: .atomic)
        // Pending edits are never pruned automatically. Only ordinary previous versions have a limit.
        if kind == "history" {
            let files = try FileManager.default.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey]).sorted { $0.lastPathComponent > $1.lastPathComponent }
            for file in files.dropFirst(20) { try FileManager.default.removeItem(at: file) }
        }
        return target
    }
}
