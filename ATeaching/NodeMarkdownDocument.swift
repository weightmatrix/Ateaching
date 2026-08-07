import Foundation

// MARK: - NodeMarkdown节点 - v2 - 定义12层节点文本来源与缓存时间的统一数据模型
struct NodeMarkdownNode: Hashable, Identifiable, Codable {
    var id: UUID
    var level: Int
    var text: String
    var sourceID: String
    var sourceFile: String
    var cache: String
    var mtimeCache: Date

    init(
        id: UUID = UUID(),
        level: Int,
        text: String,
        sourceID: String = "",
        sourceFile: String = "",
        cache: String = "",
        mtimeCache: Date = Date()
    ) {
        let safeLevel = max(0, min(12, level))
        self.id = id
        self.level = safeLevel
        self.text = text
        self.sourceID = sourceID
        self.sourceFile = sourceFile
        self.cache = cache
        self.mtimeCache = mtimeCache
    }

    var isHeading: Bool {
        level > 0
    }

    var persistenceSourceID: String {
        level == 3 ? sourceID : ""
    }

    var persistenceSourceFile: String {
        level == 3 ? sourceFile : ""
    }

    var persistenceCache: String {
        guard level == 3 else { return "" }
        return cache.isEmpty ? NodeMarkdownCacheCodec.encode(mtime: mtimeCache) : cache
    }
}

// MARK: - NodeMarkdown元信息 - v1 - 定义NodeMarkdown文件末尾META字段
struct NodeMarkdownFileMeta: Hashable, Codable {
    var id: String
    var title: String
    var template: String
    var createdAt: String
    var type: String

    init(
        id: String = UUID().uuidString,
        title: String = "",
        template: String = "nil",
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        type: String = "nodemarkdown"
    ) {
        self.id = id
        self.title = title
        self.template = template
        self.createdAt = createdAt
        self.type = type
    }
}

// MARK: - NodeMarkdown文档模型 - v2 - 管理节点数组并提供增量编辑层级与H3包修时联动
struct NodeMarkdownDocument: Hashable, Codable {
    var nodes: [NodeMarkdownNode]

    init(nodes: [NodeMarkdownNode] = []) {
        self.nodes = nodes
    }

    mutating func ensureTrailingBlankLine(defaultLevel: Int = 1) -> Int {
        if let last = nodes.last, last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return max(0, nodes.count - 1)
        }
        let now = Date()
        let node = NodeMarkdownNode(
            level: max(1, min(12, defaultLevel)),
            text: "",
            sourceID: "",
            sourceFile: "",
            cache: NodeMarkdownCacheCodec.encode(mtime: now),
            mtimeCache: now
        )
        nodes.append(node)
        return max(0, nodes.count - 1)
    }

    mutating func insertSibling(after index: Int) -> Int {
        let safeIndex = max(0, min(index, max(0, nodes.count - 1)))
        let level = nodes.indices.contains(safeIndex) ? nodes[safeIndex].level : 1
        let now = Date()
        let newNode = NodeMarkdownNode(
            level: max(1, level),
            text: "",
            sourceID: "",
            sourceFile: "",
            cache: NodeMarkdownCacheCodec.encode(mtime: now),
            mtimeCache: now
        )
        let target = min(nodes.count, safeIndex + 1)
        nodes.insert(newNode, at: target)
        touchMutation(at: target, changedLevelOrText: true)
        return target
    }

    mutating func updateText(
        at index: Int,
        to newText: String,
        structuralIndex: NodeMarkdownDocumentIndex? = nil
    ) {
        guard nodes.indices.contains(index) else { return }
        guard nodes[index].text != newText else { return }
        nodes[index].text = newText
        touchMutation(at: index, changedLevelOrText: true, structuralIndex: structuralIndex)
    }

    mutating func indent(at index: Int) {
        guard nodes.indices.contains(index) else { return }
        let previousLevel = nodes[index].level
        nodes[index].level = min(12, max(1, previousLevel + 1))
        if nodes[index].level != previousLevel {
            touchMutation(at: index, changedLevelOrText: true)
        }
    }

    mutating func outdent(at index: Int) {
        guard nodes.indices.contains(index) else { return }
        let previousLevel = nodes[index].level
        nodes[index].level = max(1, previousLevel - 1)
        if nodes[index].level != previousLevel {
            touchMutation(at: index, changedLevelOrText: true)
        }
    }

    mutating func touchMutation(
        at index: Int,
        changedLevelOrText: Bool,
        structuralIndex: NodeMarkdownDocumentIndex? = nil
    ) {
        guard nodes.indices.contains(index) else { return }
        let now = Date()
        nodes[index].mtimeCache = now
        if nodes[index].level == 3 {
            nodes[index].cache = NodeMarkdownCacheCodec.encode(mtime: now)
        } else {
            nodes[index].cache = ""
        }
        guard changedLevelOrText else { return }
        guard let ownerIndex = owningH3Index(for: index, structuralIndex: structuralIndex) else { return }
        nodes[ownerIndex].mtimeCache = now
        nodes[ownerIndex].cache = NodeMarkdownCacheCodec.encode(mtime: now)
    }

    /// 将H3包内任意子节点比根节点更晚的mtimeCache传播到根节点。
    /// 仅依赖当前文档自身的时间戳，不比较外部版本。
    mutating func propagateChildMtimeToH3Roots() {
        var h3RootIndex: Int?
        var maxChildMtime: Date?
        for index in nodes.indices {
            let node = nodes[index]
            if node.level == 3 {
                if let root = h3RootIndex, let mtime = maxChildMtime, mtime > nodes[root].mtimeCache {
                    nodes[root].mtimeCache = mtime
                    nodes[root].cache = NodeMarkdownCacheCodec.encode(mtime: mtime)
                }
                h3RootIndex = index
                maxChildMtime = nil
            } else if node.level > 3, let root = h3RootIndex {
                if maxChildMtime == nil || node.mtimeCache > maxChildMtime! {
                    maxChildMtime = node.mtimeCache
                }
            } else if node.level < 3 {
                h3RootIndex = nil
                maxChildMtime = nil
            }
        }
        if let root = h3RootIndex, let mtime = maxChildMtime, mtime > nodes[root].mtimeCache {
            nodes[root].mtimeCache = mtime
            nodes[root].cache = NodeMarkdownCacheCodec.encode(mtime: mtime)
        }
    }

    mutating func touchChangedH3Packages(comparedTo previousDocument: NodeMarkdownDocument, at timestamp: Date = Date()) -> Set<String> {
        let currentIndex = NodeMarkdownDocumentIndex(nodes: nodes)
        let previousStructureIndex = NodeMarkdownDocumentIndex(nodes: previousDocument.nodes)
        var previousByID: [UUID: NodeMarkdownNode] = [:]
        var previousIndexByID: [UUID: Int] = [:]
        for (index, node) in previousDocument.nodes.enumerated() {
            previousByID[node.id] = node
            previousIndexByID[node.id] = index
        }
        var touchedIDs: Set<String> = []

        func currentH3Index(withID id: UUID) -> Int? {
            guard let row = currentIndex.row(for: id), nodes.indices.contains(row), nodes[row].level == 3 else {
                return nil
            }
            return row
        }

        func touchH3(at index: Int) {
            guard nodes.indices.contains(index), nodes[index].level == 3 else { return }
            nodes[index].mtimeCache = timestamp
            nodes[index].cache = NodeMarkdownCacheCodec.encode(mtime: timestamp)
            touchedIDs.insert(nodes[index].id.uuidString)
        }

        for index in nodes.indices {
            let node = nodes[index]
            guard let previous = previousByID[node.id] else {
                // A newly inserted child belongs to the H3 that contains its new
                // position. A newly inserted H3 is a new package, not a dirty one.
                if node.level != 3, let ownerIndex = currentIndex.owningH3Row(for: index) {
                    touchH3(at: ownerIndex)
                }
                continue
            }
            guard previous.level != node.level || previous.text != node.text else { continue }

            var candidateIndexes: [Int] = []
            if node.level == 3 {
                candidateIndexes.append(index)
            }
            if let ownerIndex = currentIndex.owningH3Row(for: index) {
                candidateIndexes.append(ownerIndex)
            }
            if let previousIndex = previousIndexByID[node.id],
               let previousOwnerID = previousStructureIndex.owningH3Row(for: previousIndex).map({ previousDocument.nodes[$0].id }),
               let currentOwnerIndex = currentIndex.row(for: previousOwnerID) {
                candidateIndexes.append(currentOwnerIndex)
            }

            for h3Index in candidateIndexes where nodes.indices.contains(h3Index) && nodes[h3Index].level == 3 {
                touchH3(at: h3Index)
            }
        }

        // Deleted nodes are absent from the current scan. Recover their pre-edit
        // owners by UUID so one group deletion can report every affected H3.
        let currentNodeIDs = Set(nodes.map(\.id))
        for (previousIndex, previousNode) in previousDocument.nodes.enumerated()
        where !currentNodeIDs.contains(previousNode.id) {
            guard let previousOwnerIndex = previousStructureIndex.owningH3Row(for: previousIndex) else { continue }
            let previousOwnerID = previousDocument.nodes[previousOwnerIndex].id
            if let ownerIndex = currentH3Index(withID: previousOwnerID) {
                touchH3(at: ownerIndex)
            }
        }

        return touchedIDs
    }

    mutating func touchChangedH3Packages(
        comparedTo previousDocument: NodeMarkdownDocument,
        affectedRowIndex: Int?,
        at timestamp: Date = Date()
    ) -> Set<String> {
        guard let affectedRowIndex else { return [] }
        let currentIndex = NodeMarkdownDocumentIndex(nodes: nodes)
        let previousStructureIndex = NodeMarkdownDocumentIndex(nodes: previousDocument.nodes)

        var candidateIndexes: Set<Int> = []
        if nodes.indices.contains(affectedRowIndex) {
            if nodes[affectedRowIndex].level == 3 {
                candidateIndexes.insert(affectedRowIndex)
            }
            if let ownerIndex = currentIndex.owningH3Row(for: affectedRowIndex) {
                candidateIndexes.insert(ownerIndex)
            }
        }

        if previousDocument.nodes.indices.contains(affectedRowIndex),
           let previousOwnerIndex = previousStructureIndex.owningH3Row(for: affectedRowIndex) {
            let previousOwnerID = previousDocument.nodes[previousOwnerIndex].id
            if let currentOwnerIndex = currentIndex.row(for: previousOwnerID),
               nodes.indices.contains(currentOwnerIndex), nodes[currentOwnerIndex].level == 3 {
                candidateIndexes.insert(currentOwnerIndex)
            }
        }

        var touchedIDs: Set<String> = []
        for h3Index in candidateIndexes where nodes.indices.contains(h3Index) && nodes[h3Index].level == 3 {
            nodes[h3Index].mtimeCache = timestamp
            nodes[h3Index].cache = NodeMarkdownCacheCodec.encode(mtime: timestamp)
            touchedIDs.insert(nodes[h3Index].id.uuidString)
        }
        return touchedIDs
    }

    @discardableResult
    mutating func restoreMissingH3SourceLinks(from previousDocument: NodeMarkdownDocument) -> Int {
        var previousH3ByID: [UUID: NodeMarkdownNode] = [:]
        for node in previousDocument.nodes where node.level == 3 {
            previousH3ByID[node.id] = node
        }

        var restoredCount = 0
        for index in nodes.indices where nodes[index].level == 3 {
            let currentSourceID = nodes[index].sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentSourceFile = nodes[index].sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
            guard currentSourceID.isEmpty || currentSourceFile.isEmpty else { continue }
            guard let previous = previousH3ByID[nodes[index].id] else { continue }
            let previousSourceID = previous.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            let previousSourceFile = previous.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !previousSourceID.isEmpty, !previousSourceFile.isEmpty else { continue }
            nodes[index].sourceID = previous.sourceID
            nodes[index].sourceFile = previous.sourceFile
            restoredCount += 1
        }
        return restoredCount
    }

    func owningH3Index(
        for index: Int,
        structuralIndex: NodeMarkdownDocumentIndex? = nil
    ) -> Int? {
        guard nodes.indices.contains(index) else { return nil }
        if let structuralIndex, structuralIndex.nodeCount == nodes.count {
            return structuralIndex.owningH3Row(for: index)
        }
        var cursor = index
        while cursor >= 0 {
            let node = nodes[cursor]
            if node.level == 3 { return cursor }
            if node.level > 0 && node.level < 3 { return nil }
            cursor -= 1
        }
        return nil
    }

    @discardableResult
    mutating func removeEmptyNodes(keepProtectedH3: Bool = true) -> Int {
        let beforeCount = nodes.count
        nodes = nodes.filter { node in
            let isEmpty = node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isProtected = keepProtectedH3
                && node.level == 3
                && !node.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return !isEmpty || isProtected
        }

        if nodes.isEmpty {
            let now = Date()
            nodes = [
                NodeMarkdownNode(
                    level: 1,
                    text: "",
                    sourceID: "",
                    sourceFile: "",
                    cache: NodeMarkdownCacheCodec.encode(mtime: now),
                    mtimeCache: now
                )
            ]
        }
        _ = ensureTrailingBlankLine(defaultLevel: min(12, max(1, nodes.last?.level ?? 1)))
        return max(0, beforeCount - nodes.count)
    }

    @discardableResult
    mutating func removeH3Package(startingAt h3Index: Int) -> Int {
        guard nodes.indices.contains(h3Index), nodes[h3Index].level == 3 else { return 0 }
        let index = NodeMarkdownDocumentIndex(nodes: nodes)
        let end = index.subtreeRange(startingAt: h3Index)?.upperBound ?? (h3Index + 1)
        let removeCount = max(0, end - h3Index)
        if removeCount == 0 { return 0 }
        nodes.removeSubrange(h3Index..<end)
        if nodes.isEmpty {
            let now = Date()
            nodes = [
                NodeMarkdownNode(
                    level: 1,
                    text: "",
                    sourceID: "",
                    sourceFile: "",
                    cache: NodeMarkdownCacheCodec.encode(mtime: now),
                    mtimeCache: now
                )
            ]
        }
        _ = ensureTrailingBlankLine(defaultLevel: min(12, max(1, nodes.last?.level ?? 1)))
        return removeCount
    }
}

// MARK: - NodeMarkdown缓存编解码 - v1 - 统一“#修时...@”格式解析与生成
enum NodeMarkdownCacheCodec {
    private static let formatter = ISO8601DateFormatter()

    static func encode(mtime: Date) -> String {
        "#修时\(formatter.string(from: mtime))@"
    }

    static func decode(_ value: String) -> Date? {
        guard value.hasPrefix("#"), value.hasSuffix("@") else { return nil }
        let body = String(value.dropFirst().dropLast())
        guard body.hasPrefix("修时") else { return nil }
        let timestamp = String(body.dropFirst(2))
        return formatter.date(from: timestamp)
    }
}

// MARK: - NodeMarkdown前缀映射 - v1 - 映射12层到Prefix并支持逆向解析
enum NodeMarkdownPrefixCodec {
    static func encode(level: Int) -> String {
        let safeLevel = max(1, min(12, level))
        switch safeLevel {
        case 1...6:
            return String(repeating: "#", count: safeLevel) + " "
        case 7:
            return "- "
        case 8:
            return "  - "
        case 9:
            return "    - "
        case 10:
            return "      - "
        case 11:
            return "        - "
        default:
            return "> "
        }
    }

    static func decode(prefix: String) -> Int {
        if prefix == "> " {
            return 12
        }
        if prefix.hasSuffix("- ") {
            let spaces = max(0, prefix.count - 2)
            if spaces % 2 == 0 {
                let bodyLevel = min(5, max(1, spaces / 2 + 1))
                return 6 + bodyLevel
            }
        }
        let hashCount = prefix.prefix { $0 == "#" }.count
        if hashCount > 0 {
            return min(6, hashCount)
        }
        return 7
    }
}

// MARK: - NodeMarkdown文件协议管理器 - v1 - 统一CSV六列正文与META读写兼容旧类型
struct NodeMarkdownFileManager {
    static let header = ["UUID", "Prefix", "Content", "SourceID", "SourceFile", "Cach"]

    static func read(fileURL: URL) throws -> (NodeMarkdownDocument, NodeMarkdownFileMeta) {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return read(rawText: text, fileTitleFallback: fileURL.deletingPathExtension().lastPathComponent)
    }

    static func read(rawText: String, fileTitleFallback: String = "") -> (NodeMarkdownDocument, NodeMarkdownFileMeta) {
        let rows = parseCSVRows(rawText)
        if rows.isEmpty {
            return legacyFromPlainMarkdown(rawText, fileTitleFallback: fileTitleFallback)
        }

        let firstRow = rows[0].map { $0.lowercased() }
        let isNodeCSV = firstRow.count >= 3
            && firstRow[0] == "uuid"
            && firstRow[1] == "prefix"
            && firstRow[2] == "content"

        guard isNodeCSV else {
            return legacyFromPlainMarkdown(rawText, fileTitleFallback: fileTitleFallback)
        }

        var nodes: [NodeMarkdownNode] = []
        var metaMap: [String: String] = [:]
        let now = Date()

        for row in rows.dropFirst() {
            if row.isEmpty || row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }
            if row.count > 1, row[0].hasPrefix("[META_") {
                metaMap[row[0]] = row[1]
                continue
            }

            let expanded = row + Array(repeating: "", count: max(0, 6 - row.count))
            let uuid = UUID(uuidString: expanded[0]) ?? UUID()
            let prefix = expanded[1]
            // U+FFFC只属于TextKit内存附件，绝不能进入领域文档。旧版本若曾把
            // 占位符写进CSV，在文件边界恢复后，新旧管线和导出共同得到干净源码。
            let content = NodeMarkdownLegacyAttachmentSourceRepair.repair(expanded[2])
            let sourceID = expanded[3]
            let sourceFile = expanded[4]
            let cache = expanded[5]
            let mtime = NodeMarkdownCacheCodec.decode(cache) ?? now
            let level = NodeMarkdownPrefixCodec.decode(prefix: prefix)
            let persistedSourceID = level == 3 ? sourceID : ""
            let persistedSourceFile = level == 3 ? sourceFile : ""
            let persistedCache = level == 3 ? (cache.isEmpty ? NodeMarkdownCacheCodec.encode(mtime: mtime) : cache) : ""

            nodes.append(
                NodeMarkdownNode(
                    id: uuid,
                    level: level,
                    text: content,
                    sourceID: persistedSourceID,
                    sourceFile: persistedSourceFile,
                    cache: persistedCache,
                    mtimeCache: mtime
                )
            )
        }

        if nodes.isEmpty {
            let defaultNow = Date()
            nodes = [
                NodeMarkdownNode(
                    level: 1,
                    text: "",
                    sourceID: "",
                    sourceFile: "",
                    cache: NodeMarkdownCacheCodec.encode(mtime: defaultNow),
                    mtimeCache: defaultNow
                )
            ]
        }

        let parsedType = (metaMap["[META_TYPE]"] ?? "nodemarkdown").lowercased()
        let normalizedType = (parsedType == "nodesmarkdown") ? "nodemarkdown" : parsedType
        let meta = NodeMarkdownFileMeta(
            id: metaMap["[META_ID]"] ?? UUID().uuidString,
            title: metaMap["[META_TITLE]"] ?? fileTitleFallback,
            template: metaMap["[META_TEMPLATE]"] ?? "nil",
            createdAt: metaMap["[META_CREATED]"] ?? ISO8601DateFormatter().string(from: Date()),
            type: normalizedType
        )
        return (NodeMarkdownDocument(nodes: nodes), meta)
    }

    static func write(document: NodeMarkdownDocument, meta: NodeMarkdownFileMeta, to fileURL: URL) throws {
        try NodeMarkdownIdentityPolicy.validateForPersistence(document)
        let text = serialize(document: document, meta: meta)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func serialize(document: NodeMarkdownDocument, meta: NodeMarkdownFileMeta) -> String {
        var lines: [String] = []
        lines.reserveCapacity(document.nodes.count + 8)
        lines.append(renderCSVRow(header))
        for node in document.nodes {
            lines.append(
                renderCSVRow([
                    node.id.uuidString,
                    NodeMarkdownPrefixCodec.encode(level: node.level),
                    NodeMarkdownLegacyAttachmentSourceRepair.repair(node.text),
                    node.persistenceSourceID,
                    node.persistenceSourceFile,
                    node.persistenceCache
                ])
            )
        }
        lines.append("")
        lines.append(renderCSVRow(["[META_ID]", meta.id]))
        lines.append(renderCSVRow(["[META_TITLE]", meta.title]))
        lines.append(renderCSVRow(["[META_TEMPLATE]", meta.template]))
        lines.append(renderCSVRow(["[META_CREATED]", meta.createdAt]))
        let rawType = meta.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let outputType = rawType.isEmpty ? "nodemarkdown" : rawType
        lines.append(renderCSVRow(["[META_TYPE]", outputType]))
        return lines.joined(separator: "\n")
    }

    private static func legacyFromPlainMarkdown(_ text: String, fileTitleFallback: String) -> (NodeMarkdownDocument, NodeMarkdownFileMeta) {
        let now = Date()
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        let nodes: [NodeMarkdownNode] = lines.isEmpty ? [
            NodeMarkdownNode(level: 1, text: "", cache: NodeMarkdownCacheCodec.encode(mtime: now), mtimeCache: now)
        ] : lines.map { line in
            let parsed = parseLegacyHeadingLine(
                NodeMarkdownLegacyAttachmentSourceRepair.repair(String(line))
            )
            return NodeMarkdownNode(
                level: parsed.level,
                text: parsed.text,
                sourceID: "",
                sourceFile: "",
                cache: NodeMarkdownCacheCodec.encode(mtime: now),
                mtimeCache: now
            )
        }
        return (
            NodeMarkdownDocument(nodes: nodes),
            NodeMarkdownFileMeta(title: fileTitleFallback, type: "nodemarkdown")
        )
    }

    private static func parseLegacyHeadingLine(_ line: String) -> (level: Int, text: String) {
        guard !line.isEmpty else { return (1, "") }
        let chars = Array(line)
        var index = 0
        while index < chars.count, chars[index] == "#" {
            index += 1
        }
        guard index > 0, index <= 12 else {
            return (7, line)
        }
        guard index < chars.count, chars[index] == " " else {
            return (7, line)
        }
        let textStart = min(chars.count, index + 1)
        return (index, String(chars[textStart...]))
    }

    private static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var index = 0

        while index < chars.count {
            let char = chars[index]
            if inQuotes {
                if char == "\"" {
                    if index + 1 < chars.count, chars[index + 1] == "\"" {
                        currentField.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                switch char {
                case "\"":
                    inQuotes = true
                case ",":
                    currentRow.append(currentField)
                    currentField = ""
                case "\n":
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                default:
                    currentField.append(char)
                }
            }
            index += 1
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }
        return rows
    }

    private static func renderCSVRow(_ fields: [String]) -> String {
        fields.map { field in
            if field.contains(",") || field.contains("\"") || field.contains("\n") {
                let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            return field
        }
        .joined(separator: ",")
    }
}

// MARK: - NodeMarkdown解析器兼容层 - v2 - 保留旧调用入口并转发到文件协议管理器
enum NodeMarkdownParser {
    static func parse(_ text: String, now: Date = Date()) -> NodeMarkdownDocument {
        let parsed = NodeMarkdownFileManager.read(rawText: text)
        return parsed.0
    }

    static func serialize(_ document: NodeMarkdownDocument) -> String {
        NodeMarkdownFileManager.serialize(document: document, meta: NodeMarkdownFileMeta())
    }
}

// MARK: - NodeMarkdown缓存记录 - v1 - 以层级文本位置组合键映射mtimeCache
struct NodeMarkdownCacheRecord: Codable, Hashable {
    var level: Int
    var text: String
    var occurrence: Int
    var mtime: Date
}

// MARK: - NodeMarkdown缓存存储 - v1 - 持久化节点mtimeCache并在重载时回填
enum NodeMarkdownCacheStore {
    static func loadMtimeMap(for documentURL: URL) -> [NodeMarkdownCacheRecord] {
        guard let data = try? Data(contentsOf: cacheURL(for: documentURL)) else { return [] }
        return (try? JSONDecoder().decode([NodeMarkdownCacheRecord].self, from: data)) ?? []
    }

    static func saveMtimeMap(_ records: [NodeMarkdownCacheRecord], for documentURL: URL) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: cacheURL(for: documentURL), options: .atomic)
    }

    static func applyCache(_ records: [NodeMarkdownCacheRecord], to document: inout NodeMarkdownDocument) {
        guard !records.isEmpty else { return }
        var cacheBuckets: [String: [NodeMarkdownCacheRecord]] = [:]
        for record in records {
            let key = "\(record.level)|\(record.text)"
            cacheBuckets[key, default: []].append(record)
        }
        for (key, value) in cacheBuckets {
            cacheBuckets[key] = value.sorted { $0.occurrence < $1.occurrence }
        }

        var seenOccurrences: [String: Int] = [:]
        for index in document.nodes.indices {
            let node = document.nodes[index]
            let key = "\(node.level)|\(node.text)"
            let occurrence = seenOccurrences[key, default: 0]
            seenOccurrences[key] = occurrence + 1
            if let recordsForKey = cacheBuckets[key],
               let matched = recordsForKey.first(where: { $0.occurrence == occurrence }) {
                document.nodes[index].mtimeCache = matched.mtime
            }
        }
    }

    static func buildCacheRecords(from document: NodeMarkdownDocument) -> [NodeMarkdownCacheRecord] {
        var seenOccurrences: [String: Int] = [:]
        var records: [NodeMarkdownCacheRecord] = []
        records.reserveCapacity(document.nodes.count)

        for node in document.nodes {
            let key = "\(node.level)|\(node.text)"
            let occurrence = seenOccurrences[key, default: 0]
            seenOccurrences[key] = occurrence + 1
            records.append(
                NodeMarkdownCacheRecord(
                    level: node.level,
                    text: node.text,
                    occurrence: occurrence,
                    mtime: node.mtimeCache
                )
            )
        }
        return records
    }

    private static func cacheURL(for documentURL: URL) -> URL {
        let fileName = documentURL.lastPathComponent + ".nodecache.json"
        let parent = documentURL.deletingLastPathComponent()
        return parent.appendingPathComponent(fileName, isDirectory: false)
    }
}
