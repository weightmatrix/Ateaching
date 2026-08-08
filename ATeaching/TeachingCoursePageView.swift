import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

// MARK: - 课程页 - v2 - 独立承载四模式并实现学生目录文件浏览（排除随堂笔记）
struct TeachingCoursePageView: View {
    enum CourseMode: String, CaseIterable, Identifiable {
        case teaching = "上课"
        case files = "文件"
        case notes = "笔记"
        case initialize = "初始"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .teaching:
                return "play.fill"
            case .files:
                return "folder"
            case .notes:
                return "note.text"
            case .initialize:
                return "gearshape.2"
            }
        }
    }

    private struct MarkdownNavigationTarget: Identifiable, Hashable {
        let id: String
    }

    private struct SingleListNavigationTarget: Identifiable, Hashable {
        let id: String
    }

    private struct AutoFillNavigationTarget: Identifiable, Hashable {
        let id: String
    }

    private struct ChecklistNavigationTarget: Identifiable, Hashable {
        let id: String
        let mode: ChecklistDocumentEditorMode
    }

    private struct NodeMarkdownNavigationTarget: Identifiable, Hashable {
        let id: String
        var isReadOnlyRendered = false
    }

    private struct CourseChecklistPickingTarget: Identifiable, Hashable {
        let id: String
    }

    private enum TeachingCoursePageError: LocalizedError {
        case invalidLessonStatisticsPrice

        var errorDescription: String? {
            switch self {
            case .invalidLessonStatisticsPrice:
                return "课时价格必须是数字。"
            }
        }
    }

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    let student: TeachingStudentItem
    var initialMode: CourseMode = .teaching
    var onStudentRenamed: ((UUID, String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var selectedMode: CourseMode = .teaching
    @State private var modeStatusMessage = ""

    @State private var studentFilesRootURL: URL?
    @State private var studentCurrentDirectoryURL: URL?
    @State private var studentFileEntries: [ArchiveEntry] = []
    @State private var isLoadingStudentFiles = false
    @State private var studentFilesStatusMessage = ""
    @State private var showStudentFilesSheet = false
    @State private var showStudentFileRenameAlert = false
    @State private var studentFileRenameTarget: ArchiveEntry?
    @State private var studentFileRenameName = ""
    @State private var showStudentFileDeleteAlert = false
    @State private var studentFileDeleteTarget: ArchiveEntry?

    @State private var markdownNavigationTarget: MarkdownNavigationTarget?
    @State private var singleListNavigationTarget: SingleListNavigationTarget?
    @State private var autoFillNavigationTarget: AutoFillNavigationTarget?
    @State private var checklistNavigationTarget: ChecklistNavigationTarget?
    @State private var nodeMarkdownNavigationTarget: NodeMarkdownNavigationTarget?
    @State private var courseChecklistPickingTarget: CourseChecklistPickingTarget?
    @State private var initializeProfileSettings = TeachingStudentProfileSettings()
    @State private var initializeSelectionData = TeachingSelectionData.empty
    @State private var initializeLessonStatisticsInstitutions: [TeachingInstitutionRecord] = []
    @State private var initializeLessonStatisticsPriceInput = ""
    @State private var initializeSelectionReady = false
    @State private var showInitializeSyncFolderPicker = false
    @State private var didLoadInitializeProfile = false
    @State private var initializeWizardStep = 1
    @State private var isRunningWorkflow = false
    @State private var isSessionActive = false
    @State private var isNotesSessionActive = false
    @State private var showLessonChecklistSheet = false
    @State private var lessonCompletionFiles: [URL] = []
    @State private var showUpdatePreviewSheet = false
    @State private var updatePreview = TeachingCourseUpdatePreview(
        dirtyPackageCount: 0,
        newPackageCount: 0,
        chapterTargets: []
    )
    @State private var pendingUpdateCount = 0
    @State private var packageChangeTracker = TeachingCoursePackageChangeTracker()
    @State private var selectedUpdateChapterPath = ""
    @State private var selectedUpdateAnchorID = ""
    @State private var showReflectionSheet = false
    @State private var reflectionFiles: [URL] = []
    @State private var reflectionIndex = 0
    @State private var reflectionShowStudentInfo = false
    @State private var reflectionExportImageToken = 0
    @State private var renamedStudentName = ""
    @State private var showConflictSheet = false
    @State private var conflictItems: [TeachingCourseSyncConflictItem] = []
    @State private var didApplyInitialMode = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                modeBar
                modeContent
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("课程页-\(student.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回") {
                        dismiss()
                    }
                }
            }
            .task {
                if !didApplyInitialMode {
                    selectedMode = initialMode
                    didApplyInitialMode = true
                }
                if renamedStudentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    renamedStudentName = student.name
                }
                if selectedMode == .files {
                    presentStudentFilesSheet()
                }
                schedulePendingUpdateRefresh(force: true)
            }
            .onChange(of: selectedMode) { _, mode in
                if mode == .files {
                    presentStudentFilesSheet()
                }
                if mode == .teaching || mode == .notes {
                    schedulePendingUpdateRefresh()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .teachingNotebookDidPersistChange)) { notification in
                guard let changedPath = notification.userInfo?["filePath"] as? String else { return }
                guard isCurrentStudentNotebookPath(changedPath) else { return }
                schedulePendingUpdateRefresh()
            }
            .onDisappear {
                handleCoursePageDisappear()
            }
            .sheet(isPresented: $showStudentFilesSheet) {
                NavigationStack {
                    studentFilesPanel
                        .navigationTitle("文件")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") {
                                    showStudentFilesSheet = false
                                }
                            }
                        }
                        .alert("改名", isPresented: $showStudentFileRenameAlert) {
                            TextField("新名称", text: $studentFileRenameName)
                            Button("取消", role: .cancel) {
                                studentFileRenameTarget = nil
                            }
                            Button("保存") {
                                renameStudentFileEntry()
                            }
                        } message: {
                            Text("只修改当前学生文件夹中的选中文件或文件夹名称。")
                        }
                        .alert("确认删除", isPresented: $showStudentFileDeleteAlert) {
                            Button("取消", role: .cancel) {
                                studentFileDeleteTarget = nil
                            }
                            Button("移入回收站", role: .destructive) {
                                moveStudentFileEntryToRecycleBin()
                            }
                        } message: {
                            Text("文件将移动到“系统/回收站”，并保留来源记录。")
                        }
                }
                .singleListAdaptivePresentation(minWidth: 760, minHeight: 520)
            }
            .navigationDestination(item: $markdownNavigationTarget) { target in
                MarkdownEditorView(fileURL: URL(fileURLWithPath: target.id))
            }
            .navigationDestination(item: $singleListNavigationTarget) { target in
                SingleListDocumentEditorView(fileURL: URL(fileURLWithPath: target.id))
            }
            .navigationDestination(item: $autoFillNavigationTarget) { target in
                AutoFillDocumentEditorView(fileURL: URL(fileURLWithPath: target.id))
            }
            .navigationDestination(item: $checklistNavigationTarget) { target in
                ChecklistDocumentEditorView(fileURL: URL(fileURLWithPath: target.id), mode: target.mode)
            }
            #if os(iOS)
            .fullScreenCover(item: $nodeMarkdownNavigationTarget) { target in
                NavigationStack {
                    NodeMarkdownEditorView(
                        fileURL: URL(fileURLWithPath: target.id),
                        isReadOnlyRendered: target.isReadOnlyRendered
                    )
                }
            }
            #else
            .navigationDestination(item: $nodeMarkdownNavigationTarget) { target in
                NodeMarkdownEditorView(
                    fileURL: URL(fileURLWithPath: target.id),
                    isReadOnlyRendered: target.isReadOnlyRendered
                )
            }
            #endif
            .sheet(isPresented: $showLessonChecklistSheet) {
                NavigationStack {
                    Group {
                        if lessonCompletionFiles.isEmpty {
                            ContentUnavailableView(
                                "暂无可用完成清单",
                                systemImage: "doc.text.magnifyingglass",
                                description: Text("请先执行上课准备，生成“教案_*_完成情况_*”文件。")
                            )
                        } else {
                            List(lessonCompletionFiles, id: \.path) { fileURL in
                                Button {
                                    courseChecklistPickingTarget = CourseChecklistPickingTarget(id: fileURL.path)
                                    showLessonChecklistSheet = false
                                } label: {
                                    Text(fileURL.deletingPathExtension().lastPathComponent)
                                        .font(.body.monospaced())
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .frame(minWidth: 520, minHeight: 320)
                    .navigationTitle("教案完成清单")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") {
                                showLessonChecklistSheet = false
                            }
                        }
                    }
                }
            }
            .sheet(item: $courseChecklistPickingTarget) { target in
                NavigationStack {
                    ChecklistDocumentEditorView(
                        fileURL: URL(fileURLWithPath: target.id),
                        mode: .coursePicking,
                        onCoursePick: { rows in
                            applyCoursePickedRows(rows, completionChecklistPath: target.id)
                        }
                    )
                    .frame(minWidth: 720, minHeight: 520)
                }
            }
            .sheet(isPresented: $showUpdatePreviewSheet) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("本次更新预览")
                            .font(.headline)
                        Text("脏包：\(updatePreview.dirtyPackageCount)")
                        Text("新包（将进入上课收集）：\(updatePreview.newPackageCount)")
                        // 上课期间母本有更新机制暂停。上课中教师不修改母本，母本不会比随堂更新。
                        // 若需恢复，取消下面注释：
                        // if updatePreview.sourceUpdatePackageCount > 0 {
                        //     Text("母本有更新：\(updatePreview.sourceUpdatePackageCount)")
                        // }
                        if updatePreview.conflictPackageCount > 0 {
                            Text("双方冲突：\(updatePreview.conflictPackageCount)")
                                .foregroundStyle(.red)
                        }
                        if updatePreview.newPackageCount > 0 && !updatePreview.chapterTargets.isEmpty {
                            Divider()
                            Text("新包落位")
                                .font(.subheadline.weight(.semibold))
                            Picker("目标章", selection: $selectedUpdateChapterPath) {
                                ForEach(updatePreview.chapterTargets) { target in
                                    Text(target.displayName).tag(target.relativePath)
                                }
                            }
                            .pickerStyle(.menu)

                            Picker("插入位置", selection: $selectedUpdateAnchorID) {
                                Text("章末").tag("")
                                ForEach(selectedUpdateChapterTarget?.anchors ?? []) { anchor in
                                    Text("跟在：\(anchor.displayName)").tag(anchor.sourceID)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        Text("说明：脏包回传母本；母本更新写入随堂笔记；双方冲突不会自动覆盖；新包可按上方目标落位。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(16)
                    .navigationTitle("更新")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") {
                                showUpdatePreviewSheet = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("执行更新") {
                                showUpdatePreviewSheet = false
                                runUpdate()
                            }
                            .disabled(isRunningWorkflow)
                        }
                    }
                }
            }
            .sheet(isPresented: $showReflectionSheet) {
                NavigationStack {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Button {
                                stepReflection(delta: -1)
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .appGlassButtonStyle()
                            .disabled(reflectionFiles.isEmpty || reflectionShowStudentInfo)

                            Button {
                                stepReflection(delta: 1)
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .appGlassButtonStyle()
                            .disabled(reflectionFiles.isEmpty || reflectionShowStudentInfo)

                            Button {
                                reflectionShowStudentInfo.toggle()
                            } label: {
                                Label(reflectionShowStudentInfo ? "课" : "主", systemImage: reflectionShowStudentInfo ? "doc.text" : "person.text.rectangle")
                            }
                            .appGlassButtonStyle()
                            .disabled(studentInfoReflectionURL == nil)

                            Spacer()

                            Text(reflectionTitleText)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button {
                                exportReflectionCurrentFile()
                            } label: {
                                Label("导出", systemImage: "square.and.arrow.up.on.square")
                            }
                            .appGlassButtonStyle()
                            .disabled(currentReflectionFileURL == nil)
                        }
                        .padding(12)

                        if let currentURL = currentReflectionFileURL {
                            SingleListDocumentEditorView(
                                fileURL: currentURL,
                                externalExportImageToken: reflectionExportImageToken,
                                showsReflectionSiblingNavigation: false
                            )
                            .id(currentURL.path)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            #if os(macOS)
                            .frame(minHeight: 520)
                            #endif
                        } else {
                            ContentUnavailableView("无可用文件", systemImage: "doc")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            #if os(macOS)
                                .frame(minHeight: 520)
                            #endif
                        }
                    }
                    .navigationTitle("课反")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") {
                                showReflectionSheet = false
                            }
                        }
                    }
                }
                .singleListAdaptivePresentation(minWidth: 900, minHeight: 620)
            }
            .sheet(isPresented: $showConflictSheet) {
                NavigationStack {
                    List(conflictItems) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.displayText)
                                .font(.caption.monospaced())
                            HStack(spacing: 8) {
                                Button("采用母本") {
                                    resolveConflict(item, action: .acceptSource)
                                }
                                .appGlassButtonStyle()
                                .disabled(isRunningWorkflow)

                                Button("采用笔记") {
                                    resolveConflict(item, action: .acceptNotebook)
                                }
                                .appGlassButtonStyle()
                                .disabled(isRunningWorkflow)

                                Button("仅清标记") {
                                    resolveConflict(item, action: .clearMarker)
                                }
                                .appGlassButtonStyle()
                                .disabled(isRunningWorkflow)
                            }
                        }
                    }
                    .navigationTitle("同步冲突")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") {
                                showConflictSheet = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("清空") {
                                clearConflictLogs()
                            }
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showInitializeSyncFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let folderURL = urls.first {
                        let canonicalURL = TeachingSecurityScopedAccess.canonicalFolderURL(folderURL)
                        initializeProfileSettings.syncBaseFolderPath = canonicalURL.path
                        do {
                            try TeachingSecurityScopedAccess.storeBookmark(for: folderURL)
                        } catch {
                            modeStatusMessage = "目录授权保存失败：\(error.localizedDescription)"
                        }
                    }
                case .failure(let error):
                    modeStatusMessage = "目录选择失败：\(error.localizedDescription)"
                }
            }
            .onChange(of: initializeProfileSettings.studentInfoTemplateID) { _, _ in
                guard initializeSelectionReady else { return }
                TeachingStudentSelectionSupport.sanitizeSelections(&initializeProfileSettings, using: initializeSelectionData)
            }
            .onChange(of: initializeProfileSettings.classInfoTemplateID) { _, _ in
                guard initializeSelectionReady else { return }
                TeachingStudentSelectionSupport.sanitizeSelections(&initializeProfileSettings, using: initializeSelectionData)
            }
        }
    }

    private var modeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CourseMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                        if mode == .files {
                            presentStudentFilesSheet()
                        }
                    } label: {
                        Label(mode.rawValue, systemImage: mode.systemImage)
                    }
                    .appGlassButtonStyle(selectedMode == mode ? .prominent : .regular)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        #if os(iOS)
        TabView(selection: $selectedMode) {
            modePanel(for: .teaching)
                .tag(CourseMode.teaching)
            modePanel(for: .files)
                .tag(CourseMode.files)
            modePanel(for: .notes)
                .tag(CourseMode.notes)
            modePanel(for: .initialize)
                .tag(CourseMode.initialize)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        modePanel(for: selectedMode)
        #endif
    }

    @ViewBuilder
    private func modePanel(for mode: CourseMode) -> some View {
        switch mode {
        case .teaching:
            teachingModePanel
        case .files:
            studentFilesLauncherPanel
        case .notes:
            notesModePanel
        case .initialize:
            initializeModePanel
        }
    }

    private func coursePanel(title: String, subtitle: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var studentFilesLauncherPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("文件")
                .font(.headline)
            Text("学生：\(student.name)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                presentStudentFilesSheet()
            } label: {
                Label("打开学生文件夹", systemImage: "folder")
            }
            .appGlassButtonStyle(.prominent)

            if !studentFilesStatusMessage.isEmpty {
                Text(studentFilesStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var studentFilesPanel: some View {
        VStack(spacing: 0) {
            studentFilesHeader

            if isLoadingStudentFiles {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 10)
            }

            if studentFileEntries.isEmpty, !isLoadingStudentFiles {
                ContentUnavailableView("暂无文件", systemImage: "folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(studentFileEntries) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.iconName)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(entry.isDirectory ? appHighlightBlue : entry.iconColor)
                            .frame(width: 30, height: 30)
                        Text(entry.name)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if entry.isDirectory {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openStudentFileEntry(entry)
                    }
                    .contextMenu {
                        Button("改名") {
                            studentFileRenameTarget = entry
                            studentFileRenameName = entry.name
                            showStudentFileRenameAlert = true
                        }
                        Button("删除", role: .destructive) {
                            studentFileDeleteTarget = entry
                            showStudentFileDeleteAlert = true
                        }
                    }
                }
                .listStyle(.plain)
            }

            if !studentFilesStatusMessage.isEmpty {
                Text(studentFilesStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if !modeStatusMessage.isEmpty {
                Text(modeStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var teachingModePanel: some View {
        TeachingCourseTeachingPanel(
            studentName: student.name,
            isSessionActive: isSessionActive,
            isRunningWorkflow: isRunningWorkflow,
            modeStatusMessage: modeStatusMessage,
            onPrepare: runPrepareForTeaching
        )
    }

    private var notesModePanel: some View {
        TeachingCourseNotesPanel(
            studentName: student.name,
            isSessionActive: isNotesSessionActive,
            isRunningWorkflow: isRunningWorkflow,
            modeStatusMessage: modeStatusMessage,
            onPrepare: runPrepareForNotes
        )
    }

    private var initializeModePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("初始")
                .font(.headline)
            Text("学生：\(student.name)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(1...initializeWizardStepCount, id: \.self) { step in
                    Button {
                        initializeWizardStep = step
                    } label: {
                        Text("\(step)")
                            .font(.caption.weight(.semibold))
                            .frame(width: 24, height: 24)
                            .background(
                                Circle().fill(initializeWizardStep == step ? appHighlightBlue : Color.secondary.opacity(0.2))
                            )
                            .foregroundStyle(initializeWizardStep == step ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("第\(initializeWizardStep)步 / \(initializeWizardStepCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Group {
                switch initializeWizardStep {
                case 1:
                    initializeStepStudentName
                case 2:
                    initializeStepStudentInfoTemplate
                case 3:
                    initializeStepClassInfoTemplate
                case 4:
                    initializeStepLessonPlans
                case 5:
                    initializeStepWorkbook
                case 6 where shouldShowInitializeLessonStatisticsStep:
                    initializeStepLessonStatistics
                default:
                    initializeStepSyncAndActions
                }
            }
            .disabled(isRunningWorkflow)

            HStack(spacing: 10) {
                Button("上一步") {
                    initializeWizardStep = max(1, initializeWizardStep - 1)
                }
                .appGlassButtonStyle()
                .disabled(initializeWizardStep <= 1 || isRunningWorkflow)

                Button(initializeWizardStep >= initializeWizardStepCount ? "完成" : "下一步") {
                    initializeWizardStep = min(initializeWizardStepCount, initializeWizardStep + 1)
                }
                .appGlassButtonStyle()
                .disabled(!canAdvanceInitializeStep || isRunningWorkflow)
            }

            Text("重跑建档不会覆盖已存在的随堂笔记/学生信息/上课信息文件。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !modeStatusMessage.isEmpty {
                Text(modeStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .task {
            guard !didLoadInitializeProfile else { return }
            didLoadInitializeProfile = true
            loadInitializeProfileSettings()
        }
    }

    private var initializeStepStudentName: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("第1步：学生姓名")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                TextField("新学生姓名", text: $renamedStudentName)
                    .textFieldStyle(.roundedBorder)
                Button {
                    runRenameStudent()
                } label: {
                    Label("改名并同步", systemImage: "character.cursor.ibeam")
                }
                .appGlassButtonStyle()
                .disabled(isRunningWorkflow || renamedStudentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || renamedStudentName.trimmingCharacters(in: .whitespacesAndNewlines) == student.name)
            }
        }
    }

    private var initializeStepStudentInfoTemplate: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("第2步：学生信息模板")
                .font(.subheadline.weight(.semibold))
            Picker("学生信息模板", selection: $initializeProfileSettings.studentInfoTemplateID) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(initializeSelectionData.singleListTemplates) { template in
                    Text(template.title).tag(Optional(template.id))
                }
            }
            .pickerStyle(.menu)

            Picker("姓名栏", selection: $initializeProfileSettings.studentNameKeyID) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(initializeStudentNameKeyOptions) { option in
                    Text(option.title).tag(Optional(option.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(initializeProfileSettings.studentInfoTemplateID == nil || initializeStudentNameKeyOptions.isEmpty)
        }
    }

    private var initializeStepClassInfoTemplate: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("第3步：上课信息模板")
                .font(.subheadline.weight(.semibold))
            Picker("上课信息模板", selection: $initializeProfileSettings.classInfoTemplateID) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(initializeSelectionData.singleListTemplates) { template in
                    Text(template.title).tag(Optional(template.id))
                }
            }
            .pickerStyle(.menu)

            Picker("姓名", selection: $initializeProfileSettings.classInfoNameKeyID) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(initializeClassInfoKeyOptions) { option in
                    Text(option.title).tag(Optional(option.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(initializeProfileSettings.classInfoTemplateID == nil || initializeClassInfoKeyOptions.isEmpty)

            Picker("内容", selection: $initializeProfileSettings.classInfoContentKeyID) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(initializeClassInfoKeyOptions) { option in
                    Text(option.title).tag(Optional(option.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(initializeProfileSettings.classInfoTemplateID == nil || initializeClassInfoKeyOptions.isEmpty)

            Picker("时间", selection: $initializeProfileSettings.classInfoTimeKeyID) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(initializeClassInfoKeyOptions) { option in
                    Text(option.title).tag(Optional(option.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(initializeProfileSettings.classInfoTemplateID == nil || initializeClassInfoKeyOptions.isEmpty)
        }
    }

    private var initializeStepLessonPlans: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("第4步：教案（可多选）")
                .font(.subheadline.weight(.semibold))
            if initializeSelectionData.lessonPlanFolders.isEmpty {
                Text("未发现可选教案文件夹")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(initializeSelectionData.lessonPlanFolders, id: \.self) { folder in
                    Toggle(folder, isOn: Binding(
                        get: { initializeProfileSettings.lessonPlanFolderIDs.contains(folder) },
                        set: { isOn in
                            if isOn {
                                if !initializeProfileSettings.lessonPlanFolderIDs.contains(folder) {
                                    initializeProfileSettings.lessonPlanFolderIDs.append(folder)
                                }
                            } else {
                                initializeProfileSettings.lessonPlanFolderIDs.removeAll { $0 == folder }
                            }
                        }
                    ))
                }
                Text("已选：\(initializeProfileSettings.lessonPlanFolderIDs.isEmpty ? "未选择" : initializeProfileSettings.lessonPlanFolderIDs.joined(separator: "、"))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var initializeStepWorkbook: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("第5步：教辅（可选）")
                .font(.subheadline.weight(.semibold))
            Picker("教辅模板", selection: $initializeProfileSettings.workbookFileID) {
                Text("不选择").tag(Optional<String>.none)
                ForEach(initializeSelectionData.checklistTemplates) { template in
                    Text(template.title).tag(Optional(template.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var initializeStepLessonStatistics: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("第6步：统计")
                .font(.subheadline.weight(.semibold))

            Picker("机构名称", selection: initializeLessonStatisticsInstitutionBinding) {
                Text("不选择").tag(Optional<UUID>.none)
                ForEach(initializeLessonStatisticsInstitutions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { institution in
                    Text(institution.name).tag(Optional(institution.id))
                }
            }
            .pickerStyle(.menu)

            TextField("课时价格（2小时）", text: $initializeLessonStatisticsPriceInput)
                .textFieldStyle(.roundedBorder)

            if initializeLessonStatisticsInstitutions.isEmpty {
                Text("未配置机构；请先在统计机构设置中添加机构。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !canAdvanceInitializeStep {
                Text("选择机构后，课时价格不能为空。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var initializeStepSyncAndActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("第\(initializeWizardStepCount)步：文件夹与执行")
                .font(.subheadline.weight(.semibold))

            Text(initializeProfileSettings.syncBaseFolderPath ?? "未选择文件夹")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 10) {
                Button("选择文件夹") {
                    showInitializeSyncFolderPicker = true
                }
                .appGlassButtonStyle()

                if initializeProfileSettings.syncBaseFolderPath != nil {
                    Button("清除目录") {
                        initializeProfileSettings.syncBaseFolderPath = nil
                    }
                    .appGlassButtonStyle()
                }
            }

            HStack(spacing: 10) {
                Button {
                    saveInitializeProfileSettings()
                } label: {
                    Label("保存覆盖设置", systemImage: "square.and.arrow.down")
                }
                .appGlassButtonStyle()

                Button {
                    reprovisionStudentSkeleton()
                } label: {
                    Label("重跑建档骨架", systemImage: "arrow.clockwise.circle")
                }
                .appGlassButtonStyle()

                Button {
                    resetInitializeProfileSettings()
                } label: {
                    Label("恢复默认", systemImage: "arrow.uturn.backward")
                }
                .appGlassButtonStyle()
            }
        }
    }

    private var initializeWizardStepCount: Int {
        #if os(iOS)
        5
        #else
        shouldShowInitializeLessonStatisticsStep ? 7 : 6
        #endif
    }

    private var shouldShowInitializeLessonStatisticsStep: Bool {
        #if os(iOS)
        false
        #else
        TeachingDebugLogStore.isLessonStatisticsEnabled()
        #endif
    }

    private var initializeLessonStatisticsInstitutionBinding: Binding<UUID?> {
        Binding(
            get: {
                initializeProfileSettings.lessonStatistics.institutionID
            },
            set: { institutionID in
                applyInitializeLessonStatisticsInstitution(institutionID)
            }
        )
    }

    private var initializeStudentNameKeyOptions: [TeachingTemplateRowOption] {
        TeachingStudentSelectionSupport.rowOptions(for: initializeProfileSettings.studentInfoTemplateID, in: initializeSelectionData)
    }

    private var initializeClassInfoKeyOptions: [TeachingTemplateRowOption] {
        TeachingStudentSelectionSupport.classInfoRowOptions(for: initializeProfileSettings.classInfoTemplateID, in: initializeSelectionData)
    }

    private var canAdvanceInitializeStep: Bool {
        switch initializeWizardStep {
        case 2:
            return initializeProfileSettings.studentInfoTemplateID != nil && initializeProfileSettings.studentNameKeyID != nil
        case 3:
            let keys = [
                initializeProfileSettings.classInfoNameKeyID,
                initializeProfileSettings.classInfoContentKeyID,
                initializeProfileSettings.classInfoTimeKeyID
            ].compactMap { $0 }
            return initializeProfileSettings.classInfoTemplateID != nil && keys.count == 3 && Set(keys).count == 3
        case 6 where shouldShowInitializeLessonStatisticsStep:
            return validateInitializeLessonStatisticsInput()
        default:
            return true
        }
    }

    private var studentFilesHeader: some View {
        HStack(spacing: 10) {
            Text("学生文件")
                .font(.headline)

            if canNavigateToParentDirectory {
                Button {
                    navigateToParentDirectory()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .appGlassButtonStyle()
                .help("返回上级")
            }

            Spacer()

            Button {
                refreshStudentDirectory()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .appGlassButtonStyle()
            .help("刷新")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func presentStudentFilesSheet() {
        showStudentFilesSheet = true
        if studentFilesRootURL == nil, !isLoadingStudentFiles {
            loadStudentFilesRoot()
        }
    }

    private var notebookFileNameLowercased: String {
        "随堂笔记_\(student.name).csv".lowercased()
    }

    private func loadStudentFilesRoot() {
        guard !isLoadingStudentFiles else { return }
        isLoadingStudentFiles = true
        studentFilesStatusMessage = ""
        Task(priority: .userInitiated) {
            do {
                let archiveRoot = try ArchiveStorage.ensureArchiveRoot()
                let studentsRoot = archiveRoot.appendingPathComponent("学生", isDirectory: true)
                let studentRoot = studentsRoot.appendingPathComponent(student.name, isDirectory: true)
                try FileManager.default.createDirectory(at: studentRoot, withIntermediateDirectories: true)
                let loaded = try fileEntries(in: studentRoot)
                studentFilesRootURL = studentRoot
                studentCurrentDirectoryURL = studentRoot
                studentFileEntries = loaded
            } catch {
                studentFilesStatusMessage = error.localizedDescription
            }
            isLoadingStudentFiles = false
        }
    }

    private func refreshStudentDirectory() {
        if let root = studentFilesRootURL {
            guard !isLoadingStudentFiles else { return }
            isLoadingStudentFiles = true
            studentFilesStatusMessage = ""
            Task(priority: .userInitiated) {
                do {
                    let targetDirectory = studentCurrentDirectoryURL ?? root
                    studentFileEntries = try fileEntries(in: targetDirectory)
                    studentCurrentDirectoryURL = targetDirectory
                } catch {
                    studentFilesStatusMessage = error.localizedDescription
                }
                isLoadingStudentFiles = false
            }
        } else {
            loadStudentFilesRoot()
        }
    }

    private var canNavigateToParentDirectory: Bool {
        guard let root = studentFilesRootURL, let current = studentCurrentDirectoryURL else { return false }
        return current.path != root.path
    }

    private func fileEntries(in directoryURL: URL) throws -> [ArchiveEntry] {
        try ArchiveStorage.loadEntries(in: directoryURL).filter { entry in
            if entry.isDirectory { return true }
            return entry.name.lowercased() != notebookFileNameLowercased
        }
    }

    private func openStudentFileEntry(_ entry: ArchiveEntry) {
        if entry.isDirectory {
            guard !isLoadingStudentFiles else { return }
            isLoadingStudentFiles = true
            studentFilesStatusMessage = ""
            Task(priority: .userInitiated) {
                do {
                    studentFileEntries = try fileEntries(in: entry.url)
                    studentCurrentDirectoryURL = entry.url
                } catch {
                    studentFilesStatusMessage = error.localizedDescription
                }
                isLoadingStudentFiles = false
            }
            return
        }

        let fileExtension = entry.url.pathExtension.lowercased()
        let metaType = (ArchiveStorage.readMetaType(fileURL: entry.url) ?? "").lowercased()

        if fileExtension == "md" {
            #if os(macOS)
            openWindow(id: "markdown-editor", value: entry.url.path)
            #else
            markdownNavigationTarget = MarkdownNavigationTarget(id: entry.url.path)
            #endif
            return
        }

        if fileExtension == "csv", metaType == "singlelist" {
            singleListNavigationTarget = SingleListNavigationTarget(id: entry.url.path)
            return
        }

        if fileExtension == "csv", metaType == "autosinglelist" {
            autoFillNavigationTarget = AutoFillNavigationTarget(id: entry.url.path)
            return
        }

        if fileExtension == "csv", metaType == "checklist" || metaType == "workbook" {
            checklistNavigationTarget = ChecklistNavigationTarget(id: entry.url.path, mode: .standard)
            return
        }

        if (fileExtension == "csv" && (metaType == "nodemarkdown" || metaType == "nodesmarkdown" || metaType == "lessonplan"))
            || fileExtension == "nodemarkdown"
            || fileExtension == "nmd" {
            #if os(macOS)
            openWindow(id: "nodemarkdown-editor", value: entry.url.path)
            #else
            nodeMarkdownNavigationTarget = NodeMarkdownNavigationTarget(id: entry.url.path)
            #endif
        }
    }

    private func renameStudentFileEntry() {
        guard let target = studentFileRenameTarget else { return }
        let newName = studentFileRenameName
        Task(priority: .userInitiated) {
            do {
                try ArchiveStorage.renameItem(at: target.url, to: newName)
                studentFileRenameTarget = nil
                studentFileRenameName = ""
                refreshStudentDirectory()
            } catch {
                studentFilesStatusMessage = error.localizedDescription
            }
        }
    }

    private func moveStudentFileEntryToRecycleBin() {
        guard let target = studentFileDeleteTarget else { return }
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try RecycleBinManager.moveToRecycleBin(itemURL: target.url)
                }.value
                studentFileDeleteTarget = nil
                refreshStudentDirectory()
            } catch {
                studentFilesStatusMessage = error.localizedDescription
            }
        }
    }

    private func navigateToParentDirectory() {
        guard let root = studentFilesRootURL, let current = studentCurrentDirectoryURL else { return }
        guard current.path != root.path else { return }
        let parent = current.deletingLastPathComponent()
        guard parent.path.hasPrefix(root.path) else { return }
        guard !isLoadingStudentFiles else { return }
        isLoadingStudentFiles = true
        studentFilesStatusMessage = ""
        Task(priority: .userInitiated) {
            do {
                studentFileEntries = try fileEntries(in: parent)
                studentCurrentDirectoryURL = parent
            } catch {
                studentFilesStatusMessage = error.localizedDescription
            }
            isLoadingStudentFiles = false
        }
    }

    private func openNotebook(isReadOnlyRendered: Bool = false) {
        do {
            let archiveRoot = try ArchiveStorage.ensureArchiveRoot()
            let notebookURL = archiveRoot
                .appendingPathComponent("学生", isDirectory: true)
                .appendingPathComponent(student.name, isDirectory: true)
                .appendingPathComponent("随堂笔记_\(student.name).CSV", isDirectory: false)
            guard FileManager.default.fileExists(atPath: notebookURL.path) else {
                modeStatusMessage = "未找到随堂笔记文件。"
                return
            }
            #if os(macOS)
            openWindow(id: "nodemarkdown-editor", value: notebookURL.path)
            #else
            nodeMarkdownNavigationTarget = NodeMarkdownNavigationTarget(
                id: notebookURL.path,
                isReadOnlyRendered: isReadOnlyRendered
            )
            #endif
        } catch {
            modeStatusMessage = "打开随堂笔记失败：\(error.localizedDescription)"
        }
    }

    private func reprovisionStudentSkeleton() {
        isRunningWorkflow = true
        Task(priority: .userInitiated) {
            do {
                let defaultSettings = try TeachingStudentSettingsStore.loadStudentSystemSettings()
                let profileOverride = initializeProfileSettings.normalized()
                try TeachingStudentProvisioningService.provisionArchiveSkeleton(
                    for: student,
                    defaultSettings: defaultSettings,
                    profileOverride: profileOverride == TeachingStudentProfileSettings() ? nil : profileOverride
                )
                if let syncPath = profileOverride.syncBaseFolderPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !syncPath.isEmpty {
                    try TeachingStudentSyncFolderService.ensureStructure(syncRootPath: syncPath, studentName: student.name)
                }
                await MainActor.run {
                    modeStatusMessage = "已完成重跑建档骨架。"
                    isRunningWorkflow = false
                    if selectedMode == .files {
                        refreshStudentDirectory()
                    }
                }
            } catch {
                await MainActor.run {
                    modeStatusMessage = "重跑建档失败：\(error.localizedDescription)"
                    isRunningWorkflow = false
                }
            }
        }
    }

    private func loadInitializeProfileSettings() {
        do {
            if let loaded = try TeachingStudentSettingsStore.loadStudentProfile(studentID: student.id) {
                initializeProfileSettings = loaded
            } else {
                let defaults = try TeachingStudentSettingsStore.loadStudentSystemSettings()
                initializeProfileSettings = TeachingStudentProfileSettings(
                    studentInfoTemplateID: defaults.studentInfoTemplateID,
                    studentNameKeyID: defaults.studentNameKeyID,
                    classInfoTemplateID: defaults.classInfoTemplateID,
                    classInfoNameKeyID: defaults.classInfoNameKeyID,
                    classInfoContentKeyID: defaults.classInfoContentKeyID,
                    classInfoTimeKeyID: defaults.classInfoTimeKeyID,
                    lessonPlanFolderIDs: defaults.lessonPlanFolderIDs,
                    workbookFileID: defaults.workbookFileID,
                    syncBaseFolderPath: nil
                )
            }
            initializeSelectionData = try TeachingStudentSelectionSupport.loadSelectionData()
            initializeLessonStatisticsInstitutions = try TeachingLessonStatisticsStore.loadInstitutions()
            refreshInitializeLessonStatisticsPriceInput()
            initializeSelectionReady = true
            TeachingStudentSelectionSupport.sanitizeSelections(&initializeProfileSettings, using: initializeSelectionData)
        } catch {
            modeStatusMessage = "加载初始设置失败：\(error.localizedDescription)"
        }
    }

    private func saveInitializeProfileSettings() {
        do {
            if shouldShowInitializeLessonStatisticsStep {
                try syncInitializeLessonStatisticsInputToProfile()
            }
            let normalized = initializeProfileSettings.normalized()
            if let syncPath = normalized.syncBaseFolderPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !syncPath.isEmpty {
                try TeachingStudentSyncFolderService.ensureStructure(syncRootPath: syncPath, studentName: student.name)
            }
            try TeachingStudentSettingsStore.saveStudentProfile(normalized, studentID: student.id)
            initializeProfileSettings = normalized
            refreshInitializeLessonStatisticsPriceInput()
            modeStatusMessage = "学生覆盖设置已保存。"
        } catch {
            modeStatusMessage = "保存覆盖设置失败：\(error.localizedDescription)"
        }
    }

    private func resetInitializeProfileSettings() {
        do {
            try TeachingStudentSettingsStore.removeStudentProfile(studentID: student.id)
            initializeProfileSettings = TeachingStudentProfileSettings()
            initializeLessonStatisticsPriceInput = ""
            if initializeSelectionReady {
                TeachingStudentSelectionSupport.sanitizeSelections(&initializeProfileSettings, using: initializeSelectionData)
            }
            modeStatusMessage = "已恢复默认覆盖设置。"
        } catch {
            modeStatusMessage = "恢复默认失败：\(error.localizedDescription)"
        }
    }

    private func applyInitializeLessonStatisticsInstitution(_ institutionID: UUID?) {
        guard let institutionID,
              let institution = initializeLessonStatisticsInstitutions.first(where: { $0.id == institutionID }) else {
            initializeProfileSettings.lessonStatistics = TeachingStudentLessonStatisticsSettings()
            initializeLessonStatisticsPriceInput = ""
            return
        }

        initializeProfileSettings.lessonStatistics.institutionID = institution.id
        initializeProfileSettings.lessonStatistics.institutionName = institution.name
        if initializeLessonStatisticsPriceInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let defaultPrice = institution.defaultPriceForTwoHours {
            initializeProfileSettings.lessonStatistics.priceForTwoHours = defaultPrice
            initializeLessonStatisticsPriceInput = formatInitializeLessonStatisticsPrice(defaultPrice)
        }
    }

    private func validateInitializeLessonStatisticsInput() -> Bool {
        let hasInstitution = initializeProfileSettings.lessonStatistics.institutionID != nil
        let rawPrice = initializeLessonStatisticsPriceInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hasInstitution {
            return rawPrice.isEmpty
        }
        return Double(rawPrice) != nil
    }

    private func syncInitializeLessonStatisticsInputToProfile() throws {
        let rawPrice = initializeLessonStatisticsPriceInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard initializeProfileSettings.lessonStatistics.institutionID != nil else {
            initializeProfileSettings.lessonStatistics = TeachingStudentLessonStatisticsSettings()
            initializeLessonStatisticsPriceInput = ""
            return
        }
        guard let price = Double(rawPrice) else {
            throw TeachingCoursePageError.invalidLessonStatisticsPrice
        }
        initializeProfileSettings.lessonStatistics.priceForTwoHours = price
    }

    private func refreshInitializeLessonStatisticsPriceInput() {
        if let price = initializeProfileSettings.lessonStatistics.priceForTwoHours {
            initializeLessonStatisticsPriceInput = formatInitializeLessonStatisticsPrice(price)
        } else {
            initializeLessonStatisticsPriceInput = ""
        }
    }

    private func formatInitializeLessonStatisticsPrice(_ price: Double) -> String {
        if price.rounded() == price {
            return String(Int(price))
        }
        return String(price)
    }

    private func runRenameStudent() {
        guard !isRunningWorkflow else { return }
        let nextName = renamedStudentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextName.isEmpty else {
            modeStatusMessage = "请输入新学生姓名。"
            return
        }
        guard nextName != student.name else {
            modeStatusMessage = "姓名未变化。"
            return
        }
        isRunningWorkflow = true
        modeStatusMessage = "正在执行改名..."
        Task(priority: .userInitiated) {
            do {
                try await TeachingStudentRenameService.renameStudent(
                    studentID: student.id,
                    from: student.name,
                    to: nextName
                )
                await MainActor.run {
                    isRunningWorkflow = false
                    modeStatusMessage = "改名完成：\(student.name) → \(nextName)"
                    onStudentRenamed?(student.id, nextName)
                    NotificationCenter.default.post(name: .teachingStudentsDidChange, object: student.id)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isRunningWorkflow = false
                    modeStatusMessage = "改名失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func runPrepareForTeaching() {
        guard !isRunningWorkflow else { return }
        if isSessionActive {
            modeStatusMessage = "已经在上课中，请到随堂笔记窗口操作。"
            return
        }
        isRunningWorkflow = true
        modeStatusMessage = "正在准备上课..."
        Task(priority: .userInitiated) {
            do {
                let summary = try await TeachingCourseWorkflowService.prepareForTeaching(student: student)
                NotificationCenter.default.post(name: TeachingBackupScheduler.classStartedNotification, object: nil)
                await MainActor.run {
                    isRunningWorkflow = false
                    isSessionActive = true
                    isNotesSessionActive = false
                    modeStatusMessage = "上课准备完成：教案\(summary.lessonPlanCount) 模板\(summary.templateFileCount) 完成清单\(summary.completionFileCount) 刷新\(summary.refreshedPackageCount) 转新包\(summary.detachedPackageCount)"
                    if let notebookURL = try? notebookFileURLForStudent() {
                        startNotebookToolbarSession(kind: .teaching, notebookPath: notebookURL.path)
                    }
                    #if os(iOS)
                    openNotebook(isReadOnlyRendered: true)
                    #else
                    openNotebook()
                    #endif
                    schedulePendingUpdateRefresh(force: true)
                }
            } catch {
                await MainActor.run {
                    isRunningWorkflow = false
                    modeStatusMessage = "上课准备失败：\(error.localizedDescription)"
                    if error.localizedDescription.contains("未完成初始化") {
                        selectedMode = .initialize
                    }
                }
            }
        }
    }

    private func runPrepareForNotes() {
        guard !isRunningWorkflow else { return }
        isRunningWorkflow = true
        modeStatusMessage = "正在刷新笔记..."
        Task(priority: .userInitiated) {
            do {
                let summary = try await TeachingCourseWorkflowService.prepareForNotes(student: student)
                await MainActor.run {
                    isRunningWorkflow = false
                    isNotesSessionActive = true
                    modeStatusMessage = "笔记刷新完成：模板\(summary.templateFileCount) 完成清单\(summary.completionFileCount) 刷新\(summary.refreshedPackageCount) 转新包\(summary.detachedPackageCount)"
                    if let notebookURL = try? notebookFileURLForStudent() {
                        startNotebookToolbarSession(kind: .notes, notebookPath: notebookURL.path)
                    }
                    openNotebook()
                    schedulePendingUpdateRefresh(force: true)
                }
            } catch {
                await MainActor.run {
                    isRunningWorkflow = false
                    modeStatusMessage = "笔记刷新失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func startNotebookToolbarSession(
        kind: TeachingClassSessionCenter.SessionKind,
        notebookPath: String
    ) {
        TeachingClassSessionCenter.shared.start(
            kind: kind,
            notebookPath: notebookPath,
            onOpenLessonChecklist: { loadLessonCompletionFiles() },
            onUpdate: { requestUpdatePreview() },
            onOpenReflection: { openLatestClassInfo() },
            onFinishClass: { runFinishClass() },
            onExitSession: {
                switch kind {
                case .teaching:
                    isSessionActive = false
                case .notes:
                    isNotesSessionActive = false
                }
                TeachingClassSessionCenter.shared.end()
                dismiss()
            }
        )
    }

    private func runUpdate() {
        guard !isRunningWorkflow else { return }
        let preflight = TeachingCommercialReadinessVerifier.preflight(students: [student], requireSyncPath: false)
        guard preflight.canProceed else {
            modeStatusMessage = "更新前检查失败：\(preflight.blockingErrors.joined(separator: "；"))"
            return
        }
        isRunningWorkflow = true
        modeStatusMessage = "正在回传更新..."
        let placementTarget: TeachingCourseUpdatePlacementTarget? = {
            guard updatePreview.newPackageCount > 0,
                  !selectedUpdateChapterPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let anchor = selectedUpdateAnchorID.trimmingCharacters(in: .whitespacesAndNewlines)
            return TeachingCourseUpdatePlacementTarget(
                sourceFile: selectedUpdateChapterPath,
                anchorSourceID: anchor.isEmpty ? nil : anchor
            )
        }()
        Task(priority: .userInitiated) {
            do {
                let summary = try await TeachingCoursePackageSyncExecutor.syncDirtyPackages(
                    student: student,
                    placementTarget: placementTarget
                )
                await MainActor.run {
                    isRunningWorkflow = false
                    pendingUpdateCount = 0
                    modeStatusMessage = "更新完成：回传\(summary.updatedSourcePackageCount) 新收集\(summary.collectedNewPackageCount) 冲突\(summary.conflictPackageCount)"
                }
            } catch {
                await MainActor.run {
                    isRunningWorkflow = false
                    modeStatusMessage = "更新失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func requestUpdatePreview() {
        guard !isRunningWorkflow else { return }
        isRunningWorkflow = true
        modeStatusMessage = "正在分析更新包..."
        Task(priority: .userInitiated) {
            do {
                let preview = try await packageChangeTracker.loadPreview(student: student)
                await MainActor.run {
                    isRunningWorkflow = false
                    updatePreview = preview
                    if let first = preview.chapterTargets.first {
                        selectedUpdateChapterPath = first.relativePath
                        selectedUpdateAnchorID = ""
                    } else {
                        selectedUpdateChapterPath = ""
                        selectedUpdateAnchorID = ""
                    }
                    showUpdatePreviewSheet = true
                    modeStatusMessage = "更新预览就绪。"
                }
            } catch {
                await MainActor.run {
                    isRunningWorkflow = false
                    modeStatusMessage = "更新预览失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func runQuickSyncByCommandSave() {
        guard !isRunningWorkflow else { return }
        let preflight = TeachingCommercialReadinessVerifier.preflight(students: [student], requireSyncPath: false)
        guard preflight.canProceed else {
            modeStatusMessage = "同步前检查失败：\(preflight.blockingErrors.joined(separator: "；"))"
            return
        }
        isRunningWorkflow = true
        modeStatusMessage = "正在执行快捷同步..."
        Task(priority: .userInitiated) {
            do {
                let summary = try await TeachingCoursePackageSyncExecutor.syncDirtyPackages(
                    student: student,
                    placementTarget: nil
                )
                await MainActor.run {
                    isRunningWorkflow = false
                    modeStatusMessage = "快捷同步完成：回传\(summary.updatedSourcePackageCount) 新收集\(summary.collectedNewPackageCount) 冲突\(summary.conflictPackageCount)"
                }
            } catch {
                await MainActor.run {
                    isRunningWorkflow = false
                    modeStatusMessage = "快捷同步失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func runFinishClass() {
        guard !isRunningWorkflow else { return }
        let preflight = TeachingCommercialReadinessVerifier.preflight(students: [student], requireSyncPath: false)
        guard preflight.canProceed else {
            modeStatusMessage = "下课前检查失败：\(preflight.blockingErrors.joined(separator: "；"))"
            return
        }
        isRunningWorkflow = true
        modeStatusMessage = "正在下课收尾..."
        Task(priority: .userInitiated) {
            do {
                let summary = try await TeachingCourseWorkflowService.finishClass(student: student)
                NotificationCenter.default.post(name: TeachingBackupScheduler.classEndedNotification, object: nil)
                await MainActor.run {
                    isRunningWorkflow = false
                    isSessionActive = false
                    isNotesSessionActive = false
                    TeachingClassSessionCenter.shared.end()
                    if let exported = summary.exportedPDFPath {
                        modeStatusMessage = "下课完成：清理空节点\(summary.removedEmptyNodeCount) 回传\(summary.syncSummary.updatedSourcePackageCount) 收集\(summary.syncSummary.collectedNewPackageCount) 冲突\(summary.syncSummary.conflictPackageCount) PDF已生成：\(exported)"
                    } else {
                        modeStatusMessage = "下课完成：清理空节点\(summary.removedEmptyNodeCount) 回传\(summary.syncSummary.updatedSourcePackageCount) 收集\(summary.syncSummary.collectedNewPackageCount) 冲突\(summary.syncSummary.conflictPackageCount)"
                    }
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isRunningWorkflow = false
                    modeStatusMessage = "下课失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func openConflictLogs() {
        do {
            conflictItems = try TeachingCourseWorkflowService.loadRecentSyncConflictItems(student: student, limit: 120)
            if conflictItems.isEmpty {
                modeStatusMessage = "当前无待确认冲突。"
            } else {
                showConflictSheet = true
            }
        } catch {
            modeStatusMessage = "读取冲突失败：\(error.localizedDescription)"
        }
    }

    private func clearConflictLogs() {
        do {
            try TeachingCourseWorkflowService.clearSyncConflicts(student: student)
            conflictItems = []
            showConflictSheet = false
            modeStatusMessage = "已清空冲突记录。"
        } catch {
            modeStatusMessage = "清空冲突失败：\(error.localizedDescription)"
        }
    }

    private func resolveConflict(
        _ item: TeachingCourseSyncConflictItem,
        action: TeachingCourseConflictResolutionAction
    ) {
        guard !isRunningWorkflow else { return }
        isRunningWorkflow = true
        modeStatusMessage = "正在处理冲突：\(action.displayName)..."
        Task(priority: .userInitiated) {
            do {
                let message = try await TeachingCourseWorkflowService.resolveSyncConflict(
                    student: student,
                    item: item,
                    action: action
                )
                let refreshed = try TeachingCourseWorkflowService.loadRecentSyncConflictItems(student: student, limit: 120)
                await MainActor.run {
                    isRunningWorkflow = false
                    conflictItems = refreshed
                    modeStatusMessage = message
                    if refreshed.isEmpty {
                        showConflictSheet = false
                    }
                }
            } catch {
                await MainActor.run {
                    isRunningWorkflow = false
                    modeStatusMessage = "处理冲突失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func loadLessonCompletionFiles() {
        do {
            lessonCompletionFiles = try TeachingCourseWorkflowService
                .lessonCompletionChecklistFiles(student: student)
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            if lessonCompletionFiles.isEmpty {
                modeStatusMessage = "未找到完成清单，请先执行上课准备。"
            } else if lessonCompletionFiles.count == 1, let onlyFile = lessonCompletionFiles.first {
                courseChecklistPickingTarget = CourseChecklistPickingTarget(id: onlyFile.path)
                modeStatusMessage = "已自动进入唯一完成清单。"
            } else {
                showLessonChecklistSheet = true
            }
        } catch {
            modeStatusMessage = "读取教案清单失败：\(error.localizedDescription)"
        }
    }

    private func applyCoursePickedRows(_ rows: [ChecklistTemplateRow], completionChecklistPath: String?) {
        guard !rows.isEmpty else {
            modeStatusMessage = "未选择可插入的H3包。"
            return
        }
        guard !isRunningWorkflow else { return }
        isRunningWorkflow = true
        modeStatusMessage = "正在插入教案内容..."
        Task(priority: .userInitiated) {
            do {
                let summary = try await TeachingCourseWorkflowService.insertLessonPackagesIntoNotebook(
                    student: student,
                    pickedRows: rows,
                    completionChecklistFileURL: completionChecklistPath.flatMap { URL(fileURLWithPath: $0) },
                    insertionAnchorOverride: .documentEnd,
                    usesStoredActiveRow: false
                )
                await MainActor.run {
                    isRunningWorkflow = false
                    if let targetRow = summary.firstInsertedRowIndex,
                       let notebookURL = try? notebookFileURLForStudent() {
                        Task {
                            await TeachingCourseEditingAnchorStore.shared.setActiveRow(
                                filePath: notebookURL.path,
                                rowIndex: targetRow
                            )
                        }
                    }
                    let undoHint = summary.canUndo ? "（可撤销）" : ""
                    modeStatusMessage = "插入完成：成功\(summary.insertedPackageCount) 跳过\(summary.skippedPackageCount)\(undoHint)"
                    openNotebook()
                    schedulePendingUpdateRefresh()
                }
            } catch {
                await MainActor.run {
                    isRunningWorkflow = false
                    modeStatusMessage = "插入失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func runUndoLastInsert() {
        guard !isRunningWorkflow else { return }
        isRunningWorkflow = true
        modeStatusMessage = "正在撤销上一次插入..."
        Task(priority: .userInitiated) {
            do {
                let restored = try await TeachingCourseWorkflowService.undoLastLessonPackageInsert(student: student)
                await MainActor.run {
                    isRunningWorkflow = false
                    if restored {
                        modeStatusMessage = "已撤销最近一次教案插入。"
                        openNotebook()
                    } else {
                        modeStatusMessage = "没有可撤销的插入记录。"
                    }
                }
            } catch {
                await MainActor.run {
                    isRunningWorkflow = false
                    modeStatusMessage = "撤销失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func notebookFileURLForStudent() throws -> URL {
        try ArchiveStorage.ensureArchiveRoot()
            .appendingPathComponent("学生", isDirectory: true)
            .appendingPathComponent(student.name, isDirectory: true)
            .appendingPathComponent("随堂笔记_\(student.name).CSV", isDirectory: false)
    }

    private func openLatestClassInfo() {
        do {
            try repairReflectionFilesIfNeeded()
            reflectionFiles = try TeachingCourseWorkflowService.classInfoFileURLs(student: student)
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            reflectionIndex = max(0, reflectionFiles.count - 1)
            reflectionShowStudentInfo = false
            if reflectionFiles.isEmpty && studentInfoReflectionURL == nil {
                modeStatusMessage = "未找到课反相关文件。"
                return
            }
            showReflectionSheet = true
        } catch {
            modeStatusMessage = "打开课反失败：\(error.localizedDescription)"
        }
    }

    private func repairReflectionFilesIfNeeded() throws {
        let defaults = try TeachingStudentSettingsStore.loadStudentSystemSettings()
        let profile = try TeachingStudentSettingsStore.loadStudentProfile(studentID: student.id)
        try TeachingStudentProvisioningService.provisionArchiveSkeleton(
            for: student,
            defaultSettings: defaults,
            profileOverride: profile
        )
    }

    private var studentInfoReflectionURL: URL? {
        do {
            let url = try TeachingCourseWorkflowService.studentInfoFileURL(student: student)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        } catch {
            return nil
        }
    }

    private var currentReflectionFileURL: URL? {
        if reflectionShowStudentInfo {
            return studentInfoReflectionURL
        }
        guard !reflectionFiles.isEmpty else { return studentInfoReflectionURL }
        let safeIndex = max(0, min(reflectionIndex, reflectionFiles.count - 1))
        return reflectionFiles[safeIndex]
    }

    private var reflectionTitleText: String {
        if reflectionShowStudentInfo {
            return "学生信息"
        }
        guard !reflectionFiles.isEmpty else { return "无上课信息" }
        let safeIndex = max(0, min(reflectionIndex, reflectionFiles.count - 1))
        return reflectionFiles[safeIndex].lastPathComponent
    }

    private func stepReflection(delta: Int) {
        guard !reflectionFiles.isEmpty else { return }
        let count = reflectionFiles.count
        reflectionIndex = (reflectionIndex + delta + count) % count
    }

    private func exportReflectionCurrentFile() {
        guard currentReflectionFileURL != nil else { return }
        reflectionExportImageToken += 1
    }

    private var selectedUpdateChapterTarget: TeachingCourseUpdateChapterTarget? {
        updatePreview.chapterTargets.first { $0.relativePath == selectedUpdateChapterPath }
    }

    private func schedulePendingUpdateRefresh(
        minimumInterval: TimeInterval = 0.7,
        force: Bool = false
    ) {
        guard !isRunningWorkflow else { return }
        packageChangeTracker.schedulePendingRefresh(
            student: student,
            onCountUpdated: { count in
                pendingUpdateCount = count
            },
            minimumInterval: minimumInterval,
            force: force
        )
    }

    private func refreshPendingUpdateCountNow() {
        guard !isRunningWorkflow else { return }
        Task(priority: .utility) {
            await packageChangeTracker.refreshNow(student: student) { count in
                pendingUpdateCount = count
            }
        }
    }

    private func isCurrentStudentNotebookPath(_ path: String) -> Bool {
        guard let expected = try? notebookFileURLForStudent().standardizedFileURL.path else { return false }
        let incoming = URL(fileURLWithPath: path).standardizedFileURL.path
        return incoming == expected
    }

    private func handleCoursePageDisappear() {
        #if os(iOS)
        if isNavigatingToChildEditor { return }
        #endif
        guard let notebookPath = try? notebookFileURLForStudent().standardizedFileURL.path else { return }
        guard TeachingClassSessionCenter.shared.isActive(for: notebookPath) else { return }
        NotificationCenter.default.post(
            name: .teachingRequestCloseNotebook,
            object: nil,
            userInfo: ["filePath": notebookPath]
        )
    }

    private var isNavigatingToChildEditor: Bool {
        markdownNavigationTarget != nil
            || singleListNavigationTarget != nil
            || autoFillNavigationTarget != nil
            || checklistNavigationTarget != nil
            || nodeMarkdownNavigationTarget != nil
            || courseChecklistPickingTarget != nil
    }
}

private struct TeachingCourseTeachingPanel: View {
    let studentName: String
    let isSessionActive: Bool
    let isRunningWorkflow: Bool
    let modeStatusMessage: String
    let onPrepare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("上课")
                .font(.headline)
            Text("学生：\(studentName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isSessionActive {
                Text("已在上课中。请到随堂笔记窗口使用“随堂/更新/课反/下课/退出”。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    onPrepare()
                } label: {
                    Label("开课", systemImage: "play.fill")
                }
                .appGlassButtonStyle()
                .disabled(isRunningWorkflow)
            }

            if !modeStatusMessage.isEmpty {
                Text(modeStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

private struct TeachingCourseNotesPanel: View {
    let studentName: String
    let isSessionActive: Bool
    let isRunningWorkflow: Bool
    let modeStatusMessage: String
    let onPrepare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("笔记")
                .font(.headline)
            Text("学生：\(studentName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isSessionActive {
                Text("随堂笔记窗口已打开，请在 NodeMarkdown 编辑器左上角使用随堂、更新、下课、退出。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    onPrepare()
                } label: {
                    Label("刷新并编辑笔记", systemImage: "square.and.pencil")
                }
                .appGlassButtonStyle()
                .disabled(isRunningWorkflow)
            }

            if !modeStatusMessage.isEmpty {
                Text(modeStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

#if os(macOS)
struct TeachingCoursePageWindowHostView: View {
    let studentID: String
    @State private var student: TeachingStudentItem?
    @State private var initialMode: TeachingCoursePageView.CourseMode = .teaching
    @State private var loadError = ""

    var body: some View {
        Group {
            if let student {
                TeachingCoursePageView(student: student, initialMode: initialMode)
            } else if !loadError.isEmpty {
                ContentUnavailableView("无法打开课程页", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else {
                ProgressView("正在加载学生…")
            }
        }
        .task(id: studentID) {
            await loadStudent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .teachingStudentsDidChange)) { _ in
            Task { await loadStudent() }
        }
    }

    private func loadStudent() async {
        do {
            let students = try TeachingStudentSettingsStore.loadStudents()
            let parts = studentID.split(separator: "|", maxSplits: 1).map(String.init)
            let rawStudentID = parts.first ?? studentID
            if parts.count > 1, let parsedMode = TeachingCoursePageView.CourseMode(rawValue: parts[1]) {
                initialMode = parsedMode
            } else {
                initialMode = .teaching
            }
            guard let uuid = UUID(uuidString: rawStudentID) else {
                loadError = "学生ID无效：\(studentID)"
                student = nil
                return
            }
            guard let matched = students.first(where: { $0.id == uuid }) else {
                loadError = "未找到该学生（可能已删除）"
                student = nil
                return
            }
            student = matched
            loadError = ""
        } catch {
            loadError = error.localizedDescription
            student = nil
        }
    }
}
#endif
