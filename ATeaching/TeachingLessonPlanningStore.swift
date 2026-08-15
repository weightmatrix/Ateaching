import Foundation

// MARK: - 排课/周表数据层 - v1 - 复用课单结构并分别落盘到排课.json、周表.json

/// 排课与周表使用和正式课单相同的课程快照结构，方便插入周表时直接拷贝到上课单。
enum TeachingLessonPlanningStore {
    enum PlanningKind {
        case planning
        case weekly

        var fileName: String {
            switch self {
            case .planning: return "排课.json"
            case .weekly: return "周表.json"
            }
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    static func load(_ kind: PlanningKind, fileManager: FileManager = .default) throws -> [TeachingLessonRecord] {
        let url = try fileURL(kind, fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode([TeachingLessonRecord].self, from: data)
            .map(TeachingLessonPlanningPlaceholder.normalizedRecord)
    }

    static func save(_ records: [TeachingLessonRecord], kind: PlanningKind, fileManager: FileManager = .default) throws {
        let url = try fileURL(kind, fileManager: fileManager)
        let data = try encoder.encode(records.map(TeachingLessonPlanningPlaceholder.normalizedRecord))
        try data.write(to: url, options: .atomic)
    }

    static func fileURL(_ kind: PlanningKind, fileManager: FileManager = .default) throws -> URL {
        try TeachingLessonStatisticsStore.lessonRecordsFolderURL(fileManager: fileManager)
            .appendingPathComponent(kind.fileName, isDirectory: false)
    }

    static func promotePastPlanningRecordsToLessonHistory(
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> Int {
        var planning = try load(.planning, fileManager: fileManager)
        let ready = planning.filter { record in
            guard !TeachingLessonPlanningPlaceholder.isPlaceholder(record),
                  let start = TeachingLessonStatisticsStore.date(from: record.startAt) else { return false }
            return start < now
        }
        guard !ready.isEmpty else { return 0 }

        var lessons = try TeachingLessonStatisticsStore.loadLessonRecords(fileManager: fileManager)
        for record in ready where !lessons.contains(where: { $0.id == record.id }) {
            let conflicts = TeachingLessonStatisticsStore.lessonRecordsConflicting(with: record, in: lessons)
            guard conflicts.isEmpty else { continue }
            lessons.append(record)
        }
        planning.removeAll { record in ready.contains(where: { $0.id == record.id }) }
        try TeachingLessonStatisticsStore.saveLessonRecords(lessons, fileManager: fileManager)
        try save(planning, kind: .planning, fileManager: fileManager)
        return ready.count
    }
}

/// 排课中的占位块不是学生课程，不参与预计课时和预计收入。
/// UUID沿用旧数据，显示名称可以安全迁移，不依赖文字判断身份。
enum TeachingLessonPlanningPlaceholder {
    nonisolated static let studentID = UUID(uuidString: "5A6DB295-6BB5-4D1C-84E8-A19D9490E5AD")!
    nonisolated static let institutionID = UUID(uuidString: "7E7E9A8C-18DE-4C42-B569-E7C80431D9A4")!
    nonisolated static let studentName = "占位"
    nonisolated static let institutionName = "空课"

    nonisolated static func isPlaceholder(_ record: TeachingLessonRecord) -> Bool {
        record.studentID == studentID || record.institutionID == institutionID
    }

    nonisolated static func normalizedRecord(_ record: TeachingLessonRecord) -> TeachingLessonRecord {
        guard isPlaceholder(record) else { return record }
        var normalized = record
        normalized.studentID = studentID
        normalized.studentName = studentName
        normalized.institutionID = institutionID
        normalized.institutionName = institutionName
        normalized.priceForTwoHours = nil
        return normalized
    }
}
