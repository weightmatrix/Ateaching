import Foundation

@main
struct TeachingCloudFileAccessTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("teaching-latest-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("settings.json")
        try TeachingCloudFileAccess.write(Data("first".utf8), to: file, expectedDigest: nil)
        let baseline = TeachingCloudFileAccess.digest(try TeachingCloudFileAccess.read(file))
        try TeachingCloudFileAccess.write(Data("second".utf8), to: file, expectedDigest: baseline)
        try TeachingCloudFileAccess.write(Data("latest user edit".utf8), to: file, expectedDigest: baseline)
        precondition(tryRead(file) == Data("latest user edit".utf8), "Latest user save was blocked by stale baseline")
        try TeachingCloudFileAccess.write(Data("new save without baseline".utf8), to: file, expectedDigest: nil)
        precondition(tryRead(file) == Data("new save without baseline".utf8))
        let report = try TeachingCloudConflictResolver.report(at: file)
        try TeachingCloudFileAccess.write(Data("after preview".utf8), to: file, expectedDigest: nil)
        try TeachingCloudConflictResolver.keepCurrent(report)
        precondition(tryRead(file) == Data("after preview".utf8), "Stale manual preview rolled back latest save")
        print("PASS: latest saves replace stale baselines; missing baseline does not freeze sync; old conflict preview cannot roll back")
    }
    static func tryRead(_ url: URL) -> Data { try! TeachingCloudFileAccess.read(url) }
}
