import SwiftUI
import UniformTypeIdentifiers

// MARK: - 学生覆盖设置面板 - v2 - 与系统设置页统一为模板与目录选择交互
struct TeachingStudentProfileSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let student: TeachingStudentItem

    @State private var settings = TeachingStudentProfileSettings()
    @State private var statusMessage = ""
    @State private var didLoad = false
    @State private var selectionData = TeachingSelectionData.empty
    @State private var selectionDataReady = false
    @State private var showSyncFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("学生") {
                    Text(student.name)
                }

                TeachingStudentMappingSectionsView(
                    settings: $settings,
                    selectionData: selectionData,
                    showSyncFolderPicker: $showSyncFolderPicker,
                    titles: TeachingStudentMappingSectionTitles(
                        studentInfo: "学生信息",
                        classInfo: "上课信息",
                        lessonPlanAndSync: "教案、教辅、文件夹",
                        studentNameField: "姓名栏",
                        syncPathLineLimit: 1...3
                    )
                )

                TeachingStatusMessageSection(message: statusMessage)

                Section {
                    Button("恢复默认") {
                        resetOverride()
                    }
                }
            }
            .navigationTitle("学生配置")
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
            .fileImporter(
                isPresented: $showSyncFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let folderURL = urls.first {
                        let canonicalURL = TeachingSecurityScopedAccess.canonicalFolderURL(folderURL)
                        settings.syncBaseFolderPath = canonicalURL.path
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
            .onChange(of: settings.studentInfoTemplateID) { _, _ in
                guard selectionDataReady else { return }
                TeachingStudentSelectionSupport.sanitizeSelections(&settings, using: selectionData)
            }
            .onChange(of: settings.classInfoTemplateID) { _, _ in
                guard selectionDataReady else { return }
                TeachingStudentSelectionSupport.sanitizeSelections(&settings, using: selectionData)
            }
        }
    }

    private func load() {
        do {
            if let loaded = try TeachingStudentSettingsStore.loadStudentProfile(studentID: student.id) {
                settings = loaded
            } else {
                settings = TeachingStudentProfileSettings()
            }
            if reloadSelectionSources() {
                TeachingStudentSelectionSupport.sanitizeSelections(&settings, using: selectionData)
            }
        } catch {
            statusMessage = "加载失败：\(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try TeachingStudentSettingsStore.saveStudentProfile(settings, studentID: student.id)
            statusMessage = "已保存。"
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func resetOverride() {
        do {
            try TeachingStudentSettingsStore.removeStudentProfile(studentID: student.id)
            settings = TeachingStudentProfileSettings()
            if selectionDataReady {
                TeachingStudentSelectionSupport.sanitizeSelections(&settings, using: selectionData)
            }
            statusMessage = "已恢复默认。"
        } catch {
            statusMessage = "恢复默认失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    private func reloadSelectionSources() -> Bool {
        do {
            selectionData = try TeachingStudentSelectionSupport.loadSelectionData()
            selectionDataReady = true
            return true
        } catch {
            selectionDataReady = false
            statusMessage = "选项加载失败：\(error.localizedDescription)"
            return false
        }
    }

}
