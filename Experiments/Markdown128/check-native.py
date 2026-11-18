from pathlib import Path
import subprocess,tempfile
repo=Path(__file__).resolve().parents[2]
src=(repo/'ATeaching/MarkdownEditorView.swift').read_text()
def method(signature):
 start=src.index(signature);return src[start:src.index('\n    }',start)+6]
start=src.index('private final class MarkdownImageDecodeCache')
cache='@MainActor\n'+src[start:src.index('\n}\n',start)+2]
projection=method('    func markdownSourceStringPreservingAttachments()')+'\n'+method('    private func markdownSourceStringPreservingAttachments(in range:')
code='''import AppKit
import ImageIO
private let markdownTextKit2AttachmentSourceTokenKey = NSAttributedString.Key("MarkdownTextKit2AttachmentSourceToken")
enum MarkdownTextKit2Diagnostic38 {
 static func now() -> UInt64 { 0 }
 static func milliseconds(since:UInt64) -> Double { 0 }
}
'''+cache+'''
@MainActor final class ProbeView: NSTextView {
 var onDiagnostic38Duration: ((String,Double)->Void)?
 var onDiagnostic38Count: ((String,Int)->Void)?
 let isolatedUndo = UndoManager()
 override var undoManager: UndoManager? { isolatedUndo }
 var cachedSourceProjection: String?
 var sourceStorageObserver: NSObjectProtocol?
'''+method('    override func didChangeText()')+'\n'+method('    func seedSourceProjection(')+'\n'+method('    private func observeSourceStorage()')+'\n'+projection+'''
}
'''+r'''
@main struct Run {
 @MainActor static func main() async throws {
  _=NSApplication.shared
  let content=NSTextContentStorage(), layout=NSTextLayoutManager()
  content.addTextLayoutManager(layout)
  let container=NSTextContainer(size:NSSize(width:900,height:CGFloat.greatestFiniteMagnitude))
  layout.textContainer=container
  let view=ProbeView(frame:NSRect(x:0,y:0,width:900,height:700),textContainer:container)
  view.allowsUndo=true; view.isEditable=true; view.isSelectable=true; view.isRichText=false
  view.isolatedUndo.groupsByEvent=false
  let window=NSWindow(contentRect:view.frame,styleMask:[.titled],backing:.buffered,defer:false)
  window.contentView=view; window.makeFirstResponder(view)
  let token="<img src=\"picture.png\" width=\"400\">"
  let original=token+token+"\n中文😀\n"+String(repeating:"paragraph\n",count:10000)
  view.string=original;view.seedSourceProjection(original)
  let storage=view.textStorage!
  // Same token attributes merge; each image anchor must restore exactly once.
  let tokenLength=(token as NSString).length
  for offset in [0,tokenLength] {
   storage.replaceCharacters(in:NSRange(location:offset,length:1),with:"\u{FFFC}")
   storage.addAttribute(markdownTextKit2AttachmentSourceTokenKey,value:token,range:NSRange(location:offset,length:tokenLength))
  }
  view.cachedSourceProjection=nil
  precondition(view.markdownSourceStringPreservingAttachments()==original)
  precondition(view.markdownSourceStringPreservingAttachments()==original)
  view.setSelectedRange(NSRange(location:storage.length,length:0))
  view.isolatedUndo.beginUndoGrouping()
  view.insertText("中文输入",replacementRange:view.selectedRange())
  view.isolatedUndo.endUndoGrouping()
  precondition(view.markdownSourceStringPreservingAttachments()==original+"中文输入")
  view.undoManager?.undo()
  precondition(view.markdownSourceStringPreservingAttachments()==original)
  view.undoManager?.redo()
  precondition(view.markdownSourceStringPreservingAttachments()==original+"中文输入")
  view.isolatedUndo.beginUndoGrouping()
  view.setMarkedText("组合",selectedRange:NSRange(location:2,length:0),replacementRange:view.selectedRange())
  view.insertText("组合完成",replacementRange:view.markedRange())
  view.isolatedUndo.endUndoGrouping()
  precondition(view.markdownSourceStringPreservingAttachments().hasSuffix("组合完成"))
  precondition(view.textLayoutManager != nil)
  // Asynchronous downsampling and cache reuse, with real file decoding.
  let url=URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("image.png")
  let pixels=Data(repeating:255,count:2000*1000*4)
  let provider=CGDataProvider(data:pixels as CFData)!
  let cg=CGImage(width:2000,height:1000,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:8000,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.noneSkipLast.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
  let destination=CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil)!
  CGImageDestinationAddImage(destination,cg,nil);precondition(CGImageDestinationFinalize(destination))
  let cache=MarkdownImageDecodeCache.shared
  var callbacks=0
  precondition(cache.image(at:url,width:200,owner:view,onReady:{callbacks += 1})==nil)
  // Same owner callback is coalesced while request is pending.
  _=cache.image(at:url,width:200,owner:view,onReady:{callbacks += 1})
  for _ in 0..<200 {
   if callbacks>0 { break };try await Task.sleep(nanoseconds:10_000_000)
  }
  precondition(callbacks==1)
  let image=cache.image(at:url,width:200,owner:view,onReady:{callbacks += 1})!
  precondition(image.size.width==400 && image.size.height==200)
  precondition(callbacks==1)
  print("PASS: production source projection/cache, adjacent attachments, native text insertion, undo/redo, marked-text API, TK2 preserved, asynchronous image downsample and request coalescing")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='markdown128-native-') as temp:
 root=Path(temp);(root/'probe.swift').write_text(code)
 subprocess.run(['swiftc','-parse-as-library',str(root/'probe.swift'),'-framework','AppKit','-framework','ImageIO','-o',str(root/'check')],check=True)
 subprocess.run([str(root/'check'),str(root)],check=True,timeout=60)
