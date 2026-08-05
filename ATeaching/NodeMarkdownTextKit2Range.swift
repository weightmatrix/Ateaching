// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import Foundation

extension NSRange {
    func clamped(toLength length: Int) -> NSRange? {
        guard location != NSNotFound else { return nil }
        let lower = max(0, min(location, length))
        let upper = max(lower, min(location + self.length, length))
        return NSRange(location: lower, length: upper - lower)
    }
}
