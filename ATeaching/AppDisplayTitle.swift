import Foundation

enum AppDisplayTitle {
    static let appName = "李知本·授课"
    static let mainWindowBaseTitle = "主窗口"

    static var defaultMainWindowTitle: String {
        "🏠·主窗口·\(shortVersion)"
    }

    static func mainWindowTitle(forPage pageTitle: String) -> String {
        "\(pageTitle == "教学" ? "授课" : pageTitle)·李知本授课系统"
    }

    private static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }
}
