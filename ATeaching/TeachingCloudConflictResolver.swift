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

/// Offers an explicit choice; never picks a winner from timestamps or student counts.
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

    /// Call only after the user confirms retaining the displayed current version.
    static func keepCurrent(_ expected: TeachingCloudConflictReport) throws {
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: expected.url, options: .forMerging, error: &coordinationError) { url in
            result = Result {
                try TeachingCloudFileAccess.ensureReady(url, rejectConflicts: false)
                let current = try Data(contentsOf: url)
                guard TeachingCloudFileAccess.digest(current) == expected.currentDigest else {
                    throw TeachingCloudFileAccess.AccessError.changed(url.lastPathComponent)
                }
                let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
                let contents = try versions.map { try Data(contentsOf: $0.url) }
                let ids = zip(versions, contents).map { describe($0.1, modifiedAt: $0.0.modificationDate).id }.sorted()
                guard ids == expected.conflicts.map(\.id).sorted() else {
                    throw TeachingCloudFileAccess.AccessError.changed("冲突版本列表")
                }
                // Back up EVERY version before setting any resolution flags. Do not delete system versions.
                try TeachingCloudFileAccess.preserve(current, original: expected.url, kind: "conflicts")
                for data in contents { try TeachingCloudFileAccess.preserve(data, original: expected.url, kind: "conflicts") }
                guard TeachingCloudFileAccess.digest(try Data(contentsOf: url)) == expected.currentDigest else {
                    throw TeachingCloudFileAccess.AccessError.changed(url.lastPathComponent)
                }
                let latest = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
                let latestIDs = try latest.map { try describe(Data(contentsOf: $0.url), modifiedAt: $0.modificationDate).id }.sorted()
                guard latestIDs == ids else { throw TeachingCloudFileAccess.AccessError.changed("冲突版本列表") }
                for version in versions { version.isResolved = true }
                guard (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty else {
                    throw NSError(domain: "TeachingCloud", code: 10, userInfo: [NSLocalizedDescriptionKey:
                        "各版本副本已保留，但 iCloud 尚未确认解除冲突，请稍后重新检查。"])
                }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw TeachingCloudFileAccess.AccessError.coordination }
        try result.get()
    }
}
