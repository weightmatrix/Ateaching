import SwiftUI

// MARK: - 单列表格图片导出快照 - v1 - 使用统一背景板渲染图片

struct SingleListExportSnapshotView: View {
    let rows: [SingleListDocumentRow]
    let styleMap: [String: SingleListRowConfig]
    let title: String
    let titleStyle: SingleListTextStyle

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.24, green: 0.07, blue: 0.34),
                            Color.black
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color(red: 0.92, green: 0.72, blue: 0.28).opacity(0.9), lineWidth: 3)
                )

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title.isEmpty ? "单列表格" : title)
                        .font(.custom(titleStyle.fontName, size: titleStyle.fontSize))
                        .foregroundStyle(exportColor(titleStyle.colorHex))
                }
                .padding(.bottom, 6)

                ForEach(rows) { row in
                    let config = styleMap[row.id] ?? .default
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.keyName.isEmpty ? "未命名词条" : row.keyName)
                            .font(.custom(config.keyNameStyle.fontName, size: config.keyNameStyle.fontSize))
                            .foregroundStyle(exportColor(config.keyNameStyle.colorHex))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(row.content.isEmpty ? " " : row.content)
                            .font(.custom(config.contentStyle.fontName, size: config.contentStyle.fontSize))
                            .foregroundStyle(exportColor(config.contentStyle.colorHex))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 5)
                    )
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .padding(.bottom, 54)

            Text("李知本授课系统")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.76, blue: 0.16),
                            Color(red: 0.91, green: 0.16, blue: 0.45),
                            Color(red: 0.98, green: 0.40, blue: 0.10),
                            Color(red: 0.30, green: 0.08, blue: 0.42)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(.trailing, 22)
                .padding(.bottom, 18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private func exportColor(_ token: String) -> Color {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let darkDefaults: Set<String> = [
            SingleListRowConfig.adaptiveColorToken,
            "black",
            "#000",
            "000",
            "#000000",
            "000000",
            "#111111",
            "111111"
        ]
        if darkDefaults.contains(normalized) {
            return .white
        }
        return colorFromHex(token)
    }
}
