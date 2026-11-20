"""Real AppKit/TK2 wheel replay against an isolated document copy.
The callback guard/navigation methods are extracted from production. The style-control
adapter uses the same per-visible-line attribute pattern, not the whole application UI.
"""
from pathlib import Path
import subprocess,tempfile,shutil
repo=Path(__file__).resolve().parents[2]
src=(repo/'ATeaching/MarkdownEditorView.swift').read_text()
def method(sig):
 a=src.index(sig);return src[a:src.index('\n    }',a)+6]
clip=src[src.index('private final class MarkdownViewportClipView:'):src.index('final class MarkdownTextKit2PlainTextView:')]
view=clip+'''@MainActor final class GuardedView: NSTextView {
 var guarded=false
 var corrections=0
'''
callback=method('    override func textViewportLayoutControllerDidLayout(')
callback=callback.replace('        let clip =','        if !guarded { super.textViewportLayoutControllerDidLayout(controller); return }\n        let clip =',1)
view+=callback+'\n}\n'
template=(repo/'Experiments/MarkdownScrollRebound/Probe.swift').read_text()
a=template.index('@MainActor final class GuardedView:');b=template.index('@MainActor final class Probe:',a)
template=template[:a]+view+template[b:]
template=template.replace('var corrections=0','var corrections=0\n var originalText=""')
template=template.replace('scroll.documentView=view;', '(view as! GuardedView).originalText=view.string;scroll.documentView=view;')
template=template.replace('scroll.documentView=view;', 'if mode == "guarded" { scroll.contentView=MarkdownViewportClipView() };scroll.documentView=view;')
template=template.replace('wheel1:8','wheel1:CommandLine.arguments.count>3 && CommandLine.arguments[3]=="down" ? -8 : 8')
template=template.replace('y-previous>24','(CommandLine.arguments.count>3 && CommandLine.arguments[3]=="down" ? previous-y : y-previous)>24')
template=template.replace('self.settledJumps += 1','print("SETTLED y=\\(y) prev=\\(previous) max=\\(self.view.frame.height-self.scroll.contentView.bounds.height)");fflush(stdout);self.settledJumps += 1')
# Headings/plain text in this fixture never replace source characters.
template=template.replace('if self.steps>90 {print(','''if self.steps>90 {
     precondition(self.view.string == (self.view as! GuardedView).originalText,"scroll changed editor text")
     if self.mode == "guarded" {
      precondition(self.settledJumps == 0,"post-layout wheel rebound survived")
      let clip=self.scroll.contentView as! MarkdownViewportClipView
      clip.scroll(to:NSPoint(x:0,y:735))
      let origin=clip.bounds.origin
      clip.blocksLayoutScrolling=true
      clip.scroll(to:NSPoint(x:0,y:origin.y+700))
      clip.setBoundsOrigin(NSPoint(x:0,y:origin.y+700))
      precondition(clip.bounds.origin == origin,"layout write changed the viewport")
      clip.blocksLayoutScrolling=false
      clip.scroll(to:NSPoint(x:0,y:origin.y+100))
      precondition(clip.bounds.minY > origin.y,"normal scrolling blocked")
      self.view.scrollRangeToVisible(NSRange(location:0,length:0))
      precondition(clip.bounds.minY <= 20,"explicit navigation blocked")
     }
     print(''')
with tempfile.TemporaryDirectory(prefix='markdown-rebound-') as tmp:
 root=Path(tmp);(root/'probe.swift').write_text(template)
 # The supplied fixture is copied here and read only. Never modify a user notebook.
 fixture=Path(__import__('sys').argv[1]);shutil.copy2(fixture,root/'fixture.md')
 subprocess.run(['swiftc','-parse-as-library',str(root/'probe.swift'),'-framework','AppKit','-o',str(root/'check')],check=True)
 for mode,direction in ([('guarded','down')] if '--down-only' in __import__('sys').argv else [('frozen','up'),('guarded','up'),('guarded','down'),('guarded','up')]):
  result=subprocess.run([str(root/'check'),str(root/'fixture.md'),mode,direction],check=False,capture_output=True,text=True,timeout=30)
  print(result.stdout.strip(),flush=True)
  if result.returncode != 0:
   print(result.stderr,flush=True);raise RuntimeError("Replay failed: "+mode+"/"+direction)
