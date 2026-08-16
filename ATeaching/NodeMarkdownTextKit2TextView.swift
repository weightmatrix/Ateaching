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
    struct InputMethodCommit {
        let sourceBefore: String
        let affectedRange: NSRange
        let replacement: String
    }

    static let formulaRenderScale: CGFloat = 2
    static var backgroundGradientCache: [NodeMarkdownTextKit2BackgroundGradientCacheKey: NSGradient] = [:]
    /// 唯一TextKit2对象链。NSTextView子类不能调用AppKit的便利初始化器，
    /// 因此由此处一次性显式组装，并用assertSingleTextStorage证明视图没有替换其中任何对象。
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
    var onRequestSave: (() -> Void)?
    var onInputMethodCommit: ((InputMethodCommit) -> Void)?
    var onInputMethodTransactionFailure: ((String) -> Void)?
    var onTransientLayoutChange: (() -> Void)?
    var quickInputSettings = MarkdownQuickInputSettings()
    var isApplyingQuickInputReplacement = false
    var isEnforcingInputMethodAttributes = false
    /// 当前Node的标准输入样式。NSTextView.typingAttributes可能被输入法临时改写，
    /// 因此组合文字不能把它当作唯一来源。
    var nodeMarkdownTypingAttributes: [NSAttributedString.Key: Any] = [:]
    var suppressesAutomaticSelectionScrolling = false
    var usesScreenMinimumFormulaFontSize = true
    private var inputMethodTransactionActive = false
    private var inputMethodCommitPending = false
    private var inputMethodSourceBefore = ""
    private var inputMethodAffectedRange = NSRange(location: 0, length: 0)
    private var inputMethodRowLayoutsBefore: [NodeMarkdownTextKit2RowLayout] = []
    private var inputMethodGeneration: UInt64 = 0
    private var caretClickViewportGeneration: UInt64 = 0
    private var didDragSelectionWithMouse = false
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
        let textContainer = NSTextContainer(
            size: NSSize(width: 688, height: CGFloat.greatestFiniteMagnitude)
        )
        contentStorage.textStorage = textStorage
        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = textContainer
        nodeTextStorage = textStorage
        nodeTextContentStorage = contentStorage
        nodeTextLayoutManager = layoutManager
        nodeTextContainer = textContainer
        super.init(
            frame: NSRect(x: 0, y: 0, width: 720, height: 600),
            textContainer: textContainer
        )
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

    /// TextKit may expose a zero-length marked range while the view is becoming first responder.
    /// That is not an IME composition and must never block document loading or normal styling.
    var hasActiveInputMethodComposition: Bool {
        let range = markedRange()
        return inputMethodTransactionActive
            || inputMethodCommitPending
            || (range.location != NSNotFound && range.length > 0)
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
        _ = drawNodeMarkdownBackgroundBars(in: dirtyRect)
        _ = drawNodeMarkdownInlineHighlights(in: dirtyRect)
        super.draw(dirtyRect)
        _ = drawNodeMarkdownMarkers(in: dirtyRect)
    }

    override func mouseDown(with event: NSEvent) {
        didDragSelectionWithMouse = false
        let viewportOrigin = enclosingScrollView?.contentView.bounds.origin
        let displayRect = visibleRect.isEmpty ? bounds : visibleRect
        if !displayRect.isEmpty {
            let containerRect = displayRect.offsetBy(
                dx: -textContainerOrigin.x,
                dy: -textContainerOrigin.y
            )
            nodeTextLayoutManager.ensureLayout(for: containerRect)
        }
        let clickPoint = convert(event.locationInWindow, from: nil)
        // Claim the Node before NSTextView starts its mouse tracking. Entering the
        // field editor can publish SwiftUI state synchronously; without an active
        // Node that update is allowed to reload table rows and cancels this click.
        // Image attachments are also restored to source before TextKit hit-testing.
        onHandlePrimaryClick?()
        // Content缓冲区已经不含隐藏前缀，点击位置应完全交给NSTextView/TextKit2。
        super.mouseDown(with: event)
        // 拖动形成选区时mouseDown在抬起时才返回，此刻已存在完整选区；只有未拖动的
        // 单击才允许把残留选区收成插入点，拖动选区必须原样保留。
        let mouseEndedInWindow = window?.convertPoint(fromScreen: NSEvent.mouseLocation) ?? event.locationInWindow
        let didDrag = didDragSelectionWithMouse
            || hypot(
                mouseEndedInWindow.x - event.locationInWindow.x,
                mouseEndedInWindow.y - event.locationInWindow.y
            ) > 3
        if event.clickCount == 1,
           !event.modifierFlags.contains(.shift),
           selectedRange().length > 0,
           !didDrag {
            let location = min(
                characterIndexForInsertion(at: clickPoint),
                (nodeSourceTextSnapshot as NSString).length
            )
            setSelectedRange(NSRange(location: location, length: 0))
        }
        // 单击进入编辑可能切换源码/渲染样式，TextKit会据此自动调整滚动位置。
        // 点击位置原本就在当前视野内，因此这不是需要“追焦点”的场景；恢复
        // 点击前视野。拖拽形成选区时保留系统原生自动滚动。
        if event.clickCount == 1, !didDrag, let viewportOrigin {
            restoreViewportAfterCaretClick(to: viewportOrigin)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        didDragSelectionWithMouse = true
        super.mouseDragged(with: event)
    }

    private func restoreViewportAfterCaretClick(to origin: NSPoint) {
        guard let scrollView = enclosingScrollView else { return }
        caretClickViewportGeneration &+= 1
        let generation = caretClickViewportGeneration
        let selectionAfterClick = selectedRange()
        let restore = { [weak scrollView] in
            guard let scrollView else { return }
            let clipView = scrollView.contentView
            var bounds = clipView.bounds
            bounds.origin = origin
            clipView.setBoundsOrigin(clipView.constrainBoundsRect(bounds).origin)
            scrollView.reflectScrolledClipView(clipView)
        }
        restore()
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.caretClickViewportGeneration == generation,
                  self.selectedRange() == selectionAfterClick else { return }
            restore()
        }
    }

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        guard beginInputMethodTransactionIfNeeded(replacementRange: replacementRange) else {
            NSSound.beep()
            return
        }
        let canonicalAttributes = nodeMarkdownTypingAttributes.isEmpty
            ? typingAttributes
            : nodeMarkdownTypingAttributes
        super.setMarkedText(
            Self.markedText(string, applying: canonicalAttributes),
            selectedRange: selectedRange,
            replacementRange: replacementRange
        )
        enforceCanonicalAttributesOnMarkedText(canonicalAttributes)
        updateInputMethodRenderingLayouts()
        onTransientLayoutChange?()
    }

    func enforceCanonicalAttributesOnMarkedText(
        _ canonicalAttributes: [NSAttributedString.Key: Any]? = nil
    ) {
        let range = markedRange()
        guard range.location != NSNotFound,
              range.length > 0,
              let safeRange = range.exact(toLength: nodeTextStorage.length) else { return }
        let attributes = canonicalAttributes ?? nodeMarkdownTypingAttributes
        guard !attributes.isEmpty else { return }

        isEnforcingInputMethodAttributes = true
        defer { isEnforcingInputMethodAttributes = false }
        nodeTextContentStorage.performEditingTransaction {
            Self.applyControlledTypingAttributes(
                attributes,
                to: nodeTextStorage,
                range: safeRange
            )
        }
        typingAttributes = attributes
    }

    static func markedText(
        _ value: Any,
        applying typingAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let markedText: NSMutableAttributedString
        if let attributed = value as? NSAttributedString {
            markedText = NSMutableAttributedString(attributedString: attributed)
        } else {
            markedText = NSMutableAttributedString(string: String(describing: value))
        }
        guard markedText.length > 0 else { return markedText }

        // 输入法自己的下划线、分词和候选标记必须保留；只把会改变行高
        // 和行颜色的三项属性锁定为当前Node的真实设置。
        applyControlledTypingAttributes(
            typingAttributes,
            to: markedText,
            range: NSRange(location: 0, length: markedText.length)
        )
        return markedText
    }

    static func applyControlledTypingAttributes(
        _ typingAttributes: [NSAttributedString.Key: Any],
        to text: NSMutableAttributedString,
        range: NSRange
    ) {
        let controlledKeys: [NSAttributedString.Key] = [
            .font,
            .foregroundColor,
            .paragraphStyle
        ]
        let controlledAttributes = controlledKeys.reduce(into: [NSAttributedString.Key: Any]()) {
            if let attribute = typingAttributes[$1] {
                $0[$1] = attribute
            }
        }
        guard !controlledAttributes.isEmpty,
              range.exact(toLength: text.length) != nil else { return }
        text.addAttributes(controlledAttributes, range: range)
    }

    override func unmarkText() {
        let wasActive = inputMethodTransactionActive
        super.unmarkText()
        if wasActive {
            scheduleInputMethodCommit()
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let wasActive = inputMethodTransactionActive
        super.insertText(insertString, replacementRange: replacementRange)
        if wasActive {
            updateInputMethodRenderingLayouts()
            scheduleInputMethodCommit()
        }
    }

    private func beginInputMethodTransactionIfNeeded(replacementRange: NSRange) -> Bool {
        guard !inputMethodTransactionActive, !inputMethodCommitPending else { return true }
        inputMethodTransactionActive = true
        inputMethodGeneration &+= 1
        inputMethodSourceBefore = nodeSourceTextSnapshot
        inputMethodRowLayoutsBefore = nodeMarkdownRowLayouts
        let sourceLength = (inputMethodSourceBefore as NSString).length
        let requestedRange = replacementRange.location == NSNotFound
            ? selectedRange()
            : replacementRange
        guard let exactRange = requestedRange.exact(toLength: sourceLength) else {
            inputMethodTransactionActive = false
            inputMethodSourceBefore = ""
            return false
        }
        inputMethodAffectedRange = exactRange
        return true
    }

    private func scheduleInputMethodCommit() {
        guard inputMethodTransactionActive, !inputMethodCommitPending else { return }
        inputMethodTransactionActive = false
        inputMethodCommitPending = true
        let generation = inputMethodGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.inputMethodCommitPending,
                  self.inputMethodGeneration == generation else { return }
            self.finishInputMethodCommit()
        }
    }

    private func finishInputMethodCommit() {
        let sourceBefore = inputMethodSourceBefore
        let sourceLengthBefore = (sourceBefore as NSString).length
        guard let affectedRange = inputMethodAffectedRange.exact(toLength: sourceLengthBefore) else {
            failInputMethodCommit(
                reason: "提交时替换范围已与事务开始时的源码不一致"
            )
            return
        }
        let replacementLength = nodeTextStorage.length - (sourceLengthBefore - affectedRange.length)

        guard replacementLength >= 0,
              let replacementRange = NSRange(
                location: affectedRange.location,
                length: replacementLength
              ).exact(toLength: nodeTextStorage.length) else {
            failInputMethodCommit(
                reason: "TextStorage长度无法与输入法替换事务对应"
            )
            return
        }
        let replacement = (nodeTextStorage.string as NSString).substring(with: replacementRange)
        nodeSourceTextSnapshot = (sourceBefore as NSString).replacingCharacters(
            in: affectedRange,
            with: replacement
        )

        inputMethodCommitPending = false
        inputMethodSourceBefore = ""
        onInputMethodCommit?(
            InputMethodCommit(
                sourceBefore: sourceBefore,
                affectedRange: affectedRange,
                replacement: replacement
            )
        )
        inputMethodRowLayoutsBefore.removeAll(keepingCapacity: true)
    }

    private func failInputMethodCommit(reason: String) {
        inputMethodTransactionActive = false
        inputMethodCommitPending = false
        inputMethodSourceBefore = ""
        inputMethodRowLayoutsBefore.removeAll(keepingCapacity: true)
        onInputMethodTransactionFailure?(reason)
    }

    private func updateInputMethodRenderingLayouts() {
        guard inputMethodTransactionActive,
              !inputMethodRowLayoutsBefore.isEmpty else { return }
        let sourceLengthBefore = (inputMethodSourceBefore as NSString).length
        let characterDelta = nodeTextStorage.length - sourceLengthBefore
        guard let projected = NodeMarkdownTextKit2TransientLayoutProjection.project(
            inputMethodRowLayoutsBefore,
            replacing: inputMethodAffectedRange,
            characterDelta: characterDelta
        ) else {
            return
        }
        nodeMarkdownRowLayouts = projected
        let displayRect = visibleRect.isEmpty ? bounds : visibleRect
        if !displayRect.isEmpty {
            setNeedsDisplay(displayRect)
        }
    }

    /// Debug构建中立刻暴露双存储或布局链断裂，避免再次出现“能显示但不能编辑”。
    func assertSingleTextStorage(file: StaticString = #fileID, line: UInt = #line) {
        assert(nodeTextContentStorage.textStorage === nodeTextStorage, "TextKit2 content storage detached from canonical text storage", file: file, line: line)
        assert(textStorage === nodeTextStorage, "NSTextView is not editing the canonical TextKit2 text storage", file: file, line: line)
        assert(textContentStorage === nodeTextContentStorage, "NSTextView is not using the configured TextKit2 content storage", file: file, line: line)
        assert(textLayoutManager === nodeTextLayoutManager, "NSTextView is not using the configured TextKit2 layout manager", file: file, line: line)
    }

    var hasSingleTextStorage: Bool {
        nodeTextContentStorage.textStorage === nodeTextStorage
            && textStorage === nodeTextStorage
            && textContentStorage === nodeTextContentStorage
            && textLayoutManager === nodeTextLayoutManager
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
