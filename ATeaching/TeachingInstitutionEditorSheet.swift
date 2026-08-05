import SwiftUI

// MARK: - 机构编辑弹窗 - v1 - 添加和修改机构基础设置

/// 机构管理中的添加/更改弹窗；负责校验名称、颜色、默认两小时价格和备注。
struct TeachingInstitutionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let institution: TeachingInstitutionRecord?
    let existingInstitutions: [TeachingInstitutionRecord]
    let onSave: (TeachingInstitutionRecord) -> Void

    @State private var name = ""
    @State private var color = Color.gray
    @State private var priceInput = ""
    @State private var note = ""
    @State private var iconName: String?
    @State private var statusMessage = ""

    @ViewBuilder
    var body: some View {
        #if os(macOS)
        editorContent
            .frame(minWidth: 420, minHeight: 300)
        #else
        editorContent
        #endif
    }

    private var editorContent: some View {
        NavigationStack {
            Form {
                Section("机构") {
                    TextField("名称", text: $name)
                    ColorPicker("颜色", selection: $color, supportsOpacity: false)
                    Picker("图标", selection: $iconName) {
                        Label("无图标", systemImage: "circle.slash").tag(String?.none)
                        ForEach(TeachingInstitutionVisualPlanner.iconNames, id: \.self) { name in
                            Label(name, systemImage: name).tag(Optional(name))
                        }
                    }
                    TextField("默认价格（2小时）", text: $priceInput)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                if !statusMessage.isEmpty {
                    TeachingStatusMessageSection(message: statusMessage)
                }
            }
            .navigationTitle(institution == nil ? "添加机构" : "更改机构")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                }
            }
            .task {
                loadDraft()
            }
        }
    }

    private func loadDraft() {
        guard let institution else {
            color = statisticsColor(fromHex: TeachingInstitutionVisualPlanner.suggestedColorHex(
                existing: existingInstitutions.map(\.effectiveColorHex)
            ))
            iconName = TeachingInstitutionVisualPlanner.iconNames.first { candidate in
                !existingInstitutions.contains(where: { $0.iconName == candidate })
            }
            return
        }
        name = institution.name
        color = statisticsColor(fromHex: institution.effectiveColorHex)
        if let price = institution.defaultPriceForTwoHours {
            priceInput = price.rounded() == price ? String(Int(price)) : String(price)
        }
        note = institution.note
        iconName = institution.iconName
    }

    private func save() {
        do {
            let trimmedName = TeachingLessonStatisticsStore.normalizedName(name)
            try TeachingLessonStatisticsStore.validateNewInstitutionName(
                trimmedName,
                excluding: institution?.id,
                in: existingInstitutions
            )
            let trimmedPrice = priceInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let price = trimmedPrice.isEmpty ? nil : Double(trimmedPrice)
            if !trimmedPrice.isEmpty && price == nil {
                statusMessage = "默认价格必须是数字。"
                return
            }
            onSave(
                TeachingInstitutionRecord(
                    id: institution?.id ?? UUID(),
                    name: trimmedName,
                    colorHex: statisticsHex(from: color),
                    defaultPriceForTwoHours: price,
                    note: note,
                    iconName: iconName
                )
            )
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
