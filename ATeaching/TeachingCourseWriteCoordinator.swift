import Foundation

// MARK: - 授课文件单写入队列 - 同一学生目录的写操作严格串行

actor TeachingCourseWriteCoordinator {
    static let shared = TeachingCourseWriteCoordinator()

    private var lockedKeys: Set<String> = []
    private var waitersByKey: [String: [CheckedContinuation<Void, Never>]] = [:]

    static func key(forNotebookURL url: URL) -> String {
        url.deletingLastPathComponent().standardizedFileURL.path
    }

    func acquire(key rawKey: String) async {
        let key = URL(fileURLWithPath: rawKey).standardizedFileURL.path
        if !lockedKeys.contains(key) {
            lockedKeys.insert(key)
            return
        }
        await withCheckedContinuation { continuation in
            waitersByKey[key, default: []].append(continuation)
        }
    }

    func release(key rawKey: String) {
        let key = URL(fileURLWithPath: rawKey).standardizedFileURL.path
        guard var waiters = waitersByKey[key], !waiters.isEmpty else {
            waitersByKey[key] = nil
            lockedKeys.remove(key)
            return
        }
        let next = waiters.removeFirst()
        waitersByKey[key] = waiters.isEmpty ? nil : waiters
        next.resume()
    }
}
