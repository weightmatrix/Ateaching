import SwiftUI

// MARK: - 教案系统设置面板 - v1 - 管理教案路径偏好与最近访问记录并持久化到快照
struct TeachingLessonPlanSystemSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var settings = TeachingLessonPlanSystemSettings()
    @State private var recentFoldersInput = ""
    @State private var statusMessage = ""
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section("教案路径偏好") {
                    TextField("教案根相对路径（可选）", text: binding(for: \.rootRelativePath), axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("最近访问教案目录") {
                    TextField("目录ID（逗号分隔）", text: $recentFoldersInput, axis: .vertical)
                        .lineLimit(2...4)
                    if !settings.recentLessonPlanFolderIDs.isEmpty {
                        Text("当前：\(settings.recentLessonPlanFolderIDs.joined(separator: "、"))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("清空最近访问") {
                        settings.recentLessonPlanFolderIDs.removeAll()
                        recentFoldersInput = ""
                    }
                }

                if !statusMessage.isEmpty {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("教案设置")
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
    }

    private func load() {
        do {
            let loaded = try TeachingStudentSettingsStore.loadLessonPlanSystemSettings()
            settings = loaded
            recentFoldersInput = loaded.recentLessonPlanFolderIDs.joined(separator: ", ")
        } catch {
            statusMessage = "加载失败：\(error.localizedDescription)"
        }
    }

    private func save() {
        settings.recentLessonPlanFolderIDs = recentFoldersInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        do {
            try TeachingStudentSettingsStore.saveLessonPlanSystemSettings(settings)
            statusMessage = "已保存。"
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func binding(for keyPath: WritableKeyPath<TeachingLessonPlanSystemSettings, String?>) -> Binding<String> {
        Binding(
            get: { settings[keyPath: keyPath] ?? "" },
            set: { newValue in
                let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                settings[keyPath: keyPath] = normalized.isEmpty ? nil : normalized
            }
        )
    }
}

