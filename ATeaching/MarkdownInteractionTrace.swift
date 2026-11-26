import Foundation

/// Opt-in diagnostics for ordinary Markdown. Payloads contain timing and numeric
/// metadata only. Small batches keep individual input events out of the log writer.
@MainActor
final class MarkdownInteractionTrace {
    private struct PendingInput {
        let id: Int
        let kind: String
        let eventTime: TimeInterval
    }

    private let id = UUID().uuidString.prefix(8)
    private let requestedAt: TimeInterval
    private var loadedLength: Int?
    private var ready = false
    private var firstDraw = false
    private var pendingInputs: [PendingInput] = []
    private var samples: [String] = []
    private var nextInputID = 0
    private var flushWork: DispatchWorkItem?
    private var previousViewportUpdate: TimeInterval?

    static var enabled: Bool { UserDefaults.standard.bool(forKey: "Markdown.tracePerformance") }

    init(requestedAt: TimeInterval) {
        self.requestedAt = requestedAt
        stage("open.request", since: requestedAt)
    }

    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func stage(_ name: String, since start: TimeInterval, detail: String = "") {
        append("\(name) ms=\(ms(Self.now - start)) \(detail)")
    }

    func loaded(length: Int, since start: TimeInterval) {
        if !ready { loadedLength = length }
        stage("open.readDecodeDigest", since: start, detail: "utf16=\(length)")
    }

    func editorReady(length: Int, viewportStyling: Bool) {
        guard !ready, loadedLength == length else { return }
        ready = true
        stage("open.editable", since: requestedAt, detail: "utf16=\(length) viewportStyling=\(viewportStyling)")
    }

    func input(kind: String, eventTime: TimeInterval, startedAt: TimeInterval) -> Int {
        nextInputID += 1
        let index = nextInputID
        if pendingInputs.count == 128 {
            let dropped = pendingInputs.removeFirst()
            append("input.unpainted id=\(dropped.id) kind=\(dropped.kind)")
        }
        pendingInputs.append(PendingInput(id: index, kind: kind, eventTime: eventTime))
        append("input.event id=\(index) kind=\(kind) queueMs=\(ms(startedAt - eventTime))")
        return index
    }

    func inputHandled(id: Int, since start: TimeInterval, marked: Bool) {
        stage("input.handled", since: start, detail: "id=\(id) marked=\(marked)")
    }

    func viewportMoved(distance: Double) {
        let now = Self.now
        if let previousViewportUpdate, now - previousViewportUpdate < 0.05, abs(distance) < 2_000 { return }
        append("viewport.move dy=\(Int(distance))")
        previousViewportUpdate = now
    }

    func didDraw() {
        guard ready else { return }
        if !firstDraw {
            firstDraw = true
            stage("open.firstDraw", since: requestedAt)
        }
        guard !pendingInputs.isEmpty else { return }
        let now = Self.now
        for input in pendingInputs {
            append("input.nextDraw id=\(input.id) kind=\(input.kind) ms=\(ms(now - input.eventTime))")
        }
        pendingInputs.removeAll(keepingCapacity: true)
    }

    func finish() {
        for input in pendingInputs {
            append("input.unpainted id=\(input.id) kind=\(input.kind)")
        }
        pendingInputs.removeAll()
        flush()
    }

    private func append(_ sample: String) {
        samples.append("t=\(ms(Self.now - requestedAt)) " + sample)
        if samples.count >= 8 {
            flush()
        } else if flushWork == nil {
            let work = DispatchWorkItem { [weak self] in self?.flush() }
            flushWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    private func flush() {
        flushWork?.cancel()
        flushWork = nil
        guard !samples.isEmpty else { return }
        TeachingDebugLogStore.append("trace=\(id) " + samples.joined(separator: " | "),
                                     category: "Markdown.Interaction", force: true)
        samples.removeAll(keepingCapacity: true)
    }

    private func ms(_ seconds: TimeInterval) -> String {
        String(format: "%.2f", max(0, seconds) * 1_000)
    }
}
