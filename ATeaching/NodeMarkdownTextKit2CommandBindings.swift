// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    func configureCommandHandlers(for textView: NodeMarkdownTextKit2TextView) {
        textView.onRequestInsertImage = { [weak self, weak textView] in
            guard let self, let textView, let rowIndex = self.currentRowIndex(in: textView) else { return }
            let transaction = self.beginDiagnostic41("图片粘贴/文件插入 row=\(rowIndex)", in: textView)
            guard let updatedRowText = self.onRequestInsertImageAtRow?(rowIndex) else {
                self.finishDiagnostic41(transaction, in: textView, stage: "父页面未返回图片正文")
                return
            }
            self.applyPreparedImageText(updatedRowText, at: rowIndex, in: textView)
            self.finishDiagnostic41(transaction, in: textView)
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
            let transaction = self.beginDiagnostic41("打开画图板 row=\(rowIndex)", in: textView)
            self.onRequestOpenDrawingBoardAtRow?(rowIndex)
            self.finishDiagnostic41(transaction, in: textView, stage: "画图板请求返回")
        }
        textView.onHandleTabCommand = { [weak self, weak textView] increaseLevel in
            guard let self, let textView else { return false }
            let transaction = self.beginDiagnostic41(increaseLevel ? "Tab" : "Shift+Tab", in: textView)
            let handled = self.handleTabCommand(in: textView, increaseLevel: increaseLevel)
            self.finishDiagnostic41(transaction, in: textView, stage: "命令返回 handled=\(handled)")
            return handled
        }
        textView.onHandleInsertNewline = { [weak self, weak textView] in
            guard let self, let textView else { return false }
            let transaction = self.beginDiagnostic41("回车", in: textView)
            let handled = self.handleInsertNewline(in: textView)
            self.finishDiagnostic41(transaction, in: textView, stage: "命令返回 handled=\(handled)")
            return handled
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
            let transaction = self.beginDiagnostic41("点击进入编辑", in: textView)
            self.handlePrimaryClick(in: textView)
            self.finishDiagnostic41(transaction, in: textView)
        }
        textView.onRequestSave = { [weak self] in
            self?.onRequestSave?()
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
