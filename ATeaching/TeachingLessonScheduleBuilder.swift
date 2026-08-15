import Foundation

// MARK: - 课时统计课表构建工具 - v1 - 共享月份/周表筛选、冲突判断和图片页生成

/// 课表、机构导出、排课和周表共用的纯数据构建工具，避免每个页面各算一套。
enum TeachingLessonScheduleBuilder {
    enum Filter {
        case all
        case institution(UUID)
        case student(UUID)
    }

    enum TextScope {
        case student(institutionName: String, studentName: String)
        case institution(institutionName: String)
    }

    private struct TextColumnWidths {
        var date: Int
        var weekday: Int
        var time: Int
        var student: Int
    }

    static func hasConflict(
        start: Date,
        end: Date,
        in records: [TeachingLessonRecord],
        excluding id: UUID? = nil
    ) -> Bool {
        records.contains { record in
            guard record.id != id,
                  let oldStart = TeachingLessonStatisticsStore.date(from: record.startAt),
                  let oldEnd = TeachingLessonStatisticsStore.date(from: record.endAt) else {
                return false
            }
            return start < oldEnd && end > oldStart
        }
    }

    static func records(
        from source: [TeachingLessonRecord],
        in interval: DateInterval,
        filter: Filter = .all
    ) -> [TeachingLessonRecord] {
        source.filter { record in
            guard matches(record, filter: filter),
                  let start = TeachingLessonStatisticsStore.date(from: record.startAt),
                  let end = TeachingLessonStatisticsStore.date(from: record.endAt),
                  start < end else {
                return false
            }
            return end > interval.start && start < interval.end
        }
        .sorted {
            (TeachingLessonStatisticsStore.date(from: $0.startAt) ?? .distantPast)
                < (TeachingLessonStatisticsStore.date(from: $1.startAt) ?? .distantPast)
        }
    }

    static func plainText(
        title: String,
        records: [TeachingLessonRecord],
        includeFeeLine: Bool = true,
        useWeekdayDate: Bool = false,
        groupByStudent: Bool = false
    ) -> String {
        if groupByStudent {
            return groupedStudentPlainText(
                title: title,
                records: records,
                includeFeeLine: includeFeeLine,
                useWeekdayDate: useWeekdayDate
            )
        }
        var totalHours = 0.0
        var totalFee = 0.0
        var lines: [String] = [title]
        for record in sortedRecordsByTime(records) {
            guard let start = TeachingLessonStatisticsStore.date(from: record.startAt),
                  let end = TeachingLessonStatisticsStore.date(from: record.endAt) else { continue }
            let hours = max(0, end.timeIntervalSince(start) / 3600)
            totalHours += hours
            totalFee += (record.priceForTwoHours ?? 0) * hours / 2
            let day = useWeekdayDate ? weekdayTitle(for: start) : fullDayTitle(for: start)
            lines.append("\(day) | \(timeRangeText(start: start, end: end)) | \(record.studentName) | \(record.institutionName) | \(formatHours(hours))小时")
        }
        if includeFeeLine {
            lines.insert("总课时：\(formatHours(totalHours))小时 | 总课费：\(formatMoney(totalFee))元", at: min(1, lines.count))
        } else {
            lines.insert("总课时：\(formatHours(totalHours))小时", at: min(1, lines.count))
        }
        return lines.joined(separator: "\n")
    }

    static func scopedPlainText(
        scope: TextScope,
        month: Date,
        records: [TeachingLessonRecord]
    ) -> String {
        let sortedRecords = sortedRecordsByTime(records)
        let rows = sortedRecords.compactMap { record -> (date: String, weekday: String, time: String, student: String, hours: String, hourValue: Double)? in
            guard let start = TeachingLessonStatisticsStore.date(from: record.startAt),
                  let end = TeachingLessonStatisticsStore.date(from: record.endAt),
                  start < end else { return nil }
            let hours = max(0, end.timeIntervalSince(start) / 3600)
            return (
                date: fullDayTitle(for: start),
                weekday: weekdayTitle(for: start),
                time: timeRangeText(start: start, end: end),
                student: record.studentName.isEmpty ? "未命名学生" : record.studentName,
                hours: "\(formatHours(hours))小时",
                hourValue: hours
            )
        }
        let totalHours = rows.reduce(0) { $0 + $1.hourValue }
        let widths = TextColumnWidths(
            date: maxDisplayWidth(header: "日期", values: rows.map(\.date)),
            weekday: maxDisplayWidth(header: "星期", values: rows.map(\.weekday)),
            time: maxDisplayWidth(header: "时间", values: rows.map(\.time)),
            student: maxDisplayWidth(header: "学生", values: rows.map(\.student))
        )
        let firstLine: String
        switch scope {
        case let .student(institutionName, studentName):
            firstLine = "机构：\(institutionName),学生:\(studentName)"
        case let .institution(institutionName):
            firstLine = "机构：\(institutionName)"
        }
        var lines = [
            firstLine,
            monthTitle(for: month),
            "总课时:\(formatHours(totalHours))"
        ]
        lines.append(contentsOf: rows.map { row in
            formatTextLine(
                date: row.date,
                weekday: row.weekday,
                time: row.time,
                student: row.student,
                hours: row.hours,
                widths: widths
            )
        })
        return lines.joined(separator: "\n")
    }

    // MARK: 月费用统计复制文本

    /// 复制·学生·月费用：第一行`<年月>学生费用统计`，第二行标题行，之后按学生逐行汇总。
    static func studentMonthlyFeeText(month: Date, records: [TeachingLessonRecord]) -> String {
        let interval = monthInterval(for: month)
        let aggregates = monthlyFeeAggregates(in: interval, records: records, groupByStudent: true)
        let lines = alignedPipeTable(
            header: ["学生", "机构", "课时", "费用"],
            rows: aggregates.map { aggregate in
                [
                    aggregate.studentName,
                    aggregate.institutionName,
                    "\(formatHours(aggregate.hours))小时",
                    "\(formatMoney(aggregate.fee))元"
                ]
            }
        )
        return ([monthTitle(for: month) + "学生费用统计"] + lines).joined(separator: "\n")
    }

    /// 复制·机构·月费用：第一行`<年月>机构费用统计`，第二行标题行，之后按机构逐行汇总。
    static func institutionMonthlyFeeText(month: Date, records: [TeachingLessonRecord]) -> String {
        let interval = monthInterval(for: month)
        let aggregates = monthlyFeeAggregates(in: interval, records: records, groupByStudent: false)
        let lines = alignedPipeTable(
            header: ["机构", "课时", "费用"],
            rows: aggregates.map { aggregate in
                [
                    aggregate.institutionName,
                    "\(formatHours(aggregate.hours))小时",
                    "\(formatMoney(aggregate.fee))元"
                ]
            }
        )
        return ([monthTitle(for: month) + "机构费用统计"] + lines).joined(separator: "\n")
    }

    private struct MonthlyFeeAggregate {
        var studentKey: String
        var studentName: String
        var institutionKey: String
        var institutionName: String
        var hours: Double
        var fee: Double
    }

    private static func monthlyFeeAggregates(
        in interval: DateInterval,
        records: [TeachingLessonRecord],
        groupByStudent: Bool
    ) -> [MonthlyFeeAggregate] {
        var buckets: [String: MonthlyFeeAggregate] = [:]
        for record in records {
            guard !TeachingLessonPlanningPlaceholder.isPlaceholder(record),
                  let start = TeachingLessonStatisticsStore.date(from: record.startAt),
                  let end = TeachingLessonStatisticsStore.date(from: record.endAt),
                  start < end,
                  end > interval.start,
                  start < interval.end else {
                continue
            }
            let clippedStart = max(start, interval.start)
            let clippedEnd = min(end, interval.end)
            let hours = max(0, clippedEnd.timeIntervalSince(clippedStart) / 3600)
            let fee = (record.priceForTwoHours ?? 0) * hours / 2
            let studentName = record.studentName.isEmpty ? "未命名学生" : record.studentName
            let institutionName = record.institutionName.isEmpty ? "未命名机构" : record.institutionName
            let studentKey = record.studentID?.uuidString ?? "学生名:\(studentName)"
            let institutionKey = record.institutionID?.uuidString ?? "机构名:\(institutionName)"
            let bucketKey = groupByStudent ? "\(studentKey)|\(institutionKey)" : institutionKey
            var aggregate = buckets[bucketKey] ?? MonthlyFeeAggregate(
                studentKey: studentKey,
                studentName: studentName,
                institutionKey: institutionKey,
                institutionName: institutionName,
                hours: 0,
                fee: 0
            )
            aggregate.hours += hours
            aggregate.fee += fee
            buckets[bucketKey] = aggregate
        }

        let rows = Array(buckets.values)
        if groupByStudent {
            return rows.sorted { lhs, rhs in
                let studentOrder = lhs.studentName.localizedCaseInsensitiveCompare(rhs.studentName)
                if studentOrder != .orderedSame {
                    return studentOrder == .orderedAscending
                }
                return lhs.institutionName.localizedCaseInsensitiveCompare(rhs.institutionName) == .orderedAscending
            }
        }
        return rows.sorted {
            $0.institutionName.localizedCaseInsensitiveCompare($1.institutionName) == .orderedAscending
        }
    }

    /// 生成用` | `分隔、所有竖线按显示宽度对齐的表格行；首行为标题行。
    private static func alignedPipeTable(header: [String], rows: [[String]]) -> [String] {
        var widths = header.map(displayWidth(of:))
        for row in rows {
            for (index, cell) in row.enumerated() where index < widths.count {
                widths[index] = max(widths[index], displayWidth(of: cell))
            }
        }
        func formatLine(_ cells: [String]) -> String {
            cells.enumerated().map { index, cell in
                if index == cells.count - 1 { return cell }
                return paddedDisplay(cell, width: widths[index])
            }
            .joined(separator: " | ")
        }
        return [formatLine(header)] + rows.map(formatLine)
    }

    private static func groupedStudentPlainText(
        title: String,
        records: [TeachingLessonRecord],
        includeFeeLine: Bool,
        useWeekdayDate: Bool
    ) -> String {
        var totalHours = 0.0
        var totalFee = 0.0
        var lines: [String] = [title]
        let grouped = Dictionary(grouping: records) { record in
            record.studentName.isEmpty ? "未命名学生" : record.studentName
        }
        for studentName in grouped.keys.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            let studentRecords = sortedRecordsByTime(grouped[studentName] ?? [])
            guard !studentRecords.isEmpty else { continue }
            lines.append("学生：\(studentName)")
            for record in studentRecords {
                guard let start = TeachingLessonStatisticsStore.date(from: record.startAt),
                      let end = TeachingLessonStatisticsStore.date(from: record.endAt) else { continue }
                let hours = max(0, end.timeIntervalSince(start) / 3600)
                totalHours += hours
                totalFee += (record.priceForTwoHours ?? 0) * hours / 2
                let day = useWeekdayDate ? weekdayTitle(for: start) : fullDayTitle(for: start)
                lines.append("\(day) | \(timeRangeText(start: start, end: end)) | \(formatHours(hours))小时")
            }
        }
        if includeFeeLine {
            lines.insert("总课时：\(formatHours(totalHours))小时 | 总课费：\(formatMoney(totalFee))元", at: min(1, lines.count))
        } else {
            lines.insert("总课时：\(formatHours(totalHours))小时", at: min(1, lines.count))
        }
        return lines.joined(separator: "\n")
    }

    static func weeklyPages(
        records: [TeachingLessonRecord],
        interval: DateInterval,
        titlePrefix: String? = nil,
        includeEmptyWeeks: Bool = false,
        occupiedRecords: [TeachingLessonRecord] = []
    ) -> [WeeklySchedulePage] {
        let calendar = Calendar.current
        var grouped: [Date: [Date: [ScheduleWeekBlock]]] = [:]

        appendBlocks(from: records, interval: interval, into: &grouped, occupied: false)
        appendBlocks(from: occupiedRecords, interval: interval, into: &grouped, occupied: true)

        let firstWeekStart = weekStart(for: interval.start)
        var weekStarts = grouped.keys.sorted()
        if includeEmptyWeeks {
            var cursor = firstWeekStart
            while cursor < interval.end {
                if !weekStarts.contains(cursor) {
                    weekStarts.append(cursor)
                }
                cursor = calendar.date(byAdding: .day, value: 7, to: cursor) ?? interval.end
            }
            weekStarts.sort()
        }

        return weekStarts.compactMap { weekStartDate in
            let days = (0..<7).compactMap { offset -> ScheduleWeekDay? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: weekStartDate) else { return nil }
                let dayStart = calendar.startOfDay(for: date)
                return ScheduleWeekDay(
                    id: dayStart.timeIntervalSince1970,
                    date: dayStart,
                    title: weekDayTitle(for: dayStart),
                    isInDisplayedMonth: dayStart >= interval.start && dayStart < interval.end,
                    blocks: (grouped[weekStartDate]?[dayStart] ?? []).sorted { $0.startHour < $1.startHour }
                )
            }
            let allBlocks = days.flatMap(\.blocks)
            guard includeEmptyWeeks || !allBlocks.isEmpty else { return nil }
            let minimumHour = min(8, Int(floor(allBlocks.map(\.startHour).min() ?? 8)))
            let maximumHour = max(24, Int(ceil(allBlocks.map(\.endHour).max() ?? 24)))
            let baseTitle = weekRangeTitle(start: weekStartDate)
            return WeeklySchedulePage(
                id: weekStartDate.timeIntervalSince1970,
                title: titlePrefix.map { "\($0) \(baseTitle)" } ?? baseTitle,
                startHour: max(0, minimumHour),
                endHour: min(24, maximumHour),
                days: days
            )
        }
    }

    static func horizontalMonthPage(
        records: [TeachingLessonRecord],
        interval: DateInterval,
        occupiedRecords: [TeachingLessonRecord] = []
    ) -> WeeklySchedulePage {
        let calendar = Calendar.current
        var grouped: [Date: [Date: [ScheduleWeekBlock]]] = [:]
        appendBlocks(from: records, interval: interval, into: &grouped, occupied: false)
        appendBlocks(from: occupiedRecords, interval: interval, into: &grouped, occupied: true)

        var days: [ScheduleWeekDay] = []
        var cursor = calendar.startOfDay(for: interval.start)
        while cursor < interval.end {
            let day = cursor
            let blocks = grouped.values.flatMap { $0[day] ?? [] }.sorted { $0.startHour < $1.startHour }
            days.append(
                ScheduleWeekDay(
                    id: day.timeIntervalSince1970,
                    date: day,
                    title: monthDayTitle(for: day),
                    isInDisplayedMonth: true,
                    blocks: blocks
                )
            )
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? interval.end
        }

        let allBlocks = days.flatMap(\.blocks)
        let minimumHour = min(8, Int(floor(allBlocks.map(\.startHour).min() ?? 8)))
        let maximumHour = max(24, Int(ceil(allBlocks.map(\.endHour).max() ?? 24)))
        return WeeklySchedulePage(
            id: interval.start.timeIntervalSince1970,
            title: monthTitle(for: interval.start),
            startHour: max(0, minimumHour),
            endHour: min(24, maximumHour),
            days: days
        )
    }

    private static func appendBlocks(
        from records: [TeachingLessonRecord],
        interval: DateInterval,
        into grouped: inout [Date: [Date: [ScheduleWeekBlock]]],
        occupied: Bool
    ) {
        let calendar = Calendar.current
        for record in records {
            guard let rawStart = TeachingLessonStatisticsStore.date(from: record.startAt),
                  let rawEnd = TeachingLessonStatisticsStore.date(from: record.endAt),
                  rawStart < rawEnd,
                  rawEnd > interval.start,
                  rawStart < interval.end else {
                continue
            }
            let clippedStart = max(rawStart, interval.start)
            let clippedEnd = min(rawEnd, interval.end)
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
                        studentName: occupied ? "占用" : (record.studentName.isEmpty ? "未命名学生" : record.studentName),
                        institutionName: occupied ? "其他机构" : (record.institutionName.isEmpty ? "未命名机构" : record.institutionName),
                        colorHex: occupied ? "#FF3B30" : record.effectiveInstitutionColorHex,
                        timeText: timeRangeText(start: sliceStart, end: sliceEnd),
                        durationText: "\(formatHours(max(0, sliceEnd.timeIntervalSince(sliceStart) / 3600)))小时",
                        isOccupied: occupied,
                        institutionIconName: occupied ? nil : record.institutionIconName
                    )
                    grouped[weekStart, default: [:]][day, default: []].append(block)
                }
                day = nextDay
            }
        }
    }

    static func monthInterval(for date: Date) -> DateInterval {
        let start = monthStart(for: date)
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    static func currentWeekInterval() -> DateInterval {
        let start = weekStart(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    static func monthStart(for date: Date) -> Date {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return Calendar.current.date(from: components) ?? date
    }

    static func weekStart(for date: Date) -> Date {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let weekday = Calendar.current.component(.weekday, from: startOfDay)
        let daysFromMonday = (weekday + 5) % 7
        return Calendar.current.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
    }

    static func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }

    private static func matches(_ record: TeachingLessonRecord, filter: Filter) -> Bool {
        switch filter {
        case .all:
            return true
        case .institution(let id):
            return record.institutionID == id
        case .student(let id):
            return record.studentID == id
        }
    }

    private static func sortedRecordsByTime(_ records: [TeachingLessonRecord]) -> [TeachingLessonRecord] {
        records.sorted {
            (TeachingLessonStatisticsStore.date(from: $0.startAt) ?? .distantPast)
                < (TeachingLessonStatisticsStore.date(from: $1.startAt) ?? .distantPast)
        }
    }

    private static func hourValue(for date: Date, day: Date? = nil) -> Double {
        if let day, Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: day) {
            return 24
        }
        let hour = Double(Calendar.current.component(.hour, from: date))
        let minute = Double(Calendar.current.component(.minute, from: date))
        return hour + minute / 60
    }

    /// 统计模块唯一的时刻输出规则：24小时制，两位小时和分钟，不使用小数小时。
    static func clockText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func timeRangeText(start: Date, end: Date) -> String {
        "\(clockText(for: start))-\(clockText(for: end))"
    }

    private static func fullDayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    private static func weekdayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private static func formatTextLine(
        date: String,
        weekday: String,
        time: String,
        student: String,
        hours: String,
        widths: TextColumnWidths
    ) -> String {
        "\(paddedDisplay(date, width: widths.date)) | \(paddedDisplay(weekday, width: widths.weekday)) | \(paddedDisplay(time, width: widths.time)) | \(paddedDisplay(student, width: widths.student)) | \(hours)"
    }

    nonisolated private static func maxDisplayWidth(header: String, values: [String]) -> Int {
        ([header] + values).map(displayWidth(of:)).max() ?? displayWidth(of: header)
    }

    nonisolated private static func paddedDisplay(_ value: String, width: Int) -> String {
        value + String(repeating: " ", count: max(0, width - displayWidth(of: value)))
    }

    nonisolated private static func displayWidth(of value: String) -> Int {
        value.reduce(0) { partial, character in
            partial + (character.isASCII ? 1 : 2)
        }
    }

    private static func weekDayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "E M.d"
        return formatter.string(from: date)
    }

    private static func monthDayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "d E"
        return formatter.string(from: date)
    }

    private static func weekRangeTitle(start: Date) -> String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        return "\(shortDayTitle(for: start))-\(shortDayTitle(for: end))"
    }

    private static func shortDayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private static func formatHours(_ hours: Double) -> String {
        hours.rounded() == hours ? String(Int(hours)) : String(format: "%.1f", hours)
    }

    private static func formatMoney(_ money: Double) -> String {
        money.rounded() == money ? String(Int(money)) : String(format: "%.1f", money)
    }
}
