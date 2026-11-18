from pathlib import Path
import subprocess, tempfile, shutil
repo=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='markdown128-preview-') as temp:
 root=Path(temp)
 for name in ['marked.min.js','katex.min.js','auto-render.min.js','markdown-renderer.js']:
  shutil.copy2(repo/'ATeaching/MarkdownAssets'/name,root/name)
 (root/'test.html').write_text('''<!doctype html><meta charset="utf-8"><style>body{margin:0}#md-root{padding:18px;font:15px/1.65 system-ui;word-break:break-word}pre{white-space:pre-wrap}img{max-width:100%}</style><div id="md-root"></div><script src="marked.min.js"></script><script src="katex.min.js"></script><script src="auto-render.min.js"></script><script src="markdown-renderer.js"></script>''')
 original=(repo/'Experiments/MarkdownVirtualization/test.js').read_text()
 original=original[:original.index('return {initialMs')]
 extra=r'''
const code='```swift\n'+('let value = "中文😀";\n'.repeat(60000))+'```';
renderer.apply(1,[{index:0,hash:'giant-code',startLine:0,markdown:code}]);
window.scrollTo(0,0);await tick();await tick();
assert(document.querySelectorAll('[data-huge-chunk]').length<20,'giant code not windowed');
assert(document.querySelector('#md-root').textContent.length<100000,'giant code DOM unbounded');
window.scrollTo(0,document.documentElement.scrollHeight/2);await tick();await tick();await tick();
assert(document.querySelectorAll('[data-huge-chunk]').length<20,'middle code DOM unbounded');
const giantMiddle=Number(document.querySelector('[data-huge-chunk]').dataset.hugeChunk);
assert(giantMiddle>10,'giant code cannot reach middle');
renderer.scrollToSourceLine(30000);await tick();await tick();await tick();
assert(Math.abs(renderer.currentCenterSourceLine()-30000)<250,'giant code line mapping failed');
renderer.setVirtualized(false);await tick();
assert(document.querySelector('pre code').textContent.includes('let value'),'full code export missing');
assert(document.querySelector('#md-root').textContent.length>1000000,'full code export truncated');
renderer.setVirtualized(true);await tick();await tick();
assert(document.querySelectorAll('[data-huge-chunk]').length<20,'giant code did not restore');
const paragraph='中文😀 plain paragraph '.repeat(80000);
renderer.apply(1,[{index:0,hash:'giant-plain',startLine:0,markdown:paragraph}]);window.scrollTo(0,0);await tick();await tick();
assert(document.querySelectorAll('[data-huge-chunk]').length<20,'giant paragraph not windowed');
assert(document.querySelector('#md-root').textContent.length<100000,'giant paragraph DOM unbounded');
window.scrollTo(0,document.documentElement.scrollHeight);await tick();await tick();await tick();
let chunks=document.querySelectorAll('[data-huge-chunk]');
assert(Number(chunks[chunks.length-1].dataset.hugeChunk)>100,'giant paragraph cannot reach tail');
renderer.setVirtualized(false);await tick();
assert(document.querySelector('#md-root').textContent.includes(paragraph),'full paragraph text changed');

renderer.setVirtualized(true);
const rich='中文 **bold** and *italic* and [link](https://example.com) &amp; '.repeat(3000);
renderer.apply(1,[{index:0,hash:'giant-rich',startLine:0,markdown:rich}]);window.scrollTo(0,0);await tick();await tick();
assert(document.querySelectorAll('[data-huge-chunk]').length<20,'rich paragraph DOM unbounded');
assert(document.querySelector('strong')&&document.querySelector('em')&&document.querySelector('a'),'rich formatting lost');
assert(!document.querySelector('#md-root').textContent.includes('&amp;'),'entities escaped twice');
renderer.setVirtualized(true);
renderer.apply(2,[{index:0,hash:'math-a',startLine:0,markdown:'$$x^2$$'},{index:1,hash:'text-b',startLine:3,markdown:'after'}]);window.scrollTo(0,0);await tick();await tick();
assert(document.querySelector('.katex'),'formula after giant blocks missing');
renderer.apply(0,[]);await tick();
renderer.apply(1,[{index:0,hash:'math-a',startLine:0,markdown:'$$x^2$$'}]);await tick();await tick();
assert(document.querySelector('.katex'),'cached formula missing');
return {passed:['existing virtualization regression','giant code middle/window/full export','giant paragraph tail/window/full export','cached formula remount','giant rich paragraph formatting/entities'],giantMiddle};
'''
 (root/'test.js').write_text(original+extra.replace('\\n','\n') if False else original+extra)
 subprocess.run(['swiftc','-parse-as-library',str(repo/'Experiments/MarkdownVirtualization/PreviewTests.swift'),'-framework','AppKit','-framework','WebKit','-o','/tmp/markdown128-preview-tests'],check=True)
 subprocess.run(['/tmp/markdown128-preview-tests',str(root)],check=True,timeout=120)
 shutil.copy2(root/'results.json',repo/'Experiments/Markdown128/preview-results.json')
