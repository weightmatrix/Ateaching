// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

enum NodeMarkdownTextKit2NativeEditPolicy {
    static func shouldDeferSelectionSynchronization(hasPendingSourceProjection: Bool) -> Bool {
        hasPendingSourceProjection
    }

    static func seamRows(afterSettling affectedRange: NSRange?, rowIndex: Int?) -> Set<Int> {
        guard let affectedRange, affectedRange.length > 0, let rowIndex else { return [] }
        return [rowIndex, rowIndex + 1]
    }
}

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
        guard !textView.isEnforcingInputMethodAttributes else { return }
        guard !textView.isApplyingQuickInputReplacement else { return }
        let diagnostic41 = diagnostic41TextTransaction ?? beginDiagnostic41("无前置事务的textDidChange", in: textView)
        let diagnosticStart = NodeMarkdownDiagnostic35.now()
        defer { recordDiagnostic35Duration("textDidChange总计", since: diagnosticStart) }
        recordDiagnostic35Count("textDidChange次数")
        NodeMarkdownDiagnostic31.record("textDidChange进入", in: textView, rowLayouts: rowLayouts)

        // 输入法管理的拼音、候选词等只是NSTextStorage中的临时文字。
        // 正式提交前，源码快照、Node层级、附件和SwiftUI绑定一律不动。
        if textView.hasActiveInputMethodComposition {
            let compositionStart = NodeMarkdownDiagnostic35.now()
            clearPendingNativeEdit()
            applyTypingAttributesToMarkedText(in: textView)
            recordDiagnostic35Duration("组合态属性", since: compositionStart)
            recordDiagnostic35Count("组合态临时通知")
            NodeMarkdownTextKit2Diagnostics.log("输入法事务中：忽略临时textDidChange，等待正式提交。")
            NodeMarkdownDiagnostic31.record("textDidChange输入法临时态返回", in: textView, rowLayouts: rowLayouts)
            finishDiagnostic41(diagnostic41, in: textView, stage: "输入法临时态返回")
            diagnostic41TextTransaction = nil
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
            finishDiagnostic41(diagnostic41, in: textView, stage: "缺少投影，安排恢复")
            diagnostic41TextTransaction = nil
            return
        }

        let quickInputStart = NodeMarkdownDiagnostic35.now()
        let quickInputEdit = textView.applyQuickInputIfNeeded(documentStyle: documentStyle)
        recordDiagnostic35Duration("快捷输入检查", since: quickInputStart)
        if let quickInputEdit {
            if quickInputEdit.changesLineStructure {
                pendingTextEditImpact = .document
                pendingProjectedRowMetadata = projectedMetadata(
                    source: quickInputEdit.sourceBeforeReplacement,
                    affectedRange: quickInputEdit.range,
                    replacement: quickInputEdit.replacement
                )
            }
        }

        let value = textView.documentString()
        let settledAffectedRange = pendingTextEditAffectedRange
        if let pendingProjectedRowMetadata {
            rowMetadata = pendingProjectedRowMetadata
            self.pendingProjectedRowMetadata = nil
        }
        let layoutStart = NodeMarkdownDiagnostic35.now()
        if pendingTextEditImpact == .character,
           let pendingTextEditAffectedRange,
           updateRowLayoutsAfterCharacterEdit(
                in: textView,
                value: value,
                affectedRange: pendingTextEditAffectedRange
           ) {
            // 当前Node的输入属性在允许系统写入前已经确定；增量布局只维护坐标。
        } else {
            rebuildRowLayouts(from: textView, value: value, applyStyles: false)
        }
        recordDiagnostic35Duration("行坐标更新入口", since: layoutStart)
        let changedStructure = pendingTextEditImpact != .character
            || documentState.nodes.count != rowLayouts.count
        let shouldRefreshAfterEdit = changedStructure
        clearPendingNativeEdit()
        let publishStart = NodeMarkdownDiagnostic35.now()
        publishTextChange(value, structural: changedStructure)
        recordDiagnostic35Duration("Node发布", since: publishStart)
        NodeMarkdownDiagnostic31.record("textDidChange发布正文后", in: textView, rowLayouts: rowLayouts)

        let seamRow = settledAffectedRange.flatMap { range -> Int? in
            guard !rowLayouts.isEmpty else { return nil }
            let documentLength = (value as NSString).length
            let location = documentLength == 0
                ? 0
                : min(range.location, documentLength - 1)
            return lineIndexForLocation(location)
        }
        var rowsToRefresh = NodeMarkdownTextKit2NativeEditPolicy.seamRows(
            afterSettling: settledAffectedRange,
            rowIndex: seamRow
        )
        if shouldRefreshAfterEdit,
           let currentRow = currentRowIndex(in: textView) {
            rowsToRefresh.insert(currentRow)
        }
        if !rowsToRefresh.isEmpty {
            recordDiagnostic35Count(
                shouldRefreshAfterEdit
                    ? "局部样式来源-结构事务与删除接缝"
                    : "局部样式来源-替换事务接缝"
            )
            let styleStart = NodeMarkdownDiagnostic35.now()
            refreshRowStyles(in: textView, rows: rowsToRefresh)
            recordDiagnostic35Duration("当前行与删除接缝刷新", since: styleStart)
        }
        let selectionStart = NodeMarkdownDiagnostic35.now()
        syncEditingRowWithSelection(in: textView)
        recordDiagnostic35Duration("编辑行同步", since: selectionStart)
        NodeMarkdownDiagnostic31.record("textDidChange刷新与同步编辑行后", in: textView, rowLayouts: rowLayouts)
        NodeMarkdownDiagnostic31.recordDeferredState(
            after: 0,
            stage: "textDidChange下一轮主队列",
            in: textView,
            rowLayouts: { [weak self] in self?.rowLayouts ?? [] }
        )
        NodeMarkdownDiagnostic31.recordDeferredState(
            after: 0.12,
            stage: "textDidChange后120ms",
            in: textView,
            rowLayouts: { [weak self] in self?.rowLayouts ?? [] }
        )
        let validationStart = NodeMarkdownDiagnostic35.now()
        validateTextKit2State(in: textView, deep: false)
        finishDiagnostic41(diagnostic41, in: textView)
        diagnostic41TextTransaction = nil
        recordDiagnostic35Duration("轻校验", since: validationStart)
    }

    func finishInputMethodCommit(
        _ commit: NodeMarkdownTextKit2TextView.InputMethodCommit,
        in textView: NodeMarkdownTextKit2TextView
    ) {
        guard !isApplyingExternalText, !isApplyingStyleUpdate else { return }
        let diagnostic41 = beginDiagnostic41("输入法正式提交 replacementUTF16=\((commit.replacement as NSString).length)", in: textView)
        let diagnosticStart = NodeMarkdownDiagnostic35.now()
        defer { recordDiagnostic35Duration("中文正式提交总计", since: diagnosticStart) }
        recordDiagnostic35Count("中文正式提交")
        NodeMarkdownDiagnostic31.noteCommittedReplacement(commit.replacement, in: textView, rowLayouts: rowLayouts)
        NodeMarkdownDiagnostic31.record("输入法正式提交进入", in: textView, rowLayouts: rowLayouts)
        prepareNodeSessionForTextChange(affectedRange: commit.affectedRange)
        clearPendingNativeEdit()

        let sourceBefore = commit.sourceBefore as NSString
        pendingTextEditAffectedRange = commit.affectedRange
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
        let value = textView.documentString()
        if let pendingProjectedRowMetadata {
            rowMetadata = pendingProjectedRowMetadata
            self.pendingProjectedRowMetadata = nil
        }
        let layoutStart = NodeMarkdownDiagnostic35.now()
        if pendingTextEditImpact == .character,
           updateRowLayoutsAfterCharacterEdit(
                in: textView,
                value: value,
                affectedRange: commit.affectedRange
           ) {
            // 普通中文确认只更新当前Node，并平移后续字符地址。
        } else {
            rebuildRowLayouts(from: textView, value: value, applyStyles: false)
        }
        recordDiagnostic35Duration("中文行坐标更新入口", since: layoutStart)
        let changedStructure = pendingTextEditImpact != .character
            || documentState.nodes.count != rowLayouts.count
        let shouldRefreshCommittedRow = changedStructure
        clearPendingNativeEdit()
        let publishStart = NodeMarkdownDiagnostic35.now()
        publishTextChange(value, structural: changedStructure)
        recordDiagnostic35Duration("中文Node发布", since: publishStart)
        if shouldRefreshCommittedRow {
            recordDiagnostic35Count("局部样式来源-中文结构变化")
            let styleStart = NodeMarkdownDiagnostic35.now()
            refreshCurrentRowStyle(in: textView)
            recordDiagnostic35Duration("中文当前行刷新入口", since: styleStart)
        }
        let selectionStart = NodeMarkdownDiagnostic35.now()
        syncEditingRowWithSelection(in: textView)
        recordDiagnostic35Duration("中文编辑行同步", since: selectionStart)
        NodeMarkdownDiagnostic31.record("输入法正式提交完成", in: textView, rowLayouts: rowLayouts)
        for (delay, label) in [(0.0, "提交后下一轮"), (0.05, "提交后50ms"), (0.25, "提交后250ms"), (1.0, "提交后1s")] {
            NodeMarkdownDiagnostic31.recordDeferredState(
                after: delay,
                stage: label,
                in: textView,
                rowLayouts: { [weak self] in self?.rowLayouts ?? [] }
            )
        }
        let validationStart = NodeMarkdownDiagnostic35.now()
        validateTextKit2State(in: textView, deep: false)
        finishDiagnostic41(diagnostic41, in: textView)
        recordDiagnostic35Duration("中文轻校验", since: validationStart)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingExternalText,
              let textView = notification.object as? NodeMarkdownTextKit2TextView else { return }
        NodeMarkdownDiagnostic31.record(
            "选区通知 applyingStyle=\(isApplyingStyleUpdate) composition=\(textView.hasActiveInputMethodComposition)",
            in: textView,
            rowLayouts: rowLayouts
        )

        if textView.hasActiveInputMethodComposition {
            reportActiveRowIfNeeded(from: textView)
            updateTypingAttributes(for: textView)
            applyTypingAttributesToMarkedText(in: textView)
            return
        }

        guard !isApplyingStyleUpdate else { return }
        if NodeMarkdownTextKit2NativeEditPolicy.shouldDeferSelectionSynchronization(
            hasPendingSourceProjection: pendingProjectedSourceText != nil
        ) {
            let affectedDescription = pendingTextEditAffectedRange.map {
                NSStringFromRange($0)
            } ?? "nil"
            NodeMarkdownDiagnostic41.event(
                "原生编辑尚未结算，推迟选区同步 selection=\(NSStringFromRange(textView.selectedRange())) affected=\(affectedDescription)"
            )
            return
        }
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

        let diagnosticStart = NodeMarkdownDiagnostic35.now()
        defer { recordDiagnostic35Duration("shouldChangeText总计", since: diagnosticStart) }
        let replacement = replacementString ?? ""
        let diagnostic41 = beginDiagnostic41(
            "文字修改 range=\(NSStringFromRange(affectedCharRange)) replacement=\(NodeMarkdownDiagnostic26.textSummary(replacement)) composition=\(textView.hasActiveInputMethodComposition)",
            in: textView
        )
        diagnostic41TextTransaction = diagnostic41
        beginDiagnostic35Input(
            in: textView,
            affectedRange: affectedCharRange,
            isComposition: textView.hasActiveInputMethodComposition
        )
        recordDiagnostic35Count("替换UTF16", amount: (replacement as NSString).length)
        NodeMarkdownDiagnostic31.startIfNeeded(
            in: textView,
            rowLayouts: rowLayouts,
            rowMetadata: rowMetadata,
            affectedRange: affectedCharRange,
            replacement: replacement
        )
        NodeMarkdownDiagnostic31.record("shouldChangeText进入", in: textView, rowLayouts: rowLayouts)

        prepareNodeSessionForTextChange(affectedRange: affectedCharRange)

        if textView.hasActiveInputMethodComposition {
            clearPendingNativeEdit()
            return true
        }

        forgetRememberedFocus()

        let source = textView.documentString() as NSString
        let projectionStart = NodeMarkdownDiagnostic35.now()
        pendingProjectedSourceText = textView.projectedSourceText(
            replacing: affectedCharRange,
            with: replacement
        )
        recordDiagnostic35Duration("整篇字符串投影", since: projectionStart)
        pendingTextEditAffectedRange = affectedCharRange
        pendingTextEditImpact = classifyTextEditImpact(
            source: source,
            affectedRange: affectedCharRange,
            replacement: replacement
        )
        let metadataStart = NodeMarkdownDiagnostic35.now()
        guard let projectedRowMetadata = projectedMetadata(
            source: source,
            affectedRange: affectedCharRange,
            replacement: replacement
        ) else {
            recordDiagnostic35Duration("Node元数据投影", since: metadataStart)
            clearPendingNativeEdit()
            NodeMarkdownTextKit2Diagnostics.log("拒绝原生文字修改：无法用精确Node边界建立结构事务。")
            NSSound.beep()
            return false
        }
        recordDiagnostic35Duration("Node元数据投影", since: metadataStart)
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
            NodeMarkdownDiagnostic31.record("shouldChangeText允许系统写入", in: textView, rowLayouts: rowLayouts)
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
        let deletedNewlines = deletedText.filter { $0 == "\n" }.count
        let insertedNewlines = replacement.filter { $0 == "\n" }.count
        guard rowMetadata.count == rowCharacterRanges.count else { return nil }
        // 普通字符不会改变Node数量或身份。它只沿用当前元数据，禁止每键拆分全文、
        // 遍历全部UUID和Source字段；完整数据契约只属于结构事务。
        guard deletedNewlines != insertedNewlines else { return rowMetadata }
        guard NodeMarkdownTextKit2DocumentState.validationError(
            text: source as String,
            rowMetadata: rowMetadata
        ) == nil else { return nil }

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

    func syncEditingRowWithSelection(in textView: NodeMarkdownTextKit2TextView) {
        // 字符事务已经维护了现有行坐标。连续输入期间先比较当前行，只有真正
        // 跨Node时才进入编辑行切换；禁止每键比较整篇源码并探测全文重建。
        let selectedRow = currentRowIndex(in: textView)
        if selectedRow != editingRowIndex {
            enterEditingRow(selectedRow, from: textView)
            updateTypingAttributes(for: textView)
        }
        applyTypingAttributesToMarkedText(in: textView)
    }
}
#endif
