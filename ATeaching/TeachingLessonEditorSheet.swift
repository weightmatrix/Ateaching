import SwiftUI

// MARK: - 课单编辑弹窗 - v1 - 手动添加课程与修改课程时间

/// 统计页“修改”里的添加/更改弹窗；只收集草稿，保存和冲突检查交给主页面。
struct TeachingLessonEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let lesson: TeachingLessonRecord?
    let students: [TeachingStudentItem]
    var initialStart: Date? = nil
    let onSave: (TeachingLessonEditorDraft) -> Void

    @State private var selectedStudentID: UUID?
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(7200)
    @State private var statusMessage = ""

    @ViewBuilder
    var body: some View {
        #if os(macOS)
        editorContent
            .frame(minWidth: 460, minHeight: 280)
        #else
        editorContent
        #endif
    }

    private var editorContent: some View {
        NavigationStack {
            Form {
                Section(lesson == nil ? "添加课程" : "更改时间") {
                    if lesson == nil {
                        Picker("学生", selection: $selectedStudentID) {
                            Text("未选择").tag(Optional<UUID>.none)
                            ForEach(students.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { student in
                                Text(student.name).tag(Optional(student.id))
                            }
                        }
                        .pickerStyle(.menu)
                    } else if let lesson {
                        Text("\(lesson.studentName)  \(lesson.institutionName)")
                            .font(.subheadline)
                    }

                    TeachingLessonDateTimeInput(title: "开始时间", date: $start)
                    startShortcutButtons
                    TeachingLessonDateTimeInput(title: "结束时间", date: $end)
                }

                if !statusMessage.isEmpty {
                    TeachingStatusMessageSection(message: statusMessage)
                }
            }
            .navigationTitle(lesson == nil ? "添加课程" : "更改时间")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
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
                loadDraft()
            }
            .onChange(of: start) { _, newValue in
                end = newValue.addingTimeInterval(7200)
            }
        }
    }

    private var startShortcutButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("开始")
                .font(.footnote)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: 7),
                spacing: 6
            ) {
                ForEach([5, 10, 20, 30, 40, 50, 60, -5, -10, -20, -30, -40, -50, -60], id: \.self) { minute in
                    Button(minute > 0 ? "+\(minute)" : "\(minute)") {
                        shiftStart(minutes: minute)
                    }
                    .font(.caption2.monospacedDigit())
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func shiftStart(minutes: Int) {
        start = start.addingTimeInterval(TimeInterval(minutes * 60))
        end = start.addingTimeInterval(7200)
    }

    private func loadDraft() {
        if let lesson {
            selectedStudentID = lesson.studentID
            if let startDate = TeachingLessonStatisticsStore.date(from: lesson.startAt) {
                start = startDate
            }
            if let endDate = TeachingLessonStatisticsStore.date(from: lesson.endAt) {
                end = endDate
            }
        } else if selectedStudentID == nil {
            selectedStudentID = students.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }.first?.id
            start = dateBySettingMinuteZero(initialStart ?? start)
            end = start.addingTimeInterval(7200)
        }
    }

    private func dateBySettingMinuteZero(_ date: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components) ?? date
    }

    private func save() {
        guard start < end else {
            statusMessage = LessonEditError.invalidTimeRange.localizedDescription
            return
        }
        onSave(
            TeachingLessonEditorDraft(
                sourceLesson: lesson,
                studentID: selectedStudentID,
                start: start,
                end: end
            )
        )
    }
}

/// 支持两位小时和分钟输入的日期时间控件；开始时间变化由外层决定是否联动结束时间。
struct TeachingLessonDateTimeInput: View {
    let title: String
    @Binding var date: Date

    @State private var day = Date()
    @State private var hourText = ""
    @State private var minuteText = ""
    @FocusState private var focusedField: Field?

    /// 当前正在编辑小时还是分钟，用于避免输入过程中被外部同步覆盖。
    private enum Field {
        case hour
        case minute
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            DatePicker("日期", selection: $day, displayedComponents: [.date])
                .onChange(of: day) { _, newValue in
                    apply(day: newValue, hour: hourValue, minute: minuteValue)
                }

            HStack(spacing: 8) {
                Text("时间")
                    .foregroundStyle(.secondary)

                TextField("", text: $hourText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, design: .monospaced))
                    .frame(width: 66)
                    .multilineTextAlignment(.center)
                    .focused($focusedField, equals: .hour)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .onChange(of: hourText) { _, newValue in
                        updateHourText(newValue)
                    }
                    .onSubmit {
                        normalizeTextFields()
                    }

                Text(":")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))

                TextField("", text: $minuteText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, design: .monospaced))
                    .frame(width: 66)
                    .multilineTextAlignment(.center)
                    .focused($focusedField, equals: .minute)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .onChange(of: minuteText) { _, newValue in
                        updateMinuteText(newValue)
                    }
                    .onSubmit {
                        normalizeTextFields()
                    }
            }
        }
        .task {
            syncFromDate()
        }
        .onChange(of: date) { _, _ in
            syncFromDate()
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                normalizeTextFields()
            }
        }
    }

    private var hourValue: Int {
        Int(hourText) ?? Calendar.current.component(.hour, from: date)
    }

    private var minuteValue: Int {
        Int(minuteText) ?? Calendar.current.component(.minute, from: date)
    }

    private func updateHourText(_ value: String) {
        let filtered = String(value.filter(\.isNumber).prefix(2))
        if filtered != value {
            hourText = filtered
            return
        }
        guard let hour = Int(filtered), (0...23).contains(hour) else {
            if filtered.count == 2 {
                hourText = String(Calendar.current.component(.hour, from: date))
            }
            return
        }
        apply(day: day, hour: hour, minute: minuteValue)
    }

    private func updateMinuteText(_ value: String) {
        let filtered = String(value.filter(\.isNumber).prefix(2))
        if filtered != value {
            minuteText = filtered
            return
        }
        guard let minute = Int(filtered), (0...59).contains(minute) else {
            if filtered.count == 2 {
                minuteText = padded(Calendar.current.component(.minute, from: date))
            }
            return
        }
        apply(day: day, hour: hourValue, minute: minute)
    }

    private func apply(day: Date, hour: Int, minute: Int) {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        components.second = 0
        if let next = Calendar.current.date(from: components), next != date {
            date = next
        }
    }

    private func syncFromDate() {
        let calendar = Calendar.current
        let nextDay = calendar.startOfDay(for: date)
        let nextHour = String(calendar.component(.hour, from: date))
        let nextMinute = padded(calendar.component(.minute, from: date))
        if day != nextDay {
            day = nextDay
        }
        if focusedField != .hour && hourText != nextHour {
            hourText = nextHour
        }
        if focusedField != .minute && minuteText != nextMinute {
            minuteText = nextMinute
        }
    }

    private func normalizeTextFields() {
        let hour = min(max(Int(hourText) ?? Calendar.current.component(.hour, from: date), 0), 23)
        let minute = min(max(Int(minuteText) ?? Calendar.current.component(.minute, from: date), 0), 59)
        hourText = String(hour)
        minuteText = padded(minute)
        apply(day: day, hour: hour, minute: minute)
    }

    private func padded(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}
