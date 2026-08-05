import SwiftUI

// MARK: - 自动填写列表页 - v1 - 展示系统/自动填写下的所有 autosinglelist 文件
struct AutoFillManagementView: View {
    var showNavigationChrome: Bool = true
    var refreshTrigger: Int = 0

    @State private var entries: [ArchiveEntry] = []
    @State private var isLoading = false
    @State private var statusMessage = ""

    var body: some View {
        Group {
            if showNavigationChrome {
                content
                    .navigationTitle("自动填写")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                loadEntries()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .appGlassButtonStyle()
                            .help("刷新")
                        }
                    }
            } else {
                content
            }
        }
        .task {
            loadEntries()
        }
        .onChange(of: refreshTrigger) { _, _ in
            loadEntries()
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 8)
            }

            if entries.isEmpty, !isLoading {
                ContentUnavailableView("暂无自动填写", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    NavigationLink(destination: AutoFillDocumentEditorView(fileURL: entry.url)) {
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
    }

    private func loadEntries() {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = ""
        Task {
            defer { isLoading = false }
            do {
                entries = try ArchiveStorage.loadAutoFillEntries()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}
