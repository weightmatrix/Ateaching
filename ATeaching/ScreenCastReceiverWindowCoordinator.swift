#if os(macOS)
import AppKit

@MainActor
enum ScreenCastReceiverWindowCoordinator {
    private static var hiddenWindows: [NSWindow] = []

    static func enterExclusiveReceiving() {
        hiddenWindows = NSApplication.shared.windows.filter { window in
            window.isVisible && (window.title.hasPrefix("Markdown-") || window.title.hasPrefix("Node-"))
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

