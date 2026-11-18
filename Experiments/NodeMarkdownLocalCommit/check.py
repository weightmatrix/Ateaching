"""Compile production logic in isolation; only workspace location is a temporary fixture.
Compare incremental package tracking against full reconciliation, exercise real image stash I/O,
and exercise notification gating/persistence sharing with controlled asynchronous adapters.
"""
from pathlib import Path
import re, subprocess, tempfile
repo = Path(__file__).resolve().parents[2]
def method(src, signature):
    start = src.index(signature)
    end = src.index('\n    }', start) + len('\n    }')
    return src[start:end]
def typ(src, name):
    start = src.index(name)
    return src[start:src.index('\n}', start)+2]
model = (repo/'ATeaching/NodeMarkdownDocument.swift').read_text()
tracker = (repo/'TeachingCoursePackageChangeTracker.swift').read_text()
images = (repo/'ATeaching/NodeMarkdownImageAssetService.swift').read_text()
editor = (repo/'ATeaching/NodeMarkdownEditorView.swift').read_text()
# Recursively include actual image implementation dependencies, including stash/restore and ownership.
methods = {}
manager = images[images.index('nonisolated enum NodeMarkdownImageResourceManager {'):images.index('\n#if os(macOS)\nenum NodeMarkdownImageAssetService')]
for match in re.finditer(r'^    (?:private )?(?:nonisolated )?static func (\w+)\(', manager, re.M):
    methods.setdefault(match.group(1), []).append(method(manager, match.group(0)))
needed = {'imagePaths', 'parseImageTokens', 'reconcileNodeImages', 'markdownImageToken'}
while True:
    bodies = '\n'.join(m for name in needed for m in methods[name])
    more = {name for name in methods if re.search(r'\b'+name+r'\s*\(', bodies)}
    if more <= needed: break
    needed |= more
image_code = images[images.index('nonisolated enum NodeMarkdownImageResourceManager {'):images.index('    static func formalScope(')]
for name in sorted(needed):
    for body in methods[name]:
        if name == 'reconcileNodeImages': image_code += '    @MainActor\n'
        image_code += body + '\n'
image_code += '}\n' + '@MainActor\n' + typ(images, 'final class NodeMarkdownImageReferenceIndex')
tracker_names = ['func establishBaseline(', 'func recordNodeMutation(', 'func recordDocumentMutation(',
                 'func localPendingCount(', 'private func isNewPackageRoot(', 'private func hasCompleteSourceLink(',
                 'private func addNewPackage(nodeID:', 'private func reconcileNewPackageList(', 'private func removeNewPackage(']
tracker_code = '''@MainActor
final class TeachingCoursePackageChangeTracker {
 var activeRowSnapshot: Int? = nil
 var dirtyPackageIDs: Set<String> = []
 var newPackageOrderedIDs: [String] = []
 var newPackageIDSet: Set<String> = []
 var baselineDigestByH3ID: [String: String] = [:]
 var diagnostic26MutationSequence: UInt64 = 0
'''+ '\n'.join(method(tracker, '    '+name) for name in tracker_names) + '\n}\n'
support = '''import Foundation
import CryptoKit
nonisolated enum ArchiveStorage {
 static let systemFolderName = "系统"
 static let teachingPlanFolderName = "教案"
 static func ensureWorkspace() throws -> URL { URL(fileURLWithPath: CommandLine.arguments[1]) }
}
nonisolated enum NodeMarkdownDiagnostic26 {
 static func log(_ message: @autoclosure () -> String) {}
 static func shortID(_ value: String) -> String { value }
 static func shortDigest(_ value: String?) -> String { value ?? "nil" }
}
'''
# Model, index, package cleaner, signature, parser and actual stash functions are production code.
source = support + model[model.index('nonisolated struct NodeMarkdownNode'):model.index('// MARK: - NodeMarkdown文件协议管理器')]
source += (repo/'ATeaching/NodeMarkdownDocumentIndex.swift').read_text()
source += (repo/'ATeaching/NodeMarkdownPackageCleaner.swift').read_text()
source += (repo/'ATeaching/TeachingCoursePackageContentSignature.swift').read_text()
source += typ(images, 'struct NodeMarkdownImageToken')+'\n'
source += typ(images, 'private struct NodeMarkdownUndoImageStashRecord')+'\n'
source += typ(images, 'nonisolated private struct NodeMarkdownUndoImageStashManifest')+'\n'
source += image_code + "\n" + tracker_code
source += r'''
@MainActor func assertEquivalent(_ a: TeachingCoursePackageChangeTracker, _ b: TeachingCoursePackageChangeTracker) {
 precondition(a.dirtyPackageIDs == b.dirtyPackageIDs)
 precondition(a.newPackageOrderedIDs == b.newPackageOrderedIDs)
 precondition(a.baselineDigestByH3ID == b.baselineDigestByH3ID)
}
@MainActor func tests() throws {
 let rootA = NodeMarkdownNode(level: 3, text: "A", sourceID: UUID().uuidString, sourceFile: "mother.csv")
 let rootB = NodeMarkdownNode(level: 3, text: "B", sourceID: UUID().uuidString, sourceFile: "mother.csv")
 let newRoot = NodeMarkdownNode(level: 3, text: "New")
 let initial = NodeMarkdownDocument(nodes: [rootA, .init(level: 4, text: "original"), rootB, .init(level: 4, text: "other"), newRoot, .init(level: 4, text: "new child"), .init(level: 2, text: "outside")])
 let local = TeachingCoursePackageChangeTracker(), full = TeachingCoursePackageChangeTracker()
 local.establishBaseline(document: initial); full.establishBaseline(document: initial)
 var before = initial
 // Another package stays dirty; reverting A must only clear A. Also blank/nonblank new roots, links, and ownerless nodes.
 for (row, text) in [(3,"edited B"),(1,"edited A"),(1,"original"),(5,"new body"),(4,""),(4,"New again"),(6,"outside edited")] {
  var after = before; after.nodes[row].text = text
  _ = local.recordNodeMutation(previousDocument: before, currentDocument: after, row: row, structuralIndex: .init(nodes: after.nodes))
  _ = full.recordDocumentMutation(previousDocument: before, currentDocument: after)
  assertEquivalent(local, full); before = after
 }
 // Clean source-less package -> linked package initializes baseline like full reconciliation.
 var linked = before; linked.nodes[4].sourceID = UUID().uuidString; linked.nodes[4].sourceFile = "linked.csv"
 _ = local.recordNodeMutation(previousDocument: before, currentDocument: linked, row: 4, structuralIndex: .init(nodes: linked.nodes))
 _ = full.recordDocumentMutation(previousDocument: before, currentDocument: linked); assertEquivalent(local, full)
 // Cached indices must reproduce old affected-H3 timestamp behavior for structural promotion/demotion too.
 for level in [2,3,4] {
  var after = initial; after.nodes[1].level = level
  var a = after, b = after
  let time = Date(timeIntervalSince1970: 12345)
  let expected = a.touchChangedH3Packages(comparedTo: initial, affectedRowIndex: 1, at: time)
  let actual = b.touchChangedH3Packages(comparedTo: initial, affectedRowIndex: 1, currentStructuralIndex: .init(nodes: after.nodes), previousStructuralIndex: .init(nodes: initial.nodes), at: time)
  precondition(expected == actual && a == b)
 }
 let workspace = try ArchiveStorage.ensureWorkspace()
 let notebook = workspace.appendingPathComponent("student/note.csv")
 let image = workspace.appendingPathComponent("系统/暂存/\(newRoot.id.uuidString)/Pic/shared.png")
 try FileManager.default.createDirectory(at: image.deletingLastPathComponent(), withIntermediateDirectories: true)
 let bytes = Data([1,2,3,4]); try bytes.write(to: image)
 let token = "![shared](\(image.path))"
 var doc = NodeMarkdownDocument(nodes: [newRoot, .init(level: 4, text: token+token), .init(level: 4, text: token)])
 var refs: NodeMarkdownImageReferenceIndex?
 func edit(_ row: Int, _ text: String) {
  let prev = doc; doc.nodes[row].text = text
  NodeMarkdownImageResourceManager.reconcileNodeImages(previousNode: prev.nodes[row], currentNode: doc.nodes[row], previousDocument: prev, currentDocument: doc, notebookFileURL: notebook, index: &refs)
 }
 edit(1,"plain") // two occurrences in one node count once; second node still owns it
 precondition(FileManager.default.fileExists(atPath: image.path))
 edit(2,"plain") // last reference goes into real undo stash
 precondition(!FileManager.default.fileExists(atPath: image.path))
 edit(1,token) // undo restores exact bytes
 let restored = try Data(contentsOf: image); precondition(restored == bytes)
 edit(2,"<img src=\"\(image.path)\" width=\"200\">")
 edit(1,"plain")
 precondition(FileManager.default.fileExists(atPath: image.path))
 // Structural replacement invalidates index. Rebuild must retain new shared references.
 doc.nodes.append(.init(level: 4, text: token)); refs = nil
 edit(2,"plain"); precondition(FileManager.default.fileExists(atPath: image.path))
 // Ordinary text-only edits neither build the global reference index nor touch files.
 refs = nil; edit(1,"another plain sentence"); precondition(refs == nil)
 var results: [[String: Any]] = []
 for packages in [10,500,2000] {
  var nodes: [NodeMarkdownNode] = []
  for _ in 0..<packages {
   nodes.append(.init(level: 3, text: "root", sourceID: UUID().uuidString, sourceFile: "mother.csv"))
   for _ in 0..<9 { nodes.append(.init(level: 4, text: "body")) }
  }
  let prev = NodeMarkdownDocument(nodes: nodes); var next = prev; next.nodes[1].text = "changed"
  let index = NodeMarkdownDocumentIndex(nodes: nodes)
  let tracker = TeachingCoursePackageChangeTracker(); tracker.establishBaseline(document: prev)
  let start = ProcessInfo.processInfo.systemUptime
  for _ in 0..<100 { _ = tracker.recordNodeMutation(previousDocument: prev, currentDocument: next, row: 1, structuralIndex: index) }
  results.append(["nodes":nodes.count,"localPackageAverageMs":(ProcessInfo.processInfo.systemUptime-start)*10])
 }
 let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted,.sortedKeys])
 try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
 print("PASS: local/full package equivalence, revert, unrelated dirty preservation, new/link packages, cached H3 touch, actual shared-image stash/undo/HTML/rebuild safety")
}
try MainActor.assumeIsolated { try tests() }
'''
with tempfile.TemporaryDirectory(prefix='node-local-') as tmp:
 root=Path(tmp); src=root/'main.swift'; src.write_text(source)
 subprocess.run(['swiftc','-O',str(src),'-o',str(root/'check')],check=True)
 subprocess.run([str(root/'check'),str(root/'workspace'),str(repo/'Experiments/NodeMarkdownLocalCommit/results.json')],check=True)
