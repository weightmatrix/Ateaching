import SwiftUI

struct TeachingLessonChecklistPickingTarget: Identifiable, Hashable {
    let id: String
}

struct TeachingLessonChecklistPickerView: View {
    let lessonCompletionFiles: [URL]
    let onPick: ([ChecklistTemplateRow], String) -> Void
    let onClose: () -> Void

    @State private var courseChecklistPickingTarget: TeachingLessonChecklistPickingTarget?

    var body: some View {
        NavigationStack {
            Group {
                if lessonCompletionFiles.isEmpty {
                    ContentUnavailableView(
                        "暂无可用完成清单",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("请先执行上课准备，生成“教案_*_完成情况_*”文件。")
                    )
                } else {
                    List(lessonCompletionFiles, id: \.path) { fileURL in
                        Button {
                            courseChecklistPickingTarget = TeachingLessonChecklistPickingTarget(id: fileURL.path)
                        } label: {
                            Text(fileURL.deletingPathExtension().lastPathComponent)
                                .font(.body.monospaced())
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(minWidth: 520, minHeight: 320)
            .navigationTitle("教案完成清单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        onClose()
                    }
                }
            }
        }
        .onAppear {
            if lessonCompletionFiles.count == 1, let onlyFile = lessonCompletionFiles.first {
                courseChecklistPickingTarget = TeachingLessonChecklistPickingTarget(id: onlyFile.path)
            }
        }
        .sheet(item: $courseChecklistPickingTarget) { target in
            NavigationStack {
                ChecklistDocumentEditorView(
                    fileURL: URL(fileURLWithPath: target.id),
                    mode: .coursePicking,
                    onCoursePick: { rows in
                        onPick(rows, target.id)
                    }
                )
                .frame(minWidth: 720, minHeight: 520)
            }
        }
    }
}
