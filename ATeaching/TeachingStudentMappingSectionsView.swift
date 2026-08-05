import SwiftUI

// MARK: - 学生映射设置区块 - v1 - 复用模板/行/教案/教辅/同步目录交互区块
struct TeachingStudentMappingSectionTitles {
    let studentInfo: String
    let classInfo: String
    let lessonPlanAndSync: String
    let studentNameField: String
    let syncPathLineLimit: ClosedRange<Int>
}

struct TeachingStudentMappingSectionsView<T: TeachingStudentMappingSettings>: View {
    @Binding var settings: T
    let selectionData: TeachingSelectionData
    @Binding var showSyncFolderPicker: Bool
    let titles: TeachingStudentMappingSectionTitles

    var body: some View {
        Section(titles.studentInfo) {
            Picker("学生信息模板", selection: TeachingStudentSelectionBindings.optionalString(settings: $settings, keyPath: \.studentInfoTemplateID)) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(selectionData.singleListTemplates) { template in
                    Text(template.title).tag(Optional(template.id))
                }
            }
            .pickerStyle(.menu)

            Picker(titles.studentNameField, selection: TeachingStudentSelectionBindings.optionalString(settings: $settings, keyPath: \.studentNameKeyID)) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(studentNameKeyOptions) { option in
                    Text(option.title).tag(Optional(option.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(settings.studentInfoTemplateID == nil || studentNameKeyOptions.isEmpty)
        }

        Section(titles.classInfo) {
            Picker("上课信息模板", selection: TeachingStudentSelectionBindings.optionalString(settings: $settings, keyPath: \.classInfoTemplateID)) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(selectionData.singleListTemplates) { template in
                    Text(template.title).tag(Optional(template.id))
                }
            }
            .pickerStyle(.menu)

            Picker("姓名", selection: TeachingStudentSelectionBindings.optionalString(settings: $settings, keyPath: \.classInfoNameKeyID)) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(classInfoNameKeyOptions) { option in
                    Text(option.title).tag(Optional(option.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(settings.classInfoTemplateID == nil || classInfoNameKeyOptions.isEmpty)

            Picker("内容", selection: TeachingStudentSelectionBindings.optionalString(settings: $settings, keyPath: \.classInfoContentKeyID)) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(classInfoContentKeyOptions) { option in
                    Text(option.title).tag(Optional(option.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(settings.classInfoTemplateID == nil || classInfoContentKeyOptions.isEmpty)

            Picker("时间", selection: TeachingStudentSelectionBindings.optionalString(settings: $settings, keyPath: \.classInfoTimeKeyID)) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(classInfoTimeKeyOptions) { option in
                    Text(option.title).tag(Optional(option.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(settings.classInfoTemplateID == nil || classInfoTimeKeyOptions.isEmpty)
        }

        Section(titles.lessonPlanAndSync) {
            if selectionData.lessonPlanFolders.isEmpty {
                Text("教案文件夹：未发现可选项")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("教案文件夹（可多选）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(selectionData.lessonPlanFolders, id: \.self) { folder in
                        Toggle(
                            folder,
                            isOn: TeachingStudentSelectionBindings.containsLessonPlanFolder(
                                settings: $settings,
                                folder: folder
                            )
                        )
                    }
                }
                Text(selectedLessonPlanSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Picker("教辅模板（可选）", selection: TeachingStudentSelectionBindings.optionalString(settings: $settings, keyPath: \.workbookFileID)) {
                Text("不选择").tag(Optional<String>.none)
                ForEach(selectionData.checklistTemplates) { template in
                    Text(template.title).tag(Optional(template.id))
                }
            }
            .pickerStyle(.menu)

            Text(settings.syncBaseFolderPath ?? "未选择")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(titles.syncPathLineLimit)
            HStack {
                Button("选择文件夹") {
                    showSyncFolderPicker = true
                }
                if settings.syncBaseFolderPath != nil {
                    Button("清除") {
                        settings.syncBaseFolderPath = nil
                    }
                }
            }
        }
    }

    private var studentNameKeyOptions: [TeachingTemplateRowOption] {
        TeachingStudentSelectionSupport.rowOptions(for: settings.studentInfoTemplateID, in: selectionData)
    }

    private var classInfoKeyOptions: [TeachingTemplateRowOption] {
        TeachingStudentSelectionSupport.classInfoRowOptions(for: settings.classInfoTemplateID, in: selectionData)
    }

    private var classInfoNameKeyOptions: [TeachingTemplateRowOption] {
        classInfoKeyOptions
    }

    private var classInfoContentKeyOptions: [TeachingTemplateRowOption] {
        classInfoKeyOptions.filter { $0.id != settings.classInfoNameKeyID }
    }

    private var classInfoTimeKeyOptions: [TeachingTemplateRowOption] {
        classInfoKeyOptions.filter {
            $0.id != settings.classInfoNameKeyID &&
            $0.id != settings.classInfoContentKeyID
        }
    }

    private var selectedLessonPlanSummary: String {
        if settings.lessonPlanFolderIDs.isEmpty {
            return "已选教案：未选择"
        }
        return "已选教案：\(settings.lessonPlanFolderIDs.joined(separator: "、"))"
    }
}
