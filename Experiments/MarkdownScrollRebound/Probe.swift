import AppKit
@MainActor final class GuardedView: NSTextView {
 var guarded = false
 var until:TimeInterval = 0
 var direction:CGFloat = 0
 var corrections = 0
 override func scrollWheel(with event:NSEvent) {
  until=ProcessInfo.processInfo.systemUptime+0.8; direction=event.scrollingDeltaY
  super.scrollWheel(with:event)
 }
 override func textViewportLayoutControllerDidLayout(_ controller:NSTextViewportLayoutController) {
  let clip=enclosingScrollView?.contentView
  let origin=clip?.bounds.origin
  super.textViewportLayoutControllerDidLayout(controller)
  guard guarded,ProcessInfo.processInfo.systemUptime<until,let clip,let origin else{return}
  let movement=clip.bounds.minY-origin.y
  if (direction>0 && movement>0.5) || (direction<0 && movement < -0.5) {
   corrections += 1;clip.setBoundsOrigin(origin)
  }
 }
}
@MainActor final class Probe: NSObject {
 var window:NSWindow!; var view:NSTextView!; var scroll:NSScrollView!
 var observer:NSObjectProtocol?; var work:DispatchWorkItem?;var timer:Timer?
 var settledJumps=0;var lastSettledY:CGFloat?;var steps=0;var jumps:[String]=[];var previousY:CGFloat=0
 let mode=CommandLine.arguments[2]
 func style(_ full:Bool) {
  guard let storage=view.textStorage,let manager=view.textLayoutManager,let content=manager.textContentManager else{return}
  var range=NSRange(location:0,length:storage.length)
  if !full,let viewport=manager.textViewportLayoutController.viewportRange {
   let a=content.offset(from:content.documentRange.location,to:viewport.location),b=content.offset(from:content.documentRange.location,to:viewport.endLocation)
   range=storage.mutableString.lineRange(for:NSRange(location:max(0,a),length:max(0,b-a)))
  }
  let ns=storage.mutableString
  storage.beginEditing()
  var cursor=range.location
  while cursor<NSMaxRange(range) && cursor<storage.length {
   let r=ns.lineRange(for:NSRange(location:cursor,length:0)),text=ns.substring(with:r)
   let hashes=text.prefix(while:{$0=="#"}).count
   let sizes:[CGFloat]=[15,30,26,22,20,18,16]
   let font=NSFont.monospacedSystemFont(ofSize:sizes[min(6,hashes)],weight:.regular)
   let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byWordWrapping
   let h=max(ceil(font.ascender-font.descender+max(0,font.leading))+6,ceil(font.pointSize*1.6))
   paragraph.minimumLineHeight=h;paragraph.maximumLineHeight=h
   let attrs:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:NSColor.labelColor,.paragraphStyle:paragraph]
   if mode != "idempotent" || !NSDictionary(dictionary:storage.attributes(at:cursor,effectiveRange:nil)).isEqual(to:attrs) {
    storage.setAttributes(attrs,range:r)
   }
   cursor=NSMaxRange(r)
  }
  storage.endEditing()
 }
 func start() throws {
  _=NSApplication.shared;NSApp.setActivationPolicy(.accessory)
  let content=NSTextContentStorage(),manager=NSTextLayoutManager()
  let container=NSTextContainer(size:NSSize(width:927,height:CGFloat.greatestFiniteMagnitude))
  container.widthTracksTextView=true;container.lineFragmentPadding=4
  manager.textContainer=container;content.addTextLayoutManager(manager)
  view=GuardedView(frame:NSRect(x:0,y:0,width:927,height:908),textContainer:container)
  (view as! GuardedView).guarded = mode == "guarded"
  view.isRichText=true;view.isVerticallyResizable=true;view.autoresizingMask = [.width]
  view.minSize = .zero;view.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
  view.textContainerInset=NSSize(width:8,height:8)
  view.font=NSFont.monospacedSystemFont(ofSize:15,weight:.regular)
  view.string=try String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8)
  scroll=NSScrollView(frame:NSRect(x:0,y:0,width:927,height:908));scroll.hasVerticalScroller=true
  scroll.documentView=view;scroll.contentView.postsBoundsChangedNotifications=true
  window=NSWindow(contentRect:scroll.frame,styleMask:[.titled,.resizable],backing:.buffered,defer:false)
  window.contentView=scroll;window.makeKeyAndOrderFront(nil)
  manager.textViewportLayoutController.layoutViewport();style(mode == "full")
  window.layoutIfNeeded()
  scroll.contentView.scroll(to:NSPoint(x:0,y:1900));scroll.reflectScrolledClipView(scroll.contentView)
  previousY=scroll.contentView.bounds.minY
  observer=NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:scroll.contentView,queue:.main){[weak self] _ in
   MainActor.assumeIsolated {
    guard let self else{return};let y=self.scroll.contentView.bounds.minY
    if y-self.previousY>24 && self.steps>0 {self.jumps.append("\(self.previousY)->\(y)")}
    self.previousY=y
    if self.mode != "frozen" && self.mode != "full" && self.mode != "guarded" {
     self.work?.cancel();let job=DispatchWorkItem{[weak self] in self?.style(false)};self.work=job
     DispatchQueue.main.asyncAfter(deadline:.now()+0.04,execute:job)
    }
   }
  }
  timer=Timer.scheduledTimer(withTimeInterval:0.14,repeats:true){[weak self] _ in
   MainActor.assumeIsolated {
    guard let self else{return}
    let y=self.scroll.contentView.bounds.minY
    if self.steps>5, let previous=self.lastSettledY,y-previous>24 {self.settledJumps += 1}
    self.lastSettledY=y
    self.steps += 1
    if self.steps>90 {print("RESULT mode=\(self.mode) jumps=\(self.jumps.count) samples=\(self.jumps.prefix(12)) settledJumps=\(self.settledJumps) corrections=\((self.view as! GuardedView).corrections)");NSApp.terminate(nil);return}
    let event=CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:1,wheel1:8,wheel2:0,wheel3:0)!
    self.view.scrollWheel(with:NSEvent(cgEvent:event)!)
   }
  }
 }
}
@main struct Main {
 @MainActor static func main() throws {let p=Probe();try p.start();NSApp.run();withExtendedLifetime(p){}}
}
