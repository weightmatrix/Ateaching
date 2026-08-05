import Foundation

/// 延迟渲染同时绑定正文、样式和搜索三个版本。任一版本变化，旧任务都必须作废。
struct NodeMarkdownLegacyRenderRevision: Equatable {
    let document: UInt64
    let style: UInt64
    let search: UInt64
}

/// 旧管线只有四种合法刷新级别。滚动不是内容变化，不属于渲染事务。
enum NodeMarkdownLegacyRefreshLevel: Equatable {
    case currentRow(Int)
    case layoutRows(Set<Int>)
    case structureRows(Set<Int>)
    case initialDocument
}

enum NodeMarkdownLegacyRenderPolicy {
    /// 增量刷新只能有一份最终行集合。样式清理和重新渲染必须共同使用
    /// 这份结果，不能各自扩展相邻行。
    static func incrementalRows(
        requestedRows: Set<Int>,
        rowCount: Int,
        visibleRows: Set<Int>,
        expandsNeighbors: Bool
    ) -> Set<Int> {
        guard rowCount > 0 else { return [] }
        var resolved: Set<Int> = []
        for row in requestedRows where row >= 0 && row < rowCount {
            resolved.insert(row)
            guard expandsNeighbors else { continue }
            if row > 0 { resolved.insert(row - 1) }
            if row + 1 < rowCount { resolved.insert(row + 1) }
        }

        let validVisible = Set(visibleRows.filter { $0 >= 0 && $0 < rowCount })
        guard !validVisible.isEmpty else { return resolved }
        let filtered = resolved.intersection(validVisible)
        return filtered.isEmpty ? resolved : filtered
    }

    /// 将内容变化收敛成最终行集合。滚动只读取既有静态快照，不能调用这里。
    static func rows(
        for level: NodeMarkdownLegacyRefreshLevel,
        rowCount: Int,
        visibleRows: Set<Int>
    ) -> Set<Int>? {
        guard rowCount > 0 else { return [] }
        let validVisible = Set(visibleRows.filter { $0 >= 0 && $0 < rowCount })
        switch level {
        case let .currentRow(row):
            guard row >= 0, row < rowCount else { return [] }
            return [row]
        case let .layoutRows(rows):
            let valid = Set(rows.filter { $0 >= 0 && $0 < rowCount })
            let filtered = valid.intersection(validVisible)
            return filtered.isEmpty ? valid : filtered
        case let .structureRows(rows):
            let valid = Set(rows.filter { $0 >= 0 && $0 < rowCount })
            return valid.intersection(validVisible)
        case .initialDocument:
            return nil
        }
    }
}
