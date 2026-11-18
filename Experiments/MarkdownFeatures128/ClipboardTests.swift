import AppKit

@main struct ClipboardTests {
    @MainActor static func main() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Title\nBold and code", forType: .string)
        board.setString("""
        <html><body><h2>Title</h2><p><strong>Bold</strong> and <code>code</code></p>
        <ol start="3"><li>Third</li></ol><table><tr><th>A</th><th>B</th></tr><tr><td>x|y</td><td>z</td></tr></table>
        <pre><code class="language-swift">let value = 1</code></pre></body></html>
        """, forType: .html)
        let source = MarkdownClipboard.source(from: board) ?? ""
        for expected in ["## Title", "**Bold** and `code`", "3. Third", "| --- | --- |", "x\\|y", "```swift\nlet value = 1\n```"] {
            precondition(source.contains(expected), "Missing \(expected)")
        }
        board.setString("# Original\n\n**raw**", forType: .init("public.markdown"))
        precondition(MarkdownClipboard.source(from: board) == "# Original\n\n**raw**")
        board.clearContents()
        board.setString("plain text", forType: .string)
        precondition(MarkdownClipboard.source(from: board) == "plain text")
        print("PASS: HTML structure, explicit Markdown and plain text")
    }
}
