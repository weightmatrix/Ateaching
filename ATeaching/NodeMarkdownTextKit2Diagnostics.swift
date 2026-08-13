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
        let id: UInt64
        let action: String
        let startedAt: UInt64
    }

    private static var nextID: UInt64 = 0
    private static var preparedLog = false
    private static var logURL: URL?

    static func begin(_ action: String) -> Transaction {
        nextID &+= 1
        let transaction = Transaction(id: nextID, action: action, startedAt: DispatchTime.now().uptimeNanoseconds)
        append("事务#\(transaction.id) 开始 动作=\(action)")
        return transaction
    }

    static func event(_ message: String, transaction: Transaction? = nil) {
        let prefix = transaction.map { "事务#\($0.id) 动作=\($0.action) " } ?? ""
        append(prefix + message)
    }

    static func state(
        _ stage: String,
        transaction: Transaction? = nil,
        textView: NodeMarkdownTextKit2TextView,
        rowLayouts: [NodeMarkdownTextKit2RowLayout],
        rowMetadata: [NodeMarkdownTextKitRowMetadata],
        editingRow: Int?
    ) {
        let selection = textView.selectedRange()
        let marked = textView.markedRange()
        let source = textView.nodeSourceTextSnapshot as NSString
        let storageLength = textView.nodeTextStorage.length
        let row = rowIndex(at: selection.location, layouts: rowLayouts, documentLength: source.length)
        let nearby = nearbyRows(around: row, source: source, textView: textView, layouts: rowLayouts, metadata: rowMetadata)
        let viewport: String = {
            guard let clip = textView.enclosingScrollView?.contentView else { return "nil" }
            return "origin=(\(format(clip.bounds.minX)),\(format(clip.bounds.minY))) size=(\(format(clip.bounds.width)),\(format(clip.bounds.height)))"
        }()
        let elapsed = transaction.map {
            Double(DispatchTime.now().uptimeNanoseconds &- $0.startedAt) / 1_000_000
        }
        let elapsedDescription = elapsed.map { format($0) + "ms" } ?? "nil"
        let rowDescription = row.map(String.init) ?? "nil"
        let editingRowDescription = editingRow.map(String.init) ?? "nil"
        let prefix = transaction.map { "事务#\($0.id) 动作=\($0.action) " } ?? ""
        append(
            prefix + "阶段=\(stage) 耗时=\(elapsedDescription) "
                + "source/storage=\(source.length)/\(storageLength) snapshot匹配=\(textView.sourceSnapshotMatchesStorage()) "
                + "layout/metadata=\(rowLayouts.count)/\(rowMetadata.count) selection=\(NSStringFromRange(selection)) "
                + "marked=\(NSStringFromRange(marked)) current/editing=\(rowDescription)/\(editingRowDescription) "
                + "viewport=[\(viewport)] nearby=[\(nearby)]"
        )
    }

    static func deferredStates(
        transaction: Transaction,
        textView: NodeMarkdownTextKit2TextView,
        coordinator: NodeMarkdownTextKit2Coordinator
    ) {
        for (delay, label) in [(0.0, "下一主循环"), (0.08, "80ms"), (0.35, "350ms")] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak textView, weak coordinator] in
                guard let textView, let coordinator else { return }
                state(
                    label,
                    transaction: transaction,
                    textView: textView,
                    rowLayouts: coordinator.rowLayouts,
                    rowMetadata: coordinator.rowMetadata,
                    editingRow: coordinator.editingRowIndex
                )
            }
        }
    }

    private static func nearbyRows(
        around row: Int?,
        source: NSString,
        textView: NodeMarkdownTextKit2TextView,
        layouts: [NodeMarkdownTextKit2RowLayout],
        metadata: [NodeMarkdownTextKitRowMetadata]
    ) -> String {
        guard let row else { return "无当前行" }
        let lower = max(0, row - 1)
        let upper = min(layouts.count - 1, row + 2)
        guard lower <= upper else { return "无布局" }
        return (lower...upper).map { index in
            let layout = layouts[index]
            let text = layout.contentRange.exact(toLength: source.length).map { source.substring(with: $0) } ?? "<越界>"
            let summary = text.replacingOccurrences(of: "\n", with: "↵").prefix(14)
            let meta = metadata.indices.contains(index) ? metadata[index] : nil
            let attributes = attributesSummary(at: layout.contentRange.location, textView: textView)
            let nodeID = meta.map { String($0.nodeID.prefix(8)) } ?? "nil"
            return "r\(index){id=\(nodeID),level=\(meta?.level ?? -1)/\(layout.level),range=\(NSStringFromRange(layout.range)),content=\(summary),attr=\(attributes)}"
        }.joined(separator: ";")
    }

    private static func attributesSummary(at location: Int, textView: NodeMarkdownTextKit2TextView) -> String {
        guard textView.nodeTextStorage.length > 0 else { return "empty" }
        let safe = min(max(0, location), textView.nodeTextStorage.length - 1)
        let attributes = textView.nodeTextStorage.attributes(at: safe, effectiveRange: nil)
        let font = attributes[.font] as? NSFont
        let color = attributes[.foregroundColor] as? NSColor
        let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
        let fontName = font?.fontName ?? "nil"
        let fontSize = font.map { format($0.pointSize) } ?? "nil"
        let colorDescription = color?.description ?? "nil"
        let indent = paragraph.map { format($0.headIndent) } ?? "nil"
        return "font=\(fontName)/\(fontSize),color=\(colorDescription),indent=\(indent),attach=\(attributes[.attachment] != nil)"
    }

    private static func rowIndex(
        at location: Int,
        layouts: [NodeMarkdownTextKit2RowLayout],
        documentLength: Int
    ) -> Int? {
        if location == documentLength, layouts.last?.range.location == documentLength { return layouts.indices.last }
        let anchor = location == documentLength ? max(0, documentLength - 1) : location
        return layouts.firstIndex { NSLocationInRange(anchor, $0.range) }
    }

    private static func append(_ message: String) {
        let tagged = "【诊断·41】\(message)"
        print(tagged)
        prepareLogIfNeeded()
        guard let logURL,
              let data = ("- `\(timestamp())` \(tagged)\n").data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private static func prepareLogIfNeeded() {
        guard !preparedLog else { return }
        preparedLog = true
        let manager = FileManager.default
        guard let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let folder = support.appendingPathComponent("ATeaching/诊断", isDirectory: true)
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("NodeMarkdown新管线诊断·41.MD")
            let header = "# NodeMarkdown新管线诊断·41\n\n"
                + "- 建立时间：\(timestamp())\n"
                + "- 目标：追踪跨Node样式污染、结构操作卡顿、非预期视野移动、搜索后跳动、画图与图片插入失败。\n"
                + "- 记录：事务前后源码、TextStorage、Node范围、层级、实际字符属性、选区、组合态、视口及耗时。\n"
                + "- 本诊断不修改正文、选区、布局或视野。\n\n"
            try header.write(to: url, atomically: true, encoding: .utf8)
            logURL = url
            print("【诊断·41】诊断记录：\(url.path)")
        } catch {
            print("【诊断·41】无法建立诊断记录：\(error.localizedDescription)")
        }
    }

    private static func format(_ value: CGFloat) -> String { String(format: "%.2f", value) }
    private static func format(_ value: Double) -> String { String(format: "%.2f", value) }
    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}

extension NodeMarkdownTextKit2Coordinator {
    func beginDiagnostic41(_ action: String, in textView: NodeMarkdownTextKit2TextView) -> NodeMarkdownDiagnostic41.Transaction {
        let transaction = NodeMarkdownDiagnostic41.begin(action)
        NodeMarkdownDiagnostic41.state(
            "操作前",
            transaction: transaction,
            textView: textView,
            rowLayouts: rowLayouts,
            rowMetadata: rowMetadata,
            editingRow: editingRowIndex
        )
        return transaction
    }

    func finishDiagnostic41(
        _ transaction: NodeMarkdownDiagnostic41.Transaction,
        in textView: NodeMarkdownTextKit2TextView,
        stage: String = "操作返回"
    ) {
        NodeMarkdownDiagnostic41.state(
            stage,
            transaction: transaction,
            textView: textView,
            rowLayouts: rowLayouts,
            rowMetadata: rowMetadata,
            editingRow: editingRowIndex
        )
        NodeMarkdownDiagnostic41.deferredStates(transaction: transaction, textView: textView, coordinator: self)
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
    ) {}
}
#endif

#if !os(macOS)
@MainActor
enum NodeMarkdownDiagnostic41 {
    static func event(_ message: String) {}
}
#endif
