import Foundation

@main
struct LatestCloudFileTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("latest-sync-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("records.json")
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let old = Data("old".utf8), newest = Data("newest".utf8)
        _ = try LatestCloudFile.write(newest, to: file, editedAt: base.addingTimeInterval(2))
        let retry = try LatestCloudFile.write(old, to: file, editedAt: base)
        precondition(retry.data == newest, "Old offline retry replaced new remote version")
        precondition(tryRead(file).modifiedAt == base.addingTimeInterval(2), "Retry changed edit time")
        let sameDateA = LatestCloudFile.Snapshot(data: Data("A".utf8), modifiedAt: base)
        let sameDateB = LatestCloudFile.Snapshot(data: Data("B".utf8), modifiedAt: base)
        precondition(LatestCloudFile.prefers(sameDateA, over: sameDateB) != LatestCloudFile.prefers(sameDateB, over: sameDateA))
        for order in [[sameDateA, sameDateB], [sameDateB, sameDateA]] {
            let path = root.appendingPathComponent(UUID().uuidString)
            for version in order { _ = try LatestCloudFile.write(version.data, to: path, editedAt: version.modifiedAt) }
            let expected = LatestCloudFile.prefers(sameDateA, over: sameDateB) ? sameDateA : sameDateB
            precondition(tryRead(path).data == expected.data, "Equal-time saves diverged")
        }
        // Out-of-order delivery, including a stale retry after the most recent save.
        for n in [4, 1, 7, 3, 9, 8, 2] {
            _ = try LatestCloudFile.write(Data("\(n)".utf8), to: file, editedAt: base.addingTimeInterval(Double(n)))
        }
        precondition(tryRead(file).data == Data("9".utf8))
        precondition(tryRead(file).modifiedAt == base.addingTimeInterval(9))
        let pending = LatestCloudFile.Snapshot(data: old, modifiedAt: base)
        precondition(!LatestCloudFile.prefers(pending, over: tryRead(file)))
        let concurrent = root.appendingPathComponent("concurrent.json")
        let group = DispatchGroup()
        for n in 0..<32 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                _ = try! LatestCloudFile.write(Data("\(n)".utf8), to: concurrent, editedAt: base.addingTimeInterval(Double(n)))
            }
        }
        group.wait()
        precondition(tryRead(concurrent).data == Data("31".utf8), "Concurrent writers did not converge to newest edit")
        print("PASS: latest save wins; stale retries cannot roll back; edit times survive retries; equal timestamps converge; out-of-order saves converge")
    }
    static func tryRead(_ url: URL) -> LatestCloudFile.Snapshot { try! LatestCloudFile.read(url) }
}
