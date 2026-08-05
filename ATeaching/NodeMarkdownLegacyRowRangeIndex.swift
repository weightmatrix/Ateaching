import Foundation

// MARK: - NodeMarkdown旧管线行范围索引 - v1 - 隔离文字坐标与样式刷新范围
/// 旧TextKit管线用UTF-16范围连接NSTextStorage中的段落和Node行号。
/// 普通字符编辑只能改变当前行长度，并让后续行整体平移；样式脏行不得参与坐标计算。
enum NodeMarkdownLegacyRowRangeIndex {
    /// 稳定范围记录最近一次结构提交时的坐标。普通字符输入只产生一个全局偏移：
    /// 当前行增长或缩短，后续行整体平移。任何渲染者都必须通过这里读取有效范围，
    /// 不得把输入中的临时坐标反写到稳定范围表。
    static func effectiveRange(
        at row: Int,
        in ranges: [NSRange],
        editedRow: Int?,
        characterDelta: Int
    ) -> NSRange? {
        guard ranges.indices.contains(row) else { return nil }
        var range = ranges[row]
        guard let editedRow, characterDelta != 0 else { return range }
        if row == editedRow {
            range.length = max(0, range.length + characterDelta)
        } else if row > editedRow {
            range.location = max(0, range.location + characterDelta)
        }
        return range
    }

    static func rowIndex(
        containing location: Int,
        in ranges: [NSRange],
        editedRow: Int?,
        characterDelta: Int
    ) -> Int? {
        guard !ranges.isEmpty else { return nil }
        var low = 0
        var high = ranges.count - 1
        while low <= high {
            let mid = (low + high) / 2
            guard let range = effectiveRange(
                at: mid,
                in: ranges,
                editedRow: editedRow,
                characterDelta: characterDelta
            ) else { return nil }
            if location < range.location {
                high = mid - 1
            } else if location >= NSMaxRange(range) {
                low = mid + 1
            } else {
                return mid
            }
        }
        guard let last = ranges.indices.last,
              let lastRange = effectiveRange(
                at: last,
                in: ranges,
                editedRow: editedRow,
                characterDelta: characterDelta
              ),
              location == NSMaxRange(lastRange) else { return nil }
        return last
    }

    static func rebuild(from text: String) -> [NSRange] {
        rebuild(from: text as NSString)
    }

    static func rebuild(from source: NSString) -> [NSRange] {
        guard source.length > 0 else { return [] }

        var ranges: [NSRange] = []
        var cursor = 0
        while cursor < source.length {
            let range = source.lineRange(for: NSRange(location: cursor, length: 0))
            guard range.length > 0, NSMaxRange(range) > cursor else { break }
            ranges.append(range)
            cursor = NSMaxRange(range)
        }
        if source.hasSuffix("\n") || source.hasSuffix("\r") {
            ranges.append(NSRange(location: source.length, length: 0))
        }
        return ranges
    }

    static func updatingCharacterEdit(
        ranges: [NSRange],
        editedRow: Int,
        text: String
    ) -> [NSRange]? {
        updatingCharacterEdit(ranges: ranges, editedRow: editedRow, source: text as NSString)
    }

    /// 普通字符编辑没有增删换行，只有当前行长度和后续行起点会变化。
    /// 这里不再逐行向NSString反查验证，避免每个按键把全文再扫描一遍。
    static func updatingCharacterEdit(
        ranges: [NSRange],
        editedRow: Int,
        source: NSString
    ) -> [NSRange]? {
        guard source.length > 0,
              ranges.indices.contains(editedRow),
              ranges[editedRow].location < source.length else { return nil }

        var updated = ranges
        updated[editedRow] = source.lineRange(
            for: NSRange(location: ranges[editedRow].location, length: 0)
        )

        if editedRow + 1 < updated.count {
            for row in (editedRow + 1)..<updated.count {
                updated[row] = NSRange(
                    location: NSMaxRange(updated[row - 1]),
                    length: ranges[row].length
                )
            }
        }
        guard updated.last.map({ NSMaxRange($0) }) == source.length else { return nil }
        return updated
    }

    static func isValid(_ ranges: [NSRange], in source: NSString) -> Bool {
        guard source.length > 0 else { return ranges.isEmpty }
        var expectedLocation = 0
        for (index, range) in ranges.enumerated() {
            if range.length == 0 {
                guard index == ranges.count - 1,
                      range.location == source.length,
                      source.hasSuffix("\n") || source.hasSuffix("\r") else { return false }
                expectedLocation = source.length
                continue
            }
            guard range.location == expectedLocation,
                  NSMaxRange(range) <= source.length else { return false }
            let actual = source.lineRange(for: NSRange(location: range.location, length: 0))
            guard actual == range else { return false }
            expectedLocation = NSMaxRange(range)
        }
        return expectedLocation == source.length
    }
}
