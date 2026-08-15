import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - 授课主页 - v6 - 重构为五页面顶栏并统一选中高亮与下方面板切换
struct TeachingHomeView: View {
    private enum TeachingPage {
        case teaching
        case lessonPlan
        case workbook
        case students
        case statistics
        case sync
    }

    @State private var statusMessage = ""
    @State private var students: [TeachingStudentItem] = []
    @State private var draggingStudentID: UUID?
    @State private var selectedPage: TeachingPage = .teaching
    @State private var didLoadStudents = false
    @State private var featureFlags = TeachingFeatureFlags()
    @State private var lessonStatisticsEnabled = false
    @State private var showStudentSystemSettings = false
    @State private var showAddStudentSheet = false
    @State private var editingProfileStudent: TeachingStudentItem?
    @State private var showDiagnosticsSheet = false
    @State private var selectedCourseStudent: TeachingStudentItem?
    @State private var selectedCourseInitialMode: TeachingCoursePageView.CourseMode = .teaching
    @State private var presentedHomeStudentDocument: TeachingHomeStudentDocument?
    @State private var showStudentBackupSheet = false
    @State private var isRunningStudentBackup = false
    @State private var pendingInitializationStudentIDs: Set<UUID> = []
    @State private var lessonPlanCreateToken = 0
    @State private var lessonPlanSettingsToken = 0
    @State private var workbookToggleMultiSelectToken = 0
    @State private var workbookCreateToken = 0
    @State private var syncPrepareToken = 0
    @State private var syncExportToken = 0
    @State private var syncCheckToken = 0
    @State private var syncReadinessToken = 0
    @State private var syncAuditToken = 0
    @State private var syncStressToken = 0
    @State private var syncCancelToken = 0
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        VStack(spacing: 12) {
            topButtons
            panelContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(usesCompactIconOnlyButtons ? 10 : 16)
        .task {
            guard !didLoadStudents else { return }
            didLoadStudents = true
            loadStudentsFromSettings()
        }
        .onChange(of: students) { _, _ in
            saveStudentsToSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .teachingStudentsDidChange)) { _ in
            loadStudentsFromSettings()
        }
        .sheet(isPresented: $showStudentSystemSettings) {
            TeachingStudentSystemSettingsView()
        }
        .sheet(isPresented: $showAddStudentSheet) {
            TeachingAddStudentSheet { student, profile in
                students.append(student)
                saveStudentsToSettings()
                saveProfileOverrideIfNeeded(profile, for: student)
            }
        }
        .sheet(item: $editingProfileStudent) { student in
            TeachingStudentProfileSettingsView(student: student)
        }
        .sheet(isPresented: $showDiagnosticsSheet) {
            TeachingSystemDiagnosticsView()
        }
        .coursePagePresentation(student: $selectedCourseStudent) { student in
            coursePage(for: student)
        }
        .sheet(isPresented: $showStudentBackupSheet) {
            TeachingStudentBackupSheet(students: students) { selectedIDs in
                runStudentBackup(selectedIDs: selectedIDs)
            }
        }
        .sheet(item: $presentedHomeStudentDocument) { document in
            NavigationStack {
                SingleListDocumentEditorView(
                    fileURL: document.fileURL,
                    onClose: { presentedHomeStudentDocument = nil }
                )
            }
            .singleListAdaptivePresentation()
        }
    }

    @ViewBuilder
    private var topButtons: some View {
        if usesCompactIconOnlyButtons {
            ScrollView(.horizontal, showsIndicators: false) {
                topButtonsRow
                    .padding(.vertical, 2)
            }
        } else {
            topButtonsRow
        }
    }

    private var topButtonsRow: some View {
        HStack(spacing: 10) {
            pageButton(title: "授课", systemImage: "play.rectangle", page: .teaching)
            pageButton(title: "教案", systemImage: "book.closed", page: .lessonPlan)
            pageButton(title: "教辅", systemImage: "books.vertical", page: .workbook)
            pageButton(title: "学生", systemImage: "person.2", page: .students)
            if lessonStatisticsEnabled {
                pageButton(title: "统计", systemImage: "chart.bar.doc.horizontal", page: .statistics)
            }
            pageButton(title: "同步", systemImage: "arrow.triangle.2.circlepath", page: .sync)
            Spacer()
            topActionButtons
        }
    }

    @ViewBuilder
    private var topActionButtons: some View {
        if selectedPage == .lessonPlan {
            Button {
                lessonPlanSettingsToken += 1
            } label: {
                actionLabel("设置", systemImage: "slider.horizontal.3")
            }
            .appGlassButtonStyle()

            Button {
                lessonPlanCreateToken += 1
            } label: {
                actionLabel("新建", systemImage: "plus")
            }
            .appGlassButtonStyle(.prominent)
        } else if selectedPage == .workbook {
            Button {
                workbookToggleMultiSelectToken += 1
            } label: {
                actionLabel("多选", systemImage: "checklist")
            }
            .appGlassButtonStyle()

            Button {
                workbookCreateToken += 1
            } label: {
                actionLabel("新建", systemImage: "plus")
            }
            .appGlassButtonStyle(.prominent)
        } else if selectedPage == .sync {
            Button {
                syncExportToken += 1
            } label: {
                actionLabel("PDF", systemImage: "doc.richtext")
            }
            .appGlassButtonStyle(.prominent)

            Button {
                syncPrepareToken += 1
            } label: {
                actionLabel("整理", systemImage: "sparkles")
            }
            .appGlassButtonStyle()

            Button {
                syncReadinessToken += 1
            } label: {
                actionLabel("验收", systemImage: "checkmark.shield")
            }
            .appGlassButtonStyle()

            Button(role: .destructive) {
                syncCancelToken += 1
            } label: {
                actionLabel("取消", systemImage: "xmark.circle")
            }
            .appGlassButtonStyle(.danger)
        }
    }

    private func pageButton(title: String, systemImage: String, page: TeachingPage) -> some View {
        Button {
            selectedPage = page
            if page != .workbook && page != .sync {
                statusMessage = ""
            }
        } label: {
            actionLabel(title, systemImage: systemImage)
        }
        .appGlassButtonStyle(selectedPage == page ? .prominent : .regular)
        .help(title)
    }

    private var usesCompactIconOnlyButtons: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String) -> some View {
        if usesCompactIconOnlyButtons {
            Image(systemName: systemImage)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        switch selectedPage {
        case .teaching:
            teachingMainPanel
        case .lessonPlan:
            LessonPlanManagementView(
                showRootBackButton: false,
                showTopActionButtons: false,
                externalCreateToken: lessonPlanCreateToken,
                externalSettingsToken: lessonPlanSettingsToken
            )
        case .students:
            studentsPanel
        case .workbook:
            TeachingWorkbookManagementView(
                showTopActionToolbar: false,
                externalToggleMultiSelectToken: workbookToggleMultiSelectToken,
                externalCreateToken: workbookCreateToken
            )
        case .statistics:
            TeachingLessonStatisticsSubpageView()
        case .sync:
            TeachingSyncPanelView(
                students: students,
                showTopActionButtons: false,
                externalPrepareToken: syncPrepareToken,
                externalExportToken: syncExportToken,
                externalCheckToken: syncCheckToken,
                externalReadinessToken: syncReadinessToken,
                externalAuditToken: syncAuditToken,
                externalStressToken: syncStressToken,
                externalCancelToken: syncCancelToken
            )
        }
    }

    private func panelPlaceholder(message: String) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.secondary.opacity(0.08))
            .frame(maxWidth: .infinity, minHeight: 180)
            .overlay {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
    }

    private var teachingMainPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("授课")
                .font(.headline)

            if students.isEmpty {
                Text("暂无学生")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                let columns = [
                    GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 10, alignment: .top)
                ]
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(students) { student in
                            Button {
                                let needsInitialize = pendingInitializationStudentIDs.contains(student.id) || !isStudentInitialized(student)
                                #if os(macOS)
                                let modeRaw = needsInitialize ? TeachingCoursePageView.CourseMode.initialize.rawValue : TeachingCoursePageView.CourseMode.teaching.rawValue
                                openWindow(id: "teaching-course-page", value: "\(student.id.uuidString)|\(modeRaw)")
                                #else
                                selectedCourseInitialMode = needsInitialize ? .initialize : .teaching
                                selectedCourseStudent = student
                                #endif
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: student.iconName)
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(student.color.value)
                                    Text(student.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, minHeight: 88)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.primary.opacity(0.03))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                                        )
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("学生信息") {
                                    openStudentInformation(student)
                                }

                                Button("上课记录") {
                                    openLatestClassInformation(student)
                                }

                                Menu("更改图标") {
                                    ForEach(TeachingStudentItem.supportedIcons, id: \.self) { iconName in
                                        Button {
                                            updateStudent(student.id) { item in
                                                item.iconName = iconName
                                            }
                                        } label: {
                                            Label(TeachingStudentItem.displayName(forIcon: iconName), systemImage: iconName)
                                        }
                                    }
                                }

                                Menu("更改颜色") {
                                    ForEach(TeachingStudentColor.allCases) { color in
                                        Button {
                                            updateStudent(student.id) { item in
                                                item.color = color
                                            }
                                        } label: {
                                            HStack {
                                                Circle()
                                                    .fill(color.value)
                                                    .frame(width: 10, height: 10)
                                                Text(color.displayName)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func coursePage(for student: TeachingStudentItem) -> some View {
        TeachingCoursePageView(student: student, initialMode: selectedCourseInitialMode) { studentID, newName in
            guard let index = students.firstIndex(where: { $0.id == studentID }) else { return }
            var updated = students[index]
            updated.name = newName
            students[index] = updated
            if selectedCourseStudent?.id == studentID {
                selectedCourseStudent = updated
            }
        }
    }

    private var studentsPanel: some View {
        TeachingStudentsSubpageView(
            students: $students,
            draggingStudentID: $draggingStudentID,
            isRunningStudentBackup: isRunningStudentBackup,
            showProfileOverrideAction: featureFlags.enableStudentProfileOverride,
            onAdd: {
                showAddStudentSheet = true
            },
            onBackup: {
                showStudentBackupSheet = true
            },
            onSettings: {
                showStudentSystemSettings = true
            },
            onRefresh: {
                refreshStudentsFromArchive()
            },
            onUpdateIcon: { studentID, iconName in
                updateStudent(studentID) { item in
                    item.iconName = iconName
                }
            },
            onUpdateColor: { studentID, color in
                updateStudent(studentID) { item in
                    item.color = color
                }
            },
            onConfigureProfile: { student in
                editingProfileStudent = student
            }
        )
    }

    private func updateStudent(_ id: UUID, updater: (inout TeachingStudentItem) -> Void) {
        guard let index = students.firstIndex(where: { $0.id == id }) else { return }
        var next = students[index]
        updater(&next)
        students[index] = next
    }

    private func openStudentInformation(_ student: TeachingStudentItem) {
        do {
            let defaults = try TeachingStudentSettingsStore.loadStudentSystemSettings()
            let profile = try TeachingStudentSettingsStore.loadStudentProfile(studentID: student.id)
            try TeachingStudentProvisioningService.provisionArchiveSkeleton(
                for: student,
                defaultSettings: defaults,
                profileOverride: profile
            )
            let url = try TeachingCourseWorkflowService.studentInfoFileURL(student: student)
            presentedHomeStudentDocument = TeachingHomeStudentDocument(
                title: "学生信息·\(student.name)",
                fileURL: url
            )
        } catch {
            statusMessage = "打开学生信息失败：\(error.localizedDescription)"
        }
    }

    private func openLatestClassInformation(_ student: TeachingStudentItem) {
        do {
            guard let url = try TeachingCourseWorkflowService
                .latestClassInfoFileURLPreparingScheduledToday(student: student) else {
                statusMessage = "\(student.name)还没有上课记录。"
                return
            }
            presentedHomeStudentDocument = TeachingHomeStudentDocument(
                title: "上课记录·\(student.name)",
                fileURL: url
            )
        } catch {
            statusMessage = "打开上课记录失败：\(error.localizedDescription)"
        }
    }

    private func loadStudentsFromSettings() {
        do {
            let snapshot = try TeachingStudentSettingsStore.loadSnapshot()
            students = snapshot.students
            featureFlags = snapshot.featureFlags
            lessonStatisticsEnabled = TeachingDebugLogStore.isLessonStatisticsEnabled()
            if selectedPage == .statistics && !lessonStatisticsEnabled {
                selectedPage = .teaching
            }
            if students.isEmpty {
                refreshStudentsFromArchive()
            }
        } catch {
            refreshStudentsFromArchive()
            if students.isEmpty {
                statusMessage = "学生设置加载失败：\(error.localizedDescription)"
            } else {
                statusMessage = "学生设置异常，已按档案目录自动重建。"
            }
        }
    }

    private func saveStudentsToSettings() {
        do {
            try TeachingStudentSettingsStore.saveStudents(students)
        } catch {
            statusMessage = "学生设置保存失败：\(error.localizedDescription)"
        }
    }

    private func saveProfileOverrideIfNeeded(_ profile: TeachingStudentProfileSettings, for student: TeachingStudentItem) {
        let normalized = profile.normalized()
        let hasOverride =
            normalized.studentInfoTemplateID != nil ||
            normalized.studentNameKeyID != nil ||
            normalized.classInfoTemplateID != nil ||
            normalized.classInfoNameKeyID != nil ||
            normalized.classInfoContentKeyID != nil ||
            normalized.classInfoTimeKeyID != nil ||
            !normalized.lessonPlanFolderIDs.isEmpty ||
            normalized.workbookFileID != nil ||
            normalized.syncBaseFolderPath != nil ||
            normalized.lessonStatistics != TeachingStudentLessonStatisticsSettings()
        guard hasOverride else { return }
        do {
            try TeachingStudentSettingsStore.saveStudentProfile(normalized, studentID: student.id)
        } catch {
            statusMessage = "学生覆盖配置保存失败：\(error.localizedDescription)"
        }
    }

    private func runStudentBackup(selectedIDs: [UUID]) {
        guard !isRunningStudentBackup else { return }
        let selectedSet = Set(selectedIDs)
        let selectedStudents = students.filter { selectedSet.contains($0.id) }
        guard !selectedStudents.isEmpty else {
            statusMessage = "未选择需要备份的学生。"
            return
        }

        isRunningStudentBackup = true
        statusMessage = "正在迁移学生到系统备份..."
        Task(priority: .userInitiated) {
            do {
                let result = try TeachingStudentBackupService.backupStudents(selectedStudents)
                await MainActor.run {
                    if !result.movedStudentIDs.isEmpty {
                        students.removeAll { result.movedStudentIDs.contains($0.id) }
                        saveStudentsToSettings()
                    }
                    isRunningStudentBackup = false
                    if result.skippedNames.isEmpty {
                        statusMessage = "备份完成：\(result.movedCount) 人，路径：\(result.backupRootPath)"
                    } else {
                        statusMessage = "备份完成：\(result.movedCount) 人；跳过：\(result.skippedNames.joined(separator: "、"))"
                    }
                }
            } catch {
                await MainActor.run {
                    isRunningStudentBackup = false
                    statusMessage = "备份失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func refreshStudentsFromArchive() {
        do {
            let studentsRoot = try ArchiveStorage.ensureArchiveRoot()
                .appendingPathComponent("学生", isDirectory: true)
            let existingStudents = (try? TeachingStudentSettingsStore.loadStudents()) ?? students
            let existingByName = Dictionary(
                existingStudents.map { ($0.name.trimmingCharacters(in: .whitespacesAndNewlines), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let folderURLs = try FileManager.default.contentsOfDirectory(
                at: studentsRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            let rebuilt = folderURLs.compactMap { url -> TeachingStudentItem? in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                guard values?.isDirectory == true else { return nil }
                let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                if var existing = existingByName[name] {
                    existing.name = name
                    return existing
                }
                return TeachingStudentItem(name: name)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            students = rebuilt
            saveStudentsToSettings()
            let failedInjection = batchInjectStudentInitialization(for: rebuilt)
            pendingInitializationStudentIDs = Set(failedInjection.map(\.id))
            saveStudentsToSettings()
            if failedInjection.isEmpty {
                statusMessage = "已按档案目录刷新并完成灌注。"
            } else {
                statusMessage = "已刷新；需初始化：\(failedInjection.map(\.name).joined(separator: "、"))"
            }
        } catch {
            statusMessage = "刷新失败：\(error.localizedDescription)"
        }
    }

    private func batchInjectStudentInitialization(for items: [TeachingStudentItem]) -> [TeachingStudentItem] {
        do {
            let defaults = try TeachingStudentSettingsStore.loadStudentSystemSettings()
            var failed: [TeachingStudentItem] = []
            for student in items {
                do {
                    let profile = try TeachingStudentSettingsStore.loadStudentProfile(studentID: student.id) ?? TeachingStudentProfileSettings()
                    let effectiveProfile = try bindSyncFolderIfNeeded(for: student, defaults: defaults, profile: profile)
                    try TeachingStudentProvisioningService.provisionArchiveSkeleton(
                        for: student,
                        defaultSettings: defaults,
                        profileOverride: effectiveProfile
                    )
                    if !isStudentInitialized(student) {
                        failed.append(student)
                    }
                } catch {
                    failed.append(student)
                }
            }
            return failed
        } catch {
            return items
        }
    }

    private func bindSyncFolderIfNeeded(
        for student: TeachingStudentItem,
        defaults: TeachingStudentSystemSettings,
        profile: TeachingStudentProfileSettings
    ) throws -> TeachingStudentProfileSettings? {
        if let path = profile.syncBaseFolderPath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return profile
        }
        guard let basePath = defaults.syncBaseFolderPath?.trimmingCharacters(in: .whitespacesAndNewlines), !basePath.isEmpty else {
            return profile == TeachingStudentProfileSettings() ? nil : profile
        }
        let matched = try TeachingSecurityScopedAccess.withWritableAccess(toPath: basePath) { writableBaseURL in
            let childURLs = try FileManager.default.contentsOfDirectory(
                at: writableBaseURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            return childURLs.first(where: { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return isDirectory && url.lastPathComponent.localizedCaseInsensitiveContains(student.name)
            })
        }
        guard let matched else {
            return profile == TeachingStudentProfileSettings() ? nil : profile
        }
        var updated = profile
        updated.syncBaseFolderPath = matched.path
        let normalized = updated.normalized()
        try TeachingStudentSettingsStore.saveStudentProfile(normalized, studentID: student.id)
        return normalized
    }

    private func isStudentInitialized(_ student: TeachingStudentItem) -> Bool {
        do {
            let studentFolder = try ArchiveStorage.ensureArchiveRoot()
                .appendingPathComponent("学生", isDirectory: true)
                .appendingPathComponent(student.name, isDirectory: true)
            let notebook = studentFolder.appendingPathComponent("随堂笔记_\(student.name).CSV", isDirectory: false)
            let studentInfo = studentFolder.appendingPathComponent("学生信息_\(student.name).CSV", isDirectory: false)
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: studentFolder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            let hasClassInfo = entries.contains {
                $0.lastPathComponent.hasPrefix("上课信息_\(student.name)_") && $0.pathExtension.lowercased() == "csv"
            }
            return FileManager.default.fileExists(atPath: notebook.path)
                && FileManager.default.fileExists(atPath: studentInfo.path)
                && hasClassInfo
        } catch {
            return false
        }
    }
}

private struct TeachingHomeStudentDocument: Identifiable {
    let id = UUID()
    let title: String
    let fileURL: URL
}

private extension View {
    @ViewBuilder
    func coursePagePresentation<Content: View>(
        student: Binding<TeachingStudentItem?>,
        @ViewBuilder content: @escaping (TeachingStudentItem) -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(item: student) { selectedStudent in
            content(selectedStudent)
        }
        #else
        sheet(item: student) { selectedStudent in
            content(selectedStudent)
        }
        #endif
    }
}

struct TeachingStudentItem: Identifiable, Equatable, Codable {
    static let supportedIcons: [String] = [
        "person.fill",
        "star.fill",
        "heart.fill",
        "bolt.fill",
        "leaf.fill",
        "flame.fill",
        "moon.fill",
        "sun.max.fill",
        "cloud.fill",
        "umbrella.fill",
        "snowflake",
        "drop.fill",
        "book.fill",
        "graduationcap.fill",
        "pencil",
        "paintbrush.fill",
        "music.note",
        "gamecontroller.fill",
        "camera.fill",
        "globe"
    ]

    static func displayName(forIcon iconName: String) -> String {
        switch iconName {
        case "person.fill": return "人物"
        case "star.fill": return "星星"
        case "heart.fill": return "爱心"
        case "bolt.fill": return "闪电"
        case "leaf.fill": return "树叶"
        case "flame.fill": return "火焰"
        case "moon.fill": return "月亮"
        case "sun.max.fill": return "太阳"
        case "cloud.fill": return "云朵"
        case "umbrella.fill": return "雨伞"
        case "snowflake": return "雪花"
        case "drop.fill": return "水滴"
        case "book.fill": return "书本"
        case "graduationcap.fill": return "学士帽"
        case "pencil": return "铅笔"
        case "paintbrush.fill": return "画笔"
        case "music.note": return "音符"
        case "gamecontroller.fill": return "手柄"
        case "camera.fill": return "相机"
        case "globe": return "地球"
        default: return "图标"
        }
    }

    var id: UUID = UUID()
    var name: String
    var iconName: String = "person.fill"
    var color: TeachingStudentColor = .blue
    var isSelected: Bool = true
}

enum TeachingStudentColor: String, CaseIterable, Identifiable, Codable {
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case cyan
    case blue
    case indigo
    case purple
    case pink
    case brown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .red: return "红色"
        case .orange: return "橙色"
        case .yellow: return "黄色"
        case .green: return "绿色"
        case .mint: return "薄荷色"
        case .teal: return "青色"
        case .cyan: return "青蓝色"
        case .blue: return "蓝色"
        case .indigo: return "靛蓝色"
        case .purple: return "紫色"
        case .pink: return "粉色"
        case .brown: return "棕色"
        }
    }

    var value: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        }
    }
}
