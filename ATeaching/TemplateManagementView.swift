import SwiftUI

// MARK: - 模板编辑路由 - v1 - 用于模板列表跳转到对应编辑页
struct TemplateEditorRoute: Hashable, Identifiable {
    let fileURL: URL
    let category: TemplateCategory

    var id: String { fileURL.path + category.rawValue }
}

// MARK: - 模板管理页 - v3 - 模板入口页面，负责分类、列表、多选删除与新建
struct TemplateManagementView: View {
    @State private var selectedCategory: TemplateCategory
    @State private var entries: [ArchiveEntry] = []
    @State private var isLoading = false
    @State private var statusMessage = ""

    @State private var isMultiSelecting = false
    @State private var selectedEntryIDs: Set<URL> = []

    @State private var showCreateAlert = false
    @State private var newTemplateName = ""
    @State private var createdRoute: TemplateEditorRoute?
    @State private var showCreatedEditor = false
    private let allowCategorySwitch: Bool
    private let navigationTitle: String
    private let checklistMetaTypeOverride: String?
    private let showTopActionToolbar: Bool
    private let externalToggleMultiSelectToken: Int
    private let externalCreateToken: Int

    init(
        initialCategory: TemplateCategory = .singleList,
        allowCategorySwitch: Bool = true,
        navigationTitle: String = "模板",
        checklistMetaTypeOverride: String? = nil,
        showTopActionToolbar: Bool = true,
        externalToggleMultiSelectToken: Int = 0,
        externalCreateToken: Int = 0
    ) {
        _selectedCategory = State(initialValue: initialCategory)
        self.allowCategorySwitch = allowCategorySwitch
        self.navigationTitle = navigationTitle
        self.checklistMetaTypeOverride = checklistMetaTypeOverride
        self.showTopActionToolbar = showTopActionToolbar
        self.externalToggleMultiSelectToken = externalToggleMultiSelectToken
        self.externalCreateToken = externalCreateToken
    }

    var body: some View {
        VStack(spacing: 0) {
            selectorBar

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 8)
            }

            if entries.isEmpty, !isLoading {
                ContentUnavailableView("暂无模板", systemImage: "doc.text")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    if isMultiSelecting {
                        Button {
                            toggleSelect(entry.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedEntryIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedEntryIDs.contains(entry.id) ? .blue : .secondary)
                                Image(systemName: entry.iconName)
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(entry.iconColor)
                                Text(entry.name)
                                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    } else {
                        let route = TemplateEditorRoute(fileURL: entry.url, category: selectedCategory)
                        NavigationLink(destination: editorView(for: route)) {
                            HStack(spacing: 10) {
                                Image(systemName: entry.iconName)
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(entry.iconColor)
                                Text(entry.name)
                                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.plain)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .navigationTitle(navigationTitle)
        .navigationDestination(isPresented: $showCreatedEditor) {
            if let route = createdRoute {
                editorView(for: route)
            } else {
                EmptyView()
            }
        }
        .toolbar {
            if showTopActionToolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        toggleMultiSelect()
                    } label: {
                        Image(systemName: isMultiSelecting ? "checkmark.circle" : "checklist")
                    }
                    .appGlassButtonStyle()
                    .help(isMultiSelecting ? "完成" : "多选")

                    Button {
                        openCreateTemplatePrompt()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .appGlassButtonStyle()
                    .help("新建")
                }
            }
        }
        .task {
            loadTemplates()
        }
        .onChange(of: selectedCategory) { _, _ in
            selectedEntryIDs.removeAll()
            isMultiSelecting = false
            loadTemplates()
        }
        .onChange(of: showCreatedEditor) { _, isPresented in
            if !isPresented {
                createdRoute = nil
            }
        }
        .onChange(of: externalToggleMultiSelectToken) { _, _ in
            guard !showTopActionToolbar else { return }
            toggleMultiSelect()
        }
        .onChange(of: externalCreateToken) { _, _ in
            guard !showTopActionToolbar else { return }
            openCreateTemplatePrompt()
        }
        .alert("新建模板", isPresented: $showCreateAlert) {
            TextField("模板名称", text: $newTemplateName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                createTemplate()
            }
        } message: {
            Text("将在“\(selectedCategory.displayName)”目录创建CSV模板。")
        }
        .safeAreaInset(edge: .bottom) {
            if isMultiSelecting {
                HStack {
                    Text("已选 \(selectedEntryIDs.count) 项")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        deleteSelected()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .appGlassButtonStyle(.danger)
                    .disabled(selectedEntryIDs.isEmpty)
                    .help("删除")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
    }

    private var selectorBar: some View {
        HStack {
            Spacer()
            if allowCategorySwitch {
                Picker("模板类型", selection: $selectedCategory) {
                    ForEach(TemplateCategory.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            } else {
                Text(selectedCategory.displayName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
                }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func editorView(for route: TemplateEditorRoute) -> some View {
        switch route.category {
        case .singleList:
            SingleListTemplateEditorView(fileURL: route.fileURL)
        case .checklist:
            ChecklistTemplateEditorView(fileURL: route.fileURL)
        }
    }

    private func loadTemplates() {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = ""
        let category = selectedCategory
        Task {
            do {
                entries = try ArchiveStorage.loadTemplateEntries(category: category)
            } catch {
                statusMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func createTemplate() {
        let name = newTemplateName
        let category = selectedCategory
        let checklistMetaTypeOverride = checklistMetaTypeOverride
        Task {
            do {
                let url = try ArchiveStorage.createTemplate(
                    named: name,
                    category: category,
                    checklistMetaTypeOverride: checklistMetaTypeOverride
                )
                createdRoute = TemplateEditorRoute(fileURL: url, category: category)
                showCreatedEditor = true
                loadTemplates()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func toggleMultiSelect() {
        isMultiSelecting.toggle()
        if !isMultiSelecting {
            selectedEntryIDs.removeAll()
        }
    }

    private func openCreateTemplatePrompt() {
        newTemplateName = ""
        showCreateAlert = true
    }

    private func toggleSelect(_ id: URL) {
        if selectedEntryIDs.contains(id) {
            selectedEntryIDs.remove(id)
        } else {
            selectedEntryIDs.insert(id)
        }
    }

    private func deleteSelected() {
        let targets = selectedEntryIDs
        guard !targets.isEmpty else { return }
        Task {
            do {
                for url in targets {
                    try ArchiveStorage.deleteItem(at: url)
                }
                selectedEntryIDs.removeAll()
                isMultiSelecting = false
                loadTemplates()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}
