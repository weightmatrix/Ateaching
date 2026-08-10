// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    func blocksCompleteProtectedH3Deletion(
        in textView: NodeMarkdownTextKit2TextView,
        affectedRange: NSRange? = nil
    ) -> Bool {
        let deletionRanges = deletionCandidateRanges(in: textView, affectedRange: affectedRange)
        guard !deletionRanges.isEmpty else { return false }
        let protectedRoots = rowLayouts
            .filter { $0.level == 3 && $0.isProtectedH3 }
            .map(\.contentRange)
        let isBlocked = protectedRoots.contains { contentRange in
            range(contentRange, isCoveredBy: deletionRanges)
        }
        if isBlocked {
            showProtectedH3SelectionDeleteAlert()
        }
        return isBlocked
    }

    private func deletionCandidateRanges(
        in textView: NodeMarkdownTextKit2TextView,
        affectedRange: NSRange?
    ) -> [NSRange] {
        let selectedRanges = textView.selectedRanges
            .map(\.rangeValue)
            .filter { $0.length > 0 }
        if !selectedRanges.isEmpty {
            return selectedRanges
        }
        if let affectedRange, affectedRange.length > 0 {
            return [affectedRange]
        }
        return []
    }

    private func range(_ target: NSRange, isCoveredBy ranges: [NSRange]) -> Bool {
        let targetEnd = NSMaxRange(target)
        var coveredUntil = target.location
        for range in ranges.sorted(by: { $0.location < $1.location }) {
            let clipped = NSIntersectionRange(target, range)
            guard clipped.length > 0 else { continue }
            if clipped.location > coveredUntil {
                return false
            }
            coveredUntil = max(coveredUntil, NSMaxRange(clipped))
            if coveredUntil >= targetEnd {
                return true
            }
        }
        return coveredUntil >= targetEnd
    }

    func showProtectedH3Alert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "母本H3包保护"
        alert.informativeText = "该H3节点关联母本，不能通过行首Backspace合并删除。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func showProtectedH3SelectionDeleteAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "母本H3包保护"
        alert.informativeText = "当前选区包含受保护的母本H3节点，请使用右键菜单处理。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}
#endif
