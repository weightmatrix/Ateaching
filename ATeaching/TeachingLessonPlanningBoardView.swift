import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - 排课/周表面板 - v1 - 独立JSON、选学生、插入、复制导出和修改

/// 排课页：按月维护未来课表，并在进入时把当前时刻之前的排课转为正式上课单历史记录。
struct TeachingLessonPlanningView: View {
    var students: [TeachingStudentItem]
    var institutions: [TeachingInstitutionRecord]
    var lessonRecords: [TeachingLessonRecord]
    var onLessonHistoryChanged: () -> Void

    var body: some View {
        TeachingLessonPlanningBoardView(
            kind: .planning,
            students: students,
            institutions: institutions,
            lessonRecords: lessonRecords,
            onLessonHistoryChanged: onLessonHistoryChanged
        )
    }
}

/// 周表页：只维护一周模板，插入课表时可由排课页按周拷贝。
struct TeachingLessonWeeklyTemplateView: View {
    var students: [TeachingStudentItem]
    var institutions: [TeachingInstitutionRecord]
    var lessonRecords: [TeachingLessonRecord]
    var onLessonHistoryChanged: () -> Void

    var body: some View {
        TeachingLessonPlanningBoardView(
            kind: .weekly,
            students: students,
            institutions: institutions,
            lessonRecords: lessonRecords,
            onLessonHistoryChanged: onLessonHistoryChanged
        )
    }
}

private struct TeachingLessonPlanningBoardView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    enum BoardKind {
        case planning
        case weekly

        var title: String {
            switch self {
            case .planning: return "排课"
            case .weekly: return "周表"
            }
        }

        var storeKind: TeachingLessonPlanningStore.PlanningKind {
            switch self {
            case .planning: return .planning
            case .weekly: return .weekly
            }
        }

        var usesMonth: Bool {
            self == .planning
        }
    }

    let kind: BoardKind
    let students: [TeachingStudentItem]
    let institutions: [TeachingInstitutionRecord]
    let lessonRecords: [TeachingLessonRecord]
    let onLessonHistoryChanged: () -> Void

    @State private var records: [TeachingLessonRecord] = []
    @State private var displayedMonth = Date()
    @State private var selectedStudentID: UUID?
    @State private var editingRecord: TeachingLessonRecord?
    @State private var showInsertWeeklyConfirmation = false
    @State private var pendingWeeklyInsertStart: Date?
    @State private var showWeekAvailabilityExporter = false
    @State private var showStudentPicker = false
    @State private var statusMessage = ""
    @State private var copiedLessonRecord: TeachingLessonRecord?
    @State private var undoStack: [[TeachingLessonRecord]] = []
    @State private var redoStack: [[TeachingLessonRecord]] = []
    @State private var presentedStudentDocument: PlanningStudentDocument?
    @AppStorage("TeachingLessonPlanningDisplayedMonth") private var persistedPlanningMonth = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            schedulePreview
                .layoutPriority(1)
            recordList
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            load()
        }
        .sheet(item: $editingRecord) { record in
            TeachingLessonEditorSheet(lesson: record, students: students) { draft in
                saveEditedRecord(draft)
            }
        }
        .sheet(isPresented: $showWeekAvailabilityExporter) {
            weekAvailabilityExportSheet
        }
        .sheet(item: $presentedStudentDocument) { item in
            NavigationStack {
                SingleListDocumentEditorView(
                    fileURL: item.fileURL,
                    onClose: { presentedStudentDocument = nil }
                )
            }
            .singleListAdaptivePresentation()
        }
        .alert("插入周表", isPresented: $showInsertWeeklyConfirmation) {
            Button("取消", role: .cancel) {
                pendingWeeklyInsertStart = nil
            }
            Button("插入") {
                insertWeeklyTemplateIntoDisplayedWeek(startingAt: pendingWeeklyInsertStart)
                pendingWeeklyInsertStart = nil
            }
        } message: {
            Text("把周表插入当前展示周？和现有排课冲突的课程会自动跳过。")
        }
        .background(TeachingLessonKeyboardShortcutView(onUndo: undoChange, onRedo: redoChange))
    }

    @ViewBuilder
    private var header: some View {
        if usesCompactLayout {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    monthNavigation
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    exportControl(iconOnly: true)
                    studentPickerControl
                }
            }
        } else {
            HStack(spacing: 8) {
                monthNavigation
                Spacer()
                exportControl(iconOnly: false)
                studentPickerControl
            }
        }
    }

    @ViewBuilder
    private var monthNavigation: some View {
        if kind.usesMonth {
            Button {
                setDisplayedMonth(Calendar.current.date(byAdding: .month, value: -1, to: monthStart(displayedMonth)) ?? displayedMonth)
            } label: {
                Image(systemName: "chevron.left")
            }
            .appGlassButtonStyle()

            Text(TeachingLessonScheduleBuilder.monthTitle(for: displayedMonth))
                .font(.system(size: 15, weight: .semibold))
                .frame(minWidth: usesCompactLayout ? 96 : 120)
                .onTapGesture(count: 2) {
                    setDisplayedMonth(Date())
                }

            Button {
                setDisplayedMonth(Calendar.current.date(byAdding: .month, value: 1, to: monthStart(displayedMonth)) ?? displayedMonth)
            } label: {
                Image(systemName: "chevron.right")
            }
            .appGlassButtonStyle()
        } else {
            Text("一周模板")
                .font(.system(size: 15, weight: .semibold))
        }
    }

    @ViewBuilder
    private func exportControl(iconOnly: Bool) -> some View {
        if kind == .planning {
            Menu {
                Button("导出月排课") {
                    exportImage(title: TeachingLessonScheduleBuilder.monthTitle(for: displayedMonth), filter: .all)
                }
                Button("导出月可用") {
                    exportAllAvailability(title: "\(TeachingLessonScheduleBuilder.monthTitle(for: displayedMonth))月可用", interval: visibleInterval, horizontalMonth: true)
                }
                Button("导出周可用") {
                    showWeekAvailabilityExporter = true
                }
            } label: {
                if iconOnly {
                    Image(systemName: "square.and.arrow.up")
                } else {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
            }
            .appGlassButtonStyle()
            .accessibilityLabel("导出排课")
        } else {
            Button {
                exportImage(title: "周课程表", filter: .all)
            } label: {
                if iconOnly {
                    Image(systemName: "square.and.arrow.up")
                } else {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
            }
            .appGlassButtonStyle()
            .accessibilityLabel("导出周表")
        }
    }

    @ViewBuilder
    private var studentPickerControl: some View {
        #if os(iOS)
        studentPickerButton
            .sheet(isPresented: $showStudentPicker) {
                NavigationStack {
                    studentPickerPanel
                        .navigationTitle("选择学生")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { showStudentPicker = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        #else
        studentPickerButton
            .popover(isPresented: $showStudentPicker, arrowEdge: .bottom) {
                studentPickerPanel
                    .frame(width: 320, height: 420)
                    .padding(12)
            }
        #endif
    }

    private var studentPickerButton: some View {
        Button {
            showStudentPicker = true
        } label: {
            if let option = selectedStudentOption {
                PlanningStudentCapsule(option: option, isSelected: true)
            } else {
                Label("选学生", systemImage: "person.crop.circle.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .appGlassButtonStyle()
        .frame(maxWidth: usesCompactLayout ? .infinity : 240)
    }

    private var studentPickerPanel: some View {
        PlanningStudentPickerPanel(
            options: studentOptions,
            selectedID: selectedStudentOption?.id
        ) { option in
            selectedStudentID = option.id
            showStudentPicker = false
        }
        .padding(usesCompactLayout ? 12 : 0)
    }

    private var usesCompactLayout: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private var schedulePreview: some View {
        if kind == .planning {
            return AnyView(
                ScrollView([.horizontal, .vertical]) {
                    interactiveSchedule(
                        title: "",
                        interval: visibleInterval,
                        records: visibleRecords,
                        fixedDayWidth: 61.7,
                        showsTitle: false
                    )
                    .frame(width: horizontalMonthWidth, height: interactiveScheduleHeight)
                }
                .frame(maxWidth: .infinity)
                .frame(
                    minHeight: 120,
                    idealHeight: usesCompactLayout ? 280 : interactiveScheduleHeight,
                    maxHeight: usesCompactLayout ? 280 : interactiveScheduleHeight
                )
            )
        }
        return AnyView(
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleWeekIntervals, id: \.start) { weekInterval in
                        interactiveSchedule(
                            title: weekTitle(for: weekInterval.start),
                            interval: weekInterval,
                            records: recordsForWeek(weekInterval),
                            fixedDayWidth: nil,
                            showsTitle: true
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(
                minHeight: 120,
                idealHeight: usesCompactLayout ? 280 : interactiveScheduleHeight,
                maxHeight: usesCompactLayout ? 280 : interactiveScheduleHeight
            )
        )
    }

    private var recordList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if kind == .planning || kind == .weekly {
                    planningMonthlySummaryRow
                }
                ForEach(visibleRecords) { record in
                    recordRow(record)
                }
            }
        }
        .frame(maxHeight: usesCompactLayout ? 120 : 220)
    }

    private var planningMonthlySummaryRow: some View {
        let summary = planningMonthlySummary
        return Text("月预计课时量：\(formatHours(summary.hours))；月预计收入：\(formatMoney(summary.fee))")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }

    private var weekAvailabilityExportSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择导出的周")
                .font(.headline)
            ForEach(visibleWeekIntervals, id: \.start) { interval in
                Button(weekTitle(for: interval.start)) {
                    exportAllAvailability(
                        title: "\(weekTitle(for: interval.start))周可用",
                        interval: interval,
                        horizontalMonth: false
                    )
                    showWeekAvailabilityExporter = false
                }
                .appGlassButtonStyle()
            }
        }
        .padding(18)
        .frame(minWidth: 280)
    }

    private var horizontalMonthWidth: CGFloat {
        let days = Calendar.current.dateComponents([.day], from: visibleInterval.start, to: visibleInterval.end).day ?? 31
        return 34 + CGFloat(days) * 61.7 + CGFloat(max(0, days - 1)) * 6 + 24
    }

    private var interactiveScheduleHeight: CGFloat {
        30 + CGFloat(24 - 8) * 36.7 + 24
    }

    private func interactiveSchedule(
        title: String,
        interval: DateInterval,
        records: [TeachingLessonRecord],
        fixedDayWidth: CGFloat?,
        showsTitle: Bool
    ) -> some View {
        TeachingPlanningInteractiveWeekView(
            title: title,
            interval: interval,
            visibleInterval: visibleInterval,
            records: records,
            lockedBefore: planningLockDate,
            fixedDayWidth: fixedDayWidth,
            showsTitle: showsTitle,
            canInsertWeeklyTemplate: kind == .planning,
            onInsertWeeklyTemplate: {
                pendingWeeklyInsertStart = interval.start
                showInsertWeeklyConfirmation = true
            },
            onInsertLesson: { day, hour in
                insertLesson(day: day, hour: hour)
            },
            onMoveLesson: { record, dayDelta, hourDelta in
                moveLesson(record, dayDelta: dayDelta, hourDelta: hourDelta)
            },
            onShiftLesson: { record, minutes in
                shiftLesson(record, minutes: minutes)
            },
            onEditLesson: { record in
                guard !isLocked(record) else { return }
                editingRecord = record
            },
            onCopyStudent: { record in
                copyText(
                    scope: .student(
                        institutionName: record.institutionName.isEmpty ? "未命名机构" : record.institutionName,
                        studentName: record.studentName.isEmpty ? "未命名学生" : record.studentName
                    ),
                    filter: record.studentID.map { .student($0) } ?? .all,
                    groupByStudent: false
                )
            },
            onExportStudent: { record in
                exportImage(
                    title: scopeTitle(prefix: record.studentName, weeklySuffix: "学生当周", monthlySuffix: "学生当月"),
                    filter: record.studentID.map { .student($0) } ?? .all
                )
            },
            onCopyInstitution: { record in
                copyText(
                    scope: .institution(institutionName: record.institutionName.isEmpty ? "未命名机构" : record.institutionName),
                    filter: record.institutionID.map { .institution($0) } ?? .all,
                    groupByStudent: true
                )
            },
            onExportInstitution: { record in
                exportImage(
                    title: scopeTitle(prefix: record.institutionName, weeklySuffix: "机构当周", monthlySuffix: "机构当月"),
                    filter: record.institutionID.map { .institution($0) } ?? .all
                )
            },
            onExportInstitutionAvailability: { record in
                exportImage(
                    title: scopeTitle(prefix: record.institutionName, weeklySuffix: "机构可用当周", monthlySuffix: "机构可用当月"),
                    filter: record.institutionID.map { .institution($0) } ?? .all,
                    availabilityForInstitutionID: record.institutionID
                )
            },
            onCopyLesson: { record in
                copiedLessonRecord = record
                statusMessage = "已复制课程。"
            },
            onPasteLesson: { day, hour in
                pasteLesson(on: day, hour: hour)
            },
            onOpenStudentInfo: { record in
                openStudentDocument(for: record, kind: .information)
            },
            onOpenClassInfo: { record in
                openStudentDocument(for: record, kind: .classInfo)
            },
            onDeleteLesson: { record in
                deleteRecord(record)
            }
        )
    }

    private func recordRow(_ record: TeachingLessonRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(statisticsColor(fromHex: record.effectiveInstitutionColorHex))
                .frame(width: 10, height: 10)
                .alignmentGuide(.firstTextBaseline) { context in
                    context[VerticalAlignment.center]
                }
            Text(recordLeadingText(record))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(width: kind == .weekly ? 104 : 118, alignment: .leading)
            Text(record.institutionName.isEmpty ? "未命名机构" : record.institutionName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(record.studentName.isEmpty ? "未命名学生" : record.studentName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(statisticsColor(fromHex: record.effectiveInstitutionColorHex).opacity(0.14))
        )
        .contextMenu {
            Button(kind == .weekly ? "复制文本·学生·当周" : "复制文本·学生·当月") {
                copyText(
                    scope: .student(
                        institutionName: record.institutionName.isEmpty ? "未命名机构" : record.institutionName,
                        studentName: record.studentName.isEmpty ? "未命名学生" : record.studentName
                    ),
                    filter: record.studentID.map { .student($0) } ?? .all,
                    groupByStudent: false
                )
            }
            Button(kind == .weekly ? "复制文本·机构·当周" : "复制文本·机构·当月") {
                copyText(
                    scope: .institution(institutionName: record.institutionName.isEmpty ? "未命名机构" : record.institutionName),
                    filter: record.institutionID.map { .institution($0) } ?? .all,
                    groupByStudent: true
                )
            }
            Button(kind == .weekly ? "导出图片·学生·当周" : "导出图片·学生·当月") {
                exportImage(
                    title: scopeTitle(prefix: record.studentName, weeklySuffix: "学生当周", monthlySuffix: "学生当月"),
                    filter: record.studentID.map { .student($0) } ?? .all
                )
            }
            Button(kind == .weekly ? "导出图片·机构·当周" : "导出图片·机构·当月") {
                exportImage(
                    title: scopeTitle(prefix: record.institutionName, weeklySuffix: "机构当周", monthlySuffix: "机构当月"),
                    filter: record.institutionID.map { .institution($0) } ?? .all
                )
            }
            Button(kind == .weekly ? "导出图片·机构·周可用" : "导出图片·机构·月可用") {
                exportImage(
                    title: scopeTitle(prefix: record.institutionName, weeklySuffix: "机构可用当周", monthlySuffix: "机构可用当月"),
                    filter: record.institutionID.map { .institution($0) } ?? .all,
                    availabilityForInstitutionID: record.institutionID
                )
            }
            Button("打开信息") { openStudentDocument(for: record, kind: .information) }
            Button("打开课反") { openStudentDocument(for: record, kind: .classInfo) }
            Button("后退半小时") { shiftLesson(record, minutes: -30) }
                .disabled(isLocked(record))
            Button("前进半小时") { shiftLesson(record, minutes: 30) }
                .disabled(isLocked(record))
            Button("修改") {
                if !isLocked(record) {
                    editingRecord = record
                }
            }
            Button("删除", role: .destructive) {
                deleteRecord(record)
            }
        }
    }

    private func openStudentDocument(for record: TeachingLessonRecord, kind: PlanningStudentDocument.Kind) {
        do {
            guard let studentID = record.studentID,
                  let student = students.first(where: { $0.id == studentID }) else {
                statusMessage = "找不到该课程对应的学生。"
                return
            }
            let url: URL
            switch kind {
            case .information:
                let defaults = try TeachingStudentSettingsStore.loadStudentSystemSettings()
                let profile = try TeachingStudentSettingsStore.loadStudentProfile(studentID: student.id)
                try TeachingStudentProvisioningService.provisionArchiveSkeleton(
                    for: student,
                    defaultSettings: defaults,
                    profileOverride: profile
                )
                url = try TeachingCourseWorkflowService.studentInfoFileURL(student: student)
            case .classInfo:
                guard let date = TeachingLessonStatisticsStore.date(from: record.startAt) else {
                    statusMessage = "课程日期无效，无法打开课反。"
                    return
                }
                url = try TeachingCourseWorkflowService.classInfoFileURL(student: student, on: date)
            }
            presentedStudentDocument = PlanningStudentDocument(kind: kind, fileURL: url)
        } catch {
            statusMessage = "打开失败：\(error.localizedDescription)"
        }
    }

    private var studentOptions: [PlanningStudentOption] {
        var options: [PlanningStudentOption] = students.compactMap { student -> PlanningStudentOption? in
            guard let profile = try? TeachingStudentSettingsStore.loadStudentProfile(studentID: student.id) else { return nil }
            let stats = profile.lessonStatistics.normalized()
            guard let institutionID = stats.institutionID,
                  let institutionName = stats.institutionName,
                  let price = stats.priceForTwoHours else { return nil }
            let color = institutions.first(where: { $0.id == institutionID })?.effectiveColorHex
                ?? TeachingLessonStatisticsStore.defaultInstitutionColorHex
            let iconName = institutions.first(where: { $0.id == institutionID })?.iconName
            return PlanningStudentOption(
                id: student.id,
                studentID: student.id,
                studentName: student.name,
                institutionID: institutionID,
                institutionName: institutionName,
                priceForTwoHours: price,
                colorHex: color,
                iconName: iconName
            )
        }
        .sorted { $0.studentName.localizedCaseInsensitiveCompare($1.studentName) == .orderedAscending }
        options.append(PlanningStudentOption.placeholder)
        return options
    }

    private var selectedStudentOption: PlanningStudentOption? {
        if let selectedStudentID,
           let option = studentOptions.first(where: { $0.id == selectedStudentID }) {
            return option
        }
        return studentOptions.first
    }

    private var visibleInterval: DateInterval {
        if kind.usesMonth {
            return TeachingLessonScheduleBuilder.monthInterval(for: displayedMonth)
        }
        return TeachingLessonScheduleBuilder.currentWeekInterval()
    }

    private var visibleRecords: [TeachingLessonRecord] {
        TeachingLessonScheduleBuilder.records(from: displayRecords, in: visibleInterval)
    }

    private var planningMonthlySummary: (hours: Double, fee: Double) {
        visibleRecords.reduce(into: (hours: 0.0, fee: 0.0)) { result, record in
            guard !TeachingLessonPlanningPlaceholder.isPlaceholder(record) else { return }
            guard let start = TeachingLessonStatisticsStore.date(from: record.startAt),
                  let end = TeachingLessonStatisticsStore.date(from: record.endAt),
                  start < end else { return }
            let clippedStart = max(start, visibleInterval.start)
            let clippedEnd = min(end, visibleInterval.end)
            guard clippedStart < clippedEnd else { return }
            let hours = clippedEnd.timeIntervalSince(clippedStart) / 3600
            result.hours += hours
            result.fee += (record.priceForTwoHours ?? 0) * hours / 2
        }
    }

    private var displayRecords: [TeachingLessonRecord] {
        guard kind == .planning, let lockDate = planningLockDate else { return records }
        let history = lessonRecords.filter { record in
            guard let start = TeachingLessonStatisticsStore.date(from: record.startAt) else { return false }
            return start < lockDate
        }
        let currentPlanning = records.filter { record in
            guard let start = TeachingLessonStatisticsStore.date(from: record.startAt) else { return true }
            return start >= lockDate
        }
        return (history + currentPlanning).map(TeachingLessonPlanningPlaceholder.normalizedRecord)
    }

    private var conflictRecords: [TeachingLessonRecord] {
        kind == .planning ? records + lessonRecords : records
    }

    private var planningLockDate: Date? {
        nil
    }

    private var visibleWeekIntervals: [DateInterval] {
        let calendar = Calendar.current
        let firstWeekStart = TeachingLessonScheduleBuilder.weekStart(for: visibleInterval.start)
        if !kind.usesMonth {
            return [TeachingLessonScheduleBuilder.currentWeekInterval()]
        }
        var intervals: [DateInterval] = []
        var cursor = firstWeekStart
        while cursor < visibleInterval.end {
            let end = calendar.date(byAdding: .day, value: 7, to: cursor) ?? cursor
            intervals.append(DateInterval(start: cursor, end: end))
            cursor = end
        }
        return intervals
    }

    private var canMoveToNextMonth: Bool {
        guard let next = Calendar.current.date(byAdding: .month, value: 1, to: monthStart(displayedMonth)) else { return false }
        return next <= monthStart(Date())
    }

    private func load() {
        do {
            if kind == .planning {
                displayedMonth = persistedPlanningDisplayedMonth()
            }
            records = try TeachingLessonPlanningStore.load(kind.storeKind)
            selectedStudentID = selectedStudentID ?? studentOptions.first?.id
            statusMessage = ""
        } catch {
            statusMessage = "\(kind.title)读取失败：\(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try TeachingLessonPlanningStore.save(records, kind: kind.storeKind)
            statusMessage = "\(kind.title)已保存。"
        } catch {
            statusMessage = "\(kind.title)保存失败：\(error.localizedDescription)"
        }
    }

    private func promotePastPlanning() {
        do {
            let moved = try TeachingLessonPlanningStore.promotePastPlanningRecordsToLessonHistory()
            if moved > 0 {
                load()
                onLessonHistoryChanged()
                statusMessage = "已把\(moved)节当前时刻之前的排课转为成课历史。"
            }
        } catch {
            statusMessage = "排课历史转入失败：\(error.localizedDescription)"
        }
    }

    private func insertLesson(day: Date, hour: Int) {
        guard let option = selectedStudentOption else {
            statusMessage = "请先选择有完整统计设置的学生。"
            return
        }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = 0
        components.second = 0
        guard let start = Calendar.current.date(from: components) else { return }
        let end: Date
        if option.isPlaceholder {
            guard let placeholderEnd = placeholderEndDate(start: start) else {
                statusMessage = "空档不足10分钟，无法插入占位|空课。"
                return
            }
            end = placeholderEnd
        } else {
            guard let standardEnd = Calendar.current.date(byAdding: .hour, value: 2, to: start) else { return }
            end = standardEnd
        }
        guard !isPastPlanningDate(start) else {
            statusMessage = "当前时刻之前的排课已锁定，不能新增。"
            return
        }
        guard !TeachingLessonScheduleBuilder.hasConflict(start: start, end: end, in: conflictRecords) else {
            statusMessage = "时间冲突，无法插入。"
            return
        }
        let record = TeachingLessonRecord(
            startAt: TeachingLessonStatisticsStore.makeISO8601String(from: start),
            endAt: TeachingLessonStatisticsStore.makeISO8601String(from: end),
            studentID: option.studentID,
            studentName: option.studentName,
            gradeCode: nil,
            institutionID: option.institutionID,
            institutionName: option.institutionName,
            priceForTwoHours: option.priceForTwoHours,
            institutionColorHex: option.colorHex,
            institutionIconName: option.iconName
        )
        pushUndoSnapshot()
        records.append(record)
        save()
    }

    private func placeholderEndDate(start: Date) -> Date? {
        let calendar = Calendar.current
        let desiredEnd = calendar.date(byAdding: .hour, value: 2, to: start) ?? start.addingTimeInterval(7200)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)) ?? desiredEnd
        let nextBusyStart = conflictRecords.compactMap { record -> Date? in
            guard let busyStart = TeachingLessonStatisticsStore.date(from: record.startAt),
                  let busyEnd = TeachingLessonStatisticsStore.date(from: record.endAt) else { return nil }
            if busyEnd > start && busyStart <= start {
                return start
            }
            return busyStart > start ? busyStart : nil
        }
        .min()
        let end = min(desiredEnd, nextBusyStart ?? desiredEnd, dayEnd)
        return end.timeIntervalSince(start) > 10 * 60 ? end : nil
    }

    private func saveEditedRecord(_ draft: TeachingLessonEditorDraft) {
        guard let source = draft.sourceLesson else { return }
        guard draft.start < draft.end else {
            statusMessage = LessonEditError.invalidTimeRange.localizedDescription
            return
        }
        guard !isLocked(source), !isPastPlanningDate(draft.start) else {
            statusMessage = "当前时刻之前的排课已锁定，不能修改。"
            return
        }
        guard !TeachingLessonScheduleBuilder.hasConflict(start: draft.start, end: draft.end, in: conflictRecords, excluding: source.id) else {
            statusMessage = LessonEditError.conflict.localizedDescription
            return
        }
        var next = source
        next.startAt = TeachingLessonStatisticsStore.makeISO8601String(from: draft.start)
        next.endAt = TeachingLessonStatisticsStore.makeISO8601String(from: draft.end)
        if let index = records.firstIndex(where: { $0.id == source.id }) {
            pushUndoSnapshot()
            records[index] = next
            editingRecord = nil
            save()
        }
    }

    private func insertWeeklyTemplateIntoDisplayedWeek(startingAt explicitWeekStart: Date? = nil) {
        guard kind == .planning else { return }
        do {
            let weekly = try TeachingLessonPlanningStore.load(.weekly)
            let targetWeekStart = explicitWeekStart ?? TeachingLessonScheduleBuilder.weekStart(for: displayedMonth)
            let sourceWeekStart = TeachingLessonScheduleBuilder.weekStart(for: Date())
            var inserted = 0
            for source in weekly {
                guard let sourceStart = TeachingLessonStatisticsStore.date(from: source.startAt),
                      let sourceEnd = TeachingLessonStatisticsStore.date(from: source.endAt) else { continue }
                let dayOffset = Calendar.current.dateComponents([.day], from: sourceWeekStart, to: Calendar.current.startOfDay(for: sourceStart)).day ?? 0
                guard let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: targetWeekStart) else { continue }
                let startComponents = Calendar.current.dateComponents([.hour, .minute], from: sourceStart)
                let endComponents = Calendar.current.dateComponents([.hour, .minute], from: sourceEnd)
                let start = date(on: day, hour: startComponents.hour ?? 0, minute: startComponents.minute ?? 0)
                let end = date(on: day, hour: endComponents.hour ?? 0, minute: endComponents.minute ?? 0)
                guard let start,
                      let end,
                      !isPastPlanningDate(start),
                      !TeachingLessonScheduleBuilder.hasConflict(start: start, end: end, in: conflictRecords) else { continue }
                var next = source
                next.id = UUID()
                next.startAt = TeachingLessonStatisticsStore.makeISO8601String(from: start)
                next.endAt = TeachingLessonStatisticsStore.makeISO8601String(from: end)
                pushUndoSnapshot()
                records.append(next)
                inserted += 1
            }
            save()
            statusMessage = "已插入周表 \(inserted) 节，冲突课程已跳过。"
        } catch {
            statusMessage = "插入周表失败：\(error.localizedDescription)"
        }
    }

    private func recordsForWeek(_ interval: DateInterval) -> [TeachingLessonRecord] {
        TeachingLessonScheduleBuilder.records(from: displayRecords, in: interval)
    }

    private func weekTitle(for weekStart: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(formatter.string(from: weekStart))-\(formatter.string(from: end))"
    }

    private func moveLesson(_ record: TeachingLessonRecord, dayDelta: Int, hourDelta: Int) {
        guard dayDelta != 0 || hourDelta != 0,
              let oldStart = TeachingLessonStatisticsStore.date(from: record.startAt),
              let oldEnd = TeachingLessonStatisticsStore.date(from: record.endAt),
              let shiftedStartByDay = Calendar.current.date(byAdding: .day, value: dayDelta, to: oldStart),
              let shiftedEndByDay = Calendar.current.date(byAdding: .day, value: dayDelta, to: oldEnd),
              let newStart = Calendar.current.date(byAdding: .hour, value: hourDelta, to: shiftedStartByDay),
              let newEnd = Calendar.current.date(byAdding: .hour, value: hourDelta, to: shiftedEndByDay) else {
            return
        }
        guard newStart >= visibleInterval.start, newStart < visibleInterval.end else {
            statusMessage = "移动后超出当前\(kind.title)范围。"
            return
        }
        guard !isLocked(record), !isPastPlanningDate(newStart) else {
            statusMessage = "当前时刻之前的排课已锁定，不能移动。"
            return
        }
        guard !TeachingLessonScheduleBuilder.hasConflict(start: newStart, end: newEnd, in: conflictRecords, excluding: record.id) else {
            statusMessage = "移动失败：时间冲突。"
            return
        }
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        pushUndoSnapshot()
        records[index].startAt = TeachingLessonStatisticsStore.makeISO8601String(from: newStart)
        records[index].endAt = TeachingLessonStatisticsStore.makeISO8601String(from: newEnd)
        save()
    }

    /// 开始和结束时间同步平移，并复用课程拖动的锁定、冲突、撤回与保存规则。
    private func shiftLesson(_ record: TeachingLessonRecord, minutes: Int) {
        guard minutes != 0,
              let oldStart = TeachingLessonStatisticsStore.date(from: record.startAt),
              let oldEnd = TeachingLessonStatisticsStore.date(from: record.endAt),
              let newStart = Calendar.current.date(byAdding: .minute, value: minutes, to: oldStart),
              let newEnd = Calendar.current.date(byAdding: .minute, value: minutes, to: oldEnd) else {
            statusMessage = "课程时间无效，无法移动。"
            return
        }
        guard !isLocked(record), !isPastPlanningDate(newStart) else {
            statusMessage = "当前时刻之前的排课已锁定，不能移动。"
            return
        }
        guard !TeachingLessonScheduleBuilder.hasConflict(
            start: newStart,
            end: newEnd,
            in: conflictRecords,
            excluding: record.id
        ) else {
            statusMessage = "移动失败：时间冲突。"
            return
        }
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        pushUndoSnapshot()
        records[index].startAt = TeachingLessonStatisticsStore.makeISO8601String(from: newStart)
        records[index].endAt = TeachingLessonStatisticsStore.makeISO8601String(from: newEnd)
        save()
        statusMessage = minutes < 0 ? "课程已后退半小时。" : "课程已前进半小时。"
    }

    private func pasteLesson(on day: Date, hour: Int) {
        guard let copiedLessonRecord else {
            statusMessage = "没有可粘贴的课程。"
            return
        }
        guard let sourceStart = TeachingLessonStatisticsStore.date(from: copiedLessonRecord.startAt),
              let sourceEnd = TeachingLessonStatisticsStore.date(from: copiedLessonRecord.endAt) else {
            statusMessage = "粘贴失败：原课程时间无效。"
            return
        }
        let components = Calendar.current.dateComponents([.hour, .minute], from: sourceStart)
        guard let start = date(on: day, hour: components.hour ?? hour, minute: components.minute ?? 0) else { return }
        let end = start.addingTimeInterval(sourceEnd.timeIntervalSince(sourceStart))
        guard !isPastPlanningDate(start) else {
            statusMessage = "当前时刻之前的排课已锁定，不能粘贴。"
            return
        }
        guard !TeachingLessonScheduleBuilder.hasConflict(start: start, end: end, in: conflictRecords) else {
            statusMessage = "粘贴失败：时间冲突。"
            return
        }
        var next = copiedLessonRecord
        next.id = UUID()
        next.startAt = TeachingLessonStatisticsStore.makeISO8601String(from: start)
        next.endAt = TeachingLessonStatisticsStore.makeISO8601String(from: end)
        pushUndoSnapshot()
        records.append(next)
        save()
        statusMessage = "课程已粘贴。"
    }

    private func copyText(scope: TeachingLessonScheduleBuilder.TextScope, filter: TeachingLessonScheduleBuilder.Filter, groupByStudent: Bool) {
        let filtered = TeachingLessonScheduleBuilder.records(from: displayRecords, in: visibleInterval, filter: filter)
        let text = TeachingLessonScheduleBuilder.scopedPlainText(
            scope: scope,
            month: displayedMonth,
            records: filtered,
        )
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        statusMessage = "已复制。"
    }

    @MainActor
    private func exportImage(
        title: String,
        filter: TeachingLessonScheduleBuilder.Filter,
        availabilityForInstitutionID institutionID: UUID? = nil
    ) {
        let source = displayRecords
        let filtered = TeachingLessonScheduleBuilder.records(from: source, in: visibleInterval, filter: filter)
        let occupied = institutionID.map { id in
            TeachingLessonScheduleBuilder.records(from: source, in: visibleInterval).filter { $0.institutionID != id }
        } ?? []
        let pages = exportPages(records: filtered, interval: visibleInterval, occupiedRecords: occupied)
        guard !pages.isEmpty else {
            statusMessage = "没有可导出的课程。"
            return
        }
        let layout = exportLayout(for: visibleInterval)
        let renderer = ImageRenderer(
            content: TeachingScheduleExportSnapshotView(
                monthTitle: title,
                pages: pages,
                layout: layout,
                usesGradientBackground: true
            )
            .frame(width: exportWidth(for: pages, layout: layout))
            .padding(24)
        )
        renderer.scale = 2
        renderer.isOpaque = false
        #if os(macOS)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            statusMessage = "导出失败：无法生成图片。"
            return
        }
        #else
        guard let image = renderer.uiImage, let data = image.pngData() else {
            statusMessage = "导出失败：无法生成图片。"
            return
        }
        #endif
        do {
            let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeFilename(title)).png")
            try TeachingDocumentExportService.exportToWeChat(
                sourceFileURL: sourceURL,
                descriptor: TeachingDocumentExportDescriptor(displayName: title, fileExtension: "png", contentType: .png)
            ) { data }
            statusMessage = "已打开系统导出菜单。"
        } catch {
            statusMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func exportAllAvailability(title: String, interval: DateInterval, horizontalMonth: Bool) {
        let occupied = TeachingLessonScheduleBuilder.records(from: displayRecords, in: interval)
        let pages: [WeeklySchedulePage]
        let layout: TeachingScheduleExportLayout
        if horizontalMonth {
            pages = [TeachingLessonScheduleBuilder.horizontalMonthPage(records: [], interval: interval, occupiedRecords: occupied)]
            layout = .horizontalMonth
        } else {
            pages = TeachingLessonScheduleBuilder.weeklyPages(
                records: [],
                interval: interval,
                includeEmptyWeeks: true,
                occupiedRecords: occupied
            )
            layout = .weeklyTemplate
        }
        exportPages(title: title, pages: pages, layout: layout)
    }

    @MainActor
    private func exportInstitutionWeekAvailability(_ record: TeachingLessonRecord) {
        guard let start = TeachingLessonStatisticsStore.date(from: record.startAt),
              let institutionID = record.institutionID else {
            statusMessage = "无法导出机构周可用：课程缺少时间或机构。"
            return
        }
        let weekStart = TeachingLessonScheduleBuilder.weekStart(for: start)
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let interval = DateInterval(start: weekStart, end: weekEnd)
        let source = displayRecords
        let records = TeachingLessonScheduleBuilder.records(from: source, in: interval, filter: .institution(institutionID))
        let occupied = TeachingLessonScheduleBuilder.records(from: source, in: interval).filter { $0.institutionID != institutionID }
        let pages = TeachingLessonScheduleBuilder.weeklyPages(
            records: records,
            interval: interval,
            includeEmptyWeeks: true,
            occupiedRecords: occupied
        )
        exportPages(title: "\(record.institutionName)\(weekTitle(for: weekStart))机构周可用", pages: pages, layout: .weeklyTemplate)
    }

    @MainActor
    private func exportPages(title: String, pages: [WeeklySchedulePage], layout: TeachingScheduleExportLayout) {
        guard !pages.isEmpty else {
            statusMessage = "没有可导出的课程。"
            return
        }
        let renderer = ImageRenderer(
            content: TeachingScheduleExportSnapshotView(
                monthTitle: title,
                pages: pages,
                layout: layout,
                usesGradientBackground: true
            )
            .frame(width: exportWidth(for: pages, layout: layout))
            .padding(24)
        )
        renderer.scale = 2
        renderer.isOpaque = false
        #if os(macOS)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            statusMessage = "导出失败：无法生成图片。"
            return
        }
        #else
        guard let image = renderer.uiImage, let data = image.pngData() else {
            statusMessage = "导出失败：无法生成图片。"
            return
        }
        #endif
        do {
            let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeFilename(title)).png")
            try TeachingDocumentExportService.exportToWeChat(
                sourceFileURL: sourceURL,
                descriptor: TeachingDocumentExportDescriptor(displayName: title, fileExtension: "png", contentType: .png)
            ) { data }
            statusMessage = "已打开系统导出菜单。"
        } catch {
            statusMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func exportPages(
        records: [TeachingLessonRecord],
        interval: DateInterval,
        occupiedRecords: [TeachingLessonRecord]
    ) -> [WeeklySchedulePage] {
        if kind == .planning {
            return [TeachingLessonScheduleBuilder.horizontalMonthPage(records: records, interval: interval, occupiedRecords: occupiedRecords)]
        }
        return TeachingLessonScheduleBuilder.weeklyPages(
            records: records,
            interval: interval,
            includeEmptyWeeks: true,
            occupiedRecords: occupiedRecords
        )
    }

    private func exportLayout(for interval: DateInterval) -> TeachingScheduleExportLayout {
        kind == .planning ? .horizontalMonth : .weeklyTemplate
    }

    private func exportWidth(for pages: [WeeklySchedulePage], layout: TeachingScheduleExportLayout) -> CGFloat {
        TeachingScheduleExportSizing.width(for: pages, layout: layout)
    }

    private func scopeTitle(prefix: String, weeklySuffix: String, monthlySuffix: String) -> String {
        let name = prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名" : prefix
        if kind == .weekly {
            return "\(name)\(weeklySuffix)"
        }
        return "\(name)\(TeachingLessonScheduleBuilder.monthTitle(for: displayedMonth))\(monthlySuffix)"
    }

    private func safeFilename(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let sanitized = value.components(separatedBy: invalidCharacters).joined(separator: "-")
        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.title : sanitized
    }

    private func setDisplayedMonth(_ date: Date) {
        displayedMonth = monthStart(date)
        if kind == .planning {
            persistedPlanningMonth = TeachingLessonStatisticsStore.makeISO8601String(from: displayedMonth)
        }
    }

    private func persistedPlanningDisplayedMonth() -> Date {
        if let date = TeachingLessonStatisticsStore.date(from: persistedPlanningMonth) {
            return monthStart(date)
        }
        return monthStart(Date())
    }

    private func deleteRecord(_ record: TeachingLessonRecord) {
        guard !isLocked(record) else {
            statusMessage = "当前时刻之前的排课已锁定，不能删除。"
            return
        }
        pushUndoSnapshot()
        records.removeAll { $0.id == record.id }
        save()
    }

    private func pushUndoSnapshot() {
        undoStack.append(records)
        if undoStack.count > 100 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    private func undoChange() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(records)
        records = previous
        save()
        statusMessage = "已撤回。"
    }

    private func redoChange() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(records)
        records = next
        save()
        statusMessage = "已恢复。"
    }

    private func isLocked(_ record: TeachingLessonRecord) -> Bool {
        guard let start = TeachingLessonStatisticsStore.date(from: record.startAt) else { return false }
        return isPastPlanningDate(start)
    }

    private func isPastPlanningDate(_ date: Date) -> Bool {
        guard let lockDate = planningLockDate else { return false }
        return date < lockDate
    }

    private func monthStart(_ date: Date) -> Date {
        TeachingLessonScheduleBuilder.monthStart(for: date)
    }

    private func date(on day: Date, hour: Int, minute: Int) -> Date? {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)
    }

    private func dateText(_ record: TeachingLessonRecord) -> String {
        guard let start = TeachingLessonStatisticsStore.date(from: record.startAt) else { return "日期错误" }
        return kind == .weekly ? shortWeekdayTitle(start) : shortDayTitle(start)
    }

    private func recordLeadingText(_ record: TeachingLessonRecord) -> String {
        if kind == .weekly {
            return "\(dateText(record)) | \(timeText(record))"
        }
        return "\(dateText(record)) \(timeText(record))"
    }

    private func timeText(_ record: TeachingLessonRecord) -> String {
        guard let start = TeachingLessonStatisticsStore.date(from: record.startAt),
              let end = TeachingLessonStatisticsStore.date(from: record.endAt) else { return "--" }
        return TeachingLessonScheduleBuilder.timeRangeText(start: start, end: end)
    }

    private func shortDayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M.d"
        return formatter.string(from: date)
    }

    private func shortWeekdayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private func formatHours(_ hours: Double) -> String {
        hours.rounded() == hours ? String(Int(hours)) : String(format: "%.1f", hours)
    }

    private func formatMoney(_ money: Double) -> String {
        money.rounded() == money ? String(Int(money)) : String(format: "%.1f", money)
    }
}

struct TeachingPlanningInteractiveWeekView: View {
    let title: String
    let interval: DateInterval
    let visibleInterval: DateInterval
    let records: [TeachingLessonRecord]
    let lockedBefore: Date?
    let fixedDayWidth: CGFloat?
    let showsTitle: Bool
    let canInsertWeeklyTemplate: Bool
    let onInsertWeeklyTemplate: () -> Void
    let onInsertLesson: (Date, Int) -> Void
    let onMoveLesson: (TeachingLessonRecord, Int, Int) -> Void
    let onShiftLesson: (TeachingLessonRecord, Int) -> Void
    let onEditLesson: (TeachingLessonRecord) -> Void
    let onCopyStudent: (TeachingLessonRecord) -> Void
    let onExportStudent: (TeachingLessonRecord) -> Void
    let onCopyInstitution: (TeachingLessonRecord) -> Void
    let onExportInstitution: (TeachingLessonRecord) -> Void
    let onExportInstitutionAvailability: (TeachingLessonRecord) -> Void
    let onCopyLesson: (TeachingLessonRecord) -> Void
    let onPasteLesson: (Date, Int) -> Void
    var onOpenStudentInfo: (TeachingLessonRecord) -> Void = { _ in }
    var onOpenClassInfo: (TeachingLessonRecord) -> Void = { _ in }
    let onDeleteLesson: (TeachingLessonRecord) -> Void

    @State private var draggingRecordID: UUID?
    @State private var dragTranslations: [UUID: CGSize] = [:]
    @State private var menuRecord: TeachingLessonRecord?

    private let startHour = 8
    private let endHour = 24
    private let rowHeight: CGFloat = 36.7
    private let headerHeight: CGFloat = 30
    private let axisWidth: CGFloat = 34
    private let columnSpacing: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if canInsertWeeklyTemplate {
                        Button("周") {
                            onInsertWeeklyTemplate()
                        }
                        .appGlassButtonStyle(.prominent)
                    }
                }
            }

            GeometryReader { proxy in
                let totalSpacing = columnSpacing * 6
                let dayWidth = fixedDayWidth ?? max(72, (proxy.size.width - axisWidth - totalSpacing) / 7)
                HStack(alignment: .top, spacing: columnSpacing) {
                    timeAxis
                        .frame(width: axisWidth)
                    ForEach(days, id: \.timeIntervalSince1970) { day in
                        dayColumn(day, width: dayWidth)
                    }
                }
            }
            .frame(height: headerHeight + CGFloat(endHour - startHour) * rowHeight)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private var days: [Date] {
        if fixedDayWidth == nil {
            return (0..<7).compactMap {
                Calendar.current.date(byAdding: .day, value: $0, to: interval.start)
            }
        }
        var result: [Date] = []
        var cursor = Calendar.current.startOfDay(for: interval.start)
        while cursor < interval.end {
            result.append(cursor)
            cursor = Calendar.current.date(byAdding: .day, value: 1, to: cursor) ?? interval.end
        }
        return result
    }

    private var timeAxis: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: headerHeight)
            ForEach(startHour..<endHour, id: \.self) { hour in
                Text("\(hour)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(height: rowHeight, alignment: .topTrailing)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
        }
    }

    private func dayColumn(_ day: Date, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(dayTitle(day))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: headerHeight)
                .foregroundStyle(isDayVisible(day) ? Color.primary : Color.secondary)

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    ForEach(startHour..<endHour, id: \.self) { hour in
                        Rectangle()
                            .fill(hour % 2 == 0 ? Color.primary.opacity(0.025) : Color.clear)
                            .frame(height: rowHeight)
                            .overlay(alignment: .top) {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.16))
                                    .frame(height: 1)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard isDayVisible(day), !isDayLocked(day) else { return }
                                onInsertLesson(day, hour)
                            }
                            .onLongPressGesture(minimumDuration: 0.35) {
                                guard isDayVisible(day), !isDayLocked(day) else { return }
                                onInsertLesson(day, hour)
                            }
                            .contextMenu {
                                Button("粘贴") {
                                    onPasteLesson(day, hour)
                                }
                            }
                    }
                }

                ForEach(recordsForDay(day)) { record in
                    lessonBlock(record, dayWidth: width)
                }
            }
            .frame(height: CGFloat(endHour - startHour) * rowHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
        }
        .frame(width: width)
        .opacity(isDayVisible(day) ? 1 : 0.48)
        .overlay {
            if isDayLocked(day) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.08))
                    .allowsHitTesting(false)
            }
        }
    }

    private func lessonBlock(_ record: TeachingLessonRecord, dayWidth: CGFloat) -> some View {
        let range = clippedHourRange(for: record)
        let top = CGFloat(range.start - Double(startHour)) * rowHeight
        let height = max(18, CGFloat(range.end - range.start) * rowHeight)
        let isDragging = draggingRecordID == record.id
        let locked = isRecordLocked(record)

        return VStack(alignment: .leading, spacing: 2) {
            Text(record.studentName.isEmpty ? "未命名学生" : record.studentName)
                .font(.system(size: 20, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.45)
            Text(record.institutionName.isEmpty ? "未命名机构" : record.institutionName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(exactTimeText(record))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(durationText(record))
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(locked ? Color.secondary : Color.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(width: max(20, dayWidth - 6), height: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(statisticsColor(fromHex: record.effectiveInstitutionColorHex).opacity(locked ? 0.16 : 0.32))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isDragging ? Color.white.opacity(0.9) : statisticsColor(fromHex: record.effectiveInstitutionColorHex).opacity(0.65), lineWidth: isDragging ? 2 : 1)
                )
        )
        .overlay {
            if let iconName = record.institutionIconName, !iconName.isEmpty {
                Image(systemName: iconName)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.primary.opacity(0.14))
                    .frame(width: max(12, (dayWidth - 6) * 0.8), height: max(12, height * 0.8))
                    .allowsHitTesting(false)
            }
        }
        .offset(x: dragTranslations[record.id]?.width ?? 0, y: top + (dragTranslations[record.id]?.height ?? 0))
        .scaleEffect(isDragging ? 1.035 : 1)
        .shadow(color: isDragging ? Color.black.opacity(0.28) : Color.clear, radius: 14, x: 0, y: 8)
        .zIndex(isDragging ? 10 : 0)
        .gesture(
            LongPressGesture(minimumDuration: 0.25)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    if case let .second(true, drag?) = value {
                        draggingRecordID = record.id
                        dragTranslations[record.id] = drag.translation
                    }
                }
                .onEnded { value in
                    draggingRecordID = nil
                    dragTranslations[record.id] = nil
                    guard case let .second(true, drag?) = value else { return }
                    let dayDelta = Int((drag.translation.width / max(1, dayWidth + columnSpacing)).rounded())
                    let hourDelta = Int((drag.translation.height / rowHeight).rounded())
                    onMoveLesson(record, dayDelta, hourDelta)
                },
            including: lessonDragGestureMask
        )
        .onTapGesture {
            menuRecord = record
        }
        .popover(item: $menuRecord) { record in
            lessonActionMenu(for: record)
        }
        .contextMenu {
            lessonActionMenu(for: record)
        }
    }

    @ViewBuilder
    private func lessonActionMenu(for record: TeachingLessonRecord) -> some View {
        let locked = isRecordLocked(record)
        Group {
            Button(canInsertWeeklyTemplate ? "复制文本·学生·当月" : "复制文本·学生·当周") {
                onCopyStudent(record)
            }
            Button(canInsertWeeklyTemplate ? "复制文本·机构·当月" : "复制文本·机构·当周") {
                onCopyInstitution(record)
            }
            Button(canInsertWeeklyTemplate ? "导出图片·学生·当月" : "导出图片·学生·当周") {
                onExportStudent(record)
            }
            Button(canInsertWeeklyTemplate ? "导出图片·机构·当月" : "导出图片·机构·当周") {
                onExportInstitution(record)
            }
            Button(canInsertWeeklyTemplate ? "导出图片·机构·月可用" : "导出图片·机构·周可用") {
                onExportInstitutionAvailability(record)
            }
            Button("打开信息") { onOpenStudentInfo(record) }
            Button("打开课反") { onOpenClassInfo(record) }
            Button("后退半小时") { onShiftLesson(record, -30) }
                .disabled(locked)
            Button("前进半小时") { onShiftLesson(record, 30) }
                .disabled(locked)
            Button("修改") { onEditLesson(record) }
                .disabled(locked)
            Divider()
            Button("删除", role: .destructive) {
                onDeleteLesson(record)
            }
        }
    }

    private var lessonDragGestureMask: GestureMask {
        .all
    }

    private func recordsForDay(_ day: Date) -> [TeachingLessonRecord] {
        let dayStart = Calendar.current.startOfDay(for: day)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return records.filter { record in
            guard let start = TeachingLessonStatisticsStore.date(from: record.startAt),
                  let end = TeachingLessonStatisticsStore.date(from: record.endAt) else {
                return false
            }
            return end > dayStart && start < dayEnd
        }
        .sorted {
            (TeachingLessonStatisticsStore.date(from: $0.startAt) ?? .distantPast)
                < (TeachingLessonStatisticsStore.date(from: $1.startAt) ?? .distantPast)
        }
    }

    private func clippedHourRange(for record: TeachingLessonRecord) -> (start: Double, end: Double) {
        guard let rawStart = TeachingLessonStatisticsStore.date(from: record.startAt),
              let rawEnd = TeachingLessonStatisticsStore.date(from: record.endAt) else {
            return (Double(startHour), Double(startHour + 1))
        }
        let start = min(max(hourValue(rawStart), Double(startHour)), Double(endHour))
        let end = min(max(hourValue(rawEnd, day: rawStart), Double(startHour)), Double(endHour))
        return (start, max(start + 0.25, end))
    }

    private func hourValue(_ date: Date, day: Date? = nil) -> Double {
        if let day,
           Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: day) {
            return 24
        }
        let hour = Double(Calendar.current.component(.hour, from: date))
        let minute = Double(Calendar.current.component(.minute, from: date))
        return hour + minute / 60
    }

    private func isDayVisible(_ day: Date) -> Bool {
        let dayStart = Calendar.current.startOfDay(for: day)
        return dayStart >= Calendar.current.startOfDay(for: visibleInterval.start)
            && dayStart < visibleInterval.end
    }

    private func isDayLocked(_ day: Date) -> Bool {
        guard let lockedBefore else { return false }
        let dayStart = Calendar.current.startOfDay(for: day)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return dayEnd <= lockedBefore
    }

    private func isRecordLocked(_ record: TeachingLessonRecord) -> Bool {
        guard let lockedBefore,
              let start = TeachingLessonStatisticsStore.date(from: record.startAt) else { return false }
        return start < lockedBefore
    }

    private func exactTimeText(_ record: TeachingLessonRecord) -> String {
        guard let start = TeachingLessonStatisticsStore.date(from: record.startAt),
              let end = TeachingLessonStatisticsStore.date(from: record.endAt) else { return "--:--- --:--" }
        return TeachingLessonScheduleBuilder.timeRangeText(start: start, end: end)
    }

    private func durationText(_ record: TeachingLessonRecord) -> String {
        guard let start = TeachingLessonStatisticsStore.date(from: record.startAt),
              let end = TeachingLessonStatisticsStore.date(from: record.endAt) else { return "" }
        let hours = max(0, end.timeIntervalSince(start) / 3600)
        return "\(hours.rounded() == hours ? String(Int(hours)) : String(format: "%.1f", hours))小时"
    }

    private func dayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = fixedDayWidth == nil ? "E M.d" : "d E"
        return formatter.string(from: date)
    }
}

private struct PlanningStudentDocument: Identifiable {
    enum Kind { case information, classInfo }
    let id = UUID()
    let kind: Kind
    let fileURL: URL
    var title: String { kind == .information ? "学生信息" : "课反" }
}

private struct PlanningStudentOption: Identifiable {
    var id: UUID
    var studentID: UUID?
    var studentName: String
    var institutionID: UUID?
    var institutionName: String
    var priceForTwoHours: Double?
    var colorHex: String
    var iconName: String? = nil
    var isPlaceholder = false

    var title: String { "\(studentName)|\(institutionName)" }

    static var placeholder: PlanningStudentOption {
        PlanningStudentOption(
            id: TeachingLessonPlanningPlaceholder.studentID,
            studentID: TeachingLessonPlanningPlaceholder.studentID,
            studentName: TeachingLessonPlanningPlaceholder.studentName,
            institutionID: TeachingLessonPlanningPlaceholder.institutionID,
            institutionName: TeachingLessonPlanningPlaceholder.institutionName,
            priceForTwoHours: nil,
            colorHex: "#4B5563",
            iconName: "calendar.badge.clock",
            isPlaceholder: true
        )
    }
}

private struct PlanningStudentPickerPanel: View {
    let options: [PlanningStudentOption]
    let selectedID: UUID?
    let onSelect: (PlanningStudentOption) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(options) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        PlanningStudentCapsule(option: option, isSelected: option.id == selectedID)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
    }
}

private struct PlanningStudentCapsule: View {
    let option: PlanningStudentOption
    var isSelected = false

    var body: some View {
        Text(option.title)
            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .multilineTextAlignment(.leading)
            .foregroundStyle(option.isPlaceholder ? Color.white.opacity(0.94) : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Capsule(style: .continuous)
                    .fill(capsuleFill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? Color.primary.opacity(0.32) : Color.clear, lineWidth: 1.2)
            )
    }

    private var capsuleFill: Color {
        let base = statisticsColor(fromHex: option.colorHex)
        return option.isPlaceholder ? base.opacity(0.86) : base.opacity(isSelected ? 0.32 : 0.22)
    }
}

struct TeachingLessonKeyboardShortcutView: View {
    let onUndo: () -> Void
    let onRedo: () -> Void

    var body: some View {
        #if os(macOS)
        TeachingLessonKeyboardShortcutRepresentable(onUndo: onUndo, onRedo: onRedo)
            .frame(width: 0, height: 0)
        #else
        EmptyView()
        #endif
    }
}

#if os(macOS)
private struct TeachingLessonKeyboardShortcutRepresentable: NSViewRepresentable {
    let onUndo: () -> Void
    let onRedo: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onUndo = onUndo
        context.coordinator.onRedo = onRedo
    }

    func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onUndo: onUndo, onRedo: onRedo)
    }

    final class Coordinator {
        var onUndo: () -> Void
        var onRedo: () -> Void
        private var monitor: Any?

        init(onUndo: @escaping () -> Void, onRedo: @escaping () -> Void) {
            self.onUndo = onUndo
            self.onRedo = onRedo
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      event.modifierFlags.contains(.command),
                      event.charactersIgnoringModifiers?.lowercased() == "z" else {
                    return event
                }
                if event.modifierFlags.contains(.shift) {
                    self.onRedo()
                } else {
                    self.onUndo()
                }
                return nil
            }
        }

        func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
#endif
