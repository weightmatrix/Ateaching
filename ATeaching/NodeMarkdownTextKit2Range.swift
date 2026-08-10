// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import Foundation

extension NSRange {
    func exact(toLength length: Int) -> NSRange? {
        guard length >= 0,
              location != NSNotFound,
              location >= 0,
              self.length >= 0,
              location <= length,
              self.length <= length - location else { return nil }
        return self
    }

    // 旧管线仍使用范围截断；TextKit2新管线的Node事务只能使用exact(toLength:)。
    func clamped(toLength length: Int) -> NSRange? {
        guard location != NSNotFound else { return nil }
        let lower = max(0, min(location, length))
        let upper = max(lower, min(location + self.length, length))
        return NSRange(location: lower, length: upper - lower)
    }
}
