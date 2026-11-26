/*
Adapted from MiaoYanCore/MarkdownEditing.swift (tw93/MiaoYan@8513ffb).
The caller supplies one local line, its line ending and its fence context.

MIT License

Copyright (c) 2022 Tw93

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

import Foundation

enum MiaoYanListContinuation {
    struct Edit: Equatable {
        /// The range of the old text to replace.
        let range: NSRange
        let replacement: String
        /// Where the caret goes afterwards, in the new text.
        let caret: Int
    }

    /// The rule on `line` alone, the caret at its end; internal for the test
    /// that holds it to the line counting it replaced.
    static func lineEdit(in text: NSString, line: NSRange, caret: Int, lineBreak: String) -> Edit? {
        let prefix: String
        if ruleRegex.firstMatch(in: text as String, range: line) == nil,  // `* * *` and `- - -` are rules, not items.
            let match = itemRegex.firstMatch(in: text as String, range: line)
        {
            let indent = text.substring(with: match.range(at: 1))
            let bullet = text.substring(with: match.range(at: 2))
            let isTask = match.range(at: 3).location != NSNotFound
            guard !text.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces).isEmpty else {
                // An item with nothing in it: Return hands the line back.
                return Edit(range: line, replacement: "", caret: line.location)
            }
            prefix = indent + next(bullet) + " " + (isTask ? "[ ] " : "")
        } else if let match = quoteRegex.firstMatch(in: text as String, range: line) {
            guard !text.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces).isEmpty else {
                // An empty quote line ends the quote, however deep it was.
                return Edit(range: line, replacement: "", caret: line.location)
            }
            // `> > ` keeps its depth.
            prefix = text.substring(with: match.range(at: 1))
        } else {
            return nil
        }
        let insertion = lineBreak + prefix
        return Edit(
            range: NSRange(location: caret, length: 0), replacement: insertion,
            caret: caret + (insertion as NSString).length)
    }

    /// `3.` becomes `4.`; a bullet stays as it is.
    private static func next(_ bullet: String) -> String {
        guard let closer = bullet.last, closer == "." || closer == ")", let number = Int(bullet.dropLast()) else {
            return bullet
        }
        return "\(number + 1)\(closer)"
    }

    // These run on one cmark line only, so `^` and `$` are its ends: with
    // `.anchorsMatchLines` they also matched at U+2028 and U+2029 inside it,
    // and `text<U+2028>- ` read as an empty item whose Return deleted the
    // whole line. `.` crosses those separators for the same reason.
    private static let itemRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*(?:>[ \t]*)*)([-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\][ \t]+|\[[ xX]\]$)?(.*)$"#,
        options: [.dotMatchesLineSeparators])
    /// A quote line: one or more `>`, the last followed by a space or tab.
    private static let quoteRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*(?:>[ \t]*)*>[ \t]+)(.*)$"#, options: [.dotMatchesLineSeparators])
    private static let ruleRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
}
