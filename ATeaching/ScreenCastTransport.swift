import Foundation
import Network

final class ScreenCastPeerConnection {
    let id = UUID()
    let connection: NWConnection
    var member: ScreenCastMember?

    var onEnvelope: ((ScreenCastWireEnvelope) -> Void)?
    var onStateChange: ((NWConnection.State) -> Void)?

    private var receiveBuffer = Data()
    private let encoder = JSONEncoder.screenCast
    private let decoder = JSONDecoder()
    private let maximumFrameLength = 128 * 1024 * 1024

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start(on queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            self?.onStateChange?(state)
        }
        connection.start(queue: queue)
        receiveNext()
    }

    func cancel() {
        connection.cancel()
    }

    func send<T: Encodable>(_ kind: ScreenCastWireKind, payload: T) {
        do {
            let envelope = try ScreenCastWireEnvelope(kind, payload: payload)
            let encoded = try encoder.encode(envelope)
            guard encoded.count <= maximumFrameLength else { return }
            var length = UInt32(encoded.count).bigEndian
            var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
            frame.append(encoded)
            connection.send(content: frame, completion: .contentProcessed { _ in })
        } catch {
            return
        }
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                receiveBuffer.append(data)
                drainFrames()
            }
            if error == nil, !isComplete {
                receiveNext()
            }
        }
    }

    private func drainFrames() {
        while receiveBuffer.count >= MemoryLayout<UInt32>.size {
            let length = Int(receiveBuffer.withUnsafeBytes { rawBuffer in
                rawBuffer.loadUnaligned(as: UInt32.self).bigEndian
            })
            guard length > 0, length <= maximumFrameLength else {
                cancel()
                receiveBuffer.removeAll(keepingCapacity: false)
                return
            }
            let frameLength = MemoryLayout<UInt32>.size + length
            guard receiveBuffer.count >= frameLength else { return }
            let payload = receiveBuffer.subdata(in: MemoryLayout<UInt32>.size..<frameLength)
            receiveBuffer.removeSubrange(0..<frameLength)
            guard let envelope = try? decoder.decode(ScreenCastWireEnvelope.self, from: payload),
                  envelope.version == 1 else { continue }
            onEnvelope?(envelope)
        }
    }
}
