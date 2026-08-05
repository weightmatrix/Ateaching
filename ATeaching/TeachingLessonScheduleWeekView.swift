import SwiftUI

// MARK: - 课时统计周课表视图 - v1 - 负责图片样式课表的网格渲染

enum TeachingScheduleExportLayout {
    case month
    case horizontalMonth
    case weeklyTemplate
}

enum TeachingScheduleExportSizing {
    static let exportRowHeight: CGFloat = 36.7
    static let exportAxisWidth: CGFloat = 34
    static let exportColumnSpacing: CGFloat = 6
    static let exportGridPadding: CGFloat = 10
    static let exportHeaderHeight: CGFloat = 30
    private static let snapshotPadding: CGFloat = 24
    private static let horizontalMonthRightReserve: CGFloat = 80

    static func width(for pages: [WeeklySchedulePage], layout: TeachingScheduleExportLayout) -> CGFloat {
        guard layout == .horizontalMonth else { return 1200 }
        let dayCount = max(1, pages.first?.days.count ?? 31)
        let dayWidth = exportRowHeight * 1.68
        let gridWidth = exportAxisWidth
            + CGFloat(dayCount) * dayWidth
            + CGFloat(max(0, dayCount - 1)) * exportColumnSpacing
            + exportGridPadding * 2
        return max(1200, gridWidth + snapshotPadding * 2 + horizontalMonthRightReserve)
    }
}

/// 课表图片样式的一周网格；普通页面和导出图片共用同一个渲染结构。
struct TeachingScheduleWeekView: View {
    let page: WeeklySchedulePage
    let compact: Bool
    var showsWeekTitle = true
    var showsDayDate = true

    private var rowHeight: CGFloat { compact ? TeachingScheduleExportSizing.exportRowHeight : 28.5 }
    private var headerHeight: CGFloat { compact ? TeachingScheduleExportSizing.exportHeaderHeight : 30 }
    private var dayWidth: CGFloat { rowHeight * 1.68 }
    private var hourCount: Int { max(1, page.endHour - page.startHour) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsWeekTitle {
                Text(page.title)
                    .font(.system(size: compact ? 18 : 15, weight: .semibold))
            }

            HStack(alignment: .top, spacing: compact ? TeachingScheduleExportSizing.exportColumnSpacing : 6) {
                timeAxis
                ForEach(page.days) { day in
                    dayColumn(day)
                }
            }
        }
        .padding(compact ? TeachingScheduleExportSizing.exportGridPadding : 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(compact ? 1 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private var timeAxis: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: headerHeight)
            ForEach(page.startHour..<page.endHour, id: \.self) { hour in
                Text("\(hour)")
                    .font(.system(size: compact ? 12 : 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: compact ? TeachingScheduleExportSizing.exportAxisWidth : 34, height: rowHeight, alignment: .topTrailing)
            }
        }
    }

    private func dayColumn(_ day: ScheduleWeekDay) -> some View {
        VStack(spacing: 0) {
            Text(dayTitle(day))
                .font(.system(size: compact ? 13 : 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: headerHeight)
                .foregroundStyle(day.isInDisplayedMonth ? Color.primary : Color.secondary)

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    ForEach(page.startHour..<page.endHour, id: \.self) { hour in
                        Rectangle()
                            .fill(hour % 2 == 0 ? Color.primary.opacity(0.025) : Color.clear)
                            .frame(height: rowHeight)
                            .overlay(alignment: .top) {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.16))
                                    .frame(height: 1)
                            }
                    }
                }

                ForEach(day.blocks) { block in
                    scheduleBlock(block)
                }
            }
            .frame(height: CGFloat(hourCount) * rowHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
        }
        .frame(width: dayWidth)
        .opacity(day.isInDisplayedMonth ? 1 : 0.48)
    }

    private func scheduleBlock(_ block: ScheduleWeekBlock) -> some View {
        let start = min(max(block.startHour, Double(page.startHour)), Double(page.endHour))
        let end = min(max(block.endHour, Double(page.startHour)), Double(page.endHour))
        let top = CGFloat(start - Double(page.startHour)) * rowHeight
        let height = max(18, CGFloat(end - start) * rowHeight)

        return VStack(alignment: .leading, spacing: 2) {
            if block.isOccupied {
                Label("占用", systemImage: "nosign")
                    .font(.system(size: compact ? 16 : 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text(block.studentName)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.45)
                Text(block.institutionName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if !block.timeText.isEmpty {
                Text(block.timeText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if !block.durationText.isEmpty {
                Text(block.durationText)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(statisticsColor(fromHex: block.colorHex).opacity(block.isOccupied ? 0.78 : 0.32))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(statisticsColor(fromHex: block.colorHex).opacity(block.isOccupied ? 0.95 : 0.65), lineWidth: 1)
                )
        )
        .overlay {
            if let iconName = block.institutionIconName, !iconName.isEmpty, !block.isOccupied {
                Image(systemName: iconName)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.primary.opacity(0.14))
                    .frame(width: dayWidth * 0.8, height: height * 0.8)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 3)
        .offset(y: top)
    }

    private func dayTitle(_ day: ScheduleWeekDay) -> String {
        guard !showsDayDate else { return day.title }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "E"
        return formatter.string(from: day.date)
    }
}

/// 课表图片导出用快照，固定使用更适合导出的紧凑网格尺寸。
struct TeachingScheduleExportSnapshotView: View {
    let monthTitle: String
    let pages: [WeeklySchedulePage]
    var layout: TeachingScheduleExportLayout = .month
    var usesGradientBackground = false

    var body: some View {
        ZStack {
            if usesGradientBackground {
                LinearGradient(
                    colors: [
                        Color(red: 0.72, green: 0.88, blue: 0.72),
                        Color(red: 0.98, green: 0.82, blue: 0.36)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(0.55)
            } else {
                Color.white
            }

            VStack(alignment: layout == .weeklyTemplate ? .center : .leading, spacing: 18) {
                Text(layout == .weeklyTemplate ? "周课程表" : "\(monthTitle) 课表")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: layout == .weeklyTemplate ? .center : .leading)

                ForEach(pages) { page in
                    TeachingScheduleWeekView(
                        page: page,
                        compact: true,
                        showsWeekTitle: layout == .month,
                        showsDayDate: layout != .weeklyTemplate
                    )
                }
            }
            .padding(24)
        }
        .foregroundStyle(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: usesGradientBackground ? 28 : 0, style: .continuous))
    }
}
