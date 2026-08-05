import Foundation

// MARK: - NodeMarkdown包清洗 - v1 - 同步前移除空行节点并保留包根

enum NodeMarkdownPackageCleaner {
    static func cleanDocument(_ document: inout NodeMarkdownDocument) -> Int {
        let originalCount = document.nodes.count
        document.nodes = cleanLooseNodes(document.nodes)
        return max(0, originalCount - document.nodes.count)
    }

    static func cleanPackage(_ packageNodes: [NodeMarkdownNode]) -> [NodeMarkdownNode] {
        guard let root = packageNodes.first else { return packageNodes }
        let children = packageNodes.dropFirst().filter { !isEmptyLine($0) }
        return [root] + children
    }

    private static func cleanLooseNodes(_ nodes: [NodeMarkdownNode]) -> [NodeMarkdownNode] {
        guard !nodes.isEmpty else { return nodes }
        return nodes.filter { !isEmptyLine($0) }
    }

    private static func isEmptyLine(_ node: NodeMarkdownNode) -> Bool {
        node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
