import Foundation

@main
struct TeachingCloudFileAccessTests {
    static func main() throws {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--inspect-conflicted-file" {
            let url = URL(fileURLWithPath: CommandLine.arguments[2])
            let before = try Data(contentsOf: url)
            let conflictsBefore = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
            precondition(!conflictsBefore.isEmpty, "This regression mode requires existing conflicts")
            let readable = try TeachingCloudFileAccess.read(url)
            precondition(readable == before, "Read must return the current file unchanged")
            do {
                try TeachingCloudFileAccess.ensureReady(url)
                fatalError("Write readiness accepted an unresolved conflict")
            } catch TeachingCloudFileAccess.AccessError.conflict { }
            let report = try TeachingCloudConflictResolver.report(at: url)
            precondition(report.conflicts.count == conflictsBefore.count)
            precondition(tryData(url) == before)
            precondition((NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).count == conflictsBefore.count)
            print("PASS: conflicted current file readable; write validation rejected; version report readable; file and conflict versions untouched (students=\(report.current.studentCount ?? -1), conflicts=\(report.conflicts.count))")
            return
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ATeaching-cloud-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("record.json")
        let first = Data("first".utf8), second = Data("second".utf8), stale = Data("stale edit".utf8)
        try TeachingCloudFileAccess.write(first, to: file, expectedDigest: nil)
        let baseline = TeachingCloudFileAccess.digest(try TeachingCloudFileAccess.read(file))
        try TeachingCloudFileAccess.write(second, to: file, expectedDigest: baseline)
        do {
            try TeachingCloudFileAccess.write(stale, to: file, expectedDigest: baseline)
            fatalError("Stale writer was accepted")
        } catch TeachingCloudFileAccess.AccessError.changed { }
        precondition(tryData(file) == second)
        do {
            try TeachingCloudFileAccess.write(first, to: file, expectedDigest: nil)
            fatalError("Baseline-free overwrite was accepted")
        } catch TeachingCloudFileAccess.AccessError.missingBaseline { }
        try TeachingCloudFileAccess.write(second, to: file, expectedDigest: baseline) // idempotent retry
        try fm.removeItem(at: file)
        do {
            try TeachingCloudFileAccess.write(stale, to: file, expectedDigest: baseline)
            fatalError("Unexpectedly deleted file was resurrected")
        } catch TeachingCloudFileAccess.AccessError.changed { }
        precondition(!fm.fileExists(atPath: file.path))
        let empty = root.appendingPathComponent("empty.json")
        try Data(" [ ] \n".utf8).write(to: empty)
        try TeachingCloudFileAccess.write(Data("[1]".utf8), to: empty, expectedDigest: nil, allowReplacingEmptyArray: true)
        do {
            try TeachingCloudFileAccess.write(Data("[2]".utf8), to: empty, expectedDigest: nil, allowReplacingEmptyArray: true)
            fatalError("Nonempty array was treated as initial empty collection")
        } catch TeachingCloudFileAccess.AccessError.missingBaseline { }
        precondition(tryData(empty) == Data("[1]".utf8))
        let concurrent = root.appendingPathComponent("concurrent.json")
        try TeachingCloudFileAccess.write(first, to: concurrent, expectedDigest: nil)
        let state = Results()
        let group = DispatchGroup()
        for value in ["writer-A", "writer-B"] {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    try TeachingCloudFileAccess.write(Data(value.utf8), to: concurrent, expectedDigest: baseline)
                    state.recordSuccess()
                } catch { }
            }
        }
        group.wait()
        precondition(state.count == 1, "Exactly one writer with the shared baseline must succeed")
        precondition([Data("writer-A".utf8), Data("writer-B".utf8)].contains(tryData(concurrent)))
        let preview = try TeachingCloudConflictResolver.report(at: concurrent)
        let externalEdit = Data("external edit after preview".utf8)
        try externalEdit.write(to: concurrent, options: .atomic)
        do {
            try TeachingCloudConflictResolver.keepCurrent(preview)
            fatalError("Stale conflict preview was accepted")
        } catch TeachingCloudFileAccess.AccessError.changed { }
        precondition(tryData(concurrent) == externalEdit)
        let fresh = try TeachingCloudConflictResolver.report(at: concurrent)
        let changedVersionList = TeachingCloudConflictReport(url: fresh.url, currentDigest: fresh.currentDigest,
            current: fresh.current, conflicts: [.init(id: "a-version-that-is-no-longer-present", studentCount: 1, savedAt: "unknown", modifiedAt: nil)])
        do {
            try TeachingCloudConflictResolver.keepCurrent(changedVersionList)
            fatalError("Changed conflict-version list was accepted")
        } catch TeachingCloudFileAccess.AccessError.changed { }
        precondition(tryData(concurrent) == externalEdit)
        let pending = try TeachingCloudFileAccess.preserve(stale, original: file, kind: "pending")
        precondition(tryData(pending) == stale)
        let recovery = try TeachingCloudFileAccess.recoveryRoot()
        for original in [file, empty, concurrent] {
            let key = TeachingCloudFileAccess.digest(Data(original.standardizedFileURL.path.utf8))
            for kind in ["pending", "history"] {
                let folder = recovery.appendingPathComponent(kind).appendingPathComponent(key)
                if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
            }
        }
        print("PASS: creation, stale-write rejection, baseline requirement, idempotent retry, deletion protection, empty-array baseline, concurrent-writer exclusion, stale conflict-preview rejection, changed version-list rejection, recovery content")
    }
    static func tryData(_ url: URL) -> Data { try! Data(contentsOf: url) }
}

private final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var successes = 0
    func recordSuccess() { lock.lock(); defer { lock.unlock() }; successes += 1 }
    var count: Int { lock.lock(); defer { lock.unlock() }; return successes }
}
