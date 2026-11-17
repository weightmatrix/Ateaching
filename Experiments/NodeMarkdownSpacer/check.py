"""Exercise the production publication helper against a real NSTableView."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[2]
src = (root / 'ATeaching/NodeMarkdownProseMirrorEditor.swift').read_text()
helper = src.split('        private func publishReadyRows(', 1)[1].split('        private func buildExactLayout', 1)[0]
helper = '    func publishReadyRows(' + helper
swift = '''import AppKit
final class Harness: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var readyRowCount = 2
    var total = 2
    var initialViewportIsReady = true
    func numberOfRows(in tableView: NSTableView) -> Int {
        readyRowCount + (readyRowCount == total ? 1 : 0)
    }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        row == readyRowCount ? 15 : 113
    }
''' + helper + '''
}
let app = NSApplication.shared
let harness = Harness()
let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("node")))
table.dataSource = harness
table.delegate = harness
table.intercellSpacing = .zero
table.reloadData()
precondition(table.rect(ofRow: 2).height == 15)
// Two consecutive tail insertions, including an intermediate partial layout batch.
for _ in 0..<2 {
    let oldTail = harness.readyRowCount
    harness.total += 4
    harness.publishReadyRows(oldTail + 2, in: table)
    precondition(table.rect(ofRow: oldTail).height == 113, "spacer height survived")
    harness.publishReadyRows(harness.total, in: table)
    precondition(table.rect(ofRow: harness.total).height == 15)
}
print("PASS: consecutive tail insertions replace cached spacer height")
'''
with tempfile.TemporaryDirectory(prefix='node-spacer-') as tmp:
    source = Path(tmp) / 'main.swift'; source.write_text(swift)
    binary = Path(tmp) / 'check'
    subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
