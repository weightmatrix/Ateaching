import Foundation

struct TeachingStudentBackupResult: Hashable {
    var movedStudentIDs: Set<UUID>
    var movedCount: Int
    var skippedNames: [String]
    var backupRootPath: String
}

struct TeachingStudentBackupEntry: Identifiable {
    let id: String
    let folderURL: URL
    let student: TeachingStudentItem
}

struct TeachingStudentRestoreResult {
    let restoredStudents: [TeachingStudentItem]
    let restoredProfiles: [UUID: TeachingStudentProfileSettings]
    let skippedNames: [String]
}

enum TeachingStudentBackupService {
    private static let metadataFileName = ".student-backup.json"

    private struct Metadata: Codable {
        let student: TeachingStudentItem
        let profile: TeachingStudentProfileSettings?
    }

    static func backupStudents(_ students: [TeachingStudentItem], fileManager: FileManager = .default) throws -> TeachingStudentBackupResult {
        let workspaceRoot = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let archiveStudentsRoot = try ArchiveStorage.ensureArchiveRoot(fileManager: fileManager)
            .appendingPathComponent("学生", isDirectory: true)
        let backupRoot = workspaceRoot
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent("学生备份", isDirectory: true)
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        var movedIDs: Set<UUID> = []
        var movedCount = 0
        var skippedNames: [String] = []

        for student in students {
            let sourceURL = archiveStudentsRoot.appendingPathComponent(student.name, isDirectory: true)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                skippedNames.append(student.name)
                continue
            }
            let destinationURL = uniqueDestinationURL(
                preferredName: student.name,
                in: backupRoot,
                fileManager: fileManager
            )
            do {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
                let profile = try? TeachingStudentSettingsStore.loadStudentProfile(
                    studentID: student.id,
                    fileManager: fileManager
                )
                if let data = try? JSONEncoder().encode(Metadata(student: student, profile: profile)) {
                    try? data.write(
                        to: destinationURL.appendingPathComponent(metadataFileName),
                        options: .atomic
                    )
                }
                movedIDs.insert(student.id)
                movedCount += 1
            } catch {
                skippedNames.append(student.name)
            }
        }

        return TeachingStudentBackupResult(
            movedStudentIDs: movedIDs,
            movedCount: movedCount,
            skippedNames: skippedNames,
            backupRootPath: backupRoot.path
        )
    }

    static func listBackups(fileManager: FileManager = .default) throws -> [TeachingStudentBackupEntry] {
        let backupRoot = try studentBackupRoot(fileManager: fileManager)
        return try fileManager.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let metadata = readMetadata(in: url)
            let fallbackName = originalName(fromBackupFolderName: url.lastPathComponent)
            return TeachingStudentBackupEntry(
                id: url.lastPathComponent,
                folderURL: url,
                student: metadata?.student ?? TeachingStudentItem(name: fallbackName)
            )
        }
        .sorted { $0.student.name.localizedStandardCompare($1.student.name) == .orderedAscending }
    }

    static func restoreBackups(
        _ entries: [TeachingStudentBackupEntry],
        fileManager: FileManager = .default
    ) throws -> TeachingStudentRestoreResult {
        let studentsRoot = try ArchiveStorage.ensureArchiveRoot(fileManager: fileManager)
            .appendingPathComponent("学生", isDirectory: true)
        try fileManager.createDirectory(at: studentsRoot, withIntermediateDirectories: true)
        var restoredStudents: [TeachingStudentItem] = []
        var restoredProfiles: [UUID: TeachingStudentProfileSettings] = [:]
        var skippedNames: [String] = []

        for entry in entries {
            let metadata = readMetadata(in: entry.folderURL)
            let student = metadata?.student ?? entry.student
            let destination = studentsRoot.appendingPathComponent(student.name, isDirectory: true)
            guard !fileManager.fileExists(atPath: destination.path) else {
                skippedNames.append(student.name)
                continue
            }
            do {
                try fileManager.moveItem(at: entry.folderURL, to: destination)
                try? fileManager.removeItem(at: destination.appendingPathComponent(metadataFileName))
                restoredStudents.append(student)
                if let profile = metadata?.profile {
                    restoredProfiles[student.id] = profile
                }
            } catch {
                skippedNames.append(student.name)
            }
        }
        return TeachingStudentRestoreResult(
            restoredStudents: restoredStudents,
            restoredProfiles: restoredProfiles,
            skippedNames: skippedNames
        )
    }

    private static func studentBackupRoot(fileManager: FileManager) throws -> URL {
        let workspaceRoot = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let root = workspaceRoot
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent("学生备份", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func readMetadata(in folderURL: URL) -> Metadata? {
        let url = folderURL.appendingPathComponent(metadataFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Metadata.self, from: data)
    }

    private static func originalName(fromBackupFolderName name: String) -> String {
        name.replacingOccurrences(
            of: "-\\d{14}(?:-\\d+)?$",
            with: "",
            options: .regularExpression
        )
    }

    private static func uniqueDestinationURL(
        preferredName: String,
        in root: URL,
        fileManager: FileManager
    ) -> URL {
        let safeName = preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名学生" : preferredName
        var candidate = root.appendingPathComponent(safeName, isDirectory: true)
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMddHHmmss"
        let suffix = formatter.string(from: Date())
        candidate = root.appendingPathComponent("\(safeName)-\(suffix)", isDirectory: true)
        var index = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(safeName)-\(suffix)-\(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }
}
