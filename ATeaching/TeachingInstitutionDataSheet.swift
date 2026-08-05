import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - 机构数据弹窗 - v1 - 展示、复制、导出某机构单月课程明细

/// 机构右键“数据”打开的弹窗；所有统计都从上课单快照实时计算。
struct TeachingInstitutionDataSheet: View {
    @Environment(\.dismiss) private var dismiss

    let institution: TeachingInstitutionRecord
    let lessonRecords: [TeachingLessonRecord]

    @State private var displayedMonth = Date()
    @State private var statusMessage = ""

    @ViewBuilder
    var body: some View {
        #if os(macOS)
        dataContent
            .frame(minWidth: 680, minHeight: 520)
        #else
        dataContent
        #endif
    }

    private var dataContent: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                monthControls

                let summary = buildSummary()
                Text("机构：\(institution.name)")
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 8) {
                    Text("总课时：\(formatHours(summary.totalHours))小时")
                    Text("|")
                        .foregroundStyle(.secondary)
                    Text("总课费：\(formatMoney(summary.totalFee))元")
                }
                .font(.system(size: 15, weight: .semibold, design: .monospaced))

                if summary.items.isEmpty {
                    ContentUnavailableView("本月暂无课程", systemImage: "calendar.badge.clock")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 7) {
                            let widths = columnWidths(for: summary)
                            Text(institutionDataHeaderLine(widths: widths))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                            ForEach(summary.items) { item in
                                Text(institutionDataLine(for: item, widths: widths))
                                    .font(.system(size: 13, design: .monospaced))
                                    .lineLimit(nil)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(statisticsColor(fromHex: item.colorHex).opacity(0.16))
                                    )
                            }
                        }
                        .frame(minWidth: 620, alignment: .leading)
                    }
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .navigationTitle("\(institution.name) 数据")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button("复制") {
                        copySummaryText()
                    }
                    Button("导出") {
                        exportSummaryImage()
                    }
                }
            }
        }
    }

    private var monthControls: some View {
        HStack(spacing: 8) {
            Button {
                displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: monthStart(for: displayedMonth)) ?? displayedMonth
            } label: {
                Image(systemName: "minus")
            }
            .appGlassButtonStyle()

            Text(monthTitle(for: displayedMonth))
                .font(.system(size: 15, weight: .semibold))
                .frame(minWidth: 120)

            Button {
                displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: monthStart(for: displayedMonth)) ?? displayedMonth
            } label: {
                Image(systemName: "plus")
            }
            .appGlassButtonStyle()
            .disabled(!canMoveToNextMonth(from: displayedMonth))

            Spacer()
        }
    }

    private func buildSummary() -> InstitutionDataSummary {
        let calendar = Calendar.current
        let start = monthStart(for: displayedMonth)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start

        let items = lessonRecords.compactMap { record -> InstitutionDataItem? in
            guard belongsToInstitution(record),
                  let lessonStart = TeachingLessonStatisticsStore.date(from: record.startAt),
                  let lessonEnd = TeachingLessonStatisticsStore.date(from: record.endAt),
                  lessonStart < lessonEnd,
                  lessonEnd > start,
                  lessonStart < end else {
                return nil
            }

            let clippedStart = max(lessonStart, start)
            let clippedEnd = min(lessonEnd, end)
            let hours = max(0, clippedEnd.timeIntervalSince(clippedStart) / 3600)
            let fee = (record.priceForTwoHours ?? 0) * hours / 2
            return InstitutionDataItem(
                id: record.id,
                sortDate: clippedStart,
                dateText: fullDayTitle(for: clippedStart),
                weekdayText: weekdayTitle(for: clippedStart),
                timeText: lessonTimeText(start: clippedStart, end: clippedEnd),
                studentName: record.studentName.isEmpty ? "未命名学生" : record.studentName,
                colorHex: record.effectiveInstitutionColorHex,
                hours: hours,
                fee: fee
            )
        }
        .sorted { $0.sortDate < $1.sortDate }

        return InstitutionDataSummary(
            totalHours: items.reduce(0) { $0 + $1.hours },
            totalFee: items.reduce(0) { $0 + $1.fee },
            items: items
        )
    }

    private func belongsToInstitution(_ record: TeachingLessonRecord) -> Bool {
        if let recordInstitutionID = record.institutionID {
            return recordInstitutionID == institution.id
        }
        return TeachingLessonStatisticsStore.normalizedName(record.institutionName) == institution.normalizedName
    }

    private func copySummaryText() {
        let text = plainTextSummary()
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        statusMessage = "机构数据已复制。"
    }

    @MainActor
    private func exportSummaryImage() {
        let summary = buildSummary()
        let snapshot = TeachingInstitutionDataExportSnapshotView(
            institutionName: institution.name,
            monthTitle: monthTitle(for: displayedMonth),
            summary: summary
        )
        let renderer = ImageRenderer(content: snapshot.frame(width: 1200).padding(24).background(Color.white))
        renderer.scale = 2

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
                .appendingPathComponent("\(sanitizedFilename(institution.name))_\(monthTitle(for: displayedMonth)).png")
            try TeachingDocumentExportService.exportToWeChat(
                sourceFileURL: sourceURL,
                descriptor: TeachingDocumentExportDescriptor(
                    displayName: "机构数据",
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

    private func plainTextSummary() -> String {
        let summary = buildSummary()
        let widths = columnWidths(for: summary)
        var lines = [
            "机构：\(institution.name)",
            "总课时：\(formatHours(summary.totalHours))小时 | 总课费：\(formatMoney(summary.totalFee))元",
            institutionDataHeaderLine(widths: widths)
        ]
        lines.append(contentsOf: summary.items.map { item in
            institutionDataLine(for: item, widths: widths)
        })
        return lines.joined(separator: "\n")
    }

    private func monthStart(for date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
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

    private func fullDayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    private func weekdayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private func lessonTimeText(start: Date, end: Date) -> String {
        TeachingLessonScheduleBuilder.timeRangeText(start: start, end: end)
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

    private func sanitizedFilename(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let sanitized = value.components(separatedBy: invalidCharacters).joined(separator: "-")
        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "机构数据" : sanitized
    }

    private func columnWidths(for summary: InstitutionDataSummary) -> InstitutionDataColumnWidths {
        InstitutionDataColumnWidths(
            date: maxDisplayWidth(header: "日期", values: summary.items.map(\.dateText)),
            weekday: maxDisplayWidth(header: "星期", values: summary.items.map(\.weekdayText)),
            time: maxDisplayWidth(header: "时间", values: summary.items.map(\.timeText)),
            student: maxDisplayWidth(header: "学生", values: summary.items.map(\.studentName))
        )
    }

    private func institutionDataHeaderLine(widths: InstitutionDataColumnWidths) -> String {
        formatInstitutionDataLine(date: "日期", weekday: "星期", time: "时间", student: "学生", hours: "小时", widths: widths)
    }

    private func institutionDataLine(for item: InstitutionDataItem, widths: InstitutionDataColumnWidths) -> String {
        formatInstitutionDataLine(
            date: item.dateText,
            weekday: item.weekdayText,
            time: item.timeText,
            student: item.studentName,
            hours: "\(formatHours(item.hours))小时",
            widths: widths
        )
    }

    private func formatInstitutionDataLine(
        date: String,
        weekday: String,
        time: String,
        student: String,
        hours: String,
        widths: InstitutionDataColumnWidths
    ) -> String {
        "\(paddedDisplay(date, width: widths.date)) | \(paddedDisplay(weekday, width: widths.weekday)) | \(paddedDisplay(time, width: widths.time)) | \(paddedDisplay(student, width: widths.student)) | \(hours)"
    }

    private func maxDisplayWidth(header: String, values: [String]) -> Int {
        ([header] + values).map(displayWidth(of:)).max() ?? displayWidth(of: header)
    }

    private func paddedDisplay(_ value: String, width: Int) -> String {
        value + String(repeating: " ", count: max(0, width - displayWidth(of: value)))
    }

    private func displayWidth(of value: String) -> Int {
        value.reduce(0) { partial, character in
            partial + (character.isASCII ? 1 : 2)
        }
    }
}

/// 机构“数据”导出图片用快照；和弹窗共享空格对齐规则，避免复制和图片不一致。
struct TeachingInstitutionDataExportSnapshotView: View {
    let institutionName: String
    let monthTitle: String
    let summary: InstitutionDataSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(institutionName) 数据")
                    .font(.system(size: 32, weight: .bold))
                Text(monthTitle)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text("总课时：\(formatHours(summary.totalHours))小时 | 总课费：\(formatMoney(summary.totalFee))元")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))

            VStack(alignment: .leading, spacing: 8) {
                let widths = columnWidths(for: summary)
                Text(formatInstitutionDataLine(date: "日期", weekday: "星期", time: "时间", student: "学生", hours: "小时", widths: widths))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))

                ForEach(summary.items) { item in
                    Text(formatInstitutionDataLine(
                        date: item.dateText,
                        weekday: item.weekdayText,
                        time: item.timeText,
                        student: item.studentName,
                        hours: "\(formatHours(item.hours))小时",
                        widths: widths
                    ))
                    .font(.system(size: 15, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(statisticsColor(fromHex: item.colorHex).opacity(0.14))
                    )
                }
            }

            if summary.items.isEmpty {
                Text("本月暂无课程")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .foregroundStyle(Color.black)
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

    private func columnWidths(for summary: InstitutionDataSummary) -> InstitutionDataColumnWidths {
        InstitutionDataColumnWidths(
            date: maxDisplayWidth(header: "日期", values: summary.items.map(\.dateText)),
            weekday: maxDisplayWidth(header: "星期", values: summary.items.map(\.weekdayText)),
            time: maxDisplayWidth(header: "时间", values: summary.items.map(\.timeText)),
            student: maxDisplayWidth(header: "学生", values: summary.items.map(\.studentName))
        )
    }

    private func formatInstitutionDataLine(
        date: String,
        weekday: String,
        time: String,
        student: String,
        hours: String,
        widths: InstitutionDataColumnWidths
    ) -> String {
        "\(paddedDisplay(date, width: widths.date)) | \(paddedDisplay(weekday, width: widths.weekday)) | \(paddedDisplay(time, width: widths.time)) | \(paddedDisplay(student, width: widths.student)) | \(hours)"
    }

    private func maxDisplayWidth(header: String, values: [String]) -> Int {
        ([header] + values).map(displayWidth(of:)).max() ?? displayWidth(of: header)
    }

    private func paddedDisplay(_ value: String, width: Int) -> String {
        value + String(repeating: " ", count: max(0, width - displayWidth(of: value)))
    }

    private func displayWidth(of value: String) -> Int {
        value.reduce(0) { partial, character in
            partial + (character.isASCII ? 1 : 2)
        }
    }
}
