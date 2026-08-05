import Foundation

@MainActor
final class TeachingCourseConsistencyScheduler {
    static let shared = TeachingCourseConsistencyScheduler()

    private let dailyKeyDefaultsKey = "TeachingCourseConsistencyScheduler.dailyKey"
    private var timer: Timer?
    private var classEndObserver: NSObjectProtocol?
    private var isRunning = false

    func bootstrapIfNeeded() {
        guard timer == nil else { return }
        runDailyIfNeeded(force: false)
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            guard let scheduler = self else { return }
            Task { @MainActor in
                scheduler.runDailyIfNeeded(force: false)
            }
        }
        classEndObserver = NotificationCenter.default.addObserver(
            forName: TeachingBackupScheduler.classEndedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let scheduler = self else { return }
            Task { @MainActor in
                scheduler.runDailyIfNeeded(force: true)
            }
        }
    }

    private func runDailyIfNeeded(force: Bool) {
        let dayKey = Self.dayStamp(for: Date())
        let defaults = UserDefaults.standard
        if !force, defaults.string(forKey: dailyKeyDefaultsKey) == dayKey {
            return
        }
        guard !isRunning else { return }
        isRunning = true

        Task(priority: .utility) {
            defer {
                Task { @MainActor in
                    self.isRunning = false
                }
            }
            do {
                let students = try TeachingStudentSettingsStore.loadStudents()
                guard !students.isEmpty else {
                    UserDefaults.standard.set(dayKey, forKey: dailyKeyDefaultsKey)
                    return
                }

                let jobID = await TeachingCourseJobCenter.shared.createJob(
                    title: force ? "自动巡检（下课）" : "自动巡检（每日）",
                    action: .checkConsistency,
                    totalUnits: students.count
                )
                await TeachingCourseJobCenter.shared.markRunning(jobID, message: "自动巡检启动")

                let result = try await TeachingCourseSyncService.checkAllStudentsConsistency(students: students) { snapshot in
                    await TeachingCourseJobCenter.shared.updateProgress(
                        jobID,
                        completedUnits: snapshot.completedStudents,
                        totalUnits: snapshot.totalStudents,
                        message: "\(snapshot.action.displayName) · \(snapshot.completedStudents)/\(snapshot.totalStudents)",
                        currentStudentName: snapshot.currentStudentName,
                        currentFilePath: snapshot.currentFilePath
                    )
                }

                let summary = "自动巡检完成：健康\(result.successCount) / 总计\(students.count)"
                if result.failures.isEmpty {
                    await TeachingCourseJobCenter.shared.markSucceeded(jobID, message: summary)
                } else {
                    await TeachingCourseJobCenter.shared.markFailed(
                        jobID,
                        message: summary,
                        failedStudentNames: result.failures.map(\.studentName),
                        consistencyReportsByStudent: result.consistencyReportsByStudent
                    )
                }
                UserDefaults.standard.set(dayKey, forKey: dailyKeyDefaultsKey)
            } catch {
                let jobID = await TeachingCourseJobCenter.shared.createJob(
                    title: force ? "自动巡检（下课）" : "自动巡检（每日）",
                    action: .checkConsistency,
                    totalUnits: 1
                )
                await TeachingCourseJobCenter.shared.markFailed(jobID, message: "自动巡检失败：\(error.localizedDescription)")
            }
        }
    }

    private static func dayStamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
