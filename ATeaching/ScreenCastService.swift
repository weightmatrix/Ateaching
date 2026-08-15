import Combine
import Foundation
import Network
import SwiftUI

@MainActor
final class ScreenCastService: ObservableObject {
    enum Mode {
        case idle
        case casting
        case receiving
    }

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var isConnected = false
    @Published private(set) var pin = ""
    @Published private(set) var hostName = ""
    @Published private(set) var statusMessage = "未连接"
    @Published private(set) var members: [ScreenCastMember] = []
    @Published private(set) var receivedDocuments: [ScreenCastContentKind: ScreenCastDocumentSnapshot] = [:]
    @Published private(set) var receivedViewport: ScreenCastViewport?
    @Published private(set) var strokes: [ScreenCastStroke] = []
    @Published var enabledKinds: Set<ScreenCastContentKind> = [.teaching] {
        didSet {
            guard mode == .casting, enabledKinds != oldValue else { return }
            ScreenCastContentHub.shared.setRequestedKinds(enabledKinds)
            publishSessionState()
            sendEnabledDocuments()
        }
    }
    @Published var selectedReceivedKind: ScreenCastContentKind = .teaching

    var isCasting: Bool { mode == .casting }
    var isReceiving: Bool { mode == .receiving }
    var receivedDocument: ScreenCastDocumentSnapshot? { receivedDocuments[selectedReceivedKind] }
    var localAnnotationColorHex: String { localMember?.colorHex ?? "#007AFF" }

    private let serviceType = "_ateaching-cast._tcp"
    private let queue = DispatchQueue(label: "Han.ATeaching.ScreenCast.Network", qos: .userInitiated)
    private let deviceID: UUID
    private let palette = [
        "#007AFF", "#34C759", "#FF9500", "#AF52DE", "#FF2D55", "#00A7A7",
        "#5856D6", "#A65E2E", "#64D2FF", "#FFD60A", "#BF5AF2", "#FF453A"
    ]

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var hostPeers: [UUID: ScreenCastPeerConnection] = [:]
    private var candidatePeers: [UUID: ScreenCastPeerConnection] = [:]
    private var attemptedEndpoints: Set<String> = []
    private var receiverPeer: ScreenCastPeerConnection?
    private var localMember: ScreenCastMember?
    private var requestedName = ""
    private var contentCancellables: Set<AnyCancellable> = []
    private var viewportTimer: Timer?
    private var lastPublishedViewport: ScreenCastViewport?
    private var hostIsPaused = false

    init() {
        let key = "ScreenCast.deviceID"
        if let raw = UserDefaults.standard.string(forKey: key), let value = UUID(uuidString: raw) {
            deviceID = value
        } else {
            let value = UUID()
            deviceID = value
            UserDefaults.standard.set(value.uuidString, forKey: key)
        }
        observeContentHub()
    }

    func startCasting(pin: String, name: String) {
        let cleanPIN = Self.normalizedPIN(pin)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanPIN.count == 4, cleanName.isEmpty == false else {
            statusMessage = "请输入名字和四位数字"
            return
        }

        stopAll(reason: "startCasting启动前清理旧会话")
        mode = .casting
        self.pin = cleanPIN
        requestedName = cleanName
        hostName = cleanName
        localMember = ScreenCastMember(id: deviceID, name: cleanName, colorHex: palette[0])
        members = localMember.map { [$0] } ?? []
        statusMessage = "正在启动投屏"
        ScreenCastContentHub.shared.setRequestedKinds(enabledKinds)

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(
                name: "ATeaching-\(deviceID.uuidString.prefix(8))",
                type: serviceType
            )
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in self?.handleListenerState(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in self?.accept(connection) }
            }
            self.listener = listener
            listener.start(queue: queue)
            startViewportMonitoring()
        } catch {
            stopAll(
                reason: "NWListener创建抛错：\(String(reflecting: error))",
                finalStatus: "启动失败：\(error.localizedDescription)"
            )
        }
    }

    func changeCastingPIN(_ value: String) {
        let cleanPIN = Self.normalizedPIN(value)
        guard cleanPIN.count == 4, isCasting else { return }
        pin = cleanPIN
        for peer in hostPeers.values {
            peer.send(.rejected, payload: ScreenCastRejection(reason: "主控已更换四位数字，请重新连接"))
            peer.cancel()
        }
        hostPeers.removeAll()
        rebuildHostMembers()
        publishSessionState()
        statusMessage = "四位数字已更新，等待重新连接"
    }

    func startReceiving(pin: String, name: String) {
        let cleanPIN = Self.normalizedPIN(pin)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanPIN.count == 4, cleanName.isEmpty == false else {
            statusMessage = "请输入名字和四位数字"
            return
        }

        stopAll(reason: "startReceiving启动前清理旧会话")
        mode = .receiving
        self.pin = cleanPIN
        requestedName = cleanName
        statusMessage = "正在同一 Wi-Fi 内寻找投屏"
        UserDefaults.standard.set(cleanPIN, forKey: "ScreenCast.lastReceivePIN")

        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in self?.handleBrowserState(state) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in self?.connectToDiscoveredResults(results) }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    func reconnect(with pin: String) {
        guard isReceiving else { return }
        startReceiving(pin: pin, name: requestedName)
    }

    func stopAll(
        reason: String = "调用方请求",
        finalStatus: String = "未连接"
    ) {
        _ = reason
        listener?.cancel()
        listener = nil
        viewportTimer?.invalidate()
        viewportTimer = nil
        lastPublishedViewport = nil
        hostIsPaused = false
        browser?.cancel()
        browser = nil
        hostPeers.values.forEach { $0.cancel() }
        candidatePeers.values.forEach { $0.cancel() }
        receiverPeer?.cancel()
        hostPeers.removeAll()
        candidatePeers.removeAll()
        attemptedEndpoints.removeAll()
        receiverPeer = nil
        localMember = nil
        mode = .idle
        isConnected = false
        pin = ""
        hostName = ""
        members = []
        receivedDocuments = [:]
        receivedViewport = nil
        strokes = []
        ScreenCastAnnotationHub.shared.replace(with: [])
        statusMessage = finalStatus
        ScreenCastContentHub.shared.setRequestedKinds([])
    }

    func publishViewport(_ viewport: ScreenCastViewport) {
        guard isCasting, enabledKinds.contains(viewport.kind) else { return }
        broadcast(.viewport, payload: viewport)
    }

    func addLocalStroke(points: [ScreenCastPoint], lineWidth: Double = 3) {
        guard isReceiving, let member = localMember, points.isEmpty == false else { return }
        let stroke = ScreenCastStroke(
            id: UUID(),
            memberID: member.id,
            colorHex: member.colorHex,
            lineWidth: lineWidth,
            points: points
        )
        strokes.append(stroke)
        syncAnnotationHub()
        receiverPeer?.send(.stroke, payload: stroke)
    }

    func removeLocalStroke(_ strokeID: UUID) {
        guard isReceiving else { return }
        strokes.removeAll { $0.id == strokeID }
        syncAnnotationHub()
        receiverPeer?.send(.removeStroke, payload: ScreenCastStrokeRemoval(strokeID: strokeID))
    }

    func clearLocalStrokes() {
        guard isReceiving, let member = localMember else { return }
        strokes.removeAll { $0.memberID == member.id }
        syncAnnotationHub()
        receiverPeer?.send(.clearMemberStrokes, payload: ScreenCastMemberStrokeClear(memberID: member.id))
    }

    static func normalizedPIN(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(4))
    }

    static func randomPIN() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }

    private func observeContentHub() {
        let hub = ScreenCastContentHub.shared
        hub.$teachingSnapshot
            .compactMap { $0 }
            .sink { [weak self] snapshot in
                guard let self, self.isCasting, self.enabledKinds.contains(.teaching) else { return }
                self.broadcast(.document, payload: snapshot)
            }
            .store(in: &contentCancellables)
        hub.$markdownSnapshot
            .compactMap { $0 }
            .sink { [weak self] snapshot in
                guard let self, self.isCasting, self.enabledKinds.contains(.markdown) else { return }
                self.broadcast(.document, payload: snapshot)
            }
            .store(in: &contentCancellables)
    }

    private func handleListenerState(_ state: NWListener.State) {
        guard isCasting else { return }
        switch state {
        case .ready:
            statusMessage = "投屏中，等待接收端"
        case .failed(let error):
            stopAll(
                reason: "Listener失败：\(String(reflecting: error))",
                finalStatus: "投屏失败：\(error.localizedDescription)"
            )
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard isCasting else {
            connection.cancel()
            return
        }
        let peer = ScreenCastPeerConnection(connection: connection)
        hostPeers[peer.id] = peer
        peer.onEnvelope = { [weak self, weak peer] envelope in
            Task { @MainActor [weak self, weak peer] in
                guard let peer else { return }
                self?.handleHostEnvelope(envelope, from: peer)
            }
        }
        peer.onStateChange = { [weak self, weak peer] state in
            Task { @MainActor [weak self, weak peer] in
                guard let peer else { return }
                self?.handleHostPeerState(state, peer: peer)
            }
        }
        peer.start(on: queue)
    }

    private func handleHostEnvelope(_ envelope: ScreenCastWireEnvelope, from peer: ScreenCastPeerConnection) {
        switch envelope.kind {
        case .hello:
            guard let hello = try? JSONDecoder().decode(ScreenCastHello.self, from: envelope.payload) else { return }
            guard hello.pin == pin else {
                peer.send(.rejected, payload: ScreenCastRejection(reason: "四位数字不匹配"))
                peer.cancel()
                return
            }
            let existingColor = members.first(where: { $0.id == hello.deviceID })?.colorHex
            let color = existingColor ?? receiverColor(for: hello.deviceID)
            let member = ScreenCastMember(id: hello.deviceID, name: hello.name, colorHex: color)
            peer.member = member
            rebuildHostMembers()
            let state = currentSessionState()
            peer.send(.welcome, payload: ScreenCastWelcome(member: member, state: state))
            publishSessionState()
            sendEnabledDocuments(to: peer)
            statusMessage = "投屏中，已连接 \(max(0, members.count - 1)) 人"
        case .stroke:
            guard peer.member != nil,
                  let stroke = try? JSONDecoder().decode(ScreenCastStroke.self, from: envelope.payload) else { return }
            strokes.append(stroke)
            syncAnnotationHub()
            broadcast(.stroke, payload: stroke, excluding: peer.id)
        case .removeStroke:
            guard let removal = try? JSONDecoder().decode(ScreenCastStrokeRemoval.self, from: envelope.payload) else { return }
            strokes.removeAll { $0.id == removal.strokeID }
            syncAnnotationHub()
            broadcast(.removeStroke, payload: removal, excluding: peer.id)
        case .clearMemberStrokes:
            guard let clear = try? JSONDecoder().decode(ScreenCastMemberStrokeClear.self, from: envelope.payload) else { return }
            strokes.removeAll { $0.memberID == clear.memberID }
            syncAnnotationHub()
            broadcast(.clearMemberStrokes, payload: clear, excluding: peer.id)
        case .ping:
            peer.send(.pong, payload: true)
        default:
            break
        }
    }

    private func handleHostPeerState(_ state: NWConnection.State, peer: ScreenCastPeerConnection) {
        switch state {
        case .failed, .cancelled:
            hostPeers.removeValue(forKey: peer.id)
            rebuildHostMembers()
            publishSessionState()
            statusMessage = members.count > 1 ? "投屏中，已连接 \(members.count - 1) 人" : "投屏中，等待接收端"
        default:
            break
        }
    }

    private func handleBrowserState(_ state: NWBrowser.State) {
        guard isReceiving else { return }
        if case .failed(let error) = state {
            statusMessage = "搜索失败：\(error.localizedDescription)"
        }
    }

    private func connectToDiscoveredResults(_ results: Set<NWBrowser.Result>) {
        guard isReceiving, receiverPeer == nil else { return }
        for result in results {
            let key = String(describing: result.endpoint)
            guard attemptedEndpoints.insert(key).inserted else { continue }
            let connection = NWConnection(to: result.endpoint, using: .tcp)
            let peer = ScreenCastPeerConnection(connection: connection)
            candidatePeers[peer.id] = peer
            peer.onEnvelope = { [weak self, weak peer] envelope in
                Task { @MainActor [weak self, weak peer] in
                    guard let peer else { return }
                    self?.handleReceiverEnvelope(envelope, from: peer)
                }
            }
            peer.onStateChange = { [weak self, weak peer] state in
                Task { @MainActor [weak self, weak peer] in
                    guard let peer else { return }
                    self?.handleReceiverPeerState(state, peer: peer)
                }
            }
            peer.start(on: queue)
        }
    }

    private func handleReceiverPeerState(_ state: NWConnection.State, peer: ScreenCastPeerConnection) {
        guard isReceiving else { return }
        switch state {
        case .ready:
            peer.send(.hello, payload: ScreenCastHello(name: requestedName, pin: pin, deviceID: deviceID))
        case .failed, .cancelled:
            candidatePeers.removeValue(forKey: peer.id)
            if receiverPeer?.id == peer.id {
                receiverPeer = nil
                localMember = nil
                isConnected = false
                browser?.cancel()
                browser = nil
                statusMessage = "连接已断开，请确认四位数字后重新连接"
            }
        default:
            break
        }
    }

    private func handleReceiverEnvelope(_ envelope: ScreenCastWireEnvelope, from peer: ScreenCastPeerConnection) {
        switch envelope.kind {
        case .welcome:
            guard receiverPeer == nil,
                  let welcome = try? JSONDecoder().decode(ScreenCastWelcome.self, from: envelope.payload) else { return }
            receiverPeer = peer
            localMember = welcome.member
            candidatePeers.values.filter { $0.id != peer.id }.forEach { $0.cancel() }
            candidatePeers = [peer.id: peer]
            apply(welcome.state)
            isConnected = true
            statusMessage = "已连接 \(welcome.state.hostName)"
        case .rejected:
            if let rejection = try? JSONDecoder().decode(ScreenCastRejection.self, from: envelope.payload) {
                statusMessage = rejection.reason
            }
            peer.cancel()
        case .sessionState:
            guard let state = try? JSONDecoder().decode(ScreenCastSessionState.self, from: envelope.payload) else { return }
            apply(state)
        case .document:
            guard let document = try? JSONDecoder().decode(ScreenCastDocumentSnapshot.self, from: envelope.payload) else { return }
            receivedDocuments[document.kind] = document
            if receivedDocuments[selectedReceivedKind] == nil {
                selectedReceivedKind = document.kind
            }
        case .viewport:
            receivedViewport = try? JSONDecoder().decode(ScreenCastViewport.self, from: envelope.payload)
        case .stroke:
            guard let stroke = try? JSONDecoder().decode(ScreenCastStroke.self, from: envelope.payload) else { return }
            strokes.removeAll { $0.id == stroke.id }
            strokes.append(stroke)
            syncAnnotationHub()
        case .removeStroke:
            guard let removal = try? JSONDecoder().decode(ScreenCastStrokeRemoval.self, from: envelope.payload) else { return }
            strokes.removeAll { $0.id == removal.strokeID }
            syncAnnotationHub()
        case .clearMemberStrokes:
            guard let clear = try? JSONDecoder().decode(ScreenCastMemberStrokeClear.self, from: envelope.payload) else { return }
            strokes.removeAll { $0.memberID == clear.memberID }
            syncAnnotationHub()
        case .ping:
            peer.send(.pong, payload: true)
        default:
            break
        }
    }

    private func apply(_ state: ScreenCastSessionState) {
        pin = state.pin
        hostName = state.hostName
        members = state.members
        let allowed = Set(state.enabledKinds)
        receivedDocuments = receivedDocuments.filter { allowed.contains($0.key) }
        if allowed.contains(selectedReceivedKind) == false, let first = state.enabledKinds.first {
            selectedReceivedKind = first
        }
        statusMessage = state.isPaused ? "主控已暂停，保留最后画面" : "已连接 \(state.hostName)"
    }

    private func currentSessionState() -> ScreenCastSessionState {
        ScreenCastSessionState(
            pin: pin,
            hostName: hostName,
            enabledKinds: ScreenCastContentKind.allCases.filter { enabledKinds.contains($0) },
            members: members,
            isPaused: hostIsPaused
        )
    }

    private func publishSessionState() {
        guard isCasting else { return }
        broadcast(.sessionState, payload: currentSessionState())
    }

    private func rebuildHostMembers() {
        let receivers = hostPeers.values.compactMap(\.member).sorted { lhs, rhs in
            if lhs.name == rhs.name { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        members = (localMember.map { [$0] } ?? []) + receivers
        isConnected = receivers.isEmpty == false
    }

    private func receiverColor(for id: UUID) -> String {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        let checksum = bytes.reduce(0) { ($0 &* 31) &+ Int($1) }
        let colorCount = max(1, palette.count - 1)
        let start = Int(checksum.magnitude % UInt(colorCount))
        let usedColors = Set(members.map(\.colorHex))
        for offset in 0..<colorCount {
            let candidate = palette[1 + (start + offset) % colorCount]
            if usedColors.contains(candidate) == false { return candidate }
        }
        let red = 64 + Int(bytes[0]) % 160
        let green = 64 + Int(bytes[5]) % 160
        let blue = 64 + Int(bytes[10]) % 160
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private func sendEnabledDocuments() {
        hostPeers.values.filter { $0.member != nil }.forEach(sendEnabledDocuments(to:))
    }

    private func sendEnabledDocuments(to peer: ScreenCastPeerConnection) {
        for kind in ScreenCastContentKind.allCases where enabledKinds.contains(kind) {
            if let snapshot = ScreenCastContentHub.shared.snapshot(for: kind) {
                peer.send(.document, payload: snapshot)
            }
        }
    }

    private func broadcast<T: Encodable>(_ kind: ScreenCastWireKind, payload: T, excluding peerID: UUID? = nil) {
        for peer in hostPeers.values where peer.member != nil && peer.id != peerID {
            peer.send(kind, payload: payload)
        }
    }

    private func startViewportMonitoring() {
        viewportTimer?.invalidate()
        viewportTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sampleAndPublishViewport() }
        }
    }

    private func syncAnnotationHub() {
        ScreenCastAnnotationHub.shared.replace(with: strokes)
    }

    private func sampleAndPublishViewport() {
        guard isCasting else { return }
        guard let viewport = ScreenCastViewportMonitor.sample(enabledKinds: enabledKinds) else {
            if hostIsPaused == false {
                hostIsPaused = true
                publishSessionState()
            }
            return
        }
        if hostIsPaused {
            hostIsPaused = false
            publishSessionState()
        }
        guard viewport != lastPublishedViewport else { return }
        lastPublishedViewport = viewport
        broadcast(.viewport, payload: viewport)
    }

}
