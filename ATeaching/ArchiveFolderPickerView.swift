import SwiftUI
import Combine

// MARK: - 档案目标文件夹选择器 - v1 - 为移动和组成文件夹提供统一的档案内目录选择
struct ArchiveFolderPickerView: View {
    let rootURL: URL
    let initialURL: URL
    let excludedURLs: Set<URL>
    let onCancel: () -> Void
    let onChoose: (URL) -> Void

    @State private var currentURL: URL
    @State private var folders: [ArchiveEntry] = []
    @State private var statusMessage = ""

    init(
        rootURL: URL,
        initialURL: URL,
        excludedURLs: Set<URL> = [],
        onCancel: @escaping () -> Void,
        onChoose: @escaping (URL) -> Void
    ) {
        self.rootURL = rootURL
        self.initialURL = initialURL
        self.excludedURLs = excludedURLs
        self.onCancel = onCancel
        self.onChoose = onChoose
        _currentURL = State(initialValue: initialURL)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button {
                        goUp()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .appGlassButtonStyle()
                    .disabled(!canGoUp)

                    Text(title)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(14)

                if folders.isEmpty {
                    ContentUnavailableView("没有子文件夹", systemImage: "folder")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(folders) { folder in
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(appHighlightBlue)
                            Text(folder.name)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            currentURL = folder.url
                            loadFolders()
                        }
                    }
                    .listStyle(.plain)
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("选择目标文件夹")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("移动到这里") {
                        onChoose(currentURL)
                    }
                    .disabled(excludedURLs.contains(currentURL.standardizedFileURL))
                }
            }
        }
        .frame(minWidth: 460, minHeight: 420)
        .task {
            loadFolders()
        }
    }

    private var canGoUp: Bool {
        currentURL.standardizedFileURL.path != rootURL.standardizedFileURL.path
    }

    private var title: String {
        let rootPath = rootURL.standardizedFileURL.path
        let currentPath = currentURL.standardizedFileURL.path
        guard currentPath.hasPrefix(rootPath) else { return "档案" }
        let suffix = String(currentPath.dropFirst(rootPath.count))
        let pieces = suffix.split(separator: "/").map(String.init)
        return pieces.isEmpty ? "档案" : "档案 / " + pieces.joined(separator: " / ")
    }

    private func goUp() {
        guard canGoUp else { return }
        currentURL = currentURL.deletingLastPathComponent()
        loadFolders()
    }

    private func loadFolders() {
        do {
            folders = try ArchiveStorage.loadEntries(in: currentURL)
                .filter { entry in
                    guard entry.isDirectory else { return false }
                    return !excludedURLs.contains { excluded in
                        entry.url.standardizedFileURL.path == excluded.path
                            || entry.url.standardizedFileURL.path.hasPrefix(excluded.path + "/")
                    }
                }
            statusMessage = ""
        } catch {
            folders = []
            statusMessage = error.localizedDescription
        }
    }
}

// MARK: - 档案目录监听器 - v1 - 监听访达改动并请求档案页刷新
final class ArchiveDirectoryWatcher: ObservableObject {
    private var descriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private var pendingChangeWorkItem: DispatchWorkItem?
    private var watchedPath = ""
    var onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func watch(_ directoryURL: URL?) {
        let path = directoryURL?.standardizedFileURL.path ?? ""
        guard path != watchedPath else { return }
        stop()
        watchedPath = path
        guard !path.isEmpty else { return }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        descriptor = fd

        let eventMask: DispatchSource.FileSystemEvent = [.write, .delete, .rename, .extend, .attrib, .link, .revoke]
        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: eventMask,
            queue: DispatchQueue.main
        )
        newSource.setEventHandler { [weak self] in
            guard let self else { return }
            self.pendingChangeWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.pendingChangeWorkItem = nil
                self?.onChange()
            }
            self.pendingChangeWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
        }
        newSource.setCancelHandler { [fd] in
            close(fd)
        }
        source = newSource
        newSource.resume()
    }

    func stop() {
        pendingChangeWorkItem?.cancel()
        pendingChangeWorkItem = nil
        source?.cancel()
        source = nil
        descriptor = -1
    }
}
