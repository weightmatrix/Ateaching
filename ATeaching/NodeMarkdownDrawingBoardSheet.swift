import SwiftUI

#if os(macOS)
import AppKit
import WebKit

struct NodeMarkdownDrawingBoardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedTextID: UUID?

    @State private var freehandStrokes: [FreehandStroke] = []
    @State private var eraserStrokes: [EraserStroke] = []
    @State private var shapeElements: [ShapeElement] = []
    @State private var textElements: [TextElement] = []
    @State private var activeDraft: DraftElement?
    @State private var undoStack: [DrawingBoardSnapshot] = []
    @State private var redoStack: [DrawingBoardSnapshot] = []
    @State private var copiedShape: ShapeElement?

    @State private var selectedShapeID: UUID?
    @State private var selectedTextID: UUID?

    @State private var activeTool: DrawingTool = .selection
    @State private var activeShapeTool: ShapeTool = .line
    @State private var standardizesFreehand = false
    @State private var eraserMode: EraserMode = .stroke
    @State private var eraserSize: CGFloat = 24
    @State private var strokeColor: Color = .black
    @State private var lineWidth: CGFloat = 3
    @State private var dashedShapeMode = false
    @State private var canvasSize: CGSize = CGSize(width: 900, height: 520)
    @State private var activeHandleDrag: ShapeHandleDrag?
    @State private var canvasResizeStart: CGSize?
    @State private var eraserDragHasSnapshot = false
    @State private var showsEraserSettings = false
    @State private var showsTextSettings = false
    @State private var showsLineWidthSettings = false
    @State private var showsColorSettings = false
    @State private var isSnapEnabled = true

    @State private var textInput = "文本"
    @State private var textFontSize: CGFloat = 18
    @State private var textFontName = "Helvetica Neue"
    @State private var quickInputSettings = NodeMarkdownSettingsStore.loadSharedQuickInputSettings()

    let onComplete: (URL?) -> Void

    private let fontNames = ["Helvetica Neue", "PingFang SC", "Times New Roman", "Menlo"]

    var body: some View {
        VStack(spacing: 10) {
            topBar
            shapeToolBar
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .bottomTrailing) {
                        canvasContent
                            .frame(width: canvasSize.width, height: canvasSize.height)
                        canvasResizeHandle
                    }
                    .padding(12)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .background(Color.clear)
        }
        .frame(minWidth: 980, minHeight: 620)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(
            DrawingKeyboardShortcutView(
                enabled: focusedTextID == nil,
                onDelete: {
                    deleteSelectedDrawingElement()
                },
                onCopy: {
                    copySelectedShape()
                },
                onPaste: {
                    pasteCopiedShape()
                },
                onUndo: {
                    undoDrawing()
                },
                onRedo: {
                    redoDrawing()
                }
            )
        )
        .onAppear {
            standardizesFreehand = false
            loadDrawingSettings()
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            selectionToolButton
            penToolButton
            eraserCombinedButton
            textCombinedButton

            Button {
                showsColorSettings.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(strokeColor)
                    Circle()
                        .stroke(.primary.opacity(0.28), lineWidth: 1)
                }
                .frame(width: 18, height: 18)
            }
            .appGlassButtonStyle()
            .help("颜色")
            .popover(isPresented: $showsColorSettings) {
                drawingColorPopover
            }

            Button {
                showsLineWidthSettings.toggle()
            } label: {
                Label("粗细", systemImage: "lineweight")
                    .labelStyle(.iconOnly)
            }
            .appGlassButtonStyle()
            .help("粗细")
            .popover(isPresented: $showsLineWidthSettings) {
                sliderPopover(title: "粗细", valueText: "\(Int(lineWidth))", value: $lineWidth, range: 1...16)
            }

            Toggle("吸附", isOn: $isSnapEnabled)
                .toggleStyle(.switch)
                .help("吸附")

            Button {
                undoDrawing()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
                    .labelStyle(.iconOnly)
            }
            .disabled(undoStack.isEmpty)
            .appGlassButtonStyle()
            .help("撤销")

            Button {
                redoDrawing()
            } label: {
                Label("恢复", systemImage: "arrow.uturn.forward")
                    .labelStyle(.iconOnly)
            }
            .disabled(redoStack.isEmpty)
            .appGlassButtonStyle()
            .help("恢复")

            Button("清空") {
                recordUndoSnapshotIfNeeded()
                freehandStrokes.removeAll()
                eraserStrokes.removeAll()
                shapeElements.removeAll()
                textElements.removeAll()
                activeDraft = nil
                selectedShapeID = nil
                selectedTextID = nil
            }
            .appGlassButtonStyle()
            Spacer()
            Button("完成") {
                onComplete(exportDrawingToTemporaryPNG())
                dismiss()
            }
            .appGlassButtonStyle(.prominent)
        }
        .padding(.horizontal, 12)
        .onChange(of: textFontSize) { _, newValue in
            if let selectedTextID, let idx = textElements.firstIndex(where: { $0.id == selectedTextID }) {
                recordUndoSnapshot()
                textElements[idx].fontSize = newValue
            }
            saveDrawingSettings()
        }
        .onChange(of: textFontName) { _, newValue in
            if let selectedTextID, let idx = textElements.firstIndex(where: { $0.id == selectedTextID }) {
                recordUndoSnapshot()
                textElements[idx].fontName = newValue
            }
            saveDrawingSettings()
        }
        .onChange(of: strokeColor) { _, newValue in
            if let selectedTextID, let idx = textElements.firstIndex(where: { $0.id == selectedTextID }) {
                recordUndoSnapshot()
                textElements[idx].color = newValue
            }
            saveDrawingSettings()
        }
        .onChange(of: lineWidth) { _, _ in
            saveDrawingSettings()
        }
        .onChange(of: eraserMode) { _, _ in
            saveDrawingSettings()
        }
        .onChange(of: eraserSize) { _, _ in
            saveDrawingSettings()
        }
        .onChange(of: dashedShapeMode) { _, _ in
            saveDrawingSettings()
        }
        .onChange(of: isSnapEnabled) { _, _ in
            saveDrawingSettings()
        }
    }

    private var drawingColorPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷颜色")
                .font(.headline)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 6),
                spacing: 8
            ) {
                ForEach(Array(Self.shortcutColors.enumerated()), id: \.offset) { _, color in
                    Button {
                        strokeColor = color
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color)
                            Circle()
                                .stroke(.primary.opacity(0.32), lineWidth: 1)
                            if DrawingBoardColorRecord(color: color) == DrawingBoardColorRecord(color: strokeColor) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(shortcutColorCheckmark(for: color))
                            }
                        }
                        .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("选择颜色")
                }
            }

            Divider()

            ColorPicker("自定义", selection: $strokeColor, supportsOpacity: true)
        }
        .padding(14)
        .frame(width: 238)
    }

    private static let shortcutColors: [Color] = [
        .black,
        .white,
        Color(red: 0.45, green: 0.47, blue: 0.50),
        Color(red: 0.86, green: 0.14, blue: 0.18),
        Color(red: 0.96, green: 0.42, blue: 0.08),
        Color(red: 0.96, green: 0.78, blue: 0.10),
        Color(red: 0.12, green: 0.66, blue: 0.32),
        Color(red: 0.12, green: 0.70, blue: 0.58),
        Color(red: 0.08, green: 0.66, blue: 0.82),
        Color(red: 0.10, green: 0.38, blue: 0.88),
        Color(red: 0.48, green: 0.22, blue: 0.82),
        Color(red: 0.92, green: 0.24, blue: 0.52)
    ]

    private func shortcutColorCheckmark(for color: Color) -> Color {
        let record = DrawingBoardColorRecord(color: color)
        let luminance = 0.2126 * record.red + 0.7152 * record.green + 0.0722 * record.blue
        return luminance > 0.62 ? .black : .white
    }

    private var selectionToolButton: some View {
        Button {
            activeTool = .selection
        } label: {
            Label("选择", systemImage: "arrow.up.left")
                .labelStyle(.iconOnly)
        }
        .appGlassButtonStyle(activeTool == .selection ? .prominent : .regular)
        .help("选择")
    }

    private var shapeToolBar: some View {
        HStack(spacing: 8) {
            ForEach(ShapeTool.allCases, id: \.self) { tool in
                Button {
                    selectShapeTool(tool)
                } label: {
                    Label(tool.title, systemImage: tool.systemImage)
                        .labelStyle(.iconOnly)
                        .frame(width: 28)
                }
                .appGlassButtonStyle(activeTool == .shape && activeShapeTool == tool ? .prominent : .regular)
                .help(tool.title)
            }

            Divider().frame(height: 22)

            Toggle("虚线", isOn: $dashedShapeMode)
                .toggleStyle(.switch)
                .help("虚线")

            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private var penToolButton: some View {
        Button {
            activeTool = .pen
        } label: {
            Label("画笔", systemImage: "pencil.tip")
                .labelStyle(.iconOnly)
        }
        .appGlassButtonStyle(activeTool == .pen ? .prominent : .regular)
        .help("画笔")
    }

    private func toolButton(_ tool: DrawingTool, title: String, systemImage: String) -> some View {
        Button {
            activeTool = tool
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .appGlassButtonStyle(activeTool == tool ? .prominent : .regular)
        .help(title)
    }

    private var eraserCombinedButton: some View {
        HStack(spacing: 1) {
            Button {
                activeTool = .eraser
            } label: {
                Label("橡皮", systemImage: "eraser")
                    .labelStyle(.iconOnly)
                    .frame(width: 28)
            }
            Divider().frame(height: 20)
            Button {
                showsEraserSettings.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 24)
            }
            .buttonStyle(.plain)
        }
        .appGlassButtonStyle(activeTool == .eraser ? .prominent : .regular)
        .help("橡皮")
        .popover(isPresented: $showsEraserSettings) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("模式", selection: $eraserMode) {
                    ForEach(EraserMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                sliderPopoverContent(title: "大小", valueText: "\(Int(eraserSize))", value: $eraserSize, range: 4...80)
            }
            .padding(14)
            .frame(width: 240)
        }
    }

    private var textCombinedButton: some View {
        HStack(spacing: 1) {
            Button {
                activeTool = .text
            } label: {
                Label("文本框", systemImage: "textformat")
                    .labelStyle(.iconOnly)
                    .frame(width: 28)
            }
            Divider().frame(height: 20)
            Button {
                showsTextSettings.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 24)
            }
            .buttonStyle(.plain)
        }
        .appGlassButtonStyle(activeTool == .text ? .prominent : .regular)
        .help("文本框")
        .popover(isPresented: $showsTextSettings) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("字体", selection: $textFontName) {
                    ForEach(fontNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                sliderPopoverContent(title: "字号", valueText: "\(Int(textFontSize))", value: $textFontSize, range: 12...52)
            }
            .padding(14)
            .frame(width: 260)
        }
    }

    private func sliderPopover(
        title: String,
        valueText: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>
    ) -> some View {
        sliderPopoverContent(title: title, valueText: valueText, value: value, range: range)
            .padding(14)
            .frame(width: 220)
    }

    private func sliderPopoverContent(
        title: String,
        valueText: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 1)
        }
    }

    private var canvasContent: some View {
        ZStack {
            drawingCanvas
            textLayer
            selectionLayer
        }
        .background(Color.clear)
        .overlay(
            Rectangle()
                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .gesture(activeGesture)
        .onTapGesture { point in
            handleTap(point)
        }
        .contextMenu {
            if selectedShape != nil {
                Button("复制") {
                    copySelectedShape()
                }
            }
        }
    }

    private var canvasResizeHandle: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
            )
            .offset(x: -2, y: -2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if canvasResizeStart == nil {
                            canvasResizeStart = canvasSize
                        }
                        let start = canvasResizeStart ?? canvasSize
                        canvasSize = CGSize(
                            width: max(320, start.width + value.translation.width),
                            height: max(220, start.height + value.translation.height)
                        )
                    }
                    .onEnded { _ in
                        canvasResizeStart = nil
                    }
            )
    }

    private var drawingCanvas: some View {
        Canvas { context, _ in
            for stroke in freehandStrokes {
                stroke.render(in: &context)
            }
            for element in shapeElements {
                element.render(in: &context)
            }
            if let activeDraft {
                activeDraft.render(in: &context)
            }
            for eraserStroke in eraserStrokes {
                eraserStroke.render(in: &context)
            }
            if case let .eraser(eraserStroke) = activeDraft {
                eraserStroke.render(in: &context)
            }
        }
    }

    private var textLayer: some View {
        ZStack {
            ForEach(textElements) { text in
                if selectedTextID == text.id, text.formulaSource == nil {
                    TextField("文本", text: textBinding(for: text.id))
                        .textFieldStyle(.plain)
                        .font(.custom(text.fontName, size: text.fontSize))
                        .foregroundStyle(text.color)
                        .padding(3)
                        .frame(width: max(60, text.rect.width), height: max(28, text.rect.height), alignment: .topLeading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .position(x: text.rect.midX, y: text.rect.midY)
                        .focused($focusedTextID, equals: text.id)
                } else if let formula = text.formulaSource {
                    DrawingFormulaPreview(source: formula)
                        .frame(width: max(30, text.rect.width), height: max(22, text.rect.height))
                        .position(x: text.rect.midX, y: text.rect.midY)
                        .allowsHitTesting(false)
                } else {
                    Text(text.text)
                        .font(.custom(text.fontName, size: text.fontSize))
                        .foregroundStyle(text.color)
                        .frame(width: max(30, text.rect.width), height: max(22, text.rect.height), alignment: .topLeading)
                        .position(x: text.rect.midX, y: text.rect.midY)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var selectionLayer: some View {
        ZStack {
            if let shape = selectedShape {
                let rect = shape.boundingRect.insetBy(dx: -8, dy: -8)
                Path { $0.addRect(rect) }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(.blue.opacity(0.8))
                ForEach(shape.handlePoints, id: \.key) { item in
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Color.blue, lineWidth: 1.5))
                        .frame(width: 10, height: 10)
                        .position(item.value)
                }
            }
            if let text = selectedText {
                Path { $0.addRect(text.rect.insetBy(dx: -4, dy: -4)) }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.orange.opacity(0.9))
            }
        }
        .allowsHitTesting(false)
    }

    private var activeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in handleDragChanged(value) }
            .onEnded { value in handleDragEnded(value) }
    }

    private var selectedShape: ShapeElement? {
        guard let selectedShapeID else { return nil }
        return shapeElements.first(where: { $0.id == selectedShapeID })
    }

    private var selectedText: TextElement? {
        guard let selectedTextID else { return nil }
        return textElements.first(where: { $0.id == selectedTextID })
    }

    private var activeToolLabel: String {
        switch activeTool {
        case .selection: return "选择"
        case .pen: return "画笔"
        case .eraser: return "橡皮"
        case .shape: return "几何-\(activeShapeTool.title)"
        case .text: return "文本框"
        }
    }

    private func selectShapeTool(_ shapeTool: ShapeTool) {
        activeShapeTool = shapeTool
        activeTool = .shape
    }

    private func textBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                textElements.first(where: { $0.id == id })?.text ?? ""
            },
            set: { newValue in
                guard let index = textElements.firstIndex(where: { $0.id == id }) else { return }
                recordUndoSnapshot()
                let nextText = applyQuickInput(text: newValue)
                textElements[index].text = nextText
                textInput = nextText
            }
        )
    }

    private func createTextElement(at point: CGPoint) {
        recordUndoSnapshot()
        let id = UUID()
        let text = TextElement(
            id: id,
            rect: CGRect(x: point.x, y: point.y, width: 180, height: max(30, textFontSize + 12)),
            text: "",
            color: strokeColor,
            fontSize: textFontSize,
            fontName: textFontName
        )
        textElements.append(text)
        selectedTextID = id
        selectedShapeID = nil
        textInput = ""
        focusedTextID = id
    }

    private func handleTap(_ point: CGPoint) {
        if let text = textElements.last(where: { $0.rect.insetBy(dx: -8, dy: -8).contains(point) }) {
            selectedTextID = text.id
            selectedShapeID = nil
            textInput = text.text
            textFontSize = text.fontSize
            textFontName = text.fontName
            strokeColor = text.color
            focusedTextID = text.id
            return
        }
        if let shape = shapeElements.last(where: { $0.boundingRect.insetBy(dx: -8, dy: -8).contains(point) }) {
            selectedShapeID = shape.id
            selectedTextID = nil
            focusedTextID = nil
            return
        }
        if activeTool == .text {
            createTextElement(at: point)
            return
        }
        selectedShapeID = nil
        selectedTextID = nil
        focusedTextID = nil
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        let point = value.location
        switch activeTool {
        case .selection:
            updateSelectionDrag(point: point, startPoint: value.startLocation)
        case .pen:
            updatePenDrag(point: point, startPoint: value.startLocation)
        case .eraser:
            updateEraserDrag(point: point, startPoint: value.startLocation)
        case .shape:
            updateShapeDrag(point: point, startPoint: value.startLocation)
        case .text:
            updateTextDrag(point: point, startPoint: value.startLocation)
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        switch activeTool {
        case .selection:
            break
        case .pen:
            commitPenDraft()
        case .eraser:
            commitEraserDraft()
        case .shape:
            commitShapeDraft()
        case .text:
            if value.startLocation.distance(to: value.location) < 3 {
                activeDraft = nil
                return
            }
            commitTextDraft()
        }
        activeHandleDrag = nil
    }

    private func updateSelectionDrag(point: CGPoint, startPoint: CGPoint) {
        if activeHandleDrag == nil, let interaction = resolveShapeInteraction(at: startPoint) {
            recordUndoSnapshot()
            activeHandleDrag = interaction
            selectedShapeID = interaction.shapeID
            selectedTextID = nil
            focusedTextID = nil
        }
        if let activeHandleDrag {
            applyShapeInteraction(activeHandleDrag, currentPoint: point)
        }
    }

    private func updatePenDrag(point: CGPoint, startPoint: CGPoint) {
        selectedShapeID = nil
        selectedTextID = nil
        if case var .freehand(stroke) = activeDraft {
            stroke.points.append(point)
            activeDraft = .freehand(stroke)
            return
        }
        activeDraft = .freehand(FreehandStroke(points: [startPoint, point], color: strokeColor, width: lineWidth))
    }

    private func commitPenDraft() {
        if case let .freehand(stroke) = activeDraft, stroke.points.count > 1 {
            recordUndoSnapshot()
            if standardizesFreehand, let shape = standardShape(from: stroke) {
                shapeElements.append(shape)
                selectedShapeID = shape.id
                selectedTextID = nil
            } else {
                freehandStrokes.append(stroke)
            }
        }
        activeDraft = nil
    }

    private func updateShapeDrag(point: CGPoint, startPoint: CGPoint) {
        if activeHandleDrag == nil, let interaction = resolveShapeInteraction(at: startPoint) {
            recordUndoSnapshot()
            activeHandleDrag = interaction
            selectedShapeID = interaction.shapeID
            selectedTextID = nil
        }
        if let activeHandleDrag {
            applyShapeInteraction(activeHandleDrag, currentPoint: point)
            return
        }
        selectedShapeID = nil
        selectedTextID = nil
        var shape = ShapeElement(
            id: UUID(),
            tool: activeShapeTool,
            start: startPoint,
            end: point,
            third: defaultThirdPoint(for: activeShapeTool, start: startPoint, end: point),
            color: strokeColor,
            width: lineWidth,
            dashed: dashedShapeMode
        )
        if isSnapEnabled {
            shape = DrawingSnapEngine.snap(shape: shape, to: shapeElements, excluding: nil, movingHandle: .end)
        }
        activeDraft = .shape(shape)
    }

    private func commitShapeDraft() {
        if case let .shape(shape) = activeDraft, shape.isValid {
            recordUndoSnapshot()
            shapeElements.append(shape)
            selectedShapeID = shape.id
            selectedTextID = nil
        }
        activeDraft = nil
    }

    private func updateTextDrag(point: CGPoint, startPoint: CGPoint) {
        selectedShapeID = nil
        selectedTextID = nil
        let rect = CGRect(
            x: min(startPoint.x, point.x),
            y: min(startPoint.y, point.y),
            width: max(40, abs(point.x - startPoint.x)),
            height: max(24, abs(point.y - startPoint.y))
        )
        activeDraft = .text(
            TextElement(
                id: UUID(),
                rect: rect,
                text: textInput,
                color: strokeColor,
                fontSize: textFontSize,
                fontName: textFontName
            )
        )
    }

    private func commitTextDraft() {
        if case let .text(text) = activeDraft {
            recordUndoSnapshot()
            textElements.append(text)
            selectedTextID = text.id
            selectedShapeID = nil
            focusedTextID = text.id
        }
        activeDraft = nil
    }

    private func updateEraserDrag(point: CGPoint, startPoint: CGPoint) {
        switch eraserMode {
        case .stroke:
            eraseWholeElements(at: point)
        case .pixel:
            if case var .eraser(stroke) = activeDraft {
                stroke.points.append(point)
                activeDraft = .eraser(stroke)
                return
            }
            activeDraft = .eraser(EraserStroke(points: [startPoint, point], width: eraserSize))
        }
    }

    private func commitEraserDraft() {
        if case let .eraser(stroke) = activeDraft, stroke.points.count > 1 {
            recordUndoSnapshot()
            eraserStrokes.append(stroke)
        }
        eraserDragHasSnapshot = false
        activeDraft = nil
    }

    private func eraseWholeElements(at point: CGPoint) {
        let radius = max(4, eraserSize * 0.5)
        let shouldEraseFreehand = freehandStrokes.contains { $0.points.contains(where: { $0.distance(to: point) <= radius }) }
        let shouldEraseShape = shapeElements.contains { $0.boundingRect.insetBy(dx: -radius, dy: -radius).contains(point) }
        let shouldEraseText = textElements.contains { $0.rect.insetBy(dx: -radius, dy: -radius).contains(point) }
        guard shouldEraseFreehand || shouldEraseShape || shouldEraseText else { return }
        if !eraserDragHasSnapshot {
            recordUndoSnapshot()
            eraserDragHasSnapshot = true
        }
        freehandStrokes.removeAll { $0.points.contains(where: { $0.distance(to: point) <= radius }) }
        shapeElements.removeAll { $0.boundingRect.insetBy(dx: -radius, dy: -radius).contains(point) }
        textElements.removeAll { $0.rect.insetBy(dx: -radius, dy: -radius).contains(point) }
        if let selectedShapeID, !shapeElements.contains(where: { $0.id == selectedShapeID }) {
            self.selectedShapeID = nil
        }
        if let selectedTextID, !textElements.contains(where: { $0.id == selectedTextID }) {
            self.selectedTextID = nil
        }
    }

    private func resolveShapeInteraction(at point: CGPoint) -> ShapeHandleDrag? {
        guard let selectedShape else {
            if let hitShape = shapeElements.last(where: { $0.boundingRect.insetBy(dx: -12, dy: -12).contains(point) }) {
                return .move(shapeID: hitShape.id, startPoint: point, originStart: hitShape.start, originEnd: hitShape.end, originThird: hitShape.third)
            }
            return nil
        }
        for handle in selectedShape.handlePoints where handle.value.distance(to: point) < 12 {
            return .resize(shapeID: selectedShape.id, handle: handle.key, originStart: selectedShape.start, originEnd: selectedShape.end)
        }
        if selectedShape.boundingRect.insetBy(dx: -10, dy: -10).contains(point) {
            return .move(shapeID: selectedShape.id, startPoint: point, originStart: selectedShape.start, originEnd: selectedShape.end, originThird: selectedShape.third)
        }
        return nil
    }

    private func applyShapeInteraction(_ interaction: ShapeHandleDrag, currentPoint: CGPoint) {
        guard let index = shapeElements.firstIndex(where: { $0.id == interaction.shapeID }) else { return }
        var shape = shapeElements[index]
        switch interaction {
        case let .move(_, startPoint, originStart, originEnd, originThird):
            let dx = currentPoint.x - startPoint.x
            let dy = currentPoint.y - startPoint.y
            shape.start = CGPoint(x: originStart.x + dx, y: originStart.y + dy)
            shape.end = CGPoint(x: originEnd.x + dx, y: originEnd.y + dy)
            if let originThird {
                shape.third = CGPoint(x: originThird.x + dx, y: originThird.y + dy)
            }
        case let .resize(_, handle, originStart, originEnd):
            if shape.isRotatableBox {
                let originShape = shape
                switch handle {
                case .start:
                    shape.start = originShape.unrotatedPoint(from: currentPoint)
                    shape.end = originEnd
                    shape.third = originShape.preservedRotationHandle(forStart: shape.start, end: shape.end)
                case .end:
                    shape.start = originStart
                    shape.end = originShape.unrotatedPoint(from: currentPoint)
                    shape.third = originShape.preservedRotationHandle(forStart: shape.start, end: shape.end)
                case .third:
                    shape.start = originStart
                    shape.end = originEnd
                    shape.third = currentPoint
                }
            } else {
                switch handle {
                case .start:
                    shape.start = currentPoint
                    shape.end = originEnd
                case .end:
                    shape.start = originStart
                    shape.end = currentPoint
                case .third:
                    shape.start = originStart
                    shape.end = originEnd
                    shape.third = currentPoint
                }
            }
        }
        if isSnapEnabled {
            shape = DrawingSnapEngine.snap(
                shape: shape,
                to: shapeElements,
                excluding: interaction.shapeID,
                movingHandle: interaction.movingHandle
            )
        }
        shapeElements[index] = shape
    }

    private func defaultTriangleThird(start: CGPoint, end: CGPoint) -> CGPoint {
        CGPoint(
            x: (start.x + end.x) * 0.5,
            y: min(start.y, end.y) - max(24, abs(end.x - start.x) * 0.55)
        )
    }

    private func defaultThirdPoint(for tool: ShapeTool, start: CGPoint, end: CGPoint) -> CGPoint? {
        switch tool {
        case .triangle:
            return defaultTriangleThird(start: start, end: end)
        case .axis:
            return ShapeElement.defaultAxisSecondEndpoint(start: start, end: end)
        case .line, .rectangle, .ellipse, .arrow, .wall:
            return nil
        }
    }

    private func deleteSelectedDrawingElement() {
        if let selectedShapeID,
           shapeElements.contains(where: { $0.id == selectedShapeID }) {
            recordUndoSnapshot()
            shapeElements.removeAll { $0.id == selectedShapeID }
            self.selectedShapeID = nil
            activeDraft = nil
            activeHandleDrag = nil
            return
        }
        if let selectedTextID,
           textElements.contains(where: { $0.id == selectedTextID }) {
            recordUndoSnapshot()
            textElements.removeAll { $0.id == selectedTextID }
            self.selectedTextID = nil
            focusedTextID = nil
            activeDraft = nil
        }
    }

    private func copySelectedShape() {
        guard let selectedShape else { return }
        copiedShape = selectedShape
    }

    private func pasteCopiedShape() {
        guard let copiedShape else { return }
        recordUndoSnapshot()
        let pasted = duplicatedShape(from: copiedShape, offset: CGSize(width: 18, height: 18))
        shapeElements.append(pasted)
        selectedShapeID = pasted.id
        selectedTextID = nil
        focusedTextID = nil
    }

    private func duplicatedShape(from shape: ShapeElement, offset: CGSize) -> ShapeElement {
        ShapeElement(
            id: UUID(),
            tool: shape.tool,
            start: CGPoint(x: shape.start.x + offset.width, y: shape.start.y + offset.height),
            end: CGPoint(x: shape.end.x + offset.width, y: shape.end.y + offset.height),
            third: shape.third.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) },
            color: shape.color,
            width: shape.width,
            dashed: shape.dashed
        )
    }

    private func loadDrawingSettings() {
        let settings = DrawingBoardSettingsStore.load()
        strokeColor = settings.strokeColor.color
        lineWidth = CGFloat(settings.lineWidth)
        eraserMode = settings.eraserMode
        eraserSize = CGFloat(settings.eraserSize)
        textFontSize = CGFloat(settings.textFontSize)
        textFontName = settings.textFontName
        isSnapEnabled = settings.isSnapEnabled
        dashedShapeMode = settings.dashedShapeMode
    }

    private func saveDrawingSettings() {
        DrawingBoardSettingsStore.save(
            DrawingBoardSettings(
                strokeColor: DrawingBoardColorRecord(color: strokeColor),
                lineWidth: Double(lineWidth),
                eraserModeRawValue: eraserMode.rawValue,
                eraserSize: Double(eraserSize),
                textFontSize: Double(textFontSize),
                textFontName: textFontName,
                isSnapEnabled: isSnapEnabled,
                dashedShapeMode: dashedShapeMode
            )
        )
    }

    private func recordUndoSnapshotIfNeeded() {
        guard !freehandStrokes.isEmpty || !eraserStrokes.isEmpty || !shapeElements.isEmpty || !textElements.isEmpty else { return }
        recordUndoSnapshot()
    }

    private func recordUndoSnapshot() {
        undoStack.append(currentSnapshot())
        if undoStack.count > 80 {
            undoStack.removeFirst(undoStack.count - 80)
        }
        redoStack.removeAll()
    }

    private func undoDrawing() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        restore(snapshot)
    }

    private func redoDrawing() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        restore(snapshot)
    }

    private func currentSnapshot() -> DrawingBoardSnapshot {
        DrawingBoardSnapshot(
            freehandStrokes: freehandStrokes,
            eraserStrokes: eraserStrokes,
            shapeElements: shapeElements,
            textElements: textElements,
            selectedShapeID: selectedShapeID,
            selectedTextID: selectedTextID
        )
    }

    private func restore(_ snapshot: DrawingBoardSnapshot) {
        freehandStrokes = snapshot.freehandStrokes
        eraserStrokes = snapshot.eraserStrokes
        shapeElements = snapshot.shapeElements
        textElements = snapshot.textElements
        selectedShapeID = snapshot.selectedShapeID
        selectedTextID = snapshot.selectedTextID
        activeDraft = nil
        activeHandleDrag = nil
        eraserDragHasSnapshot = false
    }

    private func standardShape(from stroke: FreehandStroke) -> ShapeElement? {
        guard stroke.points.count >= 2,
              let first = stroke.points.first,
              let last = stroke.points.last,
              let bounds = stroke.boundingRect else { return nil }

        let diagonal = max(1, hypot(bounds.width, bounds.height))
        let endpointDistance = first.distance(to: last)
        let closedThreshold = max(16, diagonal * 0.18)
        let straightTolerance = max(6, min(22, diagonal * 0.08 + stroke.width))

        if endpointDistance > closedThreshold,
           maximumDistanceFromLine(points: stroke.points, start: first, end: last) <= straightTolerance {
            return ShapeElement(
                id: UUID(),
                tool: .line,
                start: first,
                end: last,
                color: stroke.color,
                width: stroke.width,
                dashed: false
            )
        }

        guard endpointDistance <= closedThreshold, bounds.width >= 8, bounds.height >= 8 else {
            return nil
        }

        let tool: ShapeTool = isRectangleLike(points: stroke.points, bounds: bounds, diagonal: diagonal) ? .rectangle : .ellipse
        return ShapeElement(
            id: UUID(),
            tool: tool,
            start: bounds.origin,
            end: CGPoint(x: bounds.maxX, y: bounds.maxY),
            color: stroke.color,
            width: stroke.width,
            dashed: false
        )
    }

    private func maximumDistanceFromLine(points: [CGPoint], start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, hypot(dx, dy))
        return points.reduce(CGFloat.zero) { maximum, point in
            let distance = abs(dy * point.x - dx * point.y + end.x * start.y - end.y * start.x) / length
            return max(maximum, distance)
        }
    }

    private func isRectangleLike(points: [CGPoint], bounds: CGRect, diagonal: CGFloat) -> Bool {
        let tolerance = max(5, diagonal * 0.08)
        let averageDistance = points.reduce(CGFloat.zero) { partial, point in
            partial + distanceToRectPerimeter(point: point, rect: bounds)
        } / CGFloat(max(1, points.count))
        return averageDistance <= tolerance
    }

    private func distanceToRectPerimeter(point: CGPoint, rect: CGRect) -> CGFloat {
        min(
            abs(point.x - rect.minX),
            abs(point.x - rect.maxX),
            abs(point.y - rect.minY),
            abs(point.y - rect.maxY)
        )
    }

    private func exportDrawingToTemporaryPNG() -> URL? {
        let bounds = drawingBounds()
        let outputSize = CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
        guard outputSize.width > 0, outputSize.height > 0 else { return nil }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(outputSize.width),
            pixelsHigh: Int(outputSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = outputSize

        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = graphicsContext
        guard let cgContext = NSGraphicsContext.current?.cgContext else {
            NSGraphicsContext.current = previousContext
            return nil
        }
        cgContext.clear(CGRect(origin: .zero, size: outputSize))
        cgContext.saveGState()
        cgContext.translateBy(x: outputSize.width, y: outputSize.height)
        cgContext.rotate(by: .pi)
        cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
        for stroke in freehandStrokes { stroke.renderExport(in: cgContext) }
        for element in shapeElements { element.renderExport(in: cgContext) }
        for text in textElements { text.renderExport(in: cgContext) }
        for eraserStroke in eraserStrokes { eraserStroke.renderExport(in: cgContext) }
        cgContext.restoreGState()
        NSGraphicsContext.current = previousContext

        let outputBitmap = horizontallyMirroredBitmap(from: bitmap, size: outputSize) ?? bitmap
        guard let pngData = outputBitmap.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-\(UUID().uuidString).png")
        do {
            try pngData.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func horizontallyMirroredBitmap(
        from bitmap: NSBitmapImageRep,
        size: CGSize
    ) -> NSBitmapImageRep? {
        guard let sourceImage = bitmap.cgImage,
              let mirrored = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width),
                pixelsHigh: Int(size.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ),
              let graphicsContext = NSGraphicsContext(bitmapImageRep: mirrored) else {
            return nil
        }
        mirrored.size = size

        let cgContext = graphicsContext.cgContext
        cgContext.clear(CGRect(origin: .zero, size: size))
        cgContext.translateBy(x: size.width, y: 0)
        cgContext.scaleBy(x: -1, y: 1)
        cgContext.draw(sourceImage, in: CGRect(origin: .zero, size: size))
        return mirrored
    }

    private func drawingBounds() -> CGRect {
        var rects: [CGRect] = []
        rects.append(contentsOf: freehandStrokes.compactMap(\.expandedBoundingRect))
        rects.append(contentsOf: shapeElements.map(\.expandedBoundingRect))
        rects.append(contentsOf: textElements.map(\.rect))
        guard let first = rects.first else {
            return CGRect(origin: .zero, size: CGSize(width: 1, height: 1)).insetBy(dx: -10, dy: -10)
        }
        let union = rects.dropFirst().reduce(first) { $0.union($1) }
        return union.insetBy(dx: -10, dy: -10)
    }

    private func applyQuickInput(text: String) -> String {
        for rule in quickInputSettings.singleRules.sorted(by: { $0.trigger.count > $1.trigger.count }) {
            guard !rule.trigger.isEmpty else { continue }
            if text.hasSuffix(rule.trigger) {
                let dropped = text.dropLast(rule.trigger.count)
                return String(dropped) + rule.replacement
            }
        }
        for pairRule in quickInputSettings.pairRules.sorted(by: { $0.openTrigger.count > $1.openTrigger.count }) {
            guard !pairRule.openTrigger.isEmpty else { continue }
            guard text.hasSuffix(pairRule.openTrigger) else { continue }
            let dropped = text.dropLast(pairRule.openTrigger.count)
            return String(dropped) + pairRule.openReplacement + pairRule.closeReplacement
        }
        return text
    }
}

private enum DrawingTool { case selection, pen, eraser, shape, text }

enum EraserMode: String, CaseIterable {
    case stroke
    case pixel

    var title: String {
        switch self {
        case .stroke: return "笔画模式"
        case .pixel: return "像素模式"
        }
    }
}

enum ShapeTool: String, CaseIterable {
    case line, rectangle, triangle, ellipse, arrow, wall, axis
    var title: String {
        switch self {
        case .line: return "直线"
        case .rectangle: return "方形"
        case .triangle: return "三角形"
        case .ellipse: return "圆/椭圆"
        case .arrow: return "箭头"
        case .wall: return "墙壁"
        case .axis: return "坐标系"
        }
    }

    var systemImage: String {
        switch self {
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .triangle: return "triangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .wall: return "line.3.horizontal"
        case .axis: return "arrow.up.and.down.and.arrow.left.and.right"
        }
    }
}

enum ShapeHandleKey: Hashable { case start, end, third }

private enum ShapeHandleDrag {
    case move(shapeID: UUID, startPoint: CGPoint, originStart: CGPoint, originEnd: CGPoint, originThird: CGPoint?)
    case resize(shapeID: UUID, handle: ShapeHandleKey, originStart: CGPoint, originEnd: CGPoint)
    var shapeID: UUID {
        switch self {
        case let .move(shapeID, _, _, _, _): return shapeID
        case let .resize(shapeID, _, _, _): return shapeID
        }
    }
    var originThird: CGPoint? {
        switch self {
        case let .move(_, _, _, _, originThird): return originThird
        case .resize: return nil
        }
    }
    var movingHandle: ShapeHandleKey? {
        switch self {
        case .move:
            return nil
        case let .resize(_, handle, _, _):
            return handle
        }
    }
}

private enum DraftElement {
    case freehand(FreehandStroke)
    case eraser(EraserStroke)
    case shape(ShapeElement)
    case text(TextElement)
    func render(in context: inout GraphicsContext) {
        switch self {
        case let .freehand(stroke): stroke.render(in: &context)
        case let .eraser(stroke): stroke.render(in: &context)
        case let .shape(shape): shape.render(in: &context)
        case let .text(text): text.render(in: &context)
        }
    }
}

private struct DrawingBoardSnapshot {
    var freehandStrokes: [FreehandStroke]
    var eraserStrokes: [EraserStroke]
    var shapeElements: [ShapeElement]
    var textElements: [TextElement]
    var selectedShapeID: UUID?
    var selectedTextID: UUID?
}

private struct DrawingKeyboardShortcutView: NSViewRepresentable {
    var enabled: Bool
    var onDelete: () -> Void
    var onCopy: () -> Void
    var onPaste: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onDelete = onDelete
        view.onCopy = onCopy
        view.onPaste = onPaste
        view.onUndo = onUndo
        view.onRedo = onRedo
        view.enabled = enabled
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.onDelete = onDelete
        nsView.onCopy = onCopy
        nsView.onPaste = onPaste
        nsView.onUndo = onUndo
        nsView.onRedo = onRedo
        nsView.enabled = enabled
        guard enabled else { return }
        DispatchQueue.main.async {
            if nsView.window?.firstResponder !== nsView {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class KeyCatcherView: NSView {
        var enabled = false
        var onDelete: () -> Void = {}
        var onCopy: () -> Void = {}
        var onPaste: () -> Void = {}
        var onUndo: () -> Void = {}
        var onRedo: () -> Void = {}

        override var acceptsFirstResponder: Bool { enabled }

        override func keyDown(with event: NSEvent) {
            guard enabled else {
                super.keyDown(with: event)
                return
            }
            if event.keyCode == 51 || event.keyCode == 117 {
                onDelete()
                return
            }
            if event.modifierFlags.contains(.command) {
                let isShift = event.modifierFlags.contains(.shift)
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "c":
                    onCopy()
                    return
                case "v":
                    onPaste()
                    return
                case "z":
                    if isShift {
                        onRedo()
                    } else {
                        onUndo()
                    }
                    return
                default:
                    break
                }
            }
            super.keyDown(with: event)
        }
    }
}

private struct FreehandStroke {
    var points: [CGPoint]
    var color: Color
    var width: CGFloat
    var boundingRect: CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); minY = min(minY, point.y)
            maxX = max(maxX, point.x); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }
    var expandedBoundingRect: CGRect? {
        boundingRect?.insetBy(dx: -width * 0.5, dy: -width * 0.5)
    }
    func render(in context: inout GraphicsContext) {
        guard points.count > 1 else { return }
        var path = Path(); path.addLines(points)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
    func renderExport(in context: CGContext) {
        guard points.count > 1 else { return }
        context.saveGState()
        context.setStrokeColor(NSColor(color).cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.beginPath()
        context.move(to: points[0])
        for point in points.dropFirst() { context.addLine(to: point) }
        context.strokePath()
        context.restoreGState()
    }
}

private struct EraserStroke {
    var points: [CGPoint]
    var width: CGFloat

    func render(in context: inout GraphicsContext) {
        guard points.count > 1 else { return }
        context.blendMode = .destinationOut
        var path = Path()
        path.addLines(points)
        context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        context.blendMode = .normal
    }

    func renderExport(in context: CGContext) {
        guard points.count > 1 else { return }
        context.saveGState()
        context.setBlendMode(.clear)
        context.setStrokeColor(NSColor.clear.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: points[0])
        for point in points.dropFirst() { context.addLine(to: point) }
        context.strokePath()
        context.restoreGState()
    }
}

struct ShapeElement {
    let id: UUID
    let tool: ShapeTool
    var start: CGPoint
    var end: CGPoint
    var third: CGPoint? = nil
    var color: Color
    var width: CGFloat
    var dashed: Bool

    var isValid: Bool { start.distance(to: end) > 2 }
    var isRotatableBox: Bool {
        tool == .rectangle || tool == .ellipse
    }
    var boundingRect: CGRect {
        let points = boundingPoints
        let minX = points.map(\.x).min() ?? start.x
        let maxX = points.map(\.x).max() ?? end.x
        let minY = points.map(\.y).min() ?? start.y
        let maxY = points.map(\.y).max() ?? end.y
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }
    var expandedBoundingRect: CGRect {
        boundingRect.insetBy(dx: -width * 0.5, dy: -width * 0.5)
    }
    var controlPoints: [CGPoint] {
        switch tool {
        case .triangle:
            return [start, end, third ?? defaultTriangleThird]
        case .rectangle, .ellipse:
            return [rotatedPoint(start, around: center, angle: rotationAngle), rotatedPoint(end, around: center, angle: rotationAngle), rotationHandlePoint]
        case .axis:
            return [start, end, axisSecondEndpoint]
        case .line, .arrow, .wall:
            return [start, end]
        }
    }
    var edgeAngles: [CGFloat] {
        switch tool {
        case .line, .arrow, .wall, .axis:
            return [atan2(end.y - start.y, end.x - start.x)]
        case .rectangle:
            return [rotationAngle, rotationAngle + .pi / 2]
        case .triangle:
            let points = controlPoints
            guard points.count == 3 else { return [] }
            return [
                atan2(points[1].y - points[0].y, points[1].x - points[0].x),
                atan2(points[2].y - points[1].y, points[2].x - points[1].x),
                atan2(points[0].y - points[2].y, points[0].x - points[2].x)
            ]
        case .ellipse:
            return []
        }
    }
    var handlePoints: [(key: ShapeHandleKey, value: CGPoint)] {
        switch tool {
        case .triangle:
            return [(.start, start), (.end, end), (.third, third ?? defaultTriangleThird)]
        case .rectangle, .ellipse:
            return [
                (.start, rotatedPoint(start, around: center, angle: rotationAngle)),
                (.end, rotatedPoint(end, around: center, angle: rotationAngle)),
                (.third, rotationHandlePoint)
            ]
        case .axis:
            return [(.start, start), (.end, end), (.third, axisSecondEndpoint)]
        case .line, .arrow, .wall:
            return [(.start, start), (.end, end)]
        }
    }

    private var rawRect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: max(1, abs(end.x - start.x)),
            height: max(1, abs(end.y - start.y))
        )
    }

    private var center: CGPoint {
        CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
    }

    private var defaultTriangleThird: CGPoint {
        CGPoint(
            x: (start.x + end.x) * 0.5,
            y: min(start.y, end.y) - max(24, abs(end.x - start.x) * 0.55)
        )
    }

    private var defaultRotationHandlePoint: CGPoint {
        let rect = rawRect
        return CGPoint(x: rect.midX, y: rect.minY - 28)
    }

    private var rotationHandlePoint: CGPoint {
        third ?? defaultRotationHandlePoint
    }

    private var rotationAngle: CGFloat {
        guard third != nil else { return 0 }
        let handle = rotationHandlePoint
        return atan2(handle.y - center.y, handle.x - center.x) + .pi / 2
    }

    private var axisSecondEndpoint: CGPoint {
        third ?? Self.defaultAxisSecondEndpoint(start: start, end: end)
    }

    private var boundingPoints: [CGPoint] {
        switch tool {
        case .rectangle, .ellipse:
            return rotatedRectCorners + [rotationHandlePoint]
        default:
            return controlPoints
        }
    }

    private var rotatedRectCorners: [CGPoint] {
        let rect = rawRect
        return [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ].map { rotatedPoint($0, around: center, angle: rotationAngle) }
    }

    private var rotationTransform: CGAffineTransform {
        CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: rotationAngle)
            .translatedBy(x: -center.x, y: -center.y)
    }

    func unrotatedPoint(from point: CGPoint) -> CGPoint {
        rotatedPoint(point, around: center, angle: -rotationAngle)
    }

    func preservedRotationHandle(forStart newStart: CGPoint, end newEnd: CGPoint) -> CGPoint? {
        guard third != nil else { return nil }
        let newCenter = CGPoint(x: (newStart.x + newEnd.x) * 0.5, y: (newStart.y + newEnd.y) * 0.5)
        let newRect = CGRect(
            x: min(newStart.x, newEnd.x),
            y: min(newStart.y, newEnd.y),
            width: max(1, abs(newEnd.x - newStart.x)),
            height: max(1, abs(newEnd.y - newStart.y))
        )
        let unrotatedHandle = CGPoint(x: newRect.midX, y: newRect.minY - 28)
        return rotatedPoint(unrotatedHandle, around: newCenter, angle: rotationAngle)
    }

    static func defaultAxisSecondEndpoint(start: CGPoint, end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return CGPoint(x: start.x - dy * 0.7, y: start.y + dx * 0.7)
    }

    func render(in context: inout GraphicsContext) {
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dashed ? [8, 6] : [])
        context.stroke(path, with: .color(color), style: style)
    }

    func renderExport(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor(color).cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineDash(phase: 0, lengths: dashed ? [8, 6] : [])
        context.addPath(path.cgPath)
        context.strokePath()
        context.restoreGState()
    }

    private var path: Path {
        var path = Path()
        switch tool {
        case .line:
            path.move(to: start); path.addLine(to: end)
        case .rectangle:
            path.addRect(rawRect)
            path = path.applying(rotationTransform)
        case .triangle:
            path.move(to: start)
            path.addLine(to: end)
            path.addLine(to: third ?? defaultTriangleThird)
            path.closeSubpath()
        case .ellipse:
            path.addEllipse(in: rawRect)
            path = path.applying(rotationTransform)
        case .arrow:
            path = arrowPath
        case .wall:
            path = wallPath
        case .axis:
            path = axisPath
        }
        return path
    }

    private var arrowPath: Path {
        var path = Path()
        path.move(to: start); path.addLine(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let head = max(12, width * 3)
        let left = CGPoint(x: end.x - head * cos(angle - .pi / 6), y: end.y - head * sin(angle - .pi / 6))
        let right = CGPoint(x: end.x - head * cos(angle + .pi / 6), y: end.y - head * sin(angle + .pi / 6))
        path.move(to: end); path.addLine(to: left)
        path.move(to: end); path.addLine(to: right)
        return path
    }

    private var wallPath: Path {
        var path = Path()
        path.move(to: start); path.addLine(to: end)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let ux = dx / length
        let uy = dy / length
        let px = -uy
        let py = ux
        let diagonalScale = max(1, sqrt((ux + px) * (ux + px) + (uy + py) * (uy + py)))
        let sx = (ux + px) / diagonalScale
        let sy = (uy + py) / diagonalScale
        let step: CGFloat = 16
        var cursor: CGFloat = 0
        while cursor <= length {
            let x = start.x + ux * cursor
            let y = start.y + uy * cursor
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + sx * 12, y: y + sy * 12))
            cursor += step
        }
        return path
    }

    private var axisPath: Path {
        var path = Path()
        let center = start
        let endpoint = end
        let second = axisSecondEndpoint
        path.move(to: center)
        path.addLine(to: endpoint)
        path.move(to: center)
        path.addLine(to: second)
        path.addPath(arrowHead(from: center, to: endpoint))
        path.addPath(arrowHead(from: center, to: second))
        return path
    }

    private func arrowHead(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        let angle = atan2(end.y - start.y, end.x - start.x)
        let head = max(10, width * 2.5)
        let left = CGPoint(x: end.x - head * cos(angle - .pi / 6), y: end.y - head * sin(angle - .pi / 6))
        let right = CGPoint(x: end.x - head * cos(angle + .pi / 6), y: end.y - head * sin(angle + .pi / 6))
        path.move(to: end); path.addLine(to: left)
        path.move(to: end); path.addLine(to: right)
        return path
    }

    private func rotatedPoint(_ point: CGPoint, around center: CGPoint, angle: CGFloat) -> CGPoint {
        let translatedX = point.x - center.x
        let translatedY = point.y - center.y
        let cosValue = cos(angle)
        let sinValue = sin(angle)
        return CGPoint(
            x: center.x + translatedX * cosValue - translatedY * sinValue,
            y: center.y + translatedX * sinValue + translatedY * cosValue
        )
    }
}

private struct TextElement: Identifiable {
    let id: UUID
    var rect: CGRect
    var text: String
    var color: Color
    var fontSize: CGFloat
    var fontName: String
    var formulaSource: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4, trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$") else { return nil }
        return String(trimmed.dropFirst(2).dropLast(2))
    }

    func render(in context: inout GraphicsContext) {
        context.draw(
            Text(text).font(.custom(fontName, size: fontSize)).foregroundColor(color),
            at: CGPoint(x: rect.minX, y: rect.minY),
            anchor: .topLeading
        )
    }

    func renderExport(in context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(color),
            .font: NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attributed)
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}

private struct DrawingFormulaPreview: NSViewRepresentable {
    let source: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let escaped = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8" />
        \(katexStyleTag())
        <style>html,body{margin:0;padding:0;background:transparent;overflow:hidden;}</style>
        </head>
        <body>
        <div id="formula"></div>
        \(scriptTag(fileName: "katex.min.js"))
        <script>
        const root = document.getElementById('formula');
        if (window.katex && root) {
            katex.render('\(escaped)', root, {throwOnError:false});
        } else if (root) {
            root.textContent = '\(escaped)';
        }
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
    }

    private func scriptTag(fileName: String) -> String {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: nil) else { return "" }
        return "<script src=\"\(url.absoluteString)\"></script>"
    }

    private func katexStyleTag() -> String {
        guard let url = Bundle.main.url(forResource: "katex.min.css", withExtension: nil) else { return "" }
        return "<link rel=\"stylesheet\" href=\"\(url.absoluteString)\" />"
    }
}
#endif
