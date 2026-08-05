import Foundation

// MARK: - 单列表格模板同步 - v1 - 模板保存后按UUID重写所有使用该模板的单列表格

/// 当单列模板结构变化时，用模板的新UUID/KeyName顺序重写所有引用该模板的单列表格。
enum SingleListTemplatePropagationService {
    static func propagateTemplateChange(
        templateID: String,
        templateRows: [SingleListTemplateRow],
        fileManager: FileManager = .default
    ) throws -> Int {
        let normalizedTemplateID = templateID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTemplateID.isEmpty else { return 0 }

        let root = try ArchiveStorage.loadArchiveEntries(fileManager: fileManager).0
        let files = try singleListDocumentFiles(in: root, fileManager: fileManager)
        var changedCount = 0

        for fileURL in files {
            let loaded = try ArchiveStorage.readSingleListDocument(fileURL: fileURL)
            let oldRows = loaded.0
            let meta = loaded.1
            guard meta.templateID == normalizedTemplateID else { continue }

            let contentByRowID = Dictionary(uniqueKeysWithValues: oldRows.map { ($0.id, $0.content) })
            let nextRows = templateRows.map { templateRow in
                SingleListDocumentRow(
                    id: templateRow.id,
                    keyName: templateRow.keyName,
                    content: contentByRowID[templateRow.id] ?? ""
                )
            }
            try ArchiveStorage.writeSingleListDocument(fileURL: fileURL, rows: nextRows, meta: meta)
            changedCount += 1
        }

        return changedCount
    }

    private static func singleListDocumentFiles(
        in directoryURL: URL,
        fileManager: FileManager
    ) throws -> [URL] {
        let entries = try ArchiveStorage.loadEntries(in: directoryURL, fileManager: fileManager)
        var result: [URL] = []
        for entry in entries {
            if entry.isDirectory {
                result.append(contentsOf: try singleListDocumentFiles(in: entry.url, fileManager: fileManager))
            } else if entry.metaType == "singlelist" {
                result.append(entry.url)
            }
        }
        return result
    }
}
