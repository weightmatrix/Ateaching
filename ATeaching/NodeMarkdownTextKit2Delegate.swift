// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    func textDidBeginEditing(_ notification: Notification) {
        isLocalEditingSessionActive = true
        onInputSessionStateChange?(true)
        guard let textView = notification.object as? NodeMarkdownTextKit2TextView else { return }

        updateTypingAttributes(for: textView)
        DispatchQueue.main.async { [weak self, weak textView] in
            guard let self,
                  let textView,
                  textView.window?.firstResponder === textView else { return }
            self.syncEditingRowWithSelection(in: textView)
        }
    }

    func textDidEndEditing(_ notification: Notification) {
        isLocalEditingSessionActive = false
        forgetRememberedFocus()
        if let textView = notification.object as? NodeMarkdownTextKit2TextView {
            clearEditingRow(in: textView)
        }
        onInputSessionStateChange?(false)
    }

    func textDidChange(_ notification: Notification) {
        guard !isApplyingExternalText,
              !isApplyingStyleUpdate,
              let textView = notification.object as? NodeMarkdownTextKit2TextView else { return }
        guard !textView.isApplyingQuickInputReplacement else { return }

        if let pendingProjectedSourceText {
            textView.commitProjectedSourceText(pendingProjectedSourceText)
            self.pendingProjectedSourceText = nil
        } else {
            // 输入法、系统撤销等未提供普通替换投影时，以唯一存储重建一次快照。
            textView.rebuildSourceTextSnapshotFromStorage()
        }

        // marked text由输入法独占。拼音尚未确认时不重排、不挂载附件，也不向SwiftUI发布半成品。
        if textView.markedRange().location != NSNotFound {
            clearPendingNativeEdit()
            updateTypingAttributes(for: textView)
            return
        }

        let shouldRefreshCurrentRow = shouldRefreshCurrentRowAfterTextChange
        shouldRefreshCurrentRowAfterTextChange = true
        let didApplyQuickInput = textView.applyQuickInputIfNeeded(documentStyle: documentStyle)
        if didApplyQuickInput {
            updateTypingAttributes(for: textView)
        }

        let value = textView.documentString()
        if let pendingProjectedRowMetadata {
            rowMetadata = pendingProjectedRowMetadata
            self.pendingProjectedRowMetadata = nil
        }
        updateTypingAttributes(for: textView)
        if pendingTextEditImpact == .character,
           let pendingTextEditAffectedRange,
           updateRowLayoutsAfterCharacterEdit(
                in: textView,
                value: value,
                affectedRange: pendingTextEditAffectedRange,
                characterDelta: pendingTextEditCharacterDelta
           ) {
            updateTypingAttributes(for: textView)
        } else {
            rebuildRowLayouts(from: textView, value: value, applyStyles: false)
        }
        clearPendingNativeEdit()
        publishTextChange(value)

        if shouldRefreshCurrentRow || didApplyQuickInput {
            refreshCurrentRowStyle(in: textView)
        }
        syncEditingRowWithSelection(in: textView)
        validateTextKit2State(in: textView, deep: false)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingExternalText,
              let textView = notification.object as? NodeMarkdownTextKit2TextView else { return }

        if textView.markedRange().location != NSNotFound {
            reportActiveRowIfNeeded(from: textView)
            updateTypingAttributes(for: textView)
            return
        }

        guard !isApplyingStyleUpdate else { return }
        // 到达这里的是NSTextView原生选择变化（鼠标点击、方向键等），用户的新选择结束旧结构事务。
        forgetRememberedFocus()
        syncEditingRowWithSelection(in: textView)
    }

    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        guard !isApplyingExternalText,
              !isApplyingStyleUpdate,
              let textView = textView as? NodeMarkdownTextKit2TextView else { return true }

        forgetRememberedFocus()

        let replacement = replacementString ?? ""
        let source = textView.documentString() as NSString
        pendingProjectedSourceText = textView.projectedSourceText(
            replacing: affectedCharRange,
            with: replacement
        )
        let replacementLength = (replacement as NSString).length
        pendingTextEditAffectedRange = affectedCharRange
        pendingTextEditCharacterDelta = replacementLength - affectedCharRange.length
        pendingTextEditImpact = classifyTextEditImpact(
            source: source,
            affectedRange: affectedCharRange,
            replacement: replacement
        )
        shouldRefreshCurrentRowAfterTextChange = shouldRefreshCurrentRow(
            in: textView,
            affectedRange: affectedCharRange,
            replacement: replacement
        )
        if textView.markedRange().location != NSNotFound {
            return true
        }
        pendingProjectedRowMetadata = projectedMetadata(
            source: source,
            affectedRange: affectedCharRange,
            replacement: replacement
        )
        guard let editableRange = textView.editableChangeRange(for: affectedCharRange) else {
            clearPendingNativeEdit()
            NSSound.beep()
            return false
        }

        if editableRange != affectedCharRange {
            clearPendingNativeEdit()
            replaceSourceText(
                in: textView,
                range: editableRange,
                replacement: replacement,
                selectedRange: NSRange(
                    location: editableRange.location + (replacement as NSString).length,
                    length: 0
                )
            )
            return false
        }

        if replacement.isEmpty,
           editableRange.length > 0,
           !isSingleLineContentDeletion(in: textView, affectedRange: editableRange),
           blocksCompleteProtectedH3Deletion(in: textView, affectedRange: editableRange) {
            clearPendingNativeEdit()
            return false
        }

        guard let imageEdit = protectedImageTokenEdit(
            in: textView,
            affectedRange: affectedCharRange,
            replacement: replacement
        ) else {
            updateTypingAttributes(for: textView)
            return true
        }

        clearPendingNativeEdit()
        replaceSourceText(
            in: textView,
            range: imageEdit.replacementRange,
            replacement: imageEdit.replacement,
            selectedRange: NSRange(
                location: imageEdit.replacementRange.location + (imageEdit.replacement as NSString).length,
                length: 0
            )
        )
        return false
    }

    private func clearPendingNativeEdit() {
        pendingProjectedSourceText = nil
        pendingProjectedRowMetadata = nil
        pendingTextEditImpact = .document
        pendingTextEditAffectedRange = nil
        pendingTextEditCharacterDelta = 0
        shouldRefreshCurrentRowAfterTextChange = true
    }

    private func classifyTextEditImpact(
        source: NSString,
        affectedRange: NSRange,
        replacement: String
    ) -> EditorDeletionImpact {
        if replacement.isEmpty, affectedRange.length > 0 {
            return EditorDeletionClassifier.classifyDeletion(
                source: source,
                affectedRange: affectedRange
            ) { _ in 0 }
        }
        if replacement.contains("\n") || replacement.contains("\r") {
            return .line
        }
        return EditorDeletionClassifier.classifyDeletion(
            source: source,
            affectedRange: affectedRange
        ) { _ in 0 }
    }

    private func projectedMetadata(
        source: NSString,
        affectedRange: NSRange,
        replacement: String
    ) -> [NodeMarkdownTextKitRowMetadata]? {
        let deletedText = affectedRange.length > 0
            ? source.substring(with: affectedRange.clamped(toLength: source.length) ?? NSRange(location: 0, length: 0))
            : ""
        let deletedNewlines = deletedText.filter { $0 == "\n" }.count
        let insertedNewlines = replacement.filter { $0 == "\n" }.count
        guard deletedNewlines != insertedNewlines else { return nil }

        let safeLocation = max(0, min(affectedRange.location, source.length))
        let prefix = source.substring(to: safeLocation)
        let sourceRow = prefix.filter { $0 == "\n" }.count
        let inheritedLevel = rowMetadata.indices.contains(sourceRow) ? rowMetadata[sourceRow].level : 7
        var result = rowMetadata
        if insertedNewlines > deletedNewlines {
            let count = insertedNewlines - deletedNewlines
            let insertionIndex = min(result.count, sourceRow + 1)
            result.insert(
                contentsOf: (0..<count).map { _ in .fresh(level: inheritedLevel) },
                at: insertionIndex
            )
        } else {
            let count = deletedNewlines - insertedNewlines
            let removalStart = min(result.count, sourceRow + 1)
            let removalEnd = min(result.count, removalStart + count)
            if removalStart < removalEnd {
                result.removeSubrange(removalStart..<removalEnd)
            }
        }
        return result
    }

    private func isSingleLineContentDeletion(
        in textView: NodeMarkdownTextKit2TextView,
        affectedRange: NSRange
    ) -> Bool {
        let source = textView.documentString() as NSString
        let impact = EditorDeletionClassifier.classifyDeletion(
            source: source,
            affectedRange: affectedRange
        ) { _ in 0 }
        return impact == .character
    }

    private func shouldRefreshCurrentRow(
        in textView: NodeMarkdownTextKit2TextView,
        affectedRange: NSRange,
        replacement: String
    ) -> Bool {
        let source = textView.documentString() as NSString
        let deleted = affectedRange.length > 0
            ? source.substring(with: affectedRange.clamped(toLength: source.length) ?? NSRange(location: 0, length: 0))
            : ""
        let inlineSyntax = "*_`~=<>[]()"
        return replacement.contains("\n")
            || replacement.contains("\r")
            || replacement.contains { inlineSyntax.contains($0) }
            || deleted.contains { inlineSyntax.contains($0) }
    }

    private func syncEditingRowWithSelection(in textView: NodeMarkdownTextKit2TextView) {
        enterEditingRowIfNeeded(from: textView)
        updateTypingAttributes(for: textView)
        applyTypingAttributesToMarkedText(in: textView)
    }
}
#endif
