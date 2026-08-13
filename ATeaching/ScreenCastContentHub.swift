import Foundation
import SwiftUI
import Combine

extension Notification.Name {
    static let screenCastRequestedKindsDidChange = Notification.Name("ScreenCastRequestedKindsDidChange")
}

@MainActor
final class ScreenCastContentHub: ObservableObject {
    static let shared = ScreenCastContentHub()

    @Published private(set) var teachingSnapshot: ScreenCastDocumentSnapshot?
    @Published private(set) var markdownSnapshot: ScreenCastDocumentSnapshot?

    private var revisions: [ScreenCastContentKind: UInt64] = [:]
    private var imageCache: [String: (modificationDate: Date?, dataURI: String)] = [:]
    private(set) var requestedKinds: Set<ScreenCastContentKind> = []

    func isRequested(_ kind: ScreenCastContentKind) -> Bool {
        requestedKinds.contains(kind)
    }

    func setRequestedKinds(_ kinds: Set<ScreenCastContentKind>) {
        guard requestedKinds != kinds else { return }
        let newlyRequested = kinds.subtracting(requestedKinds)
        requestedKinds = kinds
        if newlyRequested.contains(.teaching) { teachingSnapshot = nil }
        if newlyRequested.contains(.markdown) { markdownSnapshot = nil }
        NotificationCenter.default.post(name: .screenCastRequestedKindsDidChange, object: nil)
    }

    func publishNodeMarkdown(
        document: NodeMarkdownDocument,
        style: NodeMarkdownDocumentStyle,
        title: String,
        baseURL: URL?
    ) {
        let rows = NodeMarkdownHTMLBuilder.buildRows(document: document, style: style)
        let html = NodeMarkdownHTMLBuilder.documentHTML(
            initialRowsHTML: rows,
            baseURL: baseURL,
            inlineAssets: true
        )
        publish(kind: .teaching, title: title, html: inlineLocalImages(in: html, baseURL: baseURL))
    }

    func publishNodeMarkdownRows(_ rows: String, title: String, baseURL: URL?) {
        let html = NodeMarkdownHTMLBuilder.documentHTML(
            initialRowsHTML: rows,
            baseURL: baseURL,
            inlineAssets: true
        )
        publish(kind: .teaching, title: title, html: inlineLocalImages(in: html, baseURL: baseURL))
    }

    func publishMarkdown(
        source: String,
        style: MarkdownDocumentStyle,
        preferredScheme: ColorScheme?,
        title: String,
        baseURL: URL?
    ) {
        let html = MarkdownExportRenderer.renderedHTML(
            source: source,
            style: style,
            preferredScheme: preferredScheme
        )
        publish(kind: .markdown, title: title, html: inlineLocalImages(in: html, baseURL: baseURL))
    }

    func snapshot(for kind: ScreenCastContentKind) -> ScreenCastDocumentSnapshot? {
        switch kind {
        case .teaching: teachingSnapshot
        case .markdown: markdownSnapshot
        }
    }

    private func publish(kind: ScreenCastContentKind, title: String, html: String) {
        let previous = snapshot(for: kind)
        guard previous?.html != html || previous?.title != title else { return }
        let revision = revisions[kind, default: 0] &+ 1
        revisions[kind] = revision
        let snapshot = ScreenCastDocumentSnapshot(kind: kind, title: title, html: html, revision: revision)
        switch kind {
        case .teaching: teachingSnapshot = snapshot
        case .markdown: markdownSnapshot = snapshot
        }
    }

    private func inlineLocalImages(in html: String, baseURL: URL?) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"<img\b[^>]*?\bsrc\s*=\s*[\"']([^\"']+)[\"']"#,
            options: [.caseInsensitive]
        ) else { return html }
        let source = html as NSString
        let matches = expression.matches(in: html, range: NSRange(location: 0, length: source.length))
        guard matches.isEmpty == false else { return html }
        let mutable = NSMutableString(string: html)
        for match in matches.reversed() where match.numberOfRanges > 1 {
            let range = match.range(at: 1)
            let raw = source.substring(with: range)
            guard raw.hasPrefix("data:") == false,
                  raw.hasPrefix("http://") == false,
                  raw.hasPrefix("https://") == false,
                  let url = localImageURL(raw, baseURL: baseURL),
                  let dataURI = imageDataURI(for: url) else { continue }
            mutable.replaceCharacters(in: range, with: dataURI)
        }
        return mutable as String
    }

    private func localImageURL(_ raw: String, baseURL: URL?) -> URL? {
        let decoded = raw.removingPercentEncoding ?? raw
        if decoded.hasPrefix("file://") { return URL(string: decoded) }
        guard let baseURL else { return nil }
        return URL(fileURLWithPath: decoded, relativeTo: baseURL).standardizedFileURL
    }

    private func imageDataURI(for url: URL) -> String? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modificationDate = attributes?[.modificationDate] as? Date
        if let cached = imageCache[url.path], cached.modificationDate == modificationDate {
            return cached.dataURI
        }
        guard let data = try? Data(contentsOf: url), data.isEmpty == false else { return nil }
        let mimeType: String
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": mimeType = "image/jpeg"
        case "gif": mimeType = "image/gif"
        case "webp": mimeType = "image/webp"
        case "heic", "heif": mimeType = "image/heic"
        default: mimeType = "image/png"
        }
        let value = "data:\(mimeType);base64,\(data.base64EncodedString())"
        imageCache[url.path] = (modificationDate, value)
        return value
    }
}

@MainActor
final class ScreenCastAnnotationHub: ObservableObject {
    static let shared = ScreenCastAnnotationHub()
    @Published fileprivate(set) var strokes: [ScreenCastStroke] = []

    func replace(with strokes: [ScreenCastStroke]) {
        self.strokes = strokes
    }
}
