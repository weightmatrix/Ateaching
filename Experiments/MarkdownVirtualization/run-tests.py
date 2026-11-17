from pathlib import Path
import shutil,subprocess,tempfile
repo=Path.cwd()
with tempfile.TemporaryDirectory(prefix='markdown-virtual-') as temp:
 root=Path(temp)
 for name in ['marked.min.js','katex.min.js','auto-render.min.js','markdown-renderer.js']:
  shutil.copy2(repo/'ATeaching/MarkdownAssets'/name,root/name)
 shutil.copy2(repo/'Experiments/MarkdownVirtualization/test.js',root/'test.js')
 (root/'test.html').write_text('''<!doctype html><meta charset="utf-8"><style>body{margin:0}#md-root{padding:18px;font:15px/1.65 system-ui;word-break:break-word}pre{white-space:pre-wrap}img{max-width:100%}</style><div id="md-root"></div><script src="marked.min.js"></script><script src="katex.min.js"></script><script src="auto-render.min.js"></script><script src="markdown-renderer.js"></script>''')
 subprocess.run(['swiftc','-parse-as-library',str(repo/'Experiments/MarkdownVirtualization/PreviewTests.swift'),'-framework','AppKit','-framework','WebKit','-o','/tmp/markdown-virtual-tests'],check=True)
 subprocess.run(['/tmp/markdown-virtual-tests',str(root)],check=True,timeout=120)
 shutil.copy2(root/'results.json',repo/'Experiments/MarkdownVirtualization/results.json')

 # Same synthetic input and WebKit runtime for the saved pre-change renderer.
 baseline=subprocess.check_output(['git','show','codex/pre-127-preview-virtualization-20261117:ATeaching/MarkdownAssets/markdown-renderer.js'])
 (root/'markdown-renderer.js').write_bytes(baseline)
 (root/'test.js').write_text("""const tick=()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
const patches=Array.from({length:10000},(_,index)=>({index,hash:String(index),startLine:index*3,markdown:'# Heading '+index+'\\n\\nText **bold** '+index}));
const t=performance.now();window.markdownRenderer.apply(10000,patches);await tick();await tick();
return {blocks:10000,mounted:document.querySelectorAll('section').length,initialMs:performance.now()-t};""")
 subprocess.run(['/tmp/markdown-virtual-tests',str(root)],check=True,timeout=120)
 shutil.copy2(root/'results.json',repo/'Experiments/MarkdownVirtualization/baseline-results.json')
