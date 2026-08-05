import Foundation

// MARK: - NodeMarkdown HTML导出 - v2 - 输出真实HTML并继承NodeMarkdown文档背景
enum NodeMarkdownHTMLExporter {
    static func renderData(
        sourceFileURL: URL,
        document: NodeMarkdownDocument,
        style: NodeMarkdownDocumentStyle
    ) throws -> Data {
        let rows = NodeMarkdownHTMLBuilder.buildRows(
            document: document,
            style: style,
            exportScheme: style.preferredScheme.resolvedExportScheme
        )
        let backgroundHex = NodeMarkdownHTMLBuilder.exportBackgroundHex(for: style)
        let html = NodeMarkdownHTMLBuilder.documentHTML(
            initialRowsHTML: rows,
            backgroundHex: backgroundHex,
            baseURL: sourceFileURL.deletingLastPathComponent(),
            inlineAssets: true
        )
        return Data(html.utf8)
    }

    static func renderData(sourceFileURL: URL, embeddedPDFData pdfData: Data) -> Data {
        let title = htmlEscaped(sourceFileURL.deletingPathExtension().lastPathComponent)
        let encodedPDF = pdfData.base64EncodedString()
        return Data(documentHTML(title: title, encodedPDF: encodedPDF).utf8)
    }

    private static func documentHTML(title: String, encodedPDF: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>\(title)</title>
        <style>
        html, body {
            margin: 0;
            width: 100%;
            height: 100%;
            background: #f2f2f2;
        }
        .pdf-export-frame {
            display: block;
            width: 100%;
            height: 100vh;
            border: 0;
            background: #ffffff;
        }
        </style>
        </head>
        <body>
        <embed
            class="pdf-export-frame"
            type="application/pdf"
            src="data:application/pdf;base64,\(encodedPDF)"
        />
        </body>
        </html>
        """
    }

    private static func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
