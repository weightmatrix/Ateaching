// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Representable {
    func makeNSView(context: Context) -> NSScrollView {
        #if DEBUG
        NodeMarkdownTextKit2RegressionSuite.runOnce()
        #endif
        let textView = makeConfiguredTextView(context: context)
        context.coordinator.attach(textView)
        context.coordinator.configureCommandHandlers(for: textView)
        context.coordinator.installDocument(
            text,
            metadata: rowMetadata,
            in: textView,
            reason: "makeNSView首次载入"
        )
        let scrollView = makeConfiguredScrollView(textView: textView)
        context.coordinator.prepareViewport(in: textView, scrollView: scrollView)
        NodeMarkdownTextKit2Diagnostics.report(
            stage: "makeNSView返回前",
            textView: textView,
            bindingText: text,
            metadataCount: rowMetadata.count,
            rowLayoutCount: context.coordinator.rowLayouts.count
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NodeMarkdownTextKit2TextView else { return }
        NodeMarkdownDiagnostic31.record(
            "updateNSView进入 binding/storage=\((text as NSString).length)/\(textView.nodeTextStorage.length) token=\(externalTextSyncToken)/\(context.coordinator.lastExternalTextSyncToken)",
            in: textView,
            rowLayouts: context.coordinator.rowLayouts
        )
        NodeMarkdownTextKit2Diagnostics.log("updateNSView进入，binding长度=\((text as NSString).length)，storage长度=\(textView.nodeTextStorage.length)，同步Token=\(externalTextSyncToken)，上次Token=\(context.coordinator.lastExternalTextSyncToken)。")
        let hasExplicitExternalSync = context.coordinator.hasPendingExternalTextSync(
            externalTextSyncToken
        )
        if hasExplicitExternalSync {
            // 必须在接收新行元数据之前按旧Node UUID记住焦点。插包改变前文长度后，
            // 绝不能用旧的全文字符位置恢复选择。
            context.coordinator.rememberFocus(in: textView)
        }
        context.coordinator.update(
            externalText: text,
            workingDirectoryURL: workingDirectoryURL,
            documentStyle: documentStyle,
            activeRowIndex: activeRowIndex,
            activeMatchLocationInRow: activeMatchLocationInRow,
            editingRowIndex: editingRowIndex,
            searchQuery: searchQuery,
            rowMetadata: rowMetadata,
            externalTextSyncToken: externalTextSyncToken,
            quickInputSettings: quickInputSettings,
            onTextChange: onTextChange,
            onTextChangeWithRowMetadata: onTextChangeWithRowMetadata,
            onRequestInsertImageAtRow: onRequestInsertImageAtRow,
            onRequestDeleteNodePackageAtRow: onRequestDeleteNodePackageAtRow,
            onRequestCutNodePackageAtRow: onRequestCutNodePackageAtRow,
            onRequestPasteNodePackageAfterRow: onRequestPasteNodePackageAfterRow,
            canPasteNodePackage: canPasteNodePackage,
            onRequestDeleteProtectedH3AtRow: onRequestDeleteProtectedH3AtRow,
            onRequestOpenDrawingBoardAtRow: onRequestOpenDrawingBoardAtRow,
            onActiveRowChange: onActiveRowChange,
            onFocusLocationChange: onFocusLocationChange,
            onDocumentSnapshot: onDocumentSnapshot,
            onCommitEditingNode: onCommitEditingNode,
            onEditingDraftDirtyChange: onEditingDraftDirtyChange,
            onRequestSave: onRequestSave,
            onInputSessionStateChange: onInputSessionStateChange
        )
        context.coordinator.attach(textView)
        context.coordinator.configureCommandHandlers(for: textView)
        context.coordinator.synchronize(
            textView,
            externalText: text,
            externalTextSyncToken: externalTextSyncToken
        )
        NodeMarkdownDiagnostic31.record(
            "updateNSView同步返回 pendingFocus=\(context.coordinator.pendingFocusAnchor != nil) editingRow=\(context.coordinator.editingRowIndex.map(String.init) ?? "nil")",
            in: textView,
            rowLayouts: context.coordinator.rowLayouts
        )
        if hasExplicitExternalSync {
            context.coordinator.prepareViewport(in: textView, scrollView: scrollView)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: NodeMarkdownTextKit2Coordinator) {
        guard let textView = scrollView.documentView as? NodeMarkdownTextKit2TextView else { return }
        textView.isHidden = true
    }
}
#endif
