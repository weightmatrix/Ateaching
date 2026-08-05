// PIPELINE MARKER: NodeMarkdown legacy pipeline (TeachingPrint image support).
import Foundation
import CoreGraphics

struct TeachingImageLayoutInfo: Sendable, Hashable {
    var sourceBlockID: UUID
    var rawSource: String
    var resolvedURL: URL?
    var estimatedSize: CGSize
}

enum TeachingImageRenderService {
    private static var sizeCache: [String: CGSize] = [:]
    private static let cacheQueue = DispatchQueue(label: "com.ateaching.image-cache", qos: .utility)

    static func collectLayoutInfos(
        from renderingDocument: TeachingRenderingDocument,
        baseURL: URL
    ) -> [TeachingImageLayoutInfo] {
        renderingDocument.resources.compactMap { ref in
            guard ref.kind == .image else { return nil }
            let source = extractPrimaryImageSource(from: ref.rawValue)
            let resolvedURL = resolveURL(from: source, baseURL: baseURL)
            let estimatedSize = estimateSize(for: source)
            return TeachingImageLayoutInfo(
                sourceBlockID: ref.sourceBlockID,
                rawSource: source,
                resolvedURL: resolvedURL,
                estimatedSize: estimatedSize
            )
        }
    }

    private static func extractPrimaryImageSource(from text: String) -> String {
        if let range = text.range(of: #"!\[[^\]]*\]\(([^)]+)\)"#, options: .regularExpression) {
            let match = String(text[range])
            if let start = match.firstIndex(of: "("), let end = match.lastIndex(of: ")"), start < end {
                return String(match[match.index(after: start)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let range = text.range(of: #"src\s*=\s*["']([^"']+)["']"#, options: .regularExpression) {
            let match = String(text[range])
            if let quote = match.firstIndex(of: "\""), let end = match[match.index(after: quote)...].firstIndex(of: "\""), quote < end {
                return String(match[match.index(after: quote)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let quote = match.firstIndex(of: "'"), let end = match[match.index(after: quote)...].firstIndex(of: "'"), quote < end {
                return String(match[match.index(after: quote)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolveURL(from rawSource: String, baseURL: URL) -> URL? {
        guard !rawSource.isEmpty else { return nil }
        if rawSource.hasPrefix("http://") || rawSource.hasPrefix("https://") {
            return URL(string: rawSource)
        }
        if rawSource.hasPrefix("file://") {
            return URL(string: rawSource)
        }
        return URL(fileURLWithPath: rawSource, relativeTo: baseURL).standardizedFileURL
    }

    private static func estimateSize(for source: String) -> CGSize {
        if let cached = cacheQueue.sync(execute: { sizeCache[source] }) {
            return cached
        }
        let width = 420.0
        let height = 240.0
        let size = CGSize(width: width, height: height)
        cacheQueue.sync {
            sizeCache[source] = size
        }
        return size
    }
}
