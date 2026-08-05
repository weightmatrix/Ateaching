import SwiftUI

// MARK: - 状态提示区块 - v1 - 统一设置相关页面的状态信息显示样式
struct TeachingStatusMessageSection: View {
    let message: String

    var body: some View {
        if !message.isEmpty {
            Section {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
