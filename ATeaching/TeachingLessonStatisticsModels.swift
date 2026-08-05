import Foundation

// MARK: - 课时统计视图模型 - v1 - 只承载页面派生数据，不负责读写JSON

/// 课表页的整月汇总结果：总费用、机构汇总、按日期分组的课程明细。
struct ScheduleSummary {
    var totalFee: Double
    var institutionSummaries: [InstitutionScheduleSummary]
    var days: [ScheduleDayGroup]
}

/// 课表页中单个机构在某月的总课时和总课费。
struct InstitutionScheduleSummary: Identifiable {
    var id: String
    var institutionName: String
    var colorHex: String
    var hours: Double
    var fee: Double
}

/// 机构列表右侧同时展示的本月与上月统计。
struct InstitutionMonthPairSummary {
    var currentMonth: InstitutionMonthSummary
    var previousMonth: InstitutionMonthSummary
}

/// 单个机构在单个月份内的课时和课费合计。
struct InstitutionMonthSummary {
    var hours: Double
    var fee: Double
}

/// 课表文字样式中的某一天及其课程列表。
struct ScheduleDayGroup: Identifiable {
    var id: TimeInterval
    var title: String
    var lessons: [LessonDisplayItem]
}

/// 课表文字样式使用的单节课程展示项，时间已按当前月份裁切。
struct LessonDisplayItem: Identifiable {
    var id: UUID
    var sortDate: Date
    var day: Date
    var timeText: String
    var studentName: String
    var institutionName: String
    var institutionID: UUID?
    var colorHex: String
    var hours: Double
    var fee: Double
}

/// 课表图片样式的一周页面，负责把一个自然周拆成日列。
struct WeeklySchedulePage: Identifiable {
    var id: TimeInterval
    var title: String
    var startHour: Int
    var endHour: Int
    var days: [ScheduleWeekDay]
}

/// 课表图片样式中的一天列，保存该日是否属于当前展示月份。
struct ScheduleWeekDay: Identifiable {
    var id: TimeInterval
    var date: Date
    var title: String
    var isInDisplayedMonth: Bool
    var blocks: [ScheduleWeekBlock]
}

/// 课表图片样式中的课程色块，跨日课程会在生成时切成多个色块。
struct ScheduleWeekBlock: Identifiable {
    var id: String
    var startHour: Double
    var endHour: Double
    var studentName: String
    var institutionName: String
    var colorHex: String
    var timeText: String = ""
    var durationText: String = ""
    var isOccupied: Bool = false
    var institutionIconName: String? = nil
}

/// 机构“数据”弹窗的整月汇总结果。
struct InstitutionDataSummary {
    var totalHours: Double
    var totalFee: Double
    var items: [InstitutionDataItem]
}

/// 机构“数据”弹窗中用于空格对齐的显示宽度。
struct InstitutionDataColumnWidths {
    var date: Int
    var weekday: Int = 0
    var time: Int
    var student: Int
}

/// 机构“数据”弹窗中的单节课程明细。
struct InstitutionDataItem: Identifiable {
    var id: UUID
    var sortDate: Date
    var dateText: String
    var weekdayText: String = ""
    var timeText: String
    var studentName: String
    var colorHex: String
    var hours: Double
    var fee: Double
}

/// 手动添加或修改课程时从弹窗返回给主页面的草稿。
struct TeachingLessonEditorDraft {
    var sourceLesson: TeachingLessonRecord?
    var studentID: UUID?
    var start: Date
    var end: Date
}

/// 课单手动编辑的用户可见错误。
enum LessonEditError: LocalizedError {
    case missingStudent
    case missingStudentStatistics
    case invalidTimeRange
    case conflict

    var errorDescription: String? {
        switch self {
        case .missingStudent:
            return "请选择学生。"
        case .missingStudentStatistics:
            return "该学生没有完整的统计设置，请先到学生初始化第6步设置机构和2小时价格。"
        case .invalidTimeRange:
            return "结束时间必须晚于开始时间。"
        case .conflict:
            return "时间冲突：newStart < oldEnd && newEnd > oldStart。"
        }
    }
}
