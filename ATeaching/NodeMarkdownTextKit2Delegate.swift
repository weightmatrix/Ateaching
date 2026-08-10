// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    func restoreDocumentAfterRejectedInputMethodTransaction(
        in textView: NodeMarkdownTextKit2TextView,
        reason: String
    ) {
        let snapshot = documentState.snapshot
        guard !snapshot.nodes.isEmpty else {
            NodeMarkdownTextKit2Diagnostics.log("无法恢复被拒绝的输入法事务：Node快照为空。原因：\(reason)。")
            return
        }
        installDocument(
            snapshot.plainText,
            metadata: snapshot.rowMetadata,
            in: textView,
            preserving: textView.selectedRanges,
            reason: "拒绝输入法事务后恢复Node快照"
        )
    }

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

        // 输入法管理的拼音、候选词等只是NSTextStorage中的临时文字。
        // 正式提交前，源码快照、Node层级、附件和SwiftUI绑定一律不动。
        if textView.hasActiveInputMethodComposition {
            clearPendingNativeEdit()
            NodeMarkdownTextKit2Diagnostics.log("输入法事务中：忽略临时textDidChange，等待正式提交。")
            return
        }

        if let pendingProjectedSourceText {
            textView.commitProjectedSourceText(pendingProjectedSourceText)
            self.pendingProjectedSourceText = nil
        } else {
            clearPendingNativeEdit()
            NodeMarkdownTextKit2Diagnostics.log("拒绝无事务的textDidChange：不从附件显示文字反推源码，将恢复Node快照。")
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.restoreDocumentAfterRejectedInputMethodTransaction(
                    in: textView,
                    reason: "textDidChange缺少对应的编辑事务"
                )
            }
            return
        }

        let shouldRefreshCurrentRow = shouldRefreshCurrentRowAfterTextChange
        shouldRefreshCurrentRowAfterTextChange = true
        let quickInputEdit = textView.applyQuickInputIfNeeded(documentStyle: documentStyle)
        if let quickInputEdit {
            pendingTextEditCharacterDelta += quickInputEdit.characterDelta
            if quickInputEdit.changesLineStructure {
                pendingTextEditImpact = .document
                pendingProjectedRowMetadata = projectedMetadata(
                    source: quickInputEdit.sourceBeforeReplacement,
                    affectedRange: quickInputEdit.range,
                    replacement: quickInputEdit.replacement
                )
            }
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
        let changedStructure = pendingTextEditImpact != .character
            || documentState.nodes.count != rowLayouts.count
        clearPendingNativeEdit()
        publishTextChange(value, structural: changedStructure)

        if shouldRefreshCurrentRow || quickInputEdit != nil {
            refreshCurrentRowStyle(in: textView)
        }
        syncEditingRowWithSelection(in: textView)
        validateTextKit2State(in: textView, deep: false)
    }

    func finishInputMethodCommit(
        _ commit: NodeMarkdownTextKit2TextView.InputMethodCommit,
        in textView: NodeMarkdownTextKit2TextView
    ) {
        guard !isApplyingExternalText, !isApplyingStyleUpdate else { return }
        clearPendingNativeEdit()

        let sourceBefore = commit.sourceBefore as NSString
        pendingTextEditAffectedRange = commit.affectedRange
        pendingTextEditCharacterDelta = (commit.replacement as NSString).length - commit.affectedRange.length
        pendingTextEditImpact = classifyTextEditImpact(
            source: sourceBefore,
            affectedRange: commit.affectedRange,
            replacement: commit.replacement
        )
        pendingProjectedRowMetadata = projectedMetadata(
            source: sourceBefore,
            affectedRange: commit.affectedRange,
            replacement: commit.replacement
        )
        shouldRefreshCurrentRowAfterTextChange = true

        let value = textView.documentString()
        if let pendingProjectedRowMetadata {
            rowMetadata = pendingProjectedRowMetadata
            self.pendingProjectedRowMetadata = nil
        }
        if pendingTextEditImpact == .character,
           updateRowLayoutsAfterCharacterEdit(
                in: textView,
                value: value,
                affectedRange: commit.affectedRange,
                characterDelta: pendingTextEditCharacterDelta
           ) {
            // 普通中文确认只更新当前Node，并平移后续字符地址。
        } else {
            rebuildRowLayouts(from: textView, value: value, applyStyles: false)
        }
        let changedStructure = pendingTextEditImpact != .character
            || documentState.nodes.count != rowLayouts.count
        clearPendingNativeEdit()
        publishTextChange(value, structural: changedStructure)
        refreshCurrentRowStyle(in: textView)
        syncEditingRowWithSelection(in: textView)
        updateTypingAttributes(for: textView)
        validateTextKit2State(in: textView, deep: false)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingExternalText,
              let textView = notification.object as? NodeMarkdownTextKit2TextView else { return }

        if textView.hasActiveInputMethodComposition {
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

        if textView.hasActiveInputMethodComposition {
            clearPendingNativeEdit()
            return true
        }

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
        guard let projectedRowMetadata = projectedMetadata(
            source: source,
            affectedRange: affectedCharRange,
            replacement: replacement
        ) else {
            clearPendingNativeEdit()
            NodeMarkdownTextKit2Diagnostics.log("拒绝原生文字修改：无法用精确Node边界建立结构事务。")
            NSSound.beep()
            return false
        }
        pendingProjectedRowMetadata = projectedRowMetadata
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
        guard let exactAffectedRange = affectedRange.exact(toLength: source.length) else { return nil }
        let deletedText = affectedRange.length > 0
            ? source.substring(with: exactAffectedRange)
            : ""
        guard rowMetadata.count == rowCharacterRanges.count,
              NodeMarkdownTextKit2DocumentState.validationError(
                text: source as String,
                rowMetadata: rowMetadata
              ) == nil else { return nil }

        let deletedNewlines = deletedText.filter { $0 == "\n" }.count
        let insertedNewlines = replacement.filter { $0 == "\n" }.count
        guard deletedNewlines != insertedNewlines else { return rowMetadata }

        let anchor = affectedRange.location == source.length
            ? source.length - 1
            : affectedRange.location
        guard anchor >= 0 else { return nil }
        guard let sourceRow = lineIndexForLocation(anchor),
              rowMetadata.indices.contains(sourceRow) else { return nil }
        let insertedLevel = NodeMarkdownLegacyStructurePolicy.insertedLevel(after: rowMetadata[sourceRow])
        var result = rowMetadata
        if deletedNewlines > 0 {
            let removalStart = sourceRow + 1
            let removalEnd = removalStart + deletedNewlines
            guard removalStart >= 0, removalEnd <= result.count else { return nil }
            result.removeSubrange(removalStart..<removalEnd)
        }
        if insertedNewlines > 0 {
            let insertionIndex = sourceRow + 1
            guard (0...result.count).contains(insertionIndex) else { return nil }
            result.insert(
                contentsOf: (0..<insertedNewlines).map { _ in .fresh(level: insertedLevel) },
                at: insertionIndex
            )
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
        guard let exactRange = affectedRange.exact(toLength: source.length) else { return true }
        let deleted = exactRange.length > 0 ? source.substring(with: exactRange) : ""
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
