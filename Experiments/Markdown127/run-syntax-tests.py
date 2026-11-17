from pathlib import Path
import shutil, subprocess, tempfile
repo=Path.cwd()
with tempfile.TemporaryDirectory(prefix='markdown127-') as tmp:
 root=Path(tmp);(root/'Sources/Probe').mkdir(parents=True)
 (root/'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name:"Probe", dependencies:[.package(url:"https://github.com/swiftlang/swift-markdown.git",exact:"0.9.0")], targets:[.executableTarget(name:"Probe",dependencies:[.product(name:"Markdown",package:"swift-markdown")])])
''')
 shutil.copy2(repo/'ATeaching/NormalMarkdownSyntax.swift',root/'Sources/Probe/NormalMarkdownSyntax.swift')
 (root/'Sources/Probe/main.swift').write_text('''import Foundation
let fenced="```swift\\n# not heading\\n\\nlet b = 2\\n```\\n\\n# real"
let a=NormalMarkdownSyntax.parse(fenced)
precondition(a.headings.map(\\.title)==["real"])
precondition(a.blocks.first!.preview.contains("let b = 2"))
precondition(a.blocks.count==2)
let ref=NormalMarkdownSyntax.parse("[example][id]\\n\\n[id]: https://example.com")
precondition(ref.blocks.first!.preview.contains("https://example.com"))
let unicode=NormalMarkdownSyntax.parse("😀 `abc`")
precondition(unicode.spans.first!.range.location==3, "inline code source range must start at UTF16 backtick, not character index")
let setext=NormalMarkdownSyntax.parse("Title\\n=====")
precondition(setext.headings.first?.title=="Title")
let longUnicode=NormalMarkdownSyntax.parse(String(repeating:"😀中文 ",count:10000)+"`end`")
precondition(longUnicode.spans.last!.range.location==String(repeating:"😀中文 ",count:10000).utf16.count)
let list=NormalMarkdownSyntax.parse("- first\\n\\n  second\\n\\n- third")
precondition(list.blocks.count==1)
let escaped=NormalMarkdownSyntax.parse("\\\\*literal\\\\* and ``code ` tick``")
precondition(!escaped.spans.contains { $0.kind == .emphasis })
let extensionText="$$\\nx^2 + y^2\\n$$"
precondition(NormalMarkdownSyntax.parse(extensionText).blocks.first!.preview==extensionText)
let multiMath="$$\\n# not a heading\\n\\nx^2\\n$$"
let mathSyntax=NormalMarkdownSyntax.parse(multiMath)
precondition(mathSyntax.headings.isEmpty && mathSyntax.blocks.count==1)
precondition(mathSyntax.blocks.first!.preview==multiMath)
let quoted=NormalMarkdownSyntax.parse("```\\n# no\\n```\\n\\n# yes")
precondition(quoted.clipped(to:NSRange(location:4,length:4)).isLiteral(at:0))
let bold=NormalMarkdownSyntax.parse("前缀 😀 **bold**")
let clipped=bold.clipped(to:NSRange(location:3,length:12))
precondition(!clipped.spans.isEmpty)
let imageTag="<img src=\\\"figure.png\\\" width=\\\"400\\\">"
let imageSyntax=NormalMarkdownSyntax.parse(imageTag)
precondition(imageSyntax.literalRanges.isEmpty && imageSyntax.blocks.first!.preview==imageTag)
let math=NormalMarkdownSyntax.parse("$$\\nx^2 + y^2\\n$$")
print("math preview:",math.blocks.map(\\.preview))
let fixtures = [fenced, "[example][id]\\n\\n[id]: https://example.com", "- first\\n\\n  second\\n\\n- third", "| A | B |\\n|---|---|\\n| 1 | 2 |"]
let rendered = fixtures.map { NormalMarkdownSyntax.parse($0).blocks.map(\.preview) }
let fixtureData = try JSONSerialization.data(withJSONObject:rendered)
try fixtureData.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
let concurrentSource=String(repeating:"# Concurrent\\n\\nbody\\n\\n",count:1000)
DispatchQueue.concurrentPerform(iterations:8) { _ in
 precondition(NormalMarkdownSyntax.parse(concurrentSource).headings.count==1000)
}
var results: [[String: Any]] = []
for bytes in [400000,2000000,10000000] {
 let line = "# Header\\n\\n测试 **bold** 😀 with [link](https://example.com)\\n\\n"
 let sample=String(repeating:line,count:bytes/line.utf8.count+1)
 let start=ProcessInfo.processInfo.systemUptime
 let snapshot=NormalMarkdownSyntax.parse(sample)
 results.append(["bytes":sample.utf8.count,"parseMs":(ProcessInfo.processInfo.systemUptime-start)*1000,"blocks":snapshot.blocks.count])
}
try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
print("PASS: fence/blank lines, reference links, UTF16 emoji offsets, long Unicode lines, Setext headings, escapes, list continuations, formula source preservation")
''')
 subprocess.run(['swift','run','-c','release','--package-path',str(root),'--scratch-path','/tmp/markdown127-test-build','-j','2','Probe',str(root/'fixtures.json'),str(repo/'Experiments/Markdown127/results.json')],check=True)
 subprocess.run(['node','-e',r'''const fs=require('fs'),vm=require('vm'),assert=require('assert');
const ctx={};vm.createContext(ctx);vm.runInContext(fs.readFileSync(process.argv[1],'utf8'),ctx);
const fixtures=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const html=fixtures.map(blocks=>blocks.map(x=>ctx.marked.parse(x,{gfm:true,breaks:true})).join(''));
assert(html[0].includes('let b = 2\n</code>'));assert(!html[0].includes('<h1>not heading'));
assert(html[1].includes('href="https://example.com"'));
assert(html[2].includes('<ul>') && html[2].includes('second'));
assert(html[3].includes('<table>'));
console.log('PASS: bundled Marked renders shared semantic blocks: fences, references, lists, GFM tables');
''', str(repo/'ATeaching/MarkdownAssets/marked.min.js'),str(root/'fixtures.json')],check=True)
