// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Representable {
    func makeNSView(context: Context) -> NSScrollView {
        let textView = makeConfiguredTextView(context: context)
        context.coordinator.attach(textView)
        context.coordinator.configureCommandHandlers(for: textView)
        context.coordinator.rebuildRowRanges(from: textView)
        return makeConfiguredScrollView(textView: textView)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NodeMarkdownTextKit2TextView else { return }
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
            onInputSessionStateChange: onInputSessionStateChange
        )
        context.coordinator.attach(textView)
        context.coordinator.configureCommandHandlers(for: textView)
        context.coordinator.synchronize(
            textView,
            externalText: text,
            externalTextSyncToken: externalTextSyncToken
        )
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: NodeMarkdownTextKit2Coordinator) {
        guard let textView = scrollView.documentView as? NodeMarkdownTextKit2TextView else { return }
        textView.isHidden = true
    }
}
#endif
