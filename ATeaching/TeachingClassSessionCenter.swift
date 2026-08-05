import Foundation

extension Notification.Name {
    static let teachingClassSessionDidChange = Notification.Name("TeachingClassSessionDidChange")
}

@MainActor
final class TeachingClassSessionCenter {
    static let shared = TeachingClassSessionCenter()

    enum SessionKind {
        case teaching
        case notes

        var shouldAutoFinishOnDisappear: Bool {
            switch self {
            case .teaching:
                return true
            case .notes:
                return false
            }
        }
    }

    final class Session {
        let kind: SessionKind
        let notebookPath: String
        let onOpenLessonChecklist: () -> Void
        let onUpdate: () -> Void
        let onOpenReflection: () -> Void
        let onFinishClass: () -> Void
        let onExitSession: () -> Void

        init(
            kind: SessionKind,
            notebookPath: String,
            onOpenLessonChecklist: @escaping () -> Void,
            onUpdate: @escaping () -> Void,
            onOpenReflection: @escaping () -> Void,
            onFinishClass: @escaping () -> Void,
            onExitSession: @escaping () -> Void
        ) {
            self.kind = kind
            self.notebookPath = notebookPath
            self.onOpenLessonChecklist = onOpenLessonChecklist
            self.onUpdate = onUpdate
            self.onOpenReflection = onOpenReflection
            self.onFinishClass = onFinishClass
            self.onExitSession = onExitSession
        }
    }

    private(set) var session: Session?
    private var isFinishingFromToolbar = false

    func start(
        kind: SessionKind = .teaching,
        notebookPath: String,
        onOpenLessonChecklist: @escaping () -> Void,
        onUpdate: @escaping () -> Void,
        onOpenReflection: @escaping () -> Void,
        onFinishClass: @escaping () -> Void,
        onExitSession: @escaping () -> Void
    ) {
        let standardizedPath = URL(fileURLWithPath: notebookPath).standardizedFileURL.path
        session = Session(
            kind: kind,
            notebookPath: standardizedPath,
            onOpenLessonChecklist: onOpenLessonChecklist,
            onUpdate: onUpdate,
            onOpenReflection: onOpenReflection,
            onFinishClass: onFinishClass,
            onExitSession: onExitSession
        )
        isFinishingFromToolbar = false
        postSessionChange(for: standardizedPath)
    }

    func end() {
        let notebookPath = session?.notebookPath
        session = nil
        isFinishingFromToolbar = false
        postSessionChange(for: notebookPath)
    }

    func isActive(for notebookPath: String) -> Bool {
        guard let session else { return false }
        return session.notebookPath == URL(fileURLWithPath: notebookPath).standardizedFileURL.path
    }

    func shouldAutoFinishOnDisappear(for notebookPath: String) -> Bool {
        guard let session, isActive(for: notebookPath) else { return false }
        return session.kind.shouldAutoFinishOnDisappear && !isFinishingFromToolbar
    }

    func markToolbarFinishing() {
        isFinishingFromToolbar = true
    }

    private func postSessionChange(for notebookPath: String?) {
        var userInfo: [String: Any] = [:]
        if let notebookPath {
            userInfo["filePath"] = notebookPath
        }
        NotificationCenter.default.post(
            name: .teachingClassSessionDidChange,
            object: nil,
            userInfo: userInfo
        )
    }
}
