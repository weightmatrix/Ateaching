import Foundation

enum TeachingCoursePackageSyncExecutor {
    static func previewUpdate(student: TeachingStudentItem) async throws -> TeachingCourseUpdatePreview {
        try await TeachingCourseWorkflowService.previewNotebookUpdate(student: student)
    }

    static func syncDirtyPackages(
        student: TeachingStudentItem,
        placementTarget: TeachingCourseUpdatePlacementTarget?,
        allowedNewPackageIDs: Set<String>? = nil
    ) async throws -> TeachingCourseSyncSummary {
        try await TeachingCourseWorkflowService.syncNotebookDirtyPackages(
            student: student,
            placementTarget: placementTarget,
            allowedNewPackageIDs: allowedNewPackageIDs
        )
    }
}
