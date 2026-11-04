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

@MainActor
enum NodeMarkdownDiagnostic117 {
    static let isEnabled = false

    static func newOperationID() -> String {
        String(UUID().uuidString.prefix(8))
    }

    static func record(operationID: String?, _ message: @autoclosure () -> String) {
        guard isEnabled, let operationID else { return }
        let line = "[诊断·117] op=\(operationID) " + message()
        print(line)
        TeachingDebugLogStore.append(line, category: "诊断·117")
    }

    static func textSummary(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "↵")
        return "\(normalized.prefix(80))[utf16=\((value as NSString).length)]"
    }

    static func rangesSummary(_ values: [NSValue]) -> String {
        values.map { NSStringFromRange($0.rangeValue) }.joined(separator: ",")
    }
}

@MainActor
enum NodeMarkdownDiagnostic122 {
    static func record(operationID: String, _ message: @autoclosure () -> String) {
        let line = "[诊断·122·光标视口] op=\(operationID) " + message()
        TeachingDebugLogStore.append(line, category: "诊断·122·光标视口", force: true)
    }
}

#if os(macOS)
import AppKit

@MainActor
final class NodeMarkdownDiagnostic114 {
    private struct Metric {
        var totalMilliseconds = 0.0
        var maximumMilliseconds = 0.0
        var count = 0

        mutating func add(_ milliseconds: Double) {
            totalMilliseconds += milliseconds
            maximumMilliseconds = max(maximumMilliseconds, milliseconds)
            count += 1
        }
    }

    private static let isEnabled = false

    private let sessionID: String
    private var documentRows: Int
    private var documentUTF16: Int
    private var metrics: [String: Metric] = [:]
    private var counters: [String: Int] = [:]
    private var slowSamples: [String] = []
    private var lastFlushAt = DispatchTime.now().uptimeNanoseconds

    init(sessionID: UUID, documentRows: Int, documentUTF16: Int) {
        self.sessionID = String(sessionID.uuidString.prefix(8))
        self.documentRows = documentRows
        self.documentUTF16 = documentUTF16
    }

    static func now() -> UInt64 {
        guard isEnabled else { return 0 }
        return DispatchTime.now().uptimeNanoseconds
    }

    func updateDocument(rows: Int, utf16: Int) {
        guard Self.isEnabled else { return }
        documentRows = rows
        documentUTF16 = utf16
    }

    func recordDuration(
        _ stage: String,
        since start: UInt64,
        slowThresholdMilliseconds: Double = 4,
        details: @autoclosure () -> String = ""
    ) {
        guard Self.isEnabled, start > 0 else { return }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        metrics[stage, default: Metric()].add(elapsed)
        if elapsed >= slowThresholdMilliseconds, slowSamples.count < 10 {
            let resolvedDetails = details()
            let suffix = resolvedDetails.isEmpty ? "" : " " + resolvedDetails
            slowSamples.append("\(stage)=\(String(format: "%.2f", elapsed))ms\(suffix)")
        }
    }

    func recordCount(_ name: String, amount: Int = 1) {
        guard Self.isEnabled else { return }
        counters[name, default: 0] += amount
    }

    func flushIfNeeded(reason: String, readyRows: Int, force: Bool = false) {
        guard Self.isEnabled, !metrics.isEmpty || !counters.isEmpty else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = Double(now - lastFlushAt) / 1_000_000_000
        guard force || elapsed >= 2 else { return }

        let metricText = metrics
            .sorted { lhs, rhs in lhs.value.totalMilliseconds > rhs.value.totalMilliseconds }
            .prefix(14)
            .map { name, metric in
                let average = metric.count > 0 ? metric.totalMilliseconds / Double(metric.count) : 0
                return "\(name){n=\(metric.count),avg=\(String(format: "%.2f", average)),max=\(String(format: "%.2f", metric.maximumMilliseconds)),sum=\(String(format: "%.2f", metric.totalMilliseconds))ms}"
            }
            .joined(separator: ", ")
        let counterText = counters
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        let slowText = slowSamples.isEmpty ? "-" : slowSamples.joined(separator: " | ")
        let message = "[诊断·114] session=\(sessionID) reason=\(reason) rows=\(documentRows) utf16=\(documentUTF16) ready=\(readyRows) metrics=[\(metricText)] counters=[\(counterText)] slow=[\(slowText)]"
        print(message)
        TeachingDebugLogStore.append(message, category: "诊断·114")

        metrics.removeAll(keepingCapacity: true)
        counters.removeAll(keepingCapacity: true)
        slowSamples.removeAll(keepingCapacity: true)
        lastFlushAt = now
    }
}

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

extension NodeMarkdownTextKit2TextView {
    func recordCaretViewportDiagnostics(
        reason: String
    ) {
        let operationID = String(UUID().uuidString.prefix(8))
        NodeMarkdownDiagnostic122.record(
            operationID: operationID,
            "reason=\(reason) stage=已收到输入回调"
        )
        for (delay, stage) in [(0.0, "立即"), (0.01, "下一轮"), (0.05, "50ms"), (0.20, "200ms")] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.recordCaretViewportSample(
                    operationID: operationID,
                    reason: reason,
                    stage: stage
                )
            }
        }
    }

    private func recordCaretViewportSample(
        operationID: String,
        reason: String,
        stage: String
    ) {
        let selection = selectedRange()
        guard selection.length == 0,
              let scrollView = enclosingScrollView else { return }
        let clipView = scrollView.contentView
        let viewport = clipView.bounds
        let documentLength = nodeTextStorage.length
        var caretText = "nil"
        var overflowText = "nil"
        if selection.location <= documentLength, let window {
            let screenRect = firstRect(forCharacterRange: selection, actualRange: nil)
            if !screenRect.isNull, !screenRect.isEmpty {
                let caretRect = convert(window.convertFromScreen(screenRect), from: nil)
                caretText = diagnostic122Rect(caretRect)
                overflowText = String(format: "%.1f", caretRect.maxY - viewport.maxY)
            }
        }
        // Diagnostics must not probe AppKit with near-infinite bounds during input.
        let documentBounds = scrollView.documentView?.bounds ?? bounds
        let maximumOriginY = max(documentBounds.minY, documentBounds.maxY - viewport.height)
        NodeMarkdownDiagnostic122.record(
            operationID: operationID,
            "reason=\(reason) stage=\(stage) selection=\(NSStringFromRange(selection)) "
                + "caret=\(caretText) viewport=\(diagnostic122Rect(viewport)) overflow=\(overflowText) "
                + "textFrame=\(diagnostic122Rect(frame)) textBounds=\(diagnostic122Rect(bounds)) "
                + "documentFrame=\(diagnostic122Rect(scrollView.documentView?.frame ?? .zero)) "
                + "maxOriginY=\(String(format: "%.1f", maximumOriginY)) "
                + "contentInsetBottom=\(String(format: "%.1f", scrollView.contentInsets.bottom)) "
                + "textInsetY=\(String(format: "%.1f", textContainerInset.height)) "
                + "suppressAutoScroll=\(suppressesAutomaticSelectionScrolling) utf16=\(documentLength)"
        )
    }

    private func diagnostic122Rect(_ rect: NSRect) -> String {
        String(
            format: "{x=%.1f,y=%.1f,w=%.1f,h=%.1f}",
            rect.minX,
            rect.minY,
            rect.width,
            rect.height
        )
    }
}

enum NodeMarkdownTextKit2Diagnostics {
    static func log(_ message: @autoclosure () -> String) {}

    static func report(
        stage: String,
        textView: NodeMarkdownTextKit2TextView,
        bindingText: String? = nil,
        metadataCount: Int? = nil,
        rowLayoutCount: Int? = nil
    ) {
        textView.stabilityLog.sample(stage: stage, textView: textView)
    }
}

/// 只采集常数级几何数据；五秒聚合一次，不读取全文或遍历布局片段。
@MainActor
final class NodeMarkdownStabilityLog {
    private let id = String(UUID().uuidString.prefix(8))
    private var started = ProcessInfo.processInfo.systemUptime
    private var counts: [String: Int] = [:]
    private var maxDuration = 0.0
    private var previousY: CGFloat?
    private var previousDelta: CGFloat = 0
    private var reversals = 0
    private var maxJump: CGFloat = 0
    private var invalidGeometryCount = 0

    func sample(stage: String, textView: NodeMarkdownTextKit2TextView, duration: Double = 0) {
        guard TeachingDebugLogStore.isLayoutJitterLogsEnabled() else { return }
        counts[stage, default: 0] += 1
        if duration.isFinite, duration >= 0 { maxDuration = max(maxDuration, duration) }
        let rect = textView.visibleRect
        let validGeometry = [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy {
            $0.isFinite && abs($0) < 1_000_000_000_000
        }
        if !validGeometry {
            if invalidGeometryCount == 0 {
                TeachingDebugLogStore.append(
                    "view=\(id) stage=\(stage) invalidViewport=\(rect) previousY=\(String(describing: previousY)) frame=\(textView.frame) bounds=\(textView.bounds) clip=\(String(describing: textView.enclosingScrollView?.contentView.bounds)) selection=\(NSStringFromRange(textView.selectedRange())) marked=\(textView.hasMarkedText())",
                    category: "NodeMarkdown.Stability"
                )
            }
            invalidGeometryCount += 1
            previousY = nil
            previousDelta = 0
        } else if let previousY {
            let delta = rect.minY - previousY
            maxJump = max(maxJump, abs(delta))
            if abs(delta) > 2 {
                if previousDelta != 0, (delta < 0) != (previousDelta < 0) { reversals += 1 }
                previousDelta = delta
            }
        }
        if validGeometry { previousY = rect.minY }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - started >= 5 else { return }
        let events = counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        TeachingDebugLogStore.append(
            "view=\(id) window=\(textView.window?.windowNumber ?? -1) seconds=\(String(format: "%.1f", now - started)) events=[\(events)] maxLayoutMs=\(String(format: "%.1f", maxDuration * 1000)) maxJump=\(String(format: "%.1f", Double(maxJump))) invalidGeometry=\(invalidGeometryCount) reversals=\(reversals) viewport=\(rect) frame=\(textView.frame.size) chars=\(textView.nodeTextStorage.length) marked=\(textView.hasMarkedText())",
            category: "NodeMarkdown.Stability"
        )
        counts.removeAll(keepingCapacity: true)
        maxDuration = 0
        maxJump = 0
        reversals = 0
        invalidGeometryCount = 0
        started = now
    }
}
#endif

#if !os(macOS)
@MainActor
enum NodeMarkdownDiagnostic41 {
    static func event(_ message: String) {}
}
#endif
