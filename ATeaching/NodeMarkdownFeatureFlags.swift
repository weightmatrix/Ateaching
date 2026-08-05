import Foundation

// MARK: - NodeMarkdown编辑器管线 - v1 - Debug页二选一切换TextKit2与旧TextKit
public enum NodeMarkdownEditorPipeline: String, CaseIterable, Identifiable, Codable {
    case textKit2
    case legacyTextKit

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .textKit2:
            return "TextKit2"
        case .legacyTextKit:
            return "旧TextKit"
        }
    }
}

// MARK: - NodeMarkdown功能开关 - v1 - 集中控制阶段性能力便于快速整体下线
enum NodeMarkdownFeatureFlags {
    static let phase150PackEnabled = true
    static let performanceProfilingEnabled = false
    static let renderTraceEnabled = false
    static let renderSmokeEnabled = false
    static let layoutJitterDebugEnabled = false
    static var textKit2EditorEnabled: Bool {
        TeachingDebugLogStore.nodeMarkdownEditorPipeline() == .textKit2
    }
}
