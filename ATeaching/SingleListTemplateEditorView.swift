import SwiftUI
import CoreText
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - 单列模板编辑器 - v1 - 负责单列模板的行名与配置编辑
struct SingleListTemplateEditorView: View {
    let fileURL: URL

    @State private var rows: [SingleListTemplateRow] = []
    @State private var meta = TemplateMeta(id: UUID().uuidString, title: "", type: TemplateCategory.singleList.metaType, keyCount: 0)
    @State private var statusMessage = ""
    @State private var isLoading = true
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var lastPropagatedSchema = ""
    @FocusState private var focusedRowID: String?
    @AppStorage("singleList.template.fonts.chineseOnly") private var showsChineseFontsOnly = false

    private let allFontOptions = SingleListInstalledFontCatalog.options

    private var fontOptions: [SingleListFontOption] {
        showsChineseFontsOnly ? allFontOptions.filter(\.supportsChinese) : allFontOptions
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            SingleListTextStyleControls(
                title: "标题字体",
                style: Binding(
                    get: { meta.titleStyle ?? .titleDefault },
                    set: { meta.titleStyle = $0 }
                ),
                fontOptions: fontOptions
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 8)

            Text(meta.title.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : meta.title)
                .font(.custom((meta.titleStyle ?? .titleDefault).fontName, size: (meta.titleStyle ?? .titleDefault).fontSize))
                .foregroundStyle(colorFromConfigToken((meta.titleStyle ?? .titleDefault).colorHex))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)

            List {
                ForEach($rows) { $row in
                    SingleListTemplateItemRowView(
                        row: $row,
                        focusedRowID: $focusedRowID,
                        fontOptions: fontOptions,
                        onSubmit: { insertRowAndFocus(below: row.id) },
                        onDelete: { removeRow(row.id) }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)

            HStack {
                Button {
                    let newRow = SingleListTemplateRow(id: UUID().uuidString, keyName: "", config: .default, content: "")
                    rows.append(newRow)
                    focusedRowID = newRow.id
                    requestAutoSave()
                } label: {
                    Image(systemName: "plus")
                }
                .appGlassButtonStyle(.prominent)
                .help("新增行")

                Spacer()
            }
            .padding(12)

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle(meta.title.isEmpty ? fileURL.lastPathComponent : meta.title)
        .task {
            load()
        }
        .onChange(of: rows) { _, _ in
            requestAutoSave()
        }
        .onChange(of: meta.titleStyle) { _, _ in
            requestAutoSave()
        }
        .onDisappear {
            autoSaveTask?.cancel()
            save()
        }
    }

    private var headerBar: some View {
        HStack {
            Text("行名与字体设置")
            Spacer()
            Button {
                showsChineseFontsOnly.toggle()
            } label: {
                Label("中文字体", systemImage: showsChineseFontsOnly ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.plain)
            .help("只显示支持中文的字体")
        }
        .font(.caption.weight(.semibold))
        .frame(height: 24)
        .padding(.horizontal, 24)
        .padding(.vertical, 0)
        .background(.bar)
    }

    private func load() {
        do {
            let value = try ArchiveStorage.readSingleListTemplate(fileURL: fileURL)
            rows = value.0
            meta = value.1
            lastPropagatedSchema = schemaSignature(value.0)
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
            try ArchiveStorage.writeSingleListTemplate(fileURL: fileURL, rows: rows, meta: meta)
            let currentSchema = schemaSignature(rows)
            let updatedCount: Int
            if currentSchema != lastPropagatedSchema {
                updatedCount = try SingleListTemplatePropagationService.propagateTemplateChange(
                    templateID: meta.id,
                    templateRows: rows
                )
                lastPropagatedSchema = currentSchema
            } else {
                updatedCount = 0
            }
            statusMessage = updatedCount > 0 ? "已自动保存，同步\(updatedCount)个单列表格" : "已自动保存"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func insertRowAndFocus(below rowID: String) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        let source = rows[index]
        let newRow = SingleListTemplateRow(
            id: UUID().uuidString,
            keyName: "",
            config: source.config,
            content: ""
        )
        rows.insert(newRow, at: index + 1)
        focusedRowID = newRow.id
        requestAutoSave()
    }

    private func removeRow(_ id: String) {
        rows.removeAll { $0.id == id }
        requestAutoSave()
    }

    private func requestAutoSave() {
        guard !isLoading else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                save()
            }
        }
    }

    private func schemaSignature(_ rows: [SingleListTemplateRow]) -> String {
        rows.map { "\($0.id)\u{1F}\($0.keyName)" }.joined(separator: "\u{1E}")
    }
}

// MARK: - 单列模板项 - v1 - 单行行名与配置编辑视图
struct SingleListTemplateItemRowView: View {
    @Binding var row: SingleListTemplateRow
    @FocusState.Binding var focusedRowID: String?

    let fontOptions: [SingleListFontOption]
    let onSubmit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("行名", text: $row.keyName)
                .font(.custom(row.config.keyNameStyle.fontName, size: row.config.keyNameStyle.fontSize))
                .foregroundStyle(colorFromConfigToken(row.config.keyNameStyle.colorHex))
                .textFieldStyle(.roundedBorder)
                .focused($focusedRowID, equals: row.id)
                .onSubmit(onSubmit)

            SingleListTextStyleControls(
                title: "行名字体",
                style: Binding(
                    get: { row.config.keyNameStyle },
                    set: { row.config.keyNameStyle = $0 }
                ),
                fontOptions: fontOptions
            )

            SingleListTextStyleControls(
                title: "Content字体",
                style: Binding(
                    get: { row.config.contentStyle },
                    set: { row.config.contentStyle = $0 }
                ),
                fontOptions: fontOptions
            )

            HStack {
                Text("Content")
                    .font(.custom(row.config.contentStyle.fontName, size: row.config.contentStyle.fontSize))
                    .foregroundStyle(colorFromConfigToken(row.config.contentStyle.colorHex))
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .appGlassButtonStyle(.danger)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
        .padding(.vertical, 1)
    }
}

private struct SingleListTextStyleControls: View {
    let title: String
    @Binding var style: SingleListTextStyle
    let fontOptions: [SingleListFontOption]

    @State private var showColorSelector = false
    @State private var showFontSelector = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(width: 88, alignment: .leading)

            Button {
                showFontSelector = true
            } label: {
                HStack {
                    Text(currentFontDisplayName)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(isPresented: $showFontSelector) {
                SingleListFontPickerView(
                    selectedFontName: $style.fontName,
                    fontOptions: normalizedFontOptions
                )
            }

            TextField("字号", value: Binding(
                get: { Int(style.fontSize) },
                set: { style.fontSize = Double(max(8, min(96, $0))) }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 66)

            Button {
                showColorSelector = true
            } label: {
                Circle()
                    .fill(colorFromConfigToken(style.colorHex))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(.secondary.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showColorSelector) {
                SingleListTemplateColorSelectorView(colorToken: $style.colorHex)
            }
        }
    }

    private var normalizedFontOptions: [SingleListFontOption] {
        guard !style.fontName.isEmpty,
              !fontOptions.contains(where: { $0.id == style.fontName }) else {
            return fontOptions
        }
        return [SingleListFontOption(id: style.fontName, displayName: style.fontName, supportsChinese: false)] + fontOptions
    }

    private var currentFontDisplayName: String {
        normalizedFontOptions.first(where: { $0.id == style.fontName })?.displayName ?? style.fontName
    }
}

struct SingleListFontOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let supportsChinese: Bool
}

private struct SingleListFontPickerView: View {
    @Binding var selectedFontName: String
    let fontOptions: [SingleListFontOption]

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var visibleOptions: [SingleListFontOption] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return fontOptions }
        return fontOptions.filter {
            $0.displayName.localizedCaseInsensitiveContains(keyword) ||
            $0.id.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        NavigationStack {
            List(visibleOptions) { option in
                Button {
                    selectedFontName = option.id
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.displayName)
                                .font(.custom(option.id, size: 17))
                            if option.displayName != option.id {
                                Text(option.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if option.id == selectedFontName {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "搜索字体")
            .navigationTitle("选择字体")
        }
        .singleListAdaptivePresentation(minWidth: 420, minHeight: 520)
    }
}

private enum SingleListInstalledFontCatalog {
    @MainActor
    static let options: [SingleListFontOption] = {
        #if os(macOS)
        let installed = NSFontManager.shared.availableFonts
        #elseif os(iOS)
        let installed = UIFont.familyNames.flatMap { UIFont.fontNames(forFamilyName: $0) }
        #else
        let installed: [String] = []
        #endif
        return Array(Set(installed + [SingleListTextStyle.default.fontName]))
            .compactMap(makeOption)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }()

    @MainActor
    private static func makeOption(fontName: String) -> SingleListFontOption? {
        #if os(macOS)
        guard let platformFont = NSFont(name: fontName, size: 16) else { return nil }
        let displayName = platformFont.displayName ?? fontName
        let ctFont = platformFont as CTFont
        #elseif os(iOS)
        guard let platformFont = UIFont(name: fontName, size: 16) else { return nil }
        let displayName = platformFont.fontDescriptor.object(forKey: .visibleName) as? String
            ?? platformFont.familyName
        let ctFont = platformFont as CTFont
        #else
        return SingleListFontOption(id: fontName, displayName: fontName, supportsChinese: false)
        #endif

        let characters = Array("中文".utf16)
        var glyphs = Array(repeating: CGGlyph(), count: characters.count)
        let supportsChinese = CTFontGetGlyphsForCharacters(ctFont, characters, &glyphs, characters.count)
        return SingleListFontOption(
            id: fontName,
            displayName: displayName,
            supportsChinese: supportsChinese
        )
    }
}

private func colorFromConfigToken(_ token: String) -> Color {
    let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

private func hexFromColor(_ color: Color) -> String {
    #if os(macOS)
    let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .labelColor
    let r = Int(round(nsColor.redComponent * 255))
    let g = Int(round(nsColor.greenComponent * 255))
    let b = Int(round(nsColor.blueComponent * 255))
    return String(format: "#%02X%02X%02X", r, g, b)
    #else
    return "#111111"
    #endif
}

private struct SingleListTemplateColorSelectorView: View {
    @Binding var colorToken: String

    @State private var customColor: Color

    private let paletteItems = markdownPresetPalette()
    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 64), spacing: 12)]

    init(colorToken: Binding<String>) {
        _colorToken = colorToken
        _customColor = State(initialValue: colorFromConfigToken(colorToken.wrappedValue))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("选择颜色")
                    .font(.headline)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(paletteItems) { palette in
                        Button {
                            applyPreset(palette)
                        } label: {
                            Circle()
                                .fill(palette.color)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle().stroke(isSelected(palette) ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: isSelected(palette) ? 3 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(palette.title)
                    }

                    ColorPicker("", selection: Binding(
                        get: { customColor },
                        set: { value in
                            customColor = value
                            colorToken = hexFromColor(value)
                        }
                    ))
                    .labelsHidden()
                    .frame(width: 28, height: 28)
                    .help("自选颜色")
                }
                Spacer()
            }
            .padding(16)
            .navigationTitle("行名颜色")
        }
        .singleListAdaptivePresentation(minWidth: 320, minHeight: 260)
    }

    private func applyPreset(_ item: MarkdownPaletteItem) {
        if item.semanticColor == .adaptiveBlackWhite {
            colorToken = SingleListRowConfig.adaptiveColorToken
            customColor = .primary
            return
        }
        colorToken = hexFromColor(item.color)
        customColor = item.color
    }

    private func isSelected(_ item: MarkdownPaletteItem) -> Bool {
        if item.semanticColor == .adaptiveBlackWhite {
            return colorToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == SingleListRowConfig.adaptiveColorToken
        }
        return colorToken.caseInsensitiveCompare(hexFromColor(item.color)) == .orderedSame
    }
}
