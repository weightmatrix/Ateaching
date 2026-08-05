import SwiftUI

// MARK: - 回收站页面 - v1 - 展示回收项目并提供恢复清除操作
struct RecycleBinView: View {
    // MARK: - 回收站加载结果 - v1 - 统一处理加载成功与失败状态
    private enum LoadResult {
        case success([RecycleBinEntry])
        case failure(String)
    }

    let onChanged: () -> Void
    var showNavigationChrome: Bool = true
    var refreshTrigger: Int = 0
    var clearAllTrigger: Int = 0

    @State private var entries: [RecycleBinEntry] = []
    @State private var isLoading = false
    @State private var statusMessage = ""
    @State private var showClearAllConfirm = false

    var body: some View {
        Group {
            if showNavigationChrome {
                content
                    .navigationTitle("回收站")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button(role: .destructive) {
                                showClearAllConfirm = true
                            } label: {
                                Image(systemName: "trash.slash")
                            }
                            .appGlassButtonStyle(.danger)
                            .disabled(entries.isEmpty)
                            .help("全部清除")
                        }
                    }
            } else {
                content
            }
        }
        .task {
            if entries.isEmpty, !isLoading {
                loadEntries()
            }
        }
        .onChange(of: refreshTrigger) { _, _ in
            loadEntries()
        }
        .onChange(of: clearAllTrigger) { _, _ in
            showClearAllConfirm = true
        }
        .alert("确认全部清除", isPresented: $showClearAllConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                clearAll()
            }
        } message: {
            Text("将彻底删除回收站全部内容，并清空回收站CSV记录。")
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 10)
            }

            if entries.isEmpty, !isLoading {
                ContentUnavailableView("回收站为空", systemImage: "trash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                            .foregroundStyle(entry.isDirectory ? appHighlightBlue : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.displayName)
                                .lineLimit(1)
                            Text(entry.originalRelativePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contextMenu {
                        Button("恢复") {
                            restore(entry)
                        }
                        Button("清除", role: .destructive) {
                            clear(entry)
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
                    .padding(.bottom, 10)
            }
        }
    }

    private func loadEntries() {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = ""

        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> LoadResult in
                do {
                    return .success(try RecycleBinManager.loadEntries())
                } catch {
                    return .failure(error.localizedDescription)
                }
            }.value

            isLoading = false
            switch result {
            case .success(let loadedEntries):
                entries = loadedEntries
                onChanged()
            case .failure(let message):
                statusMessage = message
            }
        }
    }

    private func restore(_ entry: RecycleBinEntry) {
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try RecycleBinManager.restore(entry)
                }.value
                loadEntries()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func clear(_ entry: RecycleBinEntry) {
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try RecycleBinManager.permanentlyDelete(entry)
                }.value
                loadEntries()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func clearAll() {
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try RecycleBinManager.clearAll()
                }.value
                loadEntries()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    RecycleBinView(onChanged: {})
}
