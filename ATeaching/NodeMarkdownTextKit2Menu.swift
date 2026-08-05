// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2TextView {
    override func menu(for event: NSEvent) -> NSMenu? {
        NodeMarkdownContextMenuController.makeMenu(
            target: self,
            context: .init(
                canCutPackage: canCutNodePackage?() ?? false,
                canDeletePackage: canDeleteNodePackage?() ?? false,
                canPastePackage: canPasteNodePackage?() ?? false,
                canMotherDelete: canDeleteProtectedH3?() ?? false
            )
        )
    }

    @objc func handleCutPackageMenuAction() {
        onRequestCutNodePackage?()
    }

    @objc func handlePastePackageMenuAction() {
        onRequestPasteNodePackage?()
    }

    @objc func handleDeleteNodePackageMenuAction() {
        onRequestDeleteNodePackage?()
    }

    @objc func handleInsertImageMenuAction() {
        onRequestInsertImage?()
    }

    @objc func handleDeleteProtectedH3MenuAction() {
        onRequestDeleteProtectedH3?()
    }

    @objc func handleOpenDrawingBoardMenuAction() {
        onRequestOpenDrawingBoard?()
    }
}
#endif
