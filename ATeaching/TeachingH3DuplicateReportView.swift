import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - H3名称查重 - 只读扫描正式教案并按名称汇总位置

struct TeachingH3DuplicateOccurrence: Identifiable, Hashable {
    let id: String
    let lessonName: String
    let chapterName: String
    let nodeID: UUID
    let rowNumber: Int
}

struct TeachingH3DuplicateGroup: Identifiable, Hashable {
    let title: String
    let occurrences: [TeachingH3DuplicateOccurrence]

    var id: String { title }
}

enum TeachingH3DuplicateScanner {
    nonisolated static func scan(
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> [TeachingH3DuplicateGroup] {
        let root = rootURL.standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var occurrencesByName: [String: (title: String, items: [TeachingH3DuplicateOccurrence])] = [:]
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.caseInsensitiveCompare("csv") == .orderedSame,
                  fileURL.standardizedFileURL.path.hasPrefix(rootPath) else { continue }
            let relativePath = String(fileURL.standardizedFileURL.path.dropFirst(rootPath.count))
            let components = relativePath.split(separator: "/").map(String.init)
            guard !components.isEmpty, components.first != "上课收集" else { continue }
            guard let rows = try? h3Rows(in: fileURL) else { continue }

            let lessonName = components.count > 1 ? components[0] : "根目录"
            let chapterName = fileURL.deletingPathExtension().lastPathComponent
            for row in rows {
                let title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                let normalizedName = normalize(title)
                let occurrence = TeachingH3DuplicateOccurrence(
                    id: "\(relativePath)#\(row.rowNumber)#\(row.nodeID.uuidString)",
                    lessonName: lessonName,
                    chapterName: chapterName,
                    nodeID: row.nodeID,
                    rowNumber: row.rowNumber
                )
                if occurrencesByName[normalizedName] == nil {
                    occurrencesByName[normalizedName] = (title, [])
                }
                occurrencesByName[normalizedName]?.items.append(occurrence)
            }
        }

        return occurrencesByName.values
            .filter { $0.items.count > 1 }
            .map { value in
                TeachingH3DuplicateGroup(
                    title: value.title,
                    occurrences: value.items.sorted {
                        if $0.lessonName != $1.lessonName {
                            return $0.lessonName.localizedStandardCompare($1.lessonName) == .orderedAscending
                        }
                        return $0.chapterName.localizedStandardCompare($1.chapterName) == .orderedAscending
                    }
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    nonisolated static func exportText(groups: [TeachingH3DuplicateGroup]) -> String {
        let maxOccurrences = groups.map(\.occurrences.count).max() ?? 0
        let occurrenceHeaders = maxOccurrences > 0
            ? (1...maxOccurrences).map { "出现\($0)" }
            : []
        let header = (["H3名称"] + occurrenceHeaders).joined(separator: "\t")
        let lines = groups.map { group in
            let cells = group.occurrences.map {
                "\($0.lessonName) / \($0.chapterName) / 第\($0.rowNumber)行 [\($0.nodeID.uuidString)]"
            }
            return ([group.title] + cells).joined(separator: "\t")
        }
        return ([header] + lines).joined(separator: "\n")
    }

    nonisolated private static func normalize(_ title: String) -> String {
        title
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    /// 查重只需要UUID、Prefix和Content，直接在后台读取CSV，避免把文件解析送回主线程。
    nonisolated private static func h3Rows(in fileURL: URL) throws -> [(nodeID: UUID, title: String, rowNumber: Int)] {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        let rows = parseCSVRows(text)
        guard let header = rows.first,
              header.count >= 3,
              header[0].caseInsensitiveCompare("UUID") == .orderedSame,
              header[1].caseInsensitiveCompare("Prefix") == .orderedSame,
              header[2].caseInsensitiveCompare("Content") == .orderedSame else { return [] }
        return rows.dropFirst().enumerated().compactMap { offset, fields in
            guard fields.count >= 3,
                  fields[1].trimmingCharacters(in: .whitespacesAndNewlines) == "###",
                  let nodeID = UUID(uuidString: fields[0]) else { return nil }
            return (nodeID, fields[2], offset + 2)
        }
    }

    nonisolated private static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if isQuoted, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                isQuoted.toggle()
            } else if character == ",", !isQuoted {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !isQuoted {
                if character == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" {
                        index = next
                    }
                }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

struct TeachingH3DuplicateReportView: View {
    @State private var groups: [TeachingH3DuplicateGroup] = []
    @State private var statusMessage = "尚未扫描"
    @State private var isScanning = false
    @State private var isExporting = false
    @State private var exportDocument = TeachingH3DuplicateExportDocument(content: "")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    runScan()
                } label: {
                    Label("开始查重", systemImage: "text.magnifyingglass")
                }
                .disabled(isScanning)

                Button {
                    exportDocument = TeachingH3DuplicateExportDocument(
                        content: TeachingH3DuplicateScanner.exportText(groups: groups)
                    )
                    isExporting = true
                } label: {
                    Label("导出列表", systemImage: "square.and.arrow.up")
                }
                .disabled(groups.isEmpty || isScanning)

                if isScanning { ProgressView() }
                Spacer()
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if groups.isEmpty, !isScanning {
                ContentUnavailableView(
                    statusMessage == "尚未扫描" ? "尚未扫描" : "没有重名H3",
                    systemImage: "checkmark.circle"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                duplicateGrid
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("H3查重")
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .tabSeparatedText,
            defaultFilename: exportFilename
        ) { result in
            if case let .failure(error) = result {
                statusMessage = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    private var duplicateGrid: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(groups) { group in
                    HStack(alignment: .top, spacing: 6) {
                        Text(group.title)
                            .font(.headline)
                            .frame(width: 220, alignment: .leading)
                            .textSelection(.enabled)
                        ForEach(group.occurrences) { occurrence in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(occurrence.lessonName)
                                    .fontWeight(.semibold)
                                Text(occurrence.chapterName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("第\(occurrence.rowNumber)行")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(width: 190, alignment: .leading)
                            .padding(8)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .help(occurrence.nodeID.uuidString)
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    private func runScan() {
        guard !isScanning else { return }
        isScanning = true
        statusMessage = "正在扫描正式教案…"
        Task {
            do {
                let rootURL = try LessonPlanStorage.lessonPlanRootURL()
                let result = try await Task.detached(priority: .userInitiated) {
                    try TeachingH3DuplicateScanner.scan(rootURL: rootURL)
                }.value
                groups = result
                statusMessage = result.isEmpty ? "没有发现重名H3" : "发现\(result.count)组重名H3"
            } catch {
                groups = []
                statusMessage = "扫描失败：\(error.localizedDescription)"
            }
            isScanning = false
        }
    }

    private var exportFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "H3查重_\(formatter.string(from: Date()))"
    }
}

private struct TeachingH3DuplicateExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.tabSeparatedText, .plainText] }
    var content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let value = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        content = value
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(content.utf8))
    }
}
