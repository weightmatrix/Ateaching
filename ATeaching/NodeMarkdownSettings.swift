import SwiftUI
import Combine

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - NodeMarkdown样式角色 - v2 - 定义H1-H6正文5层与注释共12类样式
enum NodeMarkdownStyleRole: String, CaseIterable, Identifiable {
    case h1 = "H1"
    case h2 = "H2"
    case h3 = "H3"
    case h4 = "H4"
    case h5 = "H5"
    case h6 = "H6"
    case body1 = "正文1"
    case body2 = "正文2"
    case body3 = "正文3"
    case body4 = "正文4"
    case body5 = "正文5"
    case comment = "注释"

    var id: String { rawValue }

    static let orderedByLevel: [NodeMarkdownStyleRole] = [
        .h1, .h2, .h3, .h4, .h5, .h6,
        .body1, .body2, .body3, .body4, .body5,
        .comment
    ]

    var level: Int {
        switch self {
        case .h1: 1
        case .h2: 2
        case .h3: 3
        case .h4: 4
        case .h5: 5
        case .h6: 6
        case .body1: 7
        case .body2: 8
        case .body3: 9
        case .body4: 10
        case .body5: 11
        case .comment: 12
        }
    }

    /// 12层Node结构到样式角色的唯一映射。编辑器、设置页和导出都必须经过这里，
    /// 禁止各自使用`level - n`下标换算，避免正文3/正文4发生错位或串色。
    static func role(forLevel rawLevel: Int) -> NodeMarkdownStyleRole {
        orderedByLevel[max(1, min(12, rawLevel)) - 1]
    }
}

// MARK: - NodeMarkdown深浅模式 - v1 - 支持系统固定浅色固定深色三种模式
enum NodeMarkdownPreferredScheme: String, Codable, Hashable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    // 导出文件必须拥有确定的配色，不能继续携带随系统变化的动态颜色。
    // 文档固定深色时按深色导出；固定浅色或跟随系统时按浅色导出。
    var resolvedExportScheme: NodeMarkdownPreferredScheme {
        self == .dark ? .dark : .light
    }
}

// MARK: - NodeMarkdown语义颜色 - v1 - 定义可持久化的深浅自适应语义色
enum NodeMarkdownSemanticColor: String, Codable, Hashable {
    case adaptiveBlackWhite

    var color: Color {
        switch self {
        case .adaptiveBlackWhite:
            return .primary
        }
    }
}

// MARK: - NodeMarkdown行样式 - v2 - 记录字体大小颜色粗体下划线背景条配置
struct NodeMarkdownRoleStyle: Hashable {
    var fontName: String
    var fontSize: Double
    var color: Color
    var semanticColor: NodeMarkdownSemanticColor?
    var isBold: Bool
    var isUnderline: Bool
    var hasBackgroundBar: Bool
    var paragraphSpacingBefore: Double
    var paragraphSpacingAfter: Double
    var peerLineSpacing: Double

    init(
        fontName: String,
        fontSize: Double,
        color: Color,
        semanticColor: NodeMarkdownSemanticColor?,
        isBold: Bool,
        isUnderline: Bool = false,
        hasBackgroundBar: Bool,
        paragraphSpacingBefore: Double,
        paragraphSpacingAfter: Double,
        peerLineSpacing: Double
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
        self.semanticColor = semanticColor
        self.isBold = isBold
        self.isUnderline = isUnderline
        self.hasBackgroundBar = hasBackgroundBar
        self.paragraphSpacingBefore = paragraphSpacingBefore
        self.paragraphSpacingAfter = paragraphSpacingAfter
        self.peerLineSpacing = peerLineSpacing
    }

    var renderedColor: Color {
        semanticColor?.color ?? color
    }

    func scaledFontSize(_ factor: Double) -> NodeMarkdownRoleStyle {
        var value = self
        value.fontSize = max(1, fontSize * factor)
        return value
    }
}

// MARK: - NodeMarkdown图标配置 - v1 - 定义12层前缀图标
struct NodeMarkdownLevelIconConfig: Codable, Hashable {
    var symbols: [String] = [
        "1",
        "(1)",
        "•",
        "○",
        "▪",
        "▫",
        "•",
        "◦",
        "▪",
        "▫",
        "•",
        ">"
    ]

    func symbol(for level: Int) -> String {
        guard (1...12).contains(level), symbols.indices.contains(level - 1) else { return "•" }
        return symbols[level - 1]
    }
}

// MARK: - NodeMarkdown文档样式 - v2 - 聚合角色样式背景色深浅模式与12层图标配置
struct NodeMarkdownDocumentStyle: Hashable {
    var h1 = NodeMarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 30, color: markdownHexColor(0x26619C), semanticColor: nil, isBold: true, hasBackgroundBar: false, paragraphSpacingBefore: 10, paragraphSpacingAfter: 8, peerLineSpacing: 0)
    var h2 = NodeMarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 26, color: markdownHexColor(0x1C39BB), semanticColor: nil, isBold: true, hasBackgroundBar: false, paragraphSpacingBefore: 8, paragraphSpacingAfter: 6, peerLineSpacing: 0)
    var h3 = NodeMarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 22, color: markdownHexColor(0x50C878), semanticColor: nil, isBold: true, hasBackgroundBar: true, paragraphSpacingBefore: 6, paragraphSpacingAfter: 5, peerLineSpacing: 0)
    var h4 = NodeMarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 20, color: markdownHexColor(0x702963), semanticColor: nil, isBold: false, hasBackgroundBar: true, paragraphSpacingBefore: 4, paragraphSpacingAfter: 4, peerLineSpacing: 0)
    var h5 = NodeMarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 18, color: markdownHexColor(0xC41E3A), semanticColor: nil, isBold: false, hasBackgroundBar: true, paragraphSpacingBefore: 3, paragraphSpacingAfter: 3, peerLineSpacing: 0)
    var h6 = NodeMarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 16, color: .primary, semanticColor: .adaptiveBlackWhite, isBold: false, hasBackgroundBar: false, paragraphSpacingBefore: 2, paragraphSpacingAfter: 2, peerLineSpacing: 0)
    var body1 = NodeMarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 15, color: .primary, semanticColor: .adaptiveBlackWhite, isBold: false, hasBackgroundBar: false, paragraphSpacingBefore: 1, paragraphSpacingAfter: 1, peerLineSpacing: 2)
    var body2 = NodeMarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 15, color: .primary, semanticColor: .adaptiveBlackWhite, isBold: false, hasBackgroundBar: false, paragraphSpacingBefore: 1, paragraphSpacingAfter: 1, peerLineSpacing: 2)
    var body3 = NodeMarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 15, color: .primary, semanticColor: .adaptiveBlackWhite, isBold: false, hasBackgroundBar: false, paragraphSpacingBefore: 1, paragraphSpacingAfter: 1, peerLineSpacing: 2)
    var body4 = NodeMarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 15, color: .primary, semanticColor: .adaptiveBlackWhite, isBold: false, hasBackgroundBar: false, paragraphSpacingBefore: 1, paragraphSpacingAfter: 1, peerLineSpacing: 2)
    var body5 = NodeMarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 15, color: .primary, semanticColor: .adaptiveBlackWhite, isBold: false, hasBackgroundBar: false, paragraphSpacingBefore: 1, paragraphSpacingAfter: 1, peerLineSpacing: 2)
    var comment = NodeMarkdownRoleStyle(fontName: appleSystemMonospacedFontName, fontSize: 14, color: .secondary, semanticColor: nil, isBold: false, hasBackgroundBar: false, paragraphSpacingBefore: 1, paragraphSpacingAfter: 1, peerLineSpacing: 1)
    var editorBackgroundColor: Color = .white
    var useSystemBackground: Bool = true
    var preferredScheme: NodeMarkdownPreferredScheme = .system
    var iconConfig: NodeMarkdownLevelIconConfig = .init()
    /// 仅由黑白导出副本启用，不写入设置文件；用于让高亮与背景条在黑白打印时仍有清晰边界。
    var usesMonochromeDecorationBorders = false

    mutating func update(_ style: NodeMarkdownRoleStyle, for role: NodeMarkdownStyleRole) {
        switch role {
        case .h1: h1 = style
        case .h2: h2 = style
        case .h3: h3 = style
        case .h4: h4 = style
        case .h5: h5 = style
        case .h6: h6 = style
        case .body1: body1 = style
        case .body2: body2 = style
        case .body3: body3 = style
        case .body4: body4 = style
        case .body5: body5 = style
        case .comment: comment = style
        }
    }

    func style(for role: NodeMarkdownStyleRole) -> NodeMarkdownRoleStyle {
        switch role {
        case .h1: h1
        case .h2: h2
        case .h3: h3
        case .h4: h4
        case .h5: h5
        case .h6: h6
        case .body1: body1
        case .body2: body2
        case .body3: body3
        case .body4: body4
        case .body5: body5
        case .comment: comment
        }
    }

    func style(forLevel level: Int) -> NodeMarkdownRoleStyle {
        style(for: NodeMarkdownStyleRole.role(forLevel: level))
    }

    var platformDisplayStyle: NodeMarkdownDocumentStyle {
        #if os(iOS)
        return fontScaled(by: 0.5)
        #else
        return self
        #endif
    }

    func fontScaled(by factor: Double) -> NodeMarkdownDocumentStyle {
        var value = self
        value.h1 = h1.scaledFontSize(factor)
        value.h2 = h2.scaledFontSize(factor)
        value.h3 = h3.scaledFontSize(factor)
        value.h4 = h4.scaledFontSize(factor)
        value.h5 = h5.scaledFontSize(factor)
        value.h6 = h6.scaledFontSize(factor)
        value.body1 = body1.scaledFontSize(factor)
        value.body2 = body2.scaledFontSize(factor)
        value.body3 = body3.scaledFontSize(factor)
        value.body4 = body4.scaledFontSize(factor)
        value.body5 = body5.scaledFontSize(factor)
        value.comment = comment.scaledFontSize(factor)
        return value
    }

    /// 黑白PDF保留排版结构，只移除背景和文字中的彩色语义。
    var monochromeExportStyle: NodeMarkdownDocumentStyle {
        var value = self
        value.useSystemBackground = false
        value.editorBackgroundColor = .white
        value.preferredScheme = .light
        value.usesMonochromeDecorationBorders = true
        for role in NodeMarkdownStyleRole.allCases {
            var roleStyle = value.style(for: role)
            roleStyle.color = .black
            roleStyle.semanticColor = nil
            value.update(roleStyle, for: role)
        }
        return value
    }
}

// MARK: - NodeMarkdown颜色存储记录 - v1 - 为JSON文件编码颜色与语义色
struct NodeMarkdownColorRecord: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
    var semanticColor: NodeMarkdownSemanticColor?

    init(color: Color, semanticColor: NodeMarkdownSemanticColor?) {
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

    var styleColor: (Color, NodeMarkdownSemanticColor?) {
        if let semanticColor {
            return (semanticColor.color, semanticColor)
        }
        return (Color(red: red, green: green, blue: blue, opacity: alpha), nil)
    }
}

// MARK: - NodeMarkdown行样式记录 - v1 - 为角色样式提供持久化结构
struct NodeMarkdownRoleStyleRecord: Codable, Hashable {
    var fontName: String
    var fontSize: Double
    var color: NodeMarkdownColorRecord
    var isBold: Bool
    var isUnderline: Bool
    var hasBackgroundBar: Bool
    var paragraphSpacingBefore: Double
    var paragraphSpacingAfter: Double
    var peerLineSpacing: Double

    init(style: NodeMarkdownRoleStyle) {
        fontName = style.fontName
        fontSize = style.fontSize
        color = NodeMarkdownColorRecord(color: style.color, semanticColor: style.semanticColor)
        isBold = style.isBold
        isUnderline = style.isUnderline
        hasBackgroundBar = style.hasBackgroundBar
        paragraphSpacingBefore = style.paragraphSpacingBefore
        paragraphSpacingAfter = style.paragraphSpacingAfter
        peerLineSpacing = style.peerLineSpacing
    }

    private enum CodingKeys: String, CodingKey {
        case fontName
        case fontSize
        case color
        case isBold
        case isUnderline
        case hasBackgroundBar
        case paragraphSpacingBefore
        case paragraphSpacingAfter
        case peerLineSpacing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontName = try container.decode(String.self, forKey: .fontName)
        fontSize = try container.decode(Double.self, forKey: .fontSize)
        color = try container.decode(NodeMarkdownColorRecord.self, forKey: .color)
        isBold = try container.decode(Bool.self, forKey: .isBold)
        isUnderline = try container.decodeIfPresent(Bool.self, forKey: .isUnderline) ?? false
        hasBackgroundBar = try container.decode(Bool.self, forKey: .hasBackgroundBar)
        paragraphSpacingBefore = try container.decodeIfPresent(Double.self, forKey: .paragraphSpacingBefore) ?? 0
        paragraphSpacingAfter = try container.decodeIfPresent(Double.self, forKey: .paragraphSpacingAfter) ?? 0
        peerLineSpacing = try container.decodeIfPresent(Double.self, forKey: .peerLineSpacing) ?? 0
    }

    var style: NodeMarkdownRoleStyle {
        let resolved = color.styleColor
        return NodeMarkdownRoleStyle(
            fontName: fontName,
            fontSize: fontSize,
            color: resolved.0,
            semanticColor: resolved.1,
            isBold: isBold,
            isUnderline: isUnderline,
            hasBackgroundBar: hasBackgroundBar,
            paragraphSpacingBefore: paragraphSpacingBefore,
            paragraphSpacingAfter: paragraphSpacingAfter,
            peerLineSpacing: peerLineSpacing
        )
    }
}

// MARK: - NodeMarkdown文档样式记录 - v2 - 定义NodeMarkdown设置文件结构
struct NodeMarkdownDocumentStyleRecord: Codable, Hashable {
    var h1: NodeMarkdownRoleStyleRecord
    var h2: NodeMarkdownRoleStyleRecord
    var h3: NodeMarkdownRoleStyleRecord
    var h4: NodeMarkdownRoleStyleRecord
    var h5: NodeMarkdownRoleStyleRecord
    var h6: NodeMarkdownRoleStyleRecord
    var body1: NodeMarkdownRoleStyleRecord
    var body2: NodeMarkdownRoleStyleRecord
    var body3: NodeMarkdownRoleStyleRecord
    var body4: NodeMarkdownRoleStyleRecord
    var body5: NodeMarkdownRoleStyleRecord
    var comment: NodeMarkdownRoleStyleRecord
    var editorBackgroundColor: NodeMarkdownColorRecord
    var useSystemBackground: Bool
    var preferredScheme: NodeMarkdownPreferredScheme
    var iconConfig: NodeMarkdownLevelIconConfig

    init(style: NodeMarkdownDocumentStyle) {
        h1 = NodeMarkdownRoleStyleRecord(style: style.h1)
        h2 = NodeMarkdownRoleStyleRecord(style: style.h2)
        h3 = NodeMarkdownRoleStyleRecord(style: style.h3)
        h4 = NodeMarkdownRoleStyleRecord(style: style.h4)
        h5 = NodeMarkdownRoleStyleRecord(style: style.h5)
        h6 = NodeMarkdownRoleStyleRecord(style: style.h6)
        body1 = NodeMarkdownRoleStyleRecord(style: style.body1)
        body2 = NodeMarkdownRoleStyleRecord(style: style.body2)
        body3 = NodeMarkdownRoleStyleRecord(style: style.body3)
        body4 = NodeMarkdownRoleStyleRecord(style: style.body4)
        body5 = NodeMarkdownRoleStyleRecord(style: style.body5)
        comment = NodeMarkdownRoleStyleRecord(style: style.comment)
        editorBackgroundColor = NodeMarkdownColorRecord(color: style.editorBackgroundColor, semanticColor: nil)
        useSystemBackground = style.useSystemBackground
        preferredScheme = style.preferredScheme
        iconConfig = style.iconConfig
    }

    private enum CodingKeys: String, CodingKey {
        case h1, h2, h3, h4, h5, h6
        case body
        case body1, body2, body3, body4, body5
        case comment
        case editorBackgroundColor
        case useSystemBackground
        case preferredScheme
        case iconConfig
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        h1 = try container.decode(NodeMarkdownRoleStyleRecord.self, forKey: .h1)
        h2 = try container.decode(NodeMarkdownRoleStyleRecord.self, forKey: .h2)
        h3 = try container.decode(NodeMarkdownRoleStyleRecord.self, forKey: .h3)
        h4 = try container.decode(NodeMarkdownRoleStyleRecord.self, forKey: .h4)
        h5 = try container.decode(NodeMarkdownRoleStyleRecord.self, forKey: .h5)
        h6 = try container.decode(NodeMarkdownRoleStyleRecord.self, forKey: .h6)

        let legacyBody = try container.decodeIfPresent(NodeMarkdownRoleStyleRecord.self, forKey: .body)
            ?? NodeMarkdownRoleStyleRecord(style: NodeMarkdownDocumentStyle().body1)

        body1 = try container.decodeIfPresent(NodeMarkdownRoleStyleRecord.self, forKey: .body1) ?? legacyBody
        body2 = try container.decodeIfPresent(NodeMarkdownRoleStyleRecord.self, forKey: .body2) ?? legacyBody
        body3 = try container.decodeIfPresent(NodeMarkdownRoleStyleRecord.self, forKey: .body3) ?? legacyBody
        body4 = try container.decodeIfPresent(NodeMarkdownRoleStyleRecord.self, forKey: .body4) ?? legacyBody
        body5 = try container.decodeIfPresent(NodeMarkdownRoleStyleRecord.self, forKey: .body5) ?? legacyBody

        comment = try container.decode(NodeMarkdownRoleStyleRecord.self, forKey: .comment)
        editorBackgroundColor = try container.decode(NodeMarkdownColorRecord.self, forKey: .editorBackgroundColor)
        useSystemBackground = try container.decodeIfPresent(Bool.self, forKey: .useSystemBackground) ?? true
        preferredScheme = try container.decode(NodeMarkdownPreferredScheme.self, forKey: .preferredScheme)
        iconConfig = try container.decode(NodeMarkdownLevelIconConfig.self, forKey: .iconConfig)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(h1, forKey: .h1)
        try container.encode(h2, forKey: .h2)
        try container.encode(h3, forKey: .h3)
        try container.encode(h4, forKey: .h4)
        try container.encode(h5, forKey: .h5)
        try container.encode(h6, forKey: .h6)
        try container.encode(body1, forKey: .body1)
        try container.encode(body2, forKey: .body2)
        try container.encode(body3, forKey: .body3)
        try container.encode(body4, forKey: .body4)
        try container.encode(body5, forKey: .body5)
        try container.encode(comment, forKey: .comment)
        try container.encode(editorBackgroundColor, forKey: .editorBackgroundColor)
        try container.encode(useSystemBackground, forKey: .useSystemBackground)
        try container.encode(preferredScheme, forKey: .preferredScheme)
        try container.encode(iconConfig, forKey: .iconConfig)
    }

    var style: NodeMarkdownDocumentStyle {
        var value = NodeMarkdownDocumentStyle()
        value.h1 = h1.style
        value.h2 = h2.style
        value.h3 = h3.style
        value.h4 = h4.style
        value.h5 = h5.style
        value.h6 = h6.style
        value.body1 = body1.style
        value.body2 = body2.style
        value.body3 = body3.style
        value.body4 = body4.style
        value.body5 = body5.style
        value.comment = comment.style
        value.editorBackgroundColor = editorBackgroundColor.styleColor.0
        value.useSystemBackground = useSystemBackground
        value.preferredScheme = preferredScheme
        value.iconConfig = iconConfig
        return value
    }
}

extension NodeMarkdownDocumentStyle {
    /// 渲染版本必须比较明确的RGBA、语义色和排版值，不能依赖SwiftUI.Color
    /// 的内部对象身份。设置中心、新旧管线和自绘缓存共同使用这一份身份。
    var renderIdentity: NodeMarkdownDocumentStyleRecord {
        NodeMarkdownDocumentStyleRecord(style: self)
    }
}

// MARK: - NodeMarkdown设置存储 - v1 - 独立文档样式文件并共享Markdown快捷输入文件
enum NodeMarkdownSettingsStore {
    private static let styleFileName = "settingnodemarkdown.json"
    private static let tocExpandModeKey = "node_markdown_toc_expand_mode"

    static func loadDocumentStyle() -> NodeMarkdownDocumentStyle? {
        guard let data = try? Data(contentsOf: try styleURL()) else { return nil }
        guard let record = try? JSONDecoder().decode(NodeMarkdownDocumentStyleRecord.self, from: data) else { return nil }
        return record.style
    }

    static func saveDocumentStyle(_ style: NodeMarkdownDocumentStyle) {
        guard let url = try? styleURL() else { return }
        guard let data = try? JSONEncoder().encode(NodeMarkdownDocumentStyleRecord(style: style)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadSharedQuickInputSettings() -> MarkdownQuickInputSettings {
        MarkdownSettingsStore.loadQuickInputSettings() ?? MarkdownQuickInputSettings()
    }

    static func saveSharedQuickInputSettings(_ settings: MarkdownQuickInputSettings) {
        MarkdownSettingsStore.saveQuickInputSettings(settings)
    }

    static func loadTOCExpandModeRawValue() -> String {
        let value = UserDefaults.standard.string(forKey: tocExpandModeKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "l3" : value
    }

    static func saveTOCExpandModeRawValue(_ rawValue: String) {
        UserDefaults.standard.set(rawValue, forKey: tocExpandModeKey)
    }

    private static func styleURL() throws -> URL {
        let settingsFolder = try settingsFolderURL()
        return settingsFolder.appendingPathComponent(styleFileName, isDirectory: false)
    }

    private static func settingsFolderURL(fileManager: FileManager = .default) throws -> URL {
        let documentsRoot = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let settingsFolder = documentsRoot.appendingPathComponent(ArchiveStorage.settingsFolderName, isDirectory: true)
        try fileManager.createDirectory(at: settingsFolder, withIntermediateDirectories: true)
        return settingsFolder
    }
}

// MARK: - NodeMarkdown设置共享中心 - v1 - 提供跨窗口共享样式和快捷输入状态
@MainActor
final class NodeMarkdownSettingsCenter: ObservableObject {
    static let shared = NodeMarkdownSettingsCenter()

    @Published private(set) var documentStyle: NodeMarkdownDocumentStyle
    @Published private(set) var quickInputSettings: MarkdownQuickInputSettings

    private init() {
        documentStyle = NodeMarkdownSettingsStore.loadDocumentStyle() ?? NodeMarkdownDocumentStyle()
        quickInputSettings = NodeMarkdownSettingsStore.loadSharedQuickInputSettings()
    }

    func updateDocumentStyle(_ value: NodeMarkdownDocumentStyle) {
        guard documentStyle.renderIdentity != value.renderIdentity else { return }
        documentStyle = value
        NodeMarkdownSettingsStore.saveDocumentStyle(value)
    }

    func updateQuickInputSettings(_ value: MarkdownQuickInputSettings) {
        guard quickInputSettings != value else { return }
        quickInputSettings = value
        NodeMarkdownSettingsStore.saveSharedQuickInputSettings(value)
    }
}
