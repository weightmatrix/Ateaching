import Foundation

enum ScreenCastContentKind: String, Codable, CaseIterable, Identifiable {
    case teaching
    case markdown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .teaching: "上课"
        case .markdown: "Markdown"
        }
    }

    var systemImage: String {
        switch self {
        case .teaching: "person.crop.rectangle"
        case .markdown: "doc.text"
        }
    }
}

struct ScreenCastDocumentSnapshot: Codable, Equatable, Identifiable {
    let kind: ScreenCastContentKind
    let title: String
    let html: String
    let revision: UInt64

    var id: ScreenCastContentKind { kind }
}

struct ScreenCastMember: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let colorHex: String
}

struct ScreenCastViewport: Codable, Equatable {
    var kind: ScreenCastContentKind
    var horizontalFraction: Double
    var verticalFraction: Double
    /// 主控编辑器真实可见区域，仅用于描述主控视口与后续精确定位；接收端按自己的可用区域排版。
    var sourceViewportWidth: Double?
    var sourceViewportHeight: Double?
    var pointerX: Double?
    var pointerY: Double?

    var sourceAspectRatio: CGFloat? {
        guard let sourceViewportWidth,
              let sourceViewportHeight,
              sourceViewportWidth > 0,
              sourceViewportHeight > 0 else { return nil }
        return CGFloat(sourceViewportWidth / sourceViewportHeight)
    }

    static func empty(for kind: ScreenCastContentKind) -> ScreenCastViewport {
        ScreenCastViewport(
            kind: kind,
            horizontalFraction: 0,
            verticalFraction: 0,
            sourceViewportWidth: nil,
            sourceViewportHeight: nil,
            pointerX: nil,
            pointerY: nil
        )
    }
}

struct ScreenCastPoint: Codable, Equatable {
    let x: Double
    let y: Double
}

struct ScreenCastStroke: Codable, Equatable, Identifiable {
    let id: UUID
    let memberID: UUID
    let colorHex: String
    let lineWidth: Double
    let points: [ScreenCastPoint]
}

struct ScreenCastSessionState: Codable, Equatable {
    let pin: String
    let hostName: String
    let enabledKinds: [ScreenCastContentKind]
    let members: [ScreenCastMember]
    let isPaused: Bool
}

enum ScreenCastWireKind: String, Codable {
    case hello
    case welcome
    case rejected
    case sessionState
    case document
    case viewport
    case stroke
    case removeStroke
    case clearMemberStrokes
    case ping
    case pong
}

struct ScreenCastWireEnvelope: Codable {
    let version: Int
    let kind: ScreenCastWireKind
    let payload: Data

    init<T: Encodable>(_ kind: ScreenCastWireKind, payload: T) throws {
        version = 1
        self.kind = kind
        self.payload = try JSONEncoder.screenCast.encode(payload)
    }
}

struct ScreenCastHello: Codable {
    let name: String
    let pin: String
    let deviceID: UUID
}

struct ScreenCastWelcome: Codable {
    let member: ScreenCastMember
    let state: ScreenCastSessionState
}

struct ScreenCastRejection: Codable {
    let reason: String
}

struct ScreenCastStrokeRemoval: Codable {
    let strokeID: UUID
}

struct ScreenCastMemberStrokeClear: Codable {
    let memberID: UUID
}

extension JSONEncoder {
    static var screenCast: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
