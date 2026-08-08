import Foundation
import Network
import SwiftUI
import Combine

final class ScreenCastService: ObservableObject {
    @Published var isCasting = false
    @Published var isReceiving = false
    @Published var localIP = ""
    @Published var connectedHost = ""
    @Published var receivedDocument: NodeMarkdownDocument?
    @Published var receivedStudentName: String?
    @Published var statusMessage = ""
    @Published var receiverColors: [String: Color] = [:]

    private(set) var port: UInt16 = 55555
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var receiveConnection: NWConnection?
    private var receiverColorIndex = 0

    private let colorPalette: [Color] = [.blue, .green, .orange, .purple, .teal, .mint, .pink, .indigo, .cyan, .brown]

    init() {}

    // MARK: - Cast

    func startCasting() {
        stopAll()
        isCasting = true
        localIP = Self.localWiFiAddress()
        statusMessage = ""
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    Task { @MainActor in
                        self?.statusMessage = "监听失败: \(error.localizedDescription)"
                        self?.stopCasting()
                    }
                }
            }
            listener?.newConnectionHandler = { [weak self] conn in
                self?.connections.append(conn)
                conn.start(queue: .main)
            }
            listener?.start(queue: .main)
        } catch {
            statusMessage = "启动失败: \(error.localizedDescription)"
            stopCasting()
        }
    }

    func stopCasting() {
        listener?.cancel()
        listener = nil
        for c in connections { c.cancel() }
        connections.removeAll()
        isCasting = false
    }

    func pushDocument(_ document: NodeMarkdownDocument, studentName: String?) {
        guard isCasting else { return }
        let encoder = JSONEncoder()
        guard let docData = try? encoder.encode(document.nodes) else { return }
        let nameData = (studentName ?? "学生").data(using: .utf8)!
        var payload = Data()
        var nameLen = UInt32(nameData.count).bigEndian
        var docLen = UInt32(docData.count).bigEndian
        payload.append(Data(bytes: &nameLen, count: 4))
        payload.append(nameData)
        payload.append(Data(bytes: &docLen, count: 4))
        payload.append(docData)
        for conn in connections {
            conn.send(content: payload, completion: .idempotent)
        }
    }

    // MARK: - Receive

    func startReceiving(host: String, port: UInt16) {
        stopAll()
        isReceiving = true
        connectedHost = host
        self.port = port
        let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        receiveConnection = conn
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor in self?.onReceiveReady(conn) }
            case .failed(let error):
                Task { @MainActor in
                    self?.statusMessage = "连接失败: \(error.localizedDescription)"
                    self?.stopReceiving()
                }
            default: break
            }
        }
        conn.start(queue: .main)
    }

    private func onReceiveReady(_ conn: NWConnection) {
        statusMessage = "已连接"
        conn.send(content: "REQUEST_DOC".data(using: .utf8)!, completion: .idempotent)
        receivePayload(conn)
    }

    func stopReceiving() {
        receiveConnection?.cancel()
        receiveConnection = nil
        isReceiving = false
        receivedDocument = nil
    }

    private func receivePayload(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, let data = data, !isComplete, error == nil else { return }
            self.parsePayload(data)
            self.receivePayload(conn)
        }
    }

    private func parsePayload(_ data: Data) {
        guard data.count >= 8 else { return }
        var offset = 0
        let nameLen = Int(data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
        offset += 4
        guard offset + nameLen <= data.count else { return }
        let name = String(data: data.subdata(in: offset..<offset + nameLen), encoding: .utf8)
        offset += nameLen
        let docLen = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian })
        offset += 4
        guard offset + docLen <= data.count else { return }
        let docData = data.subdata(in: offset..<offset + docLen)
        if let nodes = try? JSONDecoder().decode([NodeMarkdownNode].self, from: docData) {
            var doc = NodeMarkdownDocument(nodes: nodes)
            _ = doc.ensureTrailingBlankLine(defaultLevel: 1)
            receivedDocument = doc
            receivedStudentName = name
            assignColor(for: name ?? "学生")
        }
    }

    private func assignColor(for name: String) {
        if receiverColors[name] == nil {
            receiverColors[name] = colorPalette[receiverColorIndex % colorPalette.count]
            receiverColorIndex += 1
        }
    }

    func annotationColor(for name: String?) -> Color {
        guard let name else { return .blue }
        return receiverColors[name] ?? .blue
    }

    func stopAll() {
        stopCasting()
        stopReceiving()
    }

    static func localWiFiAddress() -> String {
        var addr = ""
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return "127.0.0.1" }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ptr.pointee.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            let sa = ptr.pointee.ifa_addr.pointee
            guard sa.sa_family == UInt8(AF_INET) else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(ptr.pointee.ifa_addr, socklen_t(sa.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            addr = String(cString: hostname)
            break
        }
        return addr.isEmpty ? "127.0.0.1" : addr
    }
}
