import Foundation

enum AppDisplayTitle {
    static let appName = "李知本授课管理"
    static let mainWindowBaseTitle = appName

    static var defaultMainWindowTitle: String {
        mainWindowTitle(forPage: "授课")
    }

    static func mainWindowTitle(forPage pageTitle: String) -> String {
        #if os(macOS)
        return "\(pageTitle)·\(appName)·V\(shortVersion)"
        #else
        return "\(pageTitle)·\(appName)"
        #endif
    }

    private static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }
}
