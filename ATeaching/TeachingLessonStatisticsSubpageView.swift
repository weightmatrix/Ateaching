import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 课时统计主页面；只保留顶层状态、三个主面板切换、加载保存和页面级调度。
struct TeachingLessonStatisticsSubpageView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// 统计页顶部的三个子页面模式。
    private enum SectionMode: String, CaseIterable, Identifiable {
        case planning = "排课"
        case schedule = "成课"
        case institutions = "机构"
        case weekly = "周表"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .institutions: return "building.2"
            case .schedule: return "calendar"
            case .planning: return "calendar.badge.plus"
            case .weekly: return "calendar.day.timeline.left"
            }
        }
    }

    @State private var mode: SectionMode = .planning
    @State private var institutions: [TeachingInstitutionRecord] = []
    @State private var lessonRecords: [TeachingLessonRecord] = []
    @State private var students: [TeachingStudentItem] = []
    @State private var displayedMonth = Date()
    @State private var statusMessage = ""
    @State private var showInstitutionEditor = false
    @State private var showLessonEditor = false
    @State private var editingInstitution: TeachingInstitutionRecord?
    @State private var dataInstitution: TeachingInstitutionRecord?
    @State private var editingLesson: TeachingLessonRecord?
    @State private var pendingNewLessonStart: Date?
    @State private var deleteTarget: TeachingInstitutionRecord?
    @State private var deleteImpactedStudents: [TeachingStudentItem] = []
    @State private var lessonDeleteTarget: TeachingLessonRecord?
    @State private var copiedLessonRecord: TeachingLessonRecord?
    @State private var lessonUndoStack: [[TeachingLessonRecord]] = []
    @State private var lessonRedoStack: [[TeachingLessonRecord]] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Group {
                switch mode {
                case .institutions:
                    institutionPanel
                case .schedule:
                    schedulePanel
                case .planning:
                    TeachingLessonPlanningView(students: students, institutions: institutions, lessonRecords: lessonRecords) {
                        loadAllData()
                    }
                case .weekly:
                    TeachingLessonWeeklyTemplateView(students: students, institutions: institutions, lessonRecords: lessonRecords) {
                        loadAllData()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(usesCompactLayout ? 8 : 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .task {
            loadAllData()
        }
        .sheet(isPresented: $showInstitutionEditor) {
            TeachingInstitutionEditorSheet(
                institution: editingInstitution,
                existingInstitutions: institutions,
                onSave: saveInstitution
            )
        }
        .sheet(isPresented: $showLessonEditor) {
            TeachingLessonEditorSheet(
                lesson: editingLesson,
                students: students,
                initialStart: pendingNewLessonStart,
                onSave: saveLesson
            )
        }
        .sheet(item: $dataInstitution) { institution in
            TeachingInstitutionDataSheet(
                institution: institution,
                lessonRecords: lessonRecords
            )
        }
        .alert("删除机构", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("取消", role: .cancel) {
                deleteTarget = nil
            }
            Button("删除", role: .destructive) {
                confirmDeleteInstitution()
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .alert("删除课程", isPresented: Binding(
            get: { lessonDeleteTarget != nil },
            set: { if !$0 { lessonDeleteTarget = nil } }
        )) {
            Button("取消", role: .cancel) {
                lessonDeleteTarget = nil
            }
            Button("删除", role: .destructive) {
                confirmDeleteLesson()
            }
        } message: {
            Text("确定从上课单删除这节课？")
        }
        .background(TeachingLessonKeyboardShortcutView(onUndo: undoLessonChange, onRedo: redoLessonChange))
    }

    @ViewBuilder
    private var header: some View {
        if usesCompactLayout {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("统计")
                        .font(.headline)
                    Spacer()
                    headerActions(iconOnly: true)
                }
                sectionPicker(iconOnly: true)
            }
        } else {
            HStack(spacing: 10) {
                Text("统计")
                    .font(.headline)
                sectionPicker(iconOnly: false)
                    .frame(maxWidth: 360)
                Spacer()
                headerActions(iconOnly: false)
            }
        }
    }

    private func sectionPicker(iconOnly: Bool) -> some View {
        Picker("统计页面", selection: $mode) {
            ForEach(SectionMode.allCases) { item in
                if iconOnly {
                    Text(item.rawValue).tag(item)
                } else {
                    Label(item.rawValue, systemImage: item.systemImage).tag(item)
                }
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func headerActions(iconOnly: Bool) -> some View {
        if mode == .institutions {
            Button {
                editingInstitution = nil
                showInstitutionEditor = true
            } label: {
                compactActionLabel("添加", systemImage: "plus", iconOnly: iconOnly)
            }
            .appGlassButtonStyle(.prominent)
            .accessibilityLabel("添加机构")
        }

        if mode == .schedule {
            Button {
                editingLesson = nil
                pendingNewLessonStart = nil
                showLessonEditor = true
            } label: {
                compactActionLabel("添加", systemImage: "plus", iconOnly: iconOnly)
            }
            .appGlassButtonStyle(.prominent)
            .accessibilityLabel("添加课程")

            Button {
                exportSchedule()
            } label: {
                compactActionLabel("导出", systemImage: "square.and.arrow.up", iconOnly: iconOnly)
            }
            .appGlassButtonStyle()
            .accessibilityLabel("导出成课")
        }

        Button {
            loadAllData()
        } label: {
            compactActionLabel("刷新", systemImage: "arrow.clockwise", iconOnly: iconOnly)
        }
        .appGlassButtonStyle()
        .accessibilityLabel("刷新统计")
    }

    @ViewBuilder
    private func compactActionLabel(_ title: String, systemImage: String, iconOnly: Bool) -> some View {
        if iconOnly {
            Image(systemName: systemImage)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    private var usesCompactLayout: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private var schedulePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            monthControls
            scheduleImageView
                .frame(minHeight: 120, maxHeight: .infinity)
                .layoutPriority(1)
            scheduleTextView
                .frame(maxHeight: usesCompactLayout ? 100 : 180)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var scheduleImageView: some View {
        let records = editableLessonRecords()
        return ScrollView([.horizontal, .vertical]) {
            TeachingPlanningInteractiveWeekView(
                title: "",
                interval: scheduleVisibleInterval,
                visibleInterval: scheduleVisibleInterval,
                records: records,
                lockedBefore: nil,
                fixedDayWidth: 61.7,
                showsTitle: false,
                canInsertWeeklyTemplate: true,
                onInsertWeeklyTemplate: {},
                onInsertLesson: { day, hour in
                    insertScheduleLesson(day: day, hour: hour)
                },
                onMoveLesson: { record, dayDelta, hourDelta in
                    moveScheduleLesson(record, dayDelta: dayDelta, hourDelta: hourDelta)
                },
                onShiftLesson: { record, minutes in
                    shiftScheduleLesson(record, minutes: minutes)
                },
                onEditLesson: { record in
                    editingLesson = record
                    showLessonEditor = true
                },
                onCopyStudent: { record in
                    copyScheduleText(
                        scope: .student(
                            institutionName: record.institutionName.isEmpty ? "未命名机构" : record.institutionName,
                            studentName: record.studentName.isEmpty ? "未命名学生" : record.studentName
                        ),
                        filter: record.studentID.map { .student($0) } ?? .all,
                        groupByStudent: false
                    )
                },
                onExportStudent: { record in
                    exportScheduleImage(
                        title: "\(record.studentName)\(monthTitle(for: displayedMonth))学生当月",
                        filter: record.studentID.map { .student($0) } ?? .all
                    )
                },
                onCopyInstitution: { record in
                    copyScheduleText(
                        scope: .institution(institutionName: record.institutionName.isEmpty ? "未命名机构" : record.institutionName),
                        filter: record.institutionID.map { .institution($0) } ?? .all,
                        groupByStudent: true
                    )
                },
                onExportInstitution: { record in
                    exportScheduleImage(
                        title: "\(record.institutionName)\(monthTitle(for: displayedMonth))机构当月",
                        filter: record.institutionID.map { .institution($0) } ?? .all
                    )
                },
                onExportInstitutionAvailability: { record in
                    exportScheduleImage(
                        title: "\(record.institutionName)\(monthTitle(for: displayedMonth))机构可用当月",
                        filter: record.institutionID.map { .institution($0) } ?? .all,
                        availabilityForInstitutionID: record.institutionID
                    )
                },
                onCopyLesson: { record in
                    copiedLessonRecord = record
                    statusMessage = "已复制课程。"
                },
                onPasteLesson: { day, hour in
                    pasteScheduleLesson(on: day, hour: hour)
                },
                onDeleteLesson: { record in
                    lessonDeleteTarget = record
                }
            )
            .frame(width: scheduleHorizontalMonthWidth, height: scheduleInteractiveHeight)
        }
    }

    private var monthControls: some View {
        HStack(spacing: 8) {
            Button {
                displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: monthStart(for: displayedMonth)) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.left")
            }
            .appGlassButtonStyle()

            Text(monthTitle(for: displayedMonth))
                .font(.system(size: 15, weight: .semibold))
                .frame(minWidth: 120)

            Button {
                displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: monthStart(for: displayedMonth)) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.right")
            }
            .appGlassButtonStyle()
            .disabled(!canMoveToNextMonth(from: displayedMonth))

            Spacer()
        }
    }

    private var scheduleTextView: some View {
        let summary = buildScheduleSummary()
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("该月总钱数")
                        .font(.subheadline.weight(.semibold))
                    Text("\(formatMoney(summary.totalFee))元")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                }

                if summary.institutionSummaries.isEmpty {
                    Text("该月暂无课程记录")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(summary.institutionSummaries) { item in
                            scheduleInstitutionSummaryRow(item)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(summary.days) { day in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(day.title)
                                    .font(.subheadline.weight(.semibold))
                                ForEach(day.lessons) { item in
                                    scheduleLessonRow(item)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func scheduleInstitutionSummaryRow(_ item: InstitutionScheduleSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(item.institutionName);")
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(formatHours(item.hours))小时;")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(width: 96, alignment: .leading)
            Text("\(formatMoney(item.fee))元；")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(width: 96, alignment: .leading)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(statisticsColor(fromHex: item.colorHex).opacity(0.22))
        )
    }

    private func scheduleLessonRow(_ item: LessonDisplayItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.timeText)
                .font(.system(size: 13, design: .monospaced))
                .frame(width: 72, alignment: .leading)
            Text(item.institutionName)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.studentName)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(statisticsColor(fromHex: item.colorHex).opacity(0.16))
        )
    }

    private var institutionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            monthControls
            institutionMonthTotalRow
            TeachingInstitutionListPanel(
                institutions: institutions,
                lessonRecords: lessonRecords,
                displayedMonth: displayedMonth,
                onEdit: { institution in
                    editingInstitution = institution
                    showInstitutionEditor = true
                },
                onDelete: { institution in
                    prepareDeleteInstitution(institution)
                },
                onData: { institution in
                    dataInstitution = institution
                },
                onCopyMonth: { institution, offset in
                    copyInstitutionMonth(institution, monthOffset: offset)
                },
                onExportMonth: { institution, offset in
                    exportInstitutionScheduleImage(institution, monthOffset: offset)
                }
            )
        }
    }

    private var institutionMonthTotalRow: some View {
        let summary = institutionTotalSummary(for: displayedMonth)
        return HStack(spacing: 12) {
            Text("总时长")
                .font(.subheadline.weight(.semibold))
            Text("\(formatHours(summary.hours))小时")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(Color.green.opacity(0.28)))
            Text("总收入")
                .font(.subheadline.weight(.semibold))
            Text("\(formatMoney(summary.fee))元")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(Color.yellow.opacity(0.32)))
            Spacer()
        }
    }

    private func institutionTotalSummary(for month: Date) -> InstitutionMonthSummary {
        let summary = buildScheduleSummary()
        return InstitutionMonthSummary(
            hours: summary.institutionSummaries.reduce(0) { $0 + $1.hours },
            fee: summary.institutionSummaries.reduce(0) { $0 + $1.fee }
        )
    }

    private var sortedInstitutions: [TeachingInstitutionRecord] {
        institutions.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func institutionRow(_ institution: TeachingInstitutionRecord) -> some View {
        let summary = institutionMonthlySummary(for: institution)
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(statisticsColor(fromHex: institution.effectiveColorHex))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(institution.name)
                    .font(.system(size: 15, weight: .medium))
                if !institution.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(institution.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(priceText(institution.defaultPriceForTwoHours))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(institutionMonthSummaryText(label: "本月", summary: summary.currentMonth))
                    Text(institutionMonthSummaryText(label: "上月", summary: summary.previousMonth))
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(statisticsColor(fromHex: institution.effectiveColorHex).opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
        )
        .contextMenu {
            Button("更改") {
                editingInstitution = institution
                showInstitutionEditor = true
            }
            Button("删除", role: .destructive) {
                prepareDeleteInstitution(institution)
            }
            Button("数据") {
                dataInstitution = institution
            }
            Button("复制上月") {
                copyInstitutionMonth(institution, monthOffset: -1)
            }
            Button("复制当月") {
                copyInstitutionMonth(institution, monthOffset: 0)
            }
            Button("导出上月") {
                exportInstitutionScheduleImage(institution, monthOffset: -1)
            }
            Button("导出当月") {
                exportInstitutionScheduleImage(institution, monthOffset: 0)
            }
        }
    }

    private func institutionMonthlySummary(for institution: TeachingInstitutionRecord) -> InstitutionMonthPairSummary {
        let currentStart = monthStart(for: Date())
        let previousStart = Calendar.current.date(byAdding: .month, value: -1, to: currentStart) ?? currentStart
        return InstitutionMonthPairSummary(
            currentMonth: institutionSummary(for: institution, monthStart: currentStart),
            previousMonth: institutionSummary(for: institution, monthStart: previousStart)
        )
    }

    private func institutionSummary(
        for institution: TeachingInstitutionRecord,
        monthStart: Date
    ) -> InstitutionMonthSummary {
        let calendar = Calendar.current
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        var hours = 0.0
        var fee = 0.0

        for record in lessonRecords {
            guard lessonRecord(record, belongsTo: institution),
                  let start = TeachingLessonStatisticsStore.date(from: record.startAt),
                  let end = TeachingLessonStatisticsStore.date(from: record.endAt),
                  start < end,
                  end > monthStart,
                  start < monthEnd else {
                continue
            }

            let clippedStart = max(start, monthStart)
            let clippedEnd = min(end, monthEnd)
            let itemHours = max(0, clippedEnd.timeIntervalSince(clippedStart) / 3600)
            hours += itemHours
            fee += (record.priceForTwoHours ?? 0) * itemHours / 2
        }

        return InstitutionMonthSummary(hours: hours, fee: fee)
    }

    private func lessonRecord(
        _ record: TeachingLessonRecord,
        belongsTo institution: TeachingInstitutionRecord
    ) -> Bool {
        if let recordInstitutionID = record.institutionID {
            return recordInstitutionID == institution.id
        }
        return TeachingLessonStatisticsStore.normalizedName(record.institutionName) == institution.normalizedName
    }

    private func institutionMonthSummaryText(
        label: String,
        summary: InstitutionMonthSummary
    ) -> String {
        "\(label) \(formatHours(summary.hours))小时 \(formatMoney(summary.fee))元"
    }

    private func placeholderPanel(title: String, message: String) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.03))
            .frame(maxWidth: .infinity, minHeight: 180)
            .overlay {
                VStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
    }

    private var deleteConfirmationMessage: String {
        guard let target = deleteTarget else { return "" }
        if deleteImpactedStudents.isEmpty {
            return "确定删除机构“\(target.name)”？上课单快照不会被修改。"
        }
        let names = deleteImpactedStudents.map(\.name).joined(separator: "、")
        return "确定删除机构“\(target.name)”？以下学生的统计设置会被清空：\(names)。上课单快照不会被修改。"
    }

    private func loadInstitutions() {
        do {
            institutions = try TeachingLessonStatisticsStore.loadInstitutions()
            statusMessage = ""
        } catch {
            statusMessage = "机构读取失败：\(error.localizedDescription)"
        }
    }

    private func loadAllData() {
        do {
            institutions = try TeachingLessonStatisticsStore.loadInstitutions()
            lessonRecords = try TeachingLessonStatisticsStore.loadLessonRecords()
            students = try TeachingStudentSettingsStore.loadStudents()
            statusMessage = ""
        } catch {
            statusMessage = "统计数据读取失败：\(error.localizedDescription)"
        }
    }

    private func saveInstitution(_ institution: TeachingInstitutionRecord) {
        do {
            var next = institutions
            let normalized = TeachingInstitutionRecord(
                id: institution.id,
                name: TeachingLessonStatisticsStore.normalizedName(institution.name),
                colorHex: TeachingLessonStatisticsStore.normalizedColorHex(institution.colorHex),
                defaultPriceForTwoHours: institution.defaultPriceForTwoHours,
                note: institution.note.trimmingCharacters(in: .whitespacesAndNewlines),
                iconName: institution.iconName
            )
            try TeachingLessonStatisticsStore.validateNewInstitutionName(
                normalized.name,
                excluding: normalized.id,
                in: next
            )

            if let index = next.firstIndex(where: { $0.id == normalized.id }) {
                let oldName = next[index].name
                next[index] = normalized
                try TeachingLessonStatisticsStore.saveInstitutions(next)
                if oldName != normalized.name {
                    try TeachingStudentSettingsStore.updateInstitutionNameInStudentProfiles(
                        institutionID: normalized.id,
                        newName: normalized.name
                    )
                    try TeachingLessonStatisticsStore.updateInstitutionNameInLessonRecords(
                        institutionID: normalized.id,
                        newName: normalized.name
                    )
                }
            } else {
                next.append(normalized)
                try TeachingLessonStatisticsStore.saveInstitutions(next)
            }

            institutions = next
            showInstitutionEditor = false
            editingInstitution = nil
            statusMessage = "机构已保存。"
        } catch {
            statusMessage = "机构保存失败：\(error.localizedDescription)"
        }
    }

    private func prepareDeleteInstitution(_ institution: TeachingInstitutionRecord) {
        do {
            deleteImpactedStudents = try TeachingStudentSettingsStore.studentsUsingInstitution(institutionID: institution.id)
            deleteTarget = institution
        } catch {
            statusMessage = "删除前检查失败：\(error.localizedDescription)"
        }
    }

    private func confirmDeleteInstitution() {
        guard let target = deleteTarget else { return }
        do {
            let next = institutions.filter { $0.id != target.id }
            try TeachingLessonStatisticsStore.saveInstitutions(next)
            try TeachingStudentSettingsStore.clearInstitutionFromStudentProfiles(institutionID: target.id)
            institutions = next
            deleteTarget = nil
            deleteImpactedStudents = []
            statusMessage = "机构已删除；相关学生统计设置已清空。"
        } catch {
            statusMessage = "机构删除失败：\(error.localizedDescription)"
        }
    }

    private func saveLesson(_ draft: TeachingLessonEditorDraft) {
        do {
            let record: TeachingLessonRecord
            if let source = draft.sourceLesson {
                record = try updatedLessonRecord(source, start: draft.start, end: draft.end)
            } else {
                record = try newLessonRecord(studentID: draft.studentID, start: draft.start, end: draft.end)
            }
            try saveLessonRecord(record)
            showLessonEditor = false
            editingLesson = nil
            pendingNewLessonStart = nil
            statusMessage = "课程已保存。"
        } catch {
            statusMessage = "课程保存失败：\(error.localizedDescription)"
        }
    }

    private func saveLessonRecord(_ record: TeachingLessonRecord) throws {
        guard let start = TeachingLessonStatisticsStore.date(from: record.startAt),
              let end = TeachingLessonStatisticsStore.date(from: record.endAt),
              start < end else {
            throw LessonEditError.invalidTimeRange
        }
        guard !hasLessonConflict(start: start, end: end, excluding: record.id) else {
            throw LessonEditError.conflict
        }
        pushLessonUndoSnapshot()
        if let index = lessonRecords.firstIndex(where: { $0.id == record.id }) {
            lessonRecords[index] = record
        } else {
            lessonRecords.append(record)
        }
        try TeachingLessonStatisticsStore.saveLessonRecords(lessonRecords)
    }

    private func newLessonRecord(studentID: UUID?, start: Date, end: Date) throws -> TeachingLessonRecord {
        guard let studentID,
              let student = students.first(where: { $0.id == studentID }) else {
            throw LessonEditError.missingStudent
        }
        guard let profile = try TeachingStudentSettingsStore.loadStudentProfile(studentID: studentID) else {
            throw LessonEditError.missingStudentStatistics
        }
        let statistics = profile.lessonStatistics.normalized()
        guard statistics.isComplete,
              let institutionID = statistics.institutionID,
              let institutionName = statistics.institutionName,
              let price = statistics.priceForTwoHours else {
            throw LessonEditError.missingStudentStatistics
        }
        let color = institutions.first(where: { $0.id == institutionID })?.effectiveColorHex
            ?? TeachingLessonStatisticsStore.defaultInstitutionColorHex
        let iconName = institutions.first(where: { $0.id == institutionID })?.iconName
        return TeachingLessonRecord(
            startAt: TeachingLessonStatisticsStore.makeISO8601String(from: start),
            endAt: TeachingLessonStatisticsStore.makeISO8601String(from: end),
            studentID: student.id,
            studentName: student.name,
            gradeCode: nil,
            institutionID: institutionID,
            institutionName: institutionName,
            priceForTwoHours: price,
            institutionColorHex: color,
            institutionIconName: iconName
        )
    }

    private func updatedLessonRecord(_ source: TeachingLessonRecord, start: Date, end: Date) throws -> TeachingLessonRecord {
        guard start < end else {
            throw LessonEditError.invalidTimeRange
        }
        var next = source
        next.startAt = TeachingLessonStatisticsStore.makeISO8601String(from: start)
        next.endAt = TeachingLessonStatisticsStore.makeISO8601String(from: end)
        return next
    }

    private func hasLessonConflict(start: Date, end: Date, excluding id: UUID?) -> Bool {
        lessonRecords.contains { record in
            guard record.id != id,
                  let oldStart = TeachingLessonStatisticsStore.date(from: record.startAt),
                  let oldEnd = TeachingLessonStatisticsStore.date(from: record.endAt) else {
                return false
            }
            return start < oldEnd && end > oldStart
        }
    }

    private func editableLessonRecords() -> [TeachingLessonRecord] {
        let calendar = Calendar.current
        let start = monthStart(for: displayedMonth)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return lessonRecords.filter { record in
            guard let lessonStart = TeachingLessonStatisticsStore.date(from: record.startAt),
                  let lessonEnd = TeachingLessonStatisticsStore.date(from: record.endAt) else {
                return false
            }
            return lessonEnd > start && lessonStart < end
        }
        .sorted { lhs, rhs in
            let lhsDate = TeachingLessonStatisticsStore.date(from: lhs.startAt) ?? .distantPast
            let rhsDate = TeachingLessonStatisticsStore.date(from: rhs.startAt) ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    private func confirmDeleteLesson() {
        guard let target = lessonDeleteTarget else { return }
        do {
            lessonRecords.removeAll { $0.id == target.id }
            try TeachingLessonStatisticsStore.saveLessonRecords(lessonRecords)
            lessonDeleteTarget = nil
            statusMessage = "课程已删除。"
        } catch {
            statusMessage = "课程删除失败：\(error.localizedDescription)"
        }
    }

    private var scheduleVisibleInterval: DateInterval {
        TeachingLessonScheduleBuilder.monthInterval(for: displayedMonth)
    }

    private var scheduleHorizontalMonthWidth: CGFloat {
        let days = Calendar.current.dateComponents([.day], from: scheduleVisibleInterval.start, to: scheduleVisibleInterval.end).day ?? 31
        return 34 + CGFloat(days) * 61.7 + CGFloat(max(0, days - 1)) * 6 + 24
    }

    private var scheduleInteractiveHeight: CGFloat {
        30 + CGFloat(24 - 8) * 36.7 + 24
    }

    private func moveScheduleLesson(_ record: TeachingLessonRecord, dayDelta: Int, hourDelta: Int) {
        guard dayDelta != 0 || hourDelta != 0,
              let oldStart = TeachingLessonStatisticsStore.date(from: record.startAt),
              let oldEnd = TeachingLessonStatisticsStore.date(from: record.endAt),
              let shiftedStartByDay = Calendar.current.date(byAdding: .day, value: dayDelta, to: oldStart),
              let shiftedEndByDay = Calendar.current.date(byAdding: .day, value: dayDelta, to: oldEnd),
              let newStart = Calendar.current.date(byAdding: .hour, value: hourDelta, to: shiftedStartByDay),
              let newEnd = Calendar.current.date(byAdding: .hour, value: hourDelta, to: shiftedEndByDay) else {
            return
        }
        var next = record
        next.startAt = TeachingLessonStatisticsStore.makeISO8601String(from: newStart)
        next.endAt = TeachingLessonStatisticsStore.makeISO8601String(from: newEnd)
        do {
            try saveLessonRecord(next)
            statusMessage = "课程已移动。"
        } catch {
            statusMessage = "移动失败：\(error.localizedDescription)"
        }
    }

    private func shiftScheduleLesson(_ record: TeachingLessonRecord, minutes: Int) {
        guard let oldStart = TeachingLessonStatisticsStore.date(from: record.startAt),
              let oldEnd = TeachingLessonStatisticsStore.date(from: record.endAt),
              let newStart = Calendar.current.date(byAdding: .minute, value: minutes, to: oldStart),
              let newEnd = Calendar.current.date(byAdding: .minute, value: minutes, to: oldEnd) else {
            statusMessage = "课程时间无效，无法移动。"
            return
        }
        var next = record
        next.startAt = TeachingLessonStatisticsStore.makeISO8601String(from: newStart)
        next.endAt = TeachingLessonStatisticsStore.makeISO8601String(from: newEnd)
        do {
            try saveLessonRecord(next)
            statusMessage = minutes < 0 ? "课程已后退半小时。" : "课程已前进半小时。"
        } catch {
            statusMessage = "移动失败：\(error.localizedDescription)"
        }
    }

    private func insertScheduleLesson(day: Date, hour: Int) {
        pendingNewLessonStart = date(on: day, hour: hour, minute: 0) ?? day
        editingLesson = nil
        showLessonEditor = true
    }

    private func pasteScheduleLesson(on day: Date, hour: Int) {
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
        let duration = sourceEnd.timeIntervalSince(sourceStart)
        let end = start.addingTimeInterval(duration)
        var next = copiedLessonRecord
        next.id = UUID()
        next.startAt = TeachingLessonStatisticsStore.makeISO8601String(from: start)
        next.endAt = TeachingLessonStatisticsStore.makeISO8601String(from: end)
        do {
            try saveLessonRecord(next)
            statusMessage = "课程已粘贴。"
        } catch {
            statusMessage = "粘贴失败：\(error.localizedDescription)"
        }
    }

    private func copyScheduleText(
        scope: TeachingLessonScheduleBuilder.TextScope,
        filter: TeachingLessonScheduleBuilder.Filter,
        groupByStudent: Bool
    ) {
        let records = TeachingLessonScheduleBuilder.records(from: lessonRecords, in: scheduleVisibleInterval, filter: filter)
        let text = TeachingLessonScheduleBuilder.scopedPlainText(
            scope: scope,
            month: displayedMonth,
            records: records,
        )
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        statusMessage = "已复制。"
    }

    private func priceText(_ price: Double?) -> String {
        guard let price else { return "默认价：-" }
        if price.rounded() == price {
            return "默认价：\(Int(price))"
        }
        return "默认价：\(price)"
    }

    private func copyInstitutionMonth(_ institution: TeachingInstitutionRecord, monthOffset: Int) {
        let month = Calendar.current.date(byAdding: .month, value: monthOffset, to: monthStart(for: displayedMonth)) ?? displayedMonth
        let interval = TeachingLessonScheduleBuilder.monthInterval(for: month)
        let records = TeachingLessonScheduleBuilder.records(
            from: lessonRecords,
            in: interval,
            filter: .institution(institution.id)
        )
        let text = TeachingLessonScheduleBuilder.scopedPlainText(
            scope: .institution(institutionName: institution.name),
            month: month,
            records: records,
        )
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        statusMessage = "已复制\(monthOffset == 0 ? "当月" : "上月")机构统计。"
    }

    @MainActor
    private func exportInstitutionScheduleImage(_ institution: TeachingInstitutionRecord, monthOffset: Int) {
        let month = Calendar.current.date(byAdding: .month, value: monthOffset, to: monthStart(for: displayedMonth)) ?? displayedMonth
        let interval = TeachingLessonScheduleBuilder.monthInterval(for: month)
        let records = TeachingLessonScheduleBuilder.records(
            from: lessonRecords,
            in: interval,
            filter: .institution(institution.id)
        )
        let pages = [
            TeachingLessonScheduleBuilder.horizontalMonthPage(records: records, interval: interval)
        ]
        guard !pages.isEmpty else {
            statusMessage = "该机构\(monthOffset == 0 ? "当月" : "上月")暂无课程。"
            return
        }

        let snapshot = TeachingScheduleExportSnapshotView(
            monthTitle: "\(institution.name) \(TeachingLessonScheduleBuilder.monthTitle(for: month))",
            pages: pages,
            layout: .horizontalMonth,
            usesGradientBackground: true
        )
        let renderer = ImageRenderer(
            content: snapshot
                .frame(width: TeachingScheduleExportSizing.width(for: pages, layout: .horizontalMonth))
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
        guard let image = renderer.uiImage,
              let data = image.pngData() else {
            statusMessage = "导出失败：无法生成图片。"
            return
        }
        #endif

        do {
            let sourceURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(institution.name)_\(TeachingLessonScheduleBuilder.monthTitle(for: month)).png")
            try TeachingDocumentExportService.exportToWeChat(
                sourceFileURL: sourceURL,
                descriptor: TeachingDocumentExportDescriptor(
                    displayName: "机构课",
                    fileExtension: "png",
                    contentType: .png
                )
            ) {
                data
            }
            statusMessage = "已打开系统导出菜单。"
        } catch {
            statusMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func exportSchedule() {
        exportScheduleImage()
    }

    @MainActor
    private func exportScheduleText() {
        let summary = buildScheduleSummary()
        let text = schedulePlainText(summary)
        do {
            let sourceURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("课_\(monthTitle(for: displayedMonth)).txt")
            try TeachingDocumentExportService.exportToWeChat(
                sourceFileURL: sourceURL,
                descriptor: TeachingDocumentExportDescriptor(
                    displayName: "课",
                    fileExtension: "txt",
                    contentType: .plainText
                )
            ) {
                Data(text.utf8)
            }
            statusMessage = "已打开系统导出菜单。"
        } catch {
            statusMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func exportScheduleImage() {
        exportScheduleImage(title: monthTitle(for: displayedMonth), filter: .all)
    }

    @MainActor
    private func exportScheduleImage(
        title: String,
        filter: TeachingLessonScheduleBuilder.Filter,
        availabilityForInstitutionID institutionID: UUID? = nil
    ) {
        let records = TeachingLessonScheduleBuilder.records(from: lessonRecords, in: scheduleVisibleInterval, filter: filter)
        let occupied = institutionID.map { id in
            TeachingLessonScheduleBuilder.records(from: lessonRecords, in: scheduleVisibleInterval).filter { $0.institutionID != id }
        } ?? []
        let pages = [
            TeachingLessonScheduleBuilder.horizontalMonthPage(
                records: records,
                interval: scheduleVisibleInterval,
                occupiedRecords: occupied
            )
        ]
        guard !pages.isEmpty else {
            statusMessage = "该月暂无课程记录。"
            return
        }

        let snapshot = TeachingScheduleExportSnapshotView(
            monthTitle: title,
            pages: pages,
            layout: .horizontalMonth,
            usesGradientBackground: true
        )
        let renderer = ImageRenderer(
            content: snapshot
                .frame(width: TeachingScheduleExportSizing.width(for: pages, layout: .horizontalMonth))
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
        guard let image = renderer.uiImage,
              let data = image.pngData() else {
            statusMessage = "导出失败：无法生成图片。"
            return
        }
        #endif

        do {
            let sourceURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(safeScheduleFilename(title)).png")
            try TeachingDocumentExportService.exportToWeChat(
                sourceFileURL: sourceURL,
                descriptor: TeachingDocumentExportDescriptor(
                    displayName: title,
                    fileExtension: "png",
                    contentType: .png
                )
            ) {
                data
            }
            statusMessage = "已打开系统导出菜单。"
        } catch {
            statusMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func exportScheduleInstitutionWeekAvailability(_ record: TeachingLessonRecord) {
        guard let start = TeachingLessonStatisticsStore.date(from: record.startAt),
              let institutionID = record.institutionID else {
            statusMessage = "无法导出机构周可用：课程缺少时间或机构。"
            return
        }
        let weekStart = TeachingLessonScheduleBuilder.weekStart(for: start)
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let interval = DateInterval(start: weekStart, end: weekEnd)
        let records = TeachingLessonScheduleBuilder.records(from: lessonRecords, in: interval, filter: .institution(institutionID))
        let occupied = TeachingLessonScheduleBuilder.records(from: lessonRecords, in: interval).filter { $0.institutionID != institutionID }
        let pages = TeachingLessonScheduleBuilder.weeklyPages(
            records: records,
            interval: interval,
            includeEmptyWeeks: true,
            occupiedRecords: occupied
        )
        exportSchedulePages(title: "\(record.institutionName)\(weekRangeTitle(start: weekStart))机构周可用", pages: pages, layout: .weeklyTemplate)
    }

    @MainActor
    private func exportSchedulePages(title: String, pages: [WeeklySchedulePage], layout: TeachingScheduleExportLayout) {
        let snapshot = TeachingScheduleExportSnapshotView(
            monthTitle: title,
            pages: pages,
            layout: layout,
            usesGradientBackground: true
        )
        let renderer = ImageRenderer(content: snapshot.frame(width: TeachingScheduleExportSizing.width(for: pages, layout: layout)).padding(24))
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
            let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeScheduleFilename(title)).png")
            try TeachingDocumentExportService.exportToWeChat(
                sourceFileURL: sourceURL,
                descriptor: TeachingDocumentExportDescriptor(displayName: title, fileExtension: "png", contentType: .png)
            ) { data }
            statusMessage = "已打开系统导出菜单。"
        } catch {
            statusMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func safeScheduleFilename(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let sanitized = value.components(separatedBy: invalidCharacters).joined(separator: "-")
        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "课" : sanitized
    }

    private func buildScheduleSummary() -> ScheduleSummary {
        let calendar = Calendar.current
        let monthStart = monthStart(for: displayedMonth)
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

        let visibleLessons = lessonRecords.compactMap { record -> LessonDisplayItem? in
            guard let start = TeachingLessonStatisticsStore.date(from: record.startAt),
                  let end = TeachingLessonStatisticsStore.date(from: record.endAt),
                  start < end,
                  end > monthStart,
                  start < monthEnd else {
                return nil
            }

            let clippedStart = max(start, monthStart)
            let clippedEnd = min(end, monthEnd)
            let hours = max(0, clippedEnd.timeIntervalSince(clippedStart) / 3600)
            let fee = (record.priceForTwoHours ?? 0) * hours / 2
            let displayDay = calendar.startOfDay(for: clippedStart)
            return LessonDisplayItem(
                id: record.id,
                sortDate: clippedStart,
                day: displayDay,
                timeText: lessonTimeText(start: start, end: end),
                studentName: record.studentName.isEmpty ? "未命名学生" : record.studentName,
                institutionName: record.institutionName.isEmpty ? "未命名机构" : record.institutionName,
                institutionID: record.institutionID,
                colorHex: record.effectiveInstitutionColorHex,
                hours: hours,
                fee: fee
            )
        }
        .sorted { $0.sortDate < $1.sortDate }

        let groupedByInstitution = Dictionary(grouping: visibleLessons) { item in
            item.institutionID?.uuidString ?? item.institutionName
        }
        let institutionSummaries: [InstitutionScheduleSummary] = groupedByInstitution.values.map { (items: [LessonDisplayItem]) in
            let first = items.sorted { $0.sortDate < $1.sortDate }.first
            return InstitutionScheduleSummary(
                id: first?.institutionID?.uuidString ?? first?.institutionName ?? UUID().uuidString,
                institutionName: first?.institutionName ?? "未命名机构",
                colorHex: first?.colorHex ?? TeachingLessonStatisticsStore.defaultInstitutionColorHex,
                hours: items.reduce(0) { $0 + $1.hours },
                fee: items.reduce(0) { $0 + $1.fee }
            )
        }
        .sorted { (lhs: InstitutionScheduleSummary, rhs: InstitutionScheduleSummary) in
            lhs.institutionName.localizedCaseInsensitiveCompare(rhs.institutionName) == .orderedAscending
        }

        let groupedByDay = Dictionary(grouping: visibleLessons, by: \.day)
        let days = groupedByDay.keys.sorted().map { day in
            ScheduleDayGroup(
                id: day.timeIntervalSince1970,
                title: dayTitle(for: day),
                lessons: (groupedByDay[day] ?? []).sorted { $0.sortDate < $1.sortDate }
            )
        }

        return ScheduleSummary(
            totalFee: institutionSummaries.reduce(0) { $0 + $1.fee },
            institutionSummaries: institutionSummaries,
            days: days
        )
    }

    private func buildWeeklySchedulePages() -> [WeeklySchedulePage] {
        let calendar = Calendar.current
        let monthStart = monthStart(for: displayedMonth)
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        var grouped: [Date: [Date: [ScheduleWeekBlock]]] = [:]

        for record in lessonRecords {
            guard let rawStart = TeachingLessonStatisticsStore.date(from: record.startAt),
                  let rawEnd = TeachingLessonStatisticsStore.date(from: record.endAt),
                  rawStart < rawEnd,
                  rawEnd > monthStart,
                  rawStart < monthEnd else {
                continue
            }

            let clippedStart = max(rawStart, monthStart)
            let clippedEnd = min(rawEnd, monthEnd)
            var day = calendar.startOfDay(for: clippedStart)
            while day < clippedEnd {
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                let sliceStart = max(clippedStart, day)
                let sliceEnd = min(clippedEnd, nextDay)
                if sliceStart < sliceEnd {
                    let weekStart = weekStart(for: day)
                    let block = ScheduleWeekBlock(
                        id: "\(record.id.uuidString)-\(day.timeIntervalSince1970)",
                        startHour: hourValue(for: sliceStart),
                        endHour: hourValue(for: sliceEnd, day: day),
                        studentName: record.studentName.isEmpty ? "未命名学生" : record.studentName,
                        institutionName: record.institutionName.isEmpty ? "未命名机构" : record.institutionName,
                        colorHex: record.effectiveInstitutionColorHex,
                        timeText: exactLessonTimeText(start: sliceStart, end: sliceEnd),
                        durationText: "\(formatHours(max(0, sliceEnd.timeIntervalSince(sliceStart) / 3600)))小时"
                    )
                    grouped[weekStart, default: [:]][day, default: []].append(block)
                }
                day = nextDay
            }
        }

        return grouped.keys.sorted().compactMap { weekStartDate in
            let days = (0..<7).compactMap { offset -> ScheduleWeekDay? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: weekStartDate) else {
                    return nil
                }
                let dayStart = calendar.startOfDay(for: date)
                let blocks = (grouped[weekStartDate]?[dayStart] ?? []).sorted { $0.startHour < $1.startHour }
                return ScheduleWeekDay(
                    id: dayStart.timeIntervalSince1970,
                    date: dayStart,
                    title: weekDayTitle(for: dayStart),
                    isInDisplayedMonth: dayStart >= monthStart && dayStart < monthEnd,
                    blocks: blocks
                )
            }
            let allBlocks = days.flatMap(\.blocks)
            guard !allBlocks.isEmpty else { return nil }
            let minimumHour = min(8, Int(floor(allBlocks.map(\.startHour).min() ?? 8)))
            let maximumHour = max(24, Int(ceil(allBlocks.map(\.endHour).max() ?? 24)))
            return WeeklySchedulePage(
                id: weekStartDate.timeIntervalSince1970,
                title: weekRangeTitle(start: weekStartDate),
                startHour: max(0, minimumHour),
                endHour: min(24, maximumHour),
                days: days
            )
        }
    }

    private func monthStart(for date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private func date(on day: Date, hour: Int, minute: Int) -> Date? {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)
    }

    private func pushLessonUndoSnapshot() {
        lessonUndoStack.append(lessonRecords)
        if lessonUndoStack.count > 100 {
            lessonUndoStack.removeFirst()
        }
        lessonRedoStack.removeAll()
    }

    private func undoLessonChange() {
        guard let previous = lessonUndoStack.popLast() else { return }
        lessonRedoStack.append(lessonRecords)
        lessonRecords = previous
        try? TeachingLessonStatisticsStore.saveLessonRecords(lessonRecords)
        statusMessage = "已撤回。"
    }

    private func redoLessonChange() {
        guard let next = lessonRedoStack.popLast() else { return }
        lessonUndoStack.append(lessonRecords)
        lessonRecords = next
        try? TeachingLessonStatisticsStore.saveLessonRecords(lessonRecords)
        statusMessage = "已恢复。"
    }

    private func canMoveToNextMonth(from date: Date) -> Bool {
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .month, value: 1, to: monthStart(for: date)) else {
            return false
        }
        return next <= monthStart(for: Date())
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }

    private func dayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func weekDayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "E M.d"
        return formatter.string(from: date)
    }

    private func weekRangeTitle(start: Date) -> String {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return "\(dayTitle(for: start))-\(dayTitle(for: end))"
    }

    private func lessonTimeText(start: Date, end: Date) -> String {
        TeachingLessonScheduleBuilder.timeRangeText(start: start, end: end)
    }

    private func exactLessonTimeText(start: Date, end: Date) -> String {
        TeachingLessonScheduleBuilder.timeRangeText(start: start, end: end)
    }

    private func hourValue(for date: Date, day: Date? = nil) -> Double {
        let calendar = Calendar.current
        if let day,
           calendar.startOfDay(for: date) > calendar.startOfDay(for: day) {
            return 24
        }
        let hour = Double(calendar.component(.hour, from: date))
        let minute = Double(calendar.component(.minute, from: date))
        return hour + minute / 60
    }

    private func formatHours(_ hours: Double) -> String {
        if hours.rounded() == hours {
            return String(Int(hours))
        }
        return String(format: "%.1f", hours)
    }

    private func formatMoney(_ money: Double) -> String {
        if money.rounded() == money {
            return String(Int(money))
        }
        return String(format: "%.1f", money)
    }

    private func weekStart(for date: Date) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
    }

    private func schedulePlainText(_ summary: ScheduleSummary) -> String {
        var lines = [
            "课：\(monthTitle(for: displayedMonth))",
            "该月总钱数：\(formatMoney(summary.totalFee))元"
        ]
        lines.append(contentsOf: summary.institutionSummaries.map { item in
            "\(item.institutionName);\(formatHours(item.hours))小时;\(formatMoney(item.fee))元；"
        })
        for day in summary.days {
            lines.append("")
            lines.append(day.title)
            lines.append(contentsOf: day.lessons.map { item in
                "\(item.timeText)  \(item.studentName)  \(item.institutionName)"
            })
        }
        return lines.joined(separator: "\n")
    }
}
