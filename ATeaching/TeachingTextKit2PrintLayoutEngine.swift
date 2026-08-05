import Foundation

struct TeachingTextKit2LayoutPlan: Sendable, Hashable {
    var pageSpec: TeachingPrintPageSpec
    var estimatedPageCount: Int
    var measuredLineCount: Int
}

enum TeachingTextKit2PrintLayoutEngine {
    static func buildLayoutPlan(
        renderingDocument: TeachingRenderingDocument,
        styleSheet: TeachingPrintStyleSheet
    ) -> TeachingTextKit2LayoutPlan {
        let paragraphs = renderingDocument.blocks.compactMap { block -> TeachingPrintLayoutParagraph? in
            let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return TeachingPrintLayoutParagraph(
                text: trimmed,
                kind: mapKind(block.kind),
                stripeEnabled: block.styleToken.hasBackgroundBar
            )
        }
        let layout = TeachingPrintLayoutEngine.layout(paragraphs: paragraphs, styleSheet: styleSheet)
        let lineCount = layout.pages.reduce(0) { $0 + $1.lines.count }
        return TeachingTextKit2LayoutPlan(
            pageSpec: styleSheet.pageSpec,
            estimatedPageCount: max(1, layout.pages.count),
            measuredLineCount: lineCount
        )
    }

    private static func mapKind(_ kind: TeachingRenderingBlockKind) -> TeachingPrintLayoutParagraph.Kind {
        switch kind {
        case .heading1: return .heading1
        case .heading2: return .heading2
        case .heading3: return .heading3
        case .heading4: return .heading4
        case .heading5: return .heading5
        case .heading6: return .heading6
        case .body: return .body
        case .comment: return .comment
        }
    }
}

