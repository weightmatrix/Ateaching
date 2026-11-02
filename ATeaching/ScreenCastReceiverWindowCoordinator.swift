#if os(macOS)
import AppKit

@MainActor
enum ScreenCastReceiverWindowCoordinator {
    private static var hiddenWindows: [NSWindow] = []

    static func enterExclusiveReceiving() {
        hiddenWindows = NSApplication.shared.windows.filter { window in
            window.isVisible && (window.title.hasPrefix("📝·Markdown") || window.title.hasPrefix("🧑‍🏫·上课中") || window.title.hasPrefix("🧩·NodeMarkdown") || window.title.hasPrefix("📚·教案"))
        }
        hiddenWindows.forEach { $0.orderOut(nil) }
    }

    static func leaveExclusiveReceiving() {
        hiddenWindows.forEach { $0.orderFront(nil) }
        hiddenWindows.removeAll()
    }
}
#else
enum ScreenCastReceiverWindowCoordinator {
    static func enterExclusiveReceiving() {}
    static func leaveExclusiveReceiving() {}
}
#endif

