// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import Foundation

/// 2-33结构事务追踪。只记录已经做出的业务决定，不读写正文、选区或视口。
@MainActor
enum NodeMarkdownDiagnostic33 {
    static func record(_ message: String) {
        #if DEBUG
        let tagged = "【诊断·33】\(message)"
        print(tagged)
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        let folder = applicationSupport
            .appendingPathComponent("ATeaching", isDirectory: true)
            .appendingPathComponent("诊断", isDirectory: true)
        let url = folder.appendingPathComponent("ATeaching诊断记录.MD", isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var text = (try? String(contentsOf: url, encoding: .utf8)) ?? "# ATeaching诊断记录\n"
            if !text.contains("# 诊断·33 包与目录事务") {
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
                text += "\n# 诊断·33 包与目录事务\n\n- 软件版本：\(version)\n- 记录范围：包删除、随堂插入锚点、教案剪切粘贴、目录拖动。\n\n"
            }
            let formatter = ISO8601DateFormatter()
            text += "- `\(formatter.string(from: Date()))` \(tagged)\n"
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("【诊断·33】写入失败：\(error.localizedDescription)")
        }
        #endif
    }
}

enum NodeMarkdownDiagnostic26 {
    nonisolated static func log(_ message: @autoclosure () -> String) {
        // 2-28起停用。保留入口，避免为了移除旧诊断改动脏包业务代码。
    }

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

/// 2-31只观察“空Node第一次写入文字”。诊断不能强制布局、修改选区或参与正文事务。
enum NodeMarkdownDiagnostic31 {
    struct Transaction {
        let id: Int
        let rowIndex: Int
        let nodeID: String
        let originalSelection: NSRange
        let affectedLocation: Int
        var expectedSelectionLocation: Int
        var lastSelection: NSRange
        var lastGeometry: String?
        var lastEventSignature: String?
        var suppressedEventCount: Int
        var eventCount: Int
    }

    private static var nextTransactionID = 0
    private static var preparedLog = false
    private static var logURL: URL?
    private static let sectionTitle = "# 诊断·31 空行首字与焦点"

    static func startIfNeeded(
        in textView: NodeMarkdownTextKit2TextView,
        rowLayouts: [NodeMarkdownTextKit2RowLayout],
        rowMetadata: [NodeMarkdownTextKitRowMetadata],
        affectedRange: NSRange,
        replacement: String
    ) {
        #if DEBUG
        guard !replacement.isEmpty,
              !replacement.contains("\n"),
              let rowIndex = rowLayouts.firstIndex(where: {
                  $0.contentRange.length == 0
                      && affectedRange.location == $0.contentRange.location
                      && affectedRange.length == 0
              }),
              rowMetadata.indices.contains(rowIndex) else { return }

        nextTransactionID += 1
        let selection = textView.selectedRange()
        textView.diagnostic31Transaction = Transaction(
            id: nextTransactionID,
            rowIndex: rowIndex,
            nodeID: String(rowMetadata[rowIndex].nodeID.prefix(8)),
            originalSelection: selection,
            affectedLocation: affectedRange.location,
            expectedSelectionLocation: affectedRange.location + (replacement as NSString).length,
            lastSelection: selection,
            lastGeometry: nil,
            lastEventSignature: nil,
            suppressedEventCount: 0,
            eventCount: 0
        )
        record(
            "事务开始 replacement=\(summary(replacement)) affected=\(NSStringFromRange(affectedRange))",
            in: textView,
            rowLayouts: rowLayouts
        )
        #endif
    }

    static func record(
        _ stage: String,
        in textView: NodeMarkdownTextKit2TextView,
        rowLayouts: [NodeMarkdownTextKit2RowLayout]
    ) {
        #if DEBUG
        guard var transaction = textView.diagnostic31Transaction else { return }
        let selection = textView.selectedRange()
        let marked = textView.markedRange()
        let row = rowLayouts.indices.contains(transaction.rowIndex)
            ? rowLayouts[transaction.rowIndex]
            : nil
        let currentRow = rowLayouts.firstIndex { layout in
            selection.location >= layout.range.location
                && (selection.location < NSMaxRange(layout.range)
                    || (layout.range.length == 0 && selection.location == layout.range.location))
        }
        let jumped = selection.location == 0
            && transaction.expectedSelectionLocation > 0
            && transaction.lastSelection.location != 0
        let transientLayouts = textView.nodeMarkdownRowLayouts
        let transientRow = transientLayouts.indices.contains(transaction.rowIndex)
            ? transientLayouts[transaction.rowIndex]
            : nil
        let signature = "\(stage)|\(NSStringFromRange(selection))|\(NSStringFromRange(marked))|\(textView.nodeTextStorage.length)|\(transientRow.map { NSStringFromRange($0.range) } ?? "nil")"
        if signature == transaction.lastEventSignature {
            transaction.suppressedEventCount += 1
            textView.diagnostic31Transaction = transaction
            return
        }
        transaction.eventCount += 1
        let suppressed = transaction.suppressedEventCount
        transaction.suppressedEventCount = 0
        transaction.lastEventSignature = signature
        let currentRowDescription = currentRow.map(String.init) ?? "nil"
        let rowDescription = row.map {
            "range=\(NSStringFromRange($0.range)),content=\(NSStringFromRange($0.contentRange)),level=\($0.level)"
        } ?? "nil"
        let transientDescription = transientRow.map {
            "range=\(NSStringFromRange($0.range)),content=\(NSStringFromRange($0.contentRange)),level=\($0.level)"
        } ?? "nil"
        let sourceSummary = textSummary(
            textView.nodeSourceTextSnapshot,
            around: transaction.affectedLocation
        )
        let storageSummary = textSummary(
            textView.nodeTextStorage.string,
            around: transaction.affectedLocation
        )
        let line = "事务#\(transaction.id) 事件#\(transaction.eventCount) 阶段=\(stage) "
            + "Node=\(transaction.nodeID) 目标行=\(transaction.rowIndex) 当前行=\(currentRowDescription) "
            + "selection=\(NSStringFromRange(selection)) expected=\(transaction.expectedSelectionLocation) "
            + "marked=\(NSStringFromRange(marked)) storage/source=\(textView.nodeTextStorage.length)/\((textView.nodeSourceTextSnapshot as NSString).length) "
            + "officialRow=\(rowDescription) transientRow=\(transientDescription) "
            + "source/storage片段=\(sourceSummary)/\(storageSummary) "
            + "省略重复=\(suppressed) "
            + "firstResponder=\(textView.window?.firstResponder === textView) 跳到文首=\(jumped)"
        transaction.lastSelection = selection
        textView.diagnostic31Transaction = transaction
        output(line)
        #endif
    }

    static func noteCommittedReplacement(
        _ replacement: String,
        in textView: NodeMarkdownTextKit2TextView,
        rowLayouts: [NodeMarkdownTextKit2RowLayout]
    ) {
        #if DEBUG
        guard var transaction = textView.diagnostic31Transaction else { return }
        transaction.expectedSelectionLocation = transaction.affectedLocation + (replacement as NSString).length
        textView.diagnostic31Transaction = transaction
        record("正式提交期望焦点 replacement=\(summary(replacement))", in: textView, rowLayouts: rowLayouts)
        #endif
    }

    static func recordSelectionWrite(
        _ reason: String,
        before: NSRange,
        requested: NSRange,
        in textView: NodeMarkdownTextKit2TextView,
        rowLayouts: [NodeMarkdownTextKit2RowLayout]
    ) {
        #if DEBUG
        record(
            "主动写选区 reason=\(reason) before=\(NSStringFromRange(before)) requested=\(NSStringFromRange(requested)) after=\(NSStringFromRange(textView.selectedRange()))",
            in: textView,
            rowLayouts: rowLayouts
        )
        #endif
    }

    static func recordGeometry(
        in textView: NodeMarkdownTextKit2TextView,
        layout: NodeMarkdownTextKit2RowLayout,
        lineRect: NSRect,
        markerRect: NSRect,
        baselineY: CGFloat?
    ) {
        #if DEBUG
        guard var transaction = textView.diagnostic31Transaction,
              transaction.rowIndex == layout.rowIndex else { return }
        let font = NodeMarkdownTextKit2TextView.resolvedFont(for: layout.lineStyle.roleStyle)
        let baselineDescription = baselineY.map { String(format: "%.3f", $0) } ?? "nil"
        let fontSizeDescription = String(format: "%.2f", font.pointSize)
        let fontMetricsDescription = String(format: "%.3f/%.3f", font.ascender, font.descender)
        let geometry = "line=\(NSStringFromRect(lineRect)),marker=\(NSStringFromRect(markerRect)),baselineY=\(baselineDescription),font=\(font.fontName)/\(fontSizeDescription),asc/desc=\(fontMetricsDescription)"
        guard transaction.lastGeometry != geometry else { return }
        transaction.lastGeometry = geometry
        textView.diagnostic31Transaction = transaction
        record("真实绘制几何 \(geometry)", in: textView, rowLayouts: textView.nodeMarkdownRowLayouts)
        #endif
    }

    static func recordDeferredState(
        after delay: TimeInterval,
        stage: String,
        in textView: NodeMarkdownTextKit2TextView,
        rowLayouts: @escaping () -> [NodeMarkdownTextKit2RowLayout]
    ) {
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak textView] in
            guard let textView else { return }
            record(stage, in: textView, rowLayouts: rowLayouts())
        }
        #endif
    }

    static func diagnosticFilePath() -> String {
        prepareLogIfNeeded()
        return logURL?.path ?? "无法建立诊断记录文件"
    }

    private static func output(_ message: String) {
        let tagged = "【诊断·31】\(message)"
        print(tagged)
        prepareLogIfNeeded()
        guard let logURL,
              let data = ("- `\(timestamp())` \(tagged)\n").data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            print("【诊断·31】写入诊断记录失败：\(error.localizedDescription)")
        }
    }

    private static func prepareLogIfNeeded() {
        guard !preparedLog else { return }
        preparedLog = true
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        let folder = applicationSupport
            .appendingPathComponent("ATeaching", isDirectory: true)
            .appendingPathComponent("诊断", isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("ATeaching诊断记录.MD", isDirectory: false)
            var existing = (try? String(contentsOf: url, encoding: .utf8)) ?? "# ATeaching诊断记录\n\n"
            existing = removingExistingSection(from: existing)
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
            let header = "\n\(sectionTitle)\n\n- 建立时间：\(timestamp())\n- 软件版本：\(version)\n- 固定物理位置：`\(url.path)`\n- 读取规则：直接读取上述文件，不再从 Console 复制。\n- 本节只记录空Node首字输入，不会修改正文、焦点或布局。\n\n"
            try (existing + header).write(to: url, atomically: true, encoding: .utf8)
            guard fileManager.isReadableFile(atPath: url.path),
                  (try String(contentsOf: url, encoding: .utf8)).contains(sectionTitle) else {
                throw CocoaError(.fileReadUnknown)
            }
            logURL = url
            print("【诊断·31】诊断记录：\(url.path)")
        } catch {
            print("【诊断·31】无法建立诊断记录：\(error.localizedDescription)")
        }
    }

    private static func removingExistingSection(from value: String) -> String {
        guard let start = value.range(of: sectionTitle) else { return value }
        let tail = value[start.upperBound...]
        if let next = tail.range(of: "\n# ") {
            return String(value[..<start.lowerBound]) + String(tail[next.lowerBound...].dropFirst())
        }
        return String(value[..<start.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    private static func summary(_ value: String) -> String {
        let visible = value.replacingOccurrences(of: "\n", with: "↵")
        return "\(visible.prefix(16))[UTF16:\((value as NSString).length)]"
    }

    private static func textSummary(_ value: String, around location: Int) -> String {
        let source = value as NSString
        let safeLocation = min(max(0, location), source.length)
        let lower = max(0, safeLocation - 12)
        let upper = min(source.length, safeLocation + 24)
        let visible = source.substring(with: NSRange(location: lower, length: upper - lower))
            .replacingOccurrences(of: "\n", with: "↵")
            .replacingOccurrences(of: "\r", with: "")
        return "[\(lower)..<\(upper)]\(visible)"
    }
}

/// 旧诊断入口保留为空操作，避免清理诊断扩大到业务文件。
enum NodeMarkdownTextKit2Diagnostics {
    static func log(_ message: @autoclosure () -> String) {
        // 旧诊断已停用。保留入口是为了避免诊断清理扩大到业务文件。
    }

    static func report(
        stage: String,
        textView: NodeMarkdownTextKit2TextView,
        bindingText: String? = nil,
        metadataCount: Int? = nil,
        rowLayoutCount: Int? = nil
    ) {
        // 旧的六行通用报告已停用；它会主动查询首片段，可能干扰本次布局诊断。
    }

}

#endif
