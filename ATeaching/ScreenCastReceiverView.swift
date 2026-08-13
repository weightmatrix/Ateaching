import SwiftUI
import WebKit

struct ScreenCastReceiverView: View {
    @ObservedObject var service: ScreenCastService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var annotationTool: TeachingAnnotationTool?

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            receiverToolbar
            Divider()
            #endif
            ZStack {
                let viewport = activeViewport
                if let document = service.receivedDocument {
                    ScreenCastDocumentView(snapshot: document, viewport: viewport)
                } else {
                    ContentUnavailableView(
                        "等待投屏内容",
                        systemImage: "rectangle.connected.to.line.below",
                        description: Text("主控尚未开启当前频道")
                    )
                }

                ScreenCastAnnotationCanvas(
                    strokes: service.strokes,
                    tool: annotationTool,
                    color: localColor,
                    onStroke: { service.addLocalStroke(points: $0) },
                    onErase: eraseStroke(at:)
                )
                .allowsHitTesting(annotationTool != nil)

                if let pointerX = viewport?.pointerX,
                   let pointerY = viewport?.pointerY {
                    GeometryReader { proxy in
                        Image(systemName: "cursorarrow")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.red)
                            .shadow(color: .white, radius: 1)
                            .position(
                                x: proxy.size.width * pointerX,
                                y: proxy.size.height * pointerY
                            )
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .background(Color.screenCastReceiverBackground)
        .navigationTitle(service.receivedDocument?.title ?? "等待内容")
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                channelPicker
                toolButton(.pen, icon: "pencil.tip", help: "批注")
                toolButton(.eraser, icon: "eraser", help: "橡皮")
                clearButton
                exitButton
            }
        }
        #endif
    }

    private var activeViewport: ScreenCastViewport? {
        guard let viewport = service.receivedViewport,
              viewport.kind == service.selectedReceivedKind else { return nil }
        return viewport
    }

    private var receiverToolbar: some View {
        Group {
            if horizontalSizeClass == .compact {
                VStack(spacing: 6) {
                    HStack {
                        receiverIdentity
                        Spacer()
                        exitButton
                    }
                    HStack(spacing: 8) {
                        channelPicker
                        Spacer(minLength: 0)
                        toolButton(.pen, icon: "pencil.tip", help: "批注")
                        toolButton(.eraser, icon: "eraser", help: "橡皮")
                        clearButton
                    }
                }
            } else {
                HStack(spacing: 10) {
                    receiverIdentity
                    Spacer()
                    channelPicker
                    toolButton(.pen, icon: "pencil.tip", help: "批注")
                    toolButton(.eraser, icon: "eraser", help: "橡皮")
                    clearButton
                    exitButton
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 50)
    }

    private var receiverIdentity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(service.receivedDocument?.title ?? "等待内容")
                .font(.headline)
                .lineLimit(1)
            Text("接收自 \(service.hostName) · \(service.pin)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var availableKinds: [ScreenCastContentKind] {
        ScreenCastContentKind.allCases.filter { service.receivedDocuments[$0] != nil }
    }

    @ViewBuilder
    private var channelPicker: some View {
        if availableKinds.count > 1 {
            Picker("频道", selection: $service.selectedReceivedKind) {
                ForEach(availableKinds) { kind in
                    Label(kind.title, systemImage: kind.systemImage).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
        }
    }

    private var clearButton: some View {
        Button {
            service.clearLocalStrokes()
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.bordered)
        .help("清除自己的批注")
    }

    private var exitButton: some View {
        Button(role: .destructive) {
            service.stopAll(reason: "接收窗口用户点击退出")
        } label: {
            Label("退出", systemImage: "xmark.circle.fill")
        }
        .buttonStyle(.bordered)
    }

    private var localColor: Color {
        Color.screenCast(hex: service.localAnnotationColorHex)
    }

    private func toolButton(_ tool: TeachingAnnotationTool, icon: String, help: String) -> some View {
        Button {
            annotationTool = annotationTool == tool ? nil : tool
        } label: {
            Image(systemName: icon)
        }
        .buttonStyle(.bordered)
        .tint(annotationTool == tool ? localColor : .secondary)
        .help(help)
    }

    private func eraseStroke(at point: ScreenCastPoint) {
        let threshold = 0.025
        let nearest = service.strokes
            .filter { stroke in
                stroke.points.contains { hypot($0.x - point.x, $0.y - point.y) <= threshold }
            }
            .last
        if let nearest { service.removeLocalStroke(nearest.id) }
    }
}

struct ScreenCastAnnotationCanvas: View {
    let strokes: [ScreenCastStroke]
    let tool: TeachingAnnotationTool?
    let color: Color
    let onStroke: ([ScreenCastPoint]) -> Void
    let onErase: (ScreenCastPoint) -> Void

    @State private var activePoints: [ScreenCastPoint] = []

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                for stroke in strokes {
                    draw(stroke.points, color: Color.screenCast(hex: stroke.colorHex), width: stroke.lineWidth, in: &context, size: size)
                }
                draw(activePoints, color: color, width: 3, in: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = normalized(value.location, size: proxy.size)
                        if tool == .pen {
                            activePoints.append(point)
                        } else if tool == .eraser {
                            onErase(point)
                        }
                    }
                    .onEnded { _ in
                        if tool == .pen, activePoints.isEmpty == false {
                            onStroke(activePoints)
                        }
                        activePoints = []
                    }
            )
        }
    }

    private func normalized(_ point: CGPoint, size: CGSize) -> ScreenCastPoint {
        ScreenCastPoint(
            x: max(0, min(1, point.x / max(1, size.width))),
            y: max(0, min(1, point.y / max(1, size.height)))
        )
    }

    private func draw(
        _ points: [ScreenCastPoint],
        color: Color,
        width: Double,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}

struct ScreenCastStrokeOverlay: View {
    let strokes: [ScreenCastStroke]

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                for stroke in strokes {
                    guard let first = stroke.points.first else { continue }
                    var path = Path()
                    path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                    for point in stroke.points.dropFirst() {
                        path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                    }
                    context.stroke(
                        path,
                        with: .color(Color.screenCast(hex: stroke.colorHex)),
                        style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }
}

#if os(macOS)
private extension Color {
    static var screenCastReceiverBackground: Color { Color(nsColor: .textBackgroundColor) }
}

private struct ScreenCastDocumentView: NSViewRepresentable {
    let snapshot: ScreenCastDocumentSnapshot
    let viewport: ScreenCastViewport?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.load(snapshot, into: view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.update(snapshot: snapshot, viewport: viewport, webView: view)
    }

    final class Coordinator {
        private var revision: UInt64?
        private var pendingViewport: ScreenCastViewport?

        func load(_ snapshot: ScreenCastDocumentSnapshot, into webView: WKWebView) {
            revision = snapshot.revision
            webView.loadHTMLString(snapshot.html, baseURL: Bundle.main.resourceURL)
        }

        func update(snapshot: ScreenCastDocumentSnapshot, viewport: ScreenCastViewport?, webView: WKWebView) {
            if revision != snapshot.revision {
                pendingViewport = viewport
                load(snapshot, into: webView)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak webView] in
                    guard let webView else { return }
                    self.apply(self.pendingViewport, to: webView)
                    self.pendingViewport = nil
                }
            } else {
                apply(viewport, to: webView)
            }
        }

        private func apply(_ viewport: ScreenCastViewport?, to webView: WKWebView) {
            guard let viewport else { return }
            if abs(webView.pageZoom - 1) > 0.001 {
                webView.pageZoom = 1
            }
            let script = "window.scrollTo((document.documentElement.scrollWidth-innerWidth)*\(viewport.horizontalFraction),(document.documentElement.scrollHeight-innerHeight)*\(viewport.verticalFraction));"
            webView.evaluateJavaScript(script)
        }
    }
}
#else
private extension Color {
    static var screenCastReceiverBackground: Color { Color(uiColor: .systemBackground) }
}

private struct ScreenCastDocumentView: UIViewRepresentable {
    let snapshot: ScreenCastDocumentSnapshot
    let viewport: ScreenCastViewport?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isOpaque = false
        context.coordinator.load(snapshot, into: view)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.update(snapshot: snapshot, viewport: viewport, webView: view)
    }

    final class Coordinator {
        private var revision: UInt64?

        func load(_ snapshot: ScreenCastDocumentSnapshot, into webView: WKWebView) {
            revision = snapshot.revision
            webView.loadHTMLString(snapshot.html, baseURL: Bundle.main.resourceURL)
        }

        func update(snapshot: ScreenCastDocumentSnapshot, viewport: ScreenCastViewport?, webView: WKWebView) {
            if revision != snapshot.revision { load(snapshot, into: webView) }
            guard let viewport else { return }
            if abs(webView.pageZoom - 1) > 0.001 {
                webView.pageZoom = 1
            }
            let script = "window.scrollTo((document.documentElement.scrollWidth-innerWidth)*\(viewport.horizontalFraction),(document.documentElement.scrollHeight-innerHeight)*\(viewport.verticalFraction));"
            webView.evaluateJavaScript(script)
        }
    }
}
#endif
