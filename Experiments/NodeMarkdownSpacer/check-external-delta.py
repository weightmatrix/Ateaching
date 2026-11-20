"""Exercise production row diffs and viewport preservation with a real NSTableView."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'ATeaching/NodeMarkdownProseMirrorEditor.swift').read_text()
delta = 'struct NodeMarkdownExternalRowDelta' + source.split('struct NodeMarkdownExternalRowDelta', 1)[1].split('private struct NodeMarkdownBlockRenderRecord', 1)[0]
table_delta = 'func applyStructuralTableDelta' + source.split('private func applyStructuralTableDelta', 1)[1].split('private func cancelStructuralEdit', 1)[0]
viewport = 'private func viewportAnchor' + source.split('private func viewportAnchor', 1)[1].split('private func restorePendingViewportAnchorIfPossible', 1)[0]

swift = '''import AppKit
struct NodeMarkdownTextKit2Node: Equatable {
    let id = UUID()
}
enum NodeMarkdownTransactionStep {
    case deleteNodes(nodeIDs: [UUID])
    case insertNodes(row: Int, nodes: [NodeMarkdownTextKit2Node])
}
struct NodeMarkdownTransactionResult {
    let impact: Impact
    struct Impact {
        var deletedNodeIDs: Set<UUID> = []
        var layoutNodeIDs: Set<UUID> = []
    }
}
struct TestState {
    var nodes: [NodeMarkdownTextKit2Node]
    var snapshot: Self { self }
    func node(at row: Int) -> NodeMarkdownTextKit2Node? { nodes.indices.contains(row) ? nodes[row] : nil }
    func row(for id: UUID) -> Int? { nodes.firstIndex { $0.id == id } }
}
struct TestCache {
    func invalidate(nodeID: UUID) {}
    func retain(nodeIDs: Set<UUID>) {}
}
''' + delta + '''
final class Harness: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var state = TestState(nodes: (0..<150).map { _ in NodeMarkdownTextKit2Node() })
    var tableView: NSTableView?
    var readyRowCount = 150
    var initialViewportIsReady = true
    var jumpedToTop = false
    var showsBottomPageMargin: Bool { readyRowCount > 0 && readyRowCount == state.nodes.count }
    var renderCache = TestCache()
    var exactGeometries: [UUID: CGFloat] = [:]
    var textViewsByNodeID: [UUID: NSView] = [:]
    @objc func sampleViewport(_ notification: Notification) {
        if let clip = notification.object as? NSClipView, clip.bounds.minY < 1 { jumpedToTop = true }
    }
    func cancelExactLayout() {}
    func scheduleExactLayout() {}
    func installExactStaticGeometry(at row: Int, notifyTable: Bool) {}
    func numberOfRows(in tableView: NSTableView) -> Int { readyRowCount + (showsBottomPageMargin ? 1 : 0) }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { row == readyRowCount ? 35 : 48 }
''' + table_delta + viewport + '''
    func apply(target: [NodeMarkdownTextKit2Node], in scroll: NSScrollView) {
        let delta = NodeMarkdownExternalRowDelta(current: state.nodes, target: target, readyCount: readyRowCount)!
        let removals = IndexSet(delta.removedRows.filter { $0 < readyRowCount })
        let insertions = IndexSet(delta.insertedRows.filter { $0 < delta.targetReadyCount })
        let anchor = viewportAnchor(excluding: delta.removedRows)!
        var computed = state.nodes
        for step in delta.steps {
            switch step {
            case let .deleteNodes(nodeIDs): computed.removeAll { nodeIDs.contains($0.id) }
            case let .insertNodes(row, nodes): computed.insert(contentsOf: nodes, at: row)
            }
        }
        precondition(computed == target)
        let deleted = Set(delta.removedRows.map { state.nodes[$0].id })
        state.nodes = target
        applyStructuralTableDelta(result: .init(impact: .init(deletedNodeIDs: deleted)),
                                  insertedRows: insertions, removedRows: removals, rowsToReload: [])
        tableView!.layoutSubtreeIfNeeded()
        restoreViewport(anchor: anchor, fallback: nil)
        let expected = tableView!.rect(ofRow: state.row(for: anchor.nodeID)!).minY + anchor.offsetFromRowTop
        precondition(abs(scroll.contentView.bounds.minY - expected) < 1 && expected > 0)
        precondition(tableView!.numberOfRows == numberOfRows(in: tableView!))
    }
}
let app = NSApplication.shared
let harness = Harness()
let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
let scroll = NSScrollView(frame: table.frame)
harness.tableView = table
table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("node")))
table.headerView = nil
table.dataSource = harness
table.delegate = harness
table.intercellSpacing = .zero
scroll.documentView = table
table.reloadData()
scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: 4119))
scroll.contentView.postsBoundsChangedNotifications = true
NotificationCenter.default.addObserver(harness, selector: #selector(Harness.sampleViewport(_:)),
                                       name: NSView.boundsDidChangeNotification, object: scroll.contentView)
let original = harness.state.nodes
harness.apply(target: original.enumerated().filter { ![5, 27, 144].contains($0.offset) }.map(\\.element), in: scroll)
var inserted = harness.state.nodes
inserted.removeLast()
inserted.insert(contentsOf: (0..<195).map { _ in NodeMarkdownTextKit2Node() }, at: 1)
inserted.append(NodeMarkdownTextKit2Node())
harness.apply(target: inserted, in: scroll)
precondition(!harness.jumpedToTop, "row transactions momentarily reset the viewport")
precondition(NodeMarkdownExternalRowDelta(current: original, target: Array(original.reversed()), readyCount: 100) == nil)
print("PASS: noncontiguous cleanup and 195-node insertion preserve the visible row and offset")
'''

with tempfile.TemporaryDirectory(prefix='node-external-delta-') as temp:
    main = Path(temp) / 'main.swift'
    binary = Path(temp) / 'check'
    main.write_text(swift)
    subprocess.run(['swiftc', str(main), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
