import SwiftUI
import UniformTypeIdentifiers

struct TeachingStudentsSubpageView: View {
    @Binding var students: [TeachingStudentItem]
    @Binding var draggingStudentID: UUID?
    let isRunningStudentBackup: Bool
    let showProfileOverrideAction: Bool
    let onAdd: () -> Void
    let onBackup: () -> Void
    let onSettings: () -> Void
    let onRefresh: () -> Void
    let onUpdateIcon: (UUID, String) -> Void
    let onUpdateColor: (UUID, TeachingStudentColor) -> Void
    let onConfigureProfile: (TeachingStudentItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("学生")
                .font(.headline)

            HStack(spacing: 10) {
                Button(action: onAdd) {
                    Label("添加", systemImage: "person.badge.plus")
                }
                .appGlassButtonStyle(.prominent)

                Button(action: onBackup) {
                    Label("备份", systemImage: "externaldrive.badge.icloud")
                }
                .appGlassButtonStyle()
                .disabled(isRunningStudentBackup || students.isEmpty)

                Button(action: onSettings) {
                    Label("设置", systemImage: "slider.horizontal.3")
                }
                .appGlassButtonStyle()

                Button(action: onRefresh) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .appGlassButtonStyle()

                Spacer()
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(students) { student in
                        studentRow(student)
                            .onDrag {
                                draggingStudentID = student.id
                                return NSItemProvider(object: student.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: TeachingStudentDropDelegate(
                                    target: student,
                                    students: $students,
                                    draggingStudentID: $draggingStudentID
                                )
                            )
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func studentRow(_ student: TeachingStudentItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: student.iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(student.color.value)
                .frame(width: 26, height: 26)
            Text(student.name)
                .font(.system(size: 15, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
        )
        .contextMenu {
            Menu("更换图标") {
                ForEach(TeachingStudentItem.supportedIcons, id: \.self) { iconName in
                    Button {
                        onUpdateIcon(student.id, iconName)
                    } label: {
                        Label(TeachingStudentItem.displayName(forIcon: iconName), systemImage: iconName)
                    }
                }
            }

            Menu("更换颜色") {
                ForEach(TeachingStudentColor.allCases) { color in
                    Button {
                        onUpdateColor(student.id, color)
                    } label: {
                        HStack {
                            Circle()
                                .fill(color.value)
                                .frame(width: 10, height: 10)
                            Text(color.displayName)
                        }
                    }
                }
            }

            if showProfileOverrideAction {
                Button("初始化/配置") {
                    onConfigureProfile(student)
                }
            }
        }
    }
}

private struct TeachingStudentDropDelegate: DropDelegate {
    let target: TeachingStudentItem
    @Binding var students: [TeachingStudentItem]
    @Binding var draggingStudentID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggingStudentID,
              let fromIndex = students.firstIndex(where: { $0.id == draggingStudentID }),
              let toIndex = students.firstIndex(of: target),
              fromIndex != toIndex else {
            return
        }
        withAnimation(.easeOut(duration: 0.12)) {
            let moved = students.remove(at: fromIndex)
            students.insert(moved, at: toIndex)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingStudentID = nil
        return true
    }
}
