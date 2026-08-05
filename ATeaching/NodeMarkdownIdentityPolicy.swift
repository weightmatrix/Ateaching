import Foundation

// MARK: - Node身份规则 - UUID只表示一个Node，编辑保留、增加新建、删除作废、剪切整体移动

enum NodeMarkdownIdentityPolicy {
    static func validateForPersistence(_ document: NodeMarkdownDocument) throws {
        try validateUniqueNodeIDs(document)

        for node in document.nodes {
            let sourceID = node.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceFile = node.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
            guard node.level == 3 || (sourceID.isEmpty && sourceFile.isEmpty) else {
                throw NSError(
                    domain: "NodeMarkdownIdentityPolicy",
                    code: 7833,
                    userInfo: [
                        NSLocalizedDescriptionKey: "非H3节点携带母本来源，已停止写盘：\(node.id.uuidString)"
                    ]
                )
            }
            // 旧文件可能只剩SourceID或SourceFile；允许H3暂存，由同步阶段按既有规则补齐。
            if node.level == 3, !sourceID.isEmpty, !sourceFile.isEmpty {
                guard let linkedID = UUID(uuidString: sourceID), linkedID == node.id else {
                    throw NSError(
                        domain: "NodeMarkdownIdentityPolicy",
                        code: 7834,
                        userInfo: [
                            NSLocalizedDescriptionKey: "H3节点UUID与SourceID不一致，已停止写盘：\(node.id.uuidString)"
                        ]
                    )
                }
            }
        }
    }

    static func validateUniqueNodeIDs(_ document: NodeMarkdownDocument) throws {
        let duplicateIDs = duplicateNodeIDs(in: document)
        guard duplicateIDs.isEmpty else {
            let preview = duplicateIDs.prefix(5).map(\.uuidString).joined(separator: "、")
            let suffix = duplicateIDs.count > 5 ? "等\(duplicateIDs.count)个" : ""
            throw NSError(
                domain: "NodeMarkdownIdentityPolicy",
                code: 7831,
                userInfo: [
                    NSLocalizedDescriptionKey: "文档存在重复Node UUID，已停止写盘，避免继续传播：\(preview)\(suffix)"
                ]
            )
        }
    }

    // 同步允许半截来源进入既有修复流程，但不允许重复身份或完整链接指向别的UUID。
    static func validateForSynchronization(_ document: NodeMarkdownDocument) throws {
        try validateUniqueNodeIDs(document)
        for node in document.nodes where node.level == 3 {
            let sourceID = node.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceFile = node.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sourceID.isEmpty, !sourceFile.isEmpty else { continue }
            guard let linkedID = UUID(uuidString: sourceID), linkedID == node.id else {
                throw NSError(
                    domain: "NodeMarkdownIdentityPolicy",
                    code: 7835,
                    userInfo: [
                        NSLocalizedDescriptionKey: "H3身份异常，已停止同步：\(node.id.uuidString)"
                    ]
                )
            }
        }
    }

    static func duplicateNodeIDs(in document: NodeMarkdownDocument) -> [UUID] {
        var seen: Set<UUID> = []
        var duplicates: Set<UUID> = []
        for node in document.nodes {
            if !seen.insert(node.id).inserted {
                duplicates.insert(node.id)
            }
        }
        return duplicates.sorted { $0.uuidString < $1.uuidString }
    }

    static func firstCollision(
        inserting nodes: [NodeMarkdownNode],
        into document: NodeMarkdownDocument
    ) -> UUID? {
        let existingIDs = Set(document.nodes.map(\.id))
        var insertedIDs: Set<UUID> = []
        for node in nodes {
            guard insertedIDs.insert(node.id).inserted,
                  !existingIDs.contains(node.id) else {
                return node.id
            }
        }
        return nil
    }

    // 复制与剪切不同：复制出来的每个Node都获得新身份，H3复制品成为未绑定的新包。
    static func copyAsNewNodes(_ nodes: [NodeMarkdownNode]) -> [NodeMarkdownNode] {
        var assignedIDs: Set<UUID> = []
        return nodes.map { source in
            var copy = source
            var freshID = UUID()
            while assignedIDs.contains(freshID) {
                freshID = UUID()
            }
            assignedIDs.insert(freshID)
            copy.id = freshID
            if copy.level == 3 {
                copy.sourceID = ""
                copy.sourceFile = ""
            }
            return copy
        }
    }
}
