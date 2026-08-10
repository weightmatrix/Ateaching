// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import Foundation

#if os(macOS)
import AppKit

/// 2-19期间只保留滚动、缩放与装饰绘制时序诊断。
enum NodeMarkdownTextKit2Diagnostics {
    static func log(_ message: @autoclosure () -> String) {
        // 旧诊断已停用。保留入口是为了避免诊断清理扩大到业务文件。
    }

    static func report(
        stage: String,
        textView: NodeMarkdownTextKit2TextView,
        bindingText: String? = nil,
        metadataCount: Int? = nil,
        rowLayoutCount: Int? = nil
    ) {
        // 旧的六行通用报告已停用；它会主动查询首片段，可能干扰本次布局诊断。
    }

    static func log19(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("【诊断-19】\(message())")
        #endif
    }
}
#endif
