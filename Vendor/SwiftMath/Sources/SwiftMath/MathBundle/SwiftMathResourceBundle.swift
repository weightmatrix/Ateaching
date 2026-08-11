import Foundation

/// Finds math font resources without SwiftPM's generated `Bundle.module` accessor.
/// That accessor terminates the process when an incremental app build omits its wrapper bundle.
enum SwiftMathResourceBundle {
    private final class BundleToken {}

    static let mathFonts: Bundle = {
        let markerBundle = Bundle(for: BundleToken.self)
        let startingURLs = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            markerBundle.resourceURL,
            markerBundle.bundleURL
        ].compactMap { $0 }

        var searched = Set<URL>()
        for start in startingURLs {
            var directory = start.standardizedFileURL
            for _ in 0..<4 {
                if searched.insert(directory).inserted,
                   let bundle = locateMathFontsBundle(in: directory) {
                    return bundle
                }
                let parent = directory.deletingLastPathComponent()
                guard parent.path != directory.path else { break }
                directory = parent
            }
        }

        fatalError("SwiftMath mathFonts.bundle is missing from the application resources")
    }()

    private static func locateMathFontsBundle(in directory: URL) -> Bundle? {
        let directURL = directory.appendingPathComponent("mathFonts.bundle", isDirectory: true)
        if let bundle = Bundle(url: directURL) {
            return bundle
        }

        let wrapperURL = directory.appendingPathComponent("SwiftMath_SwiftMath.bundle", isDirectory: true)
        guard let wrapper = Bundle(url: wrapperURL),
              let nestedURL = wrapper.url(forResource: "mathFonts", withExtension: "bundle") else {
            return nil
        }
        return Bundle(url: nestedURL)
    }
}
