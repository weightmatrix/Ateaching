import Foundation

#if os(macOS)
import AppKit

@MainActor
enum ScreenCastViewportMonitor {
    static func sample(enabledKinds: Set<ScreenCastContentKind>) -> ScreenCastViewport? {
        guard let window = NSApplication.shared.keyWindow,
              window.isVisible,
              window.isMiniaturized == false,
              let contentView = window.contentView,
              let kind = contentKind(for: window),
              enabledKinds.contains(kind),
              let scrollView = largestEditorScrollView(in: contentView),
              let documentView = scrollView.documentView else { return nil }

        let clip = scrollView.contentView
        let maximumX = max(0, documentView.bounds.width - clip.bounds.width)
        let maximumY = max(0, documentView.bounds.height - clip.bounds.height)
        let horizontal = maximumX > 0 ? Double(clip.bounds.minX / maximumX) : 0
        let vertical = maximumY > 0 ? Double(clip.bounds.minY / maximumY) : 0

        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let localPoint = scrollView.convert(windowPoint, from: nil)
        let pointerIsInside = scrollView.bounds.contains(localPoint)
        let pointerX = pointerIsInside ? Double(localPoint.x / max(1, scrollView.bounds.width)) : nil
        let pointerY = pointerIsInside ? Double(localPoint.y / max(1, scrollView.bounds.height)) : nil

        return ScreenCastViewport(
            kind: kind,
            horizontalFraction: clamped(horizontal),
            verticalFraction: clamped(vertical),
            sourceViewportWidth: Double(clip.bounds.width),
            sourceViewportHeight: Double(clip.bounds.height),
            pointerX: pointerX.map(clamped),
            pointerY: pointerY.map(clamped)
        )
    }

    private static func contentKind(for window: NSWindow) -> ScreenCastContentKind? {
        if window.title.hasPrefix("Markdown-") { return .markdown }
        if window.title.hasPrefix("Node-") || TeachingClassSessionCenter.shared.session != nil { return .teaching }
        return nil
    }

    private static func largestEditorScrollView(in root: NSView) -> NSScrollView? {
        var candidates: [NSScrollView] = []
        collectScrollViews(in: root, into: &candidates)
        return candidates
            .filter { $0.isHidden == false && $0.alphaValue > 0 && $0.bounds.width > 100 && $0.bounds.height > 100 }
            .max { lhs, rhs in lhs.bounds.width * lhs.bounds.height < rhs.bounds.width * rhs.bounds.height }
    }

    private static func collectScrollViews(in view: NSView, into result: inout [NSScrollView]) {
        if let scrollView = view as? NSScrollView, scrollView.documentView != nil {
            result.append(scrollView)
        }
        for subview in view.subviews {
            collectScrollViews(in: subview, into: &result)
        }
    }

    private static func clamped(_ value: Double) -> Double {
        max(0, min(1, value.isFinite ? value : 0))
    }
}

#else
import UIKit

@MainActor
enum ScreenCastViewportMonitor {
    static func sample(enabledKinds: Set<ScreenCastContentKind>) -> ScreenCastViewport? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: \.isKeyWindow),
              let root = window.rootViewController?.view,
              let scrollView = largestScrollView(in: root) else { return nil }

        let kind: ScreenCastContentKind = TeachingClassSessionCenter.shared.session == nil ? .markdown : .teaching
        guard enabledKinds.contains(kind) else { return nil }
        let maximumX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let maximumY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        return ScreenCastViewport(
            kind: kind,
            horizontalFraction: maximumX > 0 ? Double(max(0, min(1, scrollView.contentOffset.x / maximumX))) : 0,
            verticalFraction: maximumY > 0 ? Double(max(0, min(1, scrollView.contentOffset.y / maximumY))) : 0,
            sourceViewportWidth: Double(scrollView.bounds.width),
            sourceViewportHeight: Double(scrollView.bounds.height),
            pointerX: nil,
            pointerY: nil
        )
    }

    private static func largestScrollView(in root: UIView) -> UIScrollView? {
        var candidates: [UIScrollView] = []
        collectScrollViews(in: root, into: &candidates)
        return candidates
            .filter { $0.isHidden == false && $0.alpha > 0 && $0.bounds.width > 100 && $0.bounds.height > 100 }
            .max { lhs, rhs in lhs.bounds.width * lhs.bounds.height < rhs.bounds.width * rhs.bounds.height }
    }

    private static func collectScrollViews(in view: UIView, into result: inout [UIScrollView]) {
        if let scrollView = view as? UIScrollView { result.append(scrollView) }
        view.subviews.forEach { collectScrollViews(in: $0, into: &result) }
    }
}
#endif
