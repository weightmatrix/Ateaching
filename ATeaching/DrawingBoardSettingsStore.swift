import SwiftUI

#if os(macOS)
import AppKit

// MARK: - 画图设置存储 - v1 - 持久化画笔橡皮文字吸附虚线等默认状态
struct DrawingBoardSettings: Codable, Equatable {
    var strokeColor: DrawingBoardColorRecord = DrawingBoardColorRecord(color: .black)
    var lineWidth: Double = 3
    var eraserModeRawValue: String = EraserMode.stroke.rawValue
    var eraserSize: Double = 24
    var textFontSize: Double = 18
    var textFontName: String = "Helvetica Neue"
    var isSnapEnabled: Bool = true
    var dashedShapeMode: Bool = false

    var eraserMode: EraserMode {
        EraserMode(rawValue: eraserModeRawValue) ?? .stroke
    }
}

struct DrawingBoardColorRecord: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .black
        red = Double(nsColor.redComponent)
        green = Double(nsColor.greenComponent)
        blue = Double(nsColor.blueComponent)
        alpha = Double(nsColor.alphaComponent)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

enum DrawingBoardSettingsStore {
    private static let fileName = "setting-画图.json"
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private static let decoder = JSONDecoder()

    static func load(fileManager: FileManager = .default) -> DrawingBoardSettings {
        guard let url = try? settingsURL(fileManager: fileManager),
              let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode(DrawingBoardSettings.self, from: data) else {
            return DrawingBoardSettings()
        }
        return normalized(decoded)
    }

    static func save(_ settings: DrawingBoardSettings, fileManager: FileManager = .default) {
        guard let url = try? settingsURL(fileManager: fileManager),
              let data = try? encoder.encode(normalized(settings)) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private static func settingsURL(fileManager: FileManager = .default) throws -> URL {
        let workspaceURL = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let settingsURL = workspaceURL.appendingPathComponent(ArchiveStorage.settingsFolderName, isDirectory: true)
        try fileManager.createDirectory(at: settingsURL, withIntermediateDirectories: true)
        return settingsURL.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func normalized(_ settings: DrawingBoardSettings) -> DrawingBoardSettings {
        var result = settings
        result.lineWidth = min(16, max(1, result.lineWidth))
        result.eraserSize = min(80, max(4, result.eraserSize))
        result.textFontSize = min(52, max(12, result.textFontSize))
        if !EraserMode.allCases.contains(where: { $0.rawValue == result.eraserModeRawValue }) {
            result.eraserModeRawValue = EraserMode.stroke.rawValue
        }
        if result.textFontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.textFontName = "Helvetica Neue"
        }
        return result
    }
}
#endif
