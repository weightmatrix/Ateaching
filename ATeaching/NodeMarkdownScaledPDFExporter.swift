// PIPELINE MARKER: NodeMarkdown legacy pipeline (WebKit/HTML PDF export fallback).
import Foundation
import WebKit
import PDFKit

enum NodeMarkdownScaledPDFExporter {
    static let defaultScale: Double = 0.4

    private static let pageLoadTimeout: TimeInterval = 120
    private static let imageLoadTimeout: TimeInterval = 60
    private static let pdfRenderTimeout: TimeInterval = 120

    static func export(
        sourceFileURL: URL,
        destinationURL: URL,
        scale: Double = defaultScale
    ) throws {
        let payload = try NodeMarkdownFileManager.read(fileURL: sourceFileURL)
        let style = NodeMarkdownSettingsStore.loadDocumentStyle() ?? NodeMarkdownDocumentStyle()
        let settingsFromDedicated = TeachingPDFSettingsStore.load()
        let settingsFromSnapshot = (try? TeachingStudentSettingsStore.loadStudentSystemSettings().pdfExportSettings.normalized())
            ?? TeachingPDFExportSettings()
        let settings = settingsFromDedicated == TeachingPDFExportSettings() ? settingsFromSnapshot : settingsFromDedicated
        let rowsHTML = NodeMarkdownHTMLBuilder.buildRows(
            document: payload.0,
            style: style,
            exportScheme: style.preferredScheme.resolvedExportScheme
        )
        let html = NodeMarkdownHTMLBuilder.documentHTML(
            initialRowsHTML: rowsHTML,
            backgroundHex: NodeMarkdownHTMLBuilder.exportBackgroundHex(for: style),
            baseURL: sourceFileURL.deletingLastPathComponent()
        )
        let data = try renderPDFDataOnMain(
            html: html,
            baseURL: sourceFileURL.deletingLastPathComponent(),
            settings: settings,
            scale: scale
        )
        try data.write(to: destinationURL, options: .atomic)
    }

    static func renderData(
        sourceFileURL: URL,
        document: NodeMarkdownDocument,
        style: NodeMarkdownDocumentStyle,
        baseURL: URL? = nil,
        scale: Double = defaultScale
    ) throws -> Data {
        let settingsFromDedicated = TeachingPDFSettingsStore.load()
        let settingsFromSnapshot = (try? TeachingStudentSettingsStore.loadStudentSystemSettings().pdfExportSettings.normalized())
            ?? TeachingPDFExportSettings()
        let settings = settingsFromDedicated == TeachingPDFExportSettings() ? settingsFromSnapshot : settingsFromDedicated
        let rowsHTML = NodeMarkdownHTMLBuilder.buildRows(
            document: document,
            style: style,
            exportScheme: style.preferredScheme.resolvedExportScheme
        )
        let html = NodeMarkdownHTMLBuilder.documentHTML(
            initialRowsHTML: rowsHTML,
            backgroundHex: NodeMarkdownHTMLBuilder.exportBackgroundHex(for: style),
            baseURL: baseURL ?? sourceFileURL.deletingLastPathComponent()
        )
        return try renderPDFDataOnMain(
            html: html,
            baseURL: baseURL ?? sourceFileURL.deletingLastPathComponent(),
            settings: settings,
            scale: scale
        )
    }

    private static func renderPDFDataOnMain(
        html: String,
        baseURL: URL,
        settings: TeachingPDFExportSettings,
        scale: Double
    ) throws -> Data {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated {
                try renderPDFData(
                    html: html,
                    baseURL: baseURL,
                    settings: settings,
                    scale: scale
                )
            }
        }

        var result: Result<Data, Error>?
        DispatchQueue.main.sync {
            result = Result {
                try MainActor.assumeIsolated {
                    try renderPDFData(
                        html: html,
                        baseURL: baseURL,
                        settings: settings,
                        scale: scale
                    )
                }
            }
        }
        guard let result else {
            throw NSError(
                domain: "NodeMarkdownScaledPDFExporter",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "主线程 PDF 渲染未返回结果。"]
            )
        }
        return try result.get()
    }

    @MainActor
    private static func renderPDFData(
        html: String,
        baseURL: URL,
        settings: TeachingPDFExportSettings,
        scale: Double
    ) throws -> Data {
        let debugOptions = ExportDebugOptions.load()
        let clampedScale = min(1, max(0.1, scale))
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        configuration.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1200, height: 1800), configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        let loader = NodeMarkdownScaledPDFWebViewLoader()
        webView.navigationDelegate = loader
        let htmlWithExportPageStyle = normalizeHTMLForPDF(
            injectPageStyle(for: settings, scale: clampedScale, into: html)
        )
        webView.loadHTMLString(htmlWithExportPageStyle, baseURL: baseURL)
        try loader.waitSynchronouslyUntilFinished(timeout: pageLoadTimeout)
        if debugOptions.enableDiagnostics {
            TeachingDebugLogStore.append(
                "PDF导出模式：legacyPagination=\(debugOptions.legacyPagination), scale=\(clampedScale), strategy=\(settings.paginationStrategy.rawValue)",
                category: "PDF.Export"
            )
        }
        _ = webView.nmEvaluateJavaScriptSync("window.__postProcessRows && window.__postProcessRows();")
        _ = webView.nmEvaluateJavaScriptSync("window.__normalizePDFBackgroundBars && window.__normalizePDFBackgroundBars();")
        let bgbarSummary = webView.nmEvaluateJavaScriptSync(
            """
            (function() {
                return window.__pdfBgbarDiagnostics || null;
            })();
            """
        )
        if let info = bgbarSummary as? [String: Any] {
            let total = (info["rowTotal"] as? NSNumber)?.intValue ?? 0
            let tagged = (info["taggedCount"] as? NSNumber)?.intValue ?? 0
            let sampleText = ((info["samples"] as? [[String: Any]]) ?? []).map { item in
                let idx = (item["idx"] as? String) ?? ""
                let start = (item["start"] as? String) ?? ""
                let end = (item["end"] as? String) ?? ""
                return "#\(idx):\(start)->\(end)"
            }.joined(separator: " | ")
            TeachingDebugLogStore.append(
                "PDF背景条诊断：rows=\(total), tagged=\(tagged), samples=\(sampleText)",
                category: "PDF.Export"
            )
        } else {
            TeachingDebugLogStore.append(
                "PDF背景条诊断：no data",
                category: "PDF.Export"
            )
        }
        _ = webView.nmEvaluateJavaScriptSync("document.fonts && document.fonts.ready ? document.fonts.ready : Promise.resolve();")
        let imageSummaryBeforeWait = webView.nmEvaluateJavaScriptSync(
            """
            (function() {
                const imgs = Array.from(document.images || []);
                const unresolved = imgs.filter(function(img) {
                    const src = (img.getAttribute('src') || '').trim();
                    return !src || src.startsWith('about:blank');
                }).length;
                const loaded = imgs.filter(function(img) {
                    return img.complete && img.naturalWidth > 0 && img.naturalHeight > 0;
                }).length;
                return { total: imgs.length, unresolved: unresolved, loaded: loaded };
            })();
            """
        )
        _ = webView.nmEvaluateJavaScriptSync(
            """
            (function() {
                const images = Array.from(document.images || []);
                if (images.length === 0) { return Promise.resolve(true); }
                return Promise.all(images.map(function(img) {
                    if (img.complete) { return Promise.resolve(true); }
                    return new Promise(function(resolve) {
                        img.addEventListener('load', function() { resolve(true); }, { once: true });
                        img.addEventListener('error', function() { resolve(false); }, { once: true });
                    });
                }));
            })();
            """,
            timeout: imageLoadTimeout
        )
        let imageSummaryAfterWait = webView.nmEvaluateJavaScriptSync(
            """
            (function() {
                const imgs = Array.from(document.images || []);
                const unresolved = imgs.filter(function(img) {
                    const src = (img.getAttribute('src') || '').trim();
                    return !src || src.startsWith('about:blank');
                }).length;
                const loaded = imgs.filter(function(img) {
                    return img.complete && img.naturalWidth > 0 && img.naturalHeight > 0;
                }).length;
                const failed = imgs.filter(function(img) {
                    return img.complete && (!img.naturalWidth || !img.naturalHeight);
                }).length;
                const samples = imgs.slice(0, 8).map(function(img) {
                    return {
                        src: (img.getAttribute('src') || '').slice(0, 120),
                        width: img.naturalWidth || 0,
                        height: img.naturalHeight || 0
                    };
                });
                return { total: imgs.length, unresolved: unresolved, loaded: loaded, failed: failed, samples: samples };
            })();
            """
        )
        if let summaryBefore = imageSummaryBeforeWait as? [String: Any],
           let summaryAfter = imageSummaryAfterWait as? [String: Any] {
            let total = (summaryAfter["total"] as? NSNumber)?.intValue ?? 0
            let unresolvedBefore = (summaryBefore["unresolved"] as? NSNumber)?.intValue ?? 0
            let unresolvedAfter = (summaryAfter["unresolved"] as? NSNumber)?.intValue ?? 0
            let loaded = (summaryAfter["loaded"] as? NSNumber)?.intValue ?? 0
            let failed = (summaryAfter["failed"] as? NSNumber)?.intValue ?? 0
            TeachingDebugLogStore.append(
                "PDF图片检查：total=\(total), loaded=\(loaded), failed=\(failed), unresolved(before/after)=\(unresolvedBefore)/\(unresolvedAfter)",
                category: "PDF.Export"
            )
            if let samples = summaryAfter["samples"] as? [[String: Any]], !samples.isEmpty {
                let sampleText = samples.map { item in
                    let src = (item["src"] as? String) ?? ""
                    let width = (item["width"] as? NSNumber)?.intValue ?? 0
                    let height = (item["height"] as? NSNumber)?.intValue ?? 0
                    return "[\(width)x\(height)]\(src)"
                }.joined(separator: " | ")
                TeachingDebugLogStore.append(
                    "PDF图片样本：\(sampleText)",
                    category: "PDF.Export"
                )
            }
        }
        if debugOptions.enableDiagnostics {
            let formulaSummary = webView.nmEvaluateJavaScriptSync(
                """
                (function() {
                    const nodes = Array.from(document.querySelectorAll('.katex'));
                    const samples = nodes.slice(0, 6).map(function(node) {
                        const rect = node.getBoundingClientRect();
                        return { w: rect.width || 0, h: rect.height || 0 };
                    });
                    return { count: nodes.length, samples: samples };
                })();
                """
            )
            if let summary = formulaSummary as? [String: Any] {
                let count = (summary["count"] as? NSNumber)?.intValue ?? 0
                let sampleText = ((summary["samples"] as? [[String: Any]]) ?? []).map { item in
                    let width = (item["w"] as? NSNumber)?.intValue ?? 0
                    let height = (item["h"] as? NSNumber)?.intValue ?? 0
                    return "\(width)x\(height)"
                }.joined(separator: ",")
                TeachingDebugLogStore.append(
                    "PDF公式检查：count=\(count), samples=\(sampleText)",
                    category: "PDF.Export"
                )
            }
        }

        let sizeResult = webView.nmEvaluateJavaScriptSync(
            """
            (function() {
                const root = document.getElementById('rows');
                const visualHeight = root ? root.getBoundingClientRect().height : 0;
                const visualWidth = root ? root.getBoundingClientRect().width : 0;
                const docWidth = Math.max(document.body.scrollWidth, document.documentElement.scrollWidth, visualWidth);
                const docHeight = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, visualHeight);
                return { w: docWidth, h: docHeight };
            })();
            """
        )
        let contentSize = decodeSize(from: sizeResult)
        _ = webView.nmEvaluateJavaScriptSync(
            """
            (function() {
                document.querySelectorAll('img').forEach(function(img) {
                    if (img.style.maxWidth === '') { img.style.maxWidth = '100%'; }
                    img.style.height = 'auto';
                });
                return true;
            })();
            """
        )
        let paperSize = paperSize(for: settings)
        let width = max(400, paperSize.width)
        let contentHeight = max(1, contentSize.height)
        switch settings.paginationStrategy {
        case .singleLongPage:
            let config = WKPDFConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: width, height: max(1024, contentHeight))
            return try webView.nmCreatePDFSync(configuration: config, timeout: pdfRenderTimeout)
        case .paged:
            let pageHeight = max(400, paperSize.height)
            return try renderPagedPDFData(
                webView: webView,
                pageWidth: width,
                pageHeight: pageHeight,
                contentHeight: contentHeight,
                debugOptions: debugOptions
            )
        }
    }

    @MainActor
    private static func renderPagedPDFData(
        webView: WKWebView,
        pageWidth: CGFloat,
        pageHeight: CGFloat,
        contentHeight: CGFloat,
        debugOptions: ExportDebugOptions
    ) throws -> Data {
        let snapTolerance: CGFloat = max(24, pageHeight * 0.06)
        let pageSlices: [(originY: CGFloat, height: CGFloat)] = debugOptions.legacyPagination
            ? fallbackPageSlices(pageHeight: pageHeight, contentHeight: contentHeight)
            : computePageSlices(
                webView: webView,
                pageHeight: pageHeight,
                contentHeight: contentHeight,
                snapTolerance: snapTolerance
            )
        let pageCount = pageSlices.count
        TeachingDebugLogStore.append(
            "PDF分页切片：pageCount=\(pageCount), pageHeight=\(Int(pageHeight)), contentHeight=\(Int(contentHeight)), snapTolerance=\(Int(snapTolerance))",
            category: "PDF.Export"
        )
        var slices: [Data] = []
        slices.reserveCapacity(pageCount)
        for slice in pageSlices {
            let config = WKPDFConfiguration()
            config.rect = CGRect(x: 0, y: slice.originY, width: pageWidth, height: slice.height)
            let pageData = try webView.nmCreatePDFSync(configuration: config, timeout: pdfRenderTimeout)
            slices.append(pageData)
        }
        return try mergePDFPages(slices)
    }

    @MainActor
    private static func computePageSlices(
        webView: WKWebView,
        pageHeight: CGFloat,
        contentHeight: CGFloat,
        snapTolerance: CGFloat
    ) -> [(originY: CGFloat, height: CGFloat)] {
        let rowBoxes = collectRowBoxes(webView: webView, contentHeight: contentHeight)
        if rowBoxes.isEmpty {
            return fallbackPageSlices(pageHeight: pageHeight, contentHeight: contentHeight)
        }

        var slices: [(originY: CGFloat, height: CGFloat)] = []
        var pageStart: CGFloat = rowBoxes.first?.top ?? 0
        var rowCursor = 0
        let epsilon: CGFloat = 0.5
        while rowCursor < rowBoxes.count {
            let tentativeEnd = pageStart + pageHeight
            var lastIncludedIndex = rowCursor - 1
            var candidateEnd = pageStart

            var scanIndex = rowCursor
            while scanIndex < rowBoxes.count {
                let row = rowBoxes[scanIndex]
                let rowBottom = row.bottom
                if rowBottom <= tentativeEnd + snapTolerance {
                    lastIncludedIndex = scanIndex
                    candidateEnd = max(candidateEnd, rowBottom)
                    scanIndex += 1
                    continue
                }
                break
            }

            if lastIncludedIndex < rowCursor {
                let forcedRow = rowBoxes[rowCursor]
                let forcedEnd = max(forcedRow.bottom, pageStart + 1)
                slices.append((originY: pageStart, height: min(contentHeight, forcedEnd) - pageStart))
                TeachingDebugLogStore.append(
                    "PDF分页强制容纳超高行：rowIndex=\(forcedRow.index), rowTop=\(Int(forcedRow.top)), rowBottom=\(Int(forcedRow.bottom))",
                    category: "PDF.Export"
                )
                pageStart = forcedEnd
                rowCursor += 1
                continue
            }

            let pageEnd = min(contentHeight, max(pageStart + 1, candidateEnd))
            slices.append((originY: pageStart, height: pageEnd - pageStart))

            let startRow = rowBoxes[rowCursor].index
            let endRow = rowBoxes[lastIncludedIndex].index
            TeachingDebugLogStore.append(
                "PDF分页断点：startRow=\(startRow), endRow=\(endRow), pageStart=\(Int(pageStart)), pageEnd=\(Int(pageEnd))",
                category: "PDF.Export"
            )

            rowCursor = lastIncludedIndex + 1
            if rowCursor < rowBoxes.count {
                pageStart = max(pageEnd, rowBoxes[rowCursor].top)
            } else {
                pageStart = pageEnd
            }

            if pageStart >= contentHeight - epsilon {
                break
            }
        }

        return slices.isEmpty ? fallbackPageSlices(pageHeight: pageHeight, contentHeight: contentHeight) : slices
    }

    @MainActor
    private static func collectRowBoxes(webView: WKWebView, contentHeight: CGFloat) -> [RowBox] {
        let value = webView.nmEvaluateJavaScriptSync(
            """
            (function() {
                const rows = Array.from(document.querySelectorAll('.row'));
                if (rows.length === 0) { return []; }                
                const root = document.getElementById('rows') || document.body;
                const rootTop = root.getBoundingClientRect().top;
                return rows.map(function(row, idx) {
                    const rect = row.getBoundingClientRect();
                    const attr = Number(row.getAttribute('data-node-index'));
                    const rowIndex = Number.isFinite(attr) ? attr : idx;
                    return {
                        index: rowIndex,
                        top: rect.top - rootTop,
                        bottom: rect.bottom - rootTop
                    };
                }).filter(function(item) {
                    return Number.isFinite(item.top) && Number.isFinite(item.bottom) && item.bottom > item.top;
                }).sort(function(a, b) {
                    return a.top - b.top;
                });
            })();
            """
        )
        guard let list = value as? [[String: Any]], !list.isEmpty else { return [] }
        return list.compactMap { item in
            guard let topValue = (item["top"] as? NSNumber)?.doubleValue,
                  let bottomValue = (item["bottom"] as? NSNumber)?.doubleValue else {
                return nil
            }
            let indexValue = (item["index"] as? NSNumber)?.intValue ?? 0
            let top = min(max(0, CGFloat(topValue)), contentHeight)
            let bottom = min(max(0, CGFloat(bottomValue)), contentHeight)
            guard bottom > top else { return nil }
            return RowBox(index: indexValue, top: top, bottom: bottom)
        }
    }

    private static func fallbackPageSlices(pageHeight: CGFloat, contentHeight: CGFloat) -> [(originY: CGFloat, height: CGFloat)] {
        let pageCount = max(1, Int(ceil(contentHeight / pageHeight)))
        return (0..<pageCount).map { index in
            let originY = CGFloat(index) * pageHeight
            let targetHeight = min(pageHeight, max(1, contentHeight - originY))
            return (originY: originY, height: targetHeight)
        }
    }

    private static func mergePDFPages(_ pages: [Data]) throws -> Data {
        let merged = PDFDocument()
        var insertIndex = 0
        for pageData in pages {
            guard let document = PDFDocument(data: pageData) else {
                throw NSError(
                    domain: "NodeMarkdownScaledPDFExporter",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "分页导出失败：无法解析单页PDF。"]
                )
            }
            for pageOffset in 0..<document.pageCount {
                guard let page = document.page(at: pageOffset) else { continue }
                merged.insert(page, at: insertIndex)
                insertIndex += 1
            }
        }
        guard let data = merged.dataRepresentation(), !data.isEmpty else {
            throw NSError(
                domain: "NodeMarkdownScaledPDFExporter",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "分页导出失败：合并PDF为空。"]
            )
        }
        TeachingDebugLogStore.append(
            "PDF分页合并完成：outputBytes=\(data.count)",
            category: "PDF.Export"
        )
        return data
    }

    private static func decodeSize(from value: Any) -> CGSize {
        guard let dict = value as? [String: Any] else { return .zero }
        let width = (dict["w"] as? NSNumber)?.doubleValue ?? 0
        let height = (dict["h"] as? NSNumber)?.doubleValue ?? 0
        return CGSize(width: width, height: height)
    }

    private static func paperSize(for settings: TeachingPDFExportSettings) -> CGSize {
        let base: CGSize = switch settings.paperPreset {
        case .a4:
            CGSize(width: 595, height: 842)
        case .letter:
            CGSize(width: 612, height: 792)
        case .custom:
            CGSize(width: max(200, settings.customWidth), height: max(200, settings.customHeight))
        }
        switch settings.orientation {
        case .portrait: return base
        case .landscape: return CGSize(width: base.height, height: base.width)
        }
    }

    private static func injectPageStyle(for settings: TeachingPDFExportSettings, scale: Double, into html: String) -> String {
        let paper = paperSize(for: settings)
        let clampedScale = min(1, max(0.1, scale))
        let style = """
        <style id="pdf-export-style">
        :root {
            --pdf-export-scale: \(clampedScale);
        }
        @page {
            size: \(Int(paper.width))px \(Int(paper.height))px;
            margin: \(settings.marginTop)px \(settings.marginRight)px \(settings.marginBottom)px \(settings.marginLeft)px;
        }
        * {
            -webkit-print-color-adjust: exact !important;
            print-color-adjust: exact !important;
        }
        body {
            margin: 0 !important;
            -webkit-print-color-adjust: exact !important;
            print-color-adjust: exact !important;
        }
        #rows {
            transform: scale(var(--pdf-export-scale));
            transform-origin: top left;
            width: calc(100% / var(--pdf-export-scale));
        }
        .row.pdf-bgbar {
            position: relative;
            overflow: visible;
            background: transparent !important;
            background-image: none !important;
            background-color: transparent !important;
        }
        .row.pdf-bgbar::before {
            content: "";
            position: absolute;
            left: var(--pdf-row-bg-left, 10px);
            right: var(--pdf-row-bg-right, 40px);
            top: var(--pdf-row-bg-top, 50%);
            height: var(--pdf-row-bg-height, calc(100% - 6px));
            transform: var(--pdf-row-bg-transform, translateY(-50%));
            border-radius: 8px;
            background: linear-gradient(
                90deg,
                var(--pdf-row-bg-start, rgba(120,120,120,0.10)) 0%,
                var(--pdf-row-bg-end, rgba(120,120,120,0.02)) 100%
            );
            -webkit-print-color-adjust: exact !important;
            print-color-adjust: exact !important;
            z-index: 0;
            pointer-events: none;
        }
        .row.pdf-bgbar > .icon,
        .row.pdf-bgbar > .text {
            position: relative;
            z-index: 1;
        }
        .row.pdf-bgbar > .icon {
            margin-top: var(--pdf-row-icon-offset, 0px);
        }
        .row > .icon {
            width: var(--marker-advance, 1em) !important;
            min-width: var(--marker-advance, 1em) !important;
            margin-right: 0 !important;
        }
        .katex-display {
            margin: 0 !important;
        }
        </style>
        """
        guard let range = html.range(of: "</head>") else { return html + style }
        return html.replacingCharacters(in: range, with: style + "\n</head>")
    }

    private static func normalizeHTMLForPDF(_ html: String) -> String {
        let script = """
        <script id="pdf-image-normalizer">
        (function() {
            const PLACEHOLDER_SVG = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(
                "<svg xmlns='http://www.w3.org/2000/svg' width='640' height='160'><rect width='100%' height='100%' fill='#F4F4F4'/><text x='50%' y='50%' dominant-baseline='middle' text-anchor='middle' fill='#999' font-size='20'>Image Load Failed</text></svg>"
            );
            function safeDecodeURI(raw) {
                try { return decodeURI(raw); } catch (_) { return raw; }
            }
            function resolveSource(raw, base) {
                if (!raw) { return ""; }
                const trimmed = raw.trim();
                if (!trimmed) { return ""; }
                if (/^(data:|blob:|https?:|file:)/i.test(trimmed)) {
                    return trimmed;
                }
                const decoded = safeDecodeURI(trimmed);
                try {
                    return new URL(decoded, base).href;
                } catch (_) {
                    return decoded;
                }
            }
            function normalizeImages() {
                const base = document.baseURI || window.location.href;
                document.querySelectorAll('img').forEach(function(img) {
                    const raw = (img.getAttribute('src') || '').trim();
                    if (!raw) { return; }
                    try {                        
                        const resolved = resolveSource(raw, base);
                        img.setAttribute('src', resolved);
                    } catch (_) {}
                    img.style.maxWidth = img.style.maxWidth || '100%';
                    img.style.height = 'auto';
                    img.style.display = 'inline-block';
                    img.style.objectFit = img.style.objectFit || 'contain';
                    img.loading = 'eager';
                    img.decoding = 'sync';
                    img.referrerPolicy = img.referrerPolicy || 'no-referrer';
                    if (img.dataset.pdfNormalized !== '1') {
                        img.dataset.pdfNormalized = '1';
                        img.addEventListener('error', function() {
                            if (img.dataset.pdfPlaceholderApplied === '1') { return; }
                            img.dataset.pdfPlaceholderApplied = '1';
                            img.setAttribute('src', PLACEHOLDER_SVG);
                        });
                    }
                });
            }
            function normalizeBackgroundBars() {
                const rows = Array.from(document.querySelectorAll('.row'));
                function clampByte(value) {
                    return Math.max(0, Math.min(255, Math.round(value)));
                }
                function parseRGBFromTextColor(value) {
                    if (!value) { return null; }
                    const hex = value.trim().match(/^#([0-9a-f]{6})$/i);
                    if (hex) {
                        const raw = parseInt(hex[1], 16);
                        return {
                            r: (raw >> 16) & 255,
                            g: (raw >> 8) & 255,
                            b: raw & 255
                        };
                    }
                    const rgb = value.trim().match(/^rgba?\\s*[(](\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)/i);
                    if (rgb) {
                        return {
                            r: clampByte(Number(rgb[1])),
                            g: clampByte(Number(rgb[2])),
                            b: clampByte(Number(rgb[3]))
                        };
                    }
                    return null;
                }
                function parseRGBFromHex(value) {
                    if (!value) { return null; }
                    const match = value.trim().match(/^#([0-9a-f]{6})$/i);
                    if (!match) { return null; }
                    const raw = parseInt(match[1], 16);
                    return {
                        r: (raw >> 16) & 255,
                        g: (raw >> 8) & 255,
                        b: raw & 255
                    };
                }
                function textInkRect(textNode) {
                    if (!textNode) { return null; }
                    const range = document.createRange();
                    range.selectNodeContents(textNode);
                    const rects = Array.from(range.getClientRects());
                    if (!rects.length) { return textNode.getBoundingClientRect(); }
                    const left = Math.min.apply(null, rects.map(r => r.left));
                    const right = Math.max.apply(null, rects.map(r => r.right));
                    const top = Math.min.apply(null, rects.map(r => r.top));
                    const bottom = Math.max.apply(null, rects.map(r => r.bottom));
                    return { left, right, top, bottom };
                }
                function textLineRects(textNode) {
                    if (!textNode) { return []; }
                    const range = document.createRange();
                    range.selectNodeContents(textNode);
                    return Array.from(range.getClientRects()).filter(r => r.width > 0.5 && r.height > 0.5);
                }
                const taggedSamples = [];
                let taggedCount = 0;
                rows.forEach(function(row) {
                    const marked = (row.getAttribute('data-pdf-bgbar') || '').trim();
                    if (marked !== '1') {
                        return;
                    }
                    const icon = row.querySelector('.icon');
                    const iconColor = icon ? (icon.style.color || window.getComputedStyle(icon).color || '') : '';
                    const explicitHex = (row.getAttribute('data-pdf-bgcolor') || '').trim();
                    const base = parseRGBFromHex(explicitHex) || parseRGBFromTextColor(iconColor) || { r: 120, g: 120, b: 120 };
                    const start = 'rgba(' + base.r + ',' + base.g + ',' + base.b + ',0.10)';
                    const end = 'rgba(' + base.r + ',' + base.g + ',' + base.b + ',0.02)';
                    row.style.setProperty('--pdf-row-bg-start', start);
                    row.style.setProperty('--pdf-row-bg-end', end);
                    const rowRect = row.getBoundingClientRect();
                    const iconRect = icon ? icon.getBoundingClientRect() : null;
                    const textNode = row.querySelector('.text');
                    const textRect = textInkRect(textNode);
                    const lineRects = textLineRects(textNode);
                    const firstLineRect = lineRects.length ? lineRects[0] : null;
                    const bgLeft = iconRect ? Math.max(0, iconRect.left - rowRect.left - 4) : 10;
                    const bgRight = textRect ? Math.max(36, rowRect.right - textRect.right + 34) : 40;
                    row.style.setProperty('--pdf-row-bg-left', bgLeft.toFixed(1) + 'px');
                    row.style.setProperty('--pdf-row-bg-right', bgRight.toFixed(1) + 'px');
                    if (textRect) {
                        const top = Math.max(0, textRect.top - rowRect.top - 2);
                        const maxHeight = Math.max(8, rowRect.height - top - 2);
                        const height = Math.max(10, Math.min(maxHeight, textRect.bottom - textRect.top + 4));
                        row.style.setProperty('--pdf-row-bg-top', top.toFixed(1) + 'px');
                        row.style.setProperty('--pdf-row-bg-height', height.toFixed(1) + 'px');
                        row.style.setProperty('--pdf-row-bg-transform', 'none');
                    } else {
                        row.style.removeProperty('--pdf-row-bg-top');
                        row.style.removeProperty('--pdf-row-bg-height');
                        row.style.removeProperty('--pdf-row-bg-transform');
                    }
                    if (iconRect && firstLineRect) {
                        const firstLineCenterY = firstLineRect.top + firstLineRect.height / 2;
                        const iconCenterY = iconRect.top + iconRect.height / 2;
                        const iconOffset = firstLineCenterY - iconCenterY;
                        row.style.setProperty('--pdf-row-icon-offset', iconOffset.toFixed(1) + 'px');
                    } else {
                        row.style.removeProperty('--pdf-row-icon-offset');
                    }
                    row.classList.add('pdf-bgbar');
                    row.style.background = 'transparent';
                    row.style.backgroundImage = 'none';
                    row.style.backgroundColor = 'transparent';
                    taggedCount += 1;
                    if (taggedSamples.length < 8) {
                        taggedSamples.push({
                            idx: row.getAttribute('data-node-index') || '',
                            start: start,
                            end: end
                        });
                    }
                });
                window.__pdfBgbarDiagnostics = {
                    rowTotal: rows.length,
                    taggedCount: taggedCount,
                    samples: taggedSamples
                };
            }
            window.__normalizePDFBackgroundBars = normalizeBackgroundBars;
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', function() {
                    normalizeImages();
                    normalizeBackgroundBars();
                }, { once: true });
            } else {
                normalizeImages();
                normalizeBackgroundBars();
            }
        })();
        </script>
        """
        guard let range = html.range(of: "</head>") else { return html + script }
        return html.replacingCharacters(in: range, with: script + "\n</head>")
    }
}

private struct RowBox {
    let index: Int
    let top: CGFloat
    let bottom: CGFloat
}

private struct ExportDebugOptions {
    var enableDiagnostics: Bool
    var legacyPagination: Bool

    static func load(defaults: UserDefaults = .standard) -> ExportDebugOptions {
        ExportDebugOptions(
            enableDiagnostics: defaults.bool(forKey: "teaching.pdf.export.diagnostics"),
            legacyPagination: defaults.bool(forKey: "teaching.pdf.export.legacyPagination")
        )
    }
}

private final class NodeMarkdownScaledPDFWebViewLoader: NSObject, WKNavigationDelegate {
    private var settled = false
    private var finished = false
    private var capturedError: Error?

    func waitSynchronouslyUntilFinished(timeout: TimeInterval = 30) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !finished && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        if !finished {
            throw NSError(
                domain: "NodeMarkdownScaledPDFExporter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "加载导出页面超时（等待 \(Int(timeout)) 秒）。"]
            )
        }
        if let capturedError { throw capturedError }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !settled else { return }
        settled = true
        finished = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !settled else { return }
        settled = true
        capturedError = error
        finished = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !settled else { return }
        settled = true
        capturedError = error
        finished = true
    }
}

private extension WKWebView {
    @MainActor
    func nmEvaluateJavaScriptSync(_ script: String, timeout: TimeInterval = 5) -> Any {
        var resultValue: Any?
        var settled = false
        evaluateJavaScript(script) { result, _ in
            resultValue = result
            settled = true
        }
        let deadline = Date().addingTimeInterval(timeout)
        while !settled && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return resultValue as Any
    }

    @MainActor
    func nmCreatePDFSync(configuration: WKPDFConfiguration, timeout: TimeInterval = 30) throws -> Data {
        var outputData: Data?
        var outputError: Error?
        var settled = false
        createPDF(configuration: configuration) { result in
            switch result {
            case let .success(data):
                outputData = data
            case let .failure(error):
                outputError = error
            }
            settled = true
        }
        let deadline = Date().addingTimeInterval(timeout)
        while !settled && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        if !settled {
            throw NSError(domain: "NodeMarkdownScaledPDFExporter", code: -2, userInfo: [NSLocalizedDescriptionKey: "生成PDF超时。"])
        }
        if let outputError { throw outputError }
        return outputData ?? Data()
    }
}
