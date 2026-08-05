import Foundation

extension Notification.Name {
    static let teachingStudentsDidChange = Notification.Name("ATeaching.teachingStudentsDidChange")
}

/// 学生改名事务。学生 UUID 是唯一身份，姓名只是可变的显示快照。
///
/// 标准：
/// 1. 改名前完成所有路径、重名和目标冲突检查，不覆盖任何已有文件。
/// 2. 只改自动生成且名称精确匹配的文件，不猜测、不改用户自建副本。
/// 3. 成课、排课、周表仅依据 studentID 更新姓名；缺少 ID 的旧数据保持不动。
/// 4. 只改学生个人同步目录，不改系统默认同步目录。
/// 5. 任意一步失败都逆序恢复已移动文件、CSV 内容、设置和三份课单。
@MainActor
enum TeachingStudentRenameService {
    private struct FileMove {
        let source: URL
        let destination: URL
    }

    private struct FileRewrite {
        let url: URL
        let originalData: Data
        let updatedData: Data
    }

    private struct StoreBackup {
        let lessonRecords: [TeachingLessonRecord]
        let planningRecords: [TeachingLessonRecord]
        let weeklyRecords: [TeachingLessonRecord]
        let lessonRecordsExisted: Bool
        let planningRecordsExisted: Bool
        let weeklyRecordsExisted: Bool
    }

    private enum RenameError: LocalizedError {
        case emptyName
        case invalidName
        case duplicateName(String)
        case studentNotFound
        case activeSession
        case activeBackgroundJob
        case archiveFolderMissing(String)
        case syncFolderMissing(String)
        case destinationExists(String)
        case caseOnlyRename
        case unreadableCSV(String)
        case rollbackFailed(original: Error, rollback: Error)

        var errorDescription: String? {
            switch self {
            case .emptyName:
                return "学生姓名不能为空。"
            case .invalidName:
                return "学生姓名不能包含 / 、 : 或换行，也不能是 . 或 ..。"
            case .duplicateName(let name):
                return "学生姓名“\(name)”已经存在。"
            case .studentNotFound:
                return "未找到目标学生。"
            case .activeSession:
                return "正在上课或编辑随堂笔记，请先关闭当前会话再改名。"
            case .activeBackgroundJob:
                return "正在执行同步或数据任务，请等任务完成后再改名。"
            case .archiveFolderMissing(let path):
                return "学生档案目录不存在，未执行改名：\(path)"
            case .syncFolderMissing(let path):
                return "学生个人同步目录不可用，未执行改名：\(path)"
            case .destinationExists(let path):
                return "改名目标已存在，不会覆盖：\(path)"
            case .caseOnlyRename:
                return "当前不支持只改英文大小写，请先改为一个临时姓名。"
            case .unreadableCSV(let path):
                return "无法读取需要更新的 CSV 文件：\(path)"
            case let .rollbackFailed(original, rollback):
                return "改名失败：\(original.localizedDescription)；自动恢复也失败：\(rollback.localizedDescription)"
            }
        }
    }

    static func renameStudent(studentID: UUID, from oldName: String, to newName: String) async throws {
        let requestedOldName = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { throw RenameError.emptyName }
        try validatePathName(newName)
        guard TeachingClassSessionCenter.shared.session == nil else { throw RenameError.activeSession }
        guard !(await TeachingCourseJobCenter.shared.hasActiveJobs()) else {
            throw RenameError.activeBackgroundJob
        }

        let fileManager = FileManager.default
        let oldSnapshot = try TeachingStudentSettingsStore.loadSnapshot(fileManager: fileManager)
        guard let studentIndex = oldSnapshot.students.firstIndex(where: { $0.id == studentID }) else {
            throw RenameError.studentNotFound
        }

        // 设置中的名字是改名起点，界面传入的旧名只用于兼容旧调用。
        let persistedOldName = oldSnapshot.students[studentIndex].name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let oldName = persistedOldName.isEmpty ? requestedOldName : persistedOldName
        guard !oldName.isEmpty else { throw RenameError.emptyName }
        guard oldName != newName else { return }
        if foldedName(oldName) == foldedName(newName) {
            throw RenameError.caseOnlyRename
        }
        if oldSnapshot.students.contains(where: {
            $0.id != studentID && foldedName($0.name) == foldedName(newName)
        }) {
            throw RenameError.duplicateName(newName)
        }

        let oldProfile = oldSnapshot.studentProfiles[studentID.uuidString] ?? TeachingStudentProfileSettings()
        let effectiveNameKeys = resolveEffective(defaults: oldSnapshot.studentSystem, profile: oldProfile)
        let archiveRoot = try ArchiveStorage.ensureArchiveRoot(fileManager: fileManager)
            .appendingPathComponent("学生", isDirectory: true)
        let oldStudentFolder = archiveRoot.appendingPathComponent(oldName, isDirectory: true)
        let newStudentFolder = archiveRoot.appendingPathComponent(newName, isDirectory: true)
        guard fileManager.fileExists(atPath: oldStudentFolder.path) else {
            throw RenameError.archiveFolderMissing(oldStudentFolder.path)
        }

        var moves: [FileMove] = []
        var rewrites: [String: FileRewrite] = [:]
        try prepareArchiveChanges(
            folder: oldStudentFolder,
            oldName: oldName,
            newName: newName,
            studentNameKeyID: effectiveNameKeys.studentInfoNameKeyID,
            classInfoNameKeyID: effectiveNameKeys.classInfoNameKeyID,
            moves: &moves,
            rewrites: &rewrites,
            fileManager: fileManager
        )
        moves.append(FileMove(source: oldStudentFolder, destination: newStudentFolder))

        var newSnapshot = oldSnapshot
        newSnapshot.students[studentIndex].name = newName
        var newProfile = oldProfile
        try preparePersonalSyncChanges(
            profile: &newProfile,
            oldName: oldName,
            newName: newName,
            moves: &moves,
            fileManager: fileManager
        )
        newSnapshot.studentProfiles[studentID.uuidString] = newProfile.normalized()

        try preflight(moves: moves, fileManager: fileManager)

        let oldLessonRecords = try TeachingLessonStatisticsStore.loadLessonRecords(fileManager: fileManager)
        let oldPlanningRecords = try TeachingLessonPlanningStore.load(.planning, fileManager: fileManager)
        let oldWeeklyRecords = try TeachingLessonPlanningStore.load(.weekly, fileManager: fileManager)
        let lessonRecordsURL = try TeachingLessonStatisticsStore.lessonRecordsFileURL(fileManager: fileManager)
        let planningRecordsURL = try TeachingLessonPlanningStore.fileURL(.planning, fileManager: fileManager)
        let weeklyRecordsURL = try TeachingLessonPlanningStore.fileURL(.weekly, fileManager: fileManager)
        let storeBackup = StoreBackup(
            lessonRecords: oldLessonRecords,
            planningRecords: oldPlanningRecords,
            weeklyRecords: oldWeeklyRecords,
            lessonRecordsExisted: fileManager.fileExists(atPath: lessonRecordsURL.path),
            planningRecordsExisted: fileManager.fileExists(atPath: planningRecordsURL.path),
            weeklyRecordsExisted: fileManager.fileExists(atPath: weeklyRecordsURL.path)
        )

        let newLessonRecords = renamedRecords(oldLessonRecords, studentID: studentID, newName: newName)
        let newPlanningRecords = renamedRecords(oldPlanningRecords, studentID: studentID, newName: newName)
        let newWeeklyRecords = renamedRecords(oldWeeklyRecords, studentID: studentID, newName: newName)

        var completedMoves: [FileMove] = []
        do {
            for rewrite in rewrites.values {
                try rewrite.updatedData.write(to: rewrite.url, options: .atomic)
            }
            for move in moves {
                let completedMove = try performMove(move, fileManager: fileManager)
                completedMoves.append(completedMove)
            }
            try TeachingLessonStatisticsStore.saveLessonRecords(newLessonRecords, fileManager: fileManager)
            try TeachingLessonPlanningStore.save(newPlanningRecords, kind: .planning, fileManager: fileManager)
            try TeachingLessonPlanningStore.save(newWeeklyRecords, kind: .weekly, fileManager: fileManager)
            try TeachingStudentSettingsStore.saveSnapshot(newSnapshot, fileManager: fileManager)
        } catch {
            do {
                try rollback(
                    completedMoves: completedMoves,
                    rewrites: Array(rewrites.values),
                    oldSnapshot: oldSnapshot,
                    storeBackup: storeBackup,
                    lessonRecordsURL: lessonRecordsURL,
                    planningRecordsURL: planningRecordsURL,
                    weeklyRecordsURL: weeklyRecordsURL,
                    fileManager: fileManager
                )
            } catch let rollbackError {
                throw RenameError.rollbackFailed(original: error, rollback: rollbackError)
            }
            throw error
        }
    }

    private static func prepareArchiveChanges(
        folder: URL,
        oldName: String,
        newName: String,
        studentNameKeyID: String?,
        classInfoNameKeyID: String?,
        moves: inout [FileMove],
        rewrites: inout [String: FileRewrite],
        fileManager: FileManager
    ) throws {
        let files = try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "csv" }

        for source in files {
            let fileName = source.lastPathComponent
            var destinationName: String?
            var nameKeyID: String?
            var legacyNameKeys: Set<String> = []

            if fileName == "随堂笔记_\(oldName).CSV" {
                destinationName = "随堂笔记_\(newName).CSV"
            } else if fileName == "学生信息_\(oldName).CSV" {
                destinationName = "学生信息_\(newName).CSV"
                nameKeyID = studentNameKeyID
                legacyNameKeys = ["姓名", "学生姓名", "name", "studentname"]
            } else if fileName.hasPrefix("上课信息_\(oldName)_") {
                destinationName = "上课信息_\(newName)_" + fileName.dropFirst("上课信息_\(oldName)_".count)
                nameKeyID = classInfoNameKeyID
                legacyNameKeys = ["姓名", "学生姓名", "name", "studentname"]
            } else if fileName.hasPrefix("教案_") && fileName.hasSuffix("完成情况_\(oldName).CSV") {
                destinationName = String(fileName.dropLast("完成情况_\(oldName).CSV".count))
                    + "完成情况_\(newName).CSV"
            }

            let shouldUpdateStudentInfo = fileName.hasPrefix("学生信息_")
            let shouldUpdateClassInfo = fileName.hasPrefix("上课信息_")
            if shouldUpdateStudentInfo {
                nameKeyID = studentNameKeyID
                legacyNameKeys = ["姓名", "学生姓名", "name", "studentname"]
            } else if shouldUpdateClassInfo {
                nameKeyID = classInfoNameKeyID
                legacyNameKeys = ["姓名", "学生姓名", "name", "studentname"]
            }

            if destinationName != nil || shouldUpdateStudentInfo || shouldUpdateClassInfo {
                let title = destinationName.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
                let rewrite = try makeCSVRewrite(
                    url: source,
                    newTitle: title,
                    nameKeyID: nameKeyID,
                    legacyNameKeys: legacyNameKeys,
                    newName: newName
                )
                rewrites[source.path] = rewrite
            }
            if let destinationName {
                moves.append(FileMove(
                    source: source,
                    destination: folder.appendingPathComponent(destinationName, isDirectory: false)
                ))
            }
        }
    }

    private static func makeCSVRewrite(
        url: URL,
        newTitle: String?,
        nameKeyID: String?,
        legacyNameKeys: Set<String>,
        newName: String
    ) throws -> FileRewrite {
        let originalData = try Data(contentsOf: url)
        guard let text = String(data: originalData, encoding: .utf8) else {
            throw RenameError.unreadableCSV(url.path)
        }
        var rows = ArchiveStorage.parseCSVRowsForMigration(text)

        if let newTitle {
            if let index = rows.firstIndex(where: { $0.first == "[META_TITLE]" }) {
                while rows[index].count < 2 { rows[index].append("") }
                rows[index][1] = newTitle
            }
        }

        let normalizedKeyID = nameKeyID?.trimmingCharacters(in: .whitespacesAndNewlines)
        var contentRowIndex: Int?
        if let normalizedKeyID, !normalizedKeyID.isEmpty {
            contentRowIndex = rows.firstIndex(where: { $0.count >= 3 && $0[0] == normalizedKeyID })
        }
        if contentRowIndex == nil, !legacyNameKeys.isEmpty {
            contentRowIndex = rows.firstIndex(where: { row in
                guard row.count >= 3 else { return false }
                let key = row[1]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
                    .lowercased()
                return legacyNameKeys.contains(key)
            })
        }
        if let contentRowIndex {
            rows[contentRowIndex][2] = newName
        }

        let output = ArchiveStorage.renderCSVRowsForMigration(rows)
        return FileRewrite(url: url, originalData: originalData, updatedData: Data(output.utf8))
    }

    private static func preparePersonalSyncChanges(
        profile: inout TeachingStudentProfileSettings,
        oldName: String,
        newName: String,
        moves: inout [FileMove],
        fileManager: FileManager
    ) throws {
        guard let rawPath = profile.syncBaseFolderPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else { return }
        let oldFolder = URL(fileURLWithPath: rawPath, isDirectory: true)
        let oldSuffix = "-\(oldName)"
        guard oldFolder.lastPathComponent.hasSuffix(oldSuffix) else { return }
        let parentPath = oldFolder.deletingLastPathComponent().path
        try TeachingSecurityScopedAccess.withWritableAccess(toPath: parentPath) { writableParentURL in
            let resolvedOldFolder = writableParentURL.appendingPathComponent(
                oldFolder.lastPathComponent,
                isDirectory: true
            )
            guard fileManager.fileExists(atPath: resolvedOldFolder.path) else {
                throw RenameError.syncFolderMissing(resolvedOldFolder.path)
            }

            let prefix = String(oldFolder.lastPathComponent.dropLast(oldSuffix.count))
            let resolvedNewFolder = writableParentURL
                .appendingPathComponent("\(prefix)-\(newName)", isDirectory: true)
            let exactFileNames: [String: String] = [
                "问题-\(oldName).pdf": "问题-\(newName).pdf",
                "试卷-\(oldName).pdf": "试卷-\(newName).pdf",
                "随堂笔记_\(oldName).pdf": "随堂笔记_\(newName).pdf",
                "随堂笔记_\(oldName).html": "随堂笔记_\(newName).html"
            ]
            if let enumerator = fileManager.enumerator(
                at: resolvedOldFolder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let source as URL in enumerator {
                    let lowerName = source.lastPathComponent.lowercased()
                    guard let entry = exactFileNames.first(where: { $0.key.lowercased() == lowerName }) else { continue }
                    moves.append(FileMove(
                        source: source,
                        destination: source.deletingLastPathComponent().appendingPathComponent(entry.value)
                    ))
                }
            }
            moves.append(FileMove(source: resolvedOldFolder, destination: resolvedNewFolder))
            profile.syncBaseFolderPath = resolvedNewFolder.path
        }
    }

    private static func preflight(moves: [FileMove], fileManager: FileManager) throws {
        var destinations = Set<String>()
        for move in moves {
            try withResolvedMove(move) { resolvedMove in
                let sourcePath = resolvedMove.source.standardizedFileURL.path
                let destinationPath = resolvedMove.destination.standardizedFileURL.path
                guard fileManager.fileExists(atPath: sourcePath) else {
                    throw RenameError.archiveFolderMissing(sourcePath)
                }
                guard destinations.insert(destinationPath).inserted else {
                    throw RenameError.destinationExists(destinationPath)
                }
                if fileManager.fileExists(atPath: destinationPath) {
                    throw RenameError.destinationExists(destinationPath)
                }
            }
        }
    }

    private static func withResolvedMove<T>(
        _ move: FileMove,
        _ body: (FileMove) throws -> T
    ) throws -> T {
        let sourceParent = move.source.deletingLastPathComponent()
        let destinationParent = move.destination.deletingLastPathComponent()
        guard sourceParent.standardizedFileURL.path == destinationParent.standardizedFileURL.path else {
            return try body(move)
        }
        return try TeachingSecurityScopedAccess.withWritableAccess(toPath: sourceParent.path) { writableParentURL in
            let resolvedMove = FileMove(
                source: writableParentURL.appendingPathComponent(move.source.lastPathComponent),
                destination: writableParentURL.appendingPathComponent(move.destination.lastPathComponent)
            )
            return try body(resolvedMove)
        }
    }

    private static func performMove(_ move: FileMove, fileManager: FileManager) throws -> FileMove {
        try withResolvedMove(move) { resolvedMove in
            try fileManager.moveItem(at: resolvedMove.source, to: resolvedMove.destination)
            return resolvedMove
        }
    }

    private static func renamedRecords(
        _ records: [TeachingLessonRecord],
        studentID: UUID,
        newName: String
    ) -> [TeachingLessonRecord] {
        records.map { record in
            guard record.studentID == studentID else { return record }
            var next = record
            next.studentName = newName
            return next
        }
    }

    private static func rollback(
        completedMoves: [FileMove],
        rewrites: [FileRewrite],
        oldSnapshot: TeachingSettingsSnapshot,
        storeBackup: StoreBackup,
        lessonRecordsURL: URL,
        planningRecordsURL: URL,
        weeklyRecordsURL: URL,
        fileManager: FileManager
    ) throws {
        var firstError: Error?
        for move in completedMoves.reversed() {
            do {
                _ = try performMove(
                    FileMove(source: move.destination, destination: move.source),
                    fileManager: fileManager
                )
            } catch {
                firstError = firstError ?? error
            }
        }
        for rewrite in rewrites {
            do {
                try rewrite.originalData.write(to: rewrite.url, options: .atomic)
            } catch {
                firstError = firstError ?? error
            }
        }
        do {
            try TeachingLessonStatisticsStore.saveLessonRecords(storeBackup.lessonRecords, fileManager: fileManager)
            if !storeBackup.lessonRecordsExisted { try? fileManager.removeItem(at: lessonRecordsURL) }
            try TeachingLessonPlanningStore.save(storeBackup.planningRecords, kind: .planning, fileManager: fileManager)
            if !storeBackup.planningRecordsExisted { try? fileManager.removeItem(at: planningRecordsURL) }
            try TeachingLessonPlanningStore.save(storeBackup.weeklyRecords, kind: .weekly, fileManager: fileManager)
            if !storeBackup.weeklyRecordsExisted { try? fileManager.removeItem(at: weeklyRecordsURL) }
            try TeachingStudentSettingsStore.saveSnapshot(oldSnapshot, fileManager: fileManager)
        } catch {
            firstError = firstError ?? error
        }
        if let firstError { throw firstError }
    }

    private static func validatePathName(_ name: String) throws {
        let invalidScalars = CharacterSet(charactersIn: "/:\n\r")
        guard name != ".", name != "..", name.rangeOfCharacter(from: invalidScalars) == nil else {
            throw RenameError.invalidName
        }
    }

    private static func foldedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    private static func resolveEffective(
        defaults: TeachingStudentSystemSettings,
        profile: TeachingStudentProfileSettings
    ) -> (studentInfoNameKeyID: String?, classInfoNameKeyID: String?) {
        (
            profile.studentNameKeyID ?? defaults.studentNameKeyID,
            profile.classInfoNameKeyID ?? defaults.classInfoNameKeyID
        )
    }
}
