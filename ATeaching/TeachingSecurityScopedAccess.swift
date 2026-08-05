import Foundation

#if os(macOS)
import AppKit
#endif

enum TeachingSecurityScopedAccess {
    private static let defaultsKey = "teaching.security_scoped.bookmarks.v2"

    private struct BookmarkMatch {
        let storedPath: String
        let data: Data
    }

    private struct ResolvedBookmarkAccess {
        let match: BookmarkMatch
        let scopedURL: URL
        let targetURL: URL
        let isStale: Bool
    }

    static func canonicalFolderURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func canonicalPath(_ path: String) -> String {
        canonicalFolderURL(URL(fileURLWithPath: path, isDirectory: true)).path
    }

    static func storeBookmark(for url: URL) throws {
        // Powerbox把访问权授予选择器返回的原始URL。解析符号链接会生成一个
        // 没有该授权的新URL，所以真实路径只用于索引，绝不能用于生成书签。
        let pickedURL = url.standardizedFileURL
        let canonical = canonicalFolderURL(pickedURL).path
        guard !canonical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let didStart = pickedURL.startAccessingSecurityScopedResource()
        defer {
            if didStart { pickedURL.stopAccessingSecurityScopedResource() }
        }
        #if os(macOS)
        let bookmark = try pickedURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        let bookmark = try pickedURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
        _ = try resolveBookmarkData(bookmark)
        var store = loadStore()
        store[canonical] = bookmark
        store[pickedURL.path] = bookmark
        saveStore(store)
    }

    static func withWritableAccess<T>(
        toPath rawPath: String,
        allowInteractiveRecovery: Bool = false,
        _ body: (URL) throws -> T
    ) throws -> T {
        let canonical = canonicalPath(rawPath)
        let targetURL = URL(fileURLWithPath: canonical, isDirectory: true)
        let candidates = bookmarkCandidates(forPath: canonical)
        guard !candidates.isEmpty else {
            return try body(targetURL)
        }

        var authorizationFailures: [String] = []
        for match in candidates {
            let access: ResolvedBookmarkAccess
            do {
                access = try resolve(match: match, targetURL: targetURL)
            } catch {
                authorizationFailures.append("\(match.storedPath)：\(error.localizedDescription)")
                TeachingDebugLogStore.append(
                    "目录书签解析失败，继续尝试上级授权：\(match.storedPath)，错误：\(error.localizedDescription)",
                    category: "SecurityScope"
                )
                continue
            }

            let didStart = access.scopedURL.startAccessingSecurityScopedResource()
            guard didStart else {
                authorizationFailures.append("\(match.storedPath)：无法启动目录授权")
                TeachingDebugLogStore.append(
                    "目录书签无法启动，继续尝试上级授权：\(match.storedPath)",
                    category: "SecurityScope"
                )
                continue
            }
            defer { access.scopedURL.stopAccessingSecurityScopedResource() }

            if access.isStale {
                try? replaceBookmark(storedPath: match.storedPath, with: access.scopedURL)
            }
            // 上级目录书签可以授权学生子目录。成功后立即为真实学生目录补建独立书签，
            // 下次直接命中学生目录，不再依赖逐层查找。
            try? persistResolvedTargetBookmark(
                requestedPath: canonical,
                resolvedTargetURL: access.targetURL
            )
            if match.storedPath != canonical {
                TeachingDebugLogStore.append(
                    "学生目录授权已由上级书签恢复并重新落盘：\(canonical) <- \(match.storedPath)",
                    category: "SecurityScope"
                )
            }
            return try body(access.targetURL)
        }

        // 没有可解析的书签时仍尝试真实落盘路径；若沙盒拒绝访问，返回包含真实路径
        // 与全部书签失败原因的中文错误，避免系统只显示“The file couldn't be opened”。
        do {
            return try body(targetURL)
        } catch {
            #if os(macOS)
            if allowInteractiveRecovery {
                let authorizedURL = try requestWritableAuthorization(for: targetURL)
                try storeBookmark(for: authorizedURL)
                return try withWritableAccess(
                    toPath: canonical,
                    allowInteractiveRecovery: false,
                    body
                )
            }
            #endif
            let bookmarkDetails = authorizationFailures.joined(separator: "；")
            throw NSError(
                domain: "TeachingSecurityScopedAccess",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey: "同步目录地址仍为\(canonical)，但目录授权已失效。请在学生设置中重新选择一次该目录。\(bookmarkDetails.isEmpty ? "" : "书签检查：\(bookmarkDetails)")",
                    NSUnderlyingErrorKey: error
                ]
            )
        }
    }

    #if os(macOS)
    /// 失效的普通书签不能被程序静默升级，这是macOS沙盒的硬限制。
    /// 下课自动导出允许在失败点直接补授权；用户可以选择目标学生目录，
    /// 也可以选择它的任意上级目录，一次授权可覆盖同目录下其他学生。
    private static func requestWritableAuthorization(for targetURL: URL) throws -> URL {
        let panel = NSOpenPanel()
        panel.title = "重新授权学生同步目录"
        panel.message = "目录地址仍然有效，但旧授权已经失效。请选择“\(targetURL.lastPathComponent)”或它的上级文件夹，授权后本次下课会自动继续。"
        panel.prompt = "重新授权"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = targetURL.deletingLastPathComponent()
        panel.nameFieldStringValue = targetURL.lastPathComponent

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            throw NSError(
                domain: "TeachingSecurityScopedAccess",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "已取消同步目录重新授权，本次下课尚未完成。"]
            )
        }

        let canonicalTarget = canonicalFolderURL(targetURL).path
        let canonicalSelection = canonicalFolderURL(selectedURL).path
        guard canonicalTarget == canonicalSelection
                || canonicalTarget.hasPrefix(canonicalSelection + "/") else {
            throw NSError(
                domain: "TeachingSecurityScopedAccess",
                code: 7,
                userInfo: [
                    NSLocalizedDescriptionKey: "选择的目录不能覆盖学生同步目录。请选择“\(targetURL.lastPathComponent)”或它的上级文件夹。"
                ]
            )
        }
        return selectedURL
    }
    #endif

    /// 从精确学生目录一路返回到上级目录。坏掉的精确书签不能阻断有效的父目录书签。
    private static func bookmarkCandidates(forPath canonicalPath: String) -> [BookmarkMatch] {
        let store = loadStore()
        var matches: [BookmarkMatch] = []
        var includedPaths: Set<String> = []
        var cursor = URL(fileURLWithPath: canonicalPath, isDirectory: true)
        while cursor.path != "/" && !cursor.path.isEmpty {
            if let data = store[cursor.path] {
                matches.append(BookmarkMatch(storedPath: cursor.path, data: data))
                includedPaths.insert(cursor.path)
            }
            cursor.deleteLastPathComponent()
        }
        // 改名后字典Key可能仍是旧路径，但安全书签会解析到移动后的真实目录。
        // 扫描少量已存书签，把真实位置是目标上级目录的授权也纳入候选。
        for (storedPath, data) in store where !includedPaths.contains(storedPath) {
            guard let resolvedURL = try? resolveBookmarkData(data) else { continue }
            let resolvedPath = canonicalFolderURL(resolvedURL).path
            guard canonicalPath == resolvedPath || canonicalPath.hasPrefix(resolvedPath + "/") else { continue }
            matches.append(BookmarkMatch(storedPath: storedPath, data: data))
            includedPaths.insert(storedPath)
        }
        return matches
    }

    private static func resolve(match: BookmarkMatch, targetURL: URL) throws -> ResolvedBookmarkAccess {
        var stale = false
        let scopedURL: URL
        do {
        #if os(macOS)
            scopedURL = try URL(
                resolvingBookmarkData: match.data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        #else
            scopedURL = try URL(
                resolvingBookmarkData: match.data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        #endif
        } catch {
            return try migrateLegacyBookmark(match: match, targetURL: targetURL, originalError: error)
        }
        let accessURL = scopedURL.standardizedFileURL
        let canonicalScopedURL = canonicalFolderURL(accessURL)
        return ResolvedBookmarkAccess(
            match: match,
            scopedURL: accessURL,
            targetURL: remapTarget(
                targetURL,
                storedBookmarkPath: match.storedPath,
                resolvedBookmarkURL: canonicalScopedURL
            ),
            isStale: stale
        )
    }

    private static func remapTarget(
        _ targetURL: URL,
        storedBookmarkPath: String,
        resolvedBookmarkURL: URL
    ) -> URL {
        let storedComponents = URL(fileURLWithPath: storedBookmarkPath, isDirectory: true).pathComponents
        let targetComponents = targetURL.pathComponents
        let resolvedComponents = resolvedBookmarkURL.pathComponents
        if targetComponents.starts(with: resolvedComponents) {
            return targetURL
        }
        guard targetComponents.starts(with: storedComponents) else { return resolvedBookmarkURL }
        return targetComponents.dropFirst(storedComponents.count).reduce(resolvedBookmarkURL) { partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }
    }

    private static func resolveBookmarkData(_ data: Data) throws -> URL {
        var stale = false
        #if os(macOS)
        return try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        #else
        return try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        #endif
    }

    /// 812号修复前保存的是普通路径书签。若当前进程仍持有选择器授予的临时权限，
    /// 这里自动升级成安全书签；权限已经随进程结束时，只能要求用户重新授权一次。
    private static func migrateLegacyBookmark(
        match: BookmarkMatch,
        targetURL: URL,
        originalError: Error
    ) throws -> ResolvedBookmarkAccess {
        var stale = false
        let legacyURL: URL
        do {
            legacyURL = try URL(
                resolvingBookmarkData: match.data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            throw originalError
        }

        let didStart = legacyURL.startAccessingSecurityScopedResource()
        guard didStart else {
            throw NSError(
                domain: "TeachingSecurityScopedAccess",
                code: 5,
                userInfo: [
                    NSLocalizedDescriptionKey: "检测到旧版普通目录书签，需要重新授权一次：\(canonicalFolderURL(legacyURL).path)",
                    NSUnderlyingErrorKey: originalError
                ]
            )
        }
        defer { legacyURL.stopAccessingSecurityScopedResource() }

        #if os(macOS)
        let upgradedData = try legacyURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        let upgradedData = try legacyURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
        let upgradedURL = try resolveBookmarkData(upgradedData)
        var store = loadStore()
        store[match.storedPath] = upgradedData
        store[canonicalFolderURL(upgradedURL).path] = upgradedData
        saveStore(store)

        let accessURL = upgradedURL.standardizedFileURL
        let canonicalScopedURL = canonicalFolderURL(accessURL)
        return ResolvedBookmarkAccess(
            match: BookmarkMatch(storedPath: match.storedPath, data: upgradedData),
            scopedURL: accessURL,
            targetURL: remapTarget(
                targetURL,
                storedBookmarkPath: match.storedPath,
                resolvedBookmarkURL: canonicalScopedURL
            ),
            isStale: stale
        )
    }

    private static func replaceBookmark(storedPath: String, with refreshedURL: URL) throws {
        let bookmarkURL = refreshedURL.standardizedFileURL
        let canonicalURL = canonicalFolderURL(bookmarkURL)
        #if os(macOS)
        let bookmark = try bookmarkURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        let bookmark = try bookmarkURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
        _ = try resolveBookmarkData(bookmark)
        var store = loadStore()
        // 保留旧路径作为别名，让尚未迁移的设置仍能映射到书签当前的真实位置。
        store[storedPath] = bookmark
        store[canonicalURL.path] = bookmark
        saveStore(store)
    }

    private static func persistResolvedTargetBookmark(
        requestedPath: String,
        resolvedTargetURL: URL
    ) throws {
        let bookmarkURL = resolvedTargetURL.standardizedFileURL
        let canonicalTargetURL = canonicalFolderURL(bookmarkURL)
        #if os(macOS)
        let bookmark = try bookmarkURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        let bookmark = try bookmarkURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
        _ = try resolveBookmarkData(bookmark)
        var store = loadStore()
        store[requestedPath] = bookmark
        store[canonicalTargetURL.path] = bookmark
        saveStore(store)
    }

    private static func loadStore() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
    }

    private static func saveStore(_ store: [String: Data]) {
        UserDefaults.standard.set(store, forKey: defaultsKey)
    }
}
