"""Run the production async reload gate and persistence lane with controlled I/O adapters."""
from pathlib import Path
import subprocess, tempfile
repo=Path(__file__).resolve().parents[2]
src=(repo/'ATeaching/NodeMarkdownEditorView.swift').read_text()
def method(signature):
 start=src.index(signature); return src[start:src.index('\n    }',start)+6].replace('private func','func',1)
start=src.index('private final class NodeMarkdownPersistFlight')
flight='@MainActor\n'+src[start:src.index('\n}',start)+2]
support=r'''
import Foundation
struct NodeMarkdownNode: Hashable { var id: UUID; var level: Int; var text: String }
struct NodeMarkdownDocument: Hashable {
 var nodes: [NodeMarkdownNode]
 mutating func ensureTrailingBlankLine(defaultLevel: Int) -> Int { 0 }
}
struct NodeMarkdownFileMeta: Hashable { var diskDigest: String?; var diskPath: String? = nil }
struct NodeMarkdownPersistResult { var document: NodeMarkdownDocument; var diskDigest: String }
enum SaveState { case clean, dirty }
final class Storage: @unchecked Sendable {
 let lock = NSLock()
 var document = NodeMarkdownDocument(nodes:[.init(id:UUID(),level:3,text:"original")])
 var meta = NodeMarkdownFileMeta(diskDigest:"a")
 var failure = false
 var reads = 0
 var writes = 0
 var writeInputs: [String?] = []
}
enum NodeMarkdownFileManager {
 static let storage = Storage()
 static func read(fileURL: URL) throws -> (NodeMarkdownDocument,NodeMarkdownFileMeta) {
  Thread.sleep(forTimeInterval:0.03)
  return try storage.lock.withLock {
   storage.reads += 1
   if storage.failure { throw NSError(domain:"fixture",code:1) }
   return (storage.document,storage.meta)
  }
 }
 static func persistToDiskAndPrepare(document: NodeMarkdownDocument, meta: NodeMarkdownFileMeta, to url: URL) async -> Result<NodeMarkdownPersistResult,Error> {
  try? await Task.sleep(nanoseconds:30_000_000)
  let digest = storage.lock.withLock {
   storage.writes += 1; storage.writeInputs.append(meta.diskDigest)
   return "saved-\(storage.writes)"
  }
  return .success(.init(document:document,diskDigest:digest))
 }
}
enum TeachingDebugLogStore {
 static func append(_ text: String,category: String,force: Bool) {}
}
'''
harness=r'''
@MainActor final class Harness {
 var pendingLatestCloudReload = false
 var pendingCloudCheckTask: Task<Void,Never>?
 fileprivate var persistFlight: NodeMarkdownPersistFlight?
 var isLoading = false, isSaveTaskRunning = false, isNotebookWriteOperationInProgress = false, isPackageSyncRunning = false
 var saveState = SaveState.clean
 var documentRevision = 1, persistedDocumentRevision = 1, diskLoadGeneration = 1
 var hasUncommittedLegacyDraft = false
 var fileURL = URL(fileURLWithPath:"/synthetic/note.csv")
 var statusMessage = ""
 var document = NodeMarkdownFileManager.storage.document
 var fileMeta = NodeMarkdownFileManager.storage.meta
 var activeEditorRowIndex: Int? = 0
 var reloads = 0, metadataUpdates = 0
 func reloadFromDisk(reason: String) { reloads += 1 }
 func refreshPendingClassUpdateCount() {}
 func applyMetadataOnlyNotebookReload(parsedDocument: NodeMarkdownDocument, parsedMeta: NodeMarkdownFileMeta, previousDocument: NodeMarkdownDocument, preserveActiveNodeID: UUID?) {
  metadataUpdates += 1; document = parsedDocument; fileMeta = parsedMeta
 }
'''
harness+='\n'.join(method(x) for x in ['    private func applyLatestCloudReloadIfReady()', '    private func documentsHaveSameEditorLayout(', '    private func persistSnapshot('])+'\n}\n'
tests=r'''
@main struct Run {
 @MainActor static func drain(_ h: Harness) async {
  while let task = h.pendingCloudCheckTask { await task.value }
 }
 @MainActor static func main() async {
  let h = Harness(), storage = NodeMarkdownFileManager.storage
  // Repeated notifications during a save do not even issue a read.
  h.isSaveTaskRunning = true
  for _ in 0..<10 { h.pendingLatestCloudReload=true; h.applyLatestCloudReloadIfReady() }
  precondition(h.pendingCloudCheckTask == nil && storage.reads == 0)
  h.isSaveTaskRunning=false; h.applyLatestCloudReloadIfReady(); await drain(h)
  precondition(h.reloads == 0 && h.metadataUpdates == 0 && storage.reads == 1)
  // Same layout, new persisted metadata: no full reload.
  storage.lock.withLock { storage.meta.diskDigest="b" }
  h.pendingLatestCloudReload=true; h.applyLatestCloudReloadIfReady(); await drain(h)
  precondition(h.reloads == 0 && h.metadataUpdates == 1)
  // Actual remote text remains eligible for a full reload.
  storage.lock.withLock { storage.meta.diskDigest="c"; storage.document.nodes[0].text="remote" }
  h.pendingLatestCloudReload=true; h.applyLatestCloudReloadIfReady(); await drain(h)
  precondition(h.reloads == 1)
  // A local edit during the read prevents the stale result from replacing it.
  h.pendingLatestCloudReload=true; h.applyLatestCloudReloadIfReady()
  h.documentRevision += 1; h.hasUncommittedLegacyDraft=true; h.saveState = .dirty
  await drain(h); precondition(h.reloads == 1 && h.pendingLatestCloudReload)
  // Read failure remains pending but does not immediately spin retries.
  h.hasUncommittedLegacyDraft=false; h.saveState = .clean; h.persistedDocumentRevision=h.documentRevision
  storage.lock.withLock { storage.failure=true }
  let before=storage.reads
  h.applyLatestCloudReloadIfReady(); await drain(h)
  precondition(h.pendingLatestCloudReload && storage.reads == before+1)
  storage.lock.withLock { storage.failure=false }
  h.applyLatestCloudReloadIfReady(); await drain(h); precondition(h.reloads == 2)
  // Changes from an old load generation are discarded and checked again.
  h.fileMeta = storage.meta; h.document = storage.document
  h.pendingLatestCloudReload=true; h.applyLatestCloudReloadIfReady(); h.diskLoadGeneration += 1
  await drain(h); precondition(h.reloads == 2)
  // Command-save and sync-save sharing an identical snapshot issue one physical request.
  let doc=h.document, meta=h.fileMeta
  let a=Task { await h.persistSnapshot(doc,meta:meta) }
  let b=Task { await h.persistSnapshot(doc,meta:meta) }
  _ = await a.value; _ = await b.value; precondition(storage.writes == 1)
  var changed=doc; changed.nodes[0].text="newer"
  let c=Task { await h.persistSnapshot(doc,meta:meta) }
  let d=Task { await h.persistSnapshot(changed,meta:meta) }
  _ = await c.value; _ = await d.value; precondition(storage.writes == 3 && storage.writeInputs[2] == "saved-2")
  print("PASS: save deferral/coalescing, same-digest no-op, metadata-only update, actual external edit, local-edit and load-generation races, failed-read retry without spinning, identical save sharing and distinct-save serialization")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='node-reload-') as tmp:
 p=Path(tmp); (p/'probe.swift').write_text(support+flight+harness+tests)
 subprocess.run(['swiftc','-parse-as-library',str(p/'probe.swift'),'-o',str(p/'check')],check=True)
 subprocess.run([str(p/'check')],check=True)
