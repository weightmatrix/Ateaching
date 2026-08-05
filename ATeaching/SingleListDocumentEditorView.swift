import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - 单列表格编辑器 - v2 - Content专注编辑 + 工具栏对齐 + 图片导出
struct SingleListDocumentEditorView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let fileURL: URL
    var externalExportImageToken: Int = 0
    var showsReflectionSiblingNavigation: Bool = true
    var onClose: (() -> Void)?

    @State private var currentFileURL: URL
    @State private var reflectionSiblingFiles: [URL] = []

    @State private var rows: [SingleListDocumentRow] = []
    @State private var meta = SingleListDocumentMeta(id: UUID().uuidString, title: "", templateID: "", createdAt: "", type: "singlelist")
    @State private var styleMap: [String: SingleListRowConfig] = [:]
    @State private var titleStyle: SingleListTextStyle = .titleDefault
    @State private var isLoading = true
    @State private var statusMessage = ""
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var saveState: SaveState = .clean
    @State private var preferredSchemeOverride: ColorScheme?

    @State private var showSearchPopover = false
    @State private var searchText = ""
    @State private var searchMatches: [Int] = []
    @State private var activeSearchMatchIndex = 0
    @State private var showTOCPopover = false
    @State private var activeEditingRowID: String?
    #if os(macOS)
    @State private var activeSharingPicker: NSSharingServicePicker?
    @State private var pendingExportFileURL: URL?
    #endif

    init(
        fileURL: URL,
        externalExportImageToken: Int = 0,
        showsReflectionSiblingNavigation: Bool = true,
        onClose: (() -> Void)? = nil
    ) {
        self.fileURL = fileURL
        self.externalExportImageToken = externalExportImageToken
        self.showsReflectionSiblingNavigation = showsReflectionSiblingNavigation
        self.onClose = onClose
        _currentFileURL = State(initialValue: fileURL)
    }

    private enum SaveState {
        case clean
        case dirty
        case saving
        case failed
    }

    var body: some View {
        ZStack {
            SingleListVisualStyle.pageBackground

            VStack(spacing: 0) {
                if let onClose {
                    modalActionBar(onClose: onClose)
                }

                Text(meta.title.isEmpty ? currentFileURL.deletingPathExtension().lastPathComponent : meta.title)
                    .font(.custom(titleStyle.fontName, size: titleStyle.fontSize))
                    .foregroundStyle(colorFromHex(titleStyle.colorHex))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, editorHorizontalPadding)
                    .padding(.top, isCompactEditor ? 8 : 14)

                List {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, _ in
                        rowView(index: index, row: $rows[index])
                            .listRowInsets(
                                EdgeInsets(
                                    top: 4,
                                    leading: isCompactEditor ? 4 : 12,
                                    bottom: 4,
                                    trailing: isCompactEditor ? 4 : 12
                                )
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .id(rows[index].id)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
            .background(SingleListVisualStyle.roundedPageBackground)
            .clipShape(RoundedRectangle(cornerRadius: isCompactEditor ? 18 : 28, style: .continuous))
            .padding(isCompactEditor ? 4 : 12)
        }
        .navigationTitle(meta.title.isEmpty ? currentFileURL.lastPathComponent : meta.title)
        .toolbar {
            if onClose == nil {
                if showsReflectionNavigation {
                    ToolbarItemGroup(placement: .secondaryAction) {
                        Button {
                            stepReflectionFile(delta: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .help("上一个课反")
                        .disabled(reflectionSiblingFiles.count < 2)

                        Button {
                            stepReflectionFile(delta: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .help("下一个课反")
                        .disabled(reflectionSiblingFiles.count < 2)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button { showSearchPopover.toggle() } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .appGlassButtonStyle()
                    .help("搜索")
                    .popover(isPresented: $showSearchPopover) {
                        searchPanel
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button { toggleScheme() } label: {
                        Image(systemName: "circle.lefthalf.filled")
                    }
                    .appGlassButtonStyle()
                    .help("深浅色")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button { showTOCPopover.toggle() } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .appGlassButtonStyle()
                    .help("TOC")
                    .popover(isPresented: $showTOCPopover) {
                        tocPanel
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button { exportAsImage() } label: {
                        Image(systemName: "square.and.arrow.up.on.square")
                    }
                    .appGlassButtonStyle(.prominent)
                    .help("导出图片")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button { saveAfterCommittingEditor() } label: {
                        Image(systemName: saveIconName)
                    }
                    .appGlassButtonStyle(.prominent)
                    .help("保存")
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
        .task { load() }
        .onChange(of: fileURL) { _, newURL in
            guard newURL.standardizedFileURL != currentFileURL.standardizedFileURL else { return }
            switchToFile(newURL)
        }
        .onChange(of: rows) { _, _ in
            guard !isLoading else { return }
            saveState = .dirty
            rebuildSearchMatches()
            scheduleAutoSave()
        }
        .onChange(of: searchText) { _, _ in
            rebuildSearchMatches()
        }
        .onChange(of: externalExportImageToken) { _, _ in
            exportAsImage()
        }
        .onDisappear {
            autoSaveTask?.cancel()
            saveBeforeClose()
        }
        .preferredColorScheme(preferredSchemeOverride)
    }

    private var isCompactEditor: Bool {
        horizontalSizeClass == .compact
    }

    private var editorHorizontalPadding: CGFloat {
        isCompactEditor ? 10 : 18
    }

    private func modalActionBar(onClose: @escaping () -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    closeAfterSaving(onClose)
                } label: {
                    Label("关闭", systemImage: "xmark")
                }
                .appGlassButtonStyle()

                if showsReflectionNavigation {
                    Button {
                        stepReflectionFile(delta: -1)
                    } label: {
                        Label("上一个", systemImage: "chevron.left")
                    }
                    .appGlassButtonStyle()
                    .disabled(reflectionSiblingFiles.count < 2)

                    Button {
                        stepReflectionFile(delta: 1)
                    } label: {
                        Label("下一个", systemImage: "chevron.right")
                    }
                    .appGlassButtonStyle()
                    .disabled(reflectionSiblingFiles.count < 2)
                }

                Spacer(minLength: 12)

                Button { showSearchPopover.toggle() } label: {
                    Image(systemName: "magnifyingglass")
                }
                .appGlassButtonStyle()
                .help("搜索")
                .popover(isPresented: $showSearchPopover) {
                    searchPanel
                }

                Button { toggleScheme() } label: {
                    Image(systemName: "circle.lefthalf.filled")
                }
                .appGlassButtonStyle()
                .help("深浅色")

                Button { showTOCPopover.toggle() } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .appGlassButtonStyle()
                .help("目录")
                .popover(isPresented: $showTOCPopover) {
                    tocPanel
                }

                Button { exportAsImage() } label: {
                    Label("导出", systemImage: "square.and.arrow.up.on.square")
                }
                .appGlassButtonStyle(.prominent)

                Button { saveAfterCommittingEditor() } label: {
                    Label("保存", systemImage: saveIconName)
                }
                .appGlassButtonStyle(.prominent)
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.primary.opacity(0.035))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private func rowView(index: Int, row: Binding<SingleListDocumentRow>) -> some View {
        let config = styleMap[row.wrappedValue.id] ?? .default
        let keyStyle = config.keyNameStyle
        let contentStyle = config.contentStyle

        VStack(alignment: .leading, spacing: 8) {
            Text(row.wrappedValue.keyName)
                .font(.custom(keyStyle.fontName, size: keyStyle.fontSize))
                .foregroundStyle(colorFromHex(keyStyle.colorHex))
                .frame(maxWidth: .infinity, alignment: .leading)

            SingleListMarkdownContentEditor(
                text: row.content,
                fontSize: contentStyle.fontSize,
                textColorHex: contentStyle.colorHex,
                fontName: contentStyle.fontName,
                shouldFocus: activeEditingRowID == row.wrappedValue.id,
                onBecameActive: {
                    activeEditingRowID = row.wrappedValue.id
                }
            )
            .padding(6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .overlay(alignment: .topTrailing) {
            if searchMatches.contains(index) {
                Circle()
                    .fill(Color.yellow.opacity(0.9))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func load() {
        do {
            let loaded = try ArchiveStorage.readSingleListDocument(fileURL: currentFileURL)
            rows = loaded.0
            meta = loaded.1
            styleMap = ArchiveStorage.singleListTemplateStyleMap(templateID: meta.templateID)
            titleStyle = ArchiveStorage.singleListTemplateTitleStyle(templateID: meta.templateID)
            activeEditingRowID = loaded.0.first?.id
            refreshReflectionSiblingFiles()
            saveState = .clean
            rebuildSearchMatches()
            isLoading = false
        } catch {
            statusMessage = error.localizedDescription
            saveState = .failed
            isLoading = false
        }
    }

    @discardableResult
    private func saveCurrentDocument() -> Bool {
        guard !isLoading else { return false }
        do {
            saveState = .saving
            let currentTitle = currentFileURL.deletingPathExtension().lastPathComponent
            meta.title = currentTitle
            try ArchiveStorage.writeSingleListDocument(fileURL: currentFileURL, rows: rows, meta: meta)
            statusMessage = "已保存"
            saveState = .clean
            return true
        } catch {
            statusMessage = error.localizedDescription
            saveState = .failed
            return false
        }
    }

    private func save() {
        _ = saveCurrentDocument()
    }

    private func saveAfterCommittingEditor() {
        commitActiveEditorThen {
            save()
        }
    }

    private func closeAfterSaving(_ close: @escaping () -> Void) {
        autoSaveTask?.cancel()
        commitActiveEditorThen {
            guard saveCurrentDocument() else { return }
            close()
        }
    }

    private func saveBeforeClose() {
        endCurrentEditing()
        _ = saveCurrentDocument()
    }

    private func endCurrentEditing() {
        #if os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #else
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    /// NSTextView/TextField结束编辑时才会提交仍在输入法或活动控件中的最后内容。
    /// 下一轮主线程再读取rows，保证保存、导出和切换文件使用同一份最新数据。
    private func commitActiveEditorThen(_ action: @escaping () -> Void) {
        endCurrentEditing()
        DispatchQueue.main.async(execute: action)
    }

    private func scheduleAutoSave() {
        guard !isLoading else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            await MainActor.run { save() }
        }
    }

    private var showsReflectionNavigation: Bool {
        showsReflectionSiblingNavigation && isReflectionFile(currentFileURL)
    }

    private func isReflectionFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "csv"
            && url.lastPathComponent.hasPrefix("上课信息_")
    }

    private func refreshReflectionSiblingFiles() {
        guard isReflectionFile(currentFileURL) else {
            reflectionSiblingFiles = []
            return
        }
        reflectionSiblingFiles = ((try? FileManager.default.contentsOfDirectory(
            at: currentFileURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? [])
        .filter(isReflectionFile)
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func stepReflectionFile(delta: Int) {
        guard reflectionSiblingFiles.count > 1 else { return }
        let currentPath = currentFileURL.standardizedFileURL.path
        let currentIndex = reflectionSiblingFiles.firstIndex {
            $0.standardizedFileURL.path == currentPath
        } ?? 0
        let nextIndex = (currentIndex + delta + reflectionSiblingFiles.count) % reflectionSiblingFiles.count
        switchToFile(reflectionSiblingFiles[nextIndex])
    }

    private func switchToFile(_ url: URL) {
        guard url.standardizedFileURL != currentFileURL.standardizedFileURL else { return }
        autoSaveTask?.cancel()
        commitActiveEditorThen {
            guard saveCurrentDocument() else { return }
            currentFileURL = url
            rows = []
            styleMap = [:]
            titleStyle = .titleDefault
            activeEditingRowID = nil
            statusMessage = ""
            isLoading = true
            load()
        }
    }

    private var saveIconName: String {
        switch saveState {
        case .clean: return "checkmark.circle"
        case .dirty: return "circle.fill"
        case .saving: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private func toggleScheme() {
        if preferredSchemeOverride == nil {
            preferredSchemeOverride = .dark
        } else if preferredSchemeOverride == .dark {
            preferredSchemeOverride = .light
        } else {
            preferredSchemeOverride = nil
        }
    }

    private var tocPanel: some View {
        List(Array(rows.enumerated()), id: \.element.id) { index, row in
            Button {
                activeEditingRowID = row.id
                showTOCPopover = false
            } label: {
                Text(row.keyName.isEmpty ? "词条 \(index + 1)" : row.keyName)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        }
        .frame(width: isCompactEditor ? 280 : 320, height: isCompactEditor ? 360 : 320)
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("搜索词条/内容", text: $searchText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("命中 \(searchMatches.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("上一个") { jumpSearchMatch(step: -1) }
                    .disabled(searchMatches.isEmpty)
                Button("下一个") { jumpSearchMatch(step: 1) }
                    .disabled(searchMatches.isEmpty)
            }
        }
        .padding(12)
        .frame(width: isCompactEditor ? 280 : 320)
    }

    private func rebuildSearchMatches() {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else {
            searchMatches = []
            activeSearchMatchIndex = 0
            return
        }
        searchMatches = rows.enumerated().compactMap { index, row in
            let keyHit = row.keyName.lowercased().contains(keyword)
            let contentHit = row.content.lowercased().contains(keyword)
            return (keyHit || contentHit) ? index : nil
        }
        if activeSearchMatchIndex >= searchMatches.count {
            activeSearchMatchIndex = 0
        }
    }

    private func jumpSearchMatch(step: Int) {
        guard !searchMatches.isEmpty else { return }
        activeSearchMatchIndex = (activeSearchMatchIndex + step + searchMatches.count) % searchMatches.count
        let rowIndex = searchMatches[activeSearchMatchIndex]
        guard rows.indices.contains(rowIndex) else { return }
        activeEditingRowID = rows[rowIndex].id
    }

    private func exportAsImage() {
        commitActiveEditorThen {
            guard saveCurrentDocument() else { return }
            performImageExport()
        }
    }

    private func performImageExport() {
        #if os(macOS)
        guard let exportURL = makeExportImageFile() else { return }
        guard let anchorView = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView else {
            statusMessage = "导出失败：无法打开系统导出菜单。"
            return
        }

        pendingExportFileURL = exportURL
        let picker = NSSharingServicePicker(items: [exportURL])
        activeSharingPicker = picker
        picker.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
        statusMessage = "已打开系统导出菜单"
        #else
        guard let data = makeExportImageData() else { return }
        do {
            try TeachingDocumentExportService.exportToWeChat(
                sourceFileURL: currentFileURL,
                descriptor: TeachingDocumentExportDescriptor(
                    displayName: "PNG图片",
                    fileExtension: "png",
                    contentType: .png
                ),
                dataProvider: { data }
            )
            statusMessage = "已打开系统导出菜单"
        } catch {
            statusMessage = "导出失败：\(error.localizedDescription)"
        }
        #endif
    }

    #if os(macOS)
    private func makeExportImageFile() -> URL? {
        guard let data = makeExportImageData() else { return nil }

        do {
            let filename = "\(sanitizedExportFilename()).png"
            let directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ATeachingExports", isDirectory: true)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let exportURL = directoryURL.appendingPathComponent(filename)
            try data.write(to: exportURL, options: .atomic)
            return exportURL
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }
    #endif

    private func makeExportImageData() -> Data? {
        let exportView = SingleListExportSnapshotView(
            rows: rows,
            styleMap: styleMap,
            title: meta.title.isEmpty ? currentFileURL.deletingPathExtension().lastPathComponent : meta.title,
            titleStyle: titleStyle
        )
        let renderer = ImageRenderer(content: exportView.frame(width: 1200))
        renderer.scale = 2

        #if os(macOS)
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            statusMessage = "导出失败：无法生成图片。"
            return nil
        }
        return data
        #else
        guard let data = renderer.uiImage?.pngData() else {
            statusMessage = "导出失败：无法生成图片。"
            return nil
        }
        return data
        #endif
    }

    private func sanitizedExportFilename() -> String {
        let rawTitle = meta.title.isEmpty ? currentFileURL.deletingPathExtension().lastPathComponent : meta.title
        let fallback = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "单列表格" : rawTitle
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let sanitized = fallback.components(separatedBy: invalidCharacters).joined(separator: "-")
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "单列表格" : trimmed
    }
}

extension View {
    /// 表格和课反弹窗的统一尺寸边界：Mac保留可工作的最小窗口，
    /// iPhone/iPad只占系统实际提供的区域，禁止桌面尺寸把内容裁死。
    @ViewBuilder
    func singleListAdaptivePresentation(
        minWidth: CGFloat = 760,
        minHeight: CGFloat = 560
    ) -> some View {
        #if os(macOS)
        self.frame(minWidth: minWidth, minHeight: minHeight)
        #else
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
    }
}

func colorFromHex(_ hex: String) -> Color {
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

struct SingleListMarkdownContentEditor: View {
    @Binding var text: String
    let fontSize: Double
    let textColorHex: String
    let fontName: String
    let shouldFocus: Bool
    let onBecameActive: () -> Void

    @State private var measuredHeight: CGFloat = 32

    var body: some View {
        #if os(macOS)
        SingleListMacContentTextView(
            text: $text,
            fontSize: fontSize,
            textColorHex: textColorHex,
            fontName: fontName,
            shouldFocus: shouldFocus,
            onBecameActive: onBecameActive,
            measuredHeight: $measuredHeight
        )
        .frame(height: max(32, measuredHeight))
        #else
        TextField("", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...Int.max)
            .font(.custom(fontName, size: fontSize))
            .foregroundStyle(colorFromHex(textColorHex))
            .frame(minHeight: 32)
        #endif
    }
}

#if os(macOS)
private struct SingleListMacContentTextView: NSViewRepresentable {
    @Binding var text: String
    let fontSize: Double
    let textColorHex: String
    let fontName: String
    let shouldFocus: Bool
    let onBecameActive: () -> Void
    @Binding var measuredHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, measuredHeight: $measuredHeight, onBecameActive: onBecameActive)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = SingleListForwardingScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = SingleListAutoContinueTextView()
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        textView.textColor = NSColor(colorFromHex(textColorHex))

        scrollView.documentView = textView
        context.coordinator.textView = textView
        scrollView.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
            guard let coordinator, let scrollView else { return }
            coordinator.updateMeasuredHeight(in: scrollView)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.update(text: $text, measuredHeight: $measuredHeight, onBecameActive: onBecameActive)
        context.coordinator.syncExternalTextIfNeeded(text, into: textView)
        textView.font = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        textView.textColor = NSColor(colorFromHex(textColorHex))
        if shouldFocus, let window = textView.window, window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
        DispatchQueue.main.async { [weak coordinator = context.coordinator, weak nsView] in
            guard let coordinator, let nsView else { return }
            coordinator.updateMeasuredHeight(in: nsView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var textBinding: Binding<String>
        private var measuredHeightBinding: Binding<CGFloat>
        weak var textView: NSTextView?
        private var onBecameActive: () -> Void
        private var currentText: String
        private var isEditing = false

        init(
            text: Binding<String>,
            measuredHeight: Binding<CGFloat>,
            onBecameActive: @escaping () -> Void
        ) {
            textBinding = text
            measuredHeightBinding = measuredHeight
            currentText = text.wrappedValue
            self.onBecameActive = onBecameActive
        }

        func update(
            text: Binding<String>,
            measuredHeight: Binding<CGFloat>,
            onBecameActive: @escaping () -> Void
        ) {
            textBinding = text
            measuredHeightBinding = measuredHeight
            self.onBecameActive = onBecameActive
        }

        func syncExternalTextIfNeeded(_ externalText: String, into textView: NSTextView) {
            if textView.markedRange().location != NSNotFound {
                currentText = textView.string
                return
            }

            if textView.string == externalText {
                currentText = externalText
                return
            }

            if isEditing, externalText != currentText {
                return
            }

            textView.string = externalText
            currentText = externalText
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            currentText = textView.string
            if let scrollView = textView.enclosingScrollView {
                updateMeasuredHeight(in: scrollView)
            }
            guard textView.markedRange().location == NSNotFound else { return }
            commitCurrentText(from: textView)
        }

        func textDidBeginEditing(_ notification: Notification) {
            if let textView {
                currentText = textView.string
            }
            isEditing = true
            onBecameActive()
        }

        func textShouldEndEditing(_ textObject: NSText) -> Bool {
            if let textView = textObject as? NSTextView {
                commitCurrentText(from: textView, acceptingMarkedText: true)
            }
            return true
        }

        func textDidEndEditing(_ notification: Notification) {
            if let textView {
                commitCurrentText(from: textView)
            }
            isEditing = false
        }

        private func commitCurrentText(from textView: NSTextView, acceptingMarkedText: Bool = false) {
            if acceptingMarkedText, textView.markedRange().location != NSNotFound {
                textView.unmarkText()
            }
            currentText = textView.string
            if textBinding.wrappedValue != currentText {
                textBinding.wrappedValue = currentText
            }
        }

        func updateMeasuredHeight(in scrollView: NSScrollView) {
            guard let textView,
                  let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager else { return }
            let availableWidth = max(1, scrollView.contentSize.width - textView.textContainerInset.width * 2)
            if abs(textContainer.containerSize.width - availableWidth) > 0.5 {
                textContainer.containerSize = NSSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
            }
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            let verticalInsets = textView.textContainerInset.height * 2
            let nextHeight = ceil(max(32, usedHeight + verticalInsets + 4))
            if abs(textView.frame.height - nextHeight) > 0.5 {
                textView.frame.size.height = nextHeight
            }
            if abs(measuredHeightBinding.wrappedValue - nextHeight) > 0.5 {
                measuredHeightBinding.wrappedValue = nextHeight
            }
        }
    }
}

private final class SingleListForwardingScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        if let textView = documentView as? NSTextView {
            textView.frame.size.width = contentSize.width
        }
        onLayout?()
    }

    override func scrollWheel(with event: NSEvent) {
        if let parentScrollView = firstParentScrollView() {
            parentScrollView.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    private func firstParentScrollView() -> NSScrollView? {
        var current = superview
        while let view = current {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            if let enclosing = view.enclosingScrollView, enclosing !== self {
                return enclosing
            }
            current = view.superview
        }
        return nil
    }
}

private final class SingleListAutoContinueTextView: NSTextView {
    override func insertNewline(_ sender: Any?) {
        if applyAutoContinueRule() {
            return
        }
        super.insertNewline(sender)
    }

    private func applyAutoContinueRule() -> Bool {
        let nsText = string as NSString
        let selection = selectedRange()
        guard selection.length == 0 else { return false }

        let baseLocation = max(0, min(selection.location, nsText.length))
        let lineAnchor = max(0, min(baseLocation > 0 ? baseLocation - 1 : baseLocation, nsText.length))
        let lineRange = nsText.lineRange(for: NSRange(location: lineAnchor, length: 0))

        var line = nsText.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }

        guard baseLocation == lineRange.location + (line as NSString).length else { return false }
        guard let marker = parseMarker(in: line) else { return false }

        if marker.hasContent {
            let insertion = "\n\(marker.nextMarker)"
            textStorage?.replaceCharacters(in: selection, with: insertion)
            setSelectedRange(NSRange(location: baseLocation + (insertion as NSString).length, length: 0))
            didChangeText()
            return true
        }

        let markerRange = NSRange(location: lineRange.location, length: marker.markerLength)
        textStorage?.replaceCharacters(in: markerRange, with: "")
        let adjustedLocation = baseLocation - marker.markerLength
        textStorage?.replaceCharacters(in: NSRange(location: adjustedLocation, length: 0), with: "\n")
        setSelectedRange(NSRange(location: adjustedLocation + 1, length: 0))
        didChangeText()
        return true
    }

    private func parseMarker(in line: String) -> (nextMarker: String, markerLength: Int, hasContent: Bool)? {
        if let numbered = parseNumberedMarker(in: line) {
            return numbered
        }
        if let bullet = parseFixedMarker(in: line, markerBody: "- ") {
            return bullet
        }
        if let quote = parseFixedMarker(in: line, markerBody: "> ") {
            return quote
        }
        if let comment = parseCommentMarker(in: line) {
            return comment
        }
        return nil
    }

    private func parseNumberedMarker(in line: String) -> (nextMarker: String, markerLength: Int, hasContent: Bool)? {
        let chars = Array(line)
        var index = 0

        while index < chars.count, chars[index] == " " { index += 1 }
        let numberStart = index
        while index < chars.count, chars[index].isNumber { index += 1 }
        guard index > numberStart else { return nil }
        guard index < chars.count, chars[index] == "." else { return nil }
        guard index + 1 < chars.count, chars[index + 1] == " " else { return nil }

        let number = Int(String(chars[numberStart..<index])) ?? 1
        let content = String(chars[(index + 2)...]).trimmingCharacters(in: .whitespaces)
        let indent = String(chars[0..<numberStart])
        let next = "\(indent)\(number + 1). "
        return (next, index + 2, !content.isEmpty)
    }

    private func parseFixedMarker(in line: String, markerBody: String) -> (nextMarker: String, markerLength: Int, hasContent: Bool)? {
        let indentCount = line.prefix { $0 == " " }.count
        let indent = String(repeating: " ", count: indentCount)
        let remaining = String(line.dropFirst(indentCount))
        guard remaining.hasPrefix(markerBody) else { return nil }
        let markerLength = indentCount + markerBody.count
        let content = String(remaining.dropFirst(markerBody.count)).trimmingCharacters(in: .whitespaces)
        return (indent + markerBody, markerLength, !content.isEmpty)
    }

    private func parseCommentMarker(in line: String) -> (nextMarker: String, markerLength: Int, hasContent: Bool)? {
        let indentCount = line.prefix { $0 == " " }.count
        let indent = String(repeating: " ", count: indentCount)
        let remaining = String(line.dropFirst(indentCount))
        guard remaining.hasPrefix("注释") else { return nil }

        var marker = "注释"
        var offset = 2
        let chars = Array(remaining)
        if offset < chars.count, [":", "：", ".", "。"].contains(chars[offset]) {
            marker.append(chars[offset])
            offset += 1
        }
        if offset < chars.count, chars[offset] == " " {
            marker.append(" ")
            offset += 1
        } else {
            marker.append(" ")
        }

        let content = String(chars.dropFirst(offset)).trimmingCharacters(in: .whitespaces)
        let markerLength = indentCount + marker.count
        return (indent + marker, markerLength, !content.isEmpty)
    }
}
#endif
