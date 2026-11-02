// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2TextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleImagePasteShortcut(event) {
            return true
        }
        if handleSaveShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func doCommand(by selector: Selector) {
        let diagnostic117OperationID = selector == #selector(NSResponder.deleteBackward(_:))
            ? beginDiagnostic117BackspaceIfNeeded()
            : nil
        if handleNodeMarkdownCommand(selector) {
            if let diagnostic117OperationID {
                NodeMarkdownDiagnostic117.record(
                    operationID: diagnostic117OperationID,
                    "doCommand已消费Backspace selection=\(NSStringFromRange(selectedRange())) source=\(NodeMarkdownDiagnostic117.textSummary(documentString()))"
                )
                recordDiagnostic117Deferred(operationID: diagnostic117OperationID)
            }
            return
        }
        super.doCommand(by: selector)
    }

    override func keyDown(with event: NSEvent) {
        if handleImagePasteShortcut(event) {
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let usesCommandLikeModifier = flags.contains(.command)
            || flags.contains(.control)
            || flags.contains(.option)

        if event.keyCode == 6,
           flags.contains(.command),
           !flags.contains(.control),
           !flags.contains(.option) {
            if flags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return
        }

        if event.keyCode == 48 && !usesCommandLikeModifier {
            let selector = flags.contains(.shift)
                ? #selector(NSResponder.insertBacktab(_:))
                : #selector(NSResponder.insertTab(_:))
            doCommand(by: selector)
            return
        }

        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        if NodeMarkdownImageAssetService.hasPastedImage() {
            onRequestInsertImage?()
            return
        }
        super.paste(sender)
    }

    /// 纯Command+V粘贴图片与右键“插入图片”共用同一请求入口。
    /// 剪贴板不含图片时不消费按键，保留系统文本粘贴。
    private func handleImagePasteShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.shift),
              !flags.contains(.option),
              !flags.contains(.control),
              event.charactersIgnoringModifiers?.lowercased() == "v",
              NodeMarkdownImageAssetService.hasPastedImage() else {
            return false
        }
        guard self.window?.firstResponder === self else { return false }
        onRequestInsertImage?()
        return true
    }

    private func handleSaveShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.shift),
              !flags.contains(.option),
              !flags.contains(.control),
              event.charactersIgnoringModifiers?.lowercased() == "s" else {
            return false
        }
        onRequestSave?()
        return true
    }

    private func handleNodeMarkdownCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertTab(_:)),
             #selector(NSResponder.insertTabIgnoringFieldEditor(_:)):
            return onHandleTabCommand?(true) == true

        case #selector(NSResponder.insertBacktab(_:)):
            return onHandleTabCommand?(false) == true

        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            return onHandleInsertNewline?() == true

        case #selector(NSResponder.deleteBackward(_:)):
            return onHandleDeleteBackward?() == true

        case #selector(NSResponder.deleteForward(_:)):
            return onHandleDeleteForward?() == true

        case #selector(NSResponder.moveUp(_:)):
            return onHandleVerticalMove?(-1) == true

        case #selector(NSResponder.moveDown(_:)):
            return onHandleVerticalMove?(1) == true

        case #selector(NSResponder.cancelOperation(_:)):
            return onHandleCancelOperation?() == true

        default:
            return false
        }
    }
}
#endif
