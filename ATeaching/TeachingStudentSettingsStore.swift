import Foundation

// MARK: - 学生设置存储 - v4 - 持久化授课快照并支持功能开关与学生级覆盖配置
enum TeachingStudentSettingsStore {
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

    static func saveStudents(_ students: [TeachingStudentItem], fileManager: FileManager = .default) throws {
        try mutateSnapshot(fileManager: fileManager) { snapshot in
            snapshot.students = students
            let validIDs = Set(students.map { $0.id.uuidString })
            snapshot.studentProfiles = snapshot.studentProfiles.filter { validIDs.contains($0.key) }
        }
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
        let fallbackStudents = [
            TeachingStudentItem(name: "学生甲"),
            TeachingStudentItem(name: "学生乙"),
            TeachingStudentItem(name: "学生丙")
        ]
        guard fileManager.fileExists(atPath: url.path) else {
            if let migrated = try loadLegacySnapshotIfAvailable(fallbackStudents: fallbackStudents, fileManager: fileManager) {
                try saveSnapshot(migrated, fileManager: fileManager)
                return migrated
            }
            let initial = TeachingSettingsSnapshot.initial(students: fallbackStudents)
            try saveSnapshot(initial, fileManager: fileManager)
            return initial
        }

        let data = try Data(contentsOf: url)

        if let snapshot = try? decoder.decode(TeachingSettingsSnapshot.self, from: data) {
            let normalized = normalize(snapshot)
            let issues = normalized.validationIssues()
            if !issues.isEmpty {
                let repaired = normalize(normalized)
                try? saveSnapshot(repaired, fileManager: fileManager)
                return repaired
            }
            return normalized
        }

        if let legacyStudents = try? decoder.decode([TeachingStudentItem].self, from: data) {
            let migrated = TeachingSettingsSnapshot.initial(students: legacyStudents)
            try saveSnapshot(migrated, fileManager: fileManager)
            return migrated
        }

        let reset = TeachingSettingsSnapshot.initial(students: fallbackStudents)
        try saveSnapshot(reset, fileManager: fileManager)
        return reset
    }

    static func saveSnapshot(_ snapshot: TeachingSettingsSnapshot, fileManager: FileManager = .default) throws {
        let url = try settingsFileURL(fileManager: fileManager)
        var normalized = normalize(snapshot)
        normalized.schemaVersion = TeachingSettingsSnapshot.currentSchemaVersion
        normalized.savedAt = ISO8601DateFormatter().string(from: Date())
        let data = try encoder.encode(normalized)
        try data.write(to: url, options: .atomic)
    }

    private static func settingsFileURL(fileManager: FileManager = .default) throws -> URL {
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
