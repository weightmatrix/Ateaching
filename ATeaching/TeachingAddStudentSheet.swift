import SwiftUI
import UniformTypeIdentifiers

// MARK: - 学生新增向导 - v3 - 六步建档并支持默认继承与逐项覆盖
struct TeachingAddStudentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onConfirm: (TeachingStudentItem, TeachingStudentProfileSettings) -> Void

    @State private var step: Step = .basicInfo
    @State private var name = ""
    @State private var iconName = TeachingStudentItem.supportedIcons.first ?? "person.fill"
    @State private var color = TeachingStudentColor.blue

    @State private var defaultSettings = TeachingStudentSystemSettings()
    @State private var draftSettings = TeachingStudentProfileSettings()
    @State private var selectionData = TeachingSelectionData.empty
    @State private var institutions: [TeachingInstitutionRecord] = []
    @State private var featureFlags = TeachingFeatureFlags()
    @State private var statusMessage = ""
    @State private var didLoadDefaults = false
    @State private var showSyncFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("进度") {
                    Text(stepIndicatorText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                stepContent

                TeachingStatusMessageSection(message: statusMessage)
            }
            .navigationTitle("添加学生")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if step == .syncFolder {
                        Button("创建") {
                            createStudent()
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button("下一步") {
                            moveToNextStep()
                        }
                        .disabled(!canMoveToNextStep)
                    }
                }
                ToolbarItem(placement: .automatic) {
                    if step != .basicInfo {
                        Button("上一步") {
                            moveToPreviousStep()
                        }
                    }
                }
            }
            .task {
                guard !didLoadDefaults else { return }
                didLoadDefaults = true
                loadDefaults()
            }
            .fileImporter(
                isPresented: $showSyncFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let folderURL = urls.first {
                        let canonicalURL = TeachingSecurityScopedAccess.canonicalFolderURL(folderURL)
                        draftSettings.syncBaseFolderPath = canonicalURL.path
                        do {
                            try TeachingSecurityScopedAccess.storeBookmark(for: folderURL)
                        } catch {
                            statusMessage = "目录授权保存失败：\(error.localizedDescription)"
                        }
                    }
                case .failure(let error):
                    statusMessage = "目录选择失败：\(error.localizedDescription)"
                }
            }
            .onChange(of: draftSettings.studentInfoTemplateID) { _, _ in
                TeachingStudentSelectionSupport.sanitizeSelections(&draftSettings, using: selectionData)
            }
            .onChange(of: draftSettings.classInfoTemplateID) { _, _ in
                TeachingStudentSelectionSupport.sanitizeSelections(&draftSettings, using: selectionData)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .basicInfo:
            basicInfoSection
        case .studentInfo:
            studentInfoSection
        case .classInfo:
            classInfoSection
        case .lessonPlans:
            lessonPlansSection
        case .workbook:
            workbookSection
        case .statistics:
            lessonStatisticsSection
        case .syncFolder:
            syncFolderSection
        }
    }

    private var basicInfoSection: some View {
        Section("第一页：基础信息") {
            TextField("学生姓名", text: $name)
            Picker("图标", selection: $iconName) {
                ForEach(TeachingStudentItem.supportedIcons, id: \.self) { icon in
                    Label(icon, systemImage: icon).tag(icon)
                }
            }
            Picker("颜色", selection: $color) {
                ForEach(TeachingStudentColor.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
        }
    }

    private var studentInfoSection: some View {
        Section("第二页：学生信息模板") {
            Picker("学生信息模板", selection: $draftSettings.studentInfoTemplateID) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(selectionData.singleListTemplates) { template in
                    Text(template.title).tag(Optional(template.id))
                }
            }
            .pickerStyle(.menu)

            Picker("姓名栏", selection: $draftSettings.studentNameKeyID) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(studentNameRowOptions) { option in
                    Text(option.title).tag(Optional(option.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(draftSettings.studentInfoTemplateID == nil || studentNameRowOptions.isEmpty)
        }
    }

    private var classInfoSection: some View {
        Section("第三页：上课信息模板") {
            Picker("上课信息模板", selection: $draftSettings.classInfoTemplateID) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(selectionData.singleListTemplates) { template in
                    Text(template.title).tag(Optional(template.id))
                }
            }
            .pickerStyle(.menu)

            Picker("姓名", selection: $draftSettings.classInfoNameKeyID) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(classInfoNameRowOptions) { option in
                    Text(option.title).tag(Optional(option.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(draftSettings.classInfoTemplateID == nil || classInfoNameRowOptions.isEmpty)

            Picker("内容", selection: $draftSettings.classInfoContentKeyID) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(classInfoContentRowOptions) { option in
                    Text(option.title).tag(Optional(option.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(draftSettings.classInfoTemplateID == nil || classInfoContentRowOptions.isEmpty)

            Picker("时间", selection: $draftSettings.classInfoTimeKeyID) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(classInfoTimeRowOptions) { option in
                    Text(option.title).tag(Optional(option.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(draftSettings.classInfoTemplateID == nil || classInfoTimeRowOptions.isEmpty)
        }
    }

    private var lessonPlansSection: some View {
        Section("第四页：教案（可多选）") {
            if selectionData.lessonPlanFolders.isEmpty {
                Text("未发现可选教案文件夹")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(selectionData.lessonPlanFolders, id: \.self) { folder in
                    Toggle(
                        folder,
                        isOn: TeachingStudentSelectionBindings.containsLessonPlanFolder(
                            settings: Binding(
                                get: { draftSettings },
                                set: { draftSettings = $0 }
                            ),
                            folder: folder
                        )
                    )
                }
            }
            Text("当前选择：\(draftSettings.lessonPlanFolderIDs.isEmpty ? "未选择" : draftSettings.lessonPlanFolderIDs.joined(separator: "、"))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var workbookSection: some View {
        Section("第五页：教辅（可选）") {
            Picker("教辅模板", selection: $draftSettings.workbookFileID) {
                Text("不选择").tag(Optional<String>.none)
                ForEach(selectionData.checklistTemplates) { template in
                    Text(template.title).tag(Optional(template.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var lessonStatisticsSection: some View {
        Section("第六页：统计") {
            Picker("机构名称", selection: lessonStatisticsInstitutionBinding) {
                Text("不选择").tag(Optional<UUID>.none)
                ForEach(institutions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { institution in
                    Text(institution.name).tag(Optional(institution.id))
                }
            }
            .pickerStyle(.menu)

            TextField("课时价格（2小时）", value: lessonStatisticsPriceBinding, format: .number)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .disabled(draftSettings.lessonStatistics.institutionID == nil)

            Text("课时价格按 2 小时价格保存；未选择机构时不会自动记录课。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var lessonStatisticsInstitutionBinding: Binding<UUID?> {
        Binding(
            get: { draftSettings.lessonStatistics.institutionID },
            set: { newID in
                if let newID,
                   let institution = institutions.first(where: { $0.id == newID }) {
                    draftSettings.lessonStatistics.institutionID = institution.id
                    draftSettings.lessonStatistics.institutionName = institution.name
                    draftSettings.lessonStatistics.priceForTwoHours = draftSettings.lessonStatistics.priceForTwoHours ?? institution.defaultPriceForTwoHours
                } else {
                    draftSettings.lessonStatistics = TeachingStudentLessonStatisticsSettings()
                }
            }
        )
    }

    private var lessonStatisticsPriceBinding: Binding<Double?> {
        Binding(
            get: { draftSettings.lessonStatistics.priceForTwoHours },
            set: { draftSettings.lessonStatistics.priceForTwoHours = $0 }
        )
    }

    private var syncFolderSection: some View {
        Section("第七页：文件夹") {
            Text(draftSettings.syncBaseFolderPath ?? "未选择")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2...4)
            HStack {
                Button("选择文件夹") {
                    showSyncFolderPicker = true
                }
                if draftSettings.syncBaseFolderPath != nil {
                    Button("清除") {
                        draftSettings.syncBaseFolderPath = nil
                    }
                }
            }
            Text("创建时会在该目录下生成“5位序号-学生名”，并自动创建 1-教案PDF / 2-问题PDF / 3-卷子PDF。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var stepIndicatorText: String {
        "\(step.rawValue + 1)/\(Step.allCases.count) · \(step.displayName)"
    }

    private var canMoveToNextStep: Bool {
        switch step {
        case .basicInfo:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .studentInfo:
            return draftSettings.studentInfoTemplateID != nil && draftSettings.studentNameKeyID != nil
        case .classInfo:
            let selected = [
                draftSettings.classInfoNameKeyID,
                draftSettings.classInfoContentKeyID,
                draftSettings.classInfoTimeKeyID
            ].compactMap { $0 }
            return draftSettings.classInfoTemplateID != nil && selected.count == 3 && Set(selected).count == 3
        case .lessonPlans, .workbook:
            return true
        case .statistics:
            let stats = draftSettings.lessonStatistics.normalized()
            if stats.institutionID == nil && stats.institutionName == nil {
                return true
            }
            return stats.priceForTwoHours != nil
        case .syncFolder:
            return true
        }
    }

    private var studentNameRowOptions: [TeachingTemplateRowOption] {
        TeachingStudentSelectionSupport.rowOptions(for: draftSettings.studentInfoTemplateID, in: selectionData)
    }

    private var classInfoAllRowOptions: [TeachingTemplateRowOption] {
        TeachingStudentSelectionSupport.classInfoRowOptions(for: draftSettings.classInfoTemplateID, in: selectionData)
    }

    private var classInfoNameRowOptions: [TeachingTemplateRowOption] {
        classInfoAllRowOptions
    }

    private var classInfoContentRowOptions: [TeachingTemplateRowOption] {
        classInfoAllRowOptions.filter { $0.id != draftSettings.classInfoNameKeyID }
    }

    private var classInfoTimeRowOptions: [TeachingTemplateRowOption] {
        classInfoAllRowOptions.filter {
            $0.id != draftSettings.classInfoNameKeyID &&
            $0.id != draftSettings.classInfoContentKeyID
        }
    }

    private func moveToNextStep() {
        guard canMoveToNextStep else {
            statusMessage = "请先完成本页必填项。"
            return
        }
        statusMessage = ""
        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    private func moveToPreviousStep() {
        statusMessage = ""
        if let previous = Step(rawValue: step.rawValue - 1) {
            step = previous
        }
    }

    private func loadDefaults() {
        do {
            defaultSettings = try TeachingStudentSettingsStore.loadStudentSystemSettings()
            institutions = (try? TeachingLessonStatisticsStore.loadInstitutions()) ?? []
            featureFlags = try TeachingStudentSettingsStore.loadFeatureFlags()
            selectionData = (try? TeachingStudentSelectionSupport.loadSelectionData()) ?? .empty
            draftSettings = TeachingStudentProfileSettings(
                studentInfoTemplateID: defaultSettings.studentInfoTemplateID,
                studentNameKeyID: defaultSettings.studentNameKeyID,
                classInfoTemplateID: defaultSettings.classInfoTemplateID,
                classInfoNameKeyID: defaultSettings.classInfoNameKeyID,
                classInfoContentKeyID: defaultSettings.classInfoContentKeyID,
                classInfoTimeKeyID: defaultSettings.classInfoTimeKeyID,
                lessonPlanFolderIDs: defaultSettings.lessonPlanFolderIDs,
                workbookFileID: defaultSettings.workbookFileID,
                syncBaseFolderPath: defaultSettings.syncBaseFolderPath
            )
            TeachingStudentSelectionSupport.sanitizeSelections(&draftSettings, using: selectionData)
        } catch {
            statusMessage = "默认设置加载失败：\(error.localizedDescription)"
        }
    }

    private func createStudent() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            statusMessage = "请输入学生姓名。"
            return
        }
        do {
            var profile = draftSettings
            if let baseFolderPath = profile.syncBaseFolderPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !baseFolderPath.isEmpty {
                let studentSyncFolder = try TeachingStudentSyncFolderFactory.createStudentSyncFolder(
                    baseFolderPath: baseFolderPath,
                    studentName: trimmedName
                )
                profile.syncBaseFolderPath = studentSyncFolder.path
            }

            let student = TeachingStudentItem(
                name: trimmedName,
                iconName: iconName,
                color: color,
                isSelected: true
            )
            if featureFlags.enableStudentProvisioning {
                try TeachingStudentProvisioningService.provisionArchiveSkeleton(
                    for: student,
                    defaultSettings: defaultSettings,
                    profileOverride: profile
                )
            }
            onConfirm(student, profile)
            dismiss()
        } catch {
            statusMessage = "建档失败：\(error.localizedDescription)"
        }
    }
}

private extension TeachingAddStudentSheet {
    enum Step: Int, CaseIterable {
        case basicInfo
        case studentInfo
        case classInfo
        case lessonPlans
        case workbook
        case statistics
        case syncFolder

        var displayName: String {
            switch self {
            case .basicInfo:
                return "基础信息"
            case .studentInfo:
                return "学生信息"
            case .classInfo:
                return "上课信息"
            case .lessonPlans:
                return "教案"
            case .workbook:
                return "教辅"
            case .statistics:
                return "统计"
            case .syncFolder:
                return "文件夹"
            }
        }
    }
}

private enum TeachingStudentSyncFolderFactory {
    static func createStudentSyncFolder(baseFolderPath: String, studentName: String) throws -> URL {
        try TeachingSecurityScopedAccess.withWritableAccess(toPath: baseFolderPath) { writableBaseURL in
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: writableBaseURL, withIntermediateDirectories: true)

            let children = try fileManager.contentsOfDirectory(
                at: writableBaseURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            let maxPrefix = children.compactMap { url -> Int? in
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
                let name = url.lastPathComponent
                guard name.count >= 5 else { return nil }
                let prefix = String(name.prefix(5))
                return Int(prefix)
            }.max() ?? 0

            var next = maxPrefix + 1
            var studentFolderURL: URL
            while true {
                let folderName = String(format: "%05d-%@", next, studentName)
                let candidate = writableBaseURL.appendingPathComponent(folderName, isDirectory: true)
                if !fileManager.fileExists(atPath: candidate.path) {
                    studentFolderURL = candidate
                    break
                }
                next += 1
            }

            try fileManager.createDirectory(at: studentFolderURL, withIntermediateDirectories: true)
            try TeachingStudentSyncFolderService.ensureStructure(
                syncRootPath: studentFolderURL.path,
                studentName: studentName,
                fileManager: fileManager
            )
            return studentFolderURL
        }
    }
}
