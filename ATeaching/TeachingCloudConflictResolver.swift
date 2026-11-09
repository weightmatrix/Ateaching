import Foundation

nonisolated struct TeachingCloudConflictReport: Sendable {
    struct Version: Identifiable, Sendable {
        let id: String
        let studentCount: Int?
        let savedAt: String
        let modifiedAt: Date?
    }
    let url: URL
    let currentDigest: String
    let current: Version
    let conflicts: [Version]
}

/// Latest saved file wins automatically; legacy UI entry points share the same policy.
nonisolated enum TeachingCloudConflictResolver {
    private static func describe(_ data: Data, modifiedAt: Date?) -> TeachingCloudConflictReport.Version {
        let object = try? JSONSerialization.jsonObject(with: data)
        let dict = object as? [String: Any]
        let students = dict?["students"] as? [Any] ?? object as? [Any]
        let digest = TeachingCloudFileAccess.digest(data)
        return .init(id: digest + "|" + String(modifiedAt?.timeIntervalSince1970 ?? 0),
                     studentCount: students?.count, savedAt: dict?["savedAt"] as? String ?? "旧格式／未记录", modifiedAt: modifiedAt)
    }

    static func report(at url: URL) throws -> TeachingCloudConflictReport {
        _ = try LatestCloudFile.read(url)
        var coordinationError: NSError?
        var result: Result<TeachingCloudConflictReport, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            result = Result {
                try TeachingCloudFileAccess.ensureReady(coordinated, rejectConflicts: false)
                let data = try Data(contentsOf: coordinated)
                let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: coordinated) ?? []
                let conflicts = try versions.map { try describe(Data(contentsOf: $0.url), modifiedAt: $0.modificationDate) }
                return TeachingCloudConflictReport(url: url, currentDigest: TeachingCloudFileAccess.digest(data),
                    current: describe(data, modifiedAt: try coordinated.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate),
                    conflicts: conflicts)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw TeachingCloudFileAccess.AccessError.coordination }
        return try result.get()
    }

    /// Compatibility entry point: never let a stale preview select an older version.
    static func keepCurrent(_ expected: TeachingCloudConflictReport) throws {
        _ = try LatestCloudFile.read(expected.url)
    }
}
