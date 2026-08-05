import SwiftUI

// MARK: - 模板入口组件 - v1 - 档案页顶部模板入口按钮
struct TemplateEntryNavigationButton: View {
    var body: some View {
        NavigationLink {
            TemplateManagementView()
        }
        label: {
            Image(systemName: "square.grid.2x2")
        }
        .appGlassButtonStyle(.prominent)
        .help("模板")
    }
}
