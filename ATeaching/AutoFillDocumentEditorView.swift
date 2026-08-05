import SwiftUI

// MARK: - 自动填写编辑器 - v1 - 编辑 autosinglelist 文件，仅允许修改 Content
struct AutoFillDocumentEditorView: View {
    let fileURL: URL

    @State private var rows: [SingleListDocumentRow] = []
    @State private var meta = SingleListDocumentMeta(id: UUID().uuidString, title: "", templateID: "", createdAt: "", type: "autosinglelist")
    @State private var styleMap: [String: SingleListRowConfig] = [:]
    @State private var titleStyle: SingleListTextStyle = .titleDefault
    @State private var isLoading = true
    @State private var statusMessage = ""
    @State private var autoSaveTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Text(meta.title.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : meta.title)
                .font(.custom(titleStyle.fontName, size: titleStyle.fontSize))
                .foregroundStyle(autoFillColorFromHex(titleStyle.colorHex))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 14)

            List {
                ForEach($rows) { $row in
                    rowView(for: $row)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(AppBackgroundVisualStyle.pageBackground)
        .navigationTitle(meta.title.isEmpty ? fileURL.lastPathComponent : meta.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    save()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .appGlassButtonStyle(.prominent)
                .help("保存")
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .task {
            load()
        }
        .onChange(of: rows) { _, _ in
            scheduleAutoSave()
        }
        .onDisappear {
            autoSaveTask?.cancel()
            save()
        }
    }

    @ViewBuilder
    private func rowView(for row: Binding<SingleListDocumentRow>) -> some View {
        let config = styleMap[row.wrappedValue.id] ?? .default
        let keyStyle = config.keyNameStyle
        let contentStyle = config.contentStyle

        VStack(alignment: .leading, spacing: 8) {
            Text(row.wrappedValue.keyName)
                .font(.custom(keyStyle.fontName, size: keyStyle.fontSize))
                .foregroundStyle(autoFillColorFromHex(keyStyle.colorHex))
                .frame(maxWidth: .infinity, alignment: .leading)

            SingleListMarkdownContentEditor(
                text: row.content,
                fontSize: contentStyle.fontSize,
                textColorHex: contentStyle.colorHex,
                fontName: contentStyle.fontName,
                shouldFocus: false,
                onBecameActive: {}
            )
            .padding(6)
        }
        .padding(.vertical, 4)
    }

    private func load() {
        do {
            let loaded = try ArchiveStorage.readAutoFillDocument(fileURL: fileURL)
            rows = loaded.0
            meta = loaded.1
            styleMap = ArchiveStorage.singleListTemplateStyleMap(templateID: meta.templateID)
            titleStyle = ArchiveStorage.singleListTemplateTitleStyle(templateID: meta.templateID)
            isLoading = false
        } catch {
            statusMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func save() {
        guard !isLoading else { return }
        do {
            meta.title = fileURL.deletingPathExtension().lastPathComponent
            try ArchiveStorage.writeAutoFillDocument(fileURL: fileURL, rows: rows, meta: meta)
            statusMessage = "已保存"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func scheduleAutoSave() {
        guard !isLoading else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                save()
            }
        }
    }
}

private func autoFillColorFromHex(_ hex: String) -> Color {
    let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized == SingleListRowConfig.adaptiveColorToken || normalized == "#111111" || normalized == "111111" {
        return .primary
    }
    let value = normalized.replacingOccurrences(of: "#", with: "")
    guard let int = Int(value, radix: 16) else { return .primary }
    let r = Double((int >> 16) & 0xFF) / 255.0
    let g = Double((int >> 8) & 0xFF) / 255.0
    let b = Double(int & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
}
