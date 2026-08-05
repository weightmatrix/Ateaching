import SwiftUI

// MARK: - 教辅管理页 - v1 - 复用清单模板编辑器并统一 workbook 元类型
struct TeachingWorkbookManagementView: View {
    var showTopActionToolbar: Bool = true
    var externalToggleMultiSelectToken: Int = 0
    var externalCreateToken: Int = 0

    var body: some View {
        TemplateManagementView(
            initialCategory: .checklist,
            allowCategorySwitch: false,
            navigationTitle: "教辅",
            checklistMetaTypeOverride: "workbook",
            showTopActionToolbar: showTopActionToolbar,
            externalToggleMultiSelectToken: externalToggleMultiSelectToken,
            externalCreateToken: externalCreateToken
        )
    }
}
