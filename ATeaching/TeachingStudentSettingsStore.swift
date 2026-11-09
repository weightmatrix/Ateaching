import Foundation

// MARK: - 学生设置存储 - v4 - 持久化授课快照并支持功能开关与学生级覆盖配置
nonisolated enum TeachingStudentSettingsStore {
    private static let fileName = "setting-students"
    private static let legacySystemFileName = "setting-studentsystem"
    private static let legacyLessonPlanFileName = "setting-lessonplansystem"
    private static let legacyFeatureFlagsFileName = "setting-teaching-featureflags"
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private static let decoder = JSONDecoder()

    enum StoreError: LocalizedError {
        case synchronizationPending
        case fileMissing
        case invalidData

        var errorDescription: String? {
            switch self {
            case .synchronizationPending:
                return "学生设置正在从 iCloud 同步，本次不会覆盖任何数据。"
            case .fileMissing:
                return "尚未取得 iCloud 中的学生设置文件。"
            case .invalidData:
                return "学生设置文件无法解析，已保留原文件且未执行重置。"
            }
        }
    }

    static func loadStudents(fileManager: FileManager = .default) throws -> [TeachingStudentItem] {
        let snapshot = try loadSnapshot(fileManager: fileManager)
        return snapshot.students
    }

    static func loadFeatureFlags(fileManager: FileManager = .default) throws -> TeachingFeatureFlags {
        try loadSnapshot(fileManager: fileManager).featureFlags
    }

    static func saveFeatureFlags(_ featureFlags: TeachingFeatureFlags, fileManager: FileManager = .default) throws {
        try mutateSnapshot(fileManager: fileManager) { snapshot in
            snapshot.featureFlags = featureFlags
        }
    }

    static func loadStudentSystemSettings(fileManager: FileManager = .default) throws -> TeachingStudentSystemSettings {
        try loadSnapshot(fileManager: fileManager).studentSystem
    }

    static func saveStudentSystemSettings(_ settings: TeachingStudentSystemSettings, fileManager: FileManager = .default) throws {
        try mutateSnapshot(fileManager: fileManager) { snapshot in
            snapshot.studentSystem = settings
        }
    }

    static func loadLessonPlanSystemSettings(fileManager: FileManager = .default) throws -> TeachingLessonPlanSystemSettings {
        try loadSnapshot(fileManager: fileManager).lessonPlanSystem
    }

    static func saveLessonPlanSystemSettings(_ settings: TeachingLessonPlanSystemSettings, fileManager: FileManager = .default) throws {
        try mutateSnapshot(fileManager: fileManager) { snapshot in
            snapshot.lessonPlanSystem = settings
        }
    }

    static func recordRecentLessonPlanFolder(_ folderID: String, fileManager: FileManager = .default) throws {
        let normalized = folderID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        try mutateSnapshot(fileManager: fileManager) { snapshot in
            snapshot.lessonPlanSystem.recentLessonPlanFolderIDs.removeAll(where: { $0 == normalized })
            snapshot.lessonPlanSystem.recentLessonPlanFolderIDs.insert(normalized, at: 0)
            if snapshot.lessonPlanSystem.recentLessonPlanFolderIDs.count > 12 {
                snapshot.lessonPlanSystem.recentLessonPlanFolderIDs = Array(snapshot.lessonPlanSystem.recentLessonPlanFolderIDs.prefix(12))
            }
        }
    }

    static func saveStudents(_ students: [TeachingStudentItem], expectedStudents: [TeachingStudentItem], fileManager: FileManager = .default) throws {
        var snapshot = try loadSnapshot(fileManager: fileManager)
        guard snapshot.students != students else { return }
        guard snapshot.students == expectedStudents || snapshot.students == students else {
            let data = try JSONEncoder().encode(students)
            try TeachingCloudFileAccess.preserve(data, original: settingsFileURL(fileManager: fileManager), kind: "pending")
            throw TeachingCloudFileAccess.AccessError.changed("学生列表")
        }
        snapshot.students = students
        let validIDs = Set(students.map { $0.id.uuidString })
        snapshot.studentProfiles = snapshot.studentProfiles.filter { validIDs.contains($0.key) }
        try saveSnapshot(snapshot, fileManager: fileManager)
    }

    static func loadStudentProfile(
        studentID: UUID,
        fileManager: FileManager = .default
    ) throws -> TeachingStudentProfileSettings? {
        let snapshot = try loadSnapshot(fileManager: fileManager)
        return snapshot.studentProfiles[studentID.uuidString]
    }

    static func saveStudentProfile(
        _ profile: TeachingStudentProfileSettings,
        studentID: UUID,
        fileManager: FileManager = .default
    ) throws {
        try mutateSnapshot(fileManager: fileManager) { snapshot in
            snapshot.studentProfiles[studentID.uuidString] = profile
        }
    }

    static func removeStudentProfile(
        studentID: UUID,
        fileManager: FileManager = .default
    ) throws {
        try mutateSnapshot(fileManager: fileManager) { snapshot in
            snapshot.studentProfiles.removeValue(forKey: studentID.uuidString)
        }
    }

    static func studentsUsingInstitution(
        institutionID: UUID,
        fileManager: FileManager = .default
    ) throws -> [TeachingStudentItem] {
        let snapshot = try loadSnapshot(fileManager: fileManager)
        return snapshot.students.filter { student in
            snapshot.studentProfiles[student.id.uuidString]?.lessonStatistics.institutionID == institutionID
        }
    }

    static func updateInstitutionNameInStudentProfiles(
        institutionID: UUID,
        newName: String,
        fileManager: FileManager = .default
    ) throws {
        let normalizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        try mutateSnapshot(fileManager: fileManager) { snapshot in
            for key in snapshot.studentProfiles.keys {
                guard snapshot.studentProfiles[key]?.lessonStatistics.institutionID == institutionID else { continue }
                snapshot.studentProfiles[key]?.lessonStatistics.institutionName = normalizedName
            }
        }
    }

    static func clearInstitutionFromStudentProfiles(
        institutionID: UUID,
        fileManager: FileManager = .default
    ) throws {
        try mutateSnapshot(fileManager: fileManager) { snapshot in
            for key in snapshot.studentProfiles.keys {
                guard snapshot.studentProfiles[key]?.lessonStatistics.institutionID == institutionID else { continue }
                snapshot.studentProfiles[key]?.lessonStatistics = TeachingStudentLessonStatisticsSettings()
            }
        }
    }

    static func loadSnapshot(fileManager: FileManager = .default) throws -> TeachingSettingsSnapshot {
        let url = try settingsFileURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StoreError.fileMissing
        }

        try ensureCurrentUbiquitousItem(at: url, fileManager: fileManager)
        let data = try TeachingCloudFileAccess.read(url)

        if let snapshot = try? decoder.decode(TeachingSettingsSnapshot.self, from: data) {
            var normalized = normalize(snapshot)
            normalized.diskDigest = TeachingCloudFileAccess.digest(data)
            normalized.hasCloudConflict = !(NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty
            let issues = normalized.validationIssues()
            if !issues.isEmpty {
                throw StoreError.invalidData
            }
            return normalized
        }

        if let legacyStudents = try? decoder.decode([TeachingStudentItem].self, from: data) {
            var migrated = TeachingSettingsSnapshot.initial(students: legacyStudents)
            migrated.diskDigest = TeachingCloudFileAccess.digest(data)
            migrated.hasCloudConflict = !(NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty
            if !migrated.hasCloudConflict { migrated.diskDigest = try saveSnapshot(migrated, fileManager: fileManager) }
            return migrated
        }

        throw StoreError.invalidData
    }

    @discardableResult
    static func saveSnapshot(_ snapshot: TeachingSettingsSnapshot, fileManager: FileManager = .default) throws -> String {
        let url = try settingsFileURL(fileManager: fileManager)
        var normalized = normalize(snapshot)
        normalized.schemaVersion = TeachingSettingsSnapshot.currentSchemaVersion
        normalized.savedAt = ISO8601DateFormatter().string(from: Date())
        let data = try encoder.encode(normalized)
        try TeachingCloudFileAccess.write(data, to: url, expectedDigest: snapshot.diskDigest)
        return TeachingCloudFileAccess.digest(data)
    }

    private static func ensureCurrentUbiquitousItem(at url: URL, fileManager: FileManager) throws {
        let values = try url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ])
        guard values.isUbiquitousItem == true else { return }
        guard values.ubiquitousItemDownloadingStatus == .current else {
            try? fileManager.startDownloadingUbiquitousItem(at: url)
            throw StoreError.synchronizationPending
        }
    }

    static func settingsFileURL(fileManager: FileManager = .default) throws -> URL {
        let settingsURL = try settingsFolderURL(fileManager: fileManager)
        return settingsURL.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func settingsFolderURL(fileManager: FileManager = .default) throws -> URL {
        let rootURL = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let settingsURL = rootURL.appendingPathComponent(ArchiveStorage.settingsFolderName, isDirectory: true)
        try fileManager.createDirectory(at: settingsURL, withIntermediateDirectories: true)
        return settingsURL
    }

    private static func normalize(_ snapshot: TeachingSettingsSnapshot) -> TeachingSettingsSnapshot {
        snapshot.normalized()
    }

    private static func loadLegacySnapshotIfAvailable(
        fallbackStudents: [TeachingStudentItem],
        fileManager: FileManager
    ) throws -> TeachingSettingsSnapshot? {
        let settingsFolder = try settingsFolderURL(fileManager: fileManager)
        let legacyStudentsURL = settingsFolder.appendingPathComponent(fileName, isDirectory: false)
        let legacySystemURL = settingsFolder.appendingPathComponent(legacySystemFileName, isDirectory: false)
        let legacyLessonPlanURL = settingsFolder.appendingPathComponent(legacyLessonPlanFileName, isDirectory: false)
        let legacyFeatureFlagsURL = settingsFolder.appendingPathComponent(legacyFeatureFlagsFileName, isDirectory: false)

        let legacyExists = [legacyStudentsURL, legacySystemURL, legacyLessonPlanURL, legacyFeatureFlagsURL]
            .contains { fileManager.fileExists(atPath: $0.path) }
        guard legacyExists else { return nil }

        let students: [TeachingStudentItem] = {
            guard fileManager.fileExists(atPath: legacyStudentsURL.path),
                  let data = try? Data(contentsOf: legacyStudentsURL),
                  let value = try? decoder.decode([TeachingStudentItem].self, from: data) else {
                return fallbackStudents
            }
            return value
        }()
        let studentSystem: TeachingStudentSystemSettings = {
            guard fileManager.fileExists(atPath: legacySystemURL.path),
                  let data = try? Data(contentsOf: legacySystemURL),
                  let value = try? decoder.decode(TeachingStudentSystemSettings.self, from: data) else {
                return .init()
            }
            return value
        }()
        let lessonPlanSystem: TeachingLessonPlanSystemSettings = {
            guard fileManager.fileExists(atPath: legacyLessonPlanURL.path),
                  let data = try? Data(contentsOf: legacyLessonPlanURL),
                  let value = try? decoder.decode(TeachingLessonPlanSystemSettings.self, from: data) else {
                return .init()
            }
            return value
        }()
        let featureFlags: TeachingFeatureFlags = {
            guard fileManager.fileExists(atPath: legacyFeatureFlagsURL.path),
                  let data = try? Data(contentsOf: legacyFeatureFlagsURL),
                  let value = try? decoder.decode(TeachingFeatureFlags.self, from: data) else {
                return .init()
            }
            return value
        }()

        return TeachingSettingsSnapshot(
            schemaVersion: TeachingSettingsSnapshot.currentSchemaVersion,
            savedAt: ISO8601DateFormatter().string(from: Date()),
            students: students,
            studentSystem: studentSystem,
            lessonPlanSystem: lessonPlanSystem,
            featureFlags: featureFlags,
            studentProfiles: [:]
        ).normalized()
    }

    private static func mutateSnapshot(
        fileManager: FileManager = .default,
        _ body: (inout TeachingSettingsSnapshot) -> Void
    ) throws {
        var snapshot = try loadSnapshot(fileManager: fileManager)
        body(&snapshot)
        try saveSnapshot(snapshot, fileManager: fileManager)
    }
}
