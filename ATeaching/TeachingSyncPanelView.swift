import SwiftUI

struct TeachingSyncPanelView: View {
    let students: [TeachingStudentItem]
    let showTopActionButtons: Bool
    let externalPrepareToken: Int
    let externalExportToken: Int
    let externalCheckToken: Int
    let externalReadinessToken: Int
    let externalAuditToken: Int
    let externalStressToken: Int
    let externalCancelToken: Int

    init(
        students: [TeachingStudentItem],
        showTopActionButtons: Bool = true,
        externalPrepareToken: Int = 0,
        externalExportToken: Int = 0,
        externalCheckToken: Int = 0,
        externalReadinessToken: Int = 0,
        externalAuditToken: Int = 0,
        externalStressToken: Int = 0,
        externalCancelToken: Int = 0
    ) {
        self.students = students
        self.showTopActionButtons = showTopActionButtons
        self.externalPrepareToken = externalPrepareToken
        self.externalExportToken = externalExportToken
        self.externalCheckToken = externalCheckToken
        self.externalReadinessToken = externalReadinessToken
        self.externalAuditToken = externalAuditToken
        self.externalStressToken = externalStressToken
        self.externalCancelToken = externalCancelToken
    }

    @State private var isRunning = false
    @State private var progress: TeachingCourseSyncProgressSnapshot?
    @State private var task: Task<Void, Never>?
    @State private var statusMessage = ""
    @State private var jobHistory: [TeachingCourseJobSnapshot] = []
    @State private var showConsistencyReportSheet = false
    @State private var showReadinessReportSheet = false
    @State private var showAuditSheet = false
    @State private var consistencyReports: [String: TeachingCourseConsistencySummary] = [:]
    @State private var readinessReport = TeachingCommercialReadinessReport(totalChecks: 0, warningCount: 0, errorCount: 0, messages: [])
    @State private var isRepairingConsistency = false
    @State private var repairStrategy: TeachingCourseRepairStrategy = .standard
    @State private var auditKeyword = ""
    @State private var auditItems: [TeachingCourseAuditLogItem] = []
    @State private var stressRounds = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("同步")
                .font(.headline)

            if showTopActionButtons {
                HStack(spacing: 8) {
                    Button {
                        runPrepareAllStudents()
                    } label: {
                        Label("上课准备", systemImage: "figure.and.child.holdinghands")
                    }
                    .appGlassButtonStyle(.prominent)
                    .disabled(isRunning || students.isEmpty)

                    Button {
                        runExportAllPDF()
                    } label: {
                        Label("PDF", systemImage: "doc.richtext")
                    }
                    .appGlassButtonStyle()
                    .disabled(isRunning || students.isEmpty)

                    Button {
                        runCheckConsistencyAllStudents()
                    } label: {
                        Label("巡检", systemImage: "checklist")
                    }
                    .appGlassButtonStyle()
                    .disabled(isRunning || students.isEmpty)

                    Button {
                        runCommercialReadinessCheck()
                    } label: {
                        Label("验收", systemImage: "checkmark.shield")
                    }
                    .appGlassButtonStyle()
                    .disabled(isRunning)

                    Button {
                        showAuditSheet = true
                        reloadAuditLogs()
                    } label: {
                        Label("审计", systemImage: "doc.text.magnifyingglass")
                    }
                    .appGlassButtonStyle()
                    .disabled(isRunning)

                    Button {
                        runStressTestAllStudents()
                    } label: {
                        Label("压测", systemImage: "speedometer")
                    }
                    .appGlassButtonStyle()
                    .disabled(isRunning || students.isEmpty)

                    if isRunning {
                        Button(role: .destructive) {
                            task?.cancel()
                            statusMessage = "正在取消任务..."
                        } label: {
                            Label("取消", systemImage: "xmark.circle")
                        }
                        .appGlassButtonStyle(.danger)
                    }
                }
            }

            HStack(spacing: 8) {
                Picker("修复策略", selection: $repairStrategy) {
                    ForEach(TeachingCourseRepairStrategy.allCases, id: \.self) { strategy in
                        Text(strategy.displayName).tag(strategy)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)

                Button {
                    rollbackLatestRepairBatch()
                } label: {
                    Label("回滚最近修复", systemImage: "arrow.uturn.backward.circle")
                }
                .appGlassButtonStyle()
                .disabled(isRunning || isRepairingConsistency)

                Stepper("轮次 \(stressRounds)", value: $stressRounds, in: 1...20)
                    .frame(maxWidth: 130)
            }

            if let progress {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progress.fractionCompleted)
                    Text(progressText(progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let path = progress.currentFilePath, !path.isEmpty {
                        Text("当前文件：\(path)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else if students.isEmpty {
                Text("暂无学生可同步。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !jobHistory.isEmpty {
                Divider()
                Text("任务历史")
                    .font(.subheadline.weight(.semibold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(jobHistory) { job in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(job.title)
                                        .font(.caption.weight(.semibold))
                                    Text(stateText(job.state))
                                        .font(.caption2)
                                        .foregroundStyle(stateColor(job.state))
                                    Spacer()
                                    Text(timeText(job))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(job.message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                if job.state == .failed, canRetry(job) {
                                    Button {
                                        retryJob(job)
                                    } label: {
                                        Label("重试失败学生", systemImage: "arrow.clockwise")
                                    }
                                    .appGlassButtonStyle()
                                    .disabled(isRunning || isRepairingConsistency)
                                }
                                if canShowConsistencyDetails(job) {
                                    Button {
                                        openConsistencyDetails(job)
                                    } label: {
                                        Label("查看巡检详情", systemImage: "list.bullet.rectangle")
                                    }
                                    .appGlassButtonStyle()
                                    .disabled(isRunning || isRepairingConsistency)
                                }
                                if canRepairConsistency(job) {
                                    Button {
                                        repairAndRetryConsistency(job)
                                    } label: {
                                        Label("一键修复并重跑", systemImage: "wrench.and.screwdriver")
                                    }
                                    .appGlassButtonStyle()
                                    .disabled(isRunning || isRepairingConsistency)
                                }
                                if let report = job.readinessReport {
                                    Button {
                                        readinessReport = report
                                        showReadinessReportSheet = true
                                    } label: {
                                        Label("查看验收详情", systemImage: "checkmark.shield")
                                    }
                                    .appGlassButtonStyle()
                                    .disabled(isRunning || isRepairingConsistency)
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.secondary.opacity(0.08))
                            )
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .onDisappear {
            task?.cancel()
        }
        .task {
            await reloadJobHistory()
        }
        .onChange(of: externalPrepareToken) { _, _ in
            guard !showTopActionButtons else { return }
            runPrepareAllStudents()
        }
        .onChange(of: externalExportToken) { _, _ in
            guard !showTopActionButtons else { return }
            runExportAllPDF()
        }
        .onChange(of: externalCheckToken) { _, _ in
            guard !showTopActionButtons else { return }
            runCheckConsistencyAllStudents()
        }
        .onChange(of: externalReadinessToken) { _, _ in
            guard !showTopActionButtons else { return }
            runCommercialReadinessCheck()
        }
        .onChange(of: externalAuditToken) { _, _ in
            guard !showTopActionButtons else { return }
            showAuditSheet = true
            reloadAuditLogs()
        }
        .onChange(of: externalStressToken) { _, _ in
            guard !showTopActionButtons else { return }
            runStressTestAllStudents()
        }
        .onChange(of: externalCancelToken) { _, _ in
            guard !showTopActionButtons else { return }
            guard isRunning else { return }
            task?.cancel()
            statusMessage = "正在取消任务..."
        }
        .sheet(isPresented: $showConsistencyReportSheet) {
            consistencyReportSheet
        }
        .sheet(isPresented: $showReadinessReportSheet) {
            readinessReportSheet
        }
        .sheet(isPresented: $showAuditSheet) {
            auditSheet
        }
    }

    private func runAction(
        _ action: TeachingCourseSyncProgressSnapshot.Action,
        targetStudents: [TeachingStudentItem],
        work: @escaping @Sendable (_ jobID: UUID) async throws -> TeachingCourseSyncResult
    ) {
        guard !isRunning else { return }
        isRunning = true
        statusMessage = ""
        progress = TeachingCourseSyncProgressSnapshot(
            action: action,
            completedStudents: 0,
            totalStudents: max(1, targetStudents.count),
            currentStudentName: nil,
            currentFilePath: nil
        )

        task = Task {
            let jobID = await TeachingCourseJobCenter.shared.createJob(
                title: action.displayName,
                action: action,
                totalUnits: max(1, targetStudents.count)
            )
            await TeachingCourseJobCenter.shared.markRunning(jobID, message: "任务启动")
            do {
                let result = try await work(jobID)
                let finalText = resultText(result, participantCount: targetStudents.count)
                if result.failures.isEmpty {
                    await TeachingCourseJobCenter.shared.markSucceeded(jobID, message: finalText)
                } else {
                    await TeachingCourseJobCenter.shared.markFailed(
                        jobID,
                        message: finalText,
                        failedStudentNames: result.failures.map(\.studentName),
                        consistencyReportsByStudent: result.consistencyReportsByStudent
                    )
                }
                await MainActor.run {
                    finishAction()
                    if result.action == .checkConsistency {
                        consistencyReports = result.consistencyReportsByStudent
                    }
                    statusMessage = finalText
                }
                await reloadJobHistory()
            } catch is CancellationError {
                await TeachingCourseJobCenter.shared.markCancelled(jobID, message: "任务已取消")
                await MainActor.run {
                    finishAction()
                    statusMessage = "任务已取消。"
                }
                await reloadJobHistory()
            } catch {
                await TeachingCourseJobCenter.shared.markFailed(jobID, message: error.localizedDescription)
                await MainActor.run {
                    finishAction()
                    statusMessage = "任务失败：\(error.localizedDescription)"
                }
                await reloadJobHistory()
            }
        }
    }

    private func finishAction() {
        isRunning = false
        task = nil
        progress = nil
    }

    private func progressText(_ snapshot: TeachingCourseSyncProgressSnapshot) -> String {
        let studentName = snapshot.currentStudentName ?? "准备中"
        return "\(snapshot.action.displayName) · \(snapshot.completedStudents)/\(snapshot.totalStudents) · \(studentName)"
    }

    private func resultText(_ result: TeachingCourseSyncResult, participantCount: Int) -> String {
        if result.failures.isEmpty {
            return "\(result.action.displayName)完成：\(result.successCount)/\(participantCount)"
        }
        let failedNames = result.failures.map(\.studentName).joined(separator: "、")
        return "\(result.action.displayName)完成：成功\(result.successCount)，失败\(result.failures.count)（\(failedNames)）"
    }

    private func canRetry(_ job: TeachingCourseJobSnapshot) -> Bool {
        guard let action = job.action else { return false }
        guard !job.failedStudentNames.isEmpty else { return false }
        let availableNames = Set(students.map(\.name))
        let hasAny = job.failedStudentNames.contains(where: { availableNames.contains($0) })
        switch action {
        case .prepareAllStudents, .exportAllPDF, .checkConsistency:
            return hasAny
        case .stressTest:
            return false
        }
    }

    private func retryJob(_ job: TeachingCourseJobSnapshot) {
        guard let action = job.action else { return }
        let failedSet = Set(job.failedStudentNames)
        let targets = students.filter { failedSet.contains($0.name) }
        guard !targets.isEmpty else {
            statusMessage = "重试失败：未找到可重试的学生。"
            return
        }
        switch action {
        case .prepareAllStudents:
            runPrepare(targets)
        case .exportAllPDF:
            runExport(targets)
        case .checkConsistency:
            runCheckConsistency(targets)
        case .stressTest:
            runStressTestAllStudents()
        }
    }

    private func runPrepare(_ targetStudents: [TeachingStudentItem]) {
        runAction(.prepareAllStudents, targetStudents: targetStudents) { jobID in
            try await TeachingCourseSyncService.prepareAllStudents(students: targetStudents) { snapshot in
                await MainActor.run {
                    progress = snapshot
                }
                await TeachingCourseJobCenter.shared.updateProgress(
                    jobID,
                    completedUnits: snapshot.completedStudents,
                    totalUnits: snapshot.totalStudents,
                    message: "\(snapshot.action.displayName) · \(snapshot.completedStudents)/\(snapshot.totalStudents)",
                    currentStudentName: snapshot.currentStudentName,
                    currentFilePath: snapshot.currentFilePath
                )
            }
        }
    }

    private func runExport(_ targetStudents: [TeachingStudentItem]) {
        runAction(.exportAllPDF, targetStudents: targetStudents) { jobID in
            try await TeachingCourseSyncService.exportAllStudentsPDF(students: targetStudents) { snapshot in
                await MainActor.run {
                    progress = snapshot
                }
                await TeachingCourseJobCenter.shared.updateProgress(
                    jobID,
                    completedUnits: snapshot.completedStudents,
                    totalUnits: snapshot.totalStudents,
                    message: "\(snapshot.action.displayName) · \(snapshot.completedStudents)/\(snapshot.totalStudents)",
                    currentStudentName: snapshot.currentStudentName,
                    currentFilePath: snapshot.currentFilePath
                )
            }
        }
    }

    private func runCheckConsistency(_ targetStudents: [TeachingStudentItem]) {
        runAction(.checkConsistency, targetStudents: targetStudents) { jobID in
            try await TeachingCourseSyncService.checkAllStudentsConsistency(students: targetStudents) { snapshot in
                await MainActor.run {
                    progress = snapshot
                }
                await TeachingCourseJobCenter.shared.updateProgress(
                    jobID,
                    completedUnits: snapshot.completedStudents,
                    totalUnits: snapshot.totalStudents,
                    message: "\(snapshot.action.displayName) · \(snapshot.completedStudents)/\(snapshot.totalStudents)",
                    currentStudentName: snapshot.currentStudentName,
                    currentFilePath: snapshot.currentFilePath
                )
            }
        }
    }

    private func runStressTestAllStudents() {
        let rounds = stressRounds
        let repeatedTargets = Array(repeating: students, count: rounds).flatMap { $0 }
        runAction(.stressTest, targetStudents: repeatedTargets) { jobID in
            try await TeachingCourseSyncService.stressTestAllStudents(students: students, rounds: rounds) { snapshot in
                await MainActor.run {
                    progress = snapshot
                }
                await TeachingCourseJobCenter.shared.updateProgress(
                    jobID,
                    completedUnits: snapshot.completedStudents,
                    totalUnits: snapshot.totalStudents,
                    message: "\(snapshot.action.displayName) · \(snapshot.completedStudents)/\(snapshot.totalStudents)",
                    currentStudentName: snapshot.currentStudentName,
                    currentFilePath: snapshot.currentFilePath
                )
            }
        }
    }

    private func canShowConsistencyDetails(_ job: TeachingCourseJobSnapshot) -> Bool {
        guard job.action == .checkConsistency else { return false }
        return !job.consistencyReportsByStudent.isEmpty
    }

    private func canRepairConsistency(_ job: TeachingCourseJobSnapshot) -> Bool {
        guard job.action == .checkConsistency else { return false }
        guard !job.failedStudentNames.isEmpty else { return false }
        return !job.consistencyReportsByStudent.isEmpty
    }

    private func openConsistencyDetails(_ job: TeachingCourseJobSnapshot) {
        consistencyReports = job.consistencyReportsByStudent
        showConsistencyReportSheet = true
    }

    private func repairAndRetryConsistency(_ job: TeachingCourseJobSnapshot) {
        let failedSet = Set(job.failedStudentNames)
        let targets = students.filter { failedSet.contains($0.name) }
        guard !targets.isEmpty else {
            statusMessage = "修复失败：未找到可修复学生。"
            return
        }
        repairConsistencyAndOptionallyRetry(targetStudents: targets, retryAfterRepair: true)
    }

    private func repairConsistencyAndOptionallyRetry(
        targetStudents: [TeachingStudentItem],
        retryAfterRepair: Bool
    ) {
        guard !isRunning else { return }
        guard !targetStudents.isEmpty else { return }
        isRepairingConsistency = true
        statusMessage = "正在修复一致性问题（\(repairStrategy.displayName)）..."
        Task(priority: .userInitiated) {
            let result: TeachingCourseConsistencyBulkFixResult
            do {
                result = try TeachingCourseWorkflowService.fixConsistencyForStudents(
                    students: targetStudents,
                    reportsByStudent: consistencyReports,
                    strategy: repairStrategy
                )
            } catch {
                await MainActor.run {
                    isRepairingConsistency = false
                    statusMessage = "修复失败：\(error.localizedDescription)"
                }
                return
            }
            await MainActor.run {
                isRepairingConsistency = false
                consistencyReports.merge(result.reportsByStudent) { _, new in new }
                statusMessage = "修复完成：修复\(result.summary.fixedIssueCount) 跳过\(result.summary.skippedIssueCount)"
                runCheckConsistency(targetStudents)
            }
        }
    }

    private func rollbackLatestRepairBatch() {
        guard !isRunning else { return }
        guard !isRepairingConsistency else { return }
        isRepairingConsistency = true
        statusMessage = "正在回滚最近一次修复..."
        Task(priority: .userInitiated) {
            do {
                let summary = try TeachingCourseWorkflowService.rollbackLatestConsistencyRepairBatch()
                await MainActor.run {
                    isRepairingConsistency = false
                    if summary.rolledBackStudentCount > 0 {
                        statusMessage = "回滚完成：恢复\(summary.rolledBackStudentCount)名学生"
                        runCheckConsistencyAllStudents()
                    } else {
                        statusMessage = "没有可回滚的修复批次。"
                    }
                }
            } catch {
                await MainActor.run {
                    isRepairingConsistency = false
                    statusMessage = "回滚失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func reloadJobHistory() async {
        let snapshots = await TeachingCourseJobCenter.shared.latestSnapshots(limit: 20)
        await MainActor.run {
            jobHistory = snapshots
        }
    }

    private func stateText(_ state: TeachingCourseJobSnapshot.State) -> String {
        switch state {
        case .pending:
            return "等待"
        case .running:
            return "执行中"
        case .succeeded:
            return "成功"
        case .failed:
            return "失败"
        case .cancelled:
            return "取消"
        }
    }

    private func stateColor(_ state: TeachingCourseJobSnapshot.State) -> Color {
        switch state {
        case .pending:
            return .secondary
        case .running:
            return .blue
        case .succeeded:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }

    private func timeText(_ job: TeachingCourseJobSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: job.finishedAt ?? job.startedAt)
    }

    private func runPrepareAllStudents() {
        runPrepare(students)
    }

    private func runExportAllPDF() {
        runExport(students)
    }

    private func runCheckConsistencyAllStudents() {
        runCheckConsistency(students)
    }

    private func runCommercialReadinessCheck() {
        guard !isRunning else { return }
        statusMessage = "正在执行商用验收..."
        Task(priority: .utility) {
            let jobID = await TeachingCourseJobCenter.shared.createJob(
                title: "商用验收",
                action: nil,
                totalUnits: 1
            )
            await TeachingCourseJobCenter.shared.markRunning(jobID, message: "验收启动")
            do {
                let report = try TeachingCommercialReadinessVerifier.run(students: students)
                if report.isPassed {
                    await TeachingCourseJobCenter.shared.markSucceeded(
                        jobID,
                        message: "验收通过：检查\(report.totalChecks)，警告\(report.warningCount)"
                    )
                } else {
                    await TeachingCourseJobCenter.shared.markFailed(
                        jobID,
                        message: "验收失败：错误\(report.errorCount)，警告\(report.warningCount)"
                    )
                }
                await TeachingCourseJobCenter.shared.attachReadinessReport(jobID, report: report)
                await MainActor.run {
                    readinessReport = report
                    showReadinessReportSheet = true
                    if report.isPassed {
                        statusMessage = "验收通过：检查\(report.totalChecks)，警告\(report.warningCount)"
                    } else {
                        statusMessage = "验收失败：错误\(report.errorCount)，警告\(report.warningCount)"
                    }
                }
                await reloadJobHistory()
            } catch {
                await TeachingCourseJobCenter.shared.markFailed(
                    jobID,
                    message: "验收执行失败：\(error.localizedDescription)"
                )
                await MainActor.run {
                    statusMessage = "验收执行失败：\(error.localizedDescription)"
                }
                await reloadJobHistory()
            }
        }
    }

    private var readinessReportSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text(readinessReport.isPassed ? "验收通过" : "验收未通过")
                    .font(.headline)
                Text("检查项：\(readinessReport.totalChecks)  警告：\(readinessReport.warningCount)  错误：\(readinessReport.errorCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if readinessReport.messages.isEmpty {
                    ContentUnavailableView("暂无验收输出", systemImage: "checkmark.shield")
                } else {
                    List(readinessReport.messages, id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                    }
                    .listStyle(.plain)
                }
            }
            .padding(12)
            .navigationTitle("商用验收")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") {
                        showReadinessReportSheet = false
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("一键修复") {
                        runReadinessRepair()
                    }
                }
            }
        }
    }

    private var auditSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("关键字（学生名/文件名）", text: $auditKeyword)
                        .textFieldStyle(.roundedBorder)
                    Button("检索") {
                        reloadAuditLogs()
                    }
                    .appGlassButtonStyle()
                }

                if auditItems.isEmpty {
                    ContentUnavailableView("暂无审计记录", systemImage: "doc.text.magnifyingglass")
                } else {
                    List(auditItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("[\(auditSourceText(item.source))] \(item.summary)")
                                .font(.caption.weight(.semibold))
                            Text(item.rawLine)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .padding(12)
            .navigationTitle("审计检索")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") {
                        showAuditSheet = false
                    }
                }
            }
        }
    }

    private func auditSourceText(_ source: TeachingCourseAuditLogItem.Source) -> String {
        switch source {
        case .transaction:
            return "事务"
        case .conflict:
            return "冲突"
        case .exportSignature:
            return "签名"
        }
    }

    private func runReadinessRepair() {
        guard !isRunning else { return }
        statusMessage = "正在修复验收问题..."
        Task(priority: .utility) {
            do {
                let messages = try TeachingCommercialReadinessVerifier.repair(students: students)
                let report = try TeachingCommercialReadinessVerifier.run(students: students)
                await MainActor.run {
                    readinessReport = report
                    statusMessage = "修复完成：\(messages.joined(separator: "；"))"
                }
            } catch {
                await MainActor.run {
                    statusMessage = "修复失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func reloadAuditLogs() {
        Task(priority: .utility) {
            do {
                let items = try TeachingCourseWorkflowService.searchAuditLogs(keyword: auditKeyword, limit: 180)
                await MainActor.run {
                    auditItems = items
                }
            } catch {
                await MainActor.run {
                    statusMessage = "审计检索失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private var consistencyReportSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                if consistencyReports.isEmpty {
                    ContentUnavailableView("暂无巡检详情", systemImage: "checklist")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(consistencyReports.keys.sorted(), id: \.self) { studentName in
                                let summary = consistencyReports[studentName] ?? TeachingCourseConsistencySummary(checkedItemCount: 0, issueItems: [])
                                DisclosureGroup {
                                    VStack(alignment: .leading, spacing: 6) {
                                        if summary.issueItems.isEmpty {
                                            Text("未发现问题")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            ForEach(summary.issueItems) { issue in
                                                Text("• \(issue.message)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        if !summary.issueItems.isEmpty {
                                            Button {
                                                let target = students.filter { $0.name == studentName }
                                                repairConsistencyAndOptionallyRetry(targetStudents: target, retryAfterRepair: false)
                                            } label: {
                                                Label("修复该学生", systemImage: "wrench.adjustable")
                                            }
                                            .appGlassButtonStyle()
                                            .disabled(isRunning || isRepairingConsistency)
                                        }
                                    }
                                    .padding(.top, 6)
                                } label: {
                                    HStack {
                                        Text(studentName)
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(summary.issueItems.isEmpty ? "健康" : "问题\(summary.issueItems.count)")
                                            .font(.caption2)
                                            .foregroundStyle(summary.issueItems.isEmpty ? .green : .orange)
                                    }
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.secondary.opacity(0.08))
                                )
                            }
                        }
                    }
                }
            }
            .padding(12)
            .navigationTitle("巡检详情")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        showConsistencyReportSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("修复全部可修复项") {
                        repairConsistencyAndOptionallyRetry(targetStudents: students, retryAfterRepair: false)
                    }
                    .disabled(isRunning || isRepairingConsistency || consistencyReports.isEmpty)
                }
            }
        }
    }
}
