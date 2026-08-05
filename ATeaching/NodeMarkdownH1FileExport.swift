import Foundation

// MARK: - NodeMarkdown H1分文件 - v1 - 保留节点身份并为批量PDF建立稳定文件名
struct NodeMarkdownH1FileSection {
    let fileBaseName: String
    let document: NodeMarkdownDocument
}

enum NodeMarkdownH1FileSectionBuilder {
    /// H1属于它开启的分段；首个H1之前的实际内容独立成段，不要求文档必须以H1开头。
    static func build(
        document: NodeMarkdownDocument,
        sourceBaseName: String
    ) -> [NodeMarkdownH1FileSection] {
        guard !document.nodes.isEmpty else {
            return [makeSection(nodes: [], preferredName: sourceBaseName, usedNames: [])]
        }

        var rawSections: [(preferredName: String, nodes: [NodeMarkdownNode])] = []
        var currentNodes: [NodeMarkdownNode] = []
        var currentName: String?

        for node in document.nodes {
            if node.level == 1 {
                appendCurrentSection(
                    nodes: &currentNodes,
                    preferredName: currentName ?? sourceBaseName,
                    to: &rawSections
                )
                currentName = node.text
            }
            currentNodes.append(node)
        }
        appendCurrentSection(
            nodes: &currentNodes,
            preferredName: currentName ?? sourceBaseName,
            to: &rawSections,
            allowBlankOnly: rawSections.isEmpty
        )

        let exportableSections = rawSections.filter { raw in
            !isEmptyH1Section(raw.nodes)
        }

        var usedNames: Set<String> = []
        return exportableSections.map { raw in
            let section = makeSection(
                nodes: raw.nodes,
                preferredName: raw.preferredName,
                usedNames: usedNames
            )
            usedNames.insert(section.fileBaseName.lowercased())
            return section
        }
    }

    private static func isEmptyH1Section(_ nodes: [NodeMarkdownNode]) -> Bool {
        guard let first = nodes.first, first.level == 1 else { return false }
        return nodes.dropFirst().allSatisfy {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func appendCurrentSection(
        nodes: inout [NodeMarkdownNode],
        preferredName: String,
        to sections: inout [(preferredName: String, nodes: [NodeMarkdownNode])],
        allowBlankOnly: Bool = false
    ) {
        guard !nodes.isEmpty else { return }
        let hasContent = nodes.contains {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if hasContent || allowBlankOnly {
            sections.append((preferredName, nodes))
        }
        nodes.removeAll(keepingCapacity: true)
    }

    private static func makeSection(
        nodes: [NodeMarkdownNode],
        preferredName: String,
        usedNames: Set<String>
    ) -> NodeMarkdownH1FileSection {
        let baseName = sanitizedFileBaseName(preferredName)
        var uniqueName = baseName
        var suffix = 2
        while usedNames.contains(uniqueName.lowercased()) {
            uniqueName = "\(baseName)-\(suffix)"
            suffix += 1
        }
        return NodeMarkdownH1FileSection(
            fileBaseName: uniqueName,
            document: NodeMarkdownDocument(nodes: nodes)
        )
    }

    private static func sanitizedFileBaseName(_ source: String) -> String {
        var value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^\)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        value = value.components(
            separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")
        ).joined(separator: "-")
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: " .\n\r\t"))

        let markdownDelimiters = CharacterSet(charactersIn: "*_~=`")
        value = value.components(separatedBy: markdownDelimiters).joined()
        value = String(value.prefix(100)).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return value.isEmpty ? "未命名H1" : value
    }
}
