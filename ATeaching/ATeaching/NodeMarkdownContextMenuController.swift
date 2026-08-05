#if os(macOS)
import AppKit

final class NodeMarkdownContextMenuController {
    struct Context {
        var canCutPackage: Bool
        var canDeletePackage: Bool
        var canPastePackage: Bool
        var canMotherDelete: Bool
    }

    static func makeMenu(target: AnyObject, context: Context) -> NSMenu {
        let menu = NSMenu()
        let cutItem = item(title: "剪切", action: Selector(("handleCutPackageMenuAction")), target: target)
        cutItem.isEnabled = context.canCutPackage
        menu.addItem(cutItem)
        let pasteItem = item(title: "粘贴", action: Selector(("handlePastePackageMenuAction")), target: target)
        pasteItem.isEnabled = context.canPastePackage
        menu.addItem(pasteItem)
        menu.addItem(.separator())
        let deleteItem = item(title: "包删除", action: Selector(("handleDeleteNodePackageMenuAction")), target: target)
        deleteItem.isEnabled = context.canDeletePackage
        menu.addItem(deleteItem)
        menu.addItem(item(title: "插入图片", action: Selector(("handleInsertImageMenuAction")), target: target))
        if context.canMotherDelete {
            menu.addItem(item(title: "母本删除", action: Selector(("handleDeleteProtectedH3MenuAction")), target: target))
        }
        menu.addItem(item(title: "画图", action: Selector(("handleOpenDrawingBoardMenuAction")), target: target))
        return menu
    }

    private static func item(title: String, action: Selector, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        return item
    }
}
#endif
