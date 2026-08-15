// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import Foundation

@MainActor
enum NodeMarkdownDiagnostic33 {
    static func record(_ message: String) {}
}

enum NodeMarkdownDiagnostic26 {
    nonisolated static func log(_ message: @autoclosure () -> String) {}

    nonisolated static func shortID(_ value: String) -> String {
        String(value.prefix(8))
    }

    nonisolated static func shortDigest(_ value: String?) -> String {
        guard let value else { return "nil" }
        return String(value.suffix(10))
    }

    nonisolated static func textSummary(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\n", with: "↵")
            .replacingOccurrences(of: "\r", with: "")
        return "\(normalized.prefix(24))[长度:\((value as NSString).length)]"
    }
}

#if os(macOS)
import AppKit

/// Compatibility shell for removed diagnostics. Existing call sites are intentionally
/// inert so diagnostic cleanup cannot alter editor behavior.
@MainActor
enum NodeMarkdownDiagnostic35 {
    struct Session {}

    static func now() -> UInt64 { 0 }
    static func milliseconds(since start: UInt64) -> Double { 0 }
}

extension NodeMarkdownTextKit2Coordinator {
    func beginDiagnostic35Input(
        in textView: NodeMarkdownTextKit2TextView,
        affectedRange: NSRange,
        isComposition: Bool
    ) {
        diagnostic35Session = nil
    }

    func recordDiagnostic35Duration(_ stage: String, since start: UInt64) {}
    func recordDiagnostic35Duration(_ stage: String, milliseconds: Double) {}
    func recordDiagnostic35Count(_ name: String, amount: Int = 1) {}
}

enum NodeMarkdownDiagnostic31 {
    struct Transaction {}

    static func startIfNeeded(
        in textView: NodeMarkdownTextKit2TextView,
        rowLayouts: [NodeMarkdownTextKit2RowLayout],
        rowMetadata: [NodeMarkdownTextKitRowMetadata],
        affectedRange: NSRange,
        replacement: String
    ) {}

    static func record(
        _ stage: String,
        in textView: NodeMarkdownTextKit2TextView,
        rowLayouts: [NodeMarkdownTextKit2RowLayout]
    ) {}

    static func noteCommittedReplacement(
        _ replacement: String,
        in textView: NodeMarkdownTextKit2TextView,
        rowLayouts: [NodeMarkdownTextKit2RowLayout]
    ) {}

    static func recordSelectionWrite(
        _ reason: String,
        before: NSRange,
        requested: NSRange,
        in textView: NodeMarkdownTextKit2TextView,
        rowLayouts: [NodeMarkdownTextKit2RowLayout]
    ) {}

    static func recordGeometry(
        in textView: NodeMarkdownTextKit2TextView,
        layout: NodeMarkdownTextKit2RowLayout,
        lineRect: NSRect,
        markerRect: NSRect,
        baselineY: CGFloat?
    ) {}

    static func recordDeferredState(
        after delay: TimeInterval,
        stage: String,
        in textView: NodeMarkdownTextKit2TextView,
        rowLayouts: @escaping () -> [NodeMarkdownTextKit2RowLayout]
    ) {}
}

@MainActor
enum NodeMarkdownDiagnostic41 {
    struct Transaction {
        let action: String
    }

    static func begin(_ action: String) -> Transaction {
        Transaction(action: action)
    }

    static func event(_ message: String, transaction: Transaction? = nil) {}

    static func state(
        _ stage: String,
        transaction: Transaction? = nil,
        textView: NodeMarkdownTextKit2TextView,
        rowLayouts: [NodeMarkdownTextKit2RowLayout],
        rowMetadata: [NodeMarkdownTextKitRowMetadata],
        editingRow: Int?
    ) {}

    static func deferredStates(
        transaction: Transaction,
        textView: NodeMarkdownTextKit2TextView,
        coordinator: NodeMarkdownTextKit2Coordinator
    ) {}
}

extension NodeMarkdownTextKit2Coordinator {
    func beginDiagnostic41(_ action: String, in textView: NodeMarkdownTextKit2TextView) -> NodeMarkdownDiagnostic41.Transaction {
        NodeMarkdownDiagnostic41.begin(action)
    }

    func finishDiagnostic41(
        _ transaction: NodeMarkdownDiagnostic41.Transaction,
        in textView: NodeMarkdownTextKit2TextView,
        stage: String = "操作返回"
    ) {}
}

enum NodeMarkdownTextKit2Diagnostics {
    static func log(_ message: @autoclosure () -> String) {}

    static func report(
        stage: String,
        textView: NodeMarkdownTextKit2TextView,
        bindingText: String? = nil,
        metadataCount: Int? = nil,
        rowLayoutCount: Int? = nil
    ) {}
}
#endif

#if !os(macOS)
@MainActor
enum NodeMarkdownDiagnostic41 {
    static func event(_ message: String) {}
}
#endif
