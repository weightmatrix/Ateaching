"""Compile the production viewport/scroll methods into an isolated AppKit smoke test."""
from pathlib import Path
import subprocess
source = Path('ATeaching/MarkdownEditorView.swift').read_text()
def method(start, end):
    text = source[source.index(start):source.index(end, source.index(start))]
    return '\n'.join(line for line in text.splitlines() if 'performanceDiagnostics.checkPipeline' not in line)
visible=method('    private func visibleCharacterRange() -> NSRange? {','    private func selectedNeighborhoodRange()').replace('private func','func')
scroll=method('    func scrollMarkdownSourceLineToCenter(','    private func markdownSourceLineIndex(')
code='''import AppKit
@MainActor final class SmokeView: NSTextView {
'''+visible+scroll+'''
 func markdownSourceRange(forLine line: Int, in text: NSString) -> NSRange {
  var location = 0
  for _ in 0..<line { if location >= text.length { break }; location = NSMaxRange(text.lineRange(for: NSRange(location:location,length:0))) }
  return NSRange(location:min(location,text.length),length:0)
 }
}
@main struct Main {
 @MainActor static func main() {
  _ = NSApplication.shared
  let storage = NSTextContentStorage(), manager = NSTextLayoutManager()
  let container = NSTextContainer(size:NSSize(width:1000,height:CGFloat.greatestFiniteMagnitude))
  storage.addTextLayoutManager(manager);manager.textContainer = container
  let view = SmokeView(frame:NSRect(x:0,y:0,width:1000,height:800),textContainer:container)
  let scroll = NSScrollView(frame:view.frame);scroll.documentView = view
  let window = NSWindow(contentRect:view.frame,styleMask:[.titled],backing:.buffered,defer:false)
  window.contentView = scroll
  view.isVerticallyResizable = true
  view.string = String(repeating:"# 标题\\n正文测试\\n",count:10000)
  manager.textViewportLayoutController.layoutViewport()
  _ = view.visibleCharacterRange()
  precondition(view.textLayoutManager != nil)
  view.scrollMarkdownSourceLineToCenter(500, in:scroll)
  precondition(view.textLayoutManager != nil, "synchronized scroll activated TK1")
  view.textStorage!.replaceCharacters(in:NSRange(location:20,length:0),with:"中文")
  manager.textViewportLayoutController.layoutViewport()
  _ = view.visibleCharacterRange()
  precondition(view.textLayoutManager != nil)
  print("PASS: production viewport and synchronized scroll remain TextKit2 after edit")
 }
}
'''
Path('/tmp/126-pipeline-smoke.swift').write_text(code)
subprocess.run(['swiftc','-parse-as-library','/tmp/126-pipeline-smoke.swift','-o','/tmp/126-pipeline-smoke','-framework','AppKit'],check=True)
subprocess.run(['/tmp/126-pipeline-smoke'],check=True)
