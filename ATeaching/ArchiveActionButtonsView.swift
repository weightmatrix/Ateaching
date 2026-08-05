import SwiftUI

// MARK: - 档案按钮栏 - v2 - 统一承载新建文件新建文件夹多选刷新四个操作按钮
struct ArchiveActionButtonsView: View {
    let onCreateFile: () -> Void
    let onCreateFolder: () -> Void
    let onToggleMultiSelect: () -> Void
    let onRefresh: () -> Void
    var isMultiSelecting: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onCreateFile) {
                Image(systemName: "doc.badge.plus")
            }
            .appGlassButtonStyle()
            .help("新建文件")

            Button(action: onCreateFolder) {
                Image(systemName: "folder.badge.plus")
            }
            .appGlassButtonStyle()
            .help("新建文件夹")

            Button(action: onToggleMultiSelect) {
                Image(systemName: isMultiSelecting ? "checkmark.circle.fill" : "checklist")
            }
            .appGlassButtonStyle(isMultiSelecting ? .prominent : .regular)
            .help(isMultiSelecting ? "完成多选" : "多选")

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .appGlassButtonStyle()
            .help("刷新")
        }
    }
}
