import Foundation

// MARK: - NodeMarkdown内存结构索引 - 扁平文件之上的树与H3包查询层
/// CSV仍只保存有序Node。索引在打开文档或结构变化后由内存重建，不参与编码、落盘和同步。
/// 普通字符输入不会改变UUID、level或行序，因此可以持续复用同一份索引。
struct NodeMarkdownDocumentIndex {
    private(set) var nodeCount = 0
    private var firstRowByID: [UUID: Int] = [:]
    private var allRowsByID: [UUID: [Int]] = [:]
    private var parentRows: [Int?] = []
    private var childRows: [[Int]] = []
    private var subtreeEnds: [Int] = []
    private var owningH3Rows: [Int?] = []
    private var h3Ranges: [Range<Int>] = []
    private var h3RangeByRootID: [UUID: Range<Int>] = [:]

    init(nodes: [NodeMarkdownNode] = []) {
        rebuild(from: nodes)
    }

    mutating func rebuild(from nodes: [NodeMarkdownNode]) {
        nodeCount = nodes.count
        firstRowByID.removeAll(keepingCapacity: true)
        allRowsByID.removeAll(keepingCapacity: true)
        parentRows = Array(repeating: nil, count: nodes.count)
        childRows = Array(repeating: [], count: nodes.count)
        subtreeEnds = Array(repeating: nodes.count, count: nodes.count)
        owningH3Rows = Array(repeating: nil, count: nodes.count)
        h3Ranges.removeAll(keepingCapacity: true)
        h3RangeByRootID.removeAll(keepingCapacity: true)

        var openRowsByLevel = Array<Int?>(repeating: nil, count: 13)
        var activeH3Row: Int?

        for (row, node) in nodes.enumerated() {
            let level = max(1, min(12, node.level))
            if firstRowByID[node.id] == nil {
                firstRowByID[node.id] = row
            }
            allRowsByID[node.id, default: []].append(row)

            for openLevel in level...12 {
                if let openRow = openRowsByLevel[openLevel] {
                    subtreeEnds[openRow] = row
                    openRowsByLevel[openLevel] = nil
                }
            }

            if level > 1 {
                for parentLevel in stride(from: level - 1, through: 1, by: -1) {
                    if let parentRow = openRowsByLevel[parentLevel] {
                        parentRows[row] = parentRow
                        childRows[parentRow].append(row)
                        break
                    }
                }
            }
            openRowsByLevel[level] = row

            switch level {
            case 1, 2:
                activeH3Row = nil
            case 3:
                activeH3Row = row
            default:
                break
            }
            owningH3Rows[row] = activeH3Row
        }

        for level in 1...12 {
            if let openRow = openRowsByLevel[level] {
                subtreeEnds[openRow] = nodes.count
            }
        }

        for (row, node) in nodes.enumerated() where node.level == 3 {
            let range = row..<subtreeEnds[row]
            h3Ranges.append(range)
            if h3RangeByRootID[node.id] == nil {
                h3RangeByRootID[node.id] = range
            }
        }
    }

    func row(for id: UUID) -> Int? {
        firstRowByID[id]
    }

    func rows(for id: UUID) -> [Int] {
        allRowsByID[id] ?? []
    }

    func parentRow(of row: Int) -> Int? {
        guard parentRows.indices.contains(row) else { return nil }
        return parentRows[row]
    }

    func directChildRows(of row: Int) -> [Int] {
        guard childRows.indices.contains(row) else { return [] }
        return childRows[row]
    }

    func subtreeRange(startingAt row: Int) -> Range<Int>? {
        guard subtreeEnds.indices.contains(row) else { return nil }
        return row..<subtreeEnds[row]
    }

    func owningH3Row(for row: Int) -> Int? {
        guard owningH3Rows.indices.contains(row) else { return nil }
        return owningH3Rows[row]
    }

    func packageRanges() -> [Range<Int>] {
        h3Ranges
    }

    func packageRange(rootID: UUID) -> Range<Int>? {
        h3RangeByRootID[rootID]
    }
}
