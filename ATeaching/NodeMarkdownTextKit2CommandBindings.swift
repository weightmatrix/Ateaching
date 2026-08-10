// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    func configureCommandHandlers(for textView: NodeMarkdownTextKit2TextView) {
        textView.onRequestInsertImage = { [weak self, weak textView] in
            guard let self, let textView, let rowIndex = self.currentRowIndex(in: textView) else { return }
            guard let updatedRowText = self.onRequestInsertImageAtRow?(rowIndex) else { return }
            self.applyPreparedImageText(updatedRowText, at: rowIndex, in: textView)
        }
        textView.onRequestDeleteNodePackage = { [weak self, weak textView] in
            guard let self, let textView, let rowIndex = self.currentRowIndex(in: textView) else { return }
            self.prepareDestructiveExternalOperation()
            self.onRequestDeleteNodePackageAtRow?(rowIndex)
        }
        textView.onRequestCutNodePackage = { [weak self, weak textView] in
            guard let self, let textView, let rowIndex = self.currentRowIndex(in: textView) else { return }
            self.onRequestCutNodePackageAtRow?(rowIndex)
        }
        textView.onRequestPasteNodePackage = { [weak self, weak textView] in
            guard let self, let textView, let rowIndex = self.currentRowIndex(in: textView) else { return }
            self.onRequestPasteNodePackageAfterRow?(rowIndex)
        }
        textView.canPasteNodePackage = { [weak self] in
            self?.canPasteNodePackage?() ?? false
        }
        textView.canCutNodePackage = { [weak self, weak textView] in
            guard let self, let textView, let rowIndex = self.currentRowIndex(in: textView) else { return false }
            return self.canMutateNodePackage(at: rowIndex)
        }
        textView.canDeleteNodePackage = { [weak self, weak textView] in
            guard let self, let textView, let rowIndex = self.currentRowIndex(in: textView) else { return false }
            return self.canMutateNodePackage(at: rowIndex)
        }
        textView.canDeleteProtectedH3 = { [weak self, weak textView] in
            guard let self, let textView, let rowIndex = self.currentRowIndex(in: textView) else { return false }
            return self.isProtectedH3PackageRoot(at: rowIndex)
        }
        textView.onRequestDeleteProtectedH3 = { [weak self, weak textView] in
            guard let self, let textView, let rowIndex = self.currentRowIndex(in: textView) else { return }
            self.prepareDestructiveExternalOperation()
            self.onRequestDeleteProtectedH3AtRow?(rowIndex)
        }
        textView.onRequestOpenDrawingBoard = { [weak self, weak textView] in
            guard let self, let textView, let rowIndex = self.currentRowIndex(in: textView) else { return }
            self.onRequestOpenDrawingBoardAtRow?(rowIndex)
        }
        textView.onHandleTabCommand = { [weak self, weak textView] increaseLevel in
            guard let self, let textView else { return false }
            return self.handleTabCommand(in: textView, increaseLevel: increaseLevel)
        }
        textView.onHandleInsertNewline = { [weak self, weak textView] in
            guard let self, let textView else { return false }
            return self.handleInsertNewline(in: textView)
        }
        textView.onHandleDeleteBackward = { [weak self, weak textView] in
            guard let self, let textView else { return false }
            return self.handleDeleteBackward(in: textView)
        }
        textView.onHandleDeleteForward = { [weak self, weak textView] in
            guard let self, let textView else { return false }
            return self.handleDeleteForward(in: textView)
        }
        textView.onHandleVerticalMove = { [weak self, weak textView] direction in
            guard let self, let textView else { return false }
            return self.handleVerticalMove(in: textView, direction: direction)
        }
        textView.onHandleCancelOperation = { [weak self, weak textView] in
            guard let self, let textView else { return false }
            return self.handleCancelOperation(in: textView)
        }
        textView.onHandlePrimaryClick = { [weak self, weak textView] in
            guard let self, let textView else { return }
            self.handlePrimaryClick(in: textView)
        }
        textView.onInputMethodCommit = { [weak self, weak textView] commit in
            guard let self, let textView else { return }
            self.finishInputMethodCommit(commit, in: textView)
        }
        textView.onInputMethodTransactionFailure = { [weak self, weak textView] reason in
            guard let self, let textView else { return }
            self.restoreDocumentAfterRejectedInputMethodTransaction(
                in: textView,
                reason: reason
            )
        }
        textView.quickInputSettings = quickInputSettings
    }

    func canMutateNodePackage(at rowIndex: Int) -> Bool {
        rowLayouts.indices.contains(rowIndex)
    }

    func isProtectedH3PackageRoot(at rowIndex: Int) -> Bool {
        rowLayouts.indices.contains(rowIndex) && rowLayouts[rowIndex].isProtectedH3
    }

    /// 删除请求不携带替代行焦点；只有父文档确认删除成功后才真正失焦。
    private func prepareDestructiveExternalOperation() {
        forgetRememberedFocus()
    }
}
#endif
