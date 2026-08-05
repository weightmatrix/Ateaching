import SwiftUI
import UniformTypeIdentifiers

// MARK: - 学生系统设置面板 - v3 - 使用模板与目录选择器替代UUID手填并支持路径点击选择
struct TeachingStudentSystemSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var settings = TeachingStudentSystemSettings()
    @State private var featureFlags = TeachingFeatureFlags()
    @State private var statusMessage = ""
    @State private var didLoad = false
    @State private var selectionData = TeachingSelectionData.empty
    @State private var selectionDataReady = false
    @State private var showSyncFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                TeachingStudentMappingSectionsView(
                    settings: $settings,
                    selectionData: selectionData,
                    showSyncFolderPicker: $showSyncFolderPicker,
                    titles: TeachingStudentMappingSectionTitles(
                        studentInfo: "学生信息",
                        classInfo: "上课信息",
                        lessonPlanAndSync: "教案、教辅、文件夹",
                        studentNameField: "学生信息姓名栏",
                        syncPathLineLimit: 2...4
                    )
                )

                Section("关键开关") {
                    Toggle("创建学生时自动建档", isOn: $featureFlags.enableStudentProvisioning)
                    Toggle("启用学生级覆盖配置", isOn: $featureFlags.enableStudentProfileOverride)
                }

                TeachingStatusMessageSection(message: statusMessage)
            }
            .navigationTitle("学生设置")
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
            let loaded = try TeachingStudentSettingsStore.loadStudentSystemSettings()
            settings = loaded
            featureFlags = try TeachingStudentSettingsStore.loadFeatureFlags()
            if reloadSelectionSources() {
                TeachingStudentSelectionSupport.sanitizeSelections(&settings, using: selectionData)
            }
        } catch {
            statusMessage = "加载失败：\(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try TeachingStudentSettingsStore.saveStudentSystemSettings(settings)
            try TeachingStudentSettingsStore.saveFeatureFlags(featureFlags)
            statusMessage = "已保存。"
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
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
