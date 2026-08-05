import SwiftUI
import Foundation

// MARK: - 授课系统验收面板 - v1 - 一键检查关键路径配置与学生建档基础能力
struct TeachingSystemDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var checks: [TeachingSystemCheckResult] = []
    @State private var statusMessage = ""
    @State private var didRun = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(checks) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(item.passed ? Color.green : Color.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(item.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("系统验收")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("重跑") { runChecks() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            }
            .task {
                guard !didRun else { return }
                didRun = true
                runChecks()
            }
        }
    }

    private func runChecks() {
        do {
            checks = try TeachingSystemDiagnosticsService.run()
            let failedCount = checks.filter { !$0.passed }.count
            statusMessage = failedCount == 0 ? "全部通过" : "未通过 \(failedCount) 项"
        } catch {
            checks = []
            statusMessage = "验收失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 验收结果模型 - v1 - 表达单项检查的通过状态与说明
struct TeachingSystemCheckResult: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var detail: String
    var passed: Bool
}

// MARK: - 验收服务 - v1 - 对设置快照模板目录学生目录与开关进行关键路径检查
enum TeachingSystemDiagnosticsService {
    static func run(fileManager: FileManager = .default) throws -> [TeachingSystemCheckResult] {
        let snapshot = try TeachingStudentSettingsStore.loadSnapshot(fileManager: fileManager)
        let workspace = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let studentsRoot = try ArchiveStorage.ensureArchiveRoot(fileManager: fileManager)
            .appendingPathComponent("学生", isDirectory: true)
        let singleListTemplates = try ArchiveStorage.loadTemplateEntries(category: .singleList, fileManager: fileManager)

        return [
            TeachingSystemCheckResult(
                title: "快照版本",
                detail: "schemaVersion=\(snapshot.schemaVersion)",
                passed: snapshot.schemaVersion > 0
            ),
            TeachingSystemCheckResult(
                title: "功能开关",
                detail: "建档=\(snapshot.featureFlags.enableStudentProvisioning ? "开" : "关"), 覆盖=\(snapshot.featureFlags.enableStudentProfileOverride ? "开" : "关")",
                passed: true
            ),
            TeachingSystemCheckResult(
                title: "工作区目录",
                detail: workspace.path,
                passed: fileManager.fileExists(atPath: workspace.path)
            ),
            TeachingSystemCheckResult(
                title: "学生根目录",
                detail: studentsRoot.path,
                passed: fileManager.fileExists(atPath: studentsRoot.path)
            ),
            TeachingSystemCheckResult(
                title: "单列表模板可用性",
                detail: "模板数量 \(singleListTemplates.count)",
                passed: !singleListTemplates.isEmpty
            ),
            TeachingSystemCheckResult(
                title: "学生列表",
                detail: "已配置 \(snapshot.students.count) 人",
                passed: true
            )
        ]
    }
}

