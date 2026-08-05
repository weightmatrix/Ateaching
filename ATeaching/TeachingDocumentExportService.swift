import Foundation
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct TeachingDocumentExportDescriptor {
    let displayName: String
    let fileExtension: String
    let contentType: UTType
    var suggestedFileNamePrefix: String = ""
    var suggestedFileNameSuffix: String = ""
}

struct TeachingDocumentExportFile {
    let fileName: String
    let data: Data
}

enum TeachingDocumentExportService {
    #if os(macOS)
    private static var activeSharingPicker: NSSharingServicePicker?
    private static var activeSharedFileURL: URL?
    #endif

    @MainActor
    static func exportToWeChat(
        sourceFileURL: URL,
        descriptor: TeachingDocumentExportDescriptor,
        dataProvider: () throws -> Data
    ) throws {
        let exportURL = try makeTemporaryFile(
            sourceFileURL: sourceFileURL,
            descriptor: descriptor,
            dataProvider: dataProvider
        )
        try presentSystemShareSheet(for: exportURL)
    }

    @MainActor
    private static func presentSystemShareSheet(for exportURL: URL) throws {
        #if os(macOS)
        guard let anchorView = systemShareAnchorView() else {
            throw NSError(
                domain: "TeachingDocumentExportService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "无法打开系统分享菜单。"]
            )
        }
        activeSharedFileURL = exportURL
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let picker = NSSharingServicePicker(items: [exportURL])
            activeSharingPicker = picker
            let anchorRect = systemShareAnchorRect(in: anchorView)
            picker.show(relativeTo: anchorRect, of: anchorView, preferredEdge: .maxY)
        }
        #elseif os(iOS)
        guard
            let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
            let rootViewController = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            throw CocoaError(.featureUnsupported)
        }
        let controller = UIActivityViewController(activityItems: [exportURL], applicationActivities: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let presenter = topViewController(from: rootViewController)
            if let popover = controller.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(
                    x: presenter.view.bounds.midX,
                    y: presenter.view.bounds.midY,
                    width: 1,
                    height: 1
                )
                popover.permittedArrowDirections = []
            }
            presenter.present(controller, animated: true)
        }
        #else
        throw CocoaError(.featureUnsupported)
        #endif
    }

    #if os(iOS)
    @MainActor
    private static func topViewController(from root: UIViewController) -> UIViewController {
        if let presented = root.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigation = root as? UINavigationController,
           let visible = navigation.visibleViewController {
            return topViewController(from: visible)
        }
        if let tabs = root as? UITabBarController,
           let selected = tabs.selectedViewController {
            return topViewController(from: selected)
        }
        return root
    }
    #endif

    #if os(macOS)
    @MainActor
    private static func systemShareAnchorView() -> NSView? {
        let candidateWindows = [NSApp.keyWindow, NSApp.mainWindow] + NSApp.orderedWindows.map(Optional.some)
        return candidateWindows.compactMap { window -> NSView? in
            guard let window, window.isVisible, !window.isMiniaturized else { return nil }
            return window.contentView
        }.first
    }

    @MainActor
    private static func systemShareAnchorRect(in view: NSView) -> NSRect {
        let bounds = view.bounds
        let centerX = bounds.midX
        let centerY = bounds.midY
        return NSRect(x: centerX, y: centerY, width: 1, height: 1)
    }
    #endif

    @MainActor
    static func saveToFile(
        sourceFileURL: URL,
        descriptor: TeachingDocumentExportDescriptor,
        dataProvider: () throws -> Data
    ) throws {
        let exportURL = try makeTemporaryFile(
            sourceFileURL: sourceFileURL,
            descriptor: descriptor,
            dataProvider: dataProvider
        )
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = descriptor.suggestedFileNamePrefix
            + sourceFileURL.deletingPathExtension().lastPathComponent
            + descriptor.suggestedFileNameSuffix
            + ".\(descriptor.fileExtension)"
        panel.allowedContentTypes = [descriptor.contentType]
        if panel.runModal() == .OK, let destination = panel.url {
            _ = try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: exportURL, to: destination)
        }
        #else
        throw CocoaError(.featureUnsupported)
        #endif
    }

    /// 多文件导出只选择一次目录；全部数据生成成功后才开始写盘，避免渲染中途留下半套文件。
    @MainActor
    static func saveFilesToDirectory(
        sourceFileURL: URL,
        filesProvider: () throws -> [TeachingDocumentExportFile]
    ) throws -> Int {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "选择PDF导出文件夹"
        panel.prompt = "导出"
        panel.message = "每个H1将导出为一个独立PDF文件。"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = sourceFileURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let destinationDirectory = panel.url else {
            return 0
        }

        let files = try filesProvider()
        guard !files.isEmpty else { return 0 }
        let didAccess = destinationDirectory.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                destinationDirectory.stopAccessingSecurityScopedResource()
            }
        }

        for file in files {
            let safeName = URL(fileURLWithPath: file.fileName).lastPathComponent
            guard !safeName.isEmpty, safeName == file.fileName else {
                throw NSError(
                    domain: "TeachingDocumentExportService",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "导出文件名无效：\(file.fileName)"]
                )
            }
            let destination = destinationDirectory.appendingPathComponent(safeName, isDirectory: false)
            try file.data.write(to: destination, options: .atomic)
        }
        return files.count
        #else
        throw CocoaError(.featureUnsupported)
        #endif
    }

    @MainActor
    static func makeTemporaryFile(
        sourceFileURL: URL,
        descriptor: TeachingDocumentExportDescriptor,
        dataProvider: () throws -> Data
    ) throws -> URL {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                descriptor.suggestedFileNamePrefix
                    + sourceFileURL.deletingPathExtension().lastPathComponent
                    + descriptor.suggestedFileNameSuffix
                    + "-导出.\(descriptor.fileExtension)"
            )
        let data = try dataProvider()
        try data.write(to: temporaryURL, options: .atomic)
        return temporaryURL
    }
}
