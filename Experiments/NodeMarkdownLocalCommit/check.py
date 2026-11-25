"""Compile production logic in isolation; only workspace location is a temporary fixture.
Compare incremental package tracking against full reconciliation, exercise real image stash I/O,
and exercise notification gating/persistence sharing with controlled asynchronous adapters.
"""
from pathlib import Path
import re, subprocess, tempfile, sys
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
                 'func recordStructuralMutation(', 'func newPackageDisplayItems(', 'func dirtyPackageDisplayItems(',
                 'func localPendingCount(', 'private func isNewPackageRoot(', 'private func hasCompleteSourceLink(',
                 'private func addNewPackage(nodeID:', 'private func reconcileNewPackageList(', 'private func removeNewPackage(']
tracker_code = '''@MainActor
final class TeachingCoursePackageChangeTracker {
 struct PackageDisplayItem: Equatable {
  let id: String
  let title: String
  let sourceFile: String
 }
 var activeRowSnapshot: Int? = nil
 var dirtyPackageIDs: Set<String> = []
 var newPackageOrderedIDs: [String] = []
 var newPackageIDSet: Set<String> = []
 var baselineDigestByH3ID: [String: String] = [:]
 var packageDigestSnapshot: TeachingCoursePackageContentSignature.DigestSnapshot?
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
transaction_file = (repo/'ATeaching/NodeMarkdownLegacyEditorTransactions.swift').read_text()
for name in ('NodeMarkdownLegacyDocumentSnapshot', 'NodeMarkdownStructuralDelta', 'NodeMarkdownTextKitRowMetadata'):
    source += typ(transaction_file, 'nonisolated struct '+name) + '\n'
for name in ('NodeMarkdownProseMirrorCore', 'NodeMarkdownProseMirrorRuntime',
             'NodeMarkdownTextKit2DocumentState', 'NodeMarkdownTextKit2Range', 'NodeMarkdownLegacyAttachmentSourceRepair'):
    source += (repo/f'ATeaching/{name}.swift').read_text() + '\n'
codec = (repo/'ATeaching/NodeMarkdownTextKitEditor.swift').read_text()
codec_start = codec.index('nonisolated enum NodeMarkdownPlainTextCodec {')
source += codec[codec_start:codec.index('    nonisolated static func parse(\n        text:', codec_start)] + '}\n'
source += r'''
@MainActor func assertEquivalent(_ a: TeachingCoursePackageChangeTracker, _ b: TeachingCoursePackageChangeTracker) {
 precondition(a.dirtyPackageIDs == b.dirtyPackageIDs)
 precondition(a.newPackageOrderedIDs == b.newPackageOrderedIDs)
 precondition(a.baselineDigestByH3ID == b.baselineDigestByH3ID)
}
@MainActor func structuralTests() {
 let root = NodeMarkdownNode(level: 3, text: "A", sourceID: UUID().uuidString, sourceFile: "mother.csv")
 let child = NodeMarkdownNode(level: 4, text: "前后")
 let boundary = NodeMarkdownNode(level: 2, text: "chapter")
 let orphan = NodeMarkdownNode(level: 4, text: "outside")
 let fresh = NodeMarkdownNode(level: 3, text: "new")
 let tail = NodeMarkdownNode(level: 4, text: "body")
 let linked = NodeMarkdownNode(level: 3, text: "B", sourceID: UUID().uuidString, sourceFile: "mother.csv")
 let fixture = NodeMarkdownDocument(nodes: [root, child, boundary, orphan, fresh, tail, linked])
 let metadata = fixture.nodes.map {
  NodeMarkdownTextKitRowMetadata(nodeID: $0.id.uuidString, level: $0.level, sourceID: $0.sourceID, sourceFile: $0.sourceFile)
 }
 let state = NodeMarkdownTextKit2DocumentState(text: NodeMarkdownPlainTextCodec.serialize(document: fixture), rowMetadata: metadata)
 let session = UUID()
 let token = UUID()
 var clock = Date().addingTimeInterval(60)
 func snapshot() -> NodeMarkdownLegacyDocumentSnapshot {
  .init(sessionID: session, revision: state.revision, rows: state.nodes.map(\.legacySnapshotRow))
 }
 var initial = NodeMarkdownPlainTextCodec.parse(snapshot: snapshot(), previousNodes: fixture.nodes, now: clock)
 initial.propagateChildMtimeToH3Roots()
 var previous = initial
 var previousMetadata = snapshot().rowMetadata
 let full = TeachingCoursePackageChangeTracker(), deltaTracker = TeachingCoursePackageChangeTracker()
 full.establishBaseline(document: initial)
 deltaTracker.establishBaseline(document: initial)
 func compare(_ result: NodeMarkdownTransactionResult) {
  clock += 1
  let next = snapshot()
  let oldIndex = NodeMarkdownDocumentIndex(nodes: previous.nodes)
  let delta = state.structuralDelta(for: result, baseline: token, oldCount: previous.nodes.count)
  let applied = delta.applying(to: previous, index: oldIndex, rowMetadata: previousMetadata, now: clock)!
  var actual = applied.document
  let index = NodeMarkdownDocumentIndex(nodes: actual.nodes)
  let impacted = actual.maintainH3AfterStructuralEdit(previous: previous, changedIDs: result.affectedNodeIDs, previousIndex: oldIndex, currentIndex: index, at: clock)
  var expected = NodeMarkdownPlainTextCodec.parse(snapshot: next, previousNodes: previous.nodes, now: clock)
  _ = expected.restoreMissingH3SourceLinks(from: previous)
  _ = expected.touchChangedH3Packages(comparedTo: previous, at: clock)
  expected.propagateChildMtimeToH3Roots()
  precondition(actual == expected, "Node or H3 time diverged at revision \(state.revision)")
  precondition(applied.metadata == next.rowMetadata && actual.nodes.map(\.text).joined(separator: "\n") == next.plainText)
  _ = full.recordDocumentMutation(previousDocument: previous, currentDocument: expected, collectNewPackages: false)
  deltaTracker.recordStructuralMutation(previous: previous, current: actual, affectedH3IDs: impacted, previousIndex: oldIndex, currentIndex: index)
  let expectedNew = full.newPackageDisplayItems(document: expected)
  let actualNew = deltaTracker.newPackageDisplayItems(document: actual, structuralIndex: index, affectedH3IDs: impacted)
  precondition(expectedNew == actualNew)
  precondition(full.dirtyPackageDisplayItems(document: expected) == deltaTracker.dirtyPackageDisplayItems(document: actual, structuralIndex: index))
  assertEquivalent(full, deltaTracker)
  previous = actual
  previousMetadata = applied.metadata
 }
 func edit(_ steps: [NodeMarkdownTransactionStep]) {
  compare(state.dispatch(.init(baseRevision: state.revision, steps: steps, label: "delta regression"))!)
 }
 let newID = UUID()
 edit([.splitNode(nodeID: child.id, offset: 1, newNodeID: newID, newLevel: 4)])
 compare(state.undo()!)
 compare(state.redo()!)
 edit([.joinNodes(leftID: child.id, rightID: newID)])
 edit([.moveNodes(nodeIDs: [child.id], destinationRow: state.nodes.count)])
 edit([.setLevel(nodeID: boundary.id, level: 4)])
 edit([.setLevel(nodeID: orphan.id, level: 3)])
 edit([.deleteNodes(nodeIDs: [fresh.id, tail.id])])
 compare(state.undo()!)
 edit([.moveNodes(nodeIDs: [boundary.id, orphan.id], destinationRow: state.nodes.count)])
 edit([.deleteNodes(nodeIDs: [boundary.id, orphan.id])])
 var seed: UInt64 = 719
 for _ in 0..<150 {
  seed = seed &* 6364136223846793005 &+ 1
  let row = Int((seed >> 32) % UInt64(state.nodes.count))
  let node = state.nodes[row]
  switch seed % 4 {
  case 0:
   let new = NodeMarkdownTextKit2Node(id: UUID(), level: Int((seed >> 16) % 5) + 1, content: "随机", sourceID: "", sourceFile: "")
   edit([.insertNodes(row: row, nodes: [new])])
  case 1 where !node.isProtectedH3:
   edit([.setLevel(nodeID: node.id, level: Int((seed >> 16) % 5) + 1)])
  case 2 where !node.isProtectedH3 && state.nodes.count > 2:
   edit([.deleteNodes(nodeIDs: [node.id])])
  case 3:
   edit([.moveNodes(nodeIDs: [node.id], destinationRow: Int((seed >> 16) % UInt64(state.nodes.count + 1)))])
  default: break
  }
 }
 print("PASS: transaction delta splice, H3 ownership/time, package queues and undo/redo")
}
@MainActor func benchmarkStructuralCommits() {
 let now = Date()
 for count in [200, 1000, 3000, 11770] {
  let nodes = (0..<count).map { row in
   row % 10 == 0
    ? NodeMarkdownNode(level: 3, text: "课堂练习", sourceID: UUID().uuidString, sourceFile: "mother.csv", mtimeCache: now)
    : NodeMarkdownNode(level: 4, text: "物理实验、公式与笔记", mtimeCache: now)
  }
  let previous = NodeMarkdownDocument(nodes: nodes)
  let text = NodeMarkdownPlainTextCodec.serialize(document: previous)
  let metadata = nodes.map {
   NodeMarkdownTextKitRowMetadata(nodeID: $0.id.uuidString, level: $0.level, sourceID: $0.sourceID, sourceFile: $0.sourceFile)
  }
  let oldIndex = NodeMarkdownDocumentIndex(nodes: nodes)
  var fullSamples: [Double] = [], deltaSamples: [Double] = []
  for iteration in 0..<24 {
   for useDelta in (iteration.isMultiple(of: 2) ? [false, true] : [true, false]) {
    let tracker = TeachingCoursePackageChangeTracker()
    tracker.establishBaseline(document: previous)
    let state = NodeMarkdownTextKit2DocumentState(text: text, rowMetadata: metadata)
    let split = NodeMarkdownTransaction(
     baseRevision: state.revision,
     steps: [.splitNode(nodeID: nodes[1].id, offset: 3, newNodeID: UUID(), newLevel: 4)], label: "split"
    )
    let start = ProcessInfo.processInfo.systemUptime
    let result = state.dispatch(split)!
    if useDelta {
     let delta = state.structuralDelta(for: result, baseline: state.documentID, oldCount: count)
     let applied = delta.applying(to: previous, index: oldIndex, rowMetadata: metadata, now: now)!
     var current = applied.document
     let index = NodeMarkdownDocumentIndex(nodes: current.nodes)
     precondition(current.nodes.map(\.text).joined(separator: "\n").utf8.count > 0)
     let affected = current.maintainH3AfterStructuralEdit(previous: previous, changedIDs: result.affectedNodeIDs, previousIndex: oldIndex, currentIndex: index, at: now)
     tracker.recordStructuralMutation(previous: previous, current: current, affectedH3IDs: affected, previousIndex: oldIndex, currentIndex: index)
     precondition(tracker.dirtyPackageDisplayItems(document: current, structuralIndex: index).count == 1)
     precondition(tracker.newPackageDisplayItems(document: current, structuralIndex: index, affectedH3IDs: affected).isEmpty)
    } else {
     let snapshot = NodeMarkdownLegacyDocumentSnapshot(sessionID: state.documentID, revision: state.revision, rows: state.nodes.map(\.legacySnapshotRow))
     var current = NodeMarkdownPlainTextCodec.parse(snapshot: snapshot, previousNodes: nodes, now: now)
     let index = NodeMarkdownDocumentIndex(nodes: current.nodes)
     _ = current.restoreMissingH3SourceLinks(from: previous)
     _ = current.touchChangedH3Packages(comparedTo: previous, at: now, currentStructuralIndex: index, previousStructuralIndex: oldIndex)
     current.propagateChildMtimeToH3Roots()
     precondition(snapshot.plainText.utf8.count > 0 && snapshot.rowMetadata.count == count + 1)
     _ = tracker.recordDocumentMutation(previousDocument: previous, currentDocument: current, collectNewPackages: false, previousStructuralIndex: oldIndex, currentStructuralIndex: index)
     precondition(tracker.dirtyPackageDisplayItems(document: current).count == 1)
     precondition(tracker.newPackageDisplayItems(document: current).isEmpty)
    }
    let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000
    if iteration >= 4 {
     if useDelta { deltaSamples.append(elapsed) } else { fullSamples.append(elapsed) }
    }
   }
  }
  let full = fullSamples.sorted(), delta = deltaSamples.sorted()
  print("SPLIT \(count): full median \(full[full.count/2])ms, delta median \(delta[delta.count/2])ms")
 }
}

@MainActor func tests() throws {
 structuralTests()
 if CommandLine.arguments.contains("--bench-structural") { benchmarkStructuralCommits() }
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
  let old = TeachingCoursePackageContentSignature.DigestSnapshot(document: initial)
  let incremental = TeachingCoursePackageContentSignature.DigestSnapshot(document: after, reusing: old)
  precondition(incremental.digests == TeachingCoursePackageContentSignature.digestByH3ID(in: after))
  let reverted = TeachingCoursePackageContentSignature.DigestSnapshot(document: initial, reusing: incremental)
  precondition(reverted.digests == old.digests)
 }
 let timestamp = Date(timeIntervalSince1970: 12345)
 let independent = TeachingCoursePackageChangeTracker(), shared = TeachingCoursePackageChangeTracker()
 independent.establishBaseline(document: initial); shared.establishBaseline(document: initial)
 var promoted = initial; promoted.nodes[1].level = 3
 var moved = initial; moved.nodes.insert(moved.nodes.remove(at: 1), at: 3)
 var removed = initial; removed.nodes.removeSubrange(0..<2)
 var split = initial; split.nodes.insert(.init(level: 4, text: "split"), at: 2)
 var missingLink = initial; missingLink.nodes[0].sourceFile = ""
 var previous = initial
 var cachedIndex = NodeMarkdownDocumentIndex(nodes: initial.nodes)
 precondition(!cachedIndex.matchesStructure(of: moved.nodes) && !cachedIndex.matchesStructure(of: promoted.nodes))
 for draft in [promoted, initial, promoted, initial, moved, removed, split, missingLink] {
  var expected = draft, actual = draft
  precondition(cachedIndex.matchesStructure(of: previous.nodes))
  let nextIndex = cachedIndex.matchesStructure(of: draft.nodes) ? cachedIndex : .init(nodes: draft.nodes)
  _ = expected.restoreMissingH3SourceLinks(from: previous)
  _ = actual.restoreMissingH3SourceLinks(from: previous)
  let expectedIDs = expected.touchChangedH3Packages(comparedTo: previous, at: timestamp)
  let actualIDs = actual.touchChangedH3Packages(comparedTo: previous, at: timestamp, currentStructuralIndex: nextIndex, previousStructuralIndex: cachedIndex)
  expected.propagateChildMtimeToH3Roots()
  actual.propagateChildMtimeToH3Roots()
  precondition(actual == expected && actualIDs == expectedIDs)
  _ = independent.recordDocumentMutation(previousDocument: previous, currentDocument: expected, collectNewPackages: false)
  _ = shared.recordDocumentMutation(previousDocument: previous, currentDocument: actual, collectNewPackages: false, previousStructuralIndex: cachedIndex, currentStructuralIndex: nextIndex)
  assertEquivalent(independent, shared)
  precondition(independent.packageDigestSnapshot?.digests == shared.packageDigestSnapshot?.digests)
  for row in actual.nodes.indices {
   precondition(shared.packageDigestSnapshot?.index.owningH3Row(for: row) == independent.packageDigestSnapshot?.index.owningH3Row(for: row))
  }
  previous = actual; cachedIndex = nextIndex
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
 args = [str(root/'check'), str(root/'workspace')]
 args.append(str(root/'results.json' if '--check-only' in sys.argv else repo/'Experiments/NodeMarkdownLocalCommit/results.json'))
 if '--bench-structural' in sys.argv:
    args.append('--bench-structural')
 subprocess.run(args,check=True)
