import Foundation

struct TeachingCourseJobSnapshot: Hashable, Identifiable {
    enum State: String, Hashable {
        case pending
        case running
        case succeeded
        case failed
        case cancelled
    }

    var id: UUID
    var title: String
    var action: TeachingCourseSyncProgressSnapshot.Action?
    var state: State
    var completedUnits: Int
    var totalUnits: Int
    var message: String
    var currentStudentName: String?
    var currentFilePath: String?
    var failedStudentNames: [String]
    var consistencyReportsByStudent: [String: TeachingCourseConsistencySummary]
    var readinessReport: TeachingCommercialReadinessReport?
    var startedAt: Date
    var finishedAt: Date?

    var fractionCompleted: Double {
        guard totalUnits > 0 else { return 0 }
        return min(1, max(0, Double(completedUnits) / Double(totalUnits)))
    }
}

actor TeachingCourseJobCenter {
    static let shared = TeachingCourseJobCenter()

    private var jobs: [UUID: TeachingCourseJobSnapshot] = [:]

    @discardableResult
    func createJob(
        title: String,
        action: TeachingCourseSyncProgressSnapshot.Action? = nil,
        totalUnits: Int
    ) -> UUID {
        let id = UUID()
        jobs[id] = TeachingCourseJobSnapshot(
            id: id,
            title: title,
            action: action,
            state: .pending,
            completedUnits: 0,
            totalUnits: max(1, totalUnits),
            message: "已创建",
            currentStudentName: nil,
            currentFilePath: nil,
            failedStudentNames: [],
            consistencyReportsByStudent: [:],
            readinessReport: nil,
            startedAt: Date(),
            finishedAt: nil
        )
        return id
    }

    func markRunning(_ id: UUID, message: String) {
        guard var job = jobs[id] else { return }
        job.state = .running
        job.message = message
        jobs[id] = job
    }

    func updateProgress(
        _ id: UUID,
        completedUnits: Int,
        totalUnits: Int,
        message: String,
        currentStudentName: String?,
        currentFilePath: String?
    ) {
        guard var job = jobs[id] else { return }
        job.state = .running
        job.completedUnits = max(0, completedUnits)
        job.totalUnits = max(1, totalUnits)
        job.message = message
        job.currentStudentName = currentStudentName
        job.currentFilePath = currentFilePath
        jobs[id] = job
    }

    func markSucceeded(_ id: UUID, message: String) {
        guard var job = jobs[id] else { return }
        job.state = .succeeded
        job.message = message
        job.completedUnits = job.totalUnits
        job.failedStudentNames = []
        job.consistencyReportsByStudent = [:]
        job.readinessReport = nil
        job.finishedAt = Date()
        jobs[id] = job
    }

    func markFailed(
        _ id: UUID,
        message: String,
        failedStudentNames: [String] = [],
        consistencyReportsByStudent: [String: TeachingCourseConsistencySummary] = [:]
    ) {
        guard var job = jobs[id] else { return }
        job.state = .failed
        job.message = message
        job.failedStudentNames = failedStudentNames
        job.consistencyReportsByStudent = consistencyReportsByStudent
        job.readinessReport = nil
        job.finishedAt = Date()
        jobs[id] = job
    }

    func markCancelled(_ id: UUID, message: String) {
        guard var job = jobs[id] else { return }
        job.state = .cancelled
        job.message = message
        job.failedStudentNames = []
        job.consistencyReportsByStudent = [:]
        job.readinessReport = nil
        job.finishedAt = Date()
        jobs[id] = job
    }

    func attachReadinessReport(_ id: UUID, report: TeachingCommercialReadinessReport) {
        guard var job = jobs[id] else { return }
        job.readinessReport = report
        jobs[id] = job
    }

    func snapshot(id: UUID) -> TeachingCourseJobSnapshot? {
        jobs[id]
    }

    func latestSnapshots(limit: Int = 20) -> [TeachingCourseJobSnapshot] {
        jobs.values
            .sorted { lhs, rhs in
                let left = lhs.finishedAt ?? lhs.startedAt
                let right = rhs.finishedAt ?? rhs.startedAt
                return left > right
            }
            .prefix(max(1, limit))
            .map { $0 }
    }

    /// 学生改名等跨文件事务用此避开正在运行的同步任务。
    func hasActiveJobs() -> Bool {
        jobs.values.contains { $0.state == .pending || $0.state == .running }
    }
}
