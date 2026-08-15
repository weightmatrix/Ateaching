import Foundation

struct TeachingCourseSyncProgressSnapshot: Hashable {
    enum Action: String, Hashable {
        case prepareAllStudents
        case exportAllPDF
        case checkConsistency
        case stressTest

        var displayName: String {
            switch self {
            case .prepareAllStudents:
                return "整理"
            case .exportAllPDF:
                return "PDF生成"
            case .checkConsistency:
                return "一致性巡检"
            case .stressTest:
                return "压力测试"
            }
        }
    }

    var action: Action
    var completedStudents: Int
    var totalStudents: Int
    var currentStudentName: String?
    var currentFilePath: String?

    var fractionCompleted: Double {
        guard totalStudents > 0 else { return 0 }
        return min(1, max(0, Double(completedStudents) / Double(totalStudents)))
    }
}

struct TeachingCourseSyncResult: Hashable {
    struct Failure: Hashable {
        var studentName: String
        var reason: String
    }

    var action: TeachingCourseSyncProgressSnapshot.Action
    var successCount: Int
    var failures: [Failure]
    var consistencyReportsByStudent: [String: TeachingCourseConsistencySummary] = [:]
    var removedImageCount: Int = 0
}

enum TeachingCourseSyncService {
    static func prepareAllStudents(
        students: [TeachingStudentItem],
        onProgress: @escaping @Sendable (TeachingCourseSyncProgressSnapshot) async -> Void
    ) async throws -> TeachingCourseSyncResult {
        let preflight = TeachingCommercialReadinessVerifier.preflight(students: students, requireSyncPath: false)
        if !preflight.canProceed {
            throw NSError(
                domain: "TeachingCourseSyncService",
                code: 2001,
                userInfo: [NSLocalizedDescriptionKey: preflight.blockingErrors.joined(separator: "；")]
            )
        }

        var successCount = 0
        var failures: [TeachingCourseSyncResult.Failure] = []
        let total = students.count
        let imageCleanup = try NodeMarkdownImageResourceManager.removeUnreferencedManagedImagesInWorkspace()

        await onProgress(
            TeachingCourseSyncProgressSnapshot(
                action: .prepareAllStudents,
                completedStudents: 0,
                totalStudents: total,
                currentStudentName: nil,
                currentFilePath: nil
            )
        )

        for (index, student) in students.enumerated() {
            try Task.checkCancellation()
            let notebookPath = try notebookFileURL(for: student).path
            await onProgress(
                TeachingCourseSyncProgressSnapshot(
                    action: .prepareAllStudents,
                    completedStudents: index,
                    totalStudents: total,
                    currentStudentName: student.name,
                    currentFilePath: notebookPath
                )
            )
            do {
                _ = try await TeachingCourseWorkflowService.prepareForNotes(student: student)
                successCount += 1
            } catch {
                failures.append(.init(studentName: student.name, reason: error.localizedDescription))
            }
            await onProgress(
                TeachingCourseSyncProgressSnapshot(
                    action: .prepareAllStudents,
                    completedStudents: index + 1,
                    totalStudents: total,
                    currentStudentName: student.name,
                    currentFilePath: notebookPath
                )
            )
        }

        return TeachingCourseSyncResult(
            action: .prepareAllStudents,
            successCount: successCount,
            failures: failures,
            removedImageCount: imageCleanup.deletedImageCount
        )
    }

    static func exportAllStudentsPDF(
        students: [TeachingStudentItem],
        onProgress: @escaping @Sendable (TeachingCourseSyncProgressSnapshot) async -> Void
    ) async throws -> TeachingCourseSyncResult {
        let preflight = TeachingCommercialReadinessVerifier.preflight(students: students, requireSyncPath: true)
        if !preflight.canProceed {
            throw NSError(
                domain: "TeachingCourseSyncService",
                code: 2002,
                userInfo: [NSLocalizedDescriptionKey: preflight.blockingErrors.joined(separator: "；")]
            )
        }

        var successCount = 0
        var failures: [TeachingCourseSyncResult.Failure] = []
        let total = students.count

        await onProgress(
            TeachingCourseSyncProgressSnapshot(
                action: .exportAllPDF,
                completedStudents: 0,
                totalStudents: total,
                currentStudentName: nil,
                currentFilePath: nil
            )
        )

        for (index, student) in students.enumerated() {
            try Task.checkCancellation()
            do {
                let sourceURL = try notebookFileURL(for: student)
                await onProgress(
                    TeachingCourseSyncProgressSnapshot(
                        action: .exportAllPDF,
                        completedStudents: index,
                        totalStudents: total,
                        currentStudentName: student.name,
                        currentFilePath: sourceURL.path
                    )
                )
                _ = try await TeachingCourseWorkflowService.regenerateNotebookExports(student: student)
                successCount += 1
            } catch {
                failures.append(.init(studentName: student.name, reason: error.localizedDescription))
            }
            await onProgress(
                TeachingCourseSyncProgressSnapshot(
                    action: .exportAllPDF,
                    completedStudents: index + 1,
                    totalStudents: total,
                    currentStudentName: student.name,
                    currentFilePath: try? notebookFileURL(for: student).path
                )
            )
        }

        return TeachingCourseSyncResult(
            action: .exportAllPDF,
            successCount: successCount,
            failures: failures
        )
    }

    static func checkAllStudentsConsistency(
        students: [TeachingStudentItem],
        onProgress: @escaping @Sendable (TeachingCourseSyncProgressSnapshot) async -> Void
    ) async throws -> TeachingCourseSyncResult {
        let preflight = TeachingCommercialReadinessVerifier.preflight(students: students, requireSyncPath: false)
        if !preflight.canProceed {
            throw NSError(
                domain: "TeachingCourseSyncService",
                code: 2003,
                userInfo: [NSLocalizedDescriptionKey: preflight.blockingErrors.joined(separator: "；")]
            )
        }

        var successCount = 0
        var failures: [TeachingCourseSyncResult.Failure] = []
        var reportsByStudent: [String: TeachingCourseConsistencySummary] = [:]
        let total = students.count

        await onProgress(
            TeachingCourseSyncProgressSnapshot(
                action: .checkConsistency,
                completedStudents: 0,
                totalStudents: total,
                currentStudentName: nil,
                currentFilePath: nil
            )
        )

        for (index, student) in students.enumerated() {
            try Task.checkCancellation()
            await onProgress(
                TeachingCourseSyncProgressSnapshot(
                    action: .checkConsistency,
                    completedStudents: index,
                    totalStudents: total,
                    currentStudentName: student.name,
                    currentFilePath: nil
                )
            )
            do {
                let summary = try TeachingCourseWorkflowService.checkStudentConsistency(student: student)
                reportsByStudent[student.name] = summary
                if summary.isHealthy {
                    successCount += 1
                } else {
                    failures.append(
                        .init(
                            studentName: student.name,
                            reason: summary.issues.joined(separator: "；")
                        )
                    )
                }
            } catch {
                failures.append(.init(studentName: student.name, reason: error.localizedDescription))
            }
            await onProgress(
                TeachingCourseSyncProgressSnapshot(
                    action: .checkConsistency,
                    completedStudents: index + 1,
                    totalStudents: total,
                    currentStudentName: student.name,
                    currentFilePath: nil
                )
            )
        }

        return TeachingCourseSyncResult(
            action: .checkConsistency,
            successCount: successCount,
            failures: failures,
            consistencyReportsByStudent: reportsByStudent
        )
    }

    static func stressTestAllStudents(
        students: [TeachingStudentItem],
        rounds: Int,
        onProgress: @escaping @Sendable (TeachingCourseSyncProgressSnapshot) async -> Void
    ) async throws -> TeachingCourseSyncResult {
        let safeRounds = min(max(rounds, 1), 20)
        let total = students.count * safeRounds
        await onProgress(
            TeachingCourseSyncProgressSnapshot(
                action: .stressTest,
                completedStudents: 0,
                totalStudents: max(1, total),
                currentStudentName: nil,
                currentFilePath: "round=0/\(safeRounds)"
            )
        )

        var completed = 0
        var successCount = 0
        var failures: [TeachingCourseSyncResult.Failure] = []
        var reportsByStudent: [String: TeachingCourseConsistencySummary] = [:]

        for round in 1...safeRounds {
            for student in students {
                try Task.checkCancellation()
                await onProgress(
                    TeachingCourseSyncProgressSnapshot(
                        action: .stressTest,
                        completedStudents: completed,
                        totalStudents: max(1, total),
                        currentStudentName: student.name,
                        currentFilePath: "round=\(round)/\(safeRounds)"
                    )
                )
                do {
                    let summary = try TeachingCourseWorkflowService.checkStudentConsistency(student: student)
                    reportsByStudent[student.name] = summary
                    if summary.isHealthy {
                        successCount += 1
                    } else {
                        failures.append(
                            .init(
                                studentName: student.name,
                                reason: "轮次\(round)：\(summary.issues.joined(separator: "；"))"
                            )
                        )
                    }
                } catch {
                    failures.append(
                        .init(
                            studentName: student.name,
                            reason: "轮次\(round)：\(error.localizedDescription)"
                        )
                    )
                }
                completed += 1
                await onProgress(
                    TeachingCourseSyncProgressSnapshot(
                        action: .stressTest,
                        completedStudents: completed,
                        totalStudents: max(1, total),
                        currentStudentName: student.name,
                        currentFilePath: "round=\(round)/\(safeRounds)"
                    )
                )
            }
        }

        return TeachingCourseSyncResult(
            action: .stressTest,
            successCount: successCount,
            failures: failures,
            consistencyReportsByStudent: reportsByStudent
        )
    }

    private static func notebookFileURL(for student: TeachingStudentItem) throws -> URL {
        try ArchiveStorage.ensureArchiveRoot()
            .appendingPathComponent("学生", isDirectory: true)
            .appendingPathComponent(student.name, isDirectory: true)
            .appendingPathComponent("随堂笔记_\(student.name).CSV", isDirectory: false)
    }

}
