import SwiftUI

// MARK: - 学生设置绑定工具 - v2 - 统一可选字符串与教案多选绑定生成
enum TeachingStudentSelectionBindings {
    static func optionalString<T>(
        settings: Binding<T>,
        keyPath: WritableKeyPath<T, String?>
    ) -> Binding<String?> {
        Binding(
            get: { settings.wrappedValue[keyPath: keyPath] },
            set: { settings.wrappedValue[keyPath: keyPath] = $0 }
        )
    }

    static func containsLessonPlanFolder<T: TeachingStudentMappingSettings>(
        settings: Binding<T>,
        folder: String
    ) -> Binding<Bool> {
        Binding(
            get: { settings.wrappedValue.lessonPlanFolderIDs.contains(folder) },
            set: { isSelected in
                var next = settings.wrappedValue.lessonPlanFolderIDs
                if isSelected {
                    if !next.contains(folder) {
                        next.append(folder)
                    }
                } else {
                    next.removeAll { $0 == folder }
                }
                settings.wrappedValue.lessonPlanFolderIDs = next
            }
        )
    }
}
