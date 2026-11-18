import Foundation
func equivalent(_ a: NormalMarkdownSyntax.Snapshot, _ b: NormalMarkdownSyntax.Snapshot) -> Bool {
 a.lineStarts == b.lineStarts && a.headings.map { "\($0.level):\($0.title):\($0.offset)" } == b.headings.map { "\($0.level):\($0.title):\($0.offset)" }
 && a.spans.map { "\($0.range):\($0.kind)" } == b.spans.map { "\($0.range):\($0.kind)" }
 && a.literalRanges == b.literalRanges
 && a.blocks.map { "\($0.startLine):\($0.source):\($0.preview)" } == b.blocks.map { "\($0.startLine):\($0.source):\($0.preview)" }
}
let padding=String(repeating:"# Section\n\n中文 😀 paragraph **bold** and `code`.\n\n",count:1000)
var results:[[String:Any]]=[]
for (label, old, new) in [
 ("paragraph",padding,padding.replacingOccurrences(of:"paragraph",with:"paragraph edited",range:padding.range(of:"paragraph"))),
 ("unicode",padding,padding.replacingOccurrences(of:"中文",with:"中😀文",range:padding.range(of:"中文"))),
 ("split",padding,padding.replacingOccurrences(of:"paragraph",with:"paragraph\n\nnew block",range:padding.range(of:"paragraph"))),
 ("reference",padding+"\n[id]: https://example.com\n",padding+"\n[id]: https://changed.example.com\n"),
 ("fence",padding+"\n```swift\nlet x = 1\nlet y = 2\n```\n",padding+"\n```swift\nlet x = 7\nlet y = 2\n```\n"),
 ("math",padding+"\n$$\nx^2\n$$",padding+"\n$$\nx^3\n$$"),
 ("heading",padding,padding.replacingOccurrences(of:"Sect",with:"Changed",range:padding.range(of:"Sect"))),
 ("list",padding+"\n- one\n- two",padding+"\n- changed\n- two"),
 ("html",padding+"\n<div>\nhello\n</div>",padding+"\n<div>\nworld\n</div>")
] {
 FileHandle.standardError.write(Data(("CASE "+label+"\n").utf8))
 _=NormalMarkdownSyntax.parse(old)
 let start=ProcessInfo.processInfo.systemUptime
 let fast=NormalMarkdownSyntax.parse(new)
 let elapsed=(ProcessInfo.processInfo.systemUptime-start)*1000
 let full=NormalMarkdownSyntax.parse(new,useIncremental:false)
 if !equivalent(fast,full) { FileHandle.standardError.write(Data("MISMATCH\n".utf8)) }
 precondition(equivalent(fast,full),"incremental mismatch: \(label)")
 if label == "paragraph" || label == "unicode" || label == "heading" || label == "fence" { FileHandle.standardError.write(Data(("REUSE "+String(fast.reusedUnits)+"\n").utf8)); precondition(fast.reusedUnits>0,"no reuse: \(label)") }
 results.append(["case":label,"ms":elapsed,"parsedUTF16":fast.parsedUTF16,"reusedUnits":fast.reusedUnits])
}
// Repeated edits must keep offsets, spans, start lines, and reference resolution identical.
var current=padding
for i in 0..<30 {
 _=NormalMarkdownSyntax.parse(current)
 let target=current.range(of:"paragraph")!
 let next=current.replacingCharacters(in:target,with:"paragraph\(i)😀")
 let fast=NormalMarkdownSyntax.parse(next), full=NormalMarkdownSyntax.parse(next,useIncremental:false)
 if !equivalent(fast,full) { FileHandle.standardError.write(Data("MISMATCH\n".utf8)) }
 precondition(equivalent(fast,full),"repeated edit \(i)")
 current=next
}


for kind in ["plain", "code"] {
 let body=String(repeating:"中文😀 body ",count:60000)
 let old=kind == "code" ? "```swift\n"+body+"\n```" : body
 _=NormalMarkdownSyntax.parse(old)
 let next=old.replacingCharacters(in:old.range(of:"body")!,with:"body updated")
 let fast=NormalMarkdownSyntax.parse(next),full=NormalMarkdownSyntax.parse(next,useIncremental:false)
 precondition(equivalent(fast,full),"single huge block mismatch: \(kind)")
 precondition(fast.parsedUTF16 == 0,"single huge block reparsed: \(kind)")
}
// CRLF, scalar boundaries and paragraph-to-list/reference/fence changes use a correctness fallback.
for replacement in ["\r\n", "😀", "\n- item\n", "\n[id]: https://example.com\n", "\n```\n", "\\", "**"] {
 let old=padding.replacingOccurrences(of:"\n",with:"\r\n")
 _=NormalMarkdownSyntax.parse(old)
 let range=old.range(of:"paragraph")!
 let next=old.replacingCharacters(in:range,with:replacement)
 precondition(equivalent(NormalMarkdownSyntax.parse(next),NormalMarkdownSyntax.parse(next,useIncremental:false)),"CRLF edit mismatch")
}
for bytes in [400000,2000000,10000000] {
 let line="# Heading\n\n中文 😀 paragraph **bold** with `code`.\n\n"
 let old=String(repeating:line,count:bytes/line.utf8.count+1)
 _=NormalMarkdownSyntax.parse(old)
 let next=old.replacingCharacters(in:old.range(of:"paragraph")!,with:"paragraph edited")
 let start=ProcessInfo.processInfo.systemUptime
 let incremental=NormalMarkdownSyntax.parse(next)
 let fastMs=(ProcessInfo.processInfo.systemUptime-start)*1000
 let fullStart=ProcessInfo.processInfo.systemUptime
 let full=NormalMarkdownSyntax.parse(next,useIncremental:false)
 let fullMs=(ProcessInfo.processInfo.systemUptime-fullStart)*1000
 precondition(equivalent(incremental,full) && incremental.reusedUnits>0)
 results.append(["case":"large-edit","bytes":next.utf8.count,"ms":fastMs,"fullMs":fullMs,"parsedUTF16":incremental.parsedUTF16,"reusedUnits":incremental.reusedUnits])
}
try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
print("PASS incremental/full equivalence: Unicode, blocks, reference definitions, fence, math, heading, list, HTML and repeated edits")
