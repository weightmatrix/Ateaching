import SwiftUI

struct TeachingPDFSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = TeachingPDFExportSettings()
    @State private var statusMessage = ""
    @State private var didLoad = false

    var body: some View {
        AppSettingsPage(
            title: "PDF设置",
            subtitle: "统一管理纸张、边距、分页方式和NodeMarkdown导出比例"
        ) {
            AppSettingsCard(title: "页面", systemImage: "doc.richtext") {
                Picker("PDF纸张", selection: $settings.paperPreset) {
                    Text("A4").tag(TeachingPDFExportSettings.PaperPreset.a4)
                    Text("Letter").tag(TeachingPDFExportSettings.PaperPreset.letter)
                    Text("自定义").tag(TeachingPDFExportSettings.PaperPreset.custom)
                }

                Picker("PDF方向", selection: $settings.orientation) {
                    Text("纵向").tag(TeachingPDFExportSettings.Orientation.portrait)
                    Text("横向").tag(TeachingPDFExportSettings.Orientation.landscape)
                }

                Picker("分页策略", selection: $settings.paginationStrategy) {
                    Text("分页").tag(TeachingPDFExportSettings.PaginationStrategy.paged)
                    Text("单长页").tag(TeachingPDFExportSettings.PaginationStrategy.singleLongPage)
                }

                if settings.paperPreset == .custom {
                    LabeledContent("宽") {
                        TextField("595", value: $settings.customWidth, format: .number.precision(.fractionLength(0...1)))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                    LabeledContent("高") {
                        TextField("842", value: $settings.customHeight, format: .number.precision(.fractionLength(0...1)))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                }

                LabeledContent("上边距") {
                    TextField("24", value: $settings.marginTop, format: .number.precision(.fractionLength(0...1)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
                LabeledContent("下边距") {
                    TextField("24", value: $settings.marginBottom, format: .number.precision(.fractionLength(0...1)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
                LabeledContent("左边距") {
                    TextField("24", value: $settings.marginLeft, format: .number.precision(.fractionLength(0...1)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
                LabeledContent("右边距") {
                    TextField("24", value: $settings.marginRight, format: .number.precision(.fractionLength(0...1)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }

                LabeledContent("NodeMarkdown缩放") {
                    Text("\(Int(settings.nodeMarkdownScalePercent))%")
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .trailing)
                }
                Slider(value: $settings.nodeMarkdownScalePercent, in: 10...100, step: 1)
            }
            AppSettingsStatusMessage(message: statusMessage)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") {
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
            guard !didLoad else { return }
            didLoad = true
            load()
        }
    }

    private func load() {
        do {
            let current = try TeachingStudentSettingsStore.loadStudentSystemSettings()
            let persisted = TeachingPDFSettingsStore.load()
            settings = current.pdfExportSettings == TeachingPDFExportSettings() ? persisted : current.pdfExportSettings
        } catch {
            statusMessage = "加载失败：\(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            var current = try TeachingStudentSettingsStore.loadStudentSystemSettings()
            current.pdfExportSettings = settings.normalized()
            try TeachingStudentSettingsStore.saveStudentSystemSettings(current)
            try TeachingPDFSettingsStore.save(current.pdfExportSettings)
            statusMessage = "已保存。"
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
        }
    }
}
