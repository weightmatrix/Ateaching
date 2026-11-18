"""Real AppKit/TK2 wheel replay against an isolated document copy.
The callback guard/navigation methods are extracted from production. The style-control
adapter uses the same per-visible-line attribute pattern, not the whole application UI.
"""
from pathlib import Path
import subprocess,tempfile,json,shutil
repo=Path(__file__).resolve().parents[2]
src=(repo/'ATeaching/MarkdownEditorView.swift').read_text()
def method(sig):
 a=src.index(sig);return src[a:src.index('\n    }',a)+6]
view='''@MainActor final class GuardedView: NSTextView {
 var guarded=false
 var corrections=0
 var viewportWheelIntent:(time:TimeInterval,delta:CGFloat,characters:Int)?
 var hasActiveMarkedText:Bool { hasMarkedText() }
 var cachedSourceProjection:String?
 func recordScrollJump(stage:String,previousY:CGFloat) { corrections += 1 }
 override func scrollWheel(with event:NSEvent) {
  if guarded { viewportWheelIntent=(ProcessInfo.processInfo.systemUptime,event.scrollingDeltaY,textStorage?.length ?? 0) }
  super.scrollWheel(with:event)
 }
'''
callback=method('    override func textViewportLayoutControllerDidLayout(')
callback=callback.replace('        let clip =','        if !guarded { super.textViewportLayoutControllerDidLayout(controller); return }\n        let clip =',1)
view+=callback+'\n'+method('    override func mouseDown(')+'\n'+method('    override func scrollRangeToVisible(')+'\n'+method('    override func didChangeText()')+'\n}\n'
template=(repo/'Experiments/MarkdownScrollRebound/Probe.swift').read_text()
a=template.index('@MainActor final class GuardedView:');b=template.index('@MainActor final class Probe:',a)
template=template[:a]+view+template[b:]
template=template.replace('if y-self.previousY>24','if y-self.previousY>24')
template=template.replace('wheel1:8','wheel1:CommandLine.arguments.count>3 && CommandLine.arguments[3]=="down" ? -8 : 8')
template=template.replace('y-previous>24','(CommandLine.arguments.count>3 && CommandLine.arguments[3]=="down" ? previous-y : y-previous)>24')
template=template.replace('self.settledJumps += 1','print("SETTLED y=\\(y) prev=\\(previous) max=\\(self.view.frame.height-self.scroll.contentView.bounds.height)");fflush(stdout);self.settledJumps += 1')
# Headings/plain text in this fixture never replace source characters.
template=template.replace('if self.steps>90 {print(','''if self.steps>90 {
     precondition(self.view.string == (try! String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8)))
     if self.mode == "guarded" {
      let guarded=self.view as! GuardedView
      guarded.viewportWheelIntent=(ProcessInfo.processInfo.systemUptime,8,guarded.textStorage!.length)
      guarded.scrollRangeToVisible(NSRange(location:0,length:0))
      precondition(guarded.viewportWheelIntent == nil,"explicit navigation remained guarded")
      guarded.viewportWheelIntent=(ProcessInfo.processInfo.systemUptime,8,guarded.textStorage!.length)
      guarded.didChangeText()
      precondition(guarded.viewportWheelIntent == nil,"editing remained guarded")
      precondition(self.settledJumps == 0,"post-layout wheel rebound survived")
     }
     print(''')
with tempfile.TemporaryDirectory(prefix='markdown-rebound-') as tmp:
 root=Path(tmp);(root/'probe.swift').write_text(template)
 # The supplied fixture is copied here and read only. Never modify a user notebook.
 fixture=Path(__import__('sys').argv[1]);shutil.copy2(fixture,root/'fixture.md')
 subprocess.run(['swiftc','-parse-as-library',str(root/'probe.swift'),'-framework','AppKit','-o',str(root/'check')],check=True)
 results=[]
 for mode,direction in ([('guarded','down')] if '--down-only' in __import__('sys').argv else [('frozen','up'),('guarded','up'),('guarded','down'),('guarded','up')]):
  result=subprocess.run([str(root/'check'),str(root/'fixture.md'),mode,direction],check=False,capture_output=True,text=True,timeout=30)
  print(result.stdout.strip(),flush=True)
  if result.returncode != 0:
   print(result.stderr,flush=True);raise RuntimeError("Replay failed: "+mode+"/"+direction)
  results.append({'mode':mode,'direction':direction,'output':result.stdout.strip()})
 (repo/'Experiments/MarkdownScrollRebound/results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
