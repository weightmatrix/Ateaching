import Foundation

struct TeachingStudentBackupResult: Hashable {
    var movedStudentIDs: Set<UUID>
    var movedCount: Int
    var skippedNames: [String]
    var backupRootPath: String
}

enum TeachingStudentBackupService {
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
