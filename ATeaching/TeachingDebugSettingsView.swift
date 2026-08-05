import SwiftUI

struct TeachingDebugSettingsView: View {
    @State private var persistLogsEnabled = false
    @State private var layoutJitterLogsEnabled = false
    @State private var nodeMarkdownEditorPipeline: NodeMarkdownEditorPipeline = .textKit2
    @State private var textKit2FocusLocationOverlayEnabled = false
    @State private var lessonStatisticsEnabled = false
    @State private var statusMessage = ""
    @State private var didLoad = false

    var body: some View {
        Form {
            Section("Debug") {
                Toggle("调试日志", isOn: $persistLogsEnabled)
                    .onChange(of: persistLogsEnabled) { _, newValue in
                        save(
                            persistEnabled: newValue,
                            jitterEnabled: layoutJitterLogsEnabled,
                            editorPipeline: nodeMarkdownEditorPipeline,
                            textKit2FocusLocationOverlayEnabled: textKit2FocusLocationOverlayEnabled,
                            lessonStatisticsEnabled: lessonStatisticsEnabled
                        )
                    }
                Toggle("NodeMarkdown输入抖动日志", isOn: $layoutJitterLogsEnabled)
                    .onChange(of: layoutJitterLogsEnabled) { _, newValue in
                        save(
                            persistEnabled: persistLogsEnabled,
                            jitterEnabled: newValue,
                            editorPipeline: nodeMarkdownEditorPipeline,
                            textKit2FocusLocationOverlayEnabled: textKit2FocusLocationOverlayEnabled,
                            lessonStatisticsEnabled: lessonStatisticsEnabled
                        )
                    }
                Picker("NodeMarkdown编辑管线", selection: $nodeMarkdownEditorPipeline) {
                    ForEach(NodeMarkdownEditorPipeline.allCases) { pipeline in
                        Text(pipeline.displayName).tag(pipeline)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: nodeMarkdownEditorPipeline) { _, newValue in
                        save(
                            persistEnabled: persistLogsEnabled,
                            jitterEnabled: layoutJitterLogsEnabled,
                            editorPipeline: newValue,
                            textKit2FocusLocationOverlayEnabled: textKit2FocusLocationOverlayEnabled,
                            lessonStatisticsEnabled: lessonStatisticsEnabled
                        )
                    }
                Toggle("TextKit2焦点位置大字显示", isOn: $textKit2FocusLocationOverlayEnabled)
                    .onChange(of: textKit2FocusLocationOverlayEnabled) { _, newValue in
                        save(
                            persistEnabled: persistLogsEnabled,
                            jitterEnabled: layoutJitterLogsEnabled,
                            editorPipeline: nodeMarkdownEditorPipeline,
                            textKit2FocusLocationOverlayEnabled: newValue,
                            lessonStatisticsEnabled: lessonStatisticsEnabled
                        )
                    }
                Toggle("课时统计", isOn: $lessonStatisticsEnabled)
                    .onChange(of: lessonStatisticsEnabled) { _, newValue in
                        save(
                            persistEnabled: persistLogsEnabled,
                            jitterEnabled: layoutJitterLogsEnabled,
                            editorPipeline: nodeMarkdownEditorPipeline,
                            textKit2FocusLocationOverlayEnabled: textKit2FocusLocationOverlayEnabled,
                            lessonStatisticsEnabled: newValue
                        )
                    }
                NavigationLink {
                    TeachingDebugLogViewerView()
                } label: {
                    Label("查看调试日志", systemImage: "doc.text.magnifyingglass")
                }
            }
            TeachingStatusMessageSection(message: statusMessage)
        }
        .navigationTitle("Debug")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard !didLoad else { return }
            didLoad = true
            load()
        }
    }

    private func load() {
        do {
            let flags = try TeachingStudentSettingsStore.loadFeatureFlags()
            persistLogsEnabled = flags.persistDebugLogs
            let debugSettings = TeachingDebugLogStore.loadSettings()
            layoutJitterLogsEnabled = debugSettings.layoutJitterLogsEnabled
            nodeMarkdownEditorPipeline = debugSettings.nodeMarkdownEditorPipeline
            textKit2FocusLocationOverlayEnabled = debugSettings.textKit2FocusLocationOverlayEnabled
            lessonStatisticsEnabled = debugSettings.lessonStatisticsEnabled
            try TeachingDebugLogStore.saveSettings(
                .init(
                    persistLogsEnabled: flags.persistDebugLogs,
                    layoutJitterLogsEnabled: debugSettings.layoutJitterLogsEnabled,
                    nodeMarkdownEditorPipeline: debugSettings.nodeMarkdownEditorPipeline,
                    textKit2FocusLocationOverlayEnabled: debugSettings.textKit2FocusLocationOverlayEnabled,
                    lessonStatisticsEnabled: debugSettings.lessonStatisticsEnabled
                )
            )
        } catch {
            statusMessage = "读取Debug设置失败：\(error.localizedDescription)"
        }
    }

    private func save(
        persistEnabled: Bool,
        jitterEnabled: Bool,
        editorPipeline: NodeMarkdownEditorPipeline,
        textKit2FocusLocationOverlayEnabled: Bool,
        lessonStatisticsEnabled: Bool
    ) {
        do {
            var flags = try TeachingStudentSettingsStore.loadFeatureFlags()
            flags.persistDebugLogs = persistEnabled
            try TeachingStudentSettingsStore.saveFeatureFlags(flags)
            try TeachingDebugLogStore.saveSettings(
                .init(
                    persistLogsEnabled: persistEnabled,
                    layoutJitterLogsEnabled: jitterEnabled,
                    nodeMarkdownEditorPipeline: editorPipeline,
                    textKit2FocusLocationOverlayEnabled: textKit2FocusLocationOverlayEnabled,
                    lessonStatisticsEnabled: lessonStatisticsEnabled
                )
            )
            statusMessage = "已保存。"
        } catch {
            statusMessage = "保存Debug设置失败：\(error.localizedDescription)"
        }
    }
}

struct TeachingDebugActionToolsView: View {
    var body: some View {
        Form {
            Section("子目录") {
                NavigationLink {
                    TeachingH3DuplicateReportView()
                } label: {
                    Label("H3查重", systemImage: "text.magnifyingglass")
                }
                NavigationLink {
                    TeachingLessonWashActionView()
                } label: {
                    Label("洗教案", systemImage: "sparkles")
                }
                NavigationLink {
                    TeachingNotebookSSCActionView()
                } label: {
                    Label("随堂笔记SSC修改", systemImage: "arrow.triangle.2.circlepath")
                }
                NavigationLink {
                    TeachingInstitutionColorOrganizerView()
                } label: {
                    Label("颜色整理", systemImage: "paintpalette.fill")
                }
            }
        }
        .navigationTitle("功能按键")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TeachingInstitutionColorOrganizerView: View {
    @State private var statusMessage = ""
    @State private var showConfirmation = false

    var body: some View {
        Form {
            Section("机构颜色") {
                Button("重新整理全部机构颜色") {
                    showConfirmation = true
                }
                Text("按高区分度色板重新分配颜色；机构名称、价格、备注、图标和既有成课快照不变。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            TeachingStatusMessageSection(message: statusMessage)
        }
        .navigationTitle("颜色整理")
        .confirmationDialog("确认重新分配所有机构颜色？", isPresented: $showConfirmation) {
            Button("整理颜色") { reorganize() }
            Button("取消", role: .cancel) {}
        }
    }

    private func reorganize() {
        do {
            var institutions = try TeachingLessonStatisticsStore.loadInstitutions()
            let colors = TeachingInstitutionVisualPlanner.reorganizedColors(count: institutions.count)
            for index in institutions.indices {
                institutions[index].colorHex = colors[index]
            }
            try TeachingLessonStatisticsStore.saveInstitutions(institutions)
            statusMessage = "已重新整理 \(institutions.count) 个机构的颜色。"
        } catch {
            statusMessage = "颜色整理失败：\(error.localizedDescription)"
        }
    }
}

private struct TeachingLessonWashActionView: View {
    @State private var statusMessage = ""
    @State private var isRunning = false
    @State private var showConfirmation = false
    @State private var reportLines: [String] = []

    var body: some View {
        Form {
            Section("洗教案") {
                Button(role: .destructive) {
                    guard TeachingClassSessionCenter.shared.session == nil else {
                        statusMessage = "正在上课或笔记中，不能洗教案。请先关闭当前会话。"
                        return
                    }
                    showConfirmation = true
                } label: {
                    Label("洗教案", systemImage: "sparkles")
                }
                .disabled(isRunning)

                if !reportLines.isEmpty {
                    ForEach(Array(reportLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            TeachingStatusMessageSection(message: statusMessage)
        }
        .navigationTitle("洗教案")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "确认清洗全部正式教案、随堂笔记和完成清单？",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("开始洗教案", role: .destructive) {
                runWash()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("上课收集只读取、不修改；无法唯一确认的H3会保留并写入报告。")
        }
    }

    private func runWash() {
        isRunning = true
        statusMessage = "正在扫描并清洗，请勿编辑教案或随堂笔记…"
        reportLines = []

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let report = try TeachingLessonWashService.run()
                var lines = [
                    "正式教案：\(report.lessonFileCount)",
                    "重复H3组：\(report.duplicateH3GroupCount)",
                    "更换H3 UUID：\(report.reassignedH3Count)",
                    "更换其他UUID：\(report.reassignedOtherNodeCount)",
                    "清理图片残留：\(report.removedImageGarbageCount)",
                    "清理公式旧链接：\(report.removedFormulaLinkCount)",
                    "随堂笔记：\(report.notebookFileCount)",
                    "重建随堂H3：\(report.rebuiltNotebookPackageCount)",
                    "删除随堂重复H3：\(report.removedDuplicateNotebookPackageCount)",
                    "重建完成清单：\(report.completionChecklistCount)",
                    "待人工处理：\(report.unresolvedItems.count)",
                    "保持原样文件：\(report.skippedFiles.count)",
                    "UUID暂存表：\(report.mappingFileURL?.path ?? "未生成")",
                    "清洗报告：\(report.reportFileURL?.path ?? "未生成")"
                ]
                if !report.unresolvedItems.isEmpty {
                    lines.append("—— 待人工处理明细 ——")
                    lines.append(contentsOf: report.unresolvedItems.enumerated().map { index, item in
                        "\(index + 1). \(item.displayLine)\n文件：\(item.file)\nUUID：\(item.uuid)\nSourceID：\(item.sourceID)\nSourceFile：\(item.sourceFile)"
                    })
                }
                if !report.skippedFiles.isEmpty {
                    lines.append("—— 保持原样文件 ——")
                    lines.append(contentsOf: report.skippedFiles.enumerated().map { index, item in
                        "\(index + 1). \(item.displayLine)"
                    })
                }
                DispatchQueue.main.async {
                    reportLines = lines
                    statusMessage = "洗教案完成。"
                    isRunning = false
                }
            } catch {
                DispatchQueue.main.async {
                    statusMessage = "洗教案失败：\(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
    }
}

private struct TeachingNotebookSSCActionView: View {
    @State private var statusMessage = ""
    @State private var isRunning = false
    @State private var reportLines: [String] = []

    var body: some View {
        Form {
            Section("随堂笔记SSC修改") {
                Button {
                    runMigration()
                } label: {
                    Label("随堂笔记SSC修改", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isRunning)

                if !reportLines.isEmpty {
                    ForEach(reportLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            }
            TeachingStatusMessageSection(message: statusMessage)
        }
        .navigationTitle("随堂笔记SSC修改")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runMigration() {
        isRunning = true
        statusMessage = "处理中…"
        reportLines = []

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let report = try TeachingNotebookSSCMigrationService.run()
                let lines = [
                    "教案文件：\(report.lessonPlanFileCount)",
                    "随堂文件：\(report.notebookFileCount)",
                    "清空字段次数：\(report.clearedNonH3FieldCount)",
                    "修复链接次数：\(report.repairedH3LinkCount)",
                    "未修复H3：\(report.unresolvedH3LinkCount)",
                    "删除上课收集包：\(report.removedCollectorPackageCount)"
                ] + report.repairedSamples.prefix(20).map { "样例: \($0)" }
                    + report.issueMessages.prefix(30)

                DispatchQueue.main.async {
                    reportLines = lines
                    statusMessage = "迁移完成。"
                    isRunning = false
                }
            } catch {
                DispatchQueue.main.async {
                    statusMessage = "迁移失败：\(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
    }
}

private struct TeachingDebugLogViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var statusMessage = ""

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                Text(content.isEmpty ? "暂无调试日志" : content)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            TeachingStatusMessageSection(message: statusMessage)
        }
        .padding(.horizontal, 12)
        .navigationTitle("调试日志")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("刷新") { reload() }
                Button("清空") { clear() }
                Button("关闭") { dismiss() }
            }
        }
        .task {
            reload()
        }
    }

    private func reload() {
        content = TeachingDebugLogStore.readLog()
    }

    private func clear() {
        do {
            try TeachingDebugLogStore.clearLog()
            reload()
            statusMessage = "已清空。"
        } catch {
            statusMessage = "清空失败：\(error.localizedDescription)"
        }
    }
}
