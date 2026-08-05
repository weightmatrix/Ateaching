import SwiftUI
import UniformTypeIdentifiers
import CoreText
import Combine
#if canImport(SwiftMath)
import SwiftMath
#endif
#if os(macOS) || os(iOS)
import WebKit
#endif

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

#if os(macOS)
private let markdownTextKit2AttachmentSourceTokenKey = NSAttributedString.Key("MarkdownTextKit2AttachmentSourceToken")
#endif

// MARK: - 渲染模式枚举 - v6 - 定义即时渲染源码模式与Web渲染三种模式
enum MarkdownRenderMode: String, CaseIterable, Identifiable {
    case dual = "双区域"
    case textKit2Plain = "TextKit2编辑"
    case instant = "Markdown旧管道"
    case source = "源码模式"
    case web = "Web渲染"

    var id: String { rawValue }

    static var visibleCases: [MarkdownRenderMode] {
        [.dual, .textKit2Plain, .source, .web]
    }
}

// MARK: - 保存状态枚举 - v1 - 定义编辑器保存图标的状态机
enum MarkdownSaveState {
    case clean
    case dirty
    case saving
    case failed
}

// MARK: - 导出格式枚举 - v1 - 定义Markdown编辑器可导出的文件格式
enum MarkdownExportFormat: String, CaseIterable {
    case pdf = "PDF"
    case html = "HTML"
    case markdown = "MD"

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .html: return "html"
        case .markdown: return "md"
        }
    }

    var contentType: UTType {
        switch self {
        case .pdf: return .pdf
        case .html: return .html
        case .markdown: return .plainText
        }
    }

    var exportDescriptor: TeachingDocumentExportDescriptor {
        TeachingDocumentExportDescriptor(
            displayName: rawValue,
            fileExtension: fileExtension,
            contentType: contentType
        )
    }
}

// MARK: - 系统等宽字体常量 - v1 - 提供统一的Apple System Monospaced字体标识
let appleSystemMonospacedFontName = "Apple System Monospaced"

// MARK: - Markdown编辑器性能探针 - v1 - 为TextKit2迁移前建立输入渲染边界画像
private enum MarkdownEditorPerformanceProbe {
    static var isEnabled: Bool {
        TeachingDebugLogStore.isLayoutJitterLogsEnabled()
    }

    static func start() -> CFAbsoluteTime {
        isEnabled ? CFAbsoluteTimeGetCurrent() : 0
    }

    static func end(_ scope: String, start: CFAbsoluteTime, details: @autoclosure () -> String = "") {
        guard isEnabled else { return }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        guard elapsedMs >= 0.5 else { return }
        let resolvedDetails = details()
        let suffix = resolvedDetails.isEmpty ? "" : " | \(resolvedDetails)"
        TeachingDebugLogStore.append(
            String(format: "%@ %.2fms%@", scope, elapsedMs, suffix),
            category: "MarkdownEditor.Profile"
        )
    }

    static func metric(
        _ scope: String,
        start: CFAbsoluteTime,
        budgetMs: Double,
        textLength: Int,
        details: @autoclosure () -> String = ""
    ) {
        guard isEnabled else { return }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        guard elapsedMs >= 0.5 || elapsedMs > budgetMs else { return }
        let status = elapsedMs > budgetMs ? "slow" : "ok"
        let resolvedDetails = details()
        let suffix = resolvedDetails.isEmpty ? "" : " | \(resolvedDetails)"
        TeachingDebugLogStore.append(
            String(
                format: "METRIC %@ %.2fms status=%@ budget=%.1fms tier=%@ utf16=%d%@",
                scope,
                elapsedMs,
                status,
                budgetMs,
                documentTier(textLength),
                textLength,
                suffix
            ),
            category: "MarkdownEditor.Metric"
        )
    }

    static func textDetails(_ text: String) -> String {
        "utf16=\((text as NSString).length)"
    }

    static func rangeDetails(_ range: NSRange, textLength: Int) -> String {
        "range={\(range.location),\(range.length)},utf16=\(textLength)"
    }

    private static func documentTier(_ textLength: Int) -> String {
        if textLength >= 500_000 { return "500k+" }
        if textLength >= 200_000 { return "200k+" }
        if textLength >= 50_000 { return "50k+" }
        return "small"
    }
}

// MARK: - Markdown删除诊断前缀 - v1 - 只用于性能记录，不改变编辑行为
private func markdownProtectedPrefixLengthForDeletion(in line: String) -> Int {
    let nsLine = line as NSString
    let length = nsLine.length
    guard length > 0 else { return 0 }

    var index = 0
    while index < length {
        let character = nsLine.substring(with: NSRange(location: index, length: 1))
        if character != " " && character != "\t" { break }
        index += 1
    }

    let content = nsLine.substring(from: index)
    if content.hasPrefix("#") {
        var hashCount = 0
        let contentNSString = content as NSString
        while hashCount < contentNSString.length,
              hashCount < 6,
              contentNSString.substring(with: NSRange(location: hashCount, length: 1)) == "#" {
            hashCount += 1
        }
        if hashCount > 0,
           hashCount < contentNSString.length,
           contentNSString.substring(with: NSRange(location: hashCount, length: 1)) == " " {
            return index + hashCount + 1
        }
    }

    for marker in ["- ", "* ", "+ "] where content.hasPrefix(marker) {
        return index + (marker as NSString).length
    }

    if let range = content.range(
        of: #"^.*?\d+\.\s+"#,
        options: .regularExpression
    ) {
        return index + (String(content[..<range.upperBound]) as NSString).length
    }

    return 0
}

// MARK: - TOC标题模型 - v1 - 存储目录标题层级与定位偏移
struct MarkdownHeading: Identifiable, Hashable {
    let level: Int
    let title: String
    let utf16Offset: Int

    var id: String { "\(level)-\(utf16Offset)-\(title)" }
}

// MARK: - 文档样式角色 - v1 - 定义标题正文注释的样式分类
enum MarkdownStyleRole: String, CaseIterable, Identifiable {
    case h1 = "H1"
    case h2 = "H2"
    case h3 = "H3"
    case h4 = "H4"
    case h5 = "H5"
    case h6 = "H6"
    case body = "正文"
    case comment = "注释"

    var id: String { rawValue }
}

// MARK: - 语义颜色枚举 - v1 - 定义可持久化的自适应黑白颜色语义
enum MarkdownSemanticColor: String, Codable, Hashable {
    case adaptiveBlackWhite

    var color: Color {
        switch self {
        case .adaptiveBlackWhite:
            return .primary
        }
    }
}

// MARK: - 角色样式模型 - v2 - 存储角色字体大小与可持久化语义颜色配置
struct MarkdownRoleStyle: Hashable {
    var fontName: String
    var fontSize: Double
    var color: Color
    var semanticColor: MarkdownSemanticColor?

    var renderedColor: Color {
        semanticColor?.color ?? color
    }
}

// MARK: - 文档样式配置 - v5 - 聚合H1-H6正文注释并应用43号源码模式统一规则基线
struct MarkdownDocumentStyle: Hashable {
    var h1 = MarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 30, color: markdownHexColor(0x26619C), semanticColor: nil)
    var h2 = MarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 26, color: markdownHexColor(0x1C39BB), semanticColor: nil)
    var h3 = MarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 22, color: markdownHexColor(0x50C878), semanticColor: nil)
    var h4 = MarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 20, color: markdownHexColor(0x702963), semanticColor: nil)
    var h5 = MarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 18, color: markdownHexColor(0xC41E3A), semanticColor: nil)
    var h6 = MarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 16, color: .primary, semanticColor: .adaptiveBlackWhite)
    var body = MarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 15, color: .primary, semanticColor: .adaptiveBlackWhite)
    var comment = MarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 14, color: .secondary, semanticColor: nil)

    mutating func update(_ style: MarkdownRoleStyle, for role: MarkdownStyleRole) {
        switch role {
        case .h1: h1 = style
        case .h2: h2 = style
        case .h3: h3 = style
        case .h4: h4 = style
        case .h5: h5 = style
        case .h6: h6 = style
        case .body: body = style
        case .comment: comment = style
        }
    }

    func style(for role: MarkdownStyleRole) -> MarkdownRoleStyle {
        switch role {
        case .h1: h1
        case .h2: h2
        case .h3: h3
        case .h4: h4
        case .h5: h5
        case .h6: h6
        case .body: body
        case .comment: comment
        }
    }

    func headingStyle(level: Int) -> MarkdownRoleStyle {
        switch level {
        case 1: h1
        case 2: h2
        case 3: h3
        case 4: h4
        case 5: h5
        default: h6
        }
    }
}

// MARK: - 源码模式样式 - v2 - 统一源码模式标题为紫色等宽并与正文同字号
extension MarkdownDocumentStyle {
    static var sourceStandard: MarkdownDocumentStyle {
        let baseSize = 15.0
        let headingColor = markdownHexColor(0x702963)
        return MarkdownDocumentStyle(
            h1: MarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: baseSize, color: headingColor, semanticColor: nil),
            h2: MarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: baseSize, color: headingColor, semanticColor: nil),
            h3: MarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: baseSize, color: headingColor, semanticColor: nil),
            h4: MarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: baseSize, color: headingColor, semanticColor: nil),
            h5: MarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: baseSize, color: headingColor, semanticColor: nil),
            h6: MarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: baseSize, color: headingColor, semanticColor: nil),
            body: MarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: baseSize, color: .primary, semanticColor: .adaptiveBlackWhite),
            comment: MarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: baseSize, color: .secondary, semanticColor: nil)
        )
    }
}

// MARK: - 调色板模型 - v1 - 定义文档样式中的固定12色与自适应黑白入口
struct MarkdownPaletteItem: Hashable, Identifiable {
    let id: String
    let title: String
    let color: Color
    let semanticColor: MarkdownSemanticColor?
}

// MARK: - 预设调色板 - v1 - 返回编辑器样式设置使用的12个固定颜色项
func markdownPresetPalette() -> [MarkdownPaletteItem] {
    [
        MarkdownPaletteItem(id: "adaptive-bw", title: "黑/白", color: .primary, semanticColor: .adaptiveBlackWhite),
        MarkdownPaletteItem(id: "carmine-red", title: "胭脂红", color: markdownHexColor(0xC41E3A), semanticColor: nil),
        MarkdownPaletteItem(id: "lapis-blue", title: "青金石蓝", color: markdownHexColor(0x26619C), semanticColor: nil),
        MarkdownPaletteItem(id: "emerald", title: "祖母绿", color: markdownHexColor(0x50C878), semanticColor: nil),
        MarkdownPaletteItem(id: "old-gold", title: "陈金色", color: markdownHexColor(0xCFB53B), semanticColor: nil),
        MarkdownPaletteItem(id: "byzantium-purple", title: "拜占庭紫", color: markdownHexColor(0x702963), semanticColor: nil),
        MarkdownPaletteItem(id: "persian-blue", title: "波斯蓝", color: markdownHexColor(0x1C39BB), semanticColor: nil),
        MarkdownPaletteItem(id: "amber-orange", title: "琥珀橙", color: markdownHexColor(0xFF7E00), semanticColor: nil),
        MarkdownPaletteItem(id: "malachite-green", title: "孔雀石绿", color: markdownHexColor(0x088F8F), semanticColor: nil),
        MarkdownPaletteItem(id: "merlot-wine", title: "梅洛酒红", color: markdownHexColor(0x73262D), semanticColor: nil),
        MarkdownPaletteItem(id: "ochre", title: "赭石色", color: markdownHexColor(0xCC7722), semanticColor: nil),
        MarkdownPaletteItem(id: "slate-cyan", title: "石板青", color: markdownHexColor(0x6A5ACD), semanticColor: nil)
    ]
}

func markdownHexColor(_ hex: UInt32) -> Color {
    let red = Double((hex >> 16) & 0xFF) / 255.0
    let green = Double((hex >> 8) & 0xFF) / 255.0
    let blue = Double(hex & 0xFF) / 255.0
    return Color(red: red, green: green, blue: blue)
}

// MARK: - 颜色编码模型 - v2 - 提供普通色与语义色的轻量序列化能力
struct MarkdownColorRecord: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
    var semanticColor: MarkdownSemanticColor?

    init(color: Color, semanticColor: MarkdownSemanticColor?) {
        self.semanticColor = semanticColor
        #if os(macOS)
        let nsColor = NSColor((semanticColor?.color ?? color)).usingColorSpace(.sRGB) ?? NSColor.white
        red = Double(nsColor.redComponent)
        green = Double(nsColor.greenComponent)
        blue = Double(nsColor.blueComponent)
        alpha = Double(nsColor.alphaComponent)
        #elseif os(iOS)
        let uiColor = UIColor(semanticColor?.color ?? color)
        var r: CGFloat = 1
        var g: CGFloat = 1
        var b: CGFloat = 1
        var a: CGFloat = 1
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        red = Double(r)
        green = Double(g)
        blue = Double(b)
        alpha = Double(a)
        #endif
    }

    var styleColor: (Color, MarkdownSemanticColor?) {
        if let semanticColor {
            return (semanticColor.color, semanticColor)
        }
        return (Color(red: red, green: green, blue: blue, opacity: alpha), nil)
    }
}

// MARK: - 角色样式存储模型 - v1 - 为角色样式提供JSON持久化结构
struct MarkdownRoleStyleRecord: Codable, Hashable {
    var fontName: String
    var fontSize: Double
    var color: MarkdownColorRecord

    init(style: MarkdownRoleStyle) {
        fontName = style.fontName
        fontSize = style.fontSize
        color = MarkdownColorRecord(color: style.color, semanticColor: style.semanticColor)
    }

    var style: MarkdownRoleStyle {
        let resolved = color.styleColor
        return MarkdownRoleStyle(fontName: fontName, fontSize: fontSize, color: resolved.0, semanticColor: resolved.1)
    }
}

// MARK: - 文档样式存储模型 - v1 - 定义Markdown文档样式配置文件格式
struct MarkdownDocumentStyleRecord: Codable, Hashable {
    var h1: MarkdownRoleStyleRecord
    var h2: MarkdownRoleStyleRecord
    var h3: MarkdownRoleStyleRecord
    var h4: MarkdownRoleStyleRecord
    var h5: MarkdownRoleStyleRecord
    var h6: MarkdownRoleStyleRecord
    var body: MarkdownRoleStyleRecord
    var comment: MarkdownRoleStyleRecord

    init(style: MarkdownDocumentStyle) {
        h1 = MarkdownRoleStyleRecord(style: style.h1)
        h2 = MarkdownRoleStyleRecord(style: style.h2)
        h3 = MarkdownRoleStyleRecord(style: style.h3)
        h4 = MarkdownRoleStyleRecord(style: style.h4)
        h5 = MarkdownRoleStyleRecord(style: style.h5)
        h6 = MarkdownRoleStyleRecord(style: style.h6)
        body = MarkdownRoleStyleRecord(style: style.body)
        comment = MarkdownRoleStyleRecord(style: style.comment)
    }

    var style: MarkdownDocumentStyle {
        var value = MarkdownDocumentStyle()
        value.h1 = h1.style
        value.h2 = h2.style
        value.h3 = h3.style
        value.h4 = h4.style
        value.h5 = h5.style
        value.h6 = h6.style
        value.body = body.style
        value.comment = comment.style
        return value
    }
}

// MARK: - 快捷输入单目规则 - v1 - 定义单触发替换规则
struct MarkdownSingleShortcutRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var trigger: String
    var replacement: String
}

// MARK: - 快捷输入双目规则 - v1 - 定义开闭触发替换规则
struct MarkdownPairShortcutRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var openTrigger: String
    var closeTrigger: String
    var openReplacement: String
    var closeReplacement: String
}

// MARK: - 快捷输入配置 - v1 - 聚合单目与双目快捷替换规则
struct MarkdownQuickInputSettings: Codable, Hashable {
    var singleRules: [MarkdownSingleShortcutRule] = []
    var pairRules: [MarkdownPairShortcutRule] = []
}

// MARK: - 快捷输入编辑模式 - v1 - 区分快捷输入弹窗中的单目和双目录入
enum MarkdownShortcutEntryMode: String, CaseIterable, Identifiable {
    case pair = "双目"
    case single = "单目"

    var id: String { rawValue }
}

// MARK: - Markdown设置存储 - v1 - 管理文档样式与快捷输入配置文件读写
enum MarkdownSettingsStore {
    private static let markdownStyleFilePrefix = "setting-Markdown文档设置"
    private static let quickInputFileName = "setting-快捷输入.json"

    static func loadDocumentStyle() -> MarkdownDocumentStyle? {
        guard let url = try? markdownDocumentStyleURL() else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let record = try? JSONDecoder().decode(MarkdownDocumentStyleRecord.self, from: data) else { return nil }
        return record.style
    }

    static func saveDocumentStyle(_ style: MarkdownDocumentStyle) {
        guard let url = try? markdownDocumentStyleURL() else { return }
        guard let data = try? JSONEncoder().encode(MarkdownDocumentStyleRecord(style: style)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadQuickInputSettings() -> MarkdownQuickInputSettings? {
        guard let url = try? quickInputSettingsURL() else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MarkdownQuickInputSettings.self, from: data)
    }

    static func saveQuickInputSettings(_ settings: MarkdownQuickInputSettings) {
        guard let url = try? quickInputSettingsURL() else { return }
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func markdownDocumentStyleURL() throws -> URL {
        let settingsFolder = try settingsFolderURL()
        let fileName = "\(markdownStyleFilePrefix)-\(sanitizedDeviceIdentifier()).json"
        return settingsFolder.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func quickInputSettingsURL() throws -> URL {
        let settingsFolder = try settingsFolderURL()
        return settingsFolder.appendingPathComponent(quickInputFileName, isDirectory: false)
    }

    private static func settingsFolderURL(fileManager: FileManager = .default) throws -> URL {
        let documentsRoot = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let settingsFolder = documentsRoot.appendingPathComponent(ArchiveStorage.settingsFolderName, isDirectory: true)
        try fileManager.createDirectory(at: settingsFolder, withIntermediateDirectories: true)
        return settingsFolder
    }

    private static func sanitizedDeviceIdentifier() -> String {
        #if os(macOS)
        let rawName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #elseif os(iOS)
        let rawName = UIDevice.current.name
        #endif
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let components = rawName.components(separatedBy: invalid).filter { !$0.isEmpty }
        return components.joined(separator: "_")
    }
}

// MARK: - Markdown设置共享中心 - v1 - 提供跨窗口同步的文档样式与快捷输入状态
@MainActor
final class MarkdownEditorSettingsCenter: ObservableObject {
    static let shared = MarkdownEditorSettingsCenter()

    @Published private(set) var documentStyle: MarkdownDocumentStyle
    @Published private(set) var quickInputSettings: MarkdownQuickInputSettings

    private var didBootstrap = false

    private init() {
        documentStyle = MarkdownSettingsStore.loadDocumentStyle() ?? MarkdownDocumentStyle()
        quickInputSettings = MarkdownSettingsStore.loadQuickInputSettings() ?? MarkdownQuickInputSettings()
        didBootstrap = true
    }

    func updateDocumentStyle(_ newValue: MarkdownDocumentStyle) {
        guard documentStyle != newValue else { return }
        documentStyle = newValue
        if didBootstrap {
            MarkdownSettingsStore.saveDocumentStyle(newValue)
        }
    }

    func updateQuickInputSettings(_ newValue: MarkdownQuickInputSettings) {
        guard quickInputSettings != newValue else { return }
        quickInputSettings = newValue
        if didBootstrap {
            MarkdownSettingsStore.saveQuickInputSettings(newValue)
        }
    }
}

// MARK: - Markdown字体目录 - v1 - 全局缓存字体列表并支持后台预热
@MainActor
final class MarkdownFontCatalog: ObservableObject {
    static let shared = MarkdownFontCatalog()

    @Published private(set) var fontOptions: [MarkdownFontOption] = [
        MarkdownFontOption(postScriptName: appleSystemMonospacedFontName, displayName: "Apple 系统等宽", isChinese: false)
    ]

    private var hasLoaded = false
    private var isLoading = false

    private init() {}

    func prewarmIfNeeded() {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true

        Task.detached(priority: .utility) {
            let resolved = MarkdownFontResolver.resolveOptions()
            await MainActor.run {
                self.fontOptions = resolved
                self.hasLoaded = true
                self.isLoading = false
            }
        }
    }
}

// MARK: - 字体选项模型 - v1 - 存储字体名显示名与是否中文字体标记
struct MarkdownFontOption: Hashable, Identifiable {
    let postScriptName: String
    let displayName: String
    let isChinese: Bool

    var id: String { postScriptName }
}

// MARK: - 字体清单工具 - v2 - 拉取系统字体并为中文字体输出中文显示名
func markdownAvailableFontOptions() -> [MarkdownFontOption] {
    MarkdownFontResolver.resolveOptions()
}

func markdownLocalizedFontDisplayName(postScriptName: String) -> String {
    MarkdownFontResolver.localizedDisplayName(for: postScriptName)
}

func markdownContainsChinese(_ value: String) -> Bool {
    MarkdownFontResolver.containsChinese(value)
}

enum MarkdownFontResolver {
    nonisolated static let monospacedName = "Apple System Monospaced"

    nonisolated static func resolveOptions() -> [MarkdownFontOption] {
        var options: [MarkdownFontOption] = [
            MarkdownFontOption(postScriptName: monospacedName, displayName: "Apple 系统等宽", isChinese: false)
        ]

        let postScriptNames = (CTFontManagerCopyAvailablePostScriptNames() as? [String]) ?? []
        for postScript in postScriptNames {
            let display = localizedDisplayName(for: postScript)
            let chinese = containsChinese(display)
            options.append(MarkdownFontOption(postScriptName: postScript, displayName: display, isChinese: chinese))
        }

        let deduplicated = Dictionary(grouping: options, by: \.postScriptName).compactMap { $0.value.first }
        return deduplicated.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    nonisolated static func localizedDisplayName(for postScriptName: String) -> String {
        if postScriptName == monospacedName {
            return "Apple 系统等宽"
        }
        let ctFont = CTFontCreateWithName(postScriptName as CFString, 14, nil)
        if let localized = CTFontCopyLocalizedName(ctFont, kCTFontFamilyNameKey, nil) as String? {
            return localized
        }
        if let localized = CTFontCopyLocalizedName(ctFont, kCTFontFullNameKey, nil) as String? {
            return localized
        }
        return postScriptName
    }

    nonisolated static func containsChinese(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
        }
    }
}

// MARK: - Markdown编辑器主页面 - v14 - 增强搜索命中高亮与右侧浮窗结果导航
struct MarkdownEditorView: View {
    let fileURL: URL
    private static let renderModeDefaultsKey = "MarkdownEditor.lastRenderMode"

    @Environment(\.dismiss) private var dismiss
    @State private var markdownText = ""
    @State private var lastSavedText = ""
    @State private var saveState: MarkdownSaveState = .clean
    @State private var pendingAutoSaveWorkItem: DispatchWorkItem?
    @State private var lastKnownFileModificationDate: Date?
    @State private var showExternalChangeDialog = false
    @State private var pendingSaveAfterExternalChangeChoice = false

    @State private var renderMode: MarkdownRenderMode = .dual
    @State private var preferredScheme: ColorScheme?

    @State private var searchText = ""
    @State private var committedSearchText = ""
    @State private var showSearchPopover = false
    @State private var searchResults: [MarkdownSearchResult] = []
    @State private var activeSearchResultIndex: Int?
    @State private var pendingSearchResultsWorkItem: DispatchWorkItem?

    @State private var showTOCPopover = false
    @State private var tocMaxLevel = 3

    @State private var targetUTF16Offset: Int?

    @State private var showStyleSheet = false
    @State private var showQuickInputSheet = false
    @State private var showExportActionDialog = false
    @State private var pendingExportFormat: MarkdownExportFormat = .pdf
    @State private var documentStyleRefreshToken = 0

    @ObservedObject private var settingsCenter = MarkdownEditorSettingsCenter.shared
    @ObservedObject private var fontCatalog = MarkdownFontCatalog.shared

    init(fileURL: URL) {
        self.fileURL = fileURL
        _renderMode = State(initialValue: Self.restoredRenderMode())
    }

    var body: some View {
        Group {
            ZStack(alignment: .topTrailing) {
                switch renderMode {
                case .dual:
                    MarkdownDualRenderModeView(
                        markdownText: $markdownText,
                        targetUTF16Offset: $targetUTF16Offset,
                        preferredScheme: preferredScheme,
                        workingDirectoryURL: fileURL.deletingLastPathComponent(),
                        documentStyle: documentStyle,
                        quickInputSettings: quickInputSettings,
                        searchQuery: searchQuery,
                        activeSearchRange: activeSearchRange
                    )
                case .instant:
                    MarkdownInstantRenderModeView(
                        markdownText: $markdownText,
                        targetUTF16Offset: $targetUTF16Offset,
                        preferredScheme: preferredScheme,
                        workingDirectoryURL: fileURL.deletingLastPathComponent(),
                        documentStyle: documentStyle,
                        quickInputSettings: quickInputSettings,
                        searchQuery: searchQuery,
                        activeSearchRange: activeSearchRange
                    )
                case .source:
                    MarkdownSourceModeView(
                        markdownText: $markdownText,
                        targetUTF16Offset: $targetUTF16Offset,
                        preferredScheme: preferredScheme,
                        workingDirectoryURL: fileURL.deletingLastPathComponent(),
                        documentStyle: documentStyle,
                        quickInputSettings: quickInputSettings,
                        searchQuery: searchQuery,
                        activeSearchRange: activeSearchRange
                    )
                case .textKit2Plain:
                    MarkdownTextKit2PlainModeView(
                        markdownText: $markdownText,
                        targetUTF16Offset: $targetUTF16Offset,
                        preferredScheme: preferredScheme,
                        workingDirectoryURL: fileURL.deletingLastPathComponent(),
                        documentStyle: documentStyle,
                        quickInputSettings: quickInputSettings,
                        searchQuery: searchQuery,
                        activeSearchRange: activeSearchRange
                    )
                case .web:
                    MarkdownWebRenderModeView(
                        markdownText: markdownText,
                        preferredScheme: preferredScheme,
                        documentStyle: documentStyle
                    )
                }

                if shouldShowSearchFloatingPanel {
                    MarkdownSearchFloatingPanelView(
                        query: searchQuery,
                        results: searchResults,
                        activeIndex: activeSearchResultIndex,
                        onSelect: { index in
                            selectSearchResult(at: index)
                        },
                        onClose: {
                            clearSearchState()
                            showSearchPopover = false
                        }
                    )
                    .padding(.trailing, 10)
                    .padding(.top, 10)
                }
            }
            .id("markdown-display-\(renderMode.rawValue)-\(documentStyleRefreshToken)")
        }
        .navigationTitle(windowTitle)
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .cancellationAction) {
                Button("返回") {
                    dismiss()
                }
            }
            #endif
            ToolbarItemGroup(placement: .primaryAction) {
                searchButton
                colorSchemeButton
                styleButton
                tocButton
                modeMenu
                exportMenu
                saveButton
            }
        }
        .preferredColorScheme(preferredScheme)
        .task { loadFile() }
        .task { fontCatalog.prewarmIfNeeded() }
        .onDisappear {
            pendingSearchResultsWorkItem?.cancel()
            pendingSearchResultsWorkItem = nil
            pendingAutoSaveWorkItem?.cancel()
            pendingAutoSaveWorkItem = nil
            saveBeforeClosing()
        }
        .onChange(of: markdownText) { _, newValue in
            let profileStart = MarkdownEditorPerformanceProbe.start()
            if newValue != lastSavedText {
                if saveState != .saving {
                    saveState = .dirty
                }
            } else if saveState != .saving {
                saveState = .clean
            }
            scheduleAutoSave()
            scheduleSearchResultsRebuild(delay: 0.22)
            MarkdownEditorPerformanceProbe.end(
                "MarkdownEditorView.onChange(markdownText)",
                start: profileStart,
                details: MarkdownEditorPerformanceProbe.textDetails(newValue)
            )
        }
        .onChange(of: renderMode) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.renderModeDefaultsKey)
        }
        .onChange(of: settingsCenter.documentStyle) { _, _ in
            documentStyleRefreshToken &+= 1
        }
        .sheet(isPresented: $showStyleSheet) {
            MarkdownStyleSettingsView(
                documentStyle: documentStyleBinding,
                fontOptions: fontCatalog.fontOptions
            ) {
                showStyleSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    showQuickInputSheet = true
                }
            }
            .markdownAdaptiveSheetSize(width: 760, height: 700)
        }
        .sheet(isPresented: $showQuickInputSheet) {
            MarkdownQuickInputSettingsView(
                settings: quickInputSettingsBinding,
                onFinish: { showQuickInputSheet = false }
            )
            .markdownAdaptiveSheetSize(width: 520, height: 460)
        }
        .confirmationDialog("选择导出方式", isPresented: $showExportActionDialog, titleVisibility: .visible) {
            Button("导出到微信") {
                exportToWeChat(format: pendingExportFormat)
            }
            Button("保存到文件") {
                exportToFiles(format: pendingExportFormat)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前格式：\(pendingExportFormat.rawValue)")
        }
        .alert("文件已在外部修改", isPresented: $showExternalChangeDialog) {
            Button("重新载入") {
                pendingSaveAfterExternalChangeChoice = false
                loadFile()
            }
            Button("保留当前内容并覆盖") {
                let shouldSave = pendingSaveAfterExternalChangeChoice
                pendingSaveAfterExternalChangeChoice = false
                refreshKnownModificationDate()
                if shouldSave {
                    saveFile(allowExternalOverwrite: true)
                }
            }
            Button("取消", role: .cancel) {
                pendingSaveAfterExternalChangeChoice = false
            }
        } message: {
            Text("磁盘上的文件比当前编辑器最后保存的版本更新。请选择重新载入，或用当前内容覆盖磁盘文件。")
        }
        #if os(macOS)
        .background(WindowTitleSetter(title: windowTitle).frame(width: 0, height: 0))
        #endif
    }

    private var windowTitle: String {
        "Markdown-\(fileURL.lastPathComponent)"
    }

    private static func restoredRenderMode() -> MarkdownRenderMode {
        guard let rawValue = UserDefaults.standard.string(forKey: renderModeDefaultsKey),
              let mode = MarkdownRenderMode(rawValue: rawValue),
              MarkdownRenderMode.visibleCases.contains(mode) else {
            return .dual
        }
        return mode
    }

    private var documentStyle: MarkdownDocumentStyle {
        settingsCenter.documentStyle
    }

    private var quickInputSettings: MarkdownQuickInputSettings {
        settingsCenter.quickInputSettings
    }

    private var documentStyleBinding: Binding<MarkdownDocumentStyle> {
        Binding(
            get: { settingsCenter.documentStyle },
            set: { settingsCenter.updateDocumentStyle($0) }
        )
    }

    private var quickInputSettingsBinding: Binding<MarkdownQuickInputSettings> {
        Binding(
            get: { settingsCenter.quickInputSettings },
            set: { settingsCenter.updateQuickInputSettings($0) }
        )
    }

    private var hasUnsavedChanges: Bool {
        markdownText != lastSavedText
    }

    private var headings: [MarkdownHeading] {
        parseHeadings(from: markdownText, maxLevel: tocMaxLevel)
    }

    private var searchButton: some View {
        Button {
            if showSearchPopover {
                showSearchPopover = false
            } else {
                showSearchPopover = true
            }
        } label: {
            Image(systemName: "magnifyingglass")
        }
        .appGlassButtonStyle()
        .help("搜索")
        .keyboardShortcut("f", modifiers: .command)
        .popover(isPresented: $showSearchPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("搜索")
                    .font(.headline)
                TextField("输入关键词", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        performSearch()
                    }
                Text("共 \(searchResults.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        findPrevious()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .appGlassButtonStyle()
                    .disabled(searchResults.isEmpty)
                    .help("上一个")
                    Button {
                        findNext()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .appGlassButtonStyle()
                    .disabled(searchResults.isEmpty)
                    .help("下一个")
                    Spacer()
                    Button {
                        performSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    .appGlassButtonStyle(.prominent)
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("搜索")
                }
            }
            .padding(12)
            .frame(width: 240)
        }
    }

    private var colorSchemeButton: some View {
        Button {
            toggleColorScheme()
        } label: {
            Image(systemName: preferredScheme == .dark ? "moon.stars.fill" : "sun.max.fill")
        }
        .appGlassButtonStyle()
        .help("深浅切换")
    }

    private var styleButton: some View {
        Button {
            showStyleSheet = true
        } label: {
            Image(systemName: "textformat")
        }
        .appGlassButtonStyle()
        .help("文档样式")
    }

    private var tocButton: some View {
        Button {
            showTOCPopover = true
        } label: {
            Image(systemName: "list.bullet.indent")
        }
        .appGlassButtonStyle()
        .help("TOC面板")
        .popover(isPresented: $showTOCPopover, arrowEdge: .bottom) {
            MarkdownTOCPanelView(
                headings: headings,
                maxLevel: $tocMaxLevel
            ) { selected in
                targetUTF16Offset = selected.utf16Offset
                showTOCPopover = false
            }
            .frame(width: 280, height: 380)
            .padding(12)
        }
    }

    private var modeMenu: some View {
        Menu {
            ForEach(MarkdownRenderMode.visibleCases) { mode in
                Button {
                    renderMode = mode
                } label: {
                    HStack {
                        Text(mode.rawValue)
                        if renderMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "rectangle.split.3x1")
        }
        .appGlassControlChrome()
        .help("渲染模式")
    }

    private var exportMenu: some View {
        Menu {
            Button("导出为PDF") { beginExport(format: .pdf) }
            Button("导出为HTML") { beginExport(format: .html) }
            Button("导出为MD") { beginExport(format: .markdown) }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .appGlassControlChrome(.prominent)
        .help("导出")
    }

    private var saveButton: some View {
        Button {
            saveFile()
        } label: {
            Image(systemName: saveIconName)
        }
        .appGlassButtonStyle(.prominent)
        .help("保存")
        .keyboardShortcut("s", modifiers: .command)
    }

    private var saveIconName: String {
        switch saveState {
        case .clean:
            return "checkmark.circle.fill"
        case .dirty:
            return "square.and.arrow.down"
        case .saving:
            return "arrow.down.circle"
        case .failed:
            return "exclamationmark.circle.fill"
        }
    }

    private func loadFile() {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        do {
            let text = try withFileAccess {
                try String(contentsOf: fileURL, encoding: .utf8)
            }
            markdownText = text
            lastSavedText = text
            lastKnownFileModificationDate = fileModificationDate()
            saveState = .clean
            MarkdownEditorPerformanceProbe.end(
                "MarkdownEditorView.loadFile",
                start: profileStart,
                details: MarkdownEditorPerformanceProbe.textDetails(text)
            )
        } catch {
            markdownText = ""
            lastSavedText = ""
            saveState = .failed
            MarkdownEditorPerformanceProbe.end(
                "MarkdownEditorView.loadFile.failed",
                start: profileStart,
                details: error.localizedDescription
            )
        }
    }

    private func saveFile(allowExternalOverwrite: Bool = false) {
        pendingAutoSaveWorkItem?.cancel()
        pendingAutoSaveWorkItem = nil
        performSave(allowExternalOverwrite: allowExternalOverwrite, promptOnExternalChange: true)
    }

    private func saveSilently() {
        guard hasUnsavedChanges else { return }
        performSave(allowExternalOverwrite: false, promptOnExternalChange: false)
    }

    private func saveBeforeClosing() {
        pendingAutoSaveWorkItem?.cancel()
        pendingAutoSaveWorkItem = nil
        guard hasUnsavedChanges else { return }
        performSave(allowExternalOverwrite: false, promptOnExternalChange: true)
    }

    private func scheduleAutoSave() {
        pendingAutoSaveWorkItem?.cancel()
        guard hasUnsavedChanges else {
            pendingAutoSaveWorkItem = nil
            return
        }
        let workItem = DispatchWorkItem {
            saveSilently()
        }
        pendingAutoSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    private func writeCurrentMarkdownText() throws {
        try withFileAccess {
            try markdownText.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private func performSave(allowExternalOverwrite: Bool, promptOnExternalChange: Bool) {
        guard hasUnsavedChanges else { return }
        if !allowExternalOverwrite, fileWasModifiedExternally() {
            saveState = .failed
            pendingAutoSaveWorkItem?.cancel()
            pendingAutoSaveWorkItem = nil
            if promptOnExternalChange {
                pendingSaveAfterExternalChangeChoice = true
                showExternalChangeDialog = true
            }
            return
        }
        saveState = .saving
        do {
            try writeCurrentMarkdownText()
            lastSavedText = markdownText
            lastKnownFileModificationDate = fileModificationDate()
            saveState = .clean
        } catch {
            saveState = .failed
        }
    }

    private func fileWasModifiedExternally() -> Bool {
        guard let known = lastKnownFileModificationDate,
              let current = fileModificationDate() else {
            return false
        }
        return current.timeIntervalSince(known) > 0.5
    }

    private func fileModificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date
    }

    private func refreshKnownModificationDate() {
        lastKnownFileModificationDate = fileModificationDate()
    }

    private func withFileAccess<T>(_ work: () throws -> T) throws -> T {
        #if os(macOS) || os(iOS)
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        #endif
        return try work()
    }

    private func toggleColorScheme() {
        if preferredScheme == .light {
            preferredScheme = .dark
        } else {
            preferredScheme = .light
        }
    }

    private func findNext() {
        guard !searchResults.isEmpty else { return }
        let nextIndex: Int
        if let activeSearchResultIndex {
            nextIndex = (activeSearchResultIndex + 1) % searchResults.count
        } else {
            nextIndex = 0
        }
        selectSearchResult(at: nextIndex)
    }

    private func findPrevious() {
        guard !searchResults.isEmpty else { return }
        let previousIndex: Int
        if let activeSearchResultIndex {
            previousIndex = (activeSearchResultIndex - 1 + searchResults.count) % searchResults.count
        } else {
            previousIndex = max(0, searchResults.count - 1)
        }
        selectSearchResult(at: previousIndex)
    }

    private var searchQuery: String {
        committedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeSearchRange: NSRange? {
        guard let activeSearchResultIndex, searchResults.indices.contains(activeSearchResultIndex) else { return nil }
        return searchResults[activeSearchResultIndex].range
    }

    private var shouldShowSearchFloatingPanel: Bool {
        renderMode != .web && !searchResults.isEmpty
    }

    private func selectSearchResult(at index: Int) {
        guard searchResults.indices.contains(index) else { return }
        activeSearchResultIndex = index
        targetUTF16Offset = searchResults[index].range.location
    }

    private func performSearch() {
        committedSearchText = searchText
        rebuildSearchResults()
    }

    private func rebuildSearchResults() {
        pendingSearchResultsWorkItem?.cancel()
        pendingSearchResultsWorkItem = nil
        let profileStart = MarkdownEditorPerformanceProbe.start()
        let query = searchQuery
        guard !query.isEmpty else {
            searchResults = []
            activeSearchResultIndex = nil
            MarkdownEditorPerformanceProbe.end(
                "MarkdownEditorView.rebuildSearchResults.empty",
                start: profileStart,
                details: MarkdownEditorPerformanceProbe.textDetails(markdownText)
            )
            return
        }

        let previousLocation: Int? = {
            guard let activeSearchResultIndex, searchResults.indices.contains(activeSearchResultIndex) else { return nil }
            return searchResults[activeSearchResultIndex].range.location
        }()

        searchResults = markdownBuildSearchResults(in: markdownText, query: query)
        MarkdownEditorPerformanceProbe.end(
            "MarkdownEditorView.rebuildSearchResults",
            start: profileStart,
            details: "queryLength=\((query as NSString).length),matches=\(searchResults.count),\(MarkdownEditorPerformanceProbe.textDetails(markdownText))"
        )

        guard !searchResults.isEmpty else {
            activeSearchResultIndex = nil
            return
        }

        if let previousLocation,
           let index = searchResults.firstIndex(where: { $0.range.location >= previousLocation }) {
            activeSearchResultIndex = index
        } else {
            activeSearchResultIndex = 0
        }
    }

    private func scheduleSearchResultsRebuild(delay: TimeInterval) {
        pendingSearchResultsWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            rebuildSearchResults()
        }
        pendingSearchResultsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func clearSearchState() {
        pendingSearchResultsWorkItem?.cancel()
        pendingSearchResultsWorkItem = nil
        searchText = ""
        committedSearchText = ""
        searchResults = []
        activeSearchResultIndex = nil
        targetUTF16Offset = nil
    }

    private func parseHeadings(from source: String, maxLevel: Int) -> [MarkdownHeading] {
        var result: [MarkdownHeading] = []
        var offset = 0

        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineString = String(line)
            let level = headingLevel(for: lineString)
            if level > 0, level <= maxLevel {
                let title = lineString.dropFirst(level).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    result.append(MarkdownHeading(level: level, title: title, utf16Offset: offset))
                }
            }
            offset += (lineString as NSString).length + 1
        }

        return result
    }

    private func headingLevel(for line: String) -> Int {
        var level = 0
        for char in line {
            if char == "#" {
                level += 1
            } else {
                break
            }
        }
        if level == 0 || level > 6 {
            return 0
        }

        let index = line.index(line.startIndex, offsetBy: level)
        return index < line.endIndex && line[index] == " " ? level : 0
    }

    @MainActor
    private func beginExport(format: MarkdownExportFormat) {
        pendingExportFormat = format
        exportToFiles(format: format)
    }

    @MainActor
    private func exportToWeChat(format: MarkdownExportFormat) {
        do {
            try TeachingDocumentExportService.exportToWeChat(
                sourceFileURL: fileURL,
                descriptor: format.exportDescriptor
            ) {
                try renderExportData(format: format)
            }
        } catch {
            saveState = .failed
        }
    }

    @MainActor
    private func exportToFiles(format: MarkdownExportFormat) {
        do {
            try TeachingDocumentExportService.saveToFile(
                sourceFileURL: fileURL,
                descriptor: format.exportDescriptor
            ) {
                try renderExportData(format: format)
            }
        } catch {
            saveState = .failed
        }
    }

    @MainActor
    private func renderExportData(format: MarkdownExportFormat) throws -> Data {
        try MarkdownExportRenderer.renderData(
            format: format,
            source: markdownText,
            style: documentStyle,
            preferredScheme: preferredScheme,
            baseURL: fileURL.deletingLastPathComponent()
        )
    }
}

// MARK: - 文档样式设置页 - v4 - 使用延迟字体选择器避免首屏加载超大字体菜单
struct MarkdownStyleSettingsView: View {
    @Binding var documentStyle: MarkdownDocumentStyle
    let fontOptions: [MarkdownFontOption]
    let onOpenQuickInput: () -> Void
    @State private var activeFontRole: MarkdownStyleRole?
    @State private var activeColorRole: MarkdownStyleRole?

    private let paletteItems = markdownPresetPalette()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(MarkdownStyleRole.allCases) { role in
                        MarkdownStyleRowView(
                            role: role,
                            style: Binding(
                                get: { documentStyle.style(for: role) },
                                set: { documentStyle.update($0, for: role) }
                            ),
                            fontOptions: fontOptions,
                            paletteItems: paletteItems,
                            onTapFont: {
                                activeFontRole = role
                            },
                            onTapCustomColor: {
                                activeColorRole = role
                            }
                        )
                        Divider()
                    }

                    Button {
                        onOpenQuickInput()
                    } label: {
                        Image(systemName: "bolt.circle")
                    }
                    .appGlassButtonStyle(.prominent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .help("快捷输入设置")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("文档样式")
        }
        .sheet(item: $activeFontRole) { role in
            MarkdownFontSelectorView(
                title: "\(role.rawValue) 字体",
                fontOptions: fontOptions,
                selectedFontName: Binding(
                    get: { documentStyle.style(for: role).fontName },
                    set: { newFont in
                        var current = documentStyle.style(for: role)
                        current.fontName = newFont
                        documentStyle.update(current, for: role)
                    }
                )
            )
        }
        .sheet(item: $activeColorRole) { role in
            MarkdownRoleCustomColorSheet(
                roleTitle: role.rawValue,
                selectedColor: Binding(
                    get: { documentStyle.style(for: role).renderedColor },
                    set: { value in
                        var current = documentStyle.style(for: role)
                        current.color = value
                        current.semanticColor = nil
                        documentStyle.update(current, for: role)
                    }
                )
            )
        }
    }
}

// MARK: - 文档样式行 - v3 - 行内仅保留轻量操作并延迟打开字体选择器
struct MarkdownStyleRowView: View {
    let role: MarkdownStyleRole
    @Binding var style: MarkdownRoleStyle
    let fontOptions: [MarkdownFontOption]
    let paletteItems: [MarkdownPaletteItem]
    let onTapFont: () -> Void
    let onTapCustomColor: () -> Void

    private var selectedFontDisplayName: String {
        if let matched = fontOptions.first(where: { $0.postScriptName == style.fontName }) {
            return matched.displayName
        }
        return markdownLocalizedFontDisplayName(postScriptName: style.fontName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(style.renderedColor)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.55), lineWidth: 1)
                    )
                Text(role.rawValue)
                    .font(.headline)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    fontPickerButton
                    sizeStepper
                }
                VStack(alignment: .leading, spacing: 10) {
                    fontPickerButton
                    sizeStepper
                }
            }

            HStack(spacing: 8) {
                ForEach(paletteItems) { palette in
                    let isSelected = palette.semanticColor == .adaptiveBlackWhite
                        ? style.semanticColor == .adaptiveBlackWhite
                        : style.semanticColor == nil && markdownWebColorHex(style.color) == markdownWebColorHex(palette.color)
                    Button {
                        style.color = palette.color
                        style.semanticColor = palette.semanticColor
                    } label: {
                        Circle()
                            .fill(palette.color)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle().stroke(Color.white.opacity(0.6), lineWidth: 1)
                            )
                            .overlay(
                                Group {
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                    .help(palette.title)
                }

                Button(action: onTapCustomColor) {
                    Image(systemName: "paintpalette")
                }
                .appGlassButtonStyle()
                .help("自选颜色")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fontPickerButton: some View {
        Button(action: onTapFont) {
            HStack(spacing: 6) {
                Text(selectedFontDisplayName)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .frame(maxWidth: 260, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }

    private var sizeStepper: some View {
        Stepper("大小 \(Int(style.fontSize))", value: $style.fontSize, in: 10...56)
            .frame(maxWidth: 180, alignment: .leading)
    }
}

private extension View {
    @ViewBuilder
    func markdownAdaptiveSheetSize(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        frame(width: width, height: height)
        #else
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
    }
}

// MARK: - 行级自选颜色 - v1 - 单实例颜色选择面板降低设置页首开开销
struct MarkdownRoleCustomColorSheet: View {
    let roleTitle: String
    @Binding var selectedColor: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(roleTitle) 自选颜色")
                .font(.headline)
            ColorPicker("颜色", selection: $selectedColor, supportsOpacity: true)
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .appGlassButtonStyle(.prominent)
                .help("完成")
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

// MARK: - 字体选择器 - v1 - 独立搜索选择字体避免主设置页卡顿
struct MarkdownFontSelectorView: View {
    let title: String
    let fontOptions: [MarkdownFontOption]
    @Binding var selectedFontName: String

    @State private var searchText = ""
    @State private var chineseOnly = false

    private var filteredOptions: [MarkdownFontOption] {
        var result = chineseOnly ? fontOptions.filter(\.isChinese) : fontOptions
        if chineseOnly, !result.contains(where: { $0.postScriptName == selectedFontName }) {
            let fallbackName = markdownLocalizedFontDisplayName(postScriptName: selectedFontName)
            result.insert(
                MarkdownFontOption(
                    postScriptName: selectedFontName,
                    displayName: "\(fallbackName)（当前）",
                    isChinese: markdownContainsChinese(fallbackName)
                ),
                at: 0
            )
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { option in
                option.displayName.localizedCaseInsensitiveContains(query) ||
                option.postScriptName.localizedCaseInsensitiveContains(query)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("搜索字体", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Toggle("仅中文字体", isOn: $chineseOnly)
                    .toggleStyle(.switch)

                List(filteredOptions) { option in
                    Button {
                        selectedFontName = option.postScriptName
                    } label: {
                        HStack {
                            Text(option.displayName)
                                .lineLimit(1)
                            Spacer()
                            if selectedFontName == option.postScriptName {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .padding(16)
            .navigationTitle(title)
        }
        .frame(minWidth: 420, minHeight: 520)
    }
}

// MARK: - 快捷输入设置弹窗 - v2 - 支持规则列表编辑与右键长按删除
struct MarkdownQuickInputSettingsView: View {
    @Binding var settings: MarkdownQuickInputSettings
    let onFinish: () -> Void

    @State private var entryMode: MarkdownShortcutEntryMode = .pair
    @State private var editingSingleRuleID: UUID?
    @State private var editingPairRuleID: UUID?
    @State private var singleTrigger = ""
    @State private var singleReplacement = ""
    @State private var pairOpenTrigger = ""
    @State private var pairCloseTrigger = ""
    @State private var pairOpenReplacement = ""
    @State private var pairCloseReplacement = ""

    var body: some View {
        VStack(spacing: 16) {
            Picker("模式", selection: $entryMode) {
                ForEach(MarkdownShortcutEntryMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 80)
            .padding(.top, 12)

            Group {
                switch entryMode {
                case .single:
                    VStack(spacing: 12) {
                        TextField("输入触发词（如 /1）", text: $singleTrigger)
                            .textFieldStyle(.roundedBorder)
                        TextField("输入替换词（如 ①）", text: $singleReplacement)
                            .textFieldStyle(.roundedBorder)
                    }
                case .pair:
                    VStack(spacing: 12) {
                        TextField("左触发词（如 ///）", text: $pairOpenTrigger)
                            .textFieldStyle(.roundedBorder)
                        TextField("右触发词（如 //）", text: $pairCloseTrigger)
                            .textFieldStyle(.roundedBorder)
                        TextField("左替换词（如 <u>）", text: $pairOpenReplacement)
                            .textFieldStyle(.roundedBorder)
                        TextField("右替换词（如 </u>）", text: $pairCloseReplacement)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding(.horizontal, 20)

            List {
                if entryMode == .single, !settings.singleRules.isEmpty {
                    Section("单目规则") {
                        ForEach(sortedSingleRules) { rule in
                            Button {
                                editingSingleRuleID = rule.id
                                editingPairRuleID = nil
                                entryMode = .single
                                singleTrigger = rule.trigger
                                singleReplacement = rule.replacement
                            } label: {
                                HStack {
                                    Text(rule.trigger)
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.secondary)
                                    Text(rule.replacement)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("删除", role: .destructive) {
                                    settings.singleRules.removeAll { $0.id == rule.id }
                                    if editingSingleRuleID == rule.id {
                                        clearEntryFields()
                                    }
                                }
                            }
                        }
                    }
                }

                if entryMode == .pair, !settings.pairRules.isEmpty {
                    Section("双目规则") {
                        ForEach(sortedPairRules) { rule in
                            Button {
                                editingPairRuleID = rule.id
                                editingSingleRuleID = nil
                                entryMode = .pair
                                pairOpenTrigger = rule.openTrigger
                                pairCloseTrigger = rule.closeTrigger
                                pairOpenReplacement = rule.openReplacement
                                pairCloseReplacement = rule.closeReplacement
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(rule.openTrigger) / \(rule.closeTrigger)")
                                    Text("\(rule.openReplacement) / \(rule.closeReplacement)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("删除", role: .destructive) {
                                    settings.pairRules.removeAll { $0.id == rule.id }
                                    if editingPairRuleID == rule.id {
                                        clearEntryFields()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .frame(maxHeight: 180)

            Spacer()

            HStack(spacing: 14) {
                Button {
                    appendRuleIfNeeded()
                    clearEntryFields()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .appGlassButtonStyle()
                .help("继续添加")

                Button {
                    appendRuleIfNeeded()
                    onFinish()
                } label: {
                    Image(systemName: "checkmark")
                }
                .appGlassButtonStyle(.prominent)
                .help("完成")
            }
            .padding(.bottom, 18)
        }
    }

    private var sortedSingleRules: [MarkdownSingleShortcutRule] {
        settings.singleRules.sorted { lhs, rhs in
            localizedRuleKey(lhs.trigger, lhs.replacement) < localizedRuleKey(rhs.trigger, rhs.replacement)
        }
    }

    private var sortedPairRules: [MarkdownPairShortcutRule] {
        settings.pairRules.sorted { lhs, rhs in
            localizedRuleKey(lhs.openTrigger, lhs.closeTrigger, lhs.openReplacement, lhs.closeReplacement)
                < localizedRuleKey(rhs.openTrigger, rhs.closeTrigger, rhs.openReplacement, rhs.closeReplacement)
        }
    }

    private func appendRuleIfNeeded() {
        switch entryMode {
        case .single:
            let trigger = singleTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = singleReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trigger.isEmpty, !replacement.isEmpty else { return }
            guard !settings.singleRules.contains(where: { rule in
                rule.id != editingSingleRuleID && rule.trigger == trigger
            }) else { return }
            if let editingSingleRuleID, let index = settings.singleRules.firstIndex(where: { $0.id == editingSingleRuleID }) {
                settings.singleRules[index].trigger = trigger
                settings.singleRules[index].replacement = replacement
            } else {
                settings.singleRules.append(MarkdownSingleShortcutRule(trigger: trigger, replacement: replacement))
            }
            sortSingleRules()
        case .pair:
            let openTrigger = pairOpenTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
            let closeTrigger = pairCloseTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
            let openReplacement = pairOpenReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
            let closeReplacement = pairCloseReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !openTrigger.isEmpty, !closeTrigger.isEmpty, !openReplacement.isEmpty, !closeReplacement.isEmpty else { return }
            guard !settings.pairRules.contains(where: { rule in
                rule.id != editingPairRuleID
                    && rule.openTrigger == openTrigger
                    && rule.closeTrigger == closeTrigger
            }) else { return }
            if let editingPairRuleID, let index = settings.pairRules.firstIndex(where: { $0.id == editingPairRuleID }) {
                settings.pairRules[index].openTrigger = openTrigger
                settings.pairRules[index].closeTrigger = closeTrigger
                settings.pairRules[index].openReplacement = openReplacement
                settings.pairRules[index].closeReplacement = closeReplacement
            } else {
                settings.pairRules.append(
                    MarkdownPairShortcutRule(
                        openTrigger: openTrigger,
                        closeTrigger: closeTrigger,
                        openReplacement: openReplacement,
                        closeReplacement: closeReplacement
                    )
                )
            }
            sortPairRules()
        }
    }

    private func sortSingleRules() {
        settings.singleRules.sort { lhs, rhs in
            localizedRuleKey(lhs.trigger, lhs.replacement) < localizedRuleKey(rhs.trigger, rhs.replacement)
        }
    }

    private func sortPairRules() {
        settings.pairRules.sort { lhs, rhs in
            localizedRuleKey(lhs.openTrigger, lhs.closeTrigger, lhs.openReplacement, lhs.closeReplacement)
                < localizedRuleKey(rhs.openTrigger, rhs.closeTrigger, rhs.openReplacement, rhs.closeReplacement)
        }
    }

    private func localizedRuleKey(_ parts: String...) -> String {
        parts.joined(separator: "\u{0}").localizedLowercase
    }

    private func clearEntryFields() {
        editingSingleRuleID = nil
        editingPairRuleID = nil
        singleTrigger = ""
        singleReplacement = ""
        pairOpenTrigger = ""
        pairCloseTrigger = ""
        pairOpenReplacement = ""
        pairCloseReplacement = ""
    }
}

// MARK: - 搜索结果模型 - v1 - 存储命中范围与右侧浮窗展示片段
struct MarkdownSearchResult: Identifiable, Hashable {
    let id: Int
    let range: NSRange
    let snippet: String
}

// MARK: - 搜索结果构建 - v1 - 生成全文命中列表并提取行级片段
func markdownBuildSearchResults(in text: String, query: String) -> [MarkdownSearchResult] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else { return [] }

    let nsText = text as NSString
    var results: [MarkdownSearchResult] = []
    var searchRange = NSRange(location: 0, length: nsText.length)
    var identifier = 0

    while searchRange.location < nsText.length {
        let found = nsText.range(of: normalizedQuery, options: [.caseInsensitive], range: searchRange)
        if found.location == NSNotFound { break }
        let lineRange = nsText.lineRange(for: found)
        var snippet = nsText.substring(with: lineRange)
        snippet = snippet.trimmingCharacters(in: .newlines)
        results.append(MarkdownSearchResult(id: identifier, range: found, snippet: snippet))
        identifier += 1

        let nextLocation = found.location + max(found.length, 1)
        guard nextLocation <= nsText.length else { break }
        searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
    }

    return results
}

// MARK: - 搜索结果浮窗 - v1 - 右侧显示命中句子并高亮关键词
struct MarkdownSearchFloatingPanelView: View {
    let query: String
    let results: [MarkdownSearchResult]
    let activeIndex: Int?
    let onSelect: (Int) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 16, height: 16)
                }
                .appGlassButtonStyle(.danger)
                Spacer()
            }
            if results.isEmpty {
                Text("无匹配项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(results.enumerated()), id: \.offset) { item in
                            let index = item.offset
                            let result = item.element
                            Button {
                                onSelect(index)
                            } label: {
                                Text(markdownSearchHighlightedSnippet(result.snippet, query: query))
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(index == activeIndex ? Color.blue.opacity(0.16) : Color.clear)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(10)
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
    }
}

func markdownSearchHighlightedSnippet(_ snippet: String, query: String) -> AttributedString {
    var attributed = AttributedString(snippet)
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else { return attributed }

    var searchStart = attributed.startIndex
    while searchStart < attributed.endIndex,
          let range = attributed[searchStart...].range(of: normalizedQuery, options: [.caseInsensitive]) {
        attributed[range].foregroundColor = .blue
        attributed[range].font = .caption.bold()
        searchStart = range.upperBound
    }
    return attributed
}

func markdownFindSearchRanges(in text: NSString, query: String) -> [NSRange] {
    let profileStart = MarkdownEditorPerformanceProbe.start()
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else { return [] }
    var ranges: [NSRange] = []
    var searchRange = NSRange(location: 0, length: text.length)

    while searchRange.location < text.length {
        let found = text.range(of: normalizedQuery, options: [.caseInsensitive], range: searchRange)
        if found.location == NSNotFound { break }
        ranges.append(found)
        let nextLocation = found.location + max(found.length, 1)
        guard nextLocation <= text.length else { break }
        searchRange = NSRange(location: nextLocation, length: text.length - nextLocation)
    }

    MarkdownEditorPerformanceProbe.end(
        "markdownFindSearchRanges",
        start: profileStart,
        details: "queryLength=\((normalizedQuery as NSString).length),matches=\(ranges.count),utf16=\(text.length)"
    )
    return ranges
}

// MARK: - TOC面板视图 - v1 - 显示标题层级过滤与跳转列表
struct MarkdownTOCPanelView: View {
    let headings: [MarkdownHeading]
    @Binding var maxLevel: Int
    let onSelect: (MarkdownHeading) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stepper("显示到 H\(maxLevel)", value: $maxLevel, in: 1...6)
            Divider()
            if headings.isEmpty {
                Text("当前无标题")
                    .foregroundStyle(.secondary)
            } else {
                List(headings) { heading in
                    Button {
                        onSelect(heading)
                    } label: {
                        Text(String(repeating: "  ", count: max(0, heading.level - 1)) + heading.title)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - 富文本预览 - v2 - 使用节流与后台解析实现快速富文本渲染
struct MarkdownStyledPreviewView: View {
    let markdownText: String
    let documentStyle: MarkdownDocumentStyle

    @State private var rendered = AttributedString("")
    @State private var renderTask: Task<Void, Never>?
    @State private var renderRevision = 0

    var body: some View {
        ScrollView {
            Text(rendered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .task {
            await scheduleRender()
        }
        .onChange(of: markdownText) { _, _ in
            Task { await scheduleRender() }
        }
        .onChange(of: documentStyle) { _, _ in
            Task { await scheduleRender() }
        }
    }

    private func scheduleRender() async {
        let scheduleStart = MarkdownEditorPerformanceProbe.start()
        renderTask?.cancel()
        renderRevision += 1
        let revision = renderRevision
        let sourceSnapshot = markdownText
        let styleSnapshot = documentStyle
        MarkdownEditorPerformanceProbe.end(
            "MarkdownStyledPreviewView.scheduleRender",
            start: scheduleStart,
            details: "revision=\(revision),\(MarkdownEditorPerformanceProbe.textDetails(sourceSnapshot))"
        )

        renderTask = Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            let renderStart = MarkdownEditorPerformanceProbe.start()
            let value = await styledAttributedStringAsync(from: sourceSnapshot, style: styleSnapshot)
            MarkdownEditorPerformanceProbe.end(
                "MarkdownStyledPreviewView.renderTask",
                start: renderStart,
                details: "revision=\(revision),\(MarkdownEditorPerformanceProbe.textDetails(sourceSnapshot))"
            )
            guard !Task.isCancelled else { return }

            await MainActor.run {
                let applyStart = MarkdownEditorPerformanceProbe.start()
                guard revision == renderRevision else { return }
                rendered = value
                MarkdownEditorPerformanceProbe.end(
                    "MarkdownStyledPreviewView.applyRendered",
                    start: applyStart,
                    details: "revision=\(revision)"
                )
            }
        }
    }
}

// MARK: - 即时渲染模式 - v7 - 单页可编辑富文本源码并支持搜索高亮定位
struct MarkdownInstantRenderModeView: View {
    @Binding var markdownText: String
    @Binding var targetUTF16Offset: Int?
    let preferredScheme: ColorScheme?
    let workingDirectoryURL: URL?
    let documentStyle: MarkdownDocumentStyle
    let quickInputSettings: MarkdownQuickInputSettings
    let searchQuery: String
    let activeSearchRange: NSRange?

    var body: some View {
        MarkdownInstantEditorContainer(
            markdownText: $markdownText,
            targetUTF16Offset: $targetUTF16Offset,
            workingDirectoryURL: workingDirectoryURL,
            documentStyle: documentStyle,
            quickInputSettings: quickInputSettings,
            searchQuery: searchQuery,
            activeSearchRange: activeSearchRange
        )
    }
}

// MARK: - 源码模式视图 - v7 - 使用固定Markdown标准样式渲染并支持搜索高亮定位
struct MarkdownSourceModeView: View {
    @Binding var markdownText: String
    @Binding var targetUTF16Offset: Int?
    let preferredScheme: ColorScheme?
    let workingDirectoryURL: URL?
    let documentStyle: MarkdownDocumentStyle
    let quickInputSettings: MarkdownQuickInputSettings
    let searchQuery: String
    let activeSearchRange: NSRange?

    private var sourceStyle: MarkdownDocumentStyle {
        .sourceStandard
    }

    var body: some View {
        MarkdownSourceEditorContainer(
            markdownText: $markdownText,
            targetUTF16Offset: $targetUTF16Offset,
            workingDirectoryURL: workingDirectoryURL,
            documentStyle: sourceStyle,
            quickInputSettings: quickInputSettings,
            searchQuery: searchQuery,
            activeSearchRange: activeSearchRange
        )
    }
}

// MARK: - 双区域Markdown视图 - v1 - 左侧TextKit2编辑右侧Web预览并保留旧即时渲染代码为旧管道
struct MarkdownDualRenderModeView: View {
    @Binding var markdownText: String
    @Binding var targetUTF16Offset: Int?
    let preferredScheme: ColorScheme?
    let workingDirectoryURL: URL?
    let documentStyle: MarkdownDocumentStyle
    let quickInputSettings: MarkdownQuickInputSettings
    let searchQuery: String
    let activeSearchRange: NSRange?
    #if os(macOS)
    @StateObject private var scrollSyncBridge = MarkdownDualScrollSyncBridge()
    #endif

    var body: some View {
        HStack(spacing: 0) {
            Group {
            #if os(macOS)
                MarkdownTextKit2PlainModeView(
                    markdownText: $markdownText,
                    targetUTF16Offset: $targetUTF16Offset,
                    preferredScheme: preferredScheme,
                    workingDirectoryURL: workingDirectoryURL,
                    documentStyle: documentStyle,
                    quickInputSettings: quickInputSettings,
                    searchQuery: searchQuery,
                    activeSearchRange: activeSearchRange,
                    scrollSyncBridge: scrollSyncBridge
                )
            #else
                MarkdownTextKit2PlainModeView(
                    markdownText: $markdownText,
                    targetUTF16Offset: $targetUTF16Offset,
                    preferredScheme: preferredScheme,
                    workingDirectoryURL: workingDirectoryURL,
                    documentStyle: documentStyle,
                    quickInputSettings: quickInputSettings,
                    searchQuery: searchQuery,
                    activeSearchRange: activeSearchRange
                )
            #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            Group {
            #if os(macOS)
                MarkdownWebRenderModeView(
                    markdownText: markdownText,
                    preferredScheme: preferredScheme,
                    documentStyle: documentStyle,
                    scrollSyncBridge: scrollSyncBridge
                )
            #else
                MarkdownWebRenderModeView(
                    markdownText: markdownText,
                    preferredScheme: preferredScheme,
                    documentStyle: documentStyle
                )
            #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - TextKit2纯文本基线模式 - v1 - 用于验证大文档原生编辑性能
struct MarkdownTextKit2PlainModeView: View {
    @Binding var markdownText: String
    @Binding var targetUTF16Offset: Int?
    let preferredScheme: ColorScheme?
    let workingDirectoryURL: URL?
    let documentStyle: MarkdownDocumentStyle
    let quickInputSettings: MarkdownQuickInputSettings
    let searchQuery: String
    let activeSearchRange: NSRange?
    #if os(macOS)
    let scrollSyncBridge: MarkdownDualScrollSyncBridge?
    #endif

    init(
        markdownText: Binding<String>,
        targetUTF16Offset: Binding<Int?>,
        preferredScheme: ColorScheme?,
        workingDirectoryURL: URL?,
        documentStyle: MarkdownDocumentStyle,
        quickInputSettings: MarkdownQuickInputSettings,
        searchQuery: String,
        activeSearchRange: NSRange?,
        scrollSyncBridge: MarkdownDualScrollSyncBridge? = nil
    ) {
        self._markdownText = markdownText
        self._targetUTF16Offset = targetUTF16Offset
        self.preferredScheme = preferredScheme
        self.workingDirectoryURL = workingDirectoryURL
        self.documentStyle = documentStyle
        self.quickInputSettings = quickInputSettings
        self.searchQuery = searchQuery
        self.activeSearchRange = activeSearchRange
        #if os(macOS)
        self.scrollSyncBridge = scrollSyncBridge
        #endif
    }

    var body: some View {
        #if os(macOS)
        MarkdownTextKit2PlainTextEditor(
            text: $markdownText,
            targetUTF16Offset: $targetUTF16Offset,
            workingDirectoryURL: workingDirectoryURL,
            documentStyle: documentStyle,
            quickInputSettings: quickInputSettings,
            searchQuery: searchQuery,
            activeSearchRange: activeSearchRange,
            scrollSyncBridge: scrollSyncBridge
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        #else
        MarkdownIOSStyledTextEditor(
            text: $markdownText,
            targetUTF16Offset: $targetUTF16Offset,
            documentStyle: documentStyle
        )
            .padding(8)
        #endif
    }
}

// MARK: - Web渲染模式视图 - v2 - 以只读Web视图渲染Markdown并映射文档样式
struct MarkdownWebRenderModeView: View {
    let markdownText: String
    let preferredScheme: ColorScheme?
    let documentStyle: MarkdownDocumentStyle
    #if os(macOS)
    let scrollSyncBridge: MarkdownDualScrollSyncBridge?
    #endif

    init(
        markdownText: String,
        preferredScheme: ColorScheme?,
        documentStyle: MarkdownDocumentStyle,
        scrollSyncBridge: MarkdownDualScrollSyncBridge? = nil
    ) {
        self.markdownText = markdownText
        self.preferredScheme = preferredScheme
        self.documentStyle = documentStyle
        #if os(macOS)
        self.scrollSyncBridge = scrollSyncBridge
        #endif
    }

    var body: some View {
        #if os(macOS)
        MarkdownWebView(
            markdownText: markdownText,
            preferredScheme: preferredScheme,
            documentStyle: documentStyle,
            scrollSyncBridge: scrollSyncBridge
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
        #else
        MarkdownWebView(
            markdownText: markdownText,
            preferredScheme: preferredScheme,
            documentStyle: documentStyle,
            scrollSyncBridge: nil
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
        #endif
    }
}

// MARK: - 编辑器容器 - v6 - 封装源码编辑定位跳转并支持搜索高亮同步
struct MarkdownSourceEditorContainer: View {
    @Binding var markdownText: String
    @Binding var targetUTF16Offset: Int?
    let workingDirectoryURL: URL?
    let documentStyle: MarkdownDocumentStyle
    let quickInputSettings: MarkdownQuickInputSettings
    let searchQuery: String
    let activeSearchRange: NSRange?

    var body: some View {
        #if os(macOS)
        MarkdownNativeTextEditor(
            text: $markdownText,
            targetUTF16Offset: $targetUTF16Offset,
            workingDirectoryURL: workingDirectoryURL,
            highlightMode: .source(documentStyle),
            quickInputSettings: quickInputSettings,
            searchQuery: searchQuery,
            activeSearchRange: activeSearchRange
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
        #else
        MarkdownIOSStyledTextEditor(
            text: $markdownText,
            targetUTF16Offset: $targetUTF16Offset,
            documentStyle: documentStyle
        )
            .padding(8)
        #endif
    }
}

// MARK: - 即时编辑容器 - v3 - 封装富文本编辑并同步应用即时样式快捷输入与搜索高亮
struct MarkdownInstantEditorContainer: View {
    @Binding var markdownText: String
    @Binding var targetUTF16Offset: Int?
    let workingDirectoryURL: URL?
    let documentStyle: MarkdownDocumentStyle
    let quickInputSettings: MarkdownQuickInputSettings
    let searchQuery: String
    let activeSearchRange: NSRange?

    var body: some View {
        #if os(macOS)
        MarkdownNativeTextEditor(
            text: $markdownText,
            targetUTF16Offset: $targetUTF16Offset,
            workingDirectoryURL: workingDirectoryURL,
            highlightMode: .instant(documentStyle),
            quickInputSettings: quickInputSettings,
            searchQuery: searchQuery,
            activeSearchRange: activeSearchRange
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        #else
        MarkdownIOSStyledTextEditor(
            text: $markdownText,
            targetUTF16Offset: $targetUTF16Offset,
            documentStyle: documentStyle
        )
            .padding(8)
        #endif
    }
}

// MARK: - 后台渲染工具 - v1 - 使用后台线程生成富文本结果
func styledAttributedStringAsync(from source: String, style: MarkdownDocumentStyle) async -> AttributedString {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let profileStart = MarkdownEditorPerformanceProbe.start()
            let value = styledAttributedString(from: source, style: style)
            MarkdownEditorPerformanceProbe.end(
                "styledAttributedStringAsync.background",
                start: profileStart,
                details: MarkdownEditorPerformanceProbe.textDetails(source)
            )
            continuation.resume(returning: value)
        }
    }
}

// MARK: - 样式化渲染工具 - v1 - 解析Markdown并按角色映射字体大小颜色
func styledAttributedString(from source: String, style: MarkdownDocumentStyle) -> AttributedString {
    #if os(macOS)
    let profileStart = MarkdownEditorPerformanceProbe.start()
    let attributed = NSAttributedString(markdown: source)
    let mutable = NSMutableAttributedString(attributedString: attributed)
    let fullRange = NSRange(location: 0, length: mutable.length)

    applyRoleStyle(style.body, to: mutable, range: fullRange)

    let renderedText = mutable.string as NSString
    var searchLocation = 0

    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        let rawLine = String(line)

        if let headingInfo = parseHeadingLine(rawLine) {
            let styleForHeading = style.headingStyle(level: headingInfo.level)
            if let range = renderedText.range(of: headingInfo.title, options: [], range: NSRange(location: searchLocation, length: max(0, renderedText.length - searchLocation))).validRange {
                applyRoleStyle(styleForHeading, to: mutable, range: range)
                searchLocation = range.location + range.length
            }
            continue
        }

        if let commentText = parseCommentLine(rawLine), !commentText.isEmpty {
            if let range = renderedText.range(of: commentText, options: [], range: NSRange(location: searchLocation, length: max(0, renderedText.length - searchLocation))).validRange {
                applyRoleStyle(style.comment, to: mutable, range: range)
                searchLocation = range.location + range.length
            }
        }
    }

    let result = AttributedString(mutable)
    MarkdownEditorPerformanceProbe.end(
        "styledAttributedString",
        start: profileStart,
        details: "renderedUtf16=\(mutable.length),\(MarkdownEditorPerformanceProbe.textDetails(source))"
    )
    return result
    #else
    return (try? AttributedString(markdown: source)) ?? AttributedString(source)
    #endif
}

private func markdownSourceHangingPrefix(in line: String) -> String? {
    var headingLevel = 0
    for character in line {
        if character == "#" {
            headingLevel += 1
        } else {
            break
        }
    }
    if headingLevel > 0, headingLevel <= 6 {
        let index = line.index(line.startIndex, offsetBy: headingLevel)
        if index < line.endIndex, line[index] == " " {
            return String(repeating: "#", count: headingLevel) + " "
        }
    }

    let chars = Array(line)
    var index = 0
    while index < chars.count, chars[index] == " " {
        index += 1
    }
    guard index < chars.count else { return nil }

    let leadingIndent = String(chars.prefix(index))
    if chars[index] == "-", index + 1 < chars.count, chars[index + 1] == " " {
        return leadingIndent + "- "
    }

    if chars[index].isNumber {
        let numberStart = index
        var numberEnd = index
        while numberEnd < chars.count, chars[numberEnd].isNumber {
            numberEnd += 1
        }
        if numberEnd + 1 < chars.count, chars[numberEnd] == ".", chars[numberEnd + 1] == " " {
            return leadingIndent + String(chars[numberStart...numberEnd]) + " "
        }
    }

    return nil
}

#if os(macOS)

private func parseHeadingLine(_ line: String) -> (level: Int, title: String)? {
    var level = 0
    for char in line {
        if char == "#" {
            level += 1
        } else {
            break
        }
    }

    guard level > 0, level <= 6 else { return nil }
    let index = line.index(line.startIndex, offsetBy: level)
    guard index < line.endIndex, line[index] == " " else { return nil }

    let title = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
    return title.isEmpty ? nil : (level, title)
}

private func parseCommentLine(_ line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix(">") else { return nil }
    return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
}

private func applyRoleStyle(_ style: MarkdownRoleStyle, to text: NSMutableAttributedString, range: NSRange) {
    let font = markdownResolvedFont(name: style.fontName, size: style.fontSize)
    let color = NSColor(style.renderedColor)
    text.addAttributes([
        .font: font,
        .foregroundColor: color
    ], range: range)
}

private func markdownResolvedFont(name: String, size: Double) -> NSFont {
    if name == appleSystemMonospacedFontName {
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
    return NSFont(name: name, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
}

private func parseHeadingLevelForStyling(in line: String) -> Int? {
    var level = 0
    for char in line {
        if char == "#" {
            level += 1
        } else {
            break
        }
    }
    guard level > 0, level <= 6 else { return nil }
    let index = line.index(line.startIndex, offsetBy: level)
    guard index < line.endIndex, line[index] == " " else { return nil }
    return level
}

private func parseListLevel(in line: String) -> Int? {
    let chars = Array(line)
    var index = 0
    while index < chars.count, chars[index] == " " {
        index += 1
    }
    guard index < chars.count else { return nil }

    let indentLevel = max(0, index / 2)

    if chars[index] == "-", index + 1 < chars.count, chars[index + 1] == " " {
        return indentLevel + 1
    }

    if chars[index].isNumber {
        var numberIndex = index
        while numberIndex < chars.count, chars[numberIndex].isNumber {
            numberIndex += 1
        }
        if numberIndex + 1 < chars.count, chars[numberIndex] == ".", chars[numberIndex + 1] == " " {
            return indentLevel + 1
        }
    }

    return nil
}

private func markdownHangingPrefix(in line: String) -> String? {
    markdownSourceHangingPrefix(in: line)
}

private func markdownHangingParagraphStyle(prefix: String, font: NSFont) -> NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.firstLineHeadIndent = 0
    paragraph.headIndent = ceil((prefix as NSString).size(withAttributes: [.font: font]).width)
    return paragraph
}

private func markdownHangingParagraphStyle(for line: String, font: NSFont) -> NSParagraphStyle? {
    guard let prefix = markdownHangingPrefix(in: line) else { return nil }
    return markdownHangingParagraphStyle(prefix: prefix, font: font)
}

private func applyMarkdownHangingIndentStyle(to text: NSMutableAttributedString, rawLine: String, range: NSRange) {
    guard range.length > 0,
          let prefix = markdownHangingPrefix(in: rawLine) else { return }
    let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        ?? NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    let paragraph = markdownHangingParagraphStyle(prefix: prefix, font: font)
    text.addAttributes([
        .paragraphStyle: paragraph
    ], range: range)
}

private func parseInlineCodeRanges(in line: String, base: Int) -> [NSRange] {
    let chars = Array(line)
    var ranges: [NSRange] = []
    var index = 0

    while index < chars.count {
        guard chars[index] == "`" else {
            index += 1
            continue
        }

        let start = index
        index += 1
        while index < chars.count, chars[index] != "`" {
            index += 1
        }
        guard index < chars.count else { break }

        let contentStart = start + 1
        let contentLength = max(0, index - contentStart)
        if contentLength > 0 {
            ranges.append(NSRange(location: base + contentStart, length: contentLength))
        }
        index += 1
    }
    return ranges
}

private func parseInlineStrongRanges(in line: String, base: Int) -> [NSRange] {
    let chars = Array(line)
    var ranges: [NSRange] = []
    var index = 0

    while index + 1 < chars.count {
        guard chars[index] == "*", chars[index + 1] == "*" else {
            index += 1
            continue
        }

        let start = index + 2
        index = start
        while index + 1 < chars.count {
            if chars[index] == "*", chars[index + 1] == "*" {
                let length = max(0, index - start)
                if length > 0 {
                    ranges.append(NSRange(location: base + start, length: length))
                }
                index += 2
                break
            }
            index += 1
        }
    }

    return ranges
}

private func parseInlineItalicRanges(in line: String, base: Int) -> [NSRange] {
    let chars = Array(line)
    var ranges: [NSRange] = []
    var index = 0

    while index < chars.count {
        guard chars[index] == "*" else {
            index += 1
            continue
        }

        if (index > 0 && chars[index - 1] == "*") || (index + 1 < chars.count && chars[index + 1] == "*") {
            index += 1
            continue
        }

        let start = index + 1
        index = start
        while index < chars.count {
            if chars[index] == "*" {
                if (index > 0 && chars[index - 1] == "*") || (index + 1 < chars.count && chars[index + 1] == "*") {
                    index += 1
                    continue
                }
                let length = max(0, index - start)
                if length > 0 {
                    ranges.append(NSRange(location: base + start, length: length))
                }
                index += 1
                break
            }
            index += 1
        }
    }

    return ranges
}

private func parseInlineLinkLabelRanges(in line: String, base: Int) -> [NSRange] {
    let chars = Array(line)
    var ranges: [NSRange] = []
    var index = 0

    while index < chars.count {
        guard chars[index] == "[" else {
            index += 1
            continue
        }

        let labelStart = index + 1
        var labelEnd = labelStart
        while labelEnd < chars.count, chars[labelEnd] != "]" {
            labelEnd += 1
        }

        guard labelEnd + 1 < chars.count, chars[labelEnd] == "]", chars[labelEnd + 1] == "(" else {
            index += 1
            continue
        }

        var urlEnd = labelEnd + 2
        while urlEnd < chars.count, chars[urlEnd] != ")" {
            urlEnd += 1
        }

        guard urlEnd < chars.count else {
            index += 1
            continue
        }

        let labelLength = max(0, labelEnd - labelStart)
        if labelLength > 0 {
            ranges.append(NSRange(location: base + labelStart, length: labelLength))
        }
        index = urlEnd + 1
    }

    return ranges
}

private func parseInlineMathRanges(in line: String, base: Int) -> [NSRange] {
    let chars = Array(line)
    var ranges: [NSRange] = []
    var index = 0

    while index < chars.count {
        if chars[index] == "$" {
            let isDouble = index + 1 < chars.count && chars[index + 1] == "$"
            let start = index + (isDouble ? 2 : 1)
            var cursor = start
            while cursor < chars.count {
                if isDouble {
                    if cursor + 1 < chars.count, chars[cursor] == "$", chars[cursor + 1] == "$" {
                        let length = max(0, cursor - start)
                        if length > 0 {
                            ranges.append(NSRange(location: base + start, length: length))
                        }
                        index = cursor + 2
                        break
                    }
                } else if chars[cursor] == "$" {
                    let length = max(0, cursor - start)
                    if length > 0 {
                        ranges.append(NSRange(location: base + start, length: length))
                    }
                    index = cursor + 1
                    break
                }
                cursor += 1
            }
            if cursor >= chars.count {
                break
            }
            continue
        }

        if index + 1 < chars.count, chars[index] == "\\", chars[index + 1] == "(" {
            let start = index + 2
            var cursor = start
            while cursor + 1 < chars.count {
                if chars[cursor] == "\\", chars[cursor + 1] == ")" {
                    let length = max(0, cursor - start)
                    if length > 0 {
                        ranges.append(NSRange(location: base + start, length: length))
                    }
                    index = cursor + 2
                    break
                }
                cursor += 1
            }
            if cursor + 1 >= chars.count {
                break
            }
            continue
        }

        index += 1
    }

    return ranges
}

private func parseInlineHighlightRanges(in line: String, base: Int) -> [NSRange] {
    let chars = Array(line)
    var ranges: [NSRange] = []
    var index = 0

    while index + 1 < chars.count {
        guard chars[index] == "=", chars[index + 1] == "=" else {
            index += 1
            continue
        }

        let start = index + 2
        var cursor = start
        while cursor + 1 < chars.count {
            if chars[cursor] == "=", chars[cursor + 1] == "=" {
                let length = max(0, cursor - start)
                if length > 0 {
                    ranges.append(NSRange(location: base + start, length: length))
                }
                index = cursor + 2
                break
            }
            cursor += 1
        }

        if cursor + 1 >= chars.count {
            break
        }
    }

    return ranges
}

private func parseInlineUnderlineRanges(in line: String, base: Int) -> [NSRange] {
    var ranges: [NSRange] = []
    let nsLine = line as NSString
    let fullRange = NSRange(location: 0, length: nsLine.length)
    guard let regex = try? NSRegularExpression(pattern: "<u>(.*?)</u>", options: [.caseInsensitive]) else {
        return ranges
    }

    regex.enumerateMatches(in: line, options: [], range: fullRange) { result, _, _ in
        guard let result, result.numberOfRanges > 1 else { return }
        let capture = result.range(at: 1)
        guard capture.location != NSNotFound, capture.length > 0 else { return }
        ranges.append(NSRange(location: base + capture.location, length: capture.length))
    }

    return ranges
}

private func parseInlineRegexCaptureRanges(pattern: String, in line: String, base: Int, options: NSRegularExpression.Options = []) -> [NSRange] {
    var ranges: [NSRange] = []
    let nsLine = line as NSString
    let fullRange = NSRange(location: 0, length: nsLine.length)
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
        return ranges
    }
    regex.enumerateMatches(in: line, options: [], range: fullRange) { result, _, _ in
        guard let result, result.numberOfRanges > 1 else { return }
        for index in 1..<result.numberOfRanges {
            let capture = result.range(at: index)
            if capture.location != NSNotFound, capture.length > 0 {
                ranges.append(NSRange(location: base + capture.location, length: capture.length))
                break
            }
        }
    }
    return ranges
}

private func parseInlineHTMLTagMatches(
    pattern: String,
    in line: String,
    base: Int,
    options: NSRegularExpression.Options = []
) -> [(full: NSRange, content: NSRange)] {
    let nsLine = line as NSString
    let fullRange = NSRange(location: 0, length: nsLine.length)
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
        return []
    }
    return regex.matches(in: line, options: [], range: fullRange).compactMap { result in
        guard result.numberOfRanges > 1 else { return nil }
        let content = result.range(at: 1)
        guard content.location != NSNotFound, content.length > 0 else { return nil }
        return (
            full: NSRange(location: base + result.range.location, length: result.range.length),
            content: NSRange(location: base + content.location, length: content.length)
        )
    }
}

private func hideInlineMarkdownDelimiters(
    in textStorage: NSTextStorage,
    fullRange: NSRange,
    contentRange: NSRange
) {
    let leadingLength = max(0, contentRange.location - fullRange.location)
    let trailingStart = NSMaxRange(contentRange)
    let trailingLength = max(0, NSMaxRange(fullRange) - trailingStart)
    let hiddenAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.clear,
        .font: NSFont.monospacedSystemFont(ofSize: 0.1, weight: .regular),
        .kern: -2.0,
        .ligature: 0
    ]
    if leadingLength > 0 {
        textStorage.addAttributes(
            hiddenAttributes,
            range: NSRange(location: fullRange.location, length: leadingLength)
        )
    }
    if trailingLength > 0 {
        textStorage.addAttributes(
            hiddenAttributes,
            range: NSRange(location: trailingStart, length: trailingLength)
        )
    }
}

private extension NSRange {
    var validRange: NSRange? {
        location == NSNotFound ? nil : self
    }
}

#endif

#if os(iOS)
// MARK: - iOS富文本编辑器 - v1 - 按文档样式渲染Markdown行级字体颜色字号
struct MarkdownIOSStyledTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var targetUTF16Offset: Int?
    let documentStyle: MarkdownDocumentStyle

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, targetUTF16Offset: $targetUTF16Offset, documentStyle: documentStyle)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false
        textView.attributedText = markdownIOSStyledAttributedString(from: text, style: documentStyle)
        context.coordinator.lastAppliedText = text
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.documentStyle = documentStyle
        if context.coordinator.lastAppliedText != text || context.coordinator.lastAppliedStyle != documentStyle {
            let selectedRange = textView.selectedRange
            let preservedOffset = textView.contentOffset
            context.coordinator.isApplyingProgrammaticChange = true
            textView.attributedText = markdownIOSStyledAttributedString(from: text, style: documentStyle)
            textView.selectedRange = markdownIOSClampedRange(selectedRange, textLength: (text as NSString).length)
            context.coordinator.isApplyingProgrammaticChange = false
            context.coordinator.lastAppliedText = text
            context.coordinator.lastAppliedStyle = documentStyle
            context.coordinator.restoreContentOffset(preservedOffset, in: textView)
        }

        if let offset = targetUTF16Offset, context.coordinator.lastConsumedTargetOffset != offset {
            let location = max(0, min(offset, (textView.text as NSString).length))
            let range = NSRange(location: location, length: 0)
            textView.selectedRange = range
            textView.scrollRangeToVisible(range)
            context.coordinator.lastConsumedTargetOffset = offset
            DispatchQueue.main.async {
                targetUTF16Offset = nil
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String
        @Binding private var targetUTF16Offset: Int?
        var documentStyle: MarkdownDocumentStyle
        var lastAppliedText = ""
        var lastAppliedStyle: MarkdownDocumentStyle?
        var lastConsumedTargetOffset: Int?
        var isApplyingProgrammaticChange = false

        init(
            text: Binding<String>,
            targetUTF16Offset: Binding<Int?>,
            documentStyle: MarkdownDocumentStyle
        ) {
            _text = text
            _targetUTF16Offset = targetUTF16Offset
            self.documentStyle = documentStyle
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" else { return true }
            return !applyAutoContinueRule(in: textView, replacementRange: range)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingProgrammaticChange else { return }
            let selectedRange = textView.selectedRange
            let preservedOffset = textView.contentOffset
            let value = textView.text ?? ""
            text = value
            lastAppliedText = value
            isApplyingProgrammaticChange = true
            textView.attributedText = markdownIOSStyledAttributedString(from: value, style: documentStyle)
            textView.selectedRange = markdownIOSClampedRange(selectedRange, textLength: (value as NSString).length)
            isApplyingProgrammaticChange = false
            restoreContentOffset(preservedOffset, in: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingProgrammaticChange else { return }
            applyTypingAttributes(in: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            applyTypingAttributes(in: textView)
        }

        private func applyTypingAttributes(in textView: UITextView) {
            let source = textView.text ?? ""
            let style = markdownIOSRoleStyle(at: textView.selectedRange.location, in: source, documentStyle: documentStyle)
            let line = markdownIOSLineText(at: textView.selectedRange.location, in: source)
            textView.typingAttributes = markdownIOSTextAttributes(for: style, line: line)
        }

        private func applyAutoContinueRule(in textView: UITextView, replacementRange: NSRange) -> Bool {
            guard replacementRange.length == 0 else { return false }

            let source = textView.text ?? ""
            let nsText = source as NSString
            let caret = max(0, min(replacementRange.location, nsText.length))
            let lineAnchor = max(0, min(caret > 0 ? caret - 1 : caret, nsText.length))
            let lineRange = nsText.lineRange(for: NSRange(location: lineAnchor, length: 0))

            var line = nsText.substring(with: lineRange)
            if line.hasSuffix("\n") { line.removeLast() }

            guard caret == lineRange.location + (line as NSString).length else { return false }
            guard let marker = markdownIOSAutoContinueMarker(in: line) else { return false }

            let preservedOffset = textView.contentOffset
            if marker.hasContent {
                let insertion = "\n\(marker.nextMarker)"
                let nextText = nsText.replacingCharacters(in: replacementRange, with: insertion)
                let nextSelection = NSRange(location: caret + (insertion as NSString).length, length: 0)
                applyProgrammaticText(nextText, selectedRange: nextSelection, in: textView, preservedOffset: preservedOffset)
                textView.scrollRangeToVisible(nextSelection)
            } else {
                let markerRange = NSRange(location: lineRange.location, length: marker.markerLength)
                let nextText = nsText.replacingCharacters(in: markerRange, with: "")
                let nextSelection = NSRange(location: max(0, caret - marker.markerLength), length: 0)
                applyProgrammaticText(nextText, selectedRange: nextSelection, in: textView, preservedOffset: preservedOffset)
            }
            return true
        }

        private func applyProgrammaticText(
            _ value: String,
            selectedRange: NSRange,
            in textView: UITextView,
            preservedOffset: CGPoint
        ) {
            text = value
            lastAppliedText = value
            isApplyingProgrammaticChange = true
            textView.attributedText = markdownIOSStyledAttributedString(from: value, style: documentStyle)
            textView.selectedRange = markdownIOSClampedRange(selectedRange, textLength: (value as NSString).length)
            isApplyingProgrammaticChange = false
            restoreContentOffset(preservedOffset, in: textView)
            applyTypingAttributes(in: textView)
        }

        func restoreContentOffset(_ offset: CGPoint, in textView: UITextView) {
            let normalizedOffset = clampedContentOffset(offset, in: textView)
            guard textView.contentOffset != normalizedOffset else { return }
            textView.setContentOffset(normalizedOffset, animated: false)
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                let asyncOffset = self.clampedContentOffset(offset, in: textView)
                if textView.contentOffset != asyncOffset {
                    textView.setContentOffset(asyncOffset, animated: false)
                }
            }
        }

        private func clampedContentOffset(_ offset: CGPoint, in textView: UITextView) -> CGPoint {
            let minX = -textView.adjustedContentInset.left
            let minY = -textView.adjustedContentInset.top
            let maxX = max(minX, textView.contentSize.width - textView.bounds.width + textView.adjustedContentInset.right)
            let maxY = max(minY, textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom)
            return CGPoint(
                x: min(max(offset.x, minX), maxX),
                y: min(max(offset.y, minY), maxY)
            )
        }
    }
}

private func markdownIOSAutoContinueMarker(in line: String) -> (nextMarker: String, markerLength: Int, hasContent: Bool)? {
    if let numbered = markdownIOSNumberedAutoContinueMarker(in: line) {
        return numbered
    }
    return markdownIOSFixedAutoContinueMarker(in: line, markerBody: "- ")
}

private func markdownIOSNumberedAutoContinueMarker(in line: String) -> (nextMarker: String, markerLength: Int, hasContent: Bool)? {
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
    return ("\(indent)\(number + 1). ", index + 2, !content.isEmpty)
}

private func markdownIOSFixedAutoContinueMarker(in line: String, markerBody: String) -> (nextMarker: String, markerLength: Int, hasContent: Bool)? {
    let indentCount = line.prefix { $0 == " " }.count
    let indent = String(repeating: " ", count: indentCount)
    let remaining = String(line.dropFirst(indentCount))
    guard remaining.hasPrefix(markerBody) else { return nil }

    let markerLength = indentCount + markerBody.count
    let content = String(remaining.dropFirst(markerBody.count)).trimmingCharacters(in: .whitespaces)
    return (indent + markerBody, markerLength, !content.isEmpty)
}

private func markdownIOSStyledAttributedString(from source: String, style: MarkdownDocumentStyle) -> NSAttributedString {
    let nsText = source as NSString
    let attributed = NSMutableAttributedString(string: source)
    guard nsText.length > 0 else {
        attributed.addAttributes(markdownIOSTextAttributes(for: style.body), range: NSRange(location: 0, length: 0))
        return attributed
    }

    var cursor = 0
    while cursor < nsText.length {
        let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
        let rawLine = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let roleStyle = markdownIOSRoleStyle(forLine: rawLine, documentStyle: style)
        attributed.addAttributes(markdownIOSTextAttributes(for: roleStyle, line: rawLine), range: lineRange)
        let next = NSMaxRange(lineRange)
        if next <= cursor { break }
        cursor = next
    }
    return attributed
}

private func markdownIOSRoleStyle(at location: Int, in source: String, documentStyle: MarkdownDocumentStyle) -> MarkdownRoleStyle {
    let nsText = source as NSString
    guard nsText.length > 0 else { return documentStyle.body }
    let safeLocation = max(0, min(location, max(0, nsText.length - 1)))
    let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
    let rawLine = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)
    return markdownIOSRoleStyle(forLine: rawLine, documentStyle: documentStyle)
}

private func markdownIOSRoleStyle(forLine line: String, documentStyle: MarkdownDocumentStyle) -> MarkdownRoleStyle {
    if let headingLevel = markdownIOSHeadingLevel(in: line) {
        return documentStyle.headingStyle(level: headingLevel)
    }
    if markdownIOSIsCommentLine(line) {
        return documentStyle.comment
    }
    return documentStyle.body
}

private func markdownIOSHeadingLevel(in line: String) -> Int? {
    var level = 0
    for character in line {
        if character == "#" {
            level += 1
        } else {
            break
        }
    }
    guard level > 0, level <= 6 else { return nil }
    let index = line.index(line.startIndex, offsetBy: level)
    guard index < line.endIndex, line[index] == " " else { return nil }
    return level
}

private func markdownIOSIsCommentLine(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
}

private func markdownIOSLineText(at location: Int, in source: String) -> String {
    let nsText = source as NSString
    guard nsText.length > 0 else { return "" }
    let safeLocation = max(0, min(location, max(0, nsText.length - 1)))
    let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
    return nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)
}

private func markdownIOSTextAttributes(for style: MarkdownRoleStyle, line: String? = nil) -> [NSAttributedString.Key: Any] {
    let font = markdownIOSResolvedFont(name: style.fontName, size: style.fontSize)
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    if let line,
       let prefix = markdownSourceHangingPrefix(in: line) {
        paragraph.firstLineHeadIndent = 0
        paragraph.headIndent = ceil((prefix as NSString).size(withAttributes: [.font: font]).width)
    }
    return [
        .font: font,
        .foregroundColor: UIColor(style.renderedColor),
        .paragraphStyle: paragraph
    ]
}

private func markdownIOSResolvedFont(name: String, size: Double) -> UIFont {
    let pointSize = CGFloat(size)
    if name == appleSystemMonospacedFontName {
        return UIFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
    }
    return UIFont(name: name, size: pointSize) ?? UIFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
}

private func markdownIOSClampedRange(_ range: NSRange, textLength: Int) -> NSRange {
    let location = max(0, min(range.location, textLength))
    let length = max(0, min(range.length, textLength - location))
    return NSRange(location: location, length: length)
}
#endif

#if os(macOS) || os(iOS)

// MARK: - Web渲染块模型 - v2 - 定义块级缓存中的源文本与稳定哈希
struct MarkdownWebBlock {
    let raw: String
    let hash: Int
    let startLine: Int
}

#if os(macOS) || os(iOS)
// MARK: - 双区域滚动同步桥 - v1 - 以源文本行号作为左右区域共同锚点
enum MarkdownDualScrollSource {
    case textKit2
    case web
}

final class MarkdownDualScrollSyncBridge: ObservableObject {
    @Published private(set) var token: Int = 0
    private(set) var source: MarkdownDualScrollSource = .textKit2
    private(set) var sourceLine: Int = 0

    func publish(source: MarkdownDualScrollSource, sourceLine: Int) {
        let clampedLine = max(0, sourceLine)
        if Thread.isMainThread {
            commit(source: source, sourceLine: clampedLine)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.commit(source: source, sourceLine: clampedLine)
            }
        }
    }

    private func commit(source: MarkdownDualScrollSource, sourceLine: Int) {
        self.source = source
        self.sourceLine = sourceLine
        token &+= 1
    }
}
#endif

// MARK: - Web渲染容器 - v2 - 使用固定页面和JS补丁执行只读Web渲染
struct MarkdownWebView {
    let markdownText: String
    let preferredScheme: ColorScheme?
    let documentStyle: MarkdownDocumentStyle
    let scrollSyncBridge: MarkdownDualScrollSyncBridge?
}

#if os(macOS)
extension MarkdownWebView: NSViewRepresentable {
    func makeCoordinator() -> MarkdownWebRenderCoordinator {
        MarkdownWebRenderCoordinator(scrollSyncBridge: scrollSyncBridge)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = context.coordinator.makeWebView()
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.update(
            webView: webView,
            source: markdownText,
            style: documentStyle,
            preferredScheme: preferredScheme,
            scrollSyncBridge: scrollSyncBridge,
            forceBootstrap: true
        )
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.update(
            webView: nsView,
            source: markdownText,
            style: documentStyle,
            preferredScheme: preferredScheme,
            scrollSyncBridge: scrollSyncBridge,
            forceBootstrap: false
        )
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: MarkdownWebRenderCoordinator) {
        coordinator.teardown()
    }
}
#elseif os(iOS)
extension MarkdownWebView: UIViewRepresentable {
    func makeCoordinator() -> MarkdownWebRenderCoordinator {
        MarkdownWebRenderCoordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = context.coordinator.makeWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        context.coordinator.update(
            webView: webView,
            source: markdownText,
            style: documentStyle,
            preferredScheme: preferredScheme,
            scrollSyncBridge: nil,
            forceBootstrap: true
        )
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.update(
            webView: uiView,
            source: markdownText,
            style: documentStyle,
            preferredScheme: preferredScheme,
            scrollSyncBridge: nil,
            forceBootstrap: false
        )
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: MarkdownWebRenderCoordinator) {
        coordinator.teardown()
    }
}
#endif

// MARK: - Web渲染协调器 - v3 - 执行节流解析缓存命中并最小化主线程提交
final class MarkdownWebRenderCoordinator: NSObject {
    private weak var webView: WKWebView?
    private var pendingWorkItem: DispatchWorkItem?
    private var lastSource = ""
    private var cachedBlocks: [MarkdownWebBlock] = []
    private var bootstrapLoaded = false
    private var pendingScript: String?
    private var styleSignature = ""
    private var schemeSignature = ""
    #if os(macOS)
    private weak var scrollSyncBridge: MarkdownDualScrollSyncBridge?
    private var lastAppliedScrollSyncToken: Int = -1

    init(scrollSyncBridge: MarkdownDualScrollSyncBridge? = nil) {
        self.scrollSyncBridge = scrollSyncBridge
        super.init()
    }
    #endif

    func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        #if os(macOS)
        configuration.userContentController.add(self, name: "markdownScrollSync")
        #endif
        let instance = WKWebView(frame: .zero, configuration: configuration)
        self.webView = instance
        return instance
    }

    func teardown() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        #if os(macOS)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "markdownScrollSync")
        #endif
        webView?.navigationDelegate = nil
        webView = nil
    }

    func update(
        webView: WKWebView,
        source: String,
        style: MarkdownDocumentStyle,
        preferredScheme: ColorScheme?,
        scrollSyncBridge: MarkdownDualScrollSyncBridge? = nil,
        forceBootstrap: Bool
    ) {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        self.webView = webView
        #if os(macOS)
        self.scrollSyncBridge = scrollSyncBridge
        applyExternalScrollSyncIfNeeded(on: webView)
        #endif
        let newStyleSignature = markdownWebStyleSignature(style)
        let newSchemeSignature = preferredScheme == .dark ? "dark" : "light"

        if forceBootstrap || !bootstrapLoaded || newStyleSignature != styleSignature || newSchemeSignature != schemeSignature {
            styleSignature = newStyleSignature
            schemeSignature = newSchemeSignature
            bootstrapLoaded = false
            pendingScript = nil
            cachedBlocks = []
            lastSource = ""
            webView.navigationDelegate = self
            webView.loadHTMLString(
                markdownWebBootstrapHTML(style: style, preferredScheme: preferredScheme),
                baseURL: Bundle.main.resourceURL
            )
            MarkdownEditorPerformanceProbe.end(
                "MarkdownWebRenderCoordinator.bootstrap",
                start: profileStart,
                details: "forceBootstrap=\(forceBootstrap),\(MarkdownEditorPerformanceProbe.textDetails(source))"
            )
        }

        guard source != lastSource else {
            MarkdownEditorPerformanceProbe.end(
                "MarkdownWebRenderCoordinator.update.unchanged",
                start: profileStart,
                details: MarkdownEditorPerformanceProbe.textDetails(source)
            )
            return
        }
        pendingWorkItem?.cancel()

        let sourceSnapshot = source
        let blocksSnapshot = cachedBlocks

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let backgroundStart = MarkdownEditorPerformanceProbe.start()
            let nextBlocks = markdownWebRenderBlocks(source: sourceSnapshot, previousBlocks: blocksSnapshot)
            let script = markdownWebBuildPatchScript(previousBlocks: blocksSnapshot, nextBlocks: nextBlocks)
            MarkdownEditorPerformanceProbe.end(
                "MarkdownWebRenderCoordinator.backgroundPatch",
                start: backgroundStart,
                details: "previousBlocks=\(blocksSnapshot.count),nextBlocks=\(nextBlocks.count),\(MarkdownEditorPerformanceProbe.textDetails(sourceSnapshot))"
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let applyStart = MarkdownEditorPerformanceProbe.start()
                self.lastSource = sourceSnapshot
                self.cachedBlocks = nextBlocks
                if self.bootstrapLoaded {
                    webView.evaluateJavaScript(script)
                    #if os(macOS)
                    self.applyExternalScrollSyncIfNeeded(on: webView)
                    #endif
                } else {
                    self.pendingScript = script
                }
                MarkdownEditorPerformanceProbe.end(
                    "MarkdownWebRenderCoordinator.applyPatch",
                    start: applyStart,
                    details: "bootstrapLoaded=\(self.bootstrapLoaded),scriptUtf16=\((script as NSString).length)"
                )
            }
        }

        pendingWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.16, execute: workItem)
        MarkdownEditorPerformanceProbe.end(
            "MarkdownWebRenderCoordinator.update",
            start: profileStart,
            details: MarkdownEditorPerformanceProbe.textDetails(source)
        )
    }
}

extension MarkdownWebRenderCoordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        bootstrapLoaded = true
        if let pendingScript {
            webView.evaluateJavaScript(pendingScript)
            self.pendingScript = nil
        }
        #if os(macOS)
        applyExternalScrollSyncIfNeeded(on: webView)
        #endif
    }
}

#if os(macOS)
extension MarkdownWebRenderCoordinator: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "markdownScrollSync" else { return }
        let line: Int?
        if let number = message.body as? NSNumber {
            line = number.intValue
        } else if let value = message.body as? Int {
            line = value
        } else {
            line = nil
        }
        guard let line else { return }
        scrollSyncBridge?.publish(source: .web, sourceLine: line)
    }

    private func applyExternalScrollSyncIfNeeded(on webView: WKWebView) {
        guard let bridge = scrollSyncBridge,
              bridge.source == .textKit2,
              bridge.token != lastAppliedScrollSyncToken else { return }
        lastAppliedScrollSyncToken = bridge.token
        let line = max(0, bridge.sourceLine)
        webView.evaluateJavaScript("window.markdownRenderer && window.markdownRenderer.scrollToSourceLine && window.markdownRenderer.scrollToSourceLine(\(line));")
    }
}
#endif

// MARK: - Web壳页面生成 - v4 - 生成固定HTML壳并补充高亮样式规范
func markdownWebBootstrapHTML(style: MarkdownDocumentStyle, preferredScheme: ColorScheme?) -> String {
    let background = preferredScheme == .dark ? "#121212" : "#FFFFFF"
    let foreground = markdownWebRoleColor(style.body, preferredScheme: preferredScheme)
    let commentColor = markdownWebRoleColor(style.comment, preferredScheme: preferredScheme)
    let h1Color = markdownWebRoleColor(style.h1, preferredScheme: preferredScheme)
    let h2Color = markdownWebRoleColor(style.h2, preferredScheme: preferredScheme)
    let h3Color = markdownWebRoleColor(style.h3, preferredScheme: preferredScheme)
    let h4Color = markdownWebRoleColor(style.h4, preferredScheme: preferredScheme)
    let h5Color = markdownWebRoleColor(style.h5, preferredScheme: preferredScheme)
    let h6Color = markdownWebRoleColor(style.h6, preferredScheme: preferredScheme)
    let codeBackground = preferredScheme == .dark ? "#232323" : "#F4F4F4"
    let codeColor = preferredScheme == .dark ? "#F3F3F3" : "#222222"

    return """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <style>
      :root { color-scheme: light dark; }
      body { margin: 0; padding: 0; background: \(background); }
      #md-root {
        padding: 18px;
        line-height: 1.65;
        word-break: break-word;
        white-space: normal;
        font-family: \(markdownWebCSSFontFamily(style.body.fontName));
        font-size: \(style.body.fontSize)px;
        color: \(foreground);
      }
      #md-root h1 { font-family: \(markdownWebCSSFontFamily(style.h1.fontName)); font-size: \(style.h1.fontSize)px; color: \(h1Color); }
      #md-root h2 { font-family: \(markdownWebCSSFontFamily(style.h2.fontName)); font-size: \(style.h2.fontSize)px; color: \(h2Color); }
      #md-root h3 { font-family: \(markdownWebCSSFontFamily(style.h3.fontName)); font-size: \(style.h3.fontSize)px; color: \(h3Color); }
      #md-root h4 { font-family: \(markdownWebCSSFontFamily(style.h4.fontName)); font-size: \(style.h4.fontSize)px; color: \(h4Color); }
      #md-root h5 { font-family: \(markdownWebCSSFontFamily(style.h5.fontName)); font-size: \(style.h5.fontSize)px; color: \(h5Color); }
      #md-root h6 { font-family: \(markdownWebCSSFontFamily(style.h6.fontName)); font-size: \(style.h6.fontSize)px; color: \(h6Color); }
      #md-root blockquote {
        margin: 8px 0;
        padding-left: 10px;
        border-left: 3px solid rgba(128,128,128,0.45);
        font-family: \(markdownWebCSSFontFamily(style.comment.fontName));
        font-size: \(style.comment.fontSize)px;
        color: \(commentColor);
      }
      #md-root pre {
        padding: 10px;
        border-radius: 8px;
        overflow-x: auto;
        background: \(codeBackground);
      }
      #md-root code {
        padding: 2px 4px;
        border-radius: 4px;
        background: \(codeBackground);
        color: \(codeColor);
      }
      #md-root .math-inline,
      #md-root .math-display {
        font-size: 1em;
      }
      #md-root img { max-width: 100%; height: auto; }
      #md-root .md-preserved-numbered {
        margin: 0.25em 0;
        white-space: normal;
      }
      #md-root .md-preserved-marker {
        display: inline-block;
        min-width: 2.2em;
        color: inherit;
      }
      #md-root mark {
        background: #F0C847;
        border-radius: 8px;
        padding: 0 0.2em;
        color: inherit;
      }
      #md-root strong,
      #md-root b {
        font-weight: 700;
      }
      </style>
      \(markdownWebInlineKaTeXStyleTag())
      \(markdownWebScriptTag(fileName: "katex.min.js"))
      \(markdownWebScriptTag(fileName: "auto-render.min.js"))
      \(markdownWebScriptTag(fileName: "marked.min.js"))
      \(markdownWebScriptTag(fileName: "markdown-renderer.js"))
    </head>
    <body><div id="md-root"></div></body>
    </html>
    """
}

// MARK: - Web样式签名 - v1 - 生成样式配置签名用于判断是否需要重建壳页面
func markdownWebStyleSignature(_ style: MarkdownDocumentStyle) -> String {
    [
        style.h1.fontName, "\(style.h1.fontSize)", markdownWebRoleColorSignature(style.h1),
        style.h2.fontName, "\(style.h2.fontSize)", markdownWebRoleColorSignature(style.h2),
        style.h3.fontName, "\(style.h3.fontSize)", markdownWebRoleColorSignature(style.h3),
        style.h4.fontName, "\(style.h4.fontSize)", markdownWebRoleColorSignature(style.h4),
        style.h5.fontName, "\(style.h5.fontSize)", markdownWebRoleColorSignature(style.h5),
        style.h6.fontName, "\(style.h6.fontSize)", markdownWebRoleColorSignature(style.h6),
        style.body.fontName, "\(style.body.fontSize)", markdownWebRoleColorSignature(style.body),
        style.comment.fontName, "\(style.comment.fontSize)", markdownWebRoleColorSignature(style.comment)
    ].joined(separator: "|")
}

// MARK: - Web块渲染器 - v2 - 基于块级缓存与邻接重算生成Markdown块列表
func markdownWebRenderBlocks(source: String, previousBlocks: [MarkdownWebBlock]) -> [MarkdownWebBlock] {
    let profileStart = MarkdownEditorPerformanceProbe.start()
    let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
    let sourceBlocks = normalized.components(separatedBy: "\n\n")
    var sourceBlockStartLines: [Int] = []
    sourceBlockStartLines.reserveCapacity(sourceBlocks.count)
    var lineCursor = 0
    for block in sourceBlocks {
        sourceBlockStartLines.append(lineCursor)
        lineCursor += block.reduce(0) { $1 == "\n" ? $0 + 1 : $0 } + 2
    }

    var changedIndexes = Set<Int>()
    let commonCount = min(sourceBlocks.count, previousBlocks.count)
    for index in 0..<commonCount where sourceBlocks[index] != previousBlocks[index].raw {
        changedIndexes.insert(index)
    }
    if sourceBlocks.count != previousBlocks.count {
        for index in commonCount..<sourceBlocks.count {
            changedIndexes.insert(index)
        }
    }
    let baseChanged = changedIndexes
    for index in baseChanged {
        if index > 0 { changedIndexes.insert(index - 1) }
        if index + 1 < sourceBlocks.count { changedIndexes.insert(index + 1) }
    }

    var result: [MarkdownWebBlock] = []
    result.reserveCapacity(sourceBlocks.count)
    for index in sourceBlocks.indices {
        if index < previousBlocks.count, !changedIndexes.contains(index), sourceBlocks[index] == previousBlocks[index].raw {
            result.append(MarkdownWebBlock(
                raw: previousBlocks[index].raw,
                hash: previousBlocks[index].hash,
                startLine: sourceBlockStartLines[index]
            ))
        } else {
            let blockRaw = sourceBlocks[index]
            result.append(MarkdownWebBlock(raw: blockRaw, hash: blockRaw.hashValue, startLine: sourceBlockStartLines[index]))
        }
    }
    MarkdownEditorPerformanceProbe.end(
        "markdownWebRenderBlocks",
        start: profileStart,
        details: "previousBlocks=\(previousBlocks.count),nextBlocks=\(result.count),changed=\(changedIndexes.count),\(MarkdownEditorPerformanceProbe.textDetails(source))"
    )
    return result
}

// MARK: - Web补丁脚本生成 - v2 - 构建仅包含变更块的Markdown补丁提交语句
func markdownWebBuildPatchScript(previousBlocks: [MarkdownWebBlock], nextBlocks: [MarkdownWebBlock]) -> String {
    let profileStart = MarkdownEditorPerformanceProbe.start()
    var patches: [[String: Any]] = []
    for index in nextBlocks.indices {
        if index < previousBlocks.count,
           previousBlocks[index].hash == nextBlocks[index].hash,
           previousBlocks[index].startLine == nextBlocks[index].startLine {
            continue
        }
        patches.append([
            "index": index,
            "hash": "\(nextBlocks[index].hash)",
            "startLine": nextBlocks[index].startLine,
            "markdown": nextBlocks[index].raw
        ])
    }
    let data = (try? JSONSerialization.data(withJSONObject: patches, options: [])) ?? Data("[]".utf8)
    let json = String(decoding: data, as: UTF8.self)
    let script = "window.markdownRenderer.apply(\(nextBlocks.count), \(json));"
    MarkdownEditorPerformanceProbe.end(
        "markdownWebBuildPatchScript",
        start: profileStart,
        details: "patches=\(patches.count),scriptUtf16=\((script as NSString).length)"
    )
    return script
}

// MARK: - Web资源定位 - v2 - 同时兼容扁平资源与MarkdownAssets目录资源结构
func markdownWebAssetURL(fileName: String) -> URL? {
    let bundle = Bundle.main
    let parts = fileName.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let base = String(parts.first ?? "")
    let ext = parts.count > 1 ? String(parts[1]) : nil

    if let ext, let direct = bundle.url(forResource: base, withExtension: ext) {
        return direct
    }
    if let resourceURL = bundle.resourceURL {
        let nested = resourceURL
            .appendingPathComponent("MarkdownAssets", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: nested.path) {
            return nested
        }
    }
    return nil
}

// MARK: - Web脚本标签 - v1 - 生成安全的本地脚本标签并避免Swift多行字符串中的JS语法风险
func markdownWebScriptTag(fileName: String) -> String {
    guard let url = markdownWebAssetURL(fileName: fileName) else { return "" }
    return "<script src=\"\(url.absoluteString)\"></script>"
}

// MARK: - Web公式样式标签 - v1 - 读取KaTeX样式并修正字体目录映射后内联注入
func markdownWebInlineKaTeXStyleTag() -> String {
    guard
        let cssURL = markdownWebAssetURL(fileName: "katex.min.css"),
        var css = try? String(contentsOf: cssURL, encoding: .utf8)
    else { return "" }

    if markdownWebAssetURL(fileName: "KaTeX_Main-Regular.woff2") != nil {
        css = css.replacingOccurrences(of: "url(fonts/", with: "url(")
        css = css.replacingOccurrences(of: "url('./fonts/", with: "url('")
        css = css.replacingOccurrences(of: "url(\"fonts/", with: "url(\"")
        css = css.replacingOccurrences(of: "url(\"./fonts/", with: "url(\"")
    }
    return "<style>\(css)</style>"
}

func markdownWebCSSFontFamily(_ fontName: String) -> String {
    if fontName == appleSystemMonospacedFontName {
        return "\"SF Mono\", Menlo, Monaco, \"Courier New\", monospace"
    }

    let escaped = fontName
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\", -apple-system, \"PingFang SC\", \"Hiragino Sans GB\", \"Microsoft YaHei\", sans-serif"
}

func markdownWebColorHex(_ color: Color) -> String {
    #if os(macOS)
    let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
    #elseif os(iOS)
    let resolved = UIColor(color)
    #endif

    var red: CGFloat = 1
    var green: CGFloat = 1
    var blue: CGFloat = 1
    var alpha: CGFloat = 1
    resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
}

func markdownWebRoleColor(_ style: MarkdownRoleStyle, preferredScheme: ColorScheme?) -> String {
    if style.semanticColor == .adaptiveBlackWhite {
        return preferredScheme == .dark ? "#FFFFFF" : "#000000"
    }
    return markdownWebColorHex(style.color)
}

func markdownWebRoleColorSignature(_ style: MarkdownRoleStyle) -> String {
    if style.semanticColor == .adaptiveBlackWhite {
        return "adaptive-bw"
    }
    return markdownWebColorHex(style.color)
}

#endif

#if os(macOS)

// MARK: - 窗口标题设置器 - v1 - 同步更新独立窗口标题为Markdown文件名
struct WindowTitleSetter: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            view.window?.title = title
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.title = title
        }
    }
}

// MARK: - 高亮模式枚举 - v2 - 定义源码与即时渲染共用的Markdown富文本模式
enum MarkdownHighlightMode: Equatable {
    case source(MarkdownDocumentStyle)
    case instant(MarkdownDocumentStyle)
}

// MARK: - TextKit2纯文本编辑器 - v1 - 建立200k文档输入性能基线
struct MarkdownTextKit2PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var targetUTF16Offset: Int?
    var workingDirectoryURL: URL?
    var documentStyle: MarkdownDocumentStyle = MarkdownDocumentStyle()
    var quickInputSettings: MarkdownQuickInputSettings = .init()
    var searchQuery: String = ""
    var activeSearchRange: NSRange?
    var scrollSyncBridge: MarkdownDualScrollSyncBridge?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 36, right: 0)
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textLayoutManager = NSTextLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 4
        textLayoutManager.textContainer = textContainer

        let textContentStorage = NSTextContentStorage()
        textContentStorage.addTextLayoutManager(textLayoutManager)

        let textView = MarkdownTextKit2PlainTextView(frame: .zero, textContainer: textContainer)
        textView.font = markdownResolvedFont(name: appleSystemMonospacedFontName, size: 15)
        textView.textColor = .labelColor
        textView.isRichText = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = context.coordinator
        textView.string = text
        textView.workingDirectoryURL = workingDirectoryURL
        textView.quickInputSettings = quickInputSettings
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.textContentStorage = textContentStorage
        context.coordinator.textLayoutManager = textLayoutManager
        context.coordinator.textContainer = textContainer
        context.coordinator.resetClipViewBoundsOrigin(scrollView.contentView.bounds.origin)
        context.coordinator.lastSourceSnapshot = text
        context.coordinator.lastObservedBindingText = text
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        textView.applyMarkdownStyleVisibleFirst(style: documentStyle)
        textView.updateSearchHighlights(query: searchQuery, activeRange: activeSearchRange)
        context.coordinator.lastSearchQuery = searchQuery
        context.coordinator.lastSearchActiveRange = activeSearchRange

        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextKit2PlainTextEditor.makeNSView",
            start: profileStart,
            details: MarkdownEditorPerformanceProbe.textDetails(text)
        )
        return scrollView
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.flushPendingBindingSync()
        NotificationCenter.default.removeObserver(coordinator)
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.parent = self

        if textView.quickInputSettings != quickInputSettings {
            textView.quickInputSettings = quickInputSettings
        }
        textView.workingDirectoryURL = workingDirectoryURL

        let bindingChangedExternally = text != context.coordinator.lastObservedBindingText
        if bindingChangedExternally, text != context.coordinator.lastSourceSnapshot {
            let syncStart = MarkdownEditorPerformanceProbe.start()
            context.coordinator.cancelPendingBindingSync()
            let selectedRange = textView.selectedRange()
            textView.string = text
            context.coordinator.lastSourceSnapshot = text
            let maxLocation = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selectedRange.location, maxLocation), length: 0))
            textView.applyMarkdownStyleVisibleFirst(style: documentStyle)
            MarkdownEditorPerformanceProbe.end(
                "MarkdownTextKit2PlainTextEditor.updateNSView.externalTextSync",
                start: syncStart,
                details: MarkdownEditorPerformanceProbe.textDetails(text)
            )
        }
        context.coordinator.lastObservedBindingText = text

        if context.coordinator.documentStyle != documentStyle {
            let styleStart = MarkdownEditorPerformanceProbe.start()
            context.coordinator.documentStyle = documentStyle
            textView.applyMarkdownStyleVisibleFirst(style: documentStyle)
            MarkdownEditorPerformanceProbe.end(
                "MarkdownTextKit2PlainTextEditor.updateNSView.documentStyle",
                start: styleStart,
                details: MarkdownEditorPerformanceProbe.textDetails(textView.string)
            )
        }

        if context.coordinator.lastSearchQuery != searchQuery || context.coordinator.lastSearchActiveRange != activeSearchRange {
            let searchStart = MarkdownEditorPerformanceProbe.start()
            textView.updateSearchHighlights(query: searchQuery, activeRange: activeSearchRange)
            context.coordinator.lastSearchQuery = searchQuery
            context.coordinator.lastSearchActiveRange = activeSearchRange
            MarkdownEditorPerformanceProbe.end(
                "MarkdownTextKit2PlainTextEditor.updateNSView.searchHighlights",
                start: searchStart,
                details: "queryLength=\((searchQuery as NSString).length),\(MarkdownEditorPerformanceProbe.textDetails(textView.string))"
            )
        }

        if let offset = targetUTF16Offset {
            if context.coordinator.lastConsumedTargetOffset != offset {
                let jumpStart = MarkdownEditorPerformanceProbe.start()
                let location = min(max(offset, 0), (textView.string as NSString).length)
                textView.setSelectedRange(NSRange(location: location, length: 0))
                textView.scrollRangeToVisible(NSRange(location: location, length: 0))
                context.coordinator.lastConsumedTargetOffset = offset
                MarkdownEditorPerformanceProbe.end(
                    "MarkdownTextKit2PlainTextEditor.updateNSView.jumpToOffset",
                    start: jumpStart,
                    details: "offset=\(offset),location=\(location)"
                )
            }
        } else {
            context.coordinator.lastConsumedTargetOffset = nil
        }

        context.coordinator.applyExternalScrollSyncIfNeeded()

        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextKit2PlainTextEditor.updateNSView",
            start: profileStart,
            details: MarkdownEditorPerformanceProbe.textDetails(textView.string)
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextKit2PlainTextEditor
        weak var textView: MarkdownTextKit2PlainTextView?
        weak var scrollView: NSScrollView?
        var textContentStorage: NSTextContentStorage?
        var textLayoutManager: NSTextLayoutManager?
        var textContainer: NSTextContainer?
        var lastConsumedTargetOffset: Int?
        var pendingEditedRange: NSRange?
        var documentStyle: MarkdownDocumentStyle
        var lastSourceSnapshot = ""
        var lastObservedBindingText = ""
        var lastSearchQuery = ""
        var lastSearchActiveRange: NSRange?
        private var scrollRenderWorkItem: DispatchWorkItem?
        private var scrollSyncWorkItem: DispatchWorkItem?
        private var typingScrollSyncWorkItem: DispatchWorkItem?
        private var lastAppliedScrollSyncToken: Int = -1
        private var suppressScrollSyncUntil = Date.distantPast
        private var pendingBindingSourceText: String?
        private var pendingBindingNeedsTextViewSnapshot = false
        private var pendingBindingWorkItem: DispatchWorkItem?
        private var lastClipViewBoundsOrigin: NSPoint?
        private var pendingDeletionLog = "none"
        private var pendingDeletionKind: EditorDeletionKind = .none
        private var pendingEditIsLocalCharacter = false

        init(_ parent: MarkdownTextKit2PlainTextEditor) {
            self.parent = parent
            self.documentStyle = parent.documentStyle
        }

        func resetClipViewBoundsOrigin(_ origin: NSPoint) {
            lastClipViewBoundsOrigin = origin
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            let replacement = replacementString ?? ""
            let replacementLength = (replacement as NSString).length
            pendingEditedRange = NSRange(location: affectedCharRange.location, length: replacementLength)
            let source = textView.textStorage?.mutableString ?? NSMutableString(string: textView.string)
            let safeAffectedRange = NSIntersectionRange(
                affectedCharRange,
                NSRange(location: 0, length: source.length)
            )
            let deletesLineBreak = safeAffectedRange.length > 0
                && (source.range(of: "\n", options: [], range: safeAffectedRange).location != NSNotFound
                    || source.range(of: "\r", options: [], range: safeAffectedRange).location != NSNotFound)
            pendingEditIsLocalCharacter = !replacement.contains("\n")
                && !replacement.contains("\r")
                && !deletesLineBreak
            if (replacementString ?? "").isEmpty, affectedCharRange.length > 0 {
                let diagnosis = EditorDeletionClassifier.diagnoseDeletion(
                    source: textView.string as NSString,
                    affectedRange: affectedCharRange,
                    protectedPrefixLengthForLine: markdownProtectedPrefixLengthForDeletion
                )
                pendingDeletionLog = diagnosis.logSummary
                pendingDeletionKind = diagnosis.kind
            } else {
                pendingDeletionLog = "none"
                pendingDeletionKind = .none
            }
            if let markdownTextView = textView as? MarkdownTextKit2PlainTextView {
                markdownTextView.prepareTypingAttributesIfNeeded(at: affectedCharRange.location)
                markdownTextView.prepareCachesForTextEdit(
                    affectedRange: affectedCharRange,
                    replacementString: replacementString
                )
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            let profileStart = MarkdownEditorPerformanceProbe.start()
            guard let textView else { return }
            guard !textView.isApplyingQuickInputReplacement else { return }
            guard !textView.isApplyingMarkdownStyle else { return }
            guard !textView.isRestoringAttachmentSource else { return }
            if textView.hasActiveMarkedText {
                pendingEditIsLocalCharacter = false
                textView.prepareTypingAttributesIfNeeded(at: textView.selectedRange().location)
                textView.keepInsertionPointComfortablyVisible()
                scheduleCenterLinePublish(delay: 3.0)
                MarkdownEditorPerformanceProbe.end(
                    "MarkdownTextKit2PlainTextEditor.textDidChange.markedText",
                    start: profileStart,
                    details: "\(MarkdownEditorPerformanceProbe.textDetails(textView.string)),deletion=\(pendingDeletionLog)"
                )
                pendingDeletionLog = "none"
                pendingDeletionKind = .none
                return
            }
            let quickInputStart = MarkdownEditorPerformanceProbe.start()
            if textView.applyQuickInputIfNeeded() {
                pendingEditedRange = textView.selectedRange()
            }
            MarkdownEditorPerformanceProbe.end(
                "MarkdownTextKit2PlainTextEditor.textDidChange.quickInput",
                start: quickInputStart,
                details: MarkdownEditorPerformanceProbe.textDetails(textView.string)
            )
            let usesInlineDeletionFastPath = pendingDeletionKind == .inlineCharacter
            scheduleBindingSyncFromTextView(delay: pendingEditIsLocalCharacter ? 0.35 : 0.10)
            let styleStart = MarkdownEditorPerformanceProbe.start()
            let editedRange = pendingEditedRange ?? textView.selectedRange()
            if usesInlineDeletionFastPath {
                MarkdownEditorPerformanceProbe.end(
                    "MarkdownTextKit2PlainTextEditor.textDidChange.inlineDeletionStyleSkipped",
                    start: styleStart,
                    details: pendingDeletionLog
                )
            } else if pendingEditIsLocalCharacter {
                textView.applyMarkdownStyleToEditedLine(for: editedRange, style: documentStyle)
            } else {
                textView.applyMarkdownStyleIncrementally(for: editedRange, style: documentStyle)
            }
            textView.prepareTypingAttributesIfNeeded(at: textView.selectedRange().location)
            textView.keepInsertionPointComfortablyVisible()
            scheduleCenterLinePublish(delay: 3.0)
            pendingEditedRange = nil
            MarkdownEditorPerformanceProbe.end(
                "MarkdownTextKit2PlainTextEditor.textDidChange.incrementalMarkdownStyle",
                start: styleStart,
                details: MarkdownEditorPerformanceProbe.textDetails(textView.string)
            )
            MarkdownEditorPerformanceProbe.end(
                "MarkdownTextKit2PlainTextEditor.textDidChange",
                start: profileStart,
                details: "\(MarkdownEditorPerformanceProbe.textDetails(textView.string)),deletion=\(pendingDeletionLog)"
            )
            MarkdownEditorPerformanceProbe.metric(
                "TextKit2.input",
                start: profileStart,
                budgetMs: 16,
                textLength: (textView.string as NSString).length,
                details: "edited={\(editedRange.location),\(editedRange.length)},deletion=\(pendingDeletionLog)"
            )
            pendingDeletionLog = "none"
            pendingDeletionKind = .none
            pendingEditIsLocalCharacter = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            if textView.restoreAttachmentSourceTokensForSelectedLine() {
                pendingEditedRange = textView.selectedRange()
                scheduleBindingSyncFromTextView(delay: 0.05)
            }
            textView.prepareTypingAttributesIfNeeded(at: textView.selectedRange().location)
        }

        func syncBindingImmediately(_ sourceText: String) {
            let profileStart = MarkdownEditorPerformanceProbe.start()
            pendingBindingWorkItem?.cancel()
            pendingBindingWorkItem = nil
            pendingBindingSourceText = nil
            pendingBindingNeedsTextViewSnapshot = false
            parent.text = sourceText
            lastObservedBindingText = sourceText
            MarkdownEditorPerformanceProbe.metric(
                "TextKit2.bindingImmediate",
                start: profileStart,
                budgetMs: 8,
                textLength: (sourceText as NSString).length
            )
        }

        func scheduleBindingSyncFromTextView(delay: TimeInterval) {
            pendingBindingSourceText = nil
            pendingBindingNeedsTextViewSnapshot = true
            scheduleBindingWork(delay: delay)
        }

        func scheduleBindingSync(_ sourceText: String, delay: TimeInterval) {
            pendingBindingSourceText = sourceText
            pendingBindingNeedsTextViewSnapshot = false
            scheduleBindingWork(delay: delay)
        }

        private func scheduleBindingWork(delay: TimeInterval) {
            pendingBindingWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.flushPendingBindingSync()
            }
            pendingBindingWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        func flushPendingBindingSync() {
            let profileStart = MarkdownEditorPerformanceProbe.start()
            pendingBindingWorkItem?.cancel()
            pendingBindingWorkItem = nil
            let sourceText: String?
            if let pendingBindingSourceText {
                sourceText = pendingBindingSourceText
            } else if pendingBindingNeedsTextViewSnapshot, let textView {
                sourceText = textView.markdownSourceStringPreservingAttachments()
            } else {
                sourceText = nil
            }
            pendingBindingSourceText = nil
            pendingBindingNeedsTextViewSnapshot = false
            guard let sourceText else { return }
            lastSourceSnapshot = sourceText
            parent.text = sourceText
            lastObservedBindingText = sourceText
            MarkdownEditorPerformanceProbe.metric(
                "TextKit2.bindingFlush",
                start: profileStart,
                budgetMs: 8,
                textLength: (sourceText as NSString).length
            )
        }

        func cancelPendingBindingSync() {
            pendingBindingWorkItem?.cancel()
            pendingBindingWorkItem = nil
            pendingBindingSourceText = nil
            pendingBindingNeedsTextViewSnapshot = false
        }

        @objc func clipViewBoundsDidChange(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView else { return }
            let currentOrigin = clipView.bounds.origin
            if let lastClipViewBoundsOrigin,
               abs(lastClipViewBoundsOrigin.x - currentOrigin.x) < 0.5,
               abs(lastClipViewBoundsOrigin.y - currentOrigin.y) < 0.5 {
                return
            }
            lastClipViewBoundsOrigin = currentOrigin
            scrollRenderWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, let textView = self.textView else { return }
                guard !textView.isApplyingMarkdownStyle,
                      !textView.isApplyingQuickInputReplacement,
                      !textView.isRestoringAttachmentSource else { return }
                textView.applyMarkdownStyleToVisibleRange(style: self.documentStyle)
                textView.applySearchHighlightsToVisibleRange(query: self.lastSearchQuery, activeRange: self.lastSearchActiveRange)
                self.scheduleCenterLinePublish(delay: 0.18)
            }
            scrollRenderWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: workItem)
        }

        func applyExternalScrollSyncIfNeeded() {
            guard let bridge = parent.scrollSyncBridge,
                  bridge.source == .web,
                  bridge.token != lastAppliedScrollSyncToken,
                  let textView,
                  let scrollView else { return }
            lastAppliedScrollSyncToken = bridge.token
            suppressScrollSyncUntil = Date().addingTimeInterval(0.55)
            textView.scrollMarkdownSourceLineToCenter(bridge.sourceLine, in: scrollView)
        }

        func scheduleCenterLinePublish(delay: TimeInterval) {
            guard parent.scrollSyncBridge != nil else { return }
            scrollSyncWorkItem?.cancel()
            typingScrollSyncWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.publishCenterLine()
            }
            if delay >= 3.0 {
                typingScrollSyncWorkItem = workItem
            } else {
                scrollSyncWorkItem = workItem
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        private func publishCenterLine() {
            guard let bridge = parent.scrollSyncBridge,
                  let textView,
                  let scrollView,
                  Date() >= suppressScrollSyncUntil else { return }
            let line = textView.markdownSourceLineIndexAtVisibleCenter(in: scrollView)
            bridge.publish(source: .textKit2, sourceLine: line)
        }

        deinit {
            cancelPendingBindingSync()
            scrollRenderWorkItem?.cancel()
            scrollSyncWorkItem?.cancel()
            typingScrollSyncWorkItem?.cancel()
        }
    }
}

final class MarkdownTextKit2PlainTextView: NSTextView {
    private enum MarkdownBlockKind {
        case heading
        case comment
        case list
        case quote
        case codeFence
        case mathBlock
        case htmlBlock
        case paragraph
    }

    func markdownSourceLineIndexAtVisibleCenter(in scrollView: NSScrollView) -> Int {
        let clipView = scrollView.contentView
        let clipCenter = NSPoint(x: clipView.bounds.midX, y: clipView.bounds.midY)
        let localPoint = convert(clipCenter, from: clipView)
        let characterIndex = max(0, min((string as NSString).length, characterIndexForInsertion(at: localPoint)))
        return markdownSourceLineIndex(containing: characterIndex)
    }

    func scrollMarkdownSourceLineToCenter(_ sourceLine: Int, in scrollView: NSScrollView) {
        let nsText = string as NSString
        guard nsText.length > 0 else { return }
        let lineRange = markdownSourceRange(forLine: max(0, sourceLine), in: nsText)
        guard lineRange.location != NSNotFound else { return }

        scrollRangeToVisible(NSRange(location: lineRange.location, length: 0))
        guard let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        var actualRange = NSRange(location: 0, length: 0)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: lineRange.location, length: min(1, max(0, nsText.length - lineRange.location))),
            actualCharacterRange: &actualRange
        )
        guard glyphRange.location != NSNotFound else { return }
        var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        lineRect.origin.x += textContainerOrigin.x
        lineRect.origin.y += textContainerOrigin.y

        let clipView = scrollView.contentView
        let maxY = max(0, bounds.height - clipView.bounds.height)
        let targetY = max(0, min(lineRect.midY - clipView.bounds.height * 0.5, maxY))
        clipView.setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func markdownSourceLineIndex(containing location: Int) -> Int {
        let nsText = string as NSString
        guard nsText.length > 0 else { return 0 }
        let safeLocation = max(0, min(location, nsText.length))
        var lineIndex = 0
        var cursor = 0
        while cursor < safeLocation {
            let range = nsText.lineRange(for: NSRange(location: cursor, length: 0))
            let next = NSMaxRange(range)
            if next > safeLocation { break }
            lineIndex += 1
            if next <= cursor { break }
            cursor = next
        }
        return lineIndex
    }

    private func markdownSourceRange(forLine targetLine: Int, in nsText: NSString) -> NSRange {
        var lineIndex = 0
        var cursor = 0
        while cursor < nsText.length {
            let range = nsText.lineRange(for: NSRange(location: cursor, length: 0))
            if lineIndex == targetLine {
                return range
            }
            let next = NSMaxRange(range)
            if next <= cursor { break }
            cursor = next
            lineIndex += 1
        }
        return NSRange(location: nsText.length, length: 0)
    }

    private struct MarkdownBlock {
        var kind: MarkdownBlockKind
        var range: NSRange
    }

    private struct MarkdownStyleLayer: OptionSet {
        let rawValue: Int

        static let block = MarkdownStyleLayer(rawValue: 1 << 0)
        static let inline = MarkdownStyleLayer(rawValue: 1 << 1)
        static let attachment = MarkdownStyleLayer(rawValue: 1 << 2)
        static let all: MarkdownStyleLayer = [.block, .inline, .attachment]
    }

    var workingDirectoryURL: URL?
    var quickInputSettings = MarkdownQuickInputSettings()
    var isApplyingQuickInputReplacement = false
    var isApplyingMarkdownStyle = false
    var isRestoringAttachmentSource = false
    private var lineRangeCache: [NSRange] = []
    private var cachedStringLength = -1
    private var markdownBlockCache: [Int: MarkdownBlock] = [:]
    private var currentDocumentStyle: MarkdownDocumentStyle?
    private var searchHighlightRanges: [NSRange] = []
    private var searchActiveRange: NSRange?
    private var currentSearchQuery = ""
    private var currentSearchActiveRange: NSRange?
    private var searchHighlightGeneration = 0
    private var pendingSearchHighlightWorkItem: DispatchWorkItem?
    private var idleStyleGeneration = 0
    private var pendingIdleStyleWorkItem: DispatchWorkItem?
    private var attachmentStyleGeneration = 0
    private var pendingAttachmentStyleWorkItem: DispatchWorkItem?
    private var pendingAttachmentLineRanges: [Int: NSRange] = [:]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleMarkdownImagePasteShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleMarkdownImagePasteShortcut(event) { return }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        if insertPastedMarkdownImageIfAvailable() { return }
        super.paste(sender)
    }

    private func handleMarkdownImagePasteShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.shift),
              !flags.contains(.option),
              !flags.contains(.control),
              event.charactersIgnoringModifiers?.lowercased() == "v" else {
            return false
        }
        return insertPastedMarkdownImageIfAvailable()
    }

    private func insertPastedMarkdownImageIfAvailable() -> Bool {
        guard NodeMarkdownImageAssetService.hasPastedImage(),
              let markdownDirectoryURL = workingDirectoryURL,
              let selectedURL = NodeMarkdownImageAssetService.pastedImageURL() else {
            return false
        }
        let removesTemporaryImage = NodeMarkdownImageAssetService.isTemporaryPastedImageURL(selectedURL)
        defer {
            if removesTemporaryImage { try? FileManager.default.removeItem(at: selectedURL) }
        }
        guard let insertion = NodeMarkdownImageAssetService.insertMarkdownImage(
            selectedURL: selectedURL,
            markdownDirectoryURL: markdownDirectoryURL
        ) else {
            NSSound.beep()
            return true
        }
        _ = restoreAttachmentSourceTokensForSelectedLine()
        insertText(insertion.htmlSnippet, replacementRange: selectedRange())
        return true
    }

    deinit {
        cancelIdleMarkdownStyleCompletion()
        cancelPendingAttachmentStyleWork()
        cancelPendingSearchHighlightWork()
    }

    func restoreAttachmentSourceTokensForSelectedLine() -> Bool {
        guard let textStorage else { return false }
        let nsText = textStorage.string as NSString
        guard nsText.length > 0 else { return false }
        let selection = selectedRange()
        let safeLocation = max(0, min(selection.location, nsText.length))
        let anchor = safeLocation == nsText.length ? max(0, nsText.length - 1) : safeLocation
        let lineRange = nsText.lineRange(for: NSRange(location: anchor, length: 0))
        let restored = restoreAttachmentSourceTokens(in: lineRange)
        if restored {
            invalidateLineRangeCache()
            setSelectedRange(NSRange(location: min(safeLocation, (string as NSString).length), length: 0))
        }
        return restored
    }

    private func restoreAttachmentSourceTokens(in lineRange: NSRange) -> Bool {
        guard let textStorage else { return false }
        var replacements: [(range: NSRange, token: String)] = []
        textStorage.enumerateAttribute(
            markdownTextKit2AttachmentSourceTokenKey,
            in: NSIntersectionRange(lineRange, NSRange(location: 0, length: textStorage.length)),
            options: []
        ) { value, range, _ in
            guard let token = value as? String,
                  range.length > 0,
                  textStorage.attribute(.attachment, at: range.location, effectiveRange: nil) != nil else {
                return
            }
            replacements.append((range, token))
        }
        guard !replacements.isEmpty else { return false }
        isRestoringAttachmentSource = true
        textStorage.beginEditing()
        for replacement in replacements.reversed() {
            textStorage.replaceCharacters(in: replacement.range, with: replacement.token)
        }
        textStorage.endEditing()
        isRestoringAttachmentSource = false
        return true
    }

    func invalidateLineRangeCache() {
        cachedStringLength = -1
        markdownBlockCache.removeAll(keepingCapacity: true)
        pendingAttachmentLineRanges.removeAll(keepingCapacity: true)
        cancelIdleMarkdownStyleCompletion()
        cancelPendingAttachmentStyleWork()
        cancelPendingSearchHighlightWork()
    }

    func prepareCachesForTextEdit(affectedRange: NSRange, replacementString: String?) {
        guard let nsText = textStorage?.mutableString else { return }
        let replacement = replacementString ?? ""
        let impact: EditorDeletionImpact
        if replacement.isEmpty, affectedRange.length > 0 {
            impact = EditorDeletionClassifier.classifyDeletion(
                source: nsText,
                affectedRange: affectedRange
            ) { line in
                parseNumberedLine(in: line)?.markerLength ?? 0
            }
        } else if replacement.contains("\n") || replacement.contains("\r") || affectedRange.length > 0 {
            impact = .line
        } else {
            impact = .character
        }

        switch impact {
        case .character:
            invalidateLocalMarkdownCaches(around: affectedRange)
        case .line, .structure, .document:
            invalidateLineRangeCache()
        }
    }

    private func invalidateLocalMarkdownCaches(around affectedRange: NSRange) {
        guard let nsText = textStorage?.mutableString else { return }
        guard nsText.length > 0 else {
            markdownBlockCache.removeAll(keepingCapacity: true)
            pendingAttachmentLineRanges.removeAll(keepingCapacity: true)
            return
        }
        let safeLocation = max(0, min(affectedRange.location, nsText.length - 1))
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
        markdownBlockCache.removeValue(forKey: lineRange.location)
        pendingAttachmentLineRanges.removeValue(forKey: lineRange.location)
    }

    func applyMarkdownStyleToEntireDocument(style: MarkdownDocumentStyle) {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        guard let textStorage else { return }
        cancelIdleMarkdownStyleCompletion()
        currentDocumentStyle = style
        rebuildLineRangeCache()
        let fullRange = NSRange(location: 0, length: textStorage.length)
        applyMarkdownStyle(in: fullRange, style: style)
        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextKit2PlainTextView.applyMarkdownStyleToEntireDocument",
            start: profileStart,
            details: MarkdownEditorPerformanceProbe.rangeDetails(fullRange, textLength: textStorage.length)
        )
    }

    func applyMarkdownStyleVisibleFirst(style: MarkdownDocumentStyle) {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        guard let textStorage else { return }
        cancelIdleMarkdownStyleCompletion()
        currentDocumentStyle = style
        rebuildLineRangeCache()
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let visibleRange = NSIntersectionRange(selectedNeighborhoodRange(), fullRange)
        if visibleRange.length > 0 {
            applyMarkdownStyle(in: expandedLineRange(for: visibleRange), style: style)
        } else if fullRange.length <= 20_000 {
            applyMarkdownStyle(in: fullRange, style: style)
        }
        scheduleIdleMarkdownStyleCompletion(style: style, skipping: visibleRange)
        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextKit2PlainTextView.applyMarkdownStyleVisibleFirst",
            start: profileStart,
            details: "visible={\(visibleRange.location),\(visibleRange.length)},utf16=\(textStorage.length)"
        )
    }

    func applyMarkdownStyleToVisibleRange(style: MarkdownDocumentStyle) {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        guard let textStorage else { return }
        currentDocumentStyle = style
        rebuildLineRangeCacheIfNeeded()
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let visibleRange = NSIntersectionRange(visibleCharacterRange() ?? selectedNeighborhoodRange(), fullRange)
        guard visibleRange.length > 0 else { return }
        applyMarkdownStyle(in: expandedLineRange(for: visibleRange), style: style)
        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextKit2PlainTextView.applyMarkdownStyleToVisibleRange",
            start: profileStart,
            details: "visible={\(visibleRange.location),\(visibleRange.length)},utf16=\(textStorage.length)"
        )
        MarkdownEditorPerformanceProbe.metric(
            "TextKit2.scrollVisibleStyle",
            start: profileStart,
            budgetMs: 16,
            textLength: textStorage.length,
            details: "visible={\(visibleRange.location),\(visibleRange.length)}"
        )
    }

    func applyMarkdownStyleIncrementally(for editedRange: NSRange, style: MarkdownDocumentStyle) {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        guard let textStorage else { return }
        currentDocumentStyle = style
        let totalLength = textStorage.length
        let safeLocation = max(0, min(editedRange.location, totalLength))
        let safeLength = max(0, min(editedRange.length, totalLength - safeLocation))
        let safeRange = NSRange(location: safeLocation, length: safeLength)
        let block = incrementalMarkdownBlock(containing: safeRange)
        let styleRange = incrementalMarkdownStyleRange(around: block.range)
        applyMarkdownStyle(in: styleRange, style: style, layers: [.block, .inline])
        markAttachmentStyleDirty(in: styleRange)
        schedulePendingAttachmentStyle(style: style, delay: 0.18)
        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextKit2PlainTextView.applyMarkdownStyleIncrementally",
            start: profileStart,
            details: "edited={\(editedRange.location),\(editedRange.length)},block=\(block.kind),range={\(styleRange.location),\(styleRange.length)},utf16=\(totalLength)"
        )
        MarkdownEditorPerformanceProbe.metric(
            "TextKit2.incrementalStyle",
            start: profileStart,
            budgetMs: 8,
            textLength: totalLength,
            details: "edited={\(editedRange.location),\(editedRange.length)},block=\(block.kind),range={\(styleRange.location),\(styleRange.length)}"
        )
    }

    /// Ordinary typing is a line-local transaction. It must not resolve a surrounding
    /// Markdown block or touch neighboring paragraphs merely because one character changed.
    func applyMarkdownStyleToEditedLine(for editedRange: NSRange, style: MarkdownDocumentStyle) {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        guard let textStorage else { return }
        currentDocumentStyle = style
        let textLength = textStorage.length
        guard textLength > 0 else { return }
        let safeLocation = max(0, min(editedRange.location, textLength - 1))
        let lineRange = textStorage.mutableString.lineRange(
            for: NSRange(location: safeLocation, length: 0)
        )
        applyMarkdownStyle(in: lineRange, style: style, layers: [.block, .inline])
        markAttachmentStyleDirty(in: lineRange)
        schedulePendingAttachmentStyle(style: style, delay: 0.24)
        MarkdownEditorPerformanceProbe.metric(
            "TextKit2.localLineStyle",
            start: profileStart,
            budgetMs: 8,
            textLength: textLength,
            details: "line={\(lineRange.location),\(lineRange.length)}"
        )
    }

    private func incrementalMarkdownBlock(containing range: NSRange) -> MarkdownBlock {
        guard let textStorage else { return MarkdownBlock(kind: .paragraph, range: range) }
        let nsText = textStorage.mutableString
        let textLength = nsText.length
        guard textLength > 0 else { return MarkdownBlock(kind: .paragraph, range: NSRange(location: 0, length: 0)) }

        let safeLocation = max(0, min(range.location, textLength))
        let safeEnd = max(safeLocation, min(NSMaxRange(range), textLength))
        let startAnchor = max(0, min(safeLocation, textLength - 1))
        let endAnchor = max(startAnchor, min(max(safeEnd - 1, safeLocation), textLength - 1))
        let startLine = nsText.lineRange(for: NSRange(location: startAnchor, length: 0))
        let endLine = nsText.lineRange(for: NSRange(location: endAnchor, length: 0))
        let cacheKey = startLine.location
        if let cachedBlock = markdownBlockCache[cacheKey],
           NSMaxRange(cachedBlock.range) <= textLength,
           NSIntersectionRange(cachedBlock.range, NSRange(location: startLine.location, length: NSMaxRange(endLine) - startLine.location)).length > 0 {
            return cachedBlock
        }

        let block = resolveMarkdownBlock(startLine: startLine, endLine: endLine, in: nsText)
        markdownBlockCache[cacheKey] = block
        return block
    }

    private func incrementalMarkdownStyleRange(around blockRange: NSRange) -> NSRange {
        guard let textStorage else { return blockRange }
        let nsText = textStorage.mutableString
        let contextStart = previousLineRange(before: blockRange.location, in: nsText)?.location ?? blockRange.location
        let contextEnd = nextLineRange(after: NSMaxRange(blockRange), in: nsText).map { NSMaxRange($0) } ?? NSMaxRange(blockRange)
        return NSRange(location: contextStart, length: max(0, contextEnd - contextStart))
    }

    private func resolveMarkdownBlock(startLine: NSRange, endLine: NSRange, in nsText: NSString) -> MarkdownBlock {
        let targetText = markdownBlockLineText(startLine, in: nsText)
        if isMarkdownFenceLine(targetText) {
            return MarkdownBlock(kind: .codeFence, range: delimitedMarkdownBlockRange(containing: startLine, in: nsText, isDelimiter: isMarkdownFenceLine))
        }
        if isMarkdownMathDelimiterLine(targetText) {
            return MarkdownBlock(kind: .mathBlock, range: delimitedMarkdownBlockRange(containing: startLine, in: nsText, isDelimiter: isMarkdownMathDelimiterLine))
        }
        if let fencedRange = containingDelimitedMarkdownBlockRange(containing: startLine, in: nsText, isDelimiter: isMarkdownFenceLine) {
            return MarkdownBlock(kind: .codeFence, range: fencedRange)
        }
        if let mathRange = containingDelimitedMarkdownBlockRange(containing: startLine, in: nsText, isDelimiter: isMarkdownMathDelimiterLine) {
            return MarkdownBlock(kind: .mathBlock, range: mathRange)
        }
        if parseHeadingLevelForStyling(in: targetText) != nil {
            return MarkdownBlock(kind: .heading, range: NSUnionRange(startLine, endLine))
        }
        if parseCommentLine(targetText) != nil {
            return MarkdownBlock(kind: .comment, range: contiguousMarkdownBlockRange(containing: startLine, in: nsText, matches: { parseCommentLine($0) != nil }))
        }
        if parseListLevel(in: targetText) != nil {
            return MarkdownBlock(kind: .list, range: contiguousMarkdownBlockRange(containing: startLine, in: nsText, matches: { parseListLevel(in: $0) != nil || $0.trimmingCharacters(in: .whitespaces).isEmpty }))
        }
        if isMarkdownQuoteLine(targetText) {
            return MarkdownBlock(kind: .quote, range: contiguousMarkdownBlockRange(containing: startLine, in: nsText, matches: isMarkdownQuoteLine))
        }
        if isMarkdownHTMLBlockLine(targetText) {
            return MarkdownBlock(kind: .htmlBlock, range: contiguousMarkdownBlockRange(containing: startLine, in: nsText, matches: { isMarkdownHTMLBlockLine($0) || !$0.trimmingCharacters(in: .whitespaces).isEmpty }))
        }
        return MarkdownBlock(kind: .paragraph, range: contiguousMarkdownBlockRange(containing: startLine, in: nsText, matches: isMarkdownParagraphLine))
    }

    private func containingDelimitedMarkdownBlockRange(containing lineRange: NSRange, in nsText: NSString, isDelimiter: (String) -> Bool) -> NSRange? {
        guard let openingLine = nearestPreviousDelimiterLine(beforeOrAt: lineRange, in: nsText, isDelimiter: isDelimiter) else { return nil }
        let closingLine = nearestNextDelimiterLine(after: NSMaxRange(openingLine), in: nsText, isDelimiter: isDelimiter)
        if lineRange.location == openingLine.location || closingLine.map({ lineRange.location <= $0.location }) == true {
            let end = closingLine.map { NSMaxRange($0) } ?? NSMaxRange(lineRange)
            return NSRange(location: openingLine.location, length: max(0, end - openingLine.location))
        }
        return nil
    }

    private func delimitedMarkdownBlockRange(containing lineRange: NSRange, in nsText: NSString, isDelimiter: (String) -> Bool) -> NSRange {
        let openingLine = nearestPreviousDelimiterLine(beforeOrAt: lineRange, in: nsText, isDelimiter: isDelimiter) ?? lineRange
        let closingLine = nearestNextDelimiterLine(after: NSMaxRange(openingLine), in: nsText, isDelimiter: isDelimiter)
        let end = closingLine.map { NSMaxRange($0) } ?? NSMaxRange(lineRange)
        return NSRange(location: openingLine.location, length: max(0, end - openingLine.location))
    }

    private func nearestPreviousDelimiterLine(beforeOrAt lineRange: NSRange, in nsText: NSString, isDelimiter: (String) -> Bool) -> NSRange? {
        var current = lineRange
        var scanned = 0
        while scanned < 240 {
            if isDelimiter(markdownBlockLineText(current, in: nsText)) {
                return current
            }
            guard let previous = previousLineRange(before: current.location, in: nsText) else { break }
            current = previous
            scanned += 1
        }
        return nil
    }

    private func nearestNextDelimiterLine(after location: Int, in nsText: NSString, isDelimiter: (String) -> Bool) -> NSRange? {
        var currentLocation = location
        var scanned = 0
        while currentLocation < nsText.length, scanned < 240 {
            let lineRange = nsText.lineRange(for: NSRange(location: currentLocation, length: 0))
            if isDelimiter(markdownBlockLineText(lineRange, in: nsText)) {
                return lineRange
            }
            currentLocation = NSMaxRange(lineRange)
            scanned += 1
        }
        return nil
    }

    private func contiguousMarkdownBlockRange(containing lineRange: NSRange, in nsText: NSString, matches: (String) -> Bool) -> NSRange {
        var start = lineRange
        var end = lineRange
        var scannedBackward = 0
        while scannedBackward < 120,
              let previous = previousLineRange(before: start.location, in: nsText),
              matches(markdownBlockLineText(previous, in: nsText)) {
            start = previous
            scannedBackward += 1
        }
        var scannedForward = 0
        while scannedForward < 120,
              let next = nextLineRange(after: NSMaxRange(end), in: nsText),
              matches(markdownBlockLineText(next, in: nsText)) {
            end = next
            scannedForward += 1
        }
        return NSRange(location: start.location, length: max(0, NSMaxRange(end) - start.location))
    }

    private func markdownBlockLineText(_ lineRange: NSRange, in nsText: NSString) -> String {
        let safeRange = NSIntersectionRange(lineRange, NSRange(location: 0, length: nsText.length))
        guard safeRange.length > 0 else { return "" }
        return markdownSourceStringPreservingAttachments(in: safeRange).trimmingSuffixNewline()
    }

    private func isMarkdownFenceLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private func isMarkdownMathDelimiterLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "$$"
    }

    private func isMarkdownQuoteLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    private func isMarkdownHTMLBlockLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<"), !trimmed.hasPrefix("</mark"), !trimmed.hasPrefix("<mark") else { return false }
        return trimmed.hasPrefix("<div") || trimmed.hasPrefix("<table") || trimmed.hasPrefix("<ul") || trimmed.hasPrefix("<ol") || trimmed.hasPrefix("<section") || trimmed.hasPrefix("<blockquote") || trimmed.hasPrefix("<pre") || trimmed.hasPrefix("<details")
    }

    private func isMarkdownParagraphLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard parseHeadingLevelForStyling(in: line) == nil else { return false }
        guard parseCommentLine(line) == nil else { return false }
        guard parseListLevel(in: line) == nil else { return false }
        guard !isMarkdownQuoteLine(line), !isMarkdownFenceLine(line), !isMarkdownMathDelimiterLine(line), !isMarkdownHTMLBlockLine(line) else { return false }
        return true
    }

    private func previousLineRange(before location: Int, in nsText: NSString) -> NSRange? {
        guard location > 0 else { return nil }
        let anchor = max(0, min(location - 1, nsText.length - 1))
        return nsText.lineRange(for: NSRange(location: anchor, length: 0))
    }

    private func nextLineRange(after location: Int, in nsText: NSString) -> NSRange? {
        guard location < nsText.length else { return nil }
        return nsText.lineRange(for: NSRange(location: location, length: 0))
    }

    private func rebuildLineRangeCacheIfNeeded() {
        guard cachedStringLength != (textStorage?.length ?? 0) else { return }
        rebuildLineRangeCache()
    }

    private func rebuildLineRangeCache() {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        guard let nsText = textStorage?.mutableString else { return }
        lineRangeCache = []
        lineRangeCache.reserveCapacity(max(1, nsText.length / 48))
        var location = 0
        while location < nsText.length {
            let range = nsText.lineRange(for: NSRange(location: location, length: 0))
            guard range.length > 0 else { break }
            lineRangeCache.append(range)
            location = NSMaxRange(range)
        }
        if nsText.length == 0 {
            lineRangeCache = [NSRange(location: 0, length: 0)]
        }
        cachedStringLength = nsText.length
        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextKit2PlainTextView.rebuildLineRangeCache",
            start: profileStart,
            details: "lines=\(lineRangeCache.count),utf16=\(nsText.length)"
        )
    }

    private func cachedLineRange(containing range: NSRange) -> NSRange? {
        guard !lineRangeCache.isEmpty else { return nil }
        let location = max(0, range.location)
        var lower = 0
        var upper = lineRangeCache.count - 1
        while lower <= upper {
            let mid = (lower + upper) / 2
            let lineRange = lineRangeCache[mid]
            if location < lineRange.location {
                upper = mid - 1
            } else if location >= NSMaxRange(lineRange), NSMaxRange(lineRange) < cachedStringLength {
                lower = mid + 1
            } else {
                return lineRange
            }
        }
        return nil
    }

    private func visibleCharacterRange() -> NSRange? {
        guard let layoutManager, let textContainer else { return nil }
        let paintRect = visibleRect.insetBy(dx: -16, dy: -240)
        guard !paintRect.isEmpty else { return nil }
        let glyphRange = layoutManager.glyphRange(forBoundingRect: paintRect, in: textContainer)
        guard glyphRange.length > 0 else { return nil }
        return layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    }

    private func selectedNeighborhoodRange() -> NSRange {
        let textLength = textStorage?.length ?? 0
        let selection = selectedRange()
        let location = max(0, min(selection.location, textLength))
        let start = max(0, location - 8_000)
        let end = min(textLength, location + max(selection.length, 8_000))
        return NSRange(location: start, length: max(0, end - start))
    }

    private func expandedLineRange(for range: NSRange) -> NSRange {
        guard let textStorage else { return range }
        let textLength = textStorage.length
        guard textLength > 0 else { return NSRange(location: 0, length: 0) }
        let safeLocation = max(0, min(range.location, textLength))
        let safeEnd = max(safeLocation, min(NSMaxRange(range), textLength))
        let source = textStorage.mutableString
        let startLine = source.lineRange(for: NSRange(location: safeLocation, length: 0))
        let endAnchor = max(safeLocation, min(textLength - 1, max(safeLocation, safeEnd - 1)))
        let endLine = source.lineRange(for: NSRange(location: endAnchor, length: 0))
        return NSRange(location: startLine.location, length: NSMaxRange(endLine) - startLine.location)
    }

    private func scheduleIdleMarkdownStyleCompletion(style: MarkdownDocumentStyle, skipping visibleRange: NSRange) {
        guard !lineRangeCache.isEmpty else { return }
        idleStyleGeneration += 1
        let generation = idleStyleGeneration
        var nextIndex = 0
        let batchLineCount = 240

        func scheduleNextBatch() {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard generation == self.idleStyleGeneration else { return }
                guard let textStorage = self.textStorage else { return }

                let profileStart = MarkdownEditorPerformanceProbe.start()
                var processed = 0
                while nextIndex < self.lineRangeCache.count, processed < batchLineCount {
                    let lineRange = self.lineRangeCache[nextIndex]
                    nextIndex += 1
                    if visibleRange.length > 0, NSIntersectionRange(lineRange, visibleRange).length > 0 {
                        continue
                    }
                    guard NSMaxRange(lineRange) <= textStorage.length else { continue }
                    self.applyMarkdownStyle(in: lineRange, style: style, layers: [.block, .inline])
                    self.markAttachmentStyleDirty(in: lineRange)
                    processed += 1
                }

                MarkdownEditorPerformanceProbe.end(
                    "MarkdownTextKit2PlainTextView.idleMarkdownStyleBatch",
                    start: profileStart,
                    details: "processed=\(processed),nextIndex=\(nextIndex),lines=\(self.lineRangeCache.count)"
                )

                if nextIndex < self.lineRangeCache.count {
                    scheduleNextBatch()
                } else {
                    self.schedulePendingAttachmentStyle(style: style, delay: 0.12)
                }
            }
            pendingIdleStyleWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }

        scheduleNextBatch()
    }

    private func cancelIdleMarkdownStyleCompletion() {
        idleStyleGeneration += 1
        pendingIdleStyleWorkItem?.cancel()
        pendingIdleStyleWorkItem = nil
    }

    private func cancelPendingAttachmentStyleWork() {
        attachmentStyleGeneration += 1
        pendingAttachmentStyleWorkItem?.cancel()
        pendingAttachmentStyleWorkItem = nil
    }

    private func applyMarkdownStyle(in targetRange: NSRange, style: MarkdownDocumentStyle, layers: MarkdownStyleLayer = .all) {
        guard let textStorage else { return }
        let totalLength = textStorage.length
        let safeLocation = max(0, min(targetRange.location, totalLength))
        let safeLength = max(0, min(targetRange.length, totalLength - safeLocation))
        let safeRange = NSRange(location: safeLocation, length: safeLength)
        guard safeRange.length > 0 || totalLength == 0 else { return }

        let nsText = textStorage.mutableString
        let actualLineRange = totalLength == 0 ? NSRange(location: 0, length: 0) : nsText.lineRange(for: safeRange)
        let selectedRange = selectedRange()
        isApplyingMarkdownStyle = true
        textStorage.beginEditing()
        if layers.contains(.block) || layers.contains(.inline) {
            textStorage.setAttributes(bodyAttributes(for: style.body), range: actualLineRange)
        }

        var lineLocation = actualLineRange.location
        while lineLocation < NSMaxRange(actualLineRange) {
            let lineRange = nsText.lineRange(for: NSRange(location: lineLocation, length: 0))
            if lineRange.length == 0 { break }

            var rawLine = nsText.substring(with: lineRange)
            if rawLine.hasSuffix("\n") { rawLine.removeLast() }
            let syntaxLine = markdownSourceStringPreservingAttachments(in: lineRange).trimmingSuffixNewline()

            if !layers.contains(.attachment),
               lineContainsMarkdownAttachment(lineRange),
               !isLineRangeEditing(lineRange) {
                markAttachmentStyleDirty(in: lineRange)
                lineLocation = NSMaxRange(lineRange)
                continue
            }

            if layers.contains(.block) {
                applyMarkdownBlockStyle(in: textStorage, rawLine: syntaxLine, lineRange: lineRange, style: style)
            }
            if layers.contains(.inline) {
                applyMarkdownInlineStyle(in: textStorage, rawLine: syntaxLine, lineRange: lineRange, style: style)
            }
            if layers.contains(.attachment) {
                applyMarkdownAttachmentStyle(in: textStorage, rawLine: syntaxLine, lineRange: lineRange, style: style)
            }

            lineLocation = NSMaxRange(lineRange)
        }

        textStorage.endEditing()
        if self.selectedRange() != selectedRange {
            setSelectedRange(selectedRange)
        }
        isApplyingMarkdownStyle = false
    }

    private func applyMarkdownBlockStyle(
        in textStorage: NSTextStorage,
        rawLine: String,
        lineRange: NSRange,
        style: MarkdownDocumentStyle
    ) {
        let roleStyle: MarkdownRoleStyle
        if let headingLevel = parseHeadingLevelForStyling(in: rawLine) {
            roleStyle = style.headingStyle(level: headingLevel)
            applyRoleStyle(roleStyle, to: textStorage, range: lineRange)
        } else if parseCommentLine(rawLine) != nil {
            roleStyle = style.comment
            applyRoleStyle(roleStyle, to: textStorage, range: lineRange)
        } else {
            roleStyle = style.body
        }

        textStorage.addAttributes(
            [.paragraphStyle: textKit2ParagraphStyle(rawLine: rawLine, roleStyle: roleStyle)],
            range: lineRange
        )
    }

    private func applyMarkdownInlineStyle(
        in textStorage: NSTextStorage,
        rawLine: String,
        lineRange: NSRange,
        style: MarkdownDocumentStyle
    ) {
        for codeRange in parseInlineCodeRanges(in: rawLine, base: lineRange.location) {
            let codeFont = NSFont.monospacedSystemFont(ofSize: style.body.fontSize, weight: .regular)
            textStorage.addAttributes([
                .font: codeFont,
                .foregroundColor: NSColor.systemOrange,
                .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.28)
            ], range: codeRange)
        }

        for codeRange in parseInlineRegexCaptureRanges(pattern: #"<code>([^<\n]+)</code>"#, in: rawLine, base: lineRange.location, options: [.caseInsensitive]) {
            let codeFont = NSFont.monospacedSystemFont(ofSize: style.body.fontSize, weight: .regular)
            textStorage.addAttributes([
                .font: codeFont,
                .foregroundColor: NSColor.systemOrange,
                .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.28)
            ], range: codeRange)
        }

        for strongRange in parseInlineStrongRanges(in: rawLine, base: lineRange.location) {
            let existingFont = (textStorage.attribute(.font, at: max(0, min(strongRange.location, max(0, textStorage.length - 1))), effectiveRange: nil) as? NSFont) ?? markdownResolvedFont(name: style.body.fontName, size: style.body.fontSize)
            let boldFont = NSFont.monospacedSystemFont(ofSize: existingFont.pointSize, weight: .bold)
            textStorage.addAttributes([
                .font: boldFont,
                .foregroundColor: NSColor.systemOrange
            ], range: strongRange)
        }

        for strongRange in parseInlineRegexCaptureRanges(pattern: #"__([^_\n]+)__"#, in: rawLine, base: lineRange.location) {
            let existingFont = (textStorage.attribute(.font, at: max(0, min(strongRange.location, max(0, textStorage.length - 1))), effectiveRange: nil) as? NSFont) ?? markdownResolvedFont(name: style.body.fontName, size: style.body.fontSize)
            let boldFont = NSFont.monospacedSystemFont(ofSize: existingFont.pointSize, weight: .bold)
            textStorage.addAttributes([
                .font: boldFont,
                .foregroundColor: NSColor.systemOrange
            ], range: strongRange)
        }

        let htmlStrongMatches = parseInlineHTMLTagMatches(
            pattern: #"<(?:b|strong)>([^<\n]+)</(?:b|strong)>"#,
            in: rawLine,
            base: lineRange.location,
            options: [.caseInsensitive]
        )
        for match in htmlStrongMatches {
            let strongRange = match.content
            let existingFont = (textStorage.attribute(.font, at: max(0, min(strongRange.location, max(0, textStorage.length - 1))), effectiveRange: nil) as? NSFont) ?? markdownResolvedFont(name: style.body.fontName, size: style.body.fontSize)
            let boldFont = NSFont.monospacedSystemFont(ofSize: existingFont.pointSize, weight: .bold)
            textStorage.addAttributes([
                .font: boldFont,
                .foregroundColor: NSColor.systemOrange
            ], range: strongRange)
            if !isLineRangeEditing(lineRange) {
                hideInlineMarkdownDelimiters(
                    in: textStorage,
                    fullRange: match.full,
                    contentRange: match.content
                )
            }
        }

        for italicRange in parseInlineItalicRanges(in: rawLine, base: lineRange.location) {
            let existingFont = (textStorage.attribute(.font, at: max(0, min(italicRange.location, max(0, textStorage.length - 1))), effectiveRange: nil) as? NSFont) ?? markdownResolvedFont(name: style.body.fontName, size: style.body.fontSize)
            let italicFont = NSFontManager.shared.convert(existingFont, toHaveTrait: .italicFontMask)
            textStorage.addAttributes([
                .font: italicFont
            ], range: italicRange)
        }

        let htmlItalicRanges = parseInlineRegexCaptureRanges(
            pattern: #"<(?:i|em)>([^<\n]+)</(?:i|em)>"#,
            in: rawLine,
            base: lineRange.location,
            options: [.caseInsensitive]
        )
        for italicRange in htmlItalicRanges {
            let existingFont = (textStorage.attribute(.font, at: max(0, min(italicRange.location, max(0, textStorage.length - 1))), effectiveRange: nil) as? NSFont) ?? markdownResolvedFont(name: style.body.fontName, size: style.body.fontSize)
            let italicFont = NSFontManager.shared.convert(existingFont, toHaveTrait: .italicFontMask)
            textStorage.addAttributes([.font: italicFont], range: italicRange)
        }

        for linkRange in parseInlineLinkLabelRanges(in: rawLine, base: lineRange.location) {
            textStorage.addAttributes([
                .foregroundColor: NSColor.systemBlue,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: linkRange)
        }

        for mathRange in parseInlineMathRanges(in: rawLine, base: lineRange.location) {
            textStorage.addAttributes([
                .foregroundColor: NSColor.systemCyan
            ], range: mathRange)
        }

        for highlightRange in parseInlineHighlightRanges(in: rawLine, base: lineRange.location) {
            textStorage.addAttributes([
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.35)
            ], range: highlightRange)
        }

        for highlightRange in parseInlineRegexCaptureRanges(pattern: #"<mark>([^<\n]+)</mark>"#, in: rawLine, base: lineRange.location, options: [.caseInsensitive]) {
            textStorage.addAttributes([
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.35)
            ], range: highlightRange)
        }

        for underlineRange in parseInlineUnderlineRanges(in: rawLine, base: lineRange.location) {
            textStorage.addAttributes([
                .foregroundColor: NSColor.systemBlue,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: underlineRange)
        }

        let strikeRanges = parseInlineRegexCaptureRanges(pattern: #"~~([^~\n]+)~~"#, in: rawLine, base: lineRange.location)
            + parseInlineRegexCaptureRanges(pattern: #"<(?:s|del)>([^<\n]+)</(?:s|del)>"#, in: rawLine, base: lineRange.location, options: [.caseInsensitive])
        for strikeRange in strikeRanges {
            textStorage.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: NSColor.systemRed
            ], range: strikeRange)
        }
    }

    private func applyMarkdownAttachmentStyle(
        in textStorage: NSTextStorage,
        rawLine: String,
        lineRange: NSRange,
        style: MarkdownDocumentStyle
    ) {
        guard !isLineRangeEditing(lineRange) else { return }
        applyMarkdownAttachments(in: textStorage, rawLine: rawLine, lineRange: lineRange, style: style)
    }

    private func lineContainsMarkdownAttachment(_ lineRange: NSRange) -> Bool {
        guard let textStorage else { return false }
        var containsAttachment = false
        textStorage.enumerateAttribute(
            markdownTextKit2AttachmentSourceTokenKey,
            in: NSIntersectionRange(lineRange, NSRange(location: 0, length: textStorage.length)),
            options: []
        ) { value, range, stop in
            if value is String,
               range.length > 0,
               textStorage.attribute(.attachment, at: range.location, effectiveRange: nil) != nil {
                containsAttachment = true
                stop.pointee = true
            }
        }
        return containsAttachment
    }

    private func markAttachmentStyleDirty(in range: NSRange) {
        guard let textStorage else { return }
        let nsText = textStorage.mutableString
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let targetRange = expandedLineRange(for: NSIntersectionRange(range, fullRange))
        var location = targetRange.location
        while location < NSMaxRange(targetRange), location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            guard lineRange.length > 0 else { break }
            pendingAttachmentLineRanges[lineRange.location] = lineRange
            location = NSMaxRange(lineRange)
        }
    }

    private func schedulePendingAttachmentStyle(style: MarkdownDocumentStyle, delay: TimeInterval) {
        guard !pendingAttachmentLineRanges.isEmpty else { return }
        cancelPendingAttachmentStyleWork()
        let generation = attachmentStyleGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard generation == self.attachmentStyleGeneration else { return }
            self.applyPendingAttachmentStyle(style: style, limit: 32)
            if !self.pendingAttachmentLineRanges.isEmpty {
                self.schedulePendingAttachmentStyle(style: style, delay: 0.12)
            }
        }
        pendingAttachmentStyleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func applyPendingAttachmentStyle(style: MarkdownDocumentStyle, limit: Int) {
        guard let textStorage else { return }
        let profileStart = MarkdownEditorPerformanceProbe.start()
        let orderedKeys = pendingAttachmentLineRanges.keys.sorted()
        var processed = 0
        for key in orderedKeys {
            guard processed < limit else { break }
            guard let lineRange = pendingAttachmentLineRanges.removeValue(forKey: key) else { continue }
            guard NSMaxRange(lineRange) <= textStorage.length else { continue }
            applyMarkdownStyle(in: lineRange, style: style, layers: [.attachment])
            processed += 1
        }
        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextKit2PlainTextView.applyPendingAttachmentStyle",
            start: profileStart,
            details: "processed=\(processed),remaining=\(pendingAttachmentLineRanges.count),utf16=\(textStorage.length)"
        )
        MarkdownEditorPerformanceProbe.metric(
            "TextKit2.attachmentIdle",
            start: profileStart,
            budgetMs: 24,
            textLength: textStorage.length,
            details: "processed=\(processed),remaining=\(pendingAttachmentLineRanges.count)"
        )
    }

    private func bodyAttributes(for style: MarkdownRoleStyle) -> [NSAttributedString.Key: Any] {
        let font = markdownResolvedFont(name: style.fontName, size: style.fontSize)
        return [
            .font: font,
            .foregroundColor: NSColor(style.renderedColor),
            .paragraphStyle: textKit2ParagraphStyle(rawLine: "", font: font)
        ]
    }

    private func textKit2ParagraphStyle(rawLine: String, roleStyle: MarkdownRoleStyle) -> NSParagraphStyle {
        let font = markdownResolvedFont(name: roleStyle.fontName, size: roleStyle.fontSize)
        return textKit2ParagraphStyle(rawLine: rawLine, font: font)
    }

    private func textKit2ParagraphStyle(rawLine: String, font: NSFont) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.firstLineHeadIndent = 0
        paragraph.headIndent = 0
        paragraph.paragraphSpacingBefore = 0
        paragraph.paragraphSpacing = 0
        paragraph.lineSpacing = 0

        if let prefix = markdownHangingPrefix(in: rawLine) {
            paragraph.headIndent = ceil((prefix as NSString).size(withAttributes: [.font: font]).width)
        }

        let glyphHeight = ceil(font.ascender - font.descender + max(0, font.leading))
        let stableLineHeight = max(glyphHeight + 6, ceil(font.pointSize * 1.6))
        paragraph.minimumLineHeight = stableLineHeight
        paragraph.maximumLineHeight = stableLineHeight
        return paragraph
    }

    private func isLineRangeEditing(_ lineRange: NSRange) -> Bool {
        let selection = selectedRange()
        if selection.length == 0 {
            return NSLocationInRange(selection.location, lineRange)
                || selection.location == NSMaxRange(lineRange)
        }
        return NSIntersectionRange(selection, lineRange).length > 0
    }

    private func applyMarkdownAttachments(
        in textStorage: NSTextStorage,
        rawLine: String,
        lineRange: NSRange,
        style: MarkdownDocumentStyle
    ) {
        _ = applyImageAttachments(in: textStorage, rawLine: rawLine, lineRange: lineRange, style: style)
    }

    private func applyImageAttachments(
        in textStorage: NSTextStorage,
        rawLine: String,
        lineRange: NSRange,
        style: MarkdownDocumentStyle
    ) -> [NSRange] {
        let nsLine = rawLine as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let regex = try? NSRegularExpression(pattern: #"<img\s+[^>\n]*src=\"([^\"]+)\"[^>\n]*>"#, options: [.caseInsensitive]) else {
            return []
        }
        var appliedRanges: [NSRange] = []
        for match in regex.matches(in: rawLine, options: [], range: fullRange).reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let sourceRange = match.range(at: 1)
            guard sourceRange.location != NSNotFound, sourceRange.length > 0 else { continue }
            let absoluteRange = NSRange(location: lineRange.location + match.range.location, length: match.range.length)
            let tagText = nsLine.substring(with: match.range)
            let sourcePath = nsLine.substring(with: sourceRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sourcePath.isEmpty else { continue }
            let width = markdownImageWidth(from: tagText) ?? 600
            if applyImageAttachment(in: textStorage, range: absoluteRange, sourcePath: sourcePath, targetWidth: width, sourceToken: tagText, style: style) {
                appliedRanges.append(absoluteRange)
            }
        }
        return appliedRanges
    }

    private func applyFormulaAttachments(
        in textStorage: NSTextStorage,
        rawLine: String,
        lineRange: NSRange,
        style: MarkdownDocumentStyle,
        excludedRanges: [NSRange]
    ) {
        let formulas = markdownFormulaRanges(in: rawLine, base: lineRange.location)
        for formula in formulas.reversed() {
            guard !excludedRanges.contains(where: { NSIntersectionRange($0, formula.fullRange).length > 0 }) else { continue }
            let sourceToken = (textStorage.string as NSString).substring(with: formula.fullRange)
            let fontSize = formula.isDisplay ? max(style.body.fontSize * 1.2, 18) : max(style.body.fontSize, 14)
            _ = applyFormulaAttachment(
                in: textStorage,
                range: formula.fullRange,
                latex: formula.latex,
                isDisplay: formula.isDisplay,
                textColor: NSColor(style.body.renderedColor),
                fontSize: fontSize,
                sourceToken: sourceToken,
                style: style
            )
        }
    }

    private func markdownFormulaRanges(in rawLine: String, base: Int) -> [(fullRange: NSRange, latex: String, isDisplay: Bool)] {
        let patterns: [(String, Bool)] = [
            (#"\$\$([^$\n]+)\$\$"#, true),
            (#"(?<!\$)\$([^$\n]+)\$(?!\$)"#, false),
            (#"\\\(([^)\n]+)\\\)"#, false),
            (#"\\\[([^\]\n]+)\\\]"#, true)
        ]
        let nsLine = rawLine as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        var result: [(fullRange: NSRange, latex: String, isDisplay: Bool)] = []
        for (pattern, isDisplay) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: rawLine, options: [], range: fullRange) {
                guard match.numberOfRanges > 1 else { continue }
                let latexRange = match.range(at: 1)
                guard latexRange.location != NSNotFound, latexRange.length > 0 else { continue }
                let absoluteFullRange = NSRange(location: base + match.range.location, length: match.range.length)
                guard !result.contains(where: { NSIntersectionRange($0.fullRange, absoluteFullRange).length > 0 }) else { continue }
                result.append((absoluteFullRange, nsLine.substring(with: latexRange), isDisplay))
            }
        }
        return result.sorted { $0.fullRange.location < $1.fullRange.location }
    }

    private func applyFormulaAttachment(
        in textStorage: NSTextStorage,
        range: NSRange,
        latex: String,
        isDisplay: Bool,
        textColor: NSColor,
        fontSize: CGFloat,
        sourceToken: String,
        style: MarkdownDocumentStyle
    ) -> Bool {
        #if canImport(SwiftMath)
        guard let image = markdownFormulaImage(latex: latex, isDisplay: isDisplay, textColor: textColor, fontSize: fontSize) else { return false }
        let scale = max(1, MarkdownTextKit2InlineAttachment.renderScale)
        let width = image.size.width / scale
        let height = image.size.height / scale
        guard width > 0, height > 0 else { return false }
        prepareRangeForAttachment(in: textStorage, range: range, sourceToken: sourceToken, style: style)
        let attachment = MarkdownTextKit2InlineAttachment(image: image, width: width, height: height)
        textStorage.addAttributes(
            [
                .attachment: attachment,
                .baselineOffset: 0
            ],
            range: NSRange(location: range.location, length: 1)
        )
        return true
        #else
        return false
        #endif
    }

    private func applyImageAttachment(
        in textStorage: NSTextStorage,
        range: NSRange,
        sourcePath: String,
        targetWidth: CGFloat,
        sourceToken: String,
        style: MarkdownDocumentStyle
    ) -> Bool {
        guard let imageURL = resolvedMarkdownImageURL(from: sourcePath),
              let image = NSImage(contentsOf: imageURL),
              image.size.width > 0,
              image.size.height > 0 else {
            return false
        }
        let width = max(120, targetWidth)
        let height = max(40, width * (image.size.height / image.size.width))
        prepareRangeForAttachment(in: textStorage, range: range, sourceToken: sourceToken, style: style)
        let attachment = MarkdownTextKit2InlineAttachment(image: image, width: width, height: height)
        textStorage.addAttributes(
            [
                .attachment: attachment,
                .baselineOffset: 0
            ],
            range: NSRange(location: range.location, length: 1)
        )
        return true
    }

    private func prepareRangeForAttachment(
        in textStorage: NSTextStorage,
        range: NSRange,
        sourceToken: String,
        style: MarkdownDocumentStyle
    ) {
        guard range.length > 0 else { return }
        let anchorRange = NSRange(location: range.location, length: 1)
        if (textStorage.string as NSString).substring(with: anchorRange) != "\u{FFFC}" {
            textStorage.replaceCharacters(in: anchorRange, with: "\u{FFFC}")
        }
        textStorage.addAttributes(
            [
                .font: markdownResolvedFont(name: style.body.fontName, size: style.body.fontSize),
                .foregroundColor: NSColor.clear,
                .kern: 0,
                .ligature: 0,
                markdownTextKit2AttachmentSourceTokenKey: sourceToken
            ],
            range: range
        )
        if range.length > 1 {
            textStorage.addAttributes(
                [
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.monospacedSystemFont(ofSize: 0.1, weight: .regular),
                    .kern: -2.0
                ],
                range: NSRange(location: range.location + 1, length: range.length - 1)
            )
        }
    }

    func markdownSourceStringPreservingAttachments() -> String {
        guard let textStorage else { return string }
        if textStorage.mutableString.range(of: "\u{fffc}").location == NSNotFound {
            return textStorage.string
        }
        return markdownSourceStringPreservingAttachments(in: NSRange(location: 0, length: textStorage.length))
    }

    private func markdownSourceStringPreservingAttachments(in range: NSRange) -> String {
        guard let textStorage else { return string }
        let nsText = textStorage.mutableString
        var output = ""
        let safeLocation = max(0, min(range.location, textStorage.length))
        let safeEnd = max(safeLocation, min(NSMaxRange(range), textStorage.length))
        var index = safeLocation
        while index < safeEnd {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attributes = textStorage.attributes(at: index, effectiveRange: &effectiveRange)
            let clippedRange = NSIntersectionRange(effectiveRange, NSRange(location: safeLocation, length: safeEnd - safeLocation))
            if let token = attributes[markdownTextKit2AttachmentSourceTokenKey] as? String,
               attributes[.attachment] != nil {
                output.append(token)
                index = min(safeEnd, max(index + 1, effectiveRange.location + max(1, (token as NSString).length)))
                continue
            }
            if clippedRange.length > 0 {
                output.append(nsText.substring(with: clippedRange))
            }
            index = max(index + 1, NSMaxRange(effectiveRange))
        }
        return output
    }

    private func markdownImageWidth(from tagText: String) -> CGFloat? {
        guard let regex = try? NSRegularExpression(pattern: #"width\s*=\s*\"(\d+)\""#, options: [.caseInsensitive]) else { return nil }
        let nsTag = tagText as NSString
        let range = NSRange(location: 0, length: nsTag.length)
        guard let match = regex.firstMatch(in: tagText, options: [], range: range), match.numberOfRanges > 1 else { return nil }
        return CGFloat(Int(nsTag.substring(with: match.range(at: 1))) ?? 0)
    }

    private func resolvedMarkdownImageURL(from sourcePath: String) -> URL? {
        if let directURL = URL(string: sourcePath), directURL.isFileURL {
            return directURL
        }
        if sourcePath.hasPrefix("/") {
            return URL(fileURLWithPath: sourcePath)
        }
        return workingDirectoryURL?.appendingPathComponent(sourcePath).standardizedFileURL
    }

    #if canImport(SwiftMath)
    private func markdownFormulaImage(latex: String, isDisplay: Bool, textColor: NSColor, fontSize: CGFloat) -> NSImage? {
        let normalized = NodeMarkdownFormulaLatexNormalizer.normalize(latex)
        let color = textColor.usingColorSpace(.deviceRGB) ?? textColor
        let imageBuilder = MTMathImage(
            latex: normalized,
            fontSize: fontSize * MarkdownTextKit2InlineAttachment.renderScale,
            textColor: color,
            labelMode: isDisplay ? .display : .text,
            textAlignment: .left
        )
        let result = imageBuilder.asImage()
        guard result.0 == nil else { return nil }
        return result.1
    }
    #endif

    func applyQuickInputIfNeeded() -> Bool {
        guard !isApplyingQuickInputReplacement else { return false }
        guard let textStorage else { return false }
        let selection = selectedRange()
        guard selection.length == 0 else { return false }

        let nsText = textStorage.mutableString
        let caret = max(0, min(selection.location, nsText.length))
        let prefixStart = max(0, caret - 8_192)
        let prefix = nsText.substring(with: NSRange(location: prefixStart, length: caret - prefixStart))

        if applyPairQuickInputIfNeeded(
            textStorage: textStorage,
            prefix: prefix,
            prefixStart: prefixStart,
            caret: caret
        ) {
            return true
        }

        for candidate in quickInputSingleCandidates() {
            guard !candidate.trigger.isEmpty else { continue }
            guard candidate.replacement != candidate.trigger else { continue }
            guard prefix.hasSuffix(candidate.trigger) else { continue }

            let triggerLength = (candidate.trigger as NSString).length
            let replacementLength = (candidate.replacement as NSString).length
            let start = caret - triggerLength
            guard start >= 0 else { continue }

            isApplyingQuickInputReplacement = true
            textStorage.beginEditing()
            textStorage.replaceCharacters(in: NSRange(location: start, length: triggerLength), with: candidate.replacement)
            textStorage.endEditing()
            setSelectedRange(NSRange(location: start + replacementLength, length: 0))
            isApplyingQuickInputReplacement = false
            return true
        }
        return false
    }

    private func applyPairQuickInputIfNeeded(
        textStorage: NSTextStorage,
        prefix: String,
        prefixStart: Int,
        caret: Int
    ) -> Bool {
        let nsPrefix = prefix as NSString

        for pairRule in quickInputPairCandidates() {
            let openTrigger = pairRule.openTrigger
            let closeTrigger = pairRule.closeTrigger
            guard !openTrigger.isEmpty, !closeTrigger.isEmpty else { continue }
            guard pairRule.openReplacement != openTrigger || pairRule.closeReplacement != closeTrigger else { continue }
            guard prefix.hasSuffix(closeTrigger) else { continue }

            let closeLength = (closeTrigger as NSString).length
            let openLength = (openTrigger as NSString).length
            let closeStart = caret - closeLength
            guard closeStart >= 0 else { continue }

            let localCloseStart = closeStart - prefixStart
            guard localCloseStart >= 0 else { continue }
            let searchRange = NSRange(location: 0, length: localCloseStart)
            let localOpenRange = nsPrefix.range(of: openTrigger, options: .backwards, range: searchRange)
            guard localOpenRange.location != NSNotFound else { continue }

            let localContentStart = localOpenRange.location + openLength
            guard localContentStart <= localCloseStart else { continue }
            let contentLength = localCloseStart - localContentStart
            let content = nsPrefix.substring(with: NSRange(location: localContentStart, length: contentLength))
            let replacement = pairRule.openReplacement + content + pairRule.closeReplacement
            let openLocation = prefixStart + localOpenRange.location

            isApplyingQuickInputReplacement = true
            textStorage.beginEditing()
            textStorage.replaceCharacters(
                in: NSRange(location: openLocation, length: caret - openLocation),
                with: replacement
            )
            textStorage.endEditing()
            setSelectedRange(NSRange(location: openLocation + (replacement as NSString).length, length: 0))
            isApplyingQuickInputReplacement = false
            return true
        }

        return false
    }

    private func quickInputSingleCandidates() -> [(trigger: String, replacement: String)] {
        quickInputSettings.singleRules
            .map { ($0.trigger, $0.replacement) }
            .sorted {
                ($0.trigger as NSString).length > ($1.trigger as NSString).length
            }
    }

    private func quickInputPairCandidates() -> [MarkdownPairShortcutRule] {
        quickInputSettings.pairRules.sorted {
            let lhsClose = ($0.closeTrigger as NSString).length
            let rhsClose = ($1.closeTrigger as NSString).length
            if lhsClose != rhsClose {
                return lhsClose > rhsClose
            }
            return ($0.openTrigger as NSString).length > ($1.openTrigger as NSString).length
        }
    }

    func updateSearchHighlights(query: String, activeRange: NSRange?) {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        cancelPendingSearchHighlightWork()
        clearSearchHighlights()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        currentSearchQuery = trimmedQuery
        currentSearchActiveRange = activeRange
        guard !trimmedQuery.isEmpty else {
            MarkdownEditorPerformanceProbe.end(
                "MarkdownTextKit2PlainTextView.updateSearchHighlights.empty",
                start: profileStart,
                details: MarkdownEditorPerformanceProbe.textDetails(string)
            )
            return
        }
        guard let textStorage else { return }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let visibleRange = NSIntersectionRange(expandedLineRange(for: visibleCharacterRange() ?? selectedNeighborhoodRange()), fullRange)
        applySearchHighlights(query: trimmedQuery, activeRange: activeRange, in: visibleRange)
        scheduleIdleSearchHighlights(query: trimmedQuery, activeRange: activeRange, skipping: visibleRange)
        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextKit2PlainTextView.updateSearchHighlights",
            start: profileStart,
            details: "queryLength=\((trimmedQuery as NSString).length),visible={\(visibleRange.location),\(visibleRange.length)},matches=\(searchHighlightRanges.count),\(MarkdownEditorPerformanceProbe.textDetails(string))"
        )
        MarkdownEditorPerformanceProbe.metric(
            "TextKit2.searchVisibleFirst",
            start: profileStart,
            budgetMs: 20,
            textLength: textStorage.length,
            details: "queryLength=\((trimmedQuery as NSString).length),visible={\(visibleRange.location),\(visibleRange.length)},matches=\(searchHighlightRanges.count)"
        )
    }

    func applySearchHighlightsToVisibleRange(query: String, activeRange: NSRange?) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        guard trimmedQuery == currentSearchQuery else { return }
        guard let textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let visibleRange = NSIntersectionRange(expandedLineRange(for: visibleCharacterRange() ?? selectedNeighborhoodRange()), fullRange)
        applySearchHighlights(query: trimmedQuery, activeRange: activeRange, in: visibleRange)
    }

    private func applySearchHighlights(query: String, activeRange: NSRange?, in targetRange: NSRange) {
        guard let textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let safeRange = NSIntersectionRange(targetRange, fullRange)
        guard safeRange.length > 0 else { return }

        let nsText = string as NSString
        let ranges = searchRanges(in: nsText, query: query, range: safeRange)
        textStorage.beginEditing()
        for range in ranges {
            guard !searchHighlightRanges.contains(where: { NSEqualRanges($0, range) }) else { continue }
            textStorage.addAttributes(
                [
                    .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.20)
                ],
                range: range
            )
            searchHighlightRanges.append(range)
        }
        if let activeRange {
            let safeActiveRange = NSIntersectionRange(activeRange, fullRange)
            if safeActiveRange.length > 0 {
                if let searchActiveRange {
                    textStorage.removeAttribute(.backgroundColor, range: searchActiveRange)
                }
                searchActiveRange = safeActiveRange
                textStorage.addAttributes(
                    [
                        .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.42)
                    ],
                    range: safeActiveRange
                )
            }
        }
        textStorage.endEditing()
    }

    private func scheduleIdleSearchHighlights(query: String, activeRange: NSRange?, skipping visibleRange: NSRange) {
        guard let textStorage else { return }
        let textLength = textStorage.length
        guard textLength > 0 else { return }
        searchHighlightGeneration += 1
        let generation = searchHighlightGeneration
        var nextLocation = 0
        let chunkLength = 24_000

        func scheduleNextChunk() {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard generation == self.searchHighlightGeneration else { return }
                guard let textStorage = self.textStorage else { return }

                let profileStart = MarkdownEditorPerformanceProbe.start()
                var processed = 0
                while nextLocation < textStorage.length, processed < 2 {
                    let chunkEnd = min(textStorage.length, nextLocation + chunkLength)
                    let chunkRange = NSRange(location: nextLocation, length: chunkEnd - nextLocation)
                    nextLocation = chunkEnd
                    if visibleRange.length > 0, NSIntersectionRange(chunkRange, visibleRange).length == chunkRange.length {
                        continue
                    }
                    self.applySearchHighlights(query: query, activeRange: activeRange, in: chunkRange)
                    processed += 1
                }

                MarkdownEditorPerformanceProbe.end(
                    "MarkdownTextKit2PlainTextView.idleSearchHighlightChunk",
                    start: profileStart,
                    details: "processed=\(processed),nextLocation=\(nextLocation),matches=\(self.searchHighlightRanges.count),utf16=\(textStorage.length)"
                )
                MarkdownEditorPerformanceProbe.metric(
                    "TextKit2.searchIdle",
                    start: profileStart,
                    budgetMs: 24,
                    textLength: textStorage.length,
                    details: "processed=\(processed),nextLocation=\(nextLocation),matches=\(self.searchHighlightRanges.count)"
                )

                if nextLocation < textStorage.length {
                    scheduleNextChunk()
                }
            }
            pendingSearchHighlightWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }

        scheduleNextChunk()
    }

    private func cancelPendingSearchHighlightWork() {
        searchHighlightGeneration += 1
        pendingSearchHighlightWorkItem?.cancel()
        pendingSearchHighlightWorkItem = nil
    }

    private func searchRanges(in nsText: NSString, query: String, range: NSRange) -> [NSRange] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }
        let fullRange = NSRange(location: 0, length: nsText.length)
        let safeRange = NSIntersectionRange(range, fullRange)
        guard safeRange.length > 0 else { return [] }
        var ranges: [NSRange] = []
        var searchRange = safeRange
        let rangeEnd = NSMaxRange(safeRange)
        while searchRange.location < rangeEnd {
            let found = nsText.range(of: normalizedQuery, options: [.caseInsensitive], range: searchRange)
            if found.location == NSNotFound || found.location >= rangeEnd { break }
            ranges.append(found)
            let nextLocation = found.location + max(found.length, 1)
            guard nextLocation < rangeEnd else { break }
            searchRange = NSRange(location: nextLocation, length: rangeEnd - nextLocation)
        }
        return ranges
    }

    private func clearSearchHighlights() {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        guard let textStorage else { return }
        cancelPendingSearchHighlightWork()
        let clearedCount = searchHighlightRanges.count
        var affectedRange: NSRange?
        func mergeAffectedRange(_ range: NSRange) {
            affectedRange = affectedRange.map { NSUnionRange($0, range) } ?? range
        }
        textStorage.beginEditing()
        for range in searchHighlightRanges {
            let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
            guard safeRange.length > 0 else { continue }
            mergeAffectedRange(safeRange)
            textStorage.removeAttribute(.backgroundColor, range: safeRange)
        }
        if let searchActiveRange {
            let safeRange = NSIntersectionRange(searchActiveRange, NSRange(location: 0, length: textStorage.length))
            if safeRange.length > 0 {
                mergeAffectedRange(safeRange)
                textStorage.removeAttribute(.backgroundColor, range: safeRange)
            }
        }
        textStorage.endEditing()
        searchHighlightRanges = []
        searchActiveRange = nil
        if let affectedRange, let currentDocumentStyle {
            let restoreRange: NSRange
            if affectedRange.length <= 20_000 {
                restoreRange = (textStorage.string as NSString).lineRange(for: affectedRange)
            } else {
                restoreRange = expandedLineRange(for: visibleCharacterRange() ?? selectedNeighborhoodRange())
            }
            let lineRange = NSIntersectionRange(restoreRange, NSRange(location: 0, length: textStorage.length))
            applyMarkdownStyle(in: lineRange, style: currentDocumentStyle)
        }
        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextKit2PlainTextView.clearSearchHighlights",
            start: profileStart,
            details: "cleared=\(clearedCount),\(MarkdownEditorPerformanceProbe.textDetails(string))"
        )
    }

    func prepareTypingAttributesIfNeeded(at location: Int) {
        let style = currentDocumentStyle ?? MarkdownDocumentStyle()
        let lineStyle = lineRoleStyle(at: location, style: style)
        let paragraphStyle = paragraphStyleForCurrentLine(at: location)
        let font = markdownResolvedFont(name: lineStyle.fontName, size: lineStyle.fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(lineStyle.renderedColor),
            .paragraphStyle: paragraphStyle,
            .baselineOffset: 0
        ]
        typingAttributes = attributes
    }

    private func lineRoleStyle(at location: Int, style: MarkdownDocumentStyle) -> MarkdownRoleStyle {
        let rawLine = caretLineText(at: location)
        if let headingLevel = parseHeadingLevelForStyling(in: rawLine) {
            return style.headingStyle(level: headingLevel)
        }
        if parseCommentLine(rawLine) != nil {
            return style.comment
        }
        return style.body
    }

    private func paragraphStyleForCurrentLine(at location: Int) -> NSParagraphStyle {
        let rawLine = caretLineText(at: location)
        let style = currentDocumentStyle ?? MarkdownDocumentStyle()
        let lineStyle = lineRoleStyle(at: location, style: style)
        return textKit2ParagraphStyle(rawLine: rawLine, roleStyle: lineStyle)
    }

    private func caretLineRange(at location: Int, in nsText: NSString) -> NSRange {
        let safeLocation = max(0, min(location, nsText.length))
        if isAtTrailingEmptyLine(caretLocation: safeLocation, text: nsText) {
            return NSRange(location: safeLocation, length: 0)
        }
        return nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
    }

    private func caretLineText(at location: Int) -> String {
        guard let nsText = textStorage?.mutableString else { return "" }
        let lineRange = caretLineRange(at: location, in: nsText)
        guard lineRange.length > 0 else { return "" }
        var rawLine = nsText.substring(with: lineRange)
        if rawLine.hasSuffix("\n") { rawLine.removeLast() }
        return rawLine
    }

    private func isAtTrailingEmptyLine(caretLocation: Int, text: NSString) -> Bool {
        guard caretLocation == text.length, text.length > 0 else { return false }
        return text.character(at: text.length - 1) == 10
    }

    var hasActiveMarkedText: Bool {
        let range = markedRange()
        return range.location != NSNotFound && range.length > 0
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let location = replacementRange.location == NSNotFound ? self.selectedRange().location : replacementRange.location
        prepareTypingAttributesIfNeeded(at: location)
        let markedText = markedTextByApplyingCurrentLineMetrics(to: string)
        super.setMarkedText(markedText, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    private func markedTextByApplyingCurrentLineMetrics(to string: Any) -> Any {
        let attributes = typingAttributes
        if let attributedString = string as? NSAttributedString {
            let mutable = NSMutableAttributedString(attributedString: attributedString)
            mutable.addAttributes(attributes, range: NSRange(location: 0, length: mutable.length))
            return mutable
        }
        if let plainString = string as? String {
            return NSAttributedString(string: plainString, attributes: attributes)
        }
        return string
    }

    override func insertTab(_ sender: Any?) {
        if applyHierarchyTabAction(isShift: false) {
            return
        }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if applyHierarchyTabAction(isShift: true) {
            return
        }
        super.insertBacktab(sender)
    }

    override func insertNewline(_ sender: Any?) {
        let shiftPressed = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
        if shiftPressed {
            super.insertNewline(sender)
            keepInsertionPointComfortablyVisible()
            return
        }

        if applyAutoContinueRule() {
            keepInsertionPointComfortablyVisible()
            return
        }

        super.insertNewline(sender)
        keepInsertionPointComfortablyVisible()
        DispatchQueue.main.async { [weak self] in
            self?.keepInsertionPointComfortablyVisible()
        }
    }

    override func deleteBackward(_ sender: Any?) {
        let renumberAnchor = numberedRenumberAnchorForDeletion(direction: .backward)
        super.deleteBackward(sender)
        if let renumberAnchor,
           renumberNumberedRunAround(location: renumberAnchor) {
            didChangeText()
        }
    }

    override func deleteForward(_ sender: Any?) {
        let renumberAnchor = numberedRenumberAnchorForDeletion(direction: .forward)
        super.deleteForward(sender)
        if let renumberAnchor,
           renumberNumberedRunAround(location: renumberAnchor) {
            didChangeText()
        }
    }

    private func numberedRenumberAnchorForDeletion(direction: EditorDeletionDirection) -> Int? {
        guard let textStorage else { return nil }
        let nsText = textStorage.mutableString
        guard nsText.length > 0 else { return nil }
        guard let deletionRange = EditorDeletionClassifier.deletionRangeForCommand(
            source: nsText,
            selectedRange: selectedRange(),
            direction: direction
        ) else { return nil }
        guard deletionRange.length > 0 else { return nil }

        let impact = EditorDeletionClassifier.classifyDeletion(source: nsText, affectedRange: deletionRange) { line in
            parseNumberedLine(in: line)?.markerLength ?? 0
        }
        if impact == .character {
            return nil
        }
        return deletionRange.location
    }

    private func applyHierarchyTabAction(isShift: Bool) -> Bool {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        guard let textStorage else { return false }
        let selection = selectedRange()
        let handled: Bool
        if selection.length > 0 {
            handled = applyHierarchyTabActionForSelectedLines(
                textStorage: textStorage,
                selection: selection,
                isShift: isShift
            )
        } else {
            handled = applyHierarchyTabActionForCurrentLine(
                textStorage: textStorage,
                selection: selection,
                isShift: isShift
            )
        }
        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextKit2PlainTextView.applyHierarchyTabAction",
            start: profileStart,
            details: "isShift=\(isShift),handled=\(handled),\(MarkdownEditorPerformanceProbe.textDetails(string))"
        )
        return handled
    }

    private func applyHierarchyTabActionForCurrentLine(
        textStorage: NSTextStorage,
        selection: NSRange,
        isShift: Bool
    ) -> Bool {
        let nsText = string as NSString
        let caret = max(0, min(selection.location, nsText.length))
        let lineRange = caretLineRange(at: caret, in: nsText)
        var line = lineRange.length > 0 ? nsText.substring(with: lineRange) : ""
        if line.hasSuffix("\n") { line.removeLast() }
        let caretOffsetInLine = max(0, caret - lineRange.location)

        if let heading = parseHeadingForHierarchy(in: line) {
            let content = heading.content
            let oldPrefixLength = heading.prefixLength

            if isShift {
                if heading.level == 1 { return true }
                let newPrefix = String(repeating: "#", count: heading.level - 1) + " "
                replaceCurrentLineForHierarchy(
                    textStorage: textStorage,
                    lineRange: lineRange,
                    oldPrefixLength: oldPrefixLength,
                    newPrefix: newPrefix,
                    content: content,
                    caretOffsetInLine: caretOffsetInLine
                )
                return true
            }

            if heading.level == 6 {
                replaceCurrentLineForHierarchy(
                    textStorage: textStorage,
                    lineRange: lineRange,
                    oldPrefixLength: oldPrefixLength,
                    newPrefix: "- ",
                    content: content,
                    caretOffsetInLine: caretOffsetInLine
                )
                return true
            }

            let newPrefix = String(repeating: "#", count: heading.level + 1) + " "
            replaceCurrentLineForHierarchy(
                textStorage: textStorage,
                lineRange: lineRange,
                oldPrefixLength: oldPrefixLength,
                newPrefix: newPrefix,
                content: content,
                caretOffsetInLine: caretOffsetInLine
            )
            return true
        }

        if let bullet = parseBulletForHierarchy(in: line) {
            let oldPrefixLength = bullet.prefixLength
            let content = bullet.content

            if isShift {
                if bullet.indentSpaces == 0 {
                    replaceCurrentLineForHierarchy(
                        textStorage: textStorage,
                        lineRange: lineRange,
                        oldPrefixLength: oldPrefixLength,
                        newPrefix: "###### ",
                        content: content,
                        caretOffsetInLine: caretOffsetInLine
                    )
                    return true
                }

                let newIndent = max(0, bullet.indentSpaces - 2)
                let newPrefix = String(repeating: " ", count: newIndent) + "- "
                replaceCurrentLineForHierarchy(
                    textStorage: textStorage,
                    lineRange: lineRange,
                    oldPrefixLength: oldPrefixLength,
                    newPrefix: newPrefix,
                    content: content,
                    caretOffsetInLine: caretOffsetInLine
                )
                return true
            }

            let newPrefix = String(repeating: " ", count: bullet.indentSpaces + 2) + "- "
            replaceCurrentLineForHierarchy(
                textStorage: textStorage,
                lineRange: lineRange,
                oldPrefixLength: oldPrefixLength,
                newPrefix: newPrefix,
                content: content,
                caretOffsetInLine: caretOffsetInLine
            )
            return true
        }

        if let numbered = parseNumberedLine(in: line) {
            if isShift {
                guard numbered.indentSpaces > 0 else { return true }
                let newIndent = String(repeating: " ", count: max(0, numbered.indentSpaces - 2))
                replaceCurrentNumberedLineForHierarchy(
                    textStorage: textStorage,
                    lineRange: lineRange,
                    oldLine: line,
                    oldNumbered: numbered,
                    newIndent: newIndent,
                    caretOffsetInLine: caretOffsetInLine
                )
                return true
            }

            replaceCurrentNumberedLineForHierarchy(
                textStorage: textStorage,
                lineRange: lineRange,
                oldLine: line,
                oldNumbered: numbered,
                newIndent: numbered.indent + "  ",
                caretOffsetInLine: caretOffsetInLine
            )
            return true
        }

        let leadingSpaces = line.prefix { $0 == " " }.count
        let content = String(line.dropFirst(leadingSpaces))
        let newPrefix = isShift ? "###### " : String(repeating: " ", count: leadingSpaces) + "- "
        replaceCurrentLineForHierarchy(
            textStorage: textStorage,
            lineRange: lineRange,
            oldPrefixLength: leadingSpaces,
            newPrefix: newPrefix,
            content: content,
            caretOffsetInLine: caretOffsetInLine
        )
        return true
    }

    private func applyHierarchyTabActionForSelectedLines(
        textStorage: NSTextStorage,
        selection: NSRange,
        isShift: Bool
    ) -> Bool {
        let nsText = string as NSString
        guard nsText.length > 0 else { return false }

        let safeLocation = max(0, min(selection.location, nsText.length))
        let safeUpperBound = max(safeLocation, min(selection.location + selection.length, nsText.length))
        let endAnchor = max(safeLocation, min(nsText.length, safeUpperBound - 1))

        let startLineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
        let endLineRange = nsText.lineRange(for: NSRange(location: endAnchor, length: 0))
        let replaceRange = NSRange(
            location: startLineRange.location,
            length: (endLineRange.location + endLineRange.length) - startLineRange.location
        )

        var cursor = replaceRange.location
        var rebuilt = ""
        var handledAny = false
        var changedAny = false

        while cursor < replaceRange.location + replaceRange.length {
            let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
            let lineWithTerminator = nsText.substring(with: lineRange)
            let hasTrailingNewline = lineWithTerminator.hasSuffix("\n")
            let line = hasTrailingNewline ? String(lineWithTerminator.dropLast()) : lineWithTerminator

            let action = hierarchyAction(for: line, isShift: isShift)
            handledAny = handledAny || action.handled
            changedAny = changedAny || (action.newLine != line)
            rebuilt += action.newLine
            if hasTrailingNewline {
                rebuilt += "\n"
            }

            cursor = lineRange.location + lineRange.length
        }

        guard handledAny else { return false }
        guard changedAny else { return true }

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: replaceRange, with: rebuilt)
        textStorage.endEditing()

        _ = renumberAllNumberedRunsPreservingSelection()
        let updatedLength = (rebuilt as NSString).length
        setSelectedRange(NSRange(location: replaceRange.location, length: updatedLength))
        didChangeText()
        keepInsertionPointComfortablyVisible()
        return true
    }

    private func hierarchyAction(for line: String, isShift: Bool) -> (handled: Bool, newLine: String) {
        if let heading = parseHeadingForHierarchy(in: line) {
            let content = heading.content
            if isShift {
                if heading.level == 1 {
                    return (true, line)
                }
                let newPrefix = String(repeating: "#", count: heading.level - 1) + " "
                return (true, newPrefix + content)
            }

            if heading.level == 6 {
                return (true, "- " + content)
            }

            let newPrefix = String(repeating: "#", count: heading.level + 1) + " "
            return (true, newPrefix + content)
        }

        if let bullet = parseBulletForHierarchy(in: line) {
            let content = bullet.content
            if isShift {
                if bullet.indentSpaces == 0 {
                    return (true, "###### " + content)
                }
                let newIndent = max(0, bullet.indentSpaces - 2)
                let newPrefix = String(repeating: " ", count: newIndent) + "- "
                return (true, newPrefix + content)
            }

            let newPrefix = String(repeating: " ", count: bullet.indentSpaces + 2) + "- "
            return (true, newPrefix + content)
        }

        if let numbered = parseNumberedLine(in: line) {
            if isShift {
                guard numbered.indentSpaces > 0 else { return (true, line) }
                let newIndent = String(repeating: " ", count: max(0, numbered.indentSpaces - 2))
                return (true, newIndent + numbered.numberPrefix + "\(numbered.number). " + numbered.content)
            }

            return (true, "  " + line)
        }

        let leadingSpaces = line.prefix { $0 == " " }.count
        let content = String(line.dropFirst(leadingSpaces))
        let newPrefix = isShift ? "###### " : String(repeating: " ", count: leadingSpaces) + "- "
        return (true, newPrefix + content)
    }

    private func replaceCurrentLineForHierarchy(
        textStorage: NSTextStorage,
        lineRange: NSRange,
        oldPrefixLength: Int,
        newPrefix: String,
        content: String,
        caretOffsetInLine: Int
    ) {
        let originalLineText = (string as NSString).substring(with: lineRange)
        let hasTrailingNewline = originalLineText.hasSuffix("\n")
        let replaceRange: NSRange = hasTrailingNewline
            ? NSRange(location: lineRange.location, length: max(0, lineRange.length - 1))
            : lineRange

        let newLine = newPrefix + content
        let oldContentOffset = max(0, caretOffsetInLine - oldPrefixLength)
        let newCaretOffset = min((newLine as NSString).length, (newPrefix as NSString).length + oldContentOffset)

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: replaceRange, with: newLine)
        textStorage.endEditing()

        setSelectedRange(NSRange(location: replaceRange.location + newCaretOffset, length: 0))
        _ = renumberAllNumberedRunsPreservingSelection()
        didChangeText()
        keepInsertionPointComfortablyVisible()
    }

    private func replaceCurrentNumberedLineForHierarchy(
        textStorage: NSTextStorage,
        lineRange: NSRange,
        oldLine: String,
        oldNumbered: MarkdownNumberedLine,
        newIndent: String,
        caretOffsetInLine: Int
    ) {
        let originalLineText = (string as NSString).substring(with: lineRange)
        let hasTrailingNewline = originalLineText.hasSuffix("\n")
        let replaceRange: NSRange = hasTrailingNewline
            ? NSRange(location: lineRange.location, length: max(0, lineRange.length - 1))
            : lineRange

        let oldBody = String(oldLine.dropFirst(oldNumbered.indentSpaces))
        let newLine = newIndent + oldBody
        let oldContentOffset = max(0, caretOffsetInLine - oldNumbered.indentSpaces)
        let newCaretOffset = min((newLine as NSString).length, (newIndent as NSString).length + oldContentOffset)
        let oldKey = oldNumbered.sequenceKey
        let newKey = newIndent + oldNumbered.numberPrefix

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: replaceRange, with: newLine)
        textStorage.endEditing()

        setSelectedRange(NSRange(location: replaceRange.location + newCaretOffset, length: 0))
        _ = renumberNumberedHierarchyMove(
            movedLineLocation: replaceRange.location,
            oldKey: oldKey,
            oldNumber: oldNumbered.number,
            newKey: newKey
        )
        didChangeText()
        keepInsertionPointComfortablyVisible()
    }

    private func parseHeadingForHierarchy(in line: String) -> (level: Int, prefixLength: Int, content: String)? {
        guard let level = parseHeadingLevelForStyling(in: line) else { return nil }
        let prefixLength = level + 1
        guard line.count >= prefixLength else {
            return (level, prefixLength, "")
        }
        let start = line.index(line.startIndex, offsetBy: prefixLength)
        return (level, prefixLength, String(line[start...]))
    }

    private func parseBulletForHierarchy(in line: String) -> (indentSpaces: Int, prefixLength: Int, content: String)? {
        let indentCount = line.prefix { $0 == " " }.count
        let remaining = String(line.dropFirst(indentCount))
        guard remaining.hasPrefix("- ") else { return nil }
        let content = String(remaining.dropFirst(2))
        return (indentCount, indentCount + 2, content)
    }

    private func applyAutoContinueRule() -> Bool {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        let nsText = string as NSString
        let selection = selectedRange()
        guard selection.length == 0 else { return false }

        let baseLocation = max(0, min(selection.location, nsText.length))
        let lineRange = caretLineRange(at: baseLocation, in: nsText)

        var line = lineRange.length > 0 ? nsText.substring(with: lineRange) : ""
        if line.hasSuffix("\n") { line.removeLast() }

        guard let marker = parseMarker(in: line) else { return false }
        let caretOffsetInLine = max(0, baseLocation - lineRange.location)

        if marker.hasContent || caretOffsetInLine > marker.markerLength {
            let insertion = "\n\(marker.nextMarker)"
            textStorage?.replaceCharacters(in: selection, with: insertion)
            setSelectedRange(NSRange(location: baseLocation + (insertion as NSString).length, length: 0))
            _ = renumberAllNumberedRunsPreservingSelection()
            didChangeText()
            keepInsertionPointComfortablyVisible()
            MarkdownEditorPerformanceProbe.end(
                "MarkdownTextKit2PlainTextView.applyAutoContinueRule",
                start: profileStart,
                details: "continued=true,\(MarkdownEditorPerformanceProbe.textDetails(string))"
            )
            return true
        }

        let markerRange = NSRange(location: lineRange.location, length: marker.markerLength)
        textStorage?.replaceCharacters(in: markerRange, with: "")
        let adjustedLocation = baseLocation - marker.markerLength
        setSelectedRange(NSRange(location: adjustedLocation, length: 0))
        _ = renumberAllNumberedRunsPreservingSelection()
        didChangeText()
        keepInsertionPointComfortablyVisible()
        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextKit2PlainTextView.applyAutoContinueRule",
            start: profileStart,
            details: "continued=false,removedEmptyMarker=true,\(MarkdownEditorPerformanceProbe.textDetails(string))"
        )
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
        guard let numbered = parseNumberedLine(in: line) else { return nil }
        let next = "\(numbered.indent)\(numbered.numberPrefix)\(numbered.number + 1). "
        return (next, numbered.markerLength, !numbered.content.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private struct MarkdownNumberedLine {
        var indent: String
        var indentSpaces: Int
        var numberPrefix: String
        var number: Int
        var markerLength: Int
        var numberRangeInLine: NSRange
        var content: String

        var sequenceKey: String {
            indent + numberPrefix
        }
    }

    private func parseNumberedLine(in line: String) -> MarkdownNumberedLine? {
        let nsLine = line as NSString
        let pattern = #"^( *)(.*?)(\d+)\. (.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
              match.numberOfRanges == 5 else {
            return nil
        }

        let indentRange = match.range(at: 1)
        let prefixRange = match.range(at: 2)
        let numberRange = match.range(at: 3)
        let contentRange = match.range(at: 4)
        guard numberRange.location != NSNotFound,
              let number = Int(nsLine.substring(with: numberRange)) else {
            return nil
        }

        return MarkdownNumberedLine(
            indent: nsLine.substring(with: indentRange),
            indentSpaces: indentRange.length,
            numberPrefix: nsLine.substring(with: prefixRange),
            number: number,
            markerLength: numberRange.location + numberRange.length + 2,
            numberRangeInLine: numberRange,
            content: nsLine.substring(with: contentRange)
        )
    }

    private func renumberAllNumberedRunsPreservingSelection() -> Bool {
        guard let textStorage else { return false }
        let oldSelection = selectedRange()
        let oldVisibleOrigin = enclosingScrollView?.contentView.bounds.origin
        let nsText = textStorage.string as NSString
        guard nsText.length > 0 else { return false }

        var lineRecords: [(range: NSRange, text: String, terminator: String, numbered: MarkdownNumberedLine?)] = []
        var cursor = 0
        while cursor < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
            let lineWithTerminator = nsText.substring(with: lineRange)
            let hasNewline = lineWithTerminator.hasSuffix("\n")
            let line = hasNewline ? String(lineWithTerminator.dropLast()) : lineWithTerminator
            lineRecords.append((
                range: lineRange,
                text: line,
                terminator: hasNewline ? "\n" : "",
                numbered: parseNumberedLine(in: line)
            ))
            cursor = NSMaxRange(lineRange)
        }

        var replacements: [(range: NSRange, value: String)] = []
        var changedUnion: NSRange?
        var index = 0
        while index < lineRecords.count {
            guard let firstNumbered = lineRecords[index].numbered else {
                index += 1
                continue
            }

            var expectedNumber = firstNumbered.number
            let key = firstNumbered.sequenceKey
            while index < lineRecords.count,
                  let numbered = lineRecords[index].numbered,
                  numbered.sequenceKey == key {
                let expectedString = "\(expectedNumber)"
                let currentString = "\(numbered.number)"
                if expectedString != currentString {
                    let absoluteRange = NSRange(
                        location: lineRecords[index].range.location + numbered.numberRangeInLine.location,
                        length: numbered.numberRangeInLine.length
                    )
                    replacements.append((absoluteRange, expectedString))
                    changedUnion = changedUnion.map { NSUnionRange($0, absoluteRange) } ?? absoluteRange
                }
                expectedNumber += 1
                index += 1
            }
        }

        guard !replacements.isEmpty else { return false }
        let adjustedSelection = adjustedSelection(oldSelection, after: replacements)
        applyNumberReplacements(replacements, adjustedSelection: adjustedSelection, changedUnion: changedUnion, oldVisibleOrigin: oldVisibleOrigin)
        return true
    }

    private func renumberNumberedRunAround(location: Int) -> Bool {
        guard let textStorage else { return false }
        let oldSelection = selectedRange()
        let oldVisibleOrigin = enclosingScrollView?.contentView.bounds.origin
        let nsText = textStorage.string as NSString
        guard nsText.length > 0 else { return false }

        let anchor = max(0, min(location, nsText.length - 1))
        let baseLineRange = nsText.lineRange(for: NSRange(location: anchor, length: 0))
        guard let seed = nearestNumberedLine(around: baseLineRange, in: nsText) else { return false }
        let key = seed.numbered.sequenceKey
        let firstRange = firstNumberedLineRange(inRunContaining: seed.range, key: key, in: nsText)
        var expectedNumber = numberedLine(in: firstRange, source: nsText)?.number ?? seed.numbered.number

        var replacements: [(range: NSRange, value: String)] = []
        var changedUnion: NSRange?
        var currentRange: NSRange? = firstRange
        while let lineRange = currentRange,
              let numbered = numberedLine(in: lineRange, source: nsText),
              numbered.sequenceKey == key {
            let expectedString = "\(expectedNumber)"
            let currentString = "\(numbered.number)"
            if expectedString != currentString {
                let absoluteRange = NSRange(
                    location: lineRange.location + numbered.numberRangeInLine.location,
                    length: numbered.numberRangeInLine.length
                )
                replacements.append((absoluteRange, expectedString))
                changedUnion = changedUnion.map { NSUnionRange($0, absoluteRange) } ?? absoluteRange
            }
            expectedNumber += 1
            currentRange = nextLineRange(after: NSMaxRange(lineRange), in: nsText)
        }

        guard !replacements.isEmpty else { return false }
        let adjustedSelection = adjustedSelection(oldSelection, after: replacements)
        applyNumberReplacements(
            replacements,
            adjustedSelection: adjustedSelection,
            changedUnion: changedUnion,
            oldVisibleOrigin: oldVisibleOrigin
        )
        return true
    }

    private func nearestNumberedLine(
        around lineRange: NSRange,
        in nsText: NSString
    ) -> (range: NSRange, numbered: MarkdownNumberedLine)? {
        if let numbered = numberedLine(in: lineRange, source: nsText) {
            return (lineRange, numbered)
        }
        if let previous = previousLineRange(before: lineRange.location, in: nsText),
           let numbered = numberedLine(in: previous, source: nsText) {
            return (previous, numbered)
        }
        if let next = nextLineRange(after: NSMaxRange(lineRange), in: nsText),
           let numbered = numberedLine(in: next, source: nsText) {
            return (next, numbered)
        }
        return nil
    }

    private func firstNumberedLineRange(
        inRunContaining seedRange: NSRange,
        key: String,
        in nsText: NSString
    ) -> NSRange {
        var firstRange = seedRange
        var previous = previousLineRange(before: firstRange.location, in: nsText)
        while let previousRange = previous,
              let numbered = numberedLine(in: previousRange, source: nsText),
              numbered.sequenceKey == key {
            firstRange = previousRange
            previous = previousLineRange(before: firstRange.location, in: nsText)
        }
        return firstRange
    }

    private func numberedLine(in lineRange: NSRange, source nsText: NSString) -> MarkdownNumberedLine? {
        let safeRange = NSIntersectionRange(lineRange, NSRange(location: 0, length: nsText.length))
        guard safeRange.length > 0 else { return nil }
        var line = nsText.substring(with: safeRange)
        if line.hasSuffix("\n") { line.removeLast() }
        return parseNumberedLine(in: line)
    }

    private func renumberNumberedHierarchyMove(
        movedLineLocation: Int,
        oldKey: String,
        oldNumber: Int,
        newKey: String
    ) -> Bool {
        guard let textStorage else { return false }
        let oldSelection = selectedRange()
        let oldVisibleOrigin = enclosingScrollView?.contentView.bounds.origin
        let lineRecords = numberedLineRecords(in: textStorage.string as NSString)
        guard let movedIndex = lineRecords.firstIndex(where: { $0.range.location == movedLineLocation }),
              lineRecords[movedIndex].numbered != nil else {
            return renumberAllNumberedRunsPreservingSelection()
        }

        var replacements: [(range: NSRange, value: String)] = []
        var changedUnion: NSRange?

        func addReplacement(recordIndex: Int, value: Int) {
            guard let numbered = lineRecords[recordIndex].numbered else { return }
            let valueString = "\(value)"
            guard valueString != "\(numbered.number)" else { return }
            let absoluteRange = NSRange(
                location: lineRecords[recordIndex].range.location + numbered.numberRangeInLine.location,
                length: numbered.numberRangeInLine.length
            )
            replacements.append((absoluteRange, valueString))
            changedUnion = changedUnion.map { NSUnionRange($0, absoluteRange) } ?? absoluteRange
        }

        var oldExpectedNumber = oldNumber + 1
        var scanIndex = movedIndex + 1
        while scanIndex < lineRecords.count,
              let numbered = lineRecords[scanIndex].numbered,
              numbered.sequenceKey == oldKey,
              numbered.number == oldExpectedNumber {
            addReplacement(recordIndex: scanIndex, value: oldExpectedNumber - 1)
            oldExpectedNumber += 1
            scanIndex += 1
        }

        let insertedNumber: Int
        var previousSameLevelNumber: Int?
        if movedIndex > 0 {
            var probeIndex = movedIndex - 1
            while probeIndex >= 0 {
                if let previousNumbered = lineRecords[probeIndex].numbered,
                   previousNumbered.sequenceKey == newKey {
                    previousSameLevelNumber = previousNumbered.number
                    break
                }
                if probeIndex == 0 { break }
                probeIndex -= 1
            }
        }
        insertedNumber = (previousSameLevelNumber ?? 0) + 1
        addReplacement(recordIndex: movedIndex, value: insertedNumber)

        var newExpectedNumber = insertedNumber + 1
        scanIndex = movedIndex + 1
        while scanIndex < lineRecords.count,
              let numbered = lineRecords[scanIndex].numbered,
              numbered.sequenceKey == newKey {
            addReplacement(recordIndex: scanIndex, value: newExpectedNumber)
            newExpectedNumber += 1
            scanIndex += 1
        }

        guard !replacements.isEmpty else { return false }
        let adjustedSelection = adjustedSelection(oldSelection, after: replacements)
        applyNumberReplacements(replacements, adjustedSelection: adjustedSelection, changedUnion: changedUnion, oldVisibleOrigin: oldVisibleOrigin)
        return true
    }

    private func numberedLineRecords(
        in nsText: NSString
    ) -> [(range: NSRange, text: String, terminator: String, numbered: MarkdownNumberedLine?)] {
        var lineRecords: [(range: NSRange, text: String, terminator: String, numbered: MarkdownNumberedLine?)] = []
        var cursor = 0
        while cursor < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
            let lineWithTerminator = nsText.substring(with: lineRange)
            let hasNewline = lineWithTerminator.hasSuffix("\n")
            let line = hasNewline ? String(lineWithTerminator.dropLast()) : lineWithTerminator
            lineRecords.append((
                range: lineRange,
                text: line,
                terminator: hasNewline ? "\n" : "",
                numbered: parseNumberedLine(in: line)
            ))
            cursor = NSMaxRange(lineRange)
        }
        return lineRecords
    }

    private func applyNumberReplacements(
        _ replacements: [(range: NSRange, value: String)],
        adjustedSelection: NSRange,
        changedUnion: NSRange?,
        oldVisibleOrigin: NSPoint?
    ) {
        guard let textStorage else { return }
        textStorage.beginEditing()
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            textStorage.replaceCharacters(in: replacement.range, with: replacement.value)
        }
        textStorage.endEditing()
        setSelectedRange(adjustedSelection)
        if let oldVisibleOrigin {
            enclosingScrollView?.contentView.setBoundsOrigin(oldVisibleOrigin)
        }
        if let changedUnion, let currentDocumentStyle {
            applyMarkdownStyle(in: expandedLineRange(for: changedUnion), style: currentDocumentStyle, layers: [.block, .inline])
            if let oldVisibleOrigin {
                enclosingScrollView?.contentView.setBoundsOrigin(oldVisibleOrigin)
            }
        }
    }

    private func adjustedSelection(
        _ selection: NSRange,
        after replacements: [(range: NSRange, value: String)]
    ) -> NSRange {
        func adjustedLocation(_ location: Int) -> Int {
            var adjusted = location
            for replacement in replacements {
                guard replacement.range.location < location else { continue }
                let delta = (replacement.value as NSString).length - replacement.range.length
                adjusted += delta
            }
            return max(0, adjusted)
        }

        let adjustedStart = adjustedLocation(selection.location)
        let adjustedEnd = adjustedLocation(NSMaxRange(selection))
        let textLength = textStorage?.length ?? 0
        let safeStart = max(0, min(adjustedStart, textLength))
        let safeEnd = max(safeStart, min(adjustedEnd, textLength))
        return NSRange(location: safeStart, length: safeEnd - safeStart)
    }

    func keepInsertionPointComfortablyVisible() {
        scrollInsertionPointToComfortZone()
        DispatchQueue.main.async { [weak self] in
            self?.scrollInsertionPointToComfortZone()
        }
    }

    private func scrollInsertionPointToComfortZone() {
        guard let scrollView = enclosingScrollView else {
            scrollRangeToVisible(selectedRange())
            return
        }

        let textLength = (string as NSString).length
        let selection = selectedRange()
        let insertionLocation = max(0, min(selection.location, textLength))
        let insertionRange = NSRange(location: insertionLocation, length: 0)
        scrollRangeToVisible(insertionRange)

        guard selection.length == 0,
              let window,
              !scrollView.contentView.bounds.isEmpty else {
            return
        }

        let caretScreenRect = firstRect(forCharacterRange: insertionRange, actualRange: nil)
        guard !caretScreenRect.isEmpty else { return }

        let caretWindowRect = window.convertFromScreen(caretScreenRect)
        let caretRect = convert(caretWindowRect, from: nil)
        let clipView = scrollView.contentView
        let visibleRect = convert(clipView.bounds, from: clipView)
        guard !visibleRect.isEmpty else { return }

        let lowerComfortMargin = max(72, min(180, visibleRect.height * 0.24))
        let upperComfortMargin: CGFloat = 32
        var targetOrigin = clipView.bounds.origin

        if isFlipped {
            let lowerComfortY = visibleRect.maxY - lowerComfortMargin
            if caretRect.maxY > lowerComfortY {
                targetOrigin.y += caretRect.maxY - lowerComfortY
            } else if caretRect.minY < visibleRect.minY + upperComfortMargin {
                targetOrigin.y -= (visibleRect.minY + upperComfortMargin) - caretRect.minY
            }
        } else {
            let lowerComfortY = visibleRect.minY + lowerComfortMargin
            if caretRect.minY < lowerComfortY {
                targetOrigin.y -= lowerComfortY - caretRect.minY
            } else if caretRect.maxY > visibleRect.maxY - upperComfortMargin {
                targetOrigin.y += caretRect.maxY - (visibleRect.maxY - upperComfortMargin)
            }
        }

        let maxY = max(0, bounds.height - clipView.bounds.height)
        targetOrigin.y = max(0, min(targetOrigin.y, maxY))
        guard abs(targetOrigin.y - clipView.bounds.origin.y) > 0.5 else { return }
        clipView.setBoundsOrigin(targetOrigin)
        scrollView.reflectScrolledClipView(clipView)
    }
}

private final class MarkdownTextKit2InlineAttachment: NSTextAttachment {
    static let renderScale: CGFloat = 2

    init(image: NSImage?, width: CGFloat, height: CGFloat) {
        super.init(data: nil, ofType: nil)
        self.image = image
        self.bounds = NSRect(x: 0, y: 0, width: max(0, width), height: max(0, height))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

private extension String {
    func trimmingSuffixNewline() -> String {
        hasSuffix("\n") ? String(dropLast()) : self
    }
}

// MARK: - 原生文本编辑器 - v12 - 使用统一高亮引擎并支持搜索命中高亮与定位提示
struct MarkdownNativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var targetUTF16Offset: Int?
    var workingDirectoryURL: URL?
    var highlightMode: MarkdownHighlightMode = .source(MarkdownDocumentStyle())
    var quickInputSettings: MarkdownQuickInputSettings = .init()
    var searchQuery: String = ""
    var activeSearchRange: NSRange?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        let textView = MarkdownTextView()
        textView.font = markdownResolvedFont(name: appleSystemMonospacedFontName, size: 14)
        textView.isRichText = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.string = text
        textView.highlightMode = highlightMode
        textView.quickInputSettings = quickInputSettings
        textView.workingDirectoryURL = workingDirectoryURL
        textView.updateSearchHighlights(query: searchQuery, activeRange: activeSearchRange)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.applyHighlightMode(forceFullDocument: true)
        MarkdownEditorPerformanceProbe.end(
            "MarkdownNativeTextEditor.makeNSView",
            start: profileStart,
            details: MarkdownEditorPerformanceProbe.textDetails(text)
        )

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            let syncStart = MarkdownEditorPerformanceProbe.start()
            textView.string = text
            context.coordinator.applyHighlightMode(forceFullDocument: true)
            MarkdownEditorPerformanceProbe.end(
                "MarkdownNativeTextEditor.updateNSView.externalTextSync",
                start: syncStart,
                details: MarkdownEditorPerformanceProbe.textDetails(text)
            )
        }

        if textView.highlightMode != highlightMode {
            let modeStart = MarkdownEditorPerformanceProbe.start()
            textView.highlightMode = highlightMode
            context.coordinator.applyHighlightMode(forceFullDocument: true)
            MarkdownEditorPerformanceProbe.end(
                "MarkdownNativeTextEditor.updateNSView.highlightMode",
                start: modeStart,
                details: MarkdownEditorPerformanceProbe.textDetails(textView.string)
            )
        }

        if textView.quickInputSettings != quickInputSettings {
            textView.quickInputSettings = quickInputSettings
        }
        textView.workingDirectoryURL = workingDirectoryURL

        let searchStart = MarkdownEditorPerformanceProbe.start()
        textView.updateSearchHighlights(query: searchQuery, activeRange: activeSearchRange)
        MarkdownEditorPerformanceProbe.end(
            "MarkdownNativeTextEditor.updateNSView.searchHighlights",
            start: searchStart,
            details: "queryLength=\((searchQuery as NSString).length),\(MarkdownEditorPerformanceProbe.textDetails(textView.string))"
        )

        if let offset = targetUTF16Offset {
            if context.coordinator.lastConsumedTargetOffset != offset {
                let jumpStart = MarkdownEditorPerformanceProbe.start()
                let location = min(max(offset, 0), (textView.string as NSString).length)
                textView.setSelectedRange(NSRange(location: location, length: 0))
                textView.scrollRangeToVisible(NSRange(location: location, length: 0))
                context.coordinator.lastConsumedTargetOffset = offset
                MarkdownEditorPerformanceProbe.end(
                    "MarkdownNativeTextEditor.updateNSView.jumpToOffset",
                    start: jumpStart,
                    details: "offset=\(offset),location=\(location)"
                )
            }
        } else {
            context.coordinator.lastConsumedTargetOffset = nil
        }
        MarkdownEditorPerformanceProbe.end(
            "MarkdownNativeTextEditor.updateNSView",
            start: profileStart,
            details: MarkdownEditorPerformanceProbe.textDetails(textView.string)
        )

    }

    // MARK: - 编辑器协调器 - v9 - 管理统一富文本刷新定位消费快捷输入并同步搜索高亮
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownNativeTextEditor
        weak var textView: MarkdownTextView?
        var pendingEditedRange: NSRange?
        var lastConsumedTargetOffset: Int?
        private var pendingDeletionLog = "none"
        private var pendingDeletionKind: EditorDeletionKind = .none
        private var pendingBindingText: String?
        private var pendingBindingWorkItem: DispatchWorkItem?
        private var pendingSearchWorkItem: DispatchWorkItem?

        init(_ parent: MarkdownNativeTextEditor) {
            self.parent = parent
        }

        deinit {
            pendingBindingWorkItem?.cancel()
            pendingSearchWorkItem?.cancel()
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            let profileStart = MarkdownEditorPerformanceProbe.start()
            guard let markdownTextView = textView as? MarkdownTextView else { return true }
            pendingEditedRange = replacedRange(from: affectedCharRange, replacementString: replacementString)
            if (replacementString ?? "").isEmpty, affectedCharRange.length > 0 {
                let diagnosis = EditorDeletionClassifier.diagnoseDeletion(
                    source: textView.string as NSString,
                    affectedRange: affectedCharRange,
                    protectedPrefixLengthForLine: markdownProtectedPrefixLengthForDeletion
                )
                pendingDeletionLog = diagnosis.logSummary
                pendingDeletionKind = diagnosis.kind
            } else {
                pendingDeletionLog = "none"
                pendingDeletionKind = .none
            }
            markdownTextView.prepareTypingAttributesIfNeeded(at: affectedCharRange.location)
            MarkdownEditorPerformanceProbe.end(
                "MarkdownNativeTextEditor.shouldChangeText",
                start: profileStart,
                details: "affected={\(affectedCharRange.location),\(affectedCharRange.length)},replacementUtf16=\(((replacementString ?? "") as NSString).length),deletion=\(pendingDeletionLog)"
            )
            return true
        }

        func textDidChange(_ notification: Notification) {
            let profileStart = MarkdownEditorPerformanceProbe.start()
            guard let textView else { return }
            guard !textView.isApplyingQuickInputReplacement else { return }

            let quickInputStart = MarkdownEditorPerformanceProbe.start()
            if textView.applyQuickInputIfNeeded() {
                pendingEditedRange = textView.selectedRange()
            }
            MarkdownEditorPerformanceProbe.end(
                "MarkdownNativeTextEditor.textDidChange.quickInput",
                start: quickInputStart,
                details: MarkdownEditorPerformanceProbe.textDetails(textView.string)
            )

            let usesInlineDeletionFastPath = pendingDeletionKind == .inlineCharacter
            let bindingStart = MarkdownEditorPerformanceProbe.start()
            if usesInlineDeletionFastPath {
                scheduleBindingSync(textView.string, delay: 0.04)
            } else {
                flushPendingBindingSync()
                parent.text = textView.string
            }
            MarkdownEditorPerformanceProbe.end(
                "MarkdownNativeTextEditor.textDidChange.bindingSync",
                start: bindingStart,
                details: "\(MarkdownEditorPerformanceProbe.textDetails(textView.string)),deferred=\(usesInlineDeletionFastPath)"
            )
            switch textView.highlightMode {
            case let .source(style), let .instant(style):
                let highlightStart = MarkdownEditorPerformanceProbe.start()
                if usesInlineDeletionFastPath {
                    MarkdownEditorPerformanceProbe.end(
                        "MarkdownNativeTextEditor.textDidChange.inlineDeletionHighlightSkipped",
                        start: highlightStart,
                        details: pendingDeletionLog
                    )
                } else if let pendingEditedRange {
                    textView.applyInstantStyleIncrementally(for: pendingEditedRange, style: style)
                } else {
                    textView.applyInstantStyleIncrementally(for: textView.selectedRange(), style: style)
                }
                MarkdownEditorPerformanceProbe.end(
                    "MarkdownNativeTextEditor.textDidChange.incrementalHighlight",
                    start: highlightStart,
                    details: MarkdownEditorPerformanceProbe.textDetails(textView.string)
                )
                pendingEditedRange = nil
                let typingStart = MarkdownEditorPerformanceProbe.start()
                textView.prepareTypingAttributesIfNeeded(at: textView.selectedRange().location)
                MarkdownEditorPerformanceProbe.end(
                    "MarkdownNativeTextEditor.textDidChange.typingAttributes",
                    start: typingStart,
                    details: "location=\(textView.selectedRange().location)"
                )
                if usesInlineDeletionFastPath {
                    scheduleSearchHighlightRefreshIfNeeded(on: textView, delay: 0.12)
                } else {
                    let searchStart = MarkdownEditorPerformanceProbe.start()
                    textView.updateSearchHighlights(query: parent.searchQuery, activeRange: parent.activeSearchRange)
                    MarkdownEditorPerformanceProbe.end(
                        "MarkdownNativeTextEditor.textDidChange.searchHighlights",
                        start: searchStart,
                        details: "queryLength=\((parent.searchQuery as NSString).length),\(MarkdownEditorPerformanceProbe.textDetails(textView.string))"
                    )
                }
            }
            MarkdownEditorPerformanceProbe.end(
                "MarkdownNativeTextEditor.textDidChange",
                start: profileStart,
                details: "\(MarkdownEditorPerformanceProbe.textDetails(textView.string)),deletion=\(pendingDeletionLog)"
            )
            pendingDeletionLog = "none"
            pendingDeletionKind = .none
        }

        private func scheduleBindingSync(_ text: String, delay: TimeInterval) {
            pendingBindingText = text
            pendingBindingWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.flushPendingBindingSync()
            }
            pendingBindingWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        private func flushPendingBindingSync() {
            pendingBindingWorkItem?.cancel()
            pendingBindingWorkItem = nil
            guard let text = pendingBindingText else { return }
            pendingBindingText = nil
            parent.text = text
        }

        private func scheduleSearchHighlightRefreshIfNeeded(on textView: MarkdownTextView, delay: TimeInterval) {
            guard !parent.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            pendingSearchWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                let searchStart = MarkdownEditorPerformanceProbe.start()
                textView.updateSearchHighlights(query: self.parent.searchQuery, activeRange: self.parent.activeSearchRange)
                MarkdownEditorPerformanceProbe.end(
                    "MarkdownNativeTextEditor.delayedSearchHighlights",
                    start: searchStart,
                    details: "queryLength=\((self.parent.searchQuery as NSString).length),\(MarkdownEditorPerformanceProbe.textDetails(textView.string))"
                )
            }
            pendingSearchWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        func applyHighlightMode(forceFullDocument: Bool) {
            let profileStart = MarkdownEditorPerformanceProbe.start()
            guard let textView else { return }
            switch textView.highlightMode {
            case let .source(style), let .instant(style):
                if forceFullDocument {
                    textView.applyInstantStyleToEntireDocument(style: style)
                } else {
                    textView.applyInstantStyleIncrementally(for: textView.selectedRange(), style: style)
                }
                textView.prepareTypingAttributesIfNeeded(at: textView.selectedRange().location)
                textView.updateSearchHighlights(query: parent.searchQuery, activeRange: parent.activeSearchRange)
            }
            MarkdownEditorPerformanceProbe.end(
                "MarkdownNativeTextEditor.applyHighlightMode",
                start: profileStart,
                details: "forceFullDocument=\(forceFullDocument),\(MarkdownEditorPerformanceProbe.textDetails(textView.string))"
            )
        }

        private func replacedRange(from affectedRange: NSRange, replacementString: String?) -> NSRange {
            let replacementLength = (replacementString ?? "") as NSString
            return NSRange(location: affectedRange.location, length: replacementLength.length)
        }
    }
}

// MARK: - 文本编辑实现 - v10 - 修复双目快捷输入按闭合触发整体替换并保持单目即时替换
final class MarkdownTextView: NSTextView {
    var workingDirectoryURL: URL?
    var highlightMode: MarkdownHighlightMode = .source(MarkdownDocumentStyle())
    var quickInputSettings = MarkdownQuickInputSettings()
    var isApplyingQuickInputReplacement = false
    private var searchHighlightRanges: [NSRange] = []
    private var searchActiveRange: NSRange?
    private var searchBlinkTimer: Timer?
    private var searchBlinkVisible = true

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleMarkdownImagePasteShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleMarkdownImagePasteShortcut(event) { return }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        if insertPastedMarkdownImageIfAvailable() { return }
        super.paste(sender)
    }

    private func handleMarkdownImagePasteShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.shift),
              !flags.contains(.option),
              !flags.contains(.control),
              event.charactersIgnoringModifiers?.lowercased() == "v" else {
            return false
        }
        return insertPastedMarkdownImageIfAvailable()
    }

    private func insertPastedMarkdownImageIfAvailable() -> Bool {
        guard NodeMarkdownImageAssetService.hasPastedImage(),
              let markdownDirectoryURL = workingDirectoryURL,
              let selectedURL = NodeMarkdownImageAssetService.pastedImageURL() else {
            return false
        }
        let removesTemporaryImage = NodeMarkdownImageAssetService.isTemporaryPastedImageURL(selectedURL)
        defer {
            if removesTemporaryImage { try? FileManager.default.removeItem(at: selectedURL) }
        }
        guard let insertion = NodeMarkdownImageAssetService.insertMarkdownImage(
            selectedURL: selectedURL,
            markdownDirectoryURL: markdownDirectoryURL
        ) else {
            NSSound.beep()
            return true
        }
        insertText(insertion.htmlSnippet, replacementRange: selectedRange())
        return true
    }

    func applyInstantStyleToEntireDocument(style: MarkdownDocumentStyle) {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        guard let textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        applyInstantStyle(in: fullRange, style: style)
        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextView.applyInstantStyleToEntireDocument",
            start: profileStart,
            details: MarkdownEditorPerformanceProbe.rangeDetails(fullRange, textLength: textStorage.length)
        )
    }

    func applyInstantStyleIncrementally(for editedRange: NSRange, style: MarkdownDocumentStyle) {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        guard let textStorage else { return }
        let totalLength = textStorage.length
        guard totalLength >= 0 else { return }
        let safeRange = NSRange(
            location: max(0, min(editedRange.location, totalLength)),
            length: max(0, min(editedRange.length, totalLength - max(0, min(editedRange.location, totalLength))))
        )
        let expandedLocation = max(0, safeRange.location - 1)
        let expandedUpperBound = min(totalLength, NSMaxRange(safeRange) + 1)
        let expandedRange = NSRange(location: expandedLocation, length: max(0, expandedUpperBound - expandedLocation))
        let nsText = textStorage.string as NSString
        let lineRange = nsText.lineRange(for: expandedRange)
        applyInstantStyle(in: lineRange, style: style)
        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextView.applyInstantStyleIncrementally",
            start: profileStart,
            details: "edited={\(editedRange.location),\(editedRange.length)},line={\(lineRange.location),\(lineRange.length)},utf16=\(totalLength)"
        )
    }

    func prepareTypingAttributesIfNeeded(at location: Int) {
        let style: MarkdownDocumentStyle
        switch highlightMode {
        case .source(let value), .instant(let value):
            style = value
        }
        let lineStyle = lineRoleStyle(at: location, style: style)
        let paragraphStyle = paragraphStyleForCurrentLine(at: location)
        let font = markdownResolvedFont(name: lineStyle.fontName, size: lineStyle.fontSize)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(lineStyle.renderedColor)
        ]
        if let paragraphStyle {
            attributes[.paragraphStyle] = paragraphStyle
        }
        typingAttributes = attributes
    }

    private func applyInstantStyle(in targetRange: NSRange, style: MarkdownDocumentStyle) {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        guard let textStorage else { return }
        let totalLength = textStorage.length
        let safeRange = NSRange(
            location: max(0, min(targetRange.location, totalLength)),
            length: max(0, min(targetRange.length, totalLength - max(0, min(targetRange.location, totalLength))))
        )
        guard safeRange.length >= 0 else { return }

        let nsText = textStorage.string as NSString
        let actualLineRange = nsText.lineRange(for: safeRange)
        let selectedRange = selectedRange()
        textStorage.beginEditing()

        let bodyAttributes = bodyAttributes(for: style.body)
        textStorage.setAttributes(bodyAttributes, range: actualLineRange)

        var lineLocation = actualLineRange.location
        while lineLocation < NSMaxRange(actualLineRange) {
            let lineRange = nsText.lineRange(for: NSRange(location: lineLocation, length: 0))
            if lineRange.length == 0 { break }

            var rawLine = nsText.substring(with: lineRange)
            if rawLine.hasSuffix("\n") { rawLine.removeLast() }

            if let headingLevel = parseHeadingLevelForStyling(in: rawLine) {
                applyRoleStyle(style.headingStyle(level: headingLevel), to: textStorage, range: lineRange)
            } else if parseCommentLine(rawLine) != nil {
                applyRoleStyle(style.comment, to: textStorage, range: lineRange)
            }

            applyMarkdownHangingIndentStyle(to: textStorage, rawLine: rawLine, range: lineRange)

            for codeRange in parseInlineCodeRanges(in: rawLine, base: lineRange.location) {
                let codeFont = NSFont.monospacedSystemFont(ofSize: style.body.fontSize, weight: .regular)
                textStorage.addAttributes([
                    .font: codeFont,
                    .foregroundColor: NSColor.systemOrange,
                    .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.28)
                ], range: codeRange)
            }

            for strongRange in parseInlineStrongRanges(in: rawLine, base: lineRange.location) {
                let existingFont = (textStorage.attribute(.font, at: max(0, min(strongRange.location, max(0, textStorage.length - 1))), effectiveRange: nil) as? NSFont) ?? markdownResolvedFont(name: style.body.fontName, size: style.body.fontSize)
                let boldFont = NSFont.monospacedSystemFont(ofSize: existingFont.pointSize, weight: .bold)
                textStorage.addAttributes([
                    .font: boldFont,
                    .foregroundColor: NSColor.systemOrange
                ], range: strongRange)
            }

            for italicRange in parseInlineItalicRanges(in: rawLine, base: lineRange.location) {
                let existingFont = (textStorage.attribute(.font, at: max(0, min(italicRange.location, max(0, textStorage.length - 1))), effectiveRange: nil) as? NSFont) ?? markdownResolvedFont(name: style.body.fontName, size: style.body.fontSize)
                let italicFont = NSFontManager.shared.convert(existingFont, toHaveTrait: .italicFontMask)
                textStorage.addAttributes([
                    .font: italicFont
                ], range: italicRange)
            }

            for linkRange in parseInlineLinkLabelRanges(in: rawLine, base: lineRange.location) {
                textStorage.addAttributes([
                    .foregroundColor: NSColor.systemBlue,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ], range: linkRange)
            }

            for mathRange in parseInlineMathRanges(in: rawLine, base: lineRange.location) {
                textStorage.addAttributes([
                    .foregroundColor: NSColor.systemCyan
                ], range: mathRange)
            }

            for highlightRange in parseInlineHighlightRanges(in: rawLine, base: lineRange.location) {
                textStorage.addAttributes([
                    .foregroundColor: NSColor.labelColor,
                    .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.35)
                ], range: highlightRange)
            }

            for underlineRange in parseInlineUnderlineRanges(in: rawLine, base: lineRange.location) {
                textStorage.addAttributes([
                    .foregroundColor: NSColor.systemBlue,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ], range: underlineRange)
            }

            lineLocation = NSMaxRange(lineRange)
        }

        textStorage.endEditing()
        setSelectedRange(selectedRange)
        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextView.applyInstantStyle",
            start: profileStart,
            details: MarkdownEditorPerformanceProbe.rangeDetails(actualLineRange, textLength: totalLength)
        )
    }

    private func lineRoleStyle(at location: Int, style: MarkdownDocumentStyle) -> MarkdownRoleStyle {
        let rawLine = caretLineText(at: location)
        if let headingLevel = parseHeadingLevelForStyling(in: rawLine) {
            return style.headingStyle(level: headingLevel)
        }
        if parseCommentLine(rawLine) != nil {
            return style.comment
        }
        return style.body
    }

    private func paragraphStyleForCurrentLine(at location: Int) -> NSParagraphStyle? {
        let rawLine = caretLineText(at: location)
        let style: MarkdownDocumentStyle
        switch highlightMode {
        case .source(let value), .instant(let value):
            style = value
        }
        let lineStyle = lineRoleStyle(at: location, style: style)
        let font = markdownResolvedFont(name: lineStyle.fontName, size: lineStyle.fontSize)
        return markdownHangingParagraphStyle(for: rawLine, font: font)
    }

    private func caretLineRange(at location: Int, in nsText: NSString) -> NSRange {
        let safeLocation = max(0, min(location, nsText.length))
        if isAtTrailingEmptyLine(caretLocation: safeLocation, text: nsText) {
            return NSRange(location: safeLocation, length: 0)
        }
        return nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
    }

    private func caretLineText(at location: Int) -> String {
        let nsText = string as NSString
        let lineRange = caretLineRange(at: location, in: nsText)
        guard lineRange.length > 0 else { return "" }
        var rawLine = nsText.substring(with: lineRange)
        if rawLine.hasSuffix("\n") { rawLine.removeLast() }
        return rawLine
    }

    private func bodyAttributes(for style: MarkdownRoleStyle) -> [NSAttributedString.Key: Any] {
        let font = markdownResolvedFont(name: style.fontName, size: style.fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: font,
            .foregroundColor: NSColor(style.renderedColor),
            .paragraphStyle: paragraph
        ]
    }

    func applyQuickInputIfNeeded() -> Bool {
        guard !isApplyingQuickInputReplacement else { return false }
        guard let textStorage else { return false }
        let selection = selectedRange()
        guard selection.length == 0 else { return false }

        let nsText = string as NSString
        let caret = max(0, min(selection.location, nsText.length))
        let prefix = nsText.substring(to: caret)

        if applyPairQuickInputIfNeeded(textStorage: textStorage, prefix: prefix, caret: caret) {
            return true
        }

        for candidate in quickInputSingleCandidates() {
            guard !candidate.trigger.isEmpty else { continue }
            guard candidate.replacement != candidate.trigger else { continue }
            guard prefix.hasSuffix(candidate.trigger) else { continue }

            let triggerLength = (candidate.trigger as NSString).length
            let replacementLength = (candidate.replacement as NSString).length
            let start = caret - triggerLength
            guard start >= 0 else { continue }

            isApplyingQuickInputReplacement = true
            textStorage.beginEditing()
            textStorage.replaceCharacters(in: NSRange(location: start, length: triggerLength), with: candidate.replacement)
            textStorage.endEditing()
            setSelectedRange(NSRange(location: start + replacementLength, length: 0))
            isApplyingQuickInputReplacement = false
            return true
        }
        return false
    }

    private func applyPairQuickInputIfNeeded(textStorage: NSTextStorage, prefix: String, caret: Int) -> Bool {
        let nsPrefix = prefix as NSString

        for pairRule in quickInputPairCandidates() {
            let openTrigger = pairRule.openTrigger
            let closeTrigger = pairRule.closeTrigger
            guard !openTrigger.isEmpty, !closeTrigger.isEmpty else { continue }
            guard pairRule.openReplacement != openTrigger || pairRule.closeReplacement != closeTrigger else { continue }
            guard prefix.hasSuffix(closeTrigger) else { continue }

            let closeLength = (closeTrigger as NSString).length
            let openLength = (openTrigger as NSString).length
            let closeStart = caret - closeLength
            guard closeStart >= 0 else { continue }

            let searchRange = NSRange(location: 0, length: closeStart)
            let openRange = nsPrefix.range(of: openTrigger, options: .backwards, range: searchRange)
            guard openRange.location != NSNotFound else { continue }

            let contentStart = openRange.location + openLength
            guard contentStart <= closeStart else { continue }
            let contentLength = closeStart - contentStart
            let content = nsPrefix.substring(with: NSRange(location: contentStart, length: contentLength))
            let replacement = pairRule.openReplacement + content + pairRule.closeReplacement

            isApplyingQuickInputReplacement = true
            textStorage.beginEditing()
            textStorage.replaceCharacters(
                in: NSRange(location: openRange.location, length: caret - openRange.location),
                with: replacement
            )
            textStorage.endEditing()
            setSelectedRange(NSRange(location: openRange.location + (replacement as NSString).length, length: 0))
            isApplyingQuickInputReplacement = false
            return true
        }

        return false
    }

    private func quickInputSingleCandidates() -> [(trigger: String, replacement: String)] {
        quickInputSettings.singleRules
            .map { ($0.trigger, $0.replacement) }
            .sorted {
            ($0.trigger as NSString).length > ($1.trigger as NSString).length
        }
    }

    private func quickInputPairCandidates() -> [MarkdownPairShortcutRule] {
        quickInputSettings.pairRules.sorted {
            let lhsClose = ($0.closeTrigger as NSString).length
            let rhsClose = ($1.closeTrigger as NSString).length
            if lhsClose != rhsClose {
                return lhsClose > rhsClose
            }
            return ($0.openTrigger as NSString).length > ($1.openTrigger as NSString).length
        }
    }

    func updateSearchHighlights(query: String, activeRange: NSRange?) {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        clearSearchHighlights()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            MarkdownEditorPerformanceProbe.end(
                "MarkdownTextView.updateSearchHighlights.empty",
                start: profileStart,
                details: MarkdownEditorPerformanceProbe.textDetails(string)
            )
            return
        }
        guard let layoutManager else { return }

        let nsText = string as NSString
        searchHighlightRanges = markdownFindSearchRanges(in: nsText, query: trimmedQuery)

        for range in searchHighlightRanges {
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: NSColor.systemBlue.withAlphaComponent(0.22),
                forCharacterRange: range
            )
            layoutManager.addTemporaryAttribute(
                .foregroundColor,
                value: NSColor.systemBlue,
                forCharacterRange: range
            )
        }

        if let activeRange {
            searchActiveRange = activeRange
            applyActiveSearchBlinkState()
            startSearchBlinkTimer()
        }
        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextView.updateSearchHighlights",
            start: profileStart,
            details: "queryLength=\((trimmedQuery as NSString).length),matches=\(searchHighlightRanges.count),\(MarkdownEditorPerformanceProbe.textDetails(string))"
        )
    }

    private func clearSearchHighlights() {
        let profileStart = MarkdownEditorPerformanceProbe.start()
        stopSearchBlinkTimer()
        guard let layoutManager else { return }
        let clearedCount = searchHighlightRanges.count
        for range in searchHighlightRanges {
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        }
        if let searchActiveRange {
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: searchActiveRange)
        }
        searchHighlightRanges = []
        searchActiveRange = nil
        searchBlinkVisible = true
        MarkdownEditorPerformanceProbe.end(
            "MarkdownTextView.clearSearchHighlights",
            start: profileStart,
            details: "cleared=\(clearedCount),\(MarkdownEditorPerformanceProbe.textDetails(string))"
        )
    }

    private func startSearchBlinkTimer() {
        stopSearchBlinkTimer()
        searchBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.searchBlinkVisible.toggle()
            self.applyActiveSearchBlinkState()
        }
        RunLoop.main.add(searchBlinkTimer!, forMode: .common)
    }

    private func stopSearchBlinkTimer() {
        searchBlinkTimer?.invalidate()
        searchBlinkTimer = nil
    }

    private func applyActiveSearchBlinkState() {
        guard let layoutManager, let searchActiveRange else { return }
        layoutManager.addTemporaryAttribute(
            .backgroundColor,
            value: searchBlinkVisible ? NSColor.systemBlue.withAlphaComponent(0.55) : NSColor.systemBlue.withAlphaComponent(0.30),
            forCharacterRange: searchActiveRange
        )
    }

    deinit {
        stopSearchBlinkTimer()
    }

    override func insertTab(_ sender: Any?) {
        if applyHierarchyTabAction(isShift: false) {
            return
        }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if applyHierarchyTabAction(isShift: true) {
            return
        }
        super.insertBacktab(sender)
    }

    override func insertNewline(_ sender: Any?) {
        let shiftPressed = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
        if shiftPressed {
            super.insertNewline(sender)
            return
        }

        if applyAutoContinueRule() {
            return
        }

        super.insertNewline(sender)
        enforceBodyTypingAttributesForEmptyLine()
    }

    private func enforceBodyTypingAttributesForEmptyLine() {
        let style: MarkdownDocumentStyle
        switch highlightMode {
        case .source(let value), .instant(let value):
            style = value
        }
        let selection = selectedRange()
        let rawLine = caretLineText(at: selection.location)
        if rawLine.trimmingCharacters(in: .whitespaces).isEmpty {
            let font = markdownResolvedFont(name: style.body.fontName, size: style.body.fontSize)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            typingAttributes = [
                .font: font,
                .foregroundColor: NSColor(style.body.renderedColor),
                .paragraphStyle: paragraph
            ]
        }
    }

    private func isAtTrailingEmptyLine(caretLocation: Int, text: NSString) -> Bool {
        guard caretLocation == text.length, text.length > 0 else { return false }
        return text.character(at: text.length - 1) == 10
    }

    private func applyHierarchyTabAction(isShift: Bool) -> Bool {
        guard let textStorage else { return false }
        let selection = selectedRange()
        if selection.length > 0 {
            return applyHierarchyTabActionForSelectedLines(
                textStorage: textStorage,
                selection: selection,
                isShift: isShift
            )
        }

        let nsText = string as NSString
        let caret = max(0, min(selection.location, nsText.length))
        let lineAnchor = max(0, min(caret > 0 ? caret - 1 : caret, nsText.length))
        let lineRange = nsText.lineRange(for: NSRange(location: lineAnchor, length: 0))
        var line = nsText.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }
        let caretOffsetInLine = max(0, caret - lineRange.location)

        if let heading = parseHeadingForHierarchy(in: line) {
            let content = heading.content
            let oldPrefixLength = heading.prefixLength

            if isShift {
                if heading.level == 1 {
                    return true
                }
                let newPrefix = String(repeating: "#", count: heading.level - 1) + " "
                replaceCurrentLineForHierarchy(
                    textStorage: textStorage,
                    lineRange: lineRange,
                    oldPrefixLength: oldPrefixLength,
                    newPrefix: newPrefix,
                    content: content,
                    caretOffsetInLine: caretOffsetInLine
                )
                return true
            }

            if heading.level == 6 {
                replaceCurrentLineForHierarchy(
                    textStorage: textStorage,
                    lineRange: lineRange,
                    oldPrefixLength: oldPrefixLength,
                    newPrefix: "- ",
                    content: content,
                    caretOffsetInLine: caretOffsetInLine
                )
                return true
            }

            let newPrefix = String(repeating: "#", count: heading.level + 1) + " "
            replaceCurrentLineForHierarchy(
                textStorage: textStorage,
                lineRange: lineRange,
                oldPrefixLength: oldPrefixLength,
                newPrefix: newPrefix,
                content: content,
                caretOffsetInLine: caretOffsetInLine
            )
            return true
        }

        if let bullet = parseBulletForHierarchy(in: line) {
            let oldPrefixLength = bullet.prefixLength
            let content = bullet.content

            if isShift {
                if bullet.indentSpaces == 0 {
                    replaceCurrentLineForHierarchy(
                        textStorage: textStorage,
                        lineRange: lineRange,
                        oldPrefixLength: oldPrefixLength,
                        newPrefix: "###### ",
                        content: content,
                        caretOffsetInLine: caretOffsetInLine
                    )
                    return true
                }

                let newIndent = max(0, bullet.indentSpaces - 2)
                let newPrefix = String(repeating: " ", count: newIndent) + "- "
                replaceCurrentLineForHierarchy(
                    textStorage: textStorage,
                    lineRange: lineRange,
                    oldPrefixLength: oldPrefixLength,
                    newPrefix: newPrefix,
                    content: content,
                    caretOffsetInLine: caretOffsetInLine
                )
                return true
            }

            let newPrefix = String(repeating: " ", count: bullet.indentSpaces + 2) + "- "
            replaceCurrentLineForHierarchy(
                textStorage: textStorage,
                lineRange: lineRange,
                oldPrefixLength: oldPrefixLength,
                newPrefix: newPrefix,
                content: content,
                caretOffsetInLine: caretOffsetInLine
            )
            return true
        }

        if !isShift, !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let leadingSpaces = line.prefix { $0 == " " }.count
            let newPrefix = String(repeating: " ", count: leadingSpaces) + "- "
            let content = String(line.dropFirst(leadingSpaces))
            replaceCurrentLineForHierarchy(
                textStorage: textStorage,
                lineRange: lineRange,
                oldPrefixLength: leadingSpaces,
                newPrefix: newPrefix,
                content: content,
                caretOffsetInLine: caretOffsetInLine
            )
            return true
        }

        return false
    }

    private func applyHierarchyTabActionForSelectedLines(
        textStorage: NSTextStorage,
        selection: NSRange,
        isShift: Bool
    ) -> Bool {
        let nsText = string as NSString
        guard nsText.length > 0 else { return false }

        let safeLocation = max(0, min(selection.location, nsText.length))
        let safeUpperBound = max(safeLocation, min(selection.location + selection.length, nsText.length))
        let endAnchor = max(safeLocation, min(nsText.length, safeUpperBound - 1))

        let startLineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
        let endLineRange = nsText.lineRange(for: NSRange(location: endAnchor, length: 0))
        let replaceRange = NSRange(
            location: startLineRange.location,
            length: (endLineRange.location + endLineRange.length) - startLineRange.location
        )

        var cursor = replaceRange.location
        var rebuilt = ""
        var handledAny = false
        var changedAny = false

        while cursor < replaceRange.location + replaceRange.length {
            let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
            let lineWithTerminator = nsText.substring(with: lineRange)
            let hasTrailingNewline = lineWithTerminator.hasSuffix("\n")
            let line = hasTrailingNewline ? String(lineWithTerminator.dropLast()) : lineWithTerminator

            let action = hierarchyAction(for: line, isShift: isShift)
            handledAny = handledAny || action.handled
            changedAny = changedAny || (action.newLine != line)
            rebuilt += action.newLine
            if hasTrailingNewline {
                rebuilt += "\n"
            }

            cursor = lineRange.location + lineRange.length
        }

        guard handledAny else { return false }
        guard changedAny else { return true }

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: replaceRange, with: rebuilt)
        textStorage.endEditing()

        let updatedLength = (rebuilt as NSString).length
        setSelectedRange(NSRange(location: replaceRange.location, length: updatedLength))
        didChangeText()
        return true
    }

    private func hierarchyAction(for line: String, isShift: Bool) -> (handled: Bool, newLine: String) {
        if let heading = parseHeadingForHierarchy(in: line) {
            let content = heading.content
            if isShift {
                if heading.level == 1 {
                    return (true, line)
                }
                let newPrefix = String(repeating: "#", count: heading.level - 1) + " "
                return (true, newPrefix + content)
            }

            if heading.level == 6 {
                return (true, "- " + content)
            }

            let newPrefix = String(repeating: "#", count: heading.level + 1) + " "
            return (true, newPrefix + content)
        }

        if let bullet = parseBulletForHierarchy(in: line) {
            let content = bullet.content
            if isShift {
                if bullet.indentSpaces == 0 {
                    return (true, "###### " + content)
                }
                let newIndent = max(0, bullet.indentSpaces - 2)
                let newPrefix = String(repeating: " ", count: newIndent) + "- "
                return (true, newPrefix + content)
            }

            let newPrefix = String(repeating: " ", count: bullet.indentSpaces + 2) + "- "
            return (true, newPrefix + content)
        }

        guard !isShift, !line.trimmingCharacters(in: .whitespaces).isEmpty else {
            return (false, line)
        }
        let leadingSpaces = line.prefix { $0 == " " }.count
        let content = String(line.dropFirst(leadingSpaces))
        let newPrefix = String(repeating: " ", count: leadingSpaces) + "- "
        return (true, newPrefix + content)
    }

    private func replaceCurrentLineForHierarchy(
        textStorage: NSTextStorage,
        lineRange: NSRange,
        oldPrefixLength: Int,
        newPrefix: String,
        content: String,
        caretOffsetInLine: Int
    ) {
        let originalLineText = (string as NSString).substring(with: lineRange)
        let hasTrailingNewline = originalLineText.hasSuffix("\n")
        let replaceRange: NSRange = hasTrailingNewline
            ? NSRange(location: lineRange.location, length: max(0, lineRange.length - 1))
            : lineRange

        let newLine = newPrefix + content
        let oldContentOffset = max(0, caretOffsetInLine - oldPrefixLength)
        let newCaretOffset = min((newLine as NSString).length, (newPrefix as NSString).length + oldContentOffset)

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: replaceRange, with: newLine)
        textStorage.endEditing()

        setSelectedRange(NSRange(location: replaceRange.location + newCaretOffset, length: 0))
        didChangeText()
    }

    private func parseHeadingForHierarchy(in line: String) -> (level: Int, prefixLength: Int, content: String)? {
        guard let level = parseHeadingLevelForStyling(in: line) else { return nil }
        let prefixLength = level + 1
        guard line.count >= prefixLength else {
            return (level, prefixLength, "")
        }
        let start = line.index(line.startIndex, offsetBy: prefixLength)
        return (level, prefixLength, String(line[start...]))
    }

    private func parseBulletForHierarchy(in line: String) -> (indentSpaces: Int, prefixLength: Int, content: String)? {
        let indentCount = line.prefix { $0 == " " }.count
        let remaining = String(line.dropFirst(indentCount))
        guard remaining.hasPrefix("- ") else { return nil }
        let content = String(remaining.dropFirst(2))
        return (indentCount, indentCount + 2, content)
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
        setSelectedRange(NSRange(location: adjustedLocation, length: 0))
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

// MARK: - NSAttributedString扩展 - v1 - 封装Markdown到富文本的系统转换
extension NSAttributedString {
    convenience init(markdown: String) {
        if let attributed = try? AttributedString(markdown: markdown) {
            self.init(attributed)
        } else {
            self.init(string: markdown)
        }
    }
}

#Preview {
    MarkdownEditorView(fileURL: URL(fileURLWithPath: "/tmp/demo.md"))
}
