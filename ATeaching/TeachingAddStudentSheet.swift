import SwiftUI
import UniformTypeIdentifiers

// MARK: - 学生建档
struct TeachingAddStudentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingStudents: [TeachingStudentItem]
    let scheduleRoster: TeachingScheduleRoster?
    @State private var studentID = UUID()
    @State private var saving = false
    @State private var scheduleManager: UUID?
    @State private var scheduleTeacherPrice = ""
    @State private var scheduleChargePrice = ""
    @State private var scheduleGrade: Int?
    @State private var schedulePayment = "postpaid"
    let onConfirm: (TeachingStudentItem, TeachingStudentProfileSettings) -> Void

    @State private var name = ""
    @State private var iconName = TeachingStudentItem.supportedIcons.first ?? "person.fill"
    @State private var selectedColor: String?

    @State private var defaultSettings = TeachingStudentSystemSettings()
    @State private var draftSettings = TeachingStudentProfileSettings()
    @State private var selectionData = TeachingSelectionData.empty
    @State private var featureFlags = TeachingFeatureFlags()
    @State private var statusMessage = ""
    @State private var didLoadDefaults = false
    @State private var showSyncFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                studentInfoSection
                classInfoSection
                lessonPlansSection
                workbookSection
                syncFolderSection
                if let scheduleRoster {
                    Section("排课信息") {
                        Picker("学管", selection: $scheduleManager) {
                            Text("个人直收").tag(UUID?.none)
                            ForEach(scheduleRoster.managers) { manager in
                                Text(manager.name).tag(Optional(manager.id))
                            }
                        }
                        Picker("年级", selection: $scheduleGrade) {
                            Text("未指定").tag(Int?.none)
                            ForEach(1...12, id: \.self) { grade in
                                Text("\(grade) 年级").tag(Optional(grade))
                            }
                        }
                        TextField("教师价格（每小时）", text: $scheduleTeacherPrice)
                        TextField("收费价格（每小时）", text: $scheduleChargePrice)
                        Picker("付款方式", selection: $schedulePayment) {
                            Text("课后付").tag("postpaid")
                            Text("预付").tag("prepaid")
                        }
                    }
                }

                TeachingStatusMessageSection(message: statusMessage)
            }
            .navigationTitle("添加学生")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        Task { await createStudent() }
                    }
                    .disabled(!canCreateStudent || saving)
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

    private var basicInfoSection: some View {
        let activeColor = effectiveColor
        return Section("基础信息") {
            TextField("学生姓名", text: $name)
            Picker("图标", selection: $iconName) {
                ForEach(TeachingStudentItem.supportedIcons, id: \.self) { icon in
                    Label(icon, systemImage: icon).tag(icon)
                }
            }
            Button("自动选色") { selectedColor = nil }
                .accessibilityAddTraits(selectedColor == nil ? .isSelected : [])
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 34))], spacing: 10) {
                ForEach(TeachingScheduleStudentColors.presets, id: \.self) { hex in
                    Button {
                        selectedColor = hex
                    } label: {
                        ZStack {
                            Circle().fill(TeachingScheduleStudentColors.color(hex) ?? .clear)
                            if hex == activeColor {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hex)
                    .accessibilityAddTraits(hex == activeColor ? .isSelected : [])
                }
            }
        }
    }

    private var studentInfoSection: some View {
        Section("学生信息模板") {
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
        Section("上课信息模板") {
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
        Section("教案（可多选）") {
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
        Section("教辅（可选）") {
            Picker("教辅模板", selection: $draftSettings.workbookFileID) {
                Text("不选择").tag(Optional<String>.none)
                ForEach(selectionData.checklistTemplates) { template in
                    Text(template.title).tag(Optional(template.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var syncFolderSection: some View {
        Section("文件夹") {
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
            Text("创建时会在该目录下生成“5位序号-学生名”，并自动创建 1·教案 / 2·问题 / 3·试卷。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var effectiveColor: String {
        selectedColor ?? TeachingScheduleStudentColors.next(
            used: Set(existingStudents.compactMap(\.scheduleColorHex))
        )
    }

    private var canCreateStudent: Bool {
        let classInfoKeys = [
            draftSettings.classInfoNameKeyID,
            draftSettings.classInfoContentKeyID,
            draftSettings.classInfoTimeKeyID
        ].compactMap { $0 }
        return didLoadDefaults &&
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            draftSettings.studentInfoTemplateID != nil &&
            draftSettings.studentNameKeyID != nil &&
            draftSettings.classInfoTemplateID != nil &&
            Set(classInfoKeys).count == 3
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

    private func loadDefaults() {
        do {
            defaultSettings = try TeachingStudentSettingsStore.loadStudentSystemSettings()
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

    private func createStudent() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            statusMessage = "请输入学生姓名。"
            return
        }
        do {
            guard !existingStudents.contains(where: {
                $0.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) else {
                throw TeachingScheduleStudentSync.failure("已存在同名学生。")
            }
            if let scheduleRoster {
                guard let connection = TeachingScheduleConnection.load(),
                      try await connection.roster().teacherID == scheduleRoster.teacherID else {
                    throw TeachingScheduleStudentSync.failure("教师账号已变更，请重新打开建档页面。")
                }
                var fields = [
                    "name": trimmedName, "color": effectiveColor,
                    "payment_timing": schedulePayment
                ]
                if let scheduleManager { fields["academic_manager"] = scheduleManager.uuidString }
                if let scheduleGrade { fields["grade"] = String(scheduleGrade) }
                if !scheduleTeacherPrice.isEmpty { fields["default_price"] = scheduleTeacherPrice }
                if !scheduleChargePrice.isEmpty { fields["charge_price"] = scheduleChargePrice }
                try await connection.writeStudent(
                    id: studentID, method: "PUT", fields: fields,
                    profile: TeachingScheduleProfile(iconName: iconName, settings: draftSettings)
                )
            }
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
                id: studentID,
                name: trimmedName,
                iconName: iconName,
                scheduleColorHex: effectiveColor,
                scheduleStudentID: scheduleRoster == nil ? nil : studentID,
                scheduleTeacherID: scheduleRoster?.teacherID,
                scheduleProfile: scheduleRoster == nil ? nil : TeachingScheduleProfile(iconName: iconName, settings: draftSettings)
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
