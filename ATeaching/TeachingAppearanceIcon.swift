#if os(macOS)
import AppKit
import OSLog

@MainActor
final class TeachingAppearanceIcon {
    static let shared = TeachingAppearanceIcon()
    private var appearanceObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "Han.ATeaching", category: "AppearanceIcon")

    func start() {
        guard appearanceObserver == nil else { return }
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
    }

    func refresh() {
        let style = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String
        let name = style == "Dark" ? "TeachingIconNight" : "TeachingIconDay"
        guard let image = NSImage(named: NSImage.Name(name)), image.isValid else {
            logger.error("Missing teaching icon: \(name, privacy: .public)")
            return
        }
        NSApp.applicationIconImage = image
        logger.notice("Applied teaching icon: \(name, privacy: .public)")
    }
}
#endif
