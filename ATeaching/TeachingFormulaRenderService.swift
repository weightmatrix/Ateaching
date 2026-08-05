// PIPELINE MARKER: NodeMarkdown legacy pipeline (TeachingPrint formula support).
import Foundation
import CoreGraphics

struct TeachingFormulaLayoutInfo: Sendable, Hashable {
    var sourceBlockID: UUID
    var formulaText: String
    var estimatedSize: CGSize
}

enum TeachingFormulaRenderService {
    private static var cache: [String: CGSize] = [:]
    private static let cacheQueue = DispatchQueue(label: "com.ateaching.formula-cache", qos: .utility)

    static func collectLayoutInfos(from renderingDocument: TeachingRenderingDocument) -> [TeachingFormulaLayoutInfo] {
        renderingDocument.resources.compactMap { ref in
            guard ref.kind == .formula else { return nil }
            let formula = extractPrimaryFormula(from: ref.rawValue)
            let size = measureFormula(formula)
            return TeachingFormulaLayoutInfo(
                sourceBlockID: ref.sourceBlockID,
                formulaText: formula,
                estimatedSize: size
            )
        }
    }

    static func measureFormula(_ formula: String) -> CGSize {
        if let cached = cacheQueue.sync(execute: { cache[formula] }) {
            return cached
        }
        let compact = formula.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let charCount = max(1, compact.count)
        let lineCount = max(1, Int(ceil(Double(charCount) / 36.0)))
        let width = min(860.0, max(72.0, Double(charCount) * 7.2))
        let height = max(24.0, Double(lineCount) * 24.0)
        let size = CGSize(width: width, height: height)
        cacheQueue.sync {
            cache[formula] = size
        }
        return size
    }

    private static func extractPrimaryFormula(from text: String) -> String {
        if let range = text.range(of: #"\$\$([\s\S]*?)\$\$"#, options: .regularExpression) {
            return String(text[range])
        }
        if let range = text.range(of: #"\\\(([\s\S]*?)\\\)"#, options: .regularExpression) {
            return String(text[range])
        }
        if let range = text.range(of: #"\\\[([\s\S]*?)\\\]"#, options: .regularExpression) {
            return String(text[range])
        }
        return text
    }
}
