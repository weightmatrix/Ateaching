import SwiftUI

// MARK: - 新建文件弹出页 - v1 - 提供文件类型切换与文件名输入创建入口
struct ArchiveCreateFileSheetView: View {
    struct CreateRequest {
        let fileName: String
        let type: ArchiveStorage.ArchiveNewFileType
        let templateFileURL: URL?
    }

    fileprivate struct TemplateOption: Identifiable, Hashable {
        let id: URL
        let fileURL: URL
        let title: String
        let templateID: String
    }

    @State private var selectedType: ArchiveStorage.ArchiveNewFileType = .singleListTable
    @State private var fileName = ""
    @State private var templateOptions: [TemplateOption] = []
    @State private var selectedTemplateURL: URL?

    let onCancel: () -> Void
    let onCreate: (_ request: CreateRequest) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("新建文件")
                .font(.headline)

            typeSelector
                .frame(maxWidth: .infinity, alignment: .center)

            if requiresTemplateSelection {
                templateSelector
            }

            TextField("文件名", text: $fileName)
                .textFieldStyle(.roundedBorder)

            if requiresTemplateSelection {
                ArchiveAutoFillCreationSectionView(
                    selectedTemplateURL: selectedTemplateURL,
                    templateOptions: templateOptions,
                    fileName: $fileName
                )
            }

            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .appGlassButtonStyle()
                .help("取消")

                Button {
                    onCreate(
                        CreateRequest(
                            fileName: fileName,
                            type: selectedType,
                            templateFileURL: selectedTemplateURL
                        )
                    )
                } label: {
                    Image(systemName: "checkmark")
                }
                .appGlassButtonStyle(.prominent)
                .disabled(!canCreate)
                .help("创建")
            }
        }
        .padding(16)
        .frame(width: 460)
        .task {
            reloadTemplateOptions()
        }
        .onChange(of: selectedType) { _, value in
            reloadTemplateOptions()
            if !value.requiresTemplateSelection {
                selectedTemplateURL = nil
            }
        }
    }

    private var typeSelector: some View {
        HStack(spacing: 8) {
            ForEach(ArchiveStorage.ArchiveNewFileType.allCases, id: \.self) { type in
                Button {
                    selectedType = type
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: type.iconName)
                        Text(type.displayName)
                            .lineLimit(1)
                    }
                }
                .appGlassButtonStyle(selectedType == type ? .prominent : .regular)
            }
        }
    }

    private var templateSelector: some View {
        HStack {
            Text("模板")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("模板", selection: Binding(
                get: { selectedTemplateURL },
                set: { selectedTemplateURL = $0 }
            )) {
                ForEach(templateOptions) { option in
                    Text(option.title).tag(Optional(option.fileURL))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var canCreate: Bool {
        let validName = !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if requiresTemplateSelection {
            return validName && selectedTemplateURL != nil
        }
        return validName
    }

    private var requiresTemplateSelection: Bool {
        selectedType.requiresTemplateSelection
    }

    private func reloadTemplateOptions() {
        guard let category = selectedType.templateCategory else {
            templateOptions = []
            selectedTemplateURL = nil
            return
        }
        guard let entries = try? ArchiveStorage.loadTemplateEntries(category: category) else {
            templateOptions = []
            selectedTemplateURL = nil
            return
        }
        let options: [TemplateOption] = entries.compactMap { entry in
            switch category {
            case .singleList:
                guard let (_, meta) = try? ArchiveStorage.readSingleListTemplate(fileURL: entry.url) else { return nil }
                return TemplateOption(id: entry.url, fileURL: entry.url, title: meta.title, templateID: meta.id)
            case .checklist:
                guard let (_, meta) = try? ArchiveStorage.readChecklistTemplate(fileURL: entry.url) else { return nil }
                return TemplateOption(id: entry.url, fileURL: entry.url, title: meta.title, templateID: meta.id)
            }
        }
        templateOptions = options
        if selectedTemplateURL == nil || !templateOptions.contains(where: { $0.fileURL == selectedTemplateURL }) {
            selectedTemplateURL = templateOptions.first?.fileURL
        }
    }

}

private extension ArchiveStorage.ArchiveNewFileType {
    var requiresTemplateSelection: Bool {
        switch self {
        case .singleListTable, .autoFill, .checklist:
            return true
        case .markdown:
            return false
        }
    }

    var templateCategory: TemplateCategory? {
        switch self {
        case .singleListTable, .autoFill:
            return .singleList
        case .checklist:
            return .checklist
        case .markdown:
            return nil
        }
    }
}

// MARK: - 自动填写新建区块 - v1 - 模板名日期时分快捷输入
private struct ArchiveAutoFillCreationSectionView: View {
    let selectedTemplateURL: URL?
    let templateOptions: [ArchiveCreateFileSheetView.TemplateOption]
    @Binding var fileName: String

    var body: some View {
        HStack(spacing: 8) {
            Button {
                guard let selected = templateOptions.first(where: { $0.fileURL == selectedTemplateURL }) else { return }
                fileName += "\(selected.title)_"
            } label: {
                Image(systemName: "doc.text")
            }
            .appGlassButtonStyle()
            .help("模板名")

            Button {
                fileName += formattedDateString()
            } label: {
                Image(systemName: "calendar")
            }
            .appGlassButtonStyle()
            .help("日期")

            Button {
                fileName += formattedTimeString()
            } label: {
                Image(systemName: "clock")
            }
            .appGlassButtonStyle()
            .help("时分")
        }
    }

    private func formattedDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        return formatter.string(from: Date())
    }

    private func formattedTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmm"
        return formatter.string(from: Date())
    }
}
