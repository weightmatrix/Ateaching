import SwiftUI
import Combine

#if os(macOS)
import AppKit
#endif

// MARK: - 上课批注 - v1 - 临时图层：批注/橡皮/清除，批注内容跟随页面滚动，属于上层临时内容
// 895：上课时在左上角按键组右端加批注按钮群；屏蔽点击编辑、可滚动、内容跟随页面、临时、清除清空、颜色红色
// 896：批注/橡皮按钮激活时高亮；激活状态下再次点击关闭批注状态；笔/橡皮状态互相切换

enum TeachingAnnotationTool: Equatable {
    case pen
    case eraser
}

struct TeachingAnnotationStroke {
    var points: [CGPoint]
    let color: Color
    let lineWidth: CGFloat
}

@MainActor
final class TeachingAnnotationController: ObservableObject {
    @Published var isActive = false
    @Published var tool: TeachingAnnotationTool = .pen
    @Published var strokeCount = 0
    var followsDocument = true
    private(set) var clearToken = 0

    func handlePenTap() {
        if isActive && tool == .pen {
            isActive = false
        } else {
            isActive = true
            tool = .pen
        }
    }

    func handleEraserTap() {
        if isActive && tool == .eraser {
            isActive = false
        } else {
            isActive = true
            tool = .eraser
        }
    }

    func clearAll() {
        clearToken += 1
        strokeCount = 0
    }

    func handleStrokesDidChange(_ count: Int) {
        guard strokeCount != count else { return }
        strokeCount = count
    }
}

extension View {
    /// 必须用于Button的label内部，令透明留白也参与命中，而非仅命中图标笔画。
    func teachingToolbarHitTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - 工具栏按钮群 - 批注（笔）/ 橡皮 / 清除
struct TeachingAnnotationToolbarControl: View {
    @ObservedObject var controller: TeachingAnnotationController

    var body: some View {
        Button {
            controller.handlePenTap()
        } label: {
            Label("批注", systemImage: "pencil.tip")
                .teachingToolbarHitTarget()
        }
        .buttonStyle(.plain)
        .foregroundStyle(penHighlighted ? appHighlightBlue : .primary)
        .help("批注")

        Button {
            controller.handleEraserTap()
        } label: {
            Label("橡皮", systemImage: "eraser")
                .teachingToolbarHitTarget()
        }
        .buttonStyle(.plain)
        .foregroundStyle(eraserHighlighted ? appHighlightBlue : .primary)
        .help("橡皮")

        Button {
            controller.clearAll()
        } label: {
            Label("全删除", systemImage: "trash")
                .teachingToolbarHitTarget()
        }
        .buttonStyle(.plain)
        .disabled(controller.strokeCount == 0)
        .foregroundStyle(controller.strokeCount == 0 ? .secondary : .primary)
    }

    private var penHighlighted: Bool {
        controller.isActive && controller.tool == .pen
    }

    private var eraserHighlighted: Bool {
        controller.isActive && controller.tool == .eraser
    }
}

// MARK: - 批注画布宿主 - SwiftUI 挂载层；macOS 提供原生覆盖画布，iOS 为空视图
struct TeachingAnnotationCanvasHost: View {
    @ObservedObject var controller: TeachingAnnotationController

    var body: some View {
        #if os(macOS)
        AnnotationCanvasRepresentable(controller: controller)
        #else
        TeachingMobileAnnotationCanvas(controller: controller)
        #endif
    }
}

#if os(iOS)
private struct TeachingMobileAnnotationCanvas: View {
    @ObservedObject var controller: TeachingAnnotationController
    @State private var strokes: [[CGPoint]] = []
    @State private var isDrawing = false

    var body: some View {
        Canvas { context, _ in
            for points in strokes {
                guard let first = points.first else { continue }
                var path = Path()
                path.move(to: first)
                if points.count == 1 {
                    path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y))
                } else {
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                context.stroke(path, with: .color(.red), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard controller.isActive else { return }
                if controller.tool == .eraser {
                    strokes.removeAll { points in
                        points.contains { hypot($0.x - value.location.x, $0.y - value.location.y) < 14 }
                    }
                } else {
                    if !isDrawing { strokes.append([]); isDrawing = true }
                    strokes[strokes.count - 1].append(value.location)
                }
                controller.handleStrokesDidChange(strokes.count)
            }
            .onEnded { _ in isDrawing = false })
        .onChange(of: controller.clearToken) { _, _ in
            strokes.removeAll()
            isDrawing = false
        }
    }
}
#endif

#if os(macOS)
private struct AnnotationCanvasRepresentable: NSViewRepresentable {
    @ObservedObject var controller: TeachingAnnotationController

    func makeNSView(context: Context) -> TeachingAnnotationCanvasView {
        let view = TeachingAnnotationCanvasView()
        view.controller = controller
        return view
    }

    func updateNSView(_ nsView: TeachingAnnotationCanvasView, context: Context) {
        nsView.controller = controller
        nsView.tool = controller.tool
        if nsView.lastAppliedClearToken != controller.clearToken {
            nsView.lastAppliedClearToken = controller.clearToken
            nsView.removeAllStrokes()
        }
    }
}
#endif

#if os(macOS)

// MARK: - 批注覆盖画布 - 覆盖在编辑器上方，拦截鼠标（屏蔽点击编辑）、转发滚动（可滚动），批注跟随页面
final class TeachingAnnotationCanvasView: NSView {
    weak var controller: TeachingAnnotationController?
    var tool: TeachingAnnotationTool = .pen
    var lastAppliedClearToken = 0

    private var strokes: [TeachingAnnotationStroke] = []
    private var activeStrokeIndex: Int?
    private weak var scrollView: NSScrollView?
    private weak var observedClipView: NSClipView?

    static let strokeColor = Color.red
    static let strokeLineWidth: CGFloat = 3
    static let eraserHitRadius: CGFloat = 10

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.ensureScrollViewAttached()
        }
    }

    override func layout() {
        super.layout()
        ensureScrollViewAttached()
    }

    private func ensureScrollViewAttached() {
        guard controller?.followsDocument != false else { return }
        guard let window else { return }
        let foundScrollView: NSScrollView
        if let scrollView {
            foundScrollView = scrollView
        } else {
            guard let contentView = window.contentView,
                  let candidate = Self.findEditorScrollView(in: contentView) else {
                return
            }
            scrollView = candidate
            foundScrollView = candidate
        }
        let clipView = foundScrollView.contentView
        guard observedClipView !== clipView else { return }
        if let observedClipView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: observedClipView
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.frameDidChangeNotification,
                object: observedClipView
            )
        }
        observedClipView = clipView
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClipViewDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClipViewFrameDidChange),
            name: NSView.frameDidChangeNotification,
            object: clipView
        )
        setNeedsDisplay(bounds)
    }

    private static func findEditorScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView,
           scrollView.documentView is NSTextView || scrollView.documentView is NSTableView {
            return scrollView
        }
        for subview in view.subviews {
            if let found = findEditorScrollView(in: subview) {
                return found
            }
        }
        return nil
    }

    @objc private func handleClipViewDidScroll() {
        setNeedsDisplay(bounds)
    }

    @objc private func handleClipViewFrameDidChange() {
        setNeedsDisplay(bounds)
    }

    // MARK: 滚动事件转发 - 批注激活时仍可滚动页面

    override func scrollWheel(with event: NSEvent) {
        guard controller?.followsDocument != false else { return }
        ensureScrollViewAttached()
        if let scrollView {
            scrollView.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        guard controller?.followsDocument != false else { return }
        ensureScrollViewAttached()
        if let scrollView {
            scrollView.magnify(with: event)
        } else {
            super.magnify(with: event)
        }
    }

    // MARK: 绘制 - 批注点在文档坐标系，按当前滚动偏移换算到屏幕坐标

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let origin = scrollOrigin
        NSColor(Self.strokeColor).setStroke()
        for stroke in strokes {
            drawStroke(stroke, origin: origin)
        }
    }

    private func drawStroke(_ stroke: TeachingAnnotationStroke, origin: NSPoint) {
        guard !stroke.points.isEmpty else { return }
        let screenPoints = stroke.points.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }
        let path = NSBezierPath()
        path.lineWidth = stroke.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if screenPoints.count == 1 {
            path.appendArc(
                withCenter: screenPoints[0],
                radius: max(stroke.lineWidth / 2, 1),
                startAngle: 0,
                endAngle: 360
            )
        } else if screenPoints.count == 2 {
            path.move(to: screenPoints[0])
            path.line(to: screenPoints[1])
        } else {
            path.move(to: screenPoints[0])
            let lastIndex = screenPoints.count - 1
            for index in 1..<lastIndex {
                let point = screenPoints[index]
                let nextPoint = screenPoints[index + 1]
                let midpoint = CGPoint(
                    x: (point.x + nextPoint.x) * 0.5,
                    y: (point.y + nextPoint.y) * 0.5
                )
                path.curve(
                    to: midpoint,
                    controlPoint1: point,
                    controlPoint2: point
                )
            }
            path.line(to: screenPoints[lastIndex])
        }
        path.stroke()
    }

    private var scrollOrigin: NSPoint {
        scrollView?.contentView.bounds.origin ?? .zero
    }

    private func documentPoint(for screenPoint: CGPoint) -> CGPoint {
        let origin = scrollOrigin
        return CGPoint(x: screenPoint.x + origin.x, y: screenPoint.y + origin.y)
    }

    // MARK: 鼠标事件 - 拦截点击编辑；笔拖拽画线，橡皮按笔画擦除

    override func mouseDown(with event: NSEvent) {
        ensureScrollViewAttached()
        let screenPoint = convert(event.locationInWindow, from: nil)
        switch tool {
        case .pen:
            beginStroke(at: screenPoint)
        case .eraser:
            activeStrokeIndex = nil
            eraseStroke(at: screenPoint)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        ensureScrollViewAttached()
        let screenPoint = convert(event.locationInWindow, from: nil)
        switch tool {
        case .pen:
            guard let activeStrokeIndex, strokes.indices.contains(activeStrokeIndex) else { return }
            strokes[activeStrokeIndex].points.append(documentPoint(for: screenPoint))
            setNeedsDisplay(bounds)
        case .eraser:
            eraseStroke(at: screenPoint)
        }
    }

    override func mouseUp(with event: NSEvent) {
        ensureScrollViewAttached()
        if activeStrokeIndex != nil {
            activeStrokeIndex = nil
            controller?.handleStrokesDidChange(strokes.count)
        }
    }

    private func beginStroke(at screenPoint: CGPoint) {
        let stroke = TeachingAnnotationStroke(
            points: [documentPoint(for: screenPoint)],
            color: Self.strokeColor,
            lineWidth: Self.strokeLineWidth
        )
        strokes.append(stroke)
        activeStrokeIndex = strokes.count - 1
        setNeedsDisplay(bounds)
        controller?.handleStrokesDidChange(strokes.count)
    }

    private func eraseStroke(at screenPoint: CGPoint) {
        let origin = scrollOrigin
        let hitRadius = Self.eraserHitRadius
        let hitIndex = strokes.firstIndex { stroke in
            stroke.points.contains { point in
                let screen = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
                return hypot(screen.x - screenPoint.x, screen.y - screenPoint.y) <= hitRadius
            }
        }
        guard let hitIndex else { return }
        strokes.remove(at: hitIndex)
        setNeedsDisplay(bounds)
        controller?.handleStrokesDidChange(strokes.count)
    }

    func removeAllStrokes() {
        guard !strokes.isEmpty else { return }
        strokes.removeAll()
        activeStrokeIndex = nil
        setNeedsDisplay(bounds)
        controller?.handleStrokesDidChange(0)
    }
}

#endif
