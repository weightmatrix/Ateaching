import SwiftUI

// MARK: - 课时统计机构列表 - v1 - 独立展示机构、默认价、本月/上月汇总和右键动作

/// 机构页只负责展示与触发动作；机构增删改、复制导出仍由统计主页面统一调度。
struct TeachingInstitutionListPanel: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let institutions: [TeachingInstitutionRecord]
    let lessonRecords: [TeachingLessonRecord]
    let displayedMonth: Date
    let onEdit: (TeachingInstitutionRecord) -> Void
    let onDelete: (TeachingInstitutionRecord) -> Void
    let onData: (TeachingInstitutionRecord) -> Void
    let onCopyMonth: (TeachingInstitutionRecord, Int) -> Void
    let onExportMonth: (TeachingInstitutionRecord, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if institutions.isEmpty {
                ContentUnavailableView("暂无机构", systemImage: "building.2")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sortedInstitutions) { institution in
                            institutionRow(institution)
                        }
                    }
                }
            }
        }
    }

    private var sortedInstitutions: [TeachingInstitutionRecord] {
        institutions.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    @ViewBuilder
    private func institutionRow(_ institution: TeachingInstitutionRecord) -> some View {
        let summary = monthlySummary(for: institution)
        Group {
            if usesCompactLayout {
                compactInstitutionRow(institution, summary: summary)
            } else {
                regularInstitutionRow(institution, summary: summary)
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
            institutionContextMenu(institution)
        }
    }

    private func regularInstitutionRow(
        _ institution: TeachingInstitutionRecord,
        summary: InstitutionMonthPairSummary
    ) -> some View {
        HStack(spacing: 12) {
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
            .frame(minWidth: 150, alignment: .leading)

            HStack(spacing: 8) {
                if summary.currentMonth.fee > 0 {
                    moneyBadge(formatMoney(summary.currentMonth.fee), color: .yellow)
                }
                if summary.previousMonth.fee > 0 {
                    moneyBadge(formatMoney(summary.previousMonth.fee), color: .orange)
                }
            }
            .frame(minWidth: 150, alignment: .leading)

            Spacer(minLength: 12)

            HStack(alignment: .firstTextBaseline, spacing: 18) {
                metricColumn("默认价", priceValue(institution.defaultPriceForTwoHours))
                metricColumn("本月", monthValue(summary.currentMonth))
                metricColumn("上月", monthValue(summary.previousMonth))
            }
            .frame(minWidth: 310, alignment: .trailing)
        }
    }

    private func compactInstitutionRow(
        _ institution: TeachingInstitutionRecord,
        summary: InstitutionMonthPairSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(statisticsColor(fromHex: institution.effectiveColorHex))
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(institution.name)
                        .font(.system(size: 15, weight: .semibold))
                    if !institution.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(institution.note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }

            if summary.currentMonth.fee > 0 || summary.previousMonth.fee > 0 {
                HStack(spacing: 8) {
                    if summary.currentMonth.fee > 0 {
                        moneyBadge(formatMoney(summary.currentMonth.fee), color: .yellow)
                    }
                    if summary.previousMonth.fee > 0 {
                        moneyBadge(formatMoney(summary.previousMonth.fee), color: .orange)
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                compactMetricColumn("默认价", priceValue(institution.defaultPriceForTwoHours))
                compactMetricColumn("本月", monthValue(summary.currentMonth))
                compactMetricColumn("上月", monthValue(summary.previousMonth))
            }
        }
    }

    @ViewBuilder
    private func institutionContextMenu(_ institution: TeachingInstitutionRecord) -> some View {
        Button("更改") { onEdit(institution) }
        Button("删除", role: .destructive) { onDelete(institution) }
        Button("数据") { onData(institution) }
        Button("复制文字·上月课") { onCopyMonth(institution, -1) }
        Button("复制文字·当月课") { onCopyMonth(institution, 0) }
        Button("导出图片·上月课") { onExportMonth(institution, -1) }
        Button("导出图片·当月课") { onExportMonth(institution, 0) }
    }

    private func moneyBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .bold, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.28))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(color.opacity(0.5), lineWidth: 1)
            )
    }

    private func metricColumn(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 92, alignment: .trailing)
    }

    private func compactMetricColumn(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var usesCompactLayout: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private func monthlySummary(for institution: TeachingInstitutionRecord) -> InstitutionMonthPairSummary {
        let currentStart = TeachingLessonScheduleBuilder.monthStart(for: displayedMonth)
        let previousStart = Calendar.current.date(byAdding: .month, value: -1, to: currentStart) ?? currentStart
        return InstitutionMonthPairSummary(
            currentMonth: summary(for: institution, monthStart: currentStart),
            previousMonth: summary(for: institution, monthStart: previousStart)
        )
    }

    private func summary(for institution: TeachingInstitutionRecord, monthStart: Date) -> InstitutionMonthSummary {
        let monthEnd = Calendar.current.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        var hours = 0.0
        var fee = 0.0
        for record in lessonRecords {
            guard belongs(record, to: institution),
                  let start = TeachingLessonStatisticsStore.date(from: record.startAt),
                  let end = TeachingLessonStatisticsStore.date(from: record.endAt),
                  start < end,
                  end > monthStart,
                  start < monthEnd else { continue }
            let clippedStart = max(start, monthStart)
            let clippedEnd = min(end, monthEnd)
            let itemHours = max(0, clippedEnd.timeIntervalSince(clippedStart) / 3600)
            hours += itemHours
            fee += (record.priceForTwoHours ?? 0) * itemHours / 2
        }
        return InstitutionMonthSummary(hours: hours, fee: fee)
    }

    private func belongs(_ record: TeachingLessonRecord, to institution: TeachingInstitutionRecord) -> Bool {
        if let recordInstitutionID = record.institutionID {
            return recordInstitutionID == institution.id
        }
        return TeachingLessonStatisticsStore.normalizedName(record.institutionName) == institution.normalizedName
    }

    private func priceValue(_ price: Double?) -> String {
        guard let price else { return "-" }
        return formatMoney(price)
    }

    private func monthValue(_ summary: InstitutionMonthSummary) -> String {
        "\(formatHours(summary.hours))h/\(formatMoney(summary.fee))"
    }

    private func formatHours(_ hours: Double) -> String {
        hours.rounded() == hours ? String(Int(hours)) : String(format: "%.1f", hours)
    }

    private func formatMoney(_ money: Double) -> String {
        money.rounded() == money ? String(Int(money)) : String(format: "%.1f", money)
    }
}
