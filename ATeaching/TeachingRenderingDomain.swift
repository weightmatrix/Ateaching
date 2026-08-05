// PIPELINE MARKER: NodeMarkdown legacy pipeline (TeachingPrint rendering domain).
import Foundation

enum TeachingRenderingBlockKind: String, Sendable {
    case heading1
    case heading2
    case heading3
    case heading4
    case heading5
    case heading6
    case body
    case comment
}

struct TeachingRenderingStyleToken: Sendable, Hashable {
    var level: Int
    var fontName: String
    var fontSize: Double
    var isBold: Bool
    var hasBackgroundBar: Bool
    var paragraphSpacingBefore: Double
    var paragraphSpacingAfter: Double
    var peerLineSpacing: Double
}

struct TeachingRenderingBlock: Sendable, Hashable {
    var id: UUID
    var kind: TeachingRenderingBlockKind
    var level: Int
    var text: String
    var sourceID: String
    var sourceFile: String
    var styleToken: TeachingRenderingStyleToken
}

struct TeachingRenderingResourceRef: Sendable, Hashable {
    enum Kind: String, Sendable {
        case image
        case formula
    }

    var kind: Kind
    var sourceBlockID: UUID
    var rawValue: String
}

struct TeachingRenderingDocument: Sendable, Hashable {
    var blocks: [TeachingRenderingBlock]
    var resources: [TeachingRenderingResourceRef]
}

enum TeachingRenderingDomainBuilder {
    static func build(
        from document: NodeMarkdownDocument,
        style: NodeMarkdownDocumentStyle
    ) -> TeachingRenderingDocument {
        let blocks = document.nodes.map { node in
            let level = max(1, min(12, node.level))
            let roleStyle = style.style(forLevel: level)
            return TeachingRenderingBlock(
                id: node.id,
                kind: mapKind(level: level),
                level: level,
                text: node.text,
                sourceID: node.sourceID,
                sourceFile: node.sourceFile,
                styleToken: .init(
                    level: level,
                    fontName: roleStyle.fontName,
                    fontSize: roleStyle.fontSize,
                    isBold: roleStyle.isBold,
                    hasBackgroundBar: roleStyle.hasBackgroundBar,
                    paragraphSpacingBefore: roleStyle.paragraphSpacingBefore,
                    paragraphSpacingAfter: roleStyle.paragraphSpacingAfter,
                    peerLineSpacing: roleStyle.peerLineSpacing
                )
            )
        }
        let resources = collectResources(from: blocks)
        return TeachingRenderingDocument(blocks: blocks, resources: resources)
    }

    private static func mapKind(level: Int) -> TeachingRenderingBlockKind {
        switch level {
        case 1: return .heading1
        case 2: return .heading2
        case 3: return .heading3
        case 4: return .heading4
        case 5: return .heading5
        case 6: return .heading6
        case 12: return .comment
        default: return .body
        }
    }

    private static func collectResources(from blocks: [TeachingRenderingBlock]) -> [TeachingRenderingResourceRef] {
        var refs: [TeachingRenderingResourceRef] = []
        refs.reserveCapacity(blocks.count)
        for block in blocks {
            let text = block.text
            if text.contains("![](") || text.contains("<img") {
                refs.append(.init(kind: .image, sourceBlockID: block.id, rawValue: text))
            }
            if text.contains("$$") || text.contains("\\(") || text.contains("\\[") {
                refs.append(.init(kind: .formula, sourceBlockID: block.id, rawValue: text))
            }
        }
        return refs
    }
}

