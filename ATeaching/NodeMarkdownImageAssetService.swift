import Foundation

#if os(macOS)
import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
#endif

struct NodeMarkdownImageInsertResult {
    // Legacy field name kept so current insertion call sites keep compiling.
    let htmlSnippet: String
    let relativePath: String
}

enum NodeMarkdownImageScope: Hashable {
    case lessonChapter(sourceFile: String, notebookFileURL: URL)
    case h3Temporary(packageID: String, notebookFileURL: URL)
}

struct NodeMarkdownImageResourceLocation: Hashable {
    let scope: NodeMarkdownImageScope
    let rootDirectoryURL: URL
    let picDirectoryURL: URL
    let markdownBaseDirectoryURL: URL
    let relativePicDirectoryPath: String
}

struct NodeMarkdownImageToken: Hashable {
    let altText: String
    let relativePath: String
    let width: Int
    let sourceRange: NSRange
    let sourceText: String

    var markdown: String {
        NodeMarkdownImageResourceManager.markdownImageToken(
            relativePath: relativePath,
            altText: altText,
            width: width
        )
    }
}

private struct NodeMarkdownUndoImageStashRecord: Codable, Hashable {
    let originalPath: String
    let stashPath: String
    let stashedAt: Date
}

private struct NodeMarkdownUndoImageStashManifest: Codable, Hashable {
    var records: [String: NodeMarkdownUndoImageStashRecord]
}

enum NodeMarkdownImageResourceManager {
    static let picDirectoryName = "Pic"
    static let defaultDisplayWidth = 600
    static let maxImportedPixel: CGFloat = 1024
    static let maxImportedBytes = 200 * 1024
    static let managedImageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "bmp", "tiff", "webp"]
    static let temporaryRootComponents = ["系统", "暂存"]
    private static let undoImageStashDirectoryName = "图片"
    private static let undoImageStashManifestFileName = "manifest.json"
    private static let legacyTemporaryRootComponents = ["系统", "暂存", "NodeMarkdownImages"]

    static func formalScope(sourceFile: String, notebookFileURL: URL) -> NodeMarkdownImageScope {
        .lessonChapter(sourceFile: sourceFile, notebookFileURL: notebookFileURL)
    }

    static func formalScopeForCurrentLessonChapter(fileURL: URL) -> NodeMarkdownImageScope? {
        guard let workspaceRoot = try? ArchiveStorage.ensureWorkspace() else { return nil }
        let teachingPlanRoot = workspaceRoot
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent(ArchiveStorage.teachingPlanFolderName, isDirectory: true)
            .standardizedFileURL
        let standardizedFileURL = fileURL.standardizedFileURL
        guard standardizedFileURL.path.hasPrefix(teachingPlanRoot.path + "/") else { return nil }
        let pathExtension = standardizedFileURL.pathExtension.lowercased()
        guard pathExtension == "csv" || pathExtension == "nodemarkdown" || pathExtension == "md" else { return nil }
        let sourceFile = relativePathString(from: teachingPlanRoot, to: standardizedFileURL)
        guard !sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return formalScope(sourceFile: sourceFile, notebookFileURL: fileURL)
    }

    static func temporaryScope(packageID: String, notebookFileURL: URL) -> NodeMarkdownImageScope {
        .h3Temporary(packageID: packageID, notebookFileURL: notebookFileURL)
    }

    static func location(for scope: NodeMarkdownImageScope) -> NodeMarkdownImageResourceLocation? {
        switch scope {
        case .lessonChapter(let sourceFile, let notebookFileURL):
            guard let sourceFileURL = resolveSourceFileURL(sourceFile, notebookFileURL: notebookFileURL) else {
                return nil
            }
            let markdownBaseDirectoryURL = notebookFileURL.deletingLastPathComponent()
            let rootDirectoryURL = sourceFileURL.deletingPathExtension()
            let picDirectoryURL = rootDirectoryURL.appendingPathComponent(picDirectoryName, isDirectory: true)
            return NodeMarkdownImageResourceLocation(
                scope: scope,
                rootDirectoryURL: rootDirectoryURL,
                picDirectoryURL: picDirectoryURL,
                markdownBaseDirectoryURL: markdownBaseDirectoryURL,
                relativePicDirectoryPath: relativePathString(from: markdownBaseDirectoryURL, to: picDirectoryURL)
            )

        case .h3Temporary(let packageID, let notebookFileURL):
            let markdownBaseDirectoryURL = notebookFileURL.deletingLastPathComponent()
            let sanitizedID = sanitizedPathComponent(packageID.isEmpty ? UUID().uuidString : packageID)
            let rootDirectoryURL = temporaryRootURL(notebookFileURL: notebookFileURL)
                .appendingPathComponent(sanitizedID, isDirectory: true)
            let picDirectoryURL = rootDirectoryURL.appendingPathComponent(picDirectoryName, isDirectory: true)
            return NodeMarkdownImageResourceLocation(
                scope: scope,
                rootDirectoryURL: rootDirectoryURL,
                picDirectoryURL: picDirectoryURL,
                markdownBaseDirectoryURL: markdownBaseDirectoryURL,
                relativePicDirectoryPath: relativePathString(from: markdownBaseDirectoryURL, to: picDirectoryURL)
            )
        }
    }

    static func resolveSourceFileURL(_ rawSourceFile: String, notebookFileURL: URL) -> URL? {
        let trimmed = rawSourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let asPath = NSString(string: trimmed)
        if asPath.isAbsolutePath {
            return URL(fileURLWithPath: trimmed)
        }
        if trimmed.hasPrefix("档案/") {
            let suffix = String(trimmed.dropFirst("档案/".count))
            guard !suffix.isEmpty, let archiveRoot = try? ArchiveStorage.ensureArchiveRoot() else { return nil }
            return archiveRoot.appendingPathComponent(suffix, isDirectory: false)
        }
        if let workspaceRoot = try? ArchiveStorage.ensureWorkspace() {
            return workspaceRoot
                .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
                .appendingPathComponent(ArchiveStorage.teachingPlanFolderName, isDirectory: true)
                .appendingPathComponent(trimmed, isDirectory: false)
        }
        return notebookFileURL.deletingLastPathComponent().appendingPathComponent(trimmed)
    }

    static func markdownImageToken(
        relativePath: String,
        altText: String = "image",
        width: Int = defaultDisplayWidth
    ) -> String {
        let safeAlt = altText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "]", with: "\\]")
        return "![\(safeAlt)](\(relativePath)){width=\(max(1, width))}"
    }

    static func parseImageTokens(in text: String) -> [NodeMarkdownImageToken] {
        parseMarkdownImageTokens(in: text) + parseHTMLImageTokens(in: text)
    }

    static func referencedRelativePaths(in text: String) -> Set<String> {
        Set(parseImageTokens(in: text).map(\.relativePath))
    }

    static func resolvedImageURL(relativePath: String, notebookFileURL: URL) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.isFileURL {
            return url
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        return notebookFileURL.deletingLastPathComponent().appendingPathComponent(trimmed)
    }

    static func relativePathString(from baseDir: URL, to fileURL: URL) -> String {
        let baseComponents = baseDir.standardizedFileURL.pathComponents
        let targetComponents = fileURL.standardizedFileURL.pathComponents
        var index = 0
        while index < min(baseComponents.count, targetComponents.count),
              baseComponents[index] == targetComponents[index] {
            index += 1
        }
        let up = Array(repeating: "..", count: max(0, baseComponents.count - index))
        let down = targetComponents[index...]
        return (up + down).joined(separator: "/")
    }

    static func referencedImageFilePaths(in document: NodeMarkdownDocument, notebookFileURL: URL) -> Set<String> {
        var results: Set<String> = []
        for node in document.nodes {
            for token in parseImageTokens(in: node.text) {
                guard let resolvedURL = resolvedImageURL(relativePath: token.relativePath, notebookFileURL: notebookFileURL) else {
                    continue
                }
                results.insert(resolvedURL.standardizedFileURL.path)
            }
        }
        return results
    }

    @discardableResult
    static func restoreReferencedStashedImages(
        currentDocument: NodeMarkdownDocument,
        notebookFileURL: URL
    ) -> Int {
        let referencedRefs = referencedImageFilePaths(in: currentDocument, notebookFileURL: notebookFileURL)
        guard !referencedRefs.isEmpty else { return 0 }
        return restoreStashedImages(atOriginalPaths: referencedRefs, notebookFileURL: notebookFileURL)
    }

    /// Only finalize this document's undo stash after its final document write has succeeded.
    /// Referenced images are restored first, so a stale editor callback cannot permanently
    /// remove an asset that is still present in the persisted document.
    static func finalizeUndoImageStash(
        currentDocument: NodeMarkdownDocument,
        notebookFileURL: URL
    ) {
        restoreReferencedStashedImages(
            currentDocument: currentDocument,
            notebookFileURL: notebookFileURL
        )
        let stashURL = undoImageStashRootURL(notebookFileURL: notebookFileURL)
        try? FileManager.default.removeItem(at: stashURL)
    }

    @discardableResult
    static func deleteRemovedManagedImages(
        previousDocument: NodeMarkdownDocument,
        currentDocument: NodeMarkdownDocument,
        notebookFileURL: URL
    ) -> Int {
        restoreReferencedStashedImages(currentDocument: currentDocument, notebookFileURL: notebookFileURL)
        let previousRefs = referencedImageFilePaths(in: previousDocument, notebookFileURL: notebookFileURL)
        let currentRefs = referencedImageFilePaths(in: currentDocument, notebookFileURL: notebookFileURL)
        let removedRefs = previousRefs.subtracting(currentRefs).filter {
            isDocumentOwnedTemporaryImagePath(
                $0,
                previousDocument: previousDocument,
                currentDocument: currentDocument,
                notebookFileURL: notebookFileURL
            )
        }
        return deleteManagedImageFiles(atPaths: removedRefs, notebookFileURL: notebookFileURL)
    }

    static func isManagedImageURL(_ url: URL, notebookFileURL: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        guard managedImageExtensions.contains(standardizedURL.pathExtension.lowercased()) else { return false }
        let notebookDirectory = notebookFileURL.deletingLastPathComponent().standardizedFileURL
        let temporaryRoot = temporaryRootURL(notebookFileURL: notebookFileURL).standardizedFileURL
        let lessonRoot = lessonPlanRootURL()?.standardizedFileURL
        let isInManagedRoot = isDescendant(standardizedURL, of: notebookDirectory)
            || isDescendant(standardizedURL, of: temporaryRoot)
            || lessonRoot.map { isDescendant(standardizedURL, of: $0) } == true
        guard isInManagedRoot else { return false }
        if isDescendant(standardizedURL, of: undoImageStashRootURL(notebookFileURL: notebookFileURL).standardizedFileURL) {
            return false
        }
        let components = standardizedURL.pathComponents
        if components.contains(picDirectoryName) { return true }
        return containsTemporaryRoot(in: components)
    }

    static func migrateTemporaryImageTokens(
        in packageNodes: [NodeMarkdownNode],
        temporaryPackageID: String,
        formalSourceFileURL: URL,
        sourceTokenBaseDirectoryURL: URL,
        outputTokenBaseDirectoryURL: URL,
        notebookFileURL: URL
    ) throws -> (nodes: [NodeMarkdownNode], migratedCount: Int) {
        let formalPicDirectoryURL = formalSourceFileURL
            .deletingPathExtension()
            .appendingPathComponent(picDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: formalPicDirectoryURL, withIntermediateDirectories: true)

        var result = packageNodes
        var migratedCount = 0
        let temporaryPicPaths = temporaryPicDirectoryURLs(
            packageID: temporaryPackageID,
            notebookFileURL: notebookFileURL
        ).map { $0.standardizedFileURL.path }

        for nodeIndex in result.indices {
            let tokens = parseImageTokens(in: result[nodeIndex].text)
            guard !tokens.isEmpty else { continue }

            var replacements: [(range: NSRange, text: String)] = []
            for token in tokens {
                guard let temporaryImageURL = resolvedImageURL(
                    relativePath: token.relativePath,
                    baseDirectoryURL: sourceTokenBaseDirectoryURL
                ) else { continue }

                let sourceURL = temporaryImageURL.standardizedFileURL
                guard temporaryPicPaths.contains(where: { sourceURL.path.hasPrefix($0 + "/") }) else { continue }
                guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }

                let destinationURL = formalPicDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
                if !FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                }

                let newRelativePath = relativePathString(from: outputTokenBaseDirectoryURL, to: destinationURL)
                let replacement = markdownImageToken(
                    relativePath: newRelativePath,
                    altText: token.altText.isEmpty ? "image" : token.altText,
                    width: token.width
                )
                replacements.append((token.sourceRange, replacement))
                migratedCount += 1
            }

            guard !replacements.isEmpty else { continue }
            let mutableText = NSMutableString(string: result[nodeIndex].text)
            for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
                mutableText.replaceCharacters(in: replacement.range, with: replacement.text)
            }
            result[nodeIndex].text = mutableText as String
        }

        return (result, migratedCount)
    }

    private static func resolvedImageURL(relativePath: String, baseDirectoryURL: URL) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.isFileURL {
            return url
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        return baseDirectoryURL.appendingPathComponent(trimmed)
    }

    private static func temporaryRootURL(notebookFileURL: URL) -> URL {
        let baseURL = (try? ArchiveStorage.ensureWorkspace()) ?? notebookFileURL.deletingLastPathComponent()
        return temporaryRootComponents.reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(component, isDirectory: true)
        }
    }

    private static func undoImageStashRootURL(notebookFileURL: URL) -> URL {
        temporaryRootURL(notebookFileURL: notebookFileURL)
            .appendingPathComponent(undoImageStashDirectoryName, isDirectory: true)
            .appendingPathComponent(stableNotebookStashKey(notebookFileURL), isDirectory: true)
    }

    private static func undoImageStashManifestURL(notebookFileURL: URL) -> URL {
        undoImageStashRootURL(notebookFileURL: notebookFileURL)
            .appendingPathComponent(undoImageStashManifestFileName, isDirectory: false)
    }

    private static func legacyTemporaryRootURL(notebookFileURL: URL) -> URL {
        legacyTemporaryRootComponents.reduce(notebookFileURL.deletingLastPathComponent()) { partialURL, component in
            partialURL.appendingPathComponent(component, isDirectory: true)
        }
    }

    private static func stableNotebookStashKey(_ notebookFileURL: URL) -> String {
        // FNV-1a is used only for a stable directory name, not for security.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in notebookFileURL.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func isDocumentOwnedTemporaryImagePath(
        _ filePath: String,
        previousDocument: NodeMarkdownDocument,
        currentDocument: NodeMarkdownDocument,
        notebookFileURL: URL
    ) -> Bool {
        let candidate = URL(fileURLWithPath: filePath).standardizedFileURL
        let undoRoot = undoImageStashRootURL(notebookFileURL: notebookFileURL).standardizedFileURL
        guard !isDescendant(candidate, of: undoRoot) else { return false }

        let packageIDs = Set((previousDocument.nodes + currentDocument.nodes).compactMap { node -> String? in
            guard node.level == 3,
                  node.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let sourceID = node.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            return sourceID.isEmpty ? node.id.uuidString : sourceID
        })
        for packageID in packageIDs {
            for directory in temporaryPicDirectoryURLs(packageID: packageID, notebookFileURL: notebookFileURL) {
                if isDescendant(candidate, of: directory.standardizedFileURL) {
                    return true
                }
            }
        }
        return false
    }

    private static func temporaryPicDirectoryURLs(packageID: String, notebookFileURL: URL) -> [URL] {
        let sanitizedID = sanitizedPathComponent(packageID.isEmpty ? UUID().uuidString : packageID)
        return [
            temporaryRootURL(notebookFileURL: notebookFileURL),
            legacyTemporaryRootURL(notebookFileURL: notebookFileURL)
        ].map {
            $0.appendingPathComponent(sanitizedID, isDirectory: true)
                .appendingPathComponent(picDirectoryName, isDirectory: true)
        }
    }

    fileprivate static func insertedImageRelativePath(
        destinationURL: URL,
        location: NodeMarkdownImageResourceLocation
    ) -> String {
        if case let .lessonChapter(sourceFile, notebookFileURL) = location.scope,
           let portablePath = portableLessonPlanImageRelativePath(
            sourceFile: sourceFile,
            imageFileName: destinationURL.lastPathComponent,
            notebookFileURL: notebookFileURL
           ) {
            return portablePath
        }
        return relativePathString(from: location.markdownBaseDirectoryURL, to: destinationURL)
    }

    private static func portableLessonPlanImageRelativePath(
        sourceFile: String,
        imageFileName: String,
        notebookFileURL: URL
    ) -> String? {
        guard let lessonPlanRoot = lessonPlanRootURL(),
              isDescendant(notebookFileURL.standardizedFileURL, of: lessonPlanRoot.standardizedFileURL) else {
            return nil
        }

        let normalizedSourceFile = sourceFile
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        guard !normalizedSourceFile.isEmpty,
              !NSString(string: normalizedSourceFile).isAbsolutePath,
              !normalizedSourceFile.hasPrefix("档案/") else {
            return nil
        }

        // 母本教案里的图片文本会被复制到学生随堂笔记；这里故意使用和上课时一致的
        // 工作区相对路径，而不是教案文件夹内的短路径，保证两边解析同一张图。
        let sourceWithoutExtension = (normalizedSourceFile as NSString).deletingPathExtension
        return [
            "..",
            "..",
            "..",
            ArchiveStorage.systemFolderName,
            ArchiveStorage.teachingPlanFolderName,
            sourceWithoutExtension,
            picDirectoryName,
            imageFileName
        ].joined(separator: "/")
    }

    private static func lessonPlanRootURL() -> URL? {
        guard let workspaceRoot = try? ArchiveStorage.ensureWorkspace() else { return nil }
        return workspaceRoot
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent(ArchiveStorage.teachingPlanFolderName, isDirectory: true)
    }

    private static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private static func deleteManagedImageFiles(atPaths filePaths: Set<String>, notebookFileURL: URL) -> Int {
        var deletedCount = 0
        for filePath in filePaths {
            let url = URL(fileURLWithPath: filePath)
            guard isManagedImageURL(url, notebookFileURL: notebookFileURL) else { continue }
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if stashManagedImageForUndo(url, notebookFileURL: notebookFileURL) {
                deletedCount += 1
            }
        }
        return deletedCount
    }

    @discardableResult
    private static func stashManagedImageForUndo(_ originalURL: URL, notebookFileURL: URL) -> Bool {
        let original = originalURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: original.path) else { return false }
        let stashRoot = undoImageStashRootURL(notebookFileURL: notebookFileURL)
        let stashID = UUID().uuidString
        let destinationURL = stashRoot
            .appendingPathComponent(stashID, isDirectory: false)
            .appendingPathExtension(original.pathExtension)
        do {
            try FileManager.default.createDirectory(at: stashRoot, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            var manifest = loadUndoImageStashManifest(notebookFileURL: notebookFileURL)
            manifest.records[original.path] = NodeMarkdownUndoImageStashRecord(
                originalPath: original.path,
                stashPath: destinationURL.standardizedFileURL.path,
                stashedAt: Date()
            )
            // Copy first. The original remains authoritative until the recovery manifest is
            // durably written; any failure before the final remove leaves the source intact.
            try FileManager.default.copyItem(at: original, to: destinationURL)
            try saveUndoImageStashManifest(manifest, notebookFileURL: notebookFileURL)
            do {
                try FileManager.default.removeItem(at: original)
            } catch {
                try? FileManager.default.removeItem(at: destinationURL)
                manifest.records.removeValue(forKey: original.path)
                try? saveUndoImageStashManifest(manifest, notebookFileURL: notebookFileURL)
                throw error
            }
            return true
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            return false
        }
    }

    @discardableResult
    private static func restoreStashedImages(atOriginalPaths originalPaths: Set<String>, notebookFileURL: URL) -> Int {
        guard !originalPaths.isEmpty else { return 0 }
        var manifest = loadUndoImageStashManifest(notebookFileURL: notebookFileURL)
        var restoredCount = 0
        var changed = false
        for path in originalPaths {
            let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            guard let record = manifest.records[standardizedPath] ?? manifest.records[path] else { continue }
            let originalURL = URL(fileURLWithPath: record.originalPath).standardizedFileURL
            let stashURL = URL(fileURLWithPath: record.stashPath).standardizedFileURL
            guard FileManager.default.fileExists(atPath: stashURL.path) else {
                manifest.records.removeValue(forKey: record.originalPath)
                manifest.records.removeValue(forKey: standardizedPath)
                changed = true
                continue
            }
            do {
                try FileManager.default.createDirectory(
                    at: originalURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if FileManager.default.fileExists(atPath: originalURL.path) {
                    try FileManager.default.removeItem(at: stashURL)
                } else {
                    try FileManager.default.moveItem(at: stashURL, to: originalURL)
                    restoredCount += 1
                }
                manifest.records.removeValue(forKey: record.originalPath)
                manifest.records.removeValue(forKey: standardizedPath)
                changed = true
            } catch {
                continue
            }
        }
        if changed {
            try? saveUndoImageStashManifest(manifest, notebookFileURL: notebookFileURL)
        }
        return restoredCount
    }

    private static func loadUndoImageStashManifest(notebookFileURL: URL) -> NodeMarkdownUndoImageStashManifest {
        let manifestURL = undoImageStashManifestURL(notebookFileURL: notebookFileURL)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(NodeMarkdownUndoImageStashManifest.self, from: data) else {
            return NodeMarkdownUndoImageStashManifest(records: [:])
        }
        return manifest
    }

    private static func saveUndoImageStashManifest(
        _ manifest: NodeMarkdownUndoImageStashManifest,
        notebookFileURL: URL
    ) throws {
        let manifestURL = undoImageStashManifestURL(notebookFileURL: notebookFileURL)
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    private static func containsTemporaryRoot(in pathComponents: [String]) -> Bool {
        guard pathComponents.count >= temporaryRootComponents.count else { return false }
        let count = temporaryRootComponents.count
        for index in 0...(pathComponents.count - count) {
            if Array(pathComponents[index..<(index + count)]) == temporaryRootComponents {
                return true
            }
        }
        return false
    }

    private static func parseMarkdownImageTokens(in text: String) -> [NodeMarkdownImageToken] {
        let nsText = text as NSString
        var results: [NodeMarkdownImageToken] = []
        var cursor = 0

        while cursor < nsText.length {
            let marker = nsText.range(
                of: "![",
                options: [],
                range: NSRange(location: cursor, length: nsText.length - cursor)
            )
            guard marker.location != NSNotFound else { break }
            let tokenStart = marker.location
            guard let altEnd = firstUnescapedCharacter("]", in: nsText, from: tokenStart + 2),
                  altEnd + 1 < nsText.length,
                  nsText.character(at: altEnd + 1) == 0x28 else {
                cursor = tokenStart + marker.length
                continue
            }

            let destinationStart = altEnd + 2
            var depth = 1
            var index = destinationStart
            var destinationEnd: Int?
            while index < nsText.length {
                let character = nsText.character(at: index)
                if character == 0x0A || character == 0x0D { break }
                if character == 0x5C {
                    index += 2
                    continue
                }
                if character == 0x28 {
                    depth += 1
                } else if character == 0x29 {
                    depth -= 1
                    if depth == 0 {
                        destinationEnd = index
                        break
                    }
                }
                index += 1
            }
            guard let destinationEnd else {
                cursor = tokenStart + marker.length
                continue
            }

            let rawDestination = nsText.substring(
                with: NSRange(location: destinationStart, length: destinationEnd - destinationStart)
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let relativePath: String
            if rawDestination.hasPrefix("<"), rawDestination.hasSuffix(">"), rawDestination.count >= 2 {
                relativePath = String(rawDestination.dropFirst().dropLast())
            } else {
                relativePath = rawDestination
            }
            guard !relativePath.isEmpty else {
                cursor = destinationEnd + 1
                continue
            }

            var tokenEnd = destinationEnd + 1
            var width = defaultDisplayWidth
            if tokenEnd < nsText.length {
                let suffixRange = NSRange(location: tokenEnd, length: nsText.length - tokenEnd)
                if let widthRegex = try? NSRegularExpression(pattern: #"^\{\s*width\s*=\s*(\d+)\s*\}"#),
                   let match = widthRegex.firstMatch(in: text, range: suffixRange),
                   match.range.location == tokenEnd {
                    width = Int(nsText.substring(with: match.range(at: 1))) ?? defaultDisplayWidth
                    tokenEnd = NSMaxRange(match.range)
                }
            }

            let sourceRange = NSRange(location: tokenStart, length: tokenEnd - tokenStart)
            results.append(
                NodeMarkdownImageToken(
                    altText: nsText.substring(
                        with: NSRange(location: tokenStart + 2, length: altEnd - tokenStart - 2)
                    ),
                    relativePath: relativePath,
                    width: width,
                    sourceRange: sourceRange,
                    sourceText: nsText.substring(with: sourceRange)
                )
            )
            cursor = tokenEnd
        }
        return results
    }

    private static func firstUnescapedCharacter(
        _ target: Character,
        in text: NSString,
        from start: Int
    ) -> Int? {
        guard let targetValue = target.utf16.first else { return nil }
        var index = start
        while index < text.length {
            let character = text.character(at: index)
            if character == 0x0A || character == 0x0D { return nil }
            if character == 0x5C {
                index += 2
                continue
            }
            if character == targetValue { return index }
            index += 1
        }
        return nil
    }

    private static func parseHTMLImageTokens(in text: String) -> [NodeMarkdownImageToken] {
        let pattern = #"<img\s+([^>\n]*)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: fullRange).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let attributes = nsText.substring(with: match.range(at: 1))
            guard let relativePath = htmlAttribute("src", in: attributes), !relativePath.isEmpty else {
                return nil
            }
            let width = htmlAttribute("width", in: attributes).flatMap(Int.init) ?? defaultDisplayWidth
            return NodeMarkdownImageToken(
                altText: htmlAttribute("alt", in: attributes) ?? "image",
                relativePath: relativePath,
                width: width,
                sourceRange: match.range,
                sourceText: nsText.substring(with: match.range)
            )
        }
    }

    private static func htmlAttribute(_ name: String, in attributes: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"\b"# + escapedName + #"\s*=\s*["']([^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsAttributes = attributes as NSString
        let range = NSRange(location: 0, length: nsAttributes.length)
        guard let match = regex.firstMatch(in: attributes, range: range), match.numberOfRanges > 1 else {
            return nil
        }
        return nsAttributes.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizedPathComponent(_ rawValue: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let pieces = rawValue.components(separatedBy: invalid)
        let sanitized = pieces.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? UUID().uuidString : sanitized
    }
}

#if os(macOS)
enum NodeMarkdownImageAssetService {
    /// 普通 Markdown 的图片统一落入工作区“系统/Markdown图片”。
    /// 正文只保存相对于当前 Markdown 文件目录的链接，继续保持文件可迁移。
    static func insertMarkdownImage(
        selectedURL: URL,
        markdownDirectoryURL: URL
    ) -> NodeMarkdownImageInsertResult? {
        guard let workspaceRoot = try? ArchiveStorage.ensureWorkspace() else { return nil }
        let imageDirectoryURL = workspaceRoot
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent("Markdown图片", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: imageDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }

        guard let sourceData = try? Data(contentsOf: selectedURL) else { return nil }
        let fileName = importedImageFileName(for: sourceData)
        let destinationURL = imageDirectoryURL.appendingPathComponent(fileName)
        if !isUsableExistingImportedImage(at: destinationURL) {
            guard importCompressedImage(
                sourceURL: selectedURL,
                destinationURL: destinationURL,
                maxPixel: NodeMarkdownImageResourceManager.maxImportedPixel,
                maxBytes: NodeMarkdownImageResourceManager.maxImportedBytes
            ) else {
                return nil
            }
        }

        let relativePath = NodeMarkdownImageResourceManager.relativePathString(
            from: markdownDirectoryURL,
            to: destinationURL
        )
        let token = NodeMarkdownImageResourceManager.markdownImageToken(relativePath: relativePath)
        return NodeMarkdownImageInsertResult(htmlSnippet: token, relativePath: relativePath)
    }

    static func hasPastedImage() -> Bool {
        pastedImageURLFromFinder() != nil || pastedImageFromPasteboard() != nil
    }

    static func pastedImageURL() -> URL? {
        pastedImageURLFromFinder() ?? pastedImageTemporaryURL()
    }

    static func isTemporaryPastedImageURL(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        let temporaryDirectory = FileManager.default.temporaryDirectory.standardizedFileURL.path
        return standardizedURL.deletingLastPathComponent().path == temporaryDirectory
            && standardizedURL.lastPathComponent.hasPrefix("nodemarkdown-paste-")
            && standardizedURL.pathExtension.lowercased() == "png"
    }

    static func pastedImageURLFromFinder() -> URL? {
        let pasteboard = NSPasteboard.general
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return nil
        }
        return urls.first(where: { $0.isFileURL && isImageFileURL($0) })
    }

    private static func pastedImageFromPasteboard() -> NSImage? {
        let pasteboard = NSPasteboard.general
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            return image
        }
        guard let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) else {
            return nil
        }
        return NSImage(data: data)
    }

    private static func pastedImageTemporaryURL() -> URL? {
        guard let image = pastedImageFromPasteboard(),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nodemarkdown-paste-\(UUID().uuidString).png")
        do {
            try pngData.write(to: temporaryURL, options: .atomic)
            return temporaryURL
        } catch {
            return nil
        }
    }

    static func isImageFileURL(_ url: URL) -> Bool {
        let allowed = Set(["png", "jpg", "jpeg", "heic", "heif", "gif", "bmp", "tiff", "webp"])
        return allowed.contains(url.pathExtension.lowercased())
    }

    static func insertImage(
        selectedURL: URL,
        sourceFile: String,
        notebookFileURL: URL
    ) -> NodeMarkdownImageInsertResult? {
        let scope = NodeMarkdownImageResourceManager.formalScope(
            sourceFile: sourceFile,
            notebookFileURL: notebookFileURL
        )
        return insertImage(selectedURL: selectedURL, scope: scope)
    }

    static func insertTransparentPNGImage(
        selectedURL: URL,
        sourceFile: String,
        notebookFileURL: URL
    ) -> NodeMarkdownImageInsertResult? {
        let scope = NodeMarkdownImageResourceManager.formalScope(
            sourceFile: sourceFile,
            notebookFileURL: notebookFileURL
        )
        return insertTransparentPNGImage(selectedURL: selectedURL, scope: scope)
    }

    static func insertTransparentPNGImage(
        selectedURL: URL,
        scope: NodeMarkdownImageScope
    ) -> NodeMarkdownImageInsertResult? {
        guard let location = NodeMarkdownImageResourceManager.location(for: scope) else {
            return nil
        }
        try? FileManager.default.createDirectory(at: location.picDirectoryURL, withIntermediateDirectories: true)

        guard let sourceData = try? Data(contentsOf: selectedURL) else { return nil }
        let fileName = importedImageFileName(for: sourceData, pathExtension: "png")
        let destinationURL = location.picDirectoryURL.appendingPathComponent(fileName)

        if !isUsableExistingImportedImage(at: destinationURL) {
            do {
                try sourceData.write(to: destinationURL, options: .atomic)
                guard isUsableExistingImportedImage(at: destinationURL) else {
                    try? FileManager.default.removeItem(at: destinationURL)
                    return nil
                }
            } catch {
                return nil
            }
        }

        let relativePath = NodeMarkdownImageResourceManager.insertedImageRelativePath(
            destinationURL: destinationURL,
            location: location
        )
        let token = NodeMarkdownImageResourceManager.markdownImageToken(relativePath: relativePath)
        return NodeMarkdownImageInsertResult(htmlSnippet: token, relativePath: relativePath)
    }

    static func insertImage(
        selectedURL: URL,
        scope: NodeMarkdownImageScope
    ) -> NodeMarkdownImageInsertResult? {
        guard let location = NodeMarkdownImageResourceManager.location(for: scope) else {
            return nil
        }
        try? FileManager.default.createDirectory(at: location.picDirectoryURL, withIntermediateDirectories: true)

        guard let sourceData = try? Data(contentsOf: selectedURL) else { return nil }
        let fileName = importedImageFileName(for: sourceData)
        let destinationURL = location.picDirectoryURL.appendingPathComponent(fileName)

        if !isUsableExistingImportedImage(at: destinationURL) {
            guard importCompressedImage(
                sourceURL: selectedURL,
                destinationURL: destinationURL,
                maxPixel: NodeMarkdownImageResourceManager.maxImportedPixel,
                maxBytes: NodeMarkdownImageResourceManager.maxImportedBytes
            ) else {
                return nil
            }
        }

        let relativePath = NodeMarkdownImageResourceManager.insertedImageRelativePath(
            destinationURL: destinationURL,
            location: location
        )
        let token = NodeMarkdownImageResourceManager.markdownImageToken(relativePath: relativePath)
        return NodeMarkdownImageInsertResult(htmlSnippet: token, relativePath: relativePath)
    }

    static func resolveSourceFileURL(_ rawSourceFile: String, notebookFileURL: URL) -> URL? {
        NodeMarkdownImageResourceManager.resolveSourceFileURL(rawSourceFile, notebookFileURL: notebookFileURL)
    }

    static func parseImageTokens(in text: String) -> [NodeMarkdownImageToken] {
        NodeMarkdownImageResourceManager.parseImageTokens(in: text)
    }

    static func referencedRelativePaths(in text: String) -> Set<String> {
        NodeMarkdownImageResourceManager.referencedRelativePaths(in: text)
    }

    static func resolvedImageURL(relativePath: String, notebookFileURL: URL) -> URL? {
        NodeMarkdownImageResourceManager.resolvedImageURL(relativePath: relativePath, notebookFileURL: notebookFileURL)
    }

    private static func importedImageFileName(for sourceData: Data, pathExtension: String = "jpg") -> String {
        let digest = SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()
        return "img-\(digest.prefix(16)).\(pathExtension)"
    }

    private static func isUsableExistingImportedImage(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue > 0,
              fileSize.intValue <= NodeMarkdownImageResourceManager.maxImportedBytes,
              let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0,
              CGImageSourceCreateImageAtIndex(imageSource, 0, nil) != nil else {
            return false
        }
        return true
    }

    private static func importCompressedImage(
        sourceURL: URL,
        destinationURL: URL,
        maxPixel: CGFloat,
        maxBytes: Int
    ) -> Bool {
        guard let encodedData = compressedJPEGData(
            sourceURL: sourceURL,
            maxPixel: maxPixel,
            maxBytes: maxBytes
        ) else {
            return false
        }

        do {
            // Data.atomic writes a sibling temporary file and replaces the destination only
            // after the new bytes are complete. Never remove the old image first.
            try encodedData.write(to: destinationURL, options: .atomic)
            return isUsableExistingImportedImage(at: destinationURL)
        } catch {
            return false
        }
    }

    private static func compressedJPEGData(
        sourceURL: URL,
        maxPixel: CGFloat,
        maxBytes: Int
    ) -> Data? {
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let originalImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        let longestEdge = CGFloat(max(originalImage.width, originalImage.height))
        let initialPixel = min(maxPixel, longestEdge)
        let pixelCandidates = Array(Set([
            Int(initialPixel.rounded()),
            896,
            768,
            640,
            512,
            384,
            320
        ])).filter { $0 > 0 && CGFloat($0) <= initialPixel }.sorted(by: >)
        let qualityCandidates: [CGFloat] = [0.82, 0.74, 0.66, 0.58, 0.50, 0.42]

        var smallestData: Data?
        for pixel in pixelCandidates {
            guard let image = resizedImage(
                imageSource: imageSource,
                originalImage: originalImage,
                maxPixel: CGFloat(pixel),
                originalLongestEdge: longestEdge
            ) else { continue }

            for quality in qualityCandidates {
                guard let data = jpegData(from: image, quality: quality) else { continue }
                if data.count <= maxBytes {
                    return data
                }
                if smallestData == nil || data.count < (smallestData?.count ?? Int.max) {
                    smallestData = data
                }
            }
        }

        return smallestData?.count ?? Int.max <= maxBytes ? smallestData : nil
    }

    private static func resizedImage(
        imageSource: CGImageSource,
        originalImage: CGImage,
        maxPixel: CGFloat,
        originalLongestEdge: CGFloat
    ) -> CGImage? {
        guard originalLongestEdge > maxPixel else {
            return originalImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel),
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
    }

    private static func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
#endif
