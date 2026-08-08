// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit
#endif
#if canImport(SwiftMath)
import SwiftMath
#endif

#if os(macOS)
final class NodeMarkdownTextKit2TextView: NSTextView {
    static let formulaRenderScale: CGFloat = 2
    static var backgroundGradientCache: [NodeMarkdownTextKit2BackgroundGradientCacheKey: NSGradient] = [:]
    /// TextKit2新管线唯一的正文存储。正文、选择、输入法和排版必须共同使用这一实例。
    let nodeTextStorage: NSTextStorage
    let nodeTextContentStorage: NSTextContentStorage
    let nodeTextLayoutManager: NSTextLayoutManager
    let nodeTextContainer: NSTextContainer
    /// 唯一正文存储的源码快照，只用于避免每次按键遍历整篇附件属性；任何修改仍先经过NSTextStorage事务。
    var nodeSourceTextSnapshot = ""
    var onRequestInsertImage: (() -> Void)?
    var onRequestDeleteNodePackage: (() -> Void)?
    var onRequestCutNodePackage: (() -> Void)?
    var onRequestPasteNodePackage: (() -> Void)?
    var canPasteNodePackage: (() -> Bool)?
    var canCutNodePackage: (() -> Bool)?
    var canDeleteNodePackage: (() -> Bool)?
    var canDeleteProtectedH3: (() -> Bool)?
    var onRequestDeleteProtectedH3: (() -> Void)?
    var onRequestOpenDrawingBoard: (() -> Void)?
    var onHandleTabCommand: ((Bool) -> Bool)?
    var onHandleInsertNewline: (() -> Bool)?
    var onHandleDeleteBackward: (() -> Bool)?
    var onHandleDeleteForward: (() -> Bool)?
    var onHandleVerticalMove: ((Int) -> Bool)?
    var onHandleCancelOperation: (() -> Bool)?
    var onHandlePrimaryClick: (() -> Void)?
    var quickInputSettings = MarkdownQuickInputSettings()
    var isApplyingQuickInputReplacement = false
    var suppressesAutomaticSelectionScrolling = false
    var usesScreenMinimumFormulaFontSize = true
    var nodeMarkdownEditingRowIndex: Int?
    var nodeMarkdownRowLayouts: [NodeMarkdownTextKit2RowLayout] = [] {
        didSet {
            guard oldValue != nodeMarkdownRowLayouts else { return }
            needsDisplay = true
        }
    }

    init() {
        let textStorage = NSTextStorage()
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude))
        contentStorage.textStorage = textStorage
        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = textContainer
        nodeTextStorage = textStorage
        nodeTextContentStorage = contentStorage
        nodeTextLayoutManager = layoutManager
        nodeTextContainer = textContainer
        super.init(frame: NSRect(x: 0, y: 0, width: 720, height: 600), textContainer: textContainer)
        assertSingleTextStorage()
    }

    required init?(coder: NSCoder) {
        fatalError("NodeMarkdownTextKit2TextView must be created with init()")
    }

    var nodeMarkdownTextLayoutManager: NSTextLayoutManager {
        nodeTextLayoutManager
    }

    var nodeMarkdownTextContentStorage: NSTextContentStorage {
        nodeTextContentStorage
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        guard !suppressesAutomaticSelectionScrolling else { return }
        super.scrollRangeToVisible(range)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawNodeMarkdownBackgroundBars(in: dirtyRect)
        drawNodeMarkdownInlineHighlights(in: dirtyRect)
        super.draw(dirtyRect)
        drawNodeMarkdownMarkers(in: dirtyRect)
    }

    override func mouseDown(with event: NSEvent) {
        // Content缓冲区已经不含隐藏前缀，点击位置应完全交给NSTextView/TextKit2。
        super.mouseDown(with: event)
        onHandlePrimaryClick?()
    }

    /// Debug构建中立刻暴露双存储或布局链断裂，避免再次出现“能显示但不能编辑”。
    func assertSingleTextStorage(file: StaticString = #fileID, line: UInt = #line) {
        assert(nodeTextContentStorage.textStorage === nodeTextStorage, "TextKit2 content storage detached from canonical text storage", file: file, line: line)
        assert(textStorage === nodeTextStorage, "NSTextView is not editing the canonical TextKit2 text storage", file: file, line: line)
        assert(textContentStorage === nodeTextContentStorage, "NSTextView is not using the configured TextKit2 content storage", file: file, line: line)
        assert(textLayoutManager === nodeTextLayoutManager, "NSTextView is not using the configured TextKit2 layout manager", file: file, line: line)
    }

    override func insertNewline(_ sender: Any?) {
        if onHandleInsertNewline?() == true { return }
        super.insertNewline(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        if onHandleDeleteBackward?() == true { return }
        super.deleteBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
        if onHandleDeleteForward?() == true { return }
        super.deleteForward(sender)
    }

    override func insertTab(_ sender: Any?) {
        if onHandleTabCommand?(true) == true { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if onHandleTabCommand?(false) == true { return }
        super.insertBacktab(sender)
    }

    override func insertTabIgnoringFieldEditor(_ sender: Any?) {
        if onHandleTabCommand?(true) == true { return }
        super.insertTabIgnoringFieldEditor(sender)
    }

    override func cancelOperation(_ sender: Any?) {
        if onHandleCancelOperation?() == true { return }
        super.cancelOperation(sender)
    }

}
#endif
