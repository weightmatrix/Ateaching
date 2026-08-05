import Foundation

// MARK: - 课时统计数据层 - v1 - Debug开关背后的纯JSON底座

/// 机构设置表中的一条机构记录；删除或改名机构不会回写已经存在的课单快照。
struct TeachingInstitutionRecord: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var colorHex: String
    var defaultPriceForTwoHours: Double?
    var note: String
    var iconName: String?

    nonisolated init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = TeachingLessonStatisticsStore.defaultInstitutionColorHex,
        defaultPriceForTwoHours: Double? = nil,
        note: String = "",
        iconName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.defaultPriceForTwoHours = defaultPriceForTwoHours
        self.note = note
        self.iconName = iconName
    }

    var normalizedName: String {
        TeachingLessonStatisticsStore.normalizedName(name)
    }

    var effectiveColorHex: String {
        TeachingLessonStatisticsStore.normalizedColorHex(colorHex)
    }
}

/// 成课JSON中的一节课快照；学生、机构、价格和颜色按排课转入历史时的状态保存。
struct TeachingLessonRecord: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var startAt: String
    var endAt: String
    var studentID: UUID?
    var studentName: String
    var gradeCode: Int?
    var institutionID: UUID?
    var institutionName: String
    var priceForTwoHours: Double?
    var institutionColorHex: String?
    var institutionIconName: String?

    nonisolated init(
        id: UUID = UUID(),
        startAt: String,
        endAt: String,
        studentID: UUID? = nil,
        studentName: String,
        gradeCode: Int? = nil,
        institutionID: UUID? = nil,
        institutionName: String,
        priceForTwoHours: Double? = nil,
        institutionColorHex: String? = nil,
        institutionIconName: String? = nil
    ) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.studentID = studentID
        self.studentName = studentName
        self.gradeCode = gradeCode
        self.institutionID = institutionID
        self.institutionName = institutionName
        self.priceForTwoHours = priceForTwoHours
        self.institutionColorHex = institutionColorHex
        self.institutionIconName = institutionIconName
    }

    var effectiveInstitutionColorHex: String {
        TeachingLessonStatisticsStore.normalizedColorHex(institutionColorHex)
    }
}

/// 课时统计的数据层；集中负责机构JSON、成课JSON、冲突检查和改名同步。
enum TeachingLessonStatisticsStore {
    enum LessonStatisticsError: LocalizedError {
        case emptyInstitutionName
        case duplicateInstitutionName(String)
        case invalidLessonTime(startAt: String, endAt: String)

        var errorDescription: String? {
            switch self {
            case .emptyInstitutionName:
                return "机构名称不能为空。"
            case .duplicateInstitutionName(let name):
                return "机构名称“\(name)”已经存在。"
            case let .invalidLessonTime(startAt, endAt):
                return "课时开始或结束时间不是有效的ISO8601格式：\(startAt) - \(endAt)"
            }
        }
    }

    nonisolated static let defaultInstitutionColorHex = "#808080"

    private static let institutionFileName = "Setting-机构.json"
    private static let lessonRecordsFolderName = "课单"
    private static let lessonRecordsFileName = "LessonRecords.json"

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    static func loadInstitutions(fileManager: FileManager = .default) throws -> [TeachingInstitutionRecord] {
        let url = try institutionSettingsFileURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode([TeachingInstitutionRecord].self, from: data)
    }

    static func saveInstitutions(
        _ institutions: [TeachingInstitutionRecord],
        fileManager: FileManager = .default
    ) throws {
        try validateInstitutionNames(institutions)
        let url = try institutionSettingsFileURL(fileManager: fileManager)
        let data = try encoder.encode(institutions.map(normalizedInstitution))
        try data.write(to: url, options: .atomic)
    }

    static func loadLessonRecords(fileManager: FileManager = .default) throws -> [TeachingLessonRecord] {
        let url = try lessonRecordsFileURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode([TeachingLessonRecord].self, from: data)
    }

    static func saveLessonRecords(
        _ records: [TeachingLessonRecord],
        fileManager: FileManager = .default
    ) throws {
        try records.forEach(validateLessonTime)
        let url = try lessonRecordsFileURL(fileManager: fileManager)
        let data = try encoder.encode(records.map(normalizedLessonRecord))
        try data.write(to: url, options: .atomic)
    }

    static func appendLessonRecord(
        _ record: TeachingLessonRecord,
        fileManager: FileManager = .default
    ) throws {
        var records = try loadLessonRecords(fileManager: fileManager)
        records.append(normalizedLessonRecord(record))
        try saveLessonRecords(records, fileManager: fileManager)
    }

    static func lessonRecordsConflicting(
        with record: TeachingLessonRecord,
        in records: [TeachingLessonRecord],
        excluding excludedID: UUID? = nil
    ) -> [TeachingLessonRecord] {
        guard let newStart = date(from: record.startAt),
              let newEnd = date(from: record.endAt),
              newStart < newEnd else {
            return []
        }
        return records.filter { existing in
            guard existing.id != record.id,
                  existing.id != excludedID,
                  let oldStart = date(from: existing.startAt),
                  let oldEnd = date(from: existing.endAt),
                  oldStart < oldEnd else {
                return false
            }
            return newStart < oldEnd && newEnd > oldStart
        }
    }

    static func updateInstitutionNameInLessonRecords(
        institutionID: UUID,
        newName: String,
        fileManager: FileManager = .default
    ) throws {
        var records = try loadLessonRecords(fileManager: fileManager)
        var didChange = false
        for index in records.indices {
            guard records[index].institutionID == institutionID else { continue }
            records[index].institutionName = normalizedName(newName)
            didChange = true
        }
        if didChange {
            try saveLessonRecords(records, fileManager: fileManager)
        }
    }

    static func updateStudentNameInLessonRecords(
        studentID: UUID,
        newName: String,
        fileManager: FileManager = .default
    ) throws {
        var records = try loadLessonRecords(fileManager: fileManager)
        var didChange = false
        for index in records.indices {
            guard records[index].studentID == studentID else { continue }
            records[index].studentName = normalizedName(newName)
            didChange = true
        }
        if didChange {
            try saveLessonRecords(records, fileManager: fileManager)
        }
    }

    static func initializeStorageIfNeeded(fileManager: FileManager = .default) throws {
        let institutionURL = try institutionSettingsFileURL(fileManager: fileManager)
        if !fileManager.fileExists(atPath: institutionURL.path) {
            try saveInstitutions([], fileManager: fileManager)
        }

        let lessonURL = try lessonRecordsFileURL(fileManager: fileManager)
        if !fileManager.fileExists(atPath: lessonURL.path) {
            try saveLessonRecords([], fileManager: fileManager)
        }
    }

    static func institutionSettingsFileURL(fileManager: FileManager = .default) throws -> URL {
        let rootURL = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let settingsURL = rootURL.appendingPathComponent(ArchiveStorage.settingsFolderName, isDirectory: true)
        try fileManager.createDirectory(at: settingsURL, withIntermediateDirectories: true)
        return settingsURL.appendingPathComponent(institutionFileName, isDirectory: false)
    }

    static func lessonRecordsFileURL(fileManager: FileManager = .default) throws -> URL {
        let folderURL = try lessonRecordsFolderURL(fileManager: fileManager)
        return folderURL.appendingPathComponent(lessonRecordsFileName, isDirectory: false)
    }

    static func lessonRecordsFolderURL(fileManager: FileManager = .default) throws -> URL {
        let rootURL = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let systemURL = rootURL.appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
        let lessonRecordsURL = systemURL.appendingPathComponent(lessonRecordsFolderName, isDirectory: true)
        try fileManager.createDirectory(at: lessonRecordsURL, withIntermediateDirectories: true)
        return lessonRecordsURL
    }

    nonisolated static func makeISO8601String(from date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    nonisolated static func date(from iso8601String: String) -> Date? {
        iso8601Formatter.date(from: iso8601String) ?? iso8601FormatterWithoutFractionalSeconds.date(from: iso8601String)
    }

    static func validateNewInstitutionName(
        _ name: String,
        excluding id: UUID? = nil,
        in institutions: [TeachingInstitutionRecord]
    ) throws {
        let candidate = normalizedName(name)
        guard !candidate.isEmpty else {
            throw LessonStatisticsError.emptyInstitutionName
        }
        if institutions.contains(where: { institution in
            institution.id != id && normalizedName(institution.name) == candidate
        }) {
            throw LessonStatisticsError.duplicateInstitutionName(candidate)
        }
    }

    nonisolated static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func normalizedColorHex(_ value: String?) -> String {
        let color = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return color.isEmpty ? defaultInstitutionColorHex : color
    }

    nonisolated private static var iso8601Formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    nonisolated private static var iso8601FormatterWithoutFractionalSeconds: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func validateInstitutionNames(_ institutions: [TeachingInstitutionRecord]) throws {
        var names = Set<String>()
        for institution in institutions {
            let name = normalizedName(institution.name)
            guard !name.isEmpty else {
                throw LessonStatisticsError.emptyInstitutionName
            }
            guard names.insert(name).inserted else {
                throw LessonStatisticsError.duplicateInstitutionName(name)
            }
        }
    }

    nonisolated private static func validateLessonTime(_ record: TeachingLessonRecord) throws {
        guard let start = date(from: record.startAt),
              let end = date(from: record.endAt),
              start < end else {
            throw LessonStatisticsError.invalidLessonTime(startAt: record.startAt, endAt: record.endAt)
        }
    }

    nonisolated private static func normalizedInstitution(_ institution: TeachingInstitutionRecord) -> TeachingInstitutionRecord {
        TeachingInstitutionRecord(
            id: institution.id,
            name: normalizedName(institution.name),
            colorHex: normalizedColorHex(institution.colorHex),
            defaultPriceForTwoHours: institution.defaultPriceForTwoHours,
            note: institution.note.trimmingCharacters(in: .whitespacesAndNewlines),
            iconName: institution.iconName?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    nonisolated private static func normalizedLessonRecord(_ record: TeachingLessonRecord) -> TeachingLessonRecord {
        TeachingLessonRecord(
            id: record.id,
            startAt: record.startAt,
            endAt: record.endAt,
            studentID: record.studentID,
            studentName: normalizedName(record.studentName),
            gradeCode: record.gradeCode,
            institutionID: record.institutionID,
            institutionName: normalizedName(record.institutionName),
            priceForTwoHours: record.priceForTwoHours,
            institutionColorHex: normalizedColorHex(record.institutionColorHex),
            institutionIconName: record.institutionIconName
        )
    }
}
