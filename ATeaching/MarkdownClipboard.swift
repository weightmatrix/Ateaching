#if os(macOS)
import AppKit
import Foundation

enum MarkdownClipboard {
    static func source(from pasteboard: NSPasteboard) -> String? {
        for identifier in ["net.daringfireball.markdown", "public.markdown", "text/markdown"] {
            let type = NSPasteboard.PasteboardType(identifier)
            if let source = pasteboard.string(forType: type), !source.isEmpty { return source }
        }
        let plain = pasteboard.string(forType: .string)
        if let plain, plain.range(of: #"(?m)^ {0,3}(#{1,6}[ \t]|\x60{3,})"#, options: .regularExpression) != nil { return plain }
        if let html = pasteboard.string(forType: .html), let converted = markdown(fromHTML: html) {
            return converted
        }
        return plain
    }

    static func markdown(fromHTML html: String) -> String? {
        guard html.utf8.count <= 2_000_000,
              let document = try? XMLDocument(xmlString: html, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let body = (try? document.nodes(forXPath: "//body"))?.first else { return nil }
        var hasStructure = false
        func fence(_ source: String, minimum: Int) -> String {
            let longest = source.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
            return String(repeating: "`", count: max(minimum, longest + 1))
        }
        func render(_ node: XMLNode, depth: Int = 0) -> String {
            guard let element = node as? XMLElement else { return node.kind == .text ? node.stringValue ?? "" : "" }
            let tag = element.name?.lowercased() ?? ""
            let children = element.children ?? []
            func content() -> String { children.map { render($0, depth: depth) }.joined() }
            switch tag {
            case "script", "style", "button", "svg": return ""
            case "h1", "h2", "h3", "h4", "h5", "h6":
                hasStructure = true
                return "\n\n" + String(repeating: "#", count: Int(tag.dropFirst()) ?? 1) + " " + content().trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
            case "p": return "\n\n" + content().trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
            case "br": return "  \n"
            case "strong", "b", "em", "i", "del", "s":
                hasStructure = true
                let marker = ["strong", "b"].contains(tag) ? "**" : ["del", "s"].contains(tag) ? "~~" : "*"
                return marker + content().trimmingCharacters(in: .whitespacesAndNewlines) + marker
            case "code":
                hasStructure = true
                let text = element.stringValue ?? ""
                let marker = fence(text, minimum: 1)
                let padding = text.hasPrefix("`") || text.hasSuffix("`") ? " " : ""
                return marker + padding + text + padding + marker
            case "pre":
                hasStructure = true
                let code = children.compactMap { $0 as? XMLElement }.first { $0.name == "code" }
                let text = code?.stringValue ?? element.stringValue ?? ""
                let marker = fence(text, minimum: 3)
                let language = code?.attribute(forName: "class")?.stringValue?.split(separator: " ")
                    .first { $0.hasPrefix("language-") }.map { String($0.dropFirst(9)) } ?? ""
                return "\n\n" + marker + language + "\n" + text + (text.hasSuffix("\n") ? "" : "\n") + marker + "\n\n"
            case "blockquote":
                hasStructure = true
                return "\n\n" + content().trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n") + "\n\n"
            case "a", "img":
                let image = tag == "img"
                let label = image ? element.attribute(forName: "alt")?.stringValue ?? "" : content()
                guard let url = element.attribute(forName: image ? "src" : "href")?.stringValue,
                      !url.contains(where: { $0.isNewline || $0 == "<" || $0 == ">" }),
                      !url.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("javascript:") else { return label }
                hasStructure = true
                return (image ? "!" : "") + "[" + label.replacingOccurrences(of: "]", with: "\\]") + "](<" + url + ">)"
            case "ul", "ol":
                hasStructure = true
                let start = Int(element.attribute(forName: "start")?.stringValue ?? "") ?? 1
                let rows = children.compactMap { $0 as? XMLElement }.filter { $0.name == "li" }
                return "\n" + rows.enumerated().map { index, item in
                    let marker = tag == "ul" ? "- " : "\(start + index). "
                    let indent = String(repeating: " ", count: depth)
                    let parts = (item.children ?? []).map { render($0, depth: depth + marker.count) }.joined()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return indent + marker + parts
                }.joined(separator: "\n") + "\n"
            case "table":
                hasStructure = true
                let rows = (try? element.nodes(forXPath: "./tr | ./thead/tr | ./tbody/tr | ./tfoot/tr")) ?? []
                let cells = rows.map { row in
                    (row.children ?? []).filter { $0.name == "th" || $0.name == "td" }.map {
                        render($0, depth: depth).trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "<br>")
                    }
                }
                guard let header = cells.first, !header.isEmpty else { return content() }
                let width = cells.map(\.count).max() ?? header.count
                func row(_ values: [String]) -> String { "| " + (values + Array(repeating: "", count: width - values.count)).joined(separator: " | ") + " |" }
                return "\n\n" + ([row(header), row(Array(repeating: "---", count: width))] + cells.dropFirst().map(row)).joined(separator: "\n") + "\n\n"
            default: return content()
            }
        }
        let result = render(body).trimmingCharacters(in: .whitespacesAndNewlines)
        return hasStructure && !result.isEmpty ? result : nil
    }
}
#endif
