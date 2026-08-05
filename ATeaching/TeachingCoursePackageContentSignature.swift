import CryptoKit
import Foundation

// MARK: - H3包有效内容签名 - 只比较用户能修改的结构与文字

enum TeachingCoursePackageContentSignature {
    private static let versionPrefix = "semantic-v1:"
    private static let persistenceVersionPrefix = "persistence-v1:"
    private struct SemanticNode: Codable {
        var level: Int
        var text: String
    }

    static func digest(_ packageNodes: [NodeMarkdownNode]) -> String {
        let cleaned = NodeMarkdownPackageCleaner.cleanPackage(packageNodes)
        let semanticNodes = cleaned.map { node in
            SemanticNode(
                level: node.level,
                text: node.text.replacingOccurrences(of: "\r\n", with: "\n")
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(semanticNodes)) ?? Data()
        let hash = SHA256.hash(data: data)
        return versionPrefix + hash.map { String(format: "%02x", $0) }.joined()
    }

    /// 新包落盘后，随堂笔记与母本会分别保存“相对于自身目录”的图片链接。
    /// 两段链接文字可以不同，但只要解析到同一张图片，就代表同一份包内容。
    /// 此签名只用于落盘复核；脏包判断仍使用原始语义签名，避免掩盖真实正文改动。
    static func persistenceDigest(
        _ packageNodes: [NodeMarkdownNode],
        documentFileURL: URL
    ) -> String {
        let cleaned = NodeMarkdownPackageCleaner.cleanPackage(packageNodes)
        let semanticNodes = cleaned.map { node in
            SemanticNode(
                level: node.level,
                text: canonicalizedImageReferences(
                    in: node.text.replacingOccurrences(of: "\r\n", with: "\n"),
                    documentFileURL: documentFileURL
                )
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(semanticNodes)) ?? Data()
        let hash = SHA256.hash(data: data)
        return persistenceVersionPrefix + hash.map { String(format: "%02x", $0) }.joined()
    }

    static func isCurrentVersionDigest(_ value: String?) -> Bool {
        value?.hasPrefix(versionPrefix) == true
    }

    static func isCollectableNewPackageRoot(_ node: NodeMarkdownNode) -> Bool {
        guard node.level == 3 else { return false }
        guard !node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return node.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && node.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func packageRanges(in nodes: [NodeMarkdownNode]) -> [(start: Int, end: Int)] {
        NodeMarkdownDocumentIndex(nodes: nodes).packageRanges().map {
            (start: $0.lowerBound, end: $0.upperBound)
        }
    }

    static func packageRange(in nodes: [NodeMarkdownNode], rootID: UUID) -> (start: Int, end: Int)? {
        guard let range = NodeMarkdownDocumentIndex(nodes: nodes).packageRange(rootID: rootID) else { return nil }
        return (range.lowerBound, range.upperBound)
    }

    static func packageRange(in nodes: [NodeMarkdownNode], sourceID: String) -> (start: Int, end: Int)? {
        guard !sourceID.isEmpty, let rootID = UUID(uuidString: sourceID) else { return nil }
        return packageRange(in: nodes, rootID: rootID)
    }

    static func digestByH3ID(in document: NodeMarkdownDocument) -> [String: String] {
        var result: [String: String] = [:]
        let index = NodeMarkdownDocumentIndex(nodes: document.nodes)
        for range in index.packageRanges() {
            let root = document.nodes[range.lowerBound]
            result[root.id.uuidString] = digest(Array(document.nodes[range]))
        }
        return result
    }

    private static func canonicalizedImageReferences(
        in text: String,
        documentFileURL: URL
    ) -> String {
        let tokens = NodeMarkdownImageResourceManager.parseImageTokens(in: text)
        guard !tokens.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for token in tokens.sorted(by: { $0.sourceRange.location > $1.sourceRange.location }) {
            guard let imageURL = NodeMarkdownImageResourceManager.resolvedImageURL(
                relativePath: token.relativePath,
                notebookFileURL: documentFileURL
            ) else { continue }
            let canonicalPath = imageURL.standardizedFileURL
                .resolvingSymlinksInPath()
                .path
            let replacement = "<AT_IMAGE path=\"\(canonicalPath)\" alt=\"\(token.altText)\" width=\"\(token.width)\">"
            mutable.replaceCharacters(in: token.sourceRange, with: replacement)
        }
        return mutable as String
    }
}
