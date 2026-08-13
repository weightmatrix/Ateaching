import Foundation

@MainActor
enum ScreenCastDiagnostic40 {
    private static var preparedLog = false
    private static var logURL: URL?

    static func record(
        _ message: String,
        instanceID: String? = nil,
        mode: String? = nil
    ) {
        var fields: [String] = []
        if let instanceID { fields.append("实例=\(instanceID)") }
        if let mode { fields.append("模式=\(mode)") }
        fields.append(message)
        let tagged = "【诊断·40】\(fields.joined(separator: " "))"
        print(tagged)
        prepareLogIfNeeded()
        append(tagged)
    }

    private static func prepareLogIfNeeded() {
        guard !preparedLog else { return }
        preparedLog = true
        let manager = FileManager.default
        guard let applicationSupport = manager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        let folder = applicationSupport
            .appendingPathComponent("ATeaching", isDirectory: true)
            .appendingPathComponent("诊断", isDirectory: true)
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            removeRetiredDiagnosticFiles(in: folder, manager: manager)
            let url = folder.appendingPathComponent("投屏诊断·40.MD", isDirectory: false)
            let header = "# 投屏诊断·40\n\n"
                + "- 建立时间：\(timestamp())\n"
                + "- 目标：追踪确认四位数字后投屏状态短暂出现又回到未连接的完整状态链。\n"
                + "- 记录范围：页面动作、服务实例、模式切换、Listener 状态及所有 stopAll 调用来源。\n"
                + "- 固定物理位置：`\(url.path)`\n\n"
            try header.write(to: url, atomically: true, encoding: .utf8)
            logURL = url
            print("【诊断·40】诊断记录：\(url.path)")
        } catch {
            print("【诊断·40】无法建立诊断记录：\(error.localizedDescription)")
        }
    }

    private static func removeRetiredDiagnosticFiles(in folder: URL, manager: FileManager) {
        let retainedNames: Set<String> = ["ATeaching诊断记录.MD", "投屏诊断·40.MD", "NodeMarkdown新管线诊断·41.MD"]
        guard let files = try? manager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for file in files where retainedNames.contains(file.lastPathComponent) == false {
            try? manager.removeItem(at: file)
        }
    }

    private static func append(_ line: String) {
        guard let logURL,
              let data = ("- `\(timestamp())` \(line)\n").data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
