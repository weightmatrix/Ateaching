"""Exercise the production Markdown preparation scheduler with synthetic lines."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
source = (repo / "ATeaching/MarkdownEditorView.swift").read_text()
batch = source[source.index("    private func prepareStyleBatch("):source.index("    private func cancelPendingAttachmentStyleWork(")]
program = r"""
import AppKit

struct MarkdownDocumentStyle {}
enum Layers { case all, attachment }
final class Harness {
    let textStorage: NSTextStorage? = NSTextStorage(string: String(repeating: "## Heading\nBody\n", count: 10))
    var idleStyleGeneration = 0
    var pendingIdleStyleWorkItem: DispatchWorkItem?
    var pendingPreparationImages = Set<String>()
    var preparationImageContinuation: (() -> Void)?
    var prepared = Set<Int>()
    var batches = 0
    var finished = false
    var requestedImage = false

    func restoreAttachmentSourceTokens(in line: NSRange) -> Bool { false }
    func applyMarkdownStyle(in line: NSRange, style: MarkdownDocumentStyle, layers: [Layers]) {
        precondition(!finished, "changed a line after reveal")
        if !requestedImage {
            requestedImage = true
            pendingPreparationImages.insert("image")
        } else if layers == [.attachment] {
            precondition(line.location == 0)
        }
        prepared.insert(line.location)
        Thread.sleep(forTimeInterval: 0.001)
    }
    func finishStylePreparation() {
        precondition(prepared.count == 20 && pendingPreparationImages.isEmpty)
        finished = true
        print("PASS: all lines prepared before reveal; image retry and batch yielding")
        exit(0)
    }
    func start() {
        prepareStyleBatch(style: MarkdownDocumentStyle(), generation: 0, startingAt: 0)
        precondition(!finished && prepared.count == 1)
        pendingPreparationImages.removeAll()
        preparationImageContinuation?()
        precondition(!finished && prepared.count < 20 && pendingIdleStyleWorkItem != nil)
    }
""" + batch.replace("retry ? [.attachment] : .all", "retry ? [.attachment] : [.all]") + """
}
let harness = Harness()
harness.start()
dispatchMain()
"""
with tempfile.TemporaryDirectory(prefix="markdown-preparation-") as temp:
    directory = Path(temp)
    main = directory / "main.swift"
    binary = directory / "check"
    main.write_text(program)
    subprocess.run(["swiftc", str(main), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=10)
