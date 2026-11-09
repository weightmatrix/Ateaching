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
        try LatestCloudFile.ready(url)
    }
    static func read(_ url: URL) throws -> Data {
        try LatestCloudFile.read(url).data
    }
    /// A fresh user save replaces older versions, irrespective of its previous read baseline.
    static func write(_ data: Data, to url: URL, expectedDigest: String?, allowReplacingEmptyArray: Bool = false) throws {
        let editedAt = Date()
        do {
            let winner = try LatestCloudFile.write(data, to: url, editedAt: editedAt)
            if winner.data != data {
                publishChange(url)
            }
            removePending(for: url, through: editedAt)
        } catch {
            try queuePending(data, url: url, editedAt: editedAt)
            throw error
        }
    }
    private static func publishChange(_ url: URL) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .teachingCloudFileChanged, object: nil, userInfo: ["filePath": url.path])
        }
    }
    private struct Pending: Codable {
        let url: URL
        let data: Data
        let editedAt: Date
    }
    private static let pendingLock = NSLock()
    private static func pendingURL(for url: URL) throws -> URL {
        let folder = try recoveryRoot().appendingPathComponent("latest-pending", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(digest(Data(url.standardizedFileURL.path.utf8)) + ".json")
    }
    private static func queuePending(_ data: Data, url: URL, editedAt: Date) throws {
        pendingLock.lock(); defer { pendingLock.unlock() }
        let path = try pendingURL(for: url)
        if let old = try? JSONDecoder().decode(Pending.self, from: Data(contentsOf: path)), old.editedAt > editedAt { return }
        try JSONEncoder().encode(Pending(url: url, data: data, editedAt: editedAt)).write(to: path, options: .atomic)
    }
    private static func removePending(for url: URL, through date: Date) {
        pendingLock.lock(); defer { pendingLock.unlock() }
        guard let path = try? pendingURL(for: url),
              let old = try? JSONDecoder().decode(Pending.self, from: Data(contentsOf: path)), old.editedAt <= date else { return }
        try? FileManager.default.removeItem(at: path)
    }
    static func retryPending() {
        guard let folder = try? recoveryRoot().appendingPathComponent("latest-pending"),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            guard let pending = try? JSONDecoder().decode(Pending.self, from: Data(contentsOf: file)) else { continue }
            do {
                _ = try LatestCloudFile.write(pending.data, to: pending.url, editedAt: pending.editedAt)
                removePending(for: pending.url, through: pending.editedAt)
                publishChange(pending.url)
            } catch { /* Keep only this newest pending edit until the provider is available. */ }
        }
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
