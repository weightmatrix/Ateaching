import SwiftUI

struct TeachingStudentBackupSheet: View {
    @Environment(\.dismiss) private var dismiss

    let students: [TeachingStudentItem]
    let onConfirm: ([UUID]) -> Void

    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var showConfirmAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Button("全选") {
                        selectedStudentIDs = Set(students.map(\.id))
                    }
                    .appGlassButtonStyle()
                    .disabled(students.isEmpty)

                    Button("清空") {
                        selectedStudentIDs.removeAll()
                    }
                    .appGlassButtonStyle()
                    .disabled(selectedStudentIDs.isEmpty)

                    Spacer()
                    Text("已选 \(selectedStudentIDs.count) / \(students.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if students.isEmpty {
                    ContentUnavailableView("暂无学生", systemImage: "person.2")
                } else {
                    List(students) { student in
                        HStack(spacing: 10) {
                            Image(systemName: selectedStudentIDs.contains(student.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedStudentIDs.contains(student.id) ? .accent : .secondary)
                            Image(systemName: student.iconName)
                                .foregroundStyle(student.color.value)
                            Text(student.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggle(student.id)
                        }
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 320)
                }
            }
            .padding(16)
            .navigationTitle("备份学生")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("备份") {
                        showConfirmAlert = true
                    }
                    .disabled(selectedStudentIDs.isEmpty)
                }
            }
            .onAppear {
                selectedStudentIDs = Set(students.map(\.id))
            }
            .alert("确认备份选中学生？", isPresented: $showConfirmAlert) {
                Button("取消", role: .cancel) {}
                Button("确认备份", role: .destructive) {
                    onConfirm(Array(selectedStudentIDs))
                    dismiss()
                }
            } message: {
                Text("选中的学生文件夹会迁移到“系统/学生备份”，并从当前学生列表移除。")
            }
        }
        .frame(minWidth: 520, minHeight: 520)
    }

    private func toggle(_ id: UUID) {
        if selectedStudentIDs.contains(id) {
            selectedStudentIDs.remove(id)
        } else {
            selectedStudentIDs.insert(id)
        }
    }
}
