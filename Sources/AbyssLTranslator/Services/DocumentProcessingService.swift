import AppKit
import CoreText
import Foundation
import PDFKit

enum DocumentProcessingError: LocalizedError {
    case unsupported(String)
    case unavailable(String)
    case extractionFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let message), .unavailable(let message), .extractionFailed(let message), .exportFailed(let message):
            return message
        }
    }
}

actor DocumentProcessingService {
    private let openAIService: OpenAIService
    private let localLLMService: LocalLLMService
    private let fileManager = FileManager.default

    init(
        openAIService: OpenAIService = OpenAIService(),
        localLLMService: LocalLLMService = LocalLLMService()
    ) {
        self.openAIService = openAIService
        self.localLLMService = localLLMService
    }

    static func inputKind(for url: URL) -> DocumentInputKind {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "txt", "text":
            return .plainText
        case "md", "markdown":
            return .markdown
        case "adoc", "asciidoc":
            return .asciidoc
        case "html", "htm":
            return .html
        case "rtf":
            return .rtf
        case "pdf":
            return .pdf
        case "docx", "xdoc":
            return .docx
        case "odt":
            return .odt
        case "csv":
            return .csv
        case "tsv":
            return .tsv
        case "xlsx":
            return .xlsx
        case "pages":
            return .pages
        case "numbers":
            return .numbers
        default:
            return .unsupported
        }
    }

    static func isKindSupported(_ kind: DocumentInputKind) -> Bool {
        switch kind {
        case .plainText, .markdown, .asciidoc, .html, .rtf, .pdf, .csv, .tsv:
            return true
        case .docx, .xlsx:
            return executableExists("/usr/bin/unzip")
        case .odt:
            return sofficeURL() != nil
        case .pages, .numbers, .unsupported:
            return false
        }
    }

    static func unavailableReason(for kind: DocumentInputKind) -> String {
        switch kind {
        case .docx, .xlsx:
            return String(localized: "document.error.unzipUnavailable", bundle: .module)
        case .odt:
            return String(localized: "document.error.odtUnavailable", bundle: .module)
        case .pages:
            return String(localized: "document.error.pagesUnavailable", bundle: .module)
        case .numbers:
            return String(localized: "document.error.numbersUnavailable", bundle: .module)
        case .unsupported:
            return String(localized: "document.error.unsupported", bundle: .module)
        default:
            return ""
        }
    }

    static func availableExportFormats(hasSpreadsheetInput: Bool) -> [DocumentExportFormat] {
        var formats: [DocumentExportFormat] = [.pdf, .docx, .markdown, .html, .asciidoc, .plainText, .rtf]
        if sofficeURL() != nil {
            formats.insert(.odt, at: 2)
        }
        if canSafelyExportPages() {
            formats.append(.pages)
        }
        if hasSpreadsheetInput, canSafelyExportNumbers() {
            formats.append(.numbers)
        }
        return formats
    }

    static func canExport(_ format: DocumentExportFormat, hasSpreadsheetInput: Bool) -> Bool {
        availableExportFormats(hasSpreadsheetInput: hasSpreadsheetInput).contains(format)
    }

    static func collectJobs(from urls: [URL]) -> [DocumentJob] {
        var jobs: [DocumentJob] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                jobs.append(contentsOf: collectDirectoryJobs(rootURL: url))
            } else {
                let kind = inputKind(for: url)
                let message = isKindSupported(kind) ? nil : unavailableReason(for: kind)
                jobs.append(DocumentJob(sourceURL: url, rootURL: nil, inputKind: kind, statusMessage: message))
            }
        }
        return jobs.sorted { lhs, rhs in
            lhs.sourceURL.path.localizedStandardCompare(rhs.sourceURL.path) == .orderedAscending
        }
    }

    func process(
        jobs: [DocumentJob],
        destinationDirectory: URL,
        options: DocumentOperationOptions,
        configuration: DocumentProcessingConfiguration,
        progress: @MainActor @escaping (DocumentBatchProgress) -> Void
    ) async -> [DocumentProcessingResult] {
        var progressState = DocumentBatchProgress(
            total: jobs.count,
            completed: 0,
            currentFile: nil,
            startedAt: Date(),
            isRunning: true
        )
        await publishProgress(progressState, progress: progress)

        var results: [DocumentProcessingResult] = []
        for job in jobs {
            guard !Task.isCancelled else { break }
            progressState.currentFile = job.displayName
            await publishProgress(progressState, progress: progress)

            do {
                guard Self.isKindSupported(job.inputKind) else {
                    throw DocumentProcessingError.unsupported(job.statusMessage ?? Self.unavailableReason(for: job.inputKind))
                }
                guard Self.canExport(options.exportFormat, hasSpreadsheetInput: job.inputKind.isSpreadsheet) else {
                    throw DocumentProcessingError.unavailable(Self.exportUnavailableReason(for: options.exportFormat))
                }

                var document = try loadDocument(job: job)
                document = try await processDocument(document, options: options, configuration: configuration)
                let outputURL = try export(
                    document,
                    sourceJob: job,
                    destinationDirectory: destinationDirectory,
                    options: options,
                    configuration: configuration
                )
                results.append(DocumentProcessingResult(
                    sourceURL: job.sourceURL,
                    outputURL: outputURL,
                    status: .success,
                    message: String(localized: "document.result.success", bundle: .module)
                ))
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                results.append(DocumentProcessingResult(
                    sourceURL: job.sourceURL,
                    outputURL: nil,
                    status: .failed,
                    message: message
                ))
            }

            progressState.completed += 1
            await publishProgress(progressState, progress: progress)
        }

        progressState.currentFile = nil
        progressState.isRunning = false
        progressState.finishedAt = Date()
        await publishProgress(progressState, progress: progress)
        return results
    }

    private func publishProgress(
        _ state: DocumentBatchProgress,
        progress: @MainActor @escaping (DocumentBatchProgress) -> Void
    ) async {
        let snapshot = state
        await MainActor.run {
            progress(snapshot)
        }
    }

    private static func collectDirectoryJobs(rootURL: URL) -> [DocumentJob] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var jobs: [DocumentJob] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else {
                continue
            }
            let kind = inputKind(for: fileURL)
            let message = isKindSupported(kind) ? nil : unavailableReason(for: kind)
            jobs.append(DocumentJob(sourceURL: fileURL, rootURL: rootURL, inputKind: kind, statusMessage: message))
        }
        return jobs
    }

    private func loadDocument(job: DocumentJob) throws -> DocumentIR {
        switch job.inputKind {
        case .plainText, .markdown, .asciidoc:
            return try loadPlainText(url: job.sourceURL, kind: job.inputKind)
        case .html:
            return try loadHTML(url: job.sourceURL)
        case .rtf:
            return try loadRTF(url: job.sourceURL)
        case .pdf:
            return try loadPDF(url: job.sourceURL)
        case .docx:
            return try loadDOCX(url: job.sourceURL)
        case .odt:
            return try loadODT(url: job.sourceURL)
        case .csv:
            return try loadDelimited(url: job.sourceURL, delimiter: ",", kind: .csv)
        case .tsv:
            return try loadDelimited(url: job.sourceURL, delimiter: "\t", kind: .tsv)
        case .xlsx:
            return try loadXLSX(url: job.sourceURL)
        case .pages, .numbers, .unsupported:
            throw DocumentProcessingError.unsupported(Self.unavailableReason(for: job.inputKind))
        }
    }

    private func processDocument(
        _ document: DocumentIR,
        options: DocumentOperationOptions,
        configuration: DocumentProcessingConfiguration
    ) async throws -> DocumentIR {
        var processedBlocks: [DocumentIR.Block] = []
        for block in document.blocks {
            switch block {
            case .paragraph(let text):
                processedBlocks.append(.paragraph(try await processTextIfNeeded(text, options: options, configuration: configuration)))
            case .table(let rows):
                var processedRows: [[String]] = []
                for row in rows {
                    var processedRow: [String] = []
                    for cell in row {
                        if shouldProcessTableCell(cell) {
                            processedRow.append(try await processTextIfNeeded(cell, options: options, configuration: configuration))
                        } else {
                            processedRow.append(cell)
                        }
                    }
                    processedRows.append(processedRow)
                }
                processedBlocks.append(.table(processedRows))
            }
        }

        return DocumentIR(blocks: processedBlocks, images: document.images, sourceKind: document.sourceKind)
    }

    private func processTextIfNeeded(
        _ text: String,
        options: DocumentOperationOptions,
        configuration: DocumentProcessingConfiguration
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        var current = text
        if options.shouldCorrect {
            current = try await correctText(current, options: options, configuration: configuration)
        }
        if options.shouldTranslate {
            current = try await translateText(current, options: options, configuration: configuration)
        }
        return current
    }

    private func correctText(
        _ text: String,
        options: DocumentOperationOptions,
        configuration: DocumentProcessingConfiguration
    ) async throws -> String {
        switch configuration.provider {
        case .openAI:
            return try await openAIService.correctWriting(
                text: text,
                instruction: options.instruction,
                alternativeCount: configuration.correctionAlternativeCount,
                source: configuration.sourceLanguage,
                model: configuration.selectedModel,
                reasoning: configuration.reasoningEnabled,
                reasoningEffort: configuration.reasoningEffort,
                apiKey: configuration.apiKey,
                baseURL: configuration.openAIBaseURL
            ).correctedText
        case .localLLM:
            return try await localLLMService.correctWriting(
                text: text,
                instruction: options.instruction,
                alternativeCount: configuration.correctionAlternativeCount,
                source: configuration.sourceLanguage,
                model: configuration.localModel,
                reasoning: configuration.reasoningEnabled,
                reasoningEffort: configuration.reasoningEffort,
                apiKey: configuration.localApiKey,
                baseURL: configuration.localBaseURL,
                timeoutSeconds: configuration.localRequestTimeoutSeconds
            ).correctedText
        }
    }

    private func translateText(
        _ text: String,
        options: DocumentOperationOptions,
        configuration: DocumentProcessingConfiguration
    ) async throws -> String {
        switch configuration.provider {
        case .openAI:
            return try await openAIService.translate(
                text: text,
                instruction: options.instruction,
                source: configuration.sourceLanguage,
                target: configuration.targetLanguage,
                style: configuration.style,
                model: configuration.selectedModel,
                reasoning: configuration.reasoningEnabled,
                reasoningEffort: configuration.reasoningEffort,
                apiKey: configuration.apiKey,
                baseURL: configuration.openAIBaseURL
            ).translation
        case .localLLM:
            return try await localLLMService.translate(
                text: text,
                instruction: options.instruction,
                source: configuration.sourceLanguage,
                target: configuration.targetLanguage,
                style: configuration.style,
                model: configuration.localModel,
                reasoning: configuration.reasoningEnabled,
                reasoningEffort: configuration.reasoningEffort,
                apiKey: configuration.localApiKey,
                baseURL: configuration.localBaseURL,
                timeoutSeconds: configuration.localRequestTimeoutSeconds
            ).translation
        }
    }

    private func loadPlainText(url: URL, kind: DocumentInputKind) throws -> DocumentIR {
        let text = try String(contentsOf: url, encoding: .utf8)
        return DocumentIR(blocks: paragraphs(from: text), images: [], sourceKind: kind)
    }

    private func loadHTML(url: URL) throws -> DocumentIR {
        let data = try Data(contentsOf: url)
        if let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        ) {
            return DocumentIR(blocks: paragraphs(from: attributed.string), images: [], sourceKind: .html)
        }
        return try loadPlainText(url: url, kind: .html)
    }

    private func loadRTF(url: URL) throws -> DocumentIR {
        let attributed = try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        return DocumentIR(blocks: paragraphs(from: attributed.string), images: [], sourceKind: .rtf)
    }

    private func loadPDF(url: URL) throws -> DocumentIR {
        guard let pdf = PDFDocument(url: url) else {
            throw DocumentProcessingError.extractionFailed(String(localized: "document.error.pdfReadFailed", bundle: .module))
        }
        var blocks: [DocumentIR.Block] = []
        for pageIndex in 0 ..< pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            blocks.append(contentsOf: pdfReflowBlocks(from: pageText))
        }

        guard !blocks.isEmpty else {
            throw DocumentProcessingError.unsupported(String(localized: "document.error.scannedPDF", bundle: .module))
        }

        return DocumentIR(blocks: blocks, images: [], sourceKind: .pdf)
    }

    private func pdfReflowBlocks(from pageText: String) -> [DocumentIR.Block] {
        let normalized = pageText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        let lines = normalized.components(separatedBy: "\n")
        var paragraphs: [String] = []
        var currentLines: [String] = []

        func flushCurrentLines() {
            let text = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                paragraphs.append(text)
            }
            currentLines.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                flushCurrentLines()
            } else {
                currentLines.append(trimmed)
            }
        }
        flushCurrentLines()

        return paragraphs.map { .paragraph($0) }
    }

    private func loadDOCX(url: URL) throws -> DocumentIR {
        let documentXML = try unzipString(path: url.path, entry: "word/document.xml")
        let blocks = DOCXDocumentParser.parse(documentXML)
        let images = try loadDOCXImages(url: url)
        guard !blocks.isEmpty else {
            throw DocumentProcessingError.extractionFailed(String(localized: "document.error.emptyDocument", bundle: .module))
        }
        return DocumentIR(blocks: blocks, images: images, sourceKind: .docx)
    }

    private func loadDOCXImages(url: URL) throws -> [DocumentIR.ImageAsset] {
        let entries = try unzipEntryList(path: url.path)
        return try entries
            .filter { $0.hasPrefix("word/media/") && !$0.hasSuffix("/") }
            .compactMap { entry in
                let data = try unzipData(path: url.path, entry: entry)
                let filename = URL(fileURLWithPath: entry).lastPathComponent
                return DocumentIR.ImageAsset(id: UUID().uuidString, suggestedFilename: filename, data: data)
            }
    }

    private func loadODT(url: URL) throws -> DocumentIR {
        guard let soffice = Self.sofficeURL() else {
            throw DocumentProcessingError.unavailable(Self.unavailableReason(for: .odt))
        }
        let tempDir = try temporaryDirectory(prefix: "odt-import")
        defer { try? fileManager.removeItem(at: tempDir) }
        try runProcess(
            executable: soffice.path,
            arguments: ["--headless", "--convert-to", "txt:Text", "--outdir", tempDir.path, url.path],
            currentDirectory: nil
        )
        let txtURL = tempDir.appendingPathComponent(url.deletingPathExtension().lastPathComponent).appendingPathExtension("txt")
        guard fileManager.fileExists(atPath: txtURL.path) else {
            throw DocumentProcessingError.extractionFailed(String(localized: "document.error.odtConvertFailed", bundle: .module))
        }
        return try loadPlainText(url: txtURL, kind: .odt)
    }

    private func loadDelimited(url: URL, delimiter: Character, kind: DocumentInputKind) throws -> DocumentIR {
        let text = try String(contentsOf: url, encoding: .utf8)
        return DocumentIR(blocks: [.table(parseDelimited(text, delimiter: delimiter))], images: [], sourceKind: kind)
    }

    private func loadXLSX(url: URL) throws -> DocumentIR {
        let entries = try unzipEntryList(path: url.path)
        guard entries.contains("xl/workbook.xml") else {
            throw DocumentProcessingError.extractionFailed(String(localized: "document.error.xlsxReadFailed", bundle: .module))
        }
        let sharedStringsXML = try? unzipString(path: url.path, entry: "xl/sharedStrings.xml")
        let sharedStrings = sharedStringsXML.map(XLSXSharedStringsParser.parse) ?? []
        let sheetEntry = entries.first { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
        guard let sheetEntry else {
            throw DocumentProcessingError.extractionFailed(String(localized: "document.error.xlsxReadFailed", bundle: .module))
        }
        let sheetXML = try unzipString(path: url.path, entry: sheetEntry)
        let table = XLSXSheetParser.parse(sheetXML, sharedStrings: sharedStrings)
        guard !table.isEmpty else {
            throw DocumentProcessingError.extractionFailed(String(localized: "document.error.emptyDocument", bundle: .module))
        }
        return DocumentIR(blocks: [.table(table)], images: [], sourceKind: .xlsx)
    }

    private func export(
        _ document: DocumentIR,
        sourceJob: DocumentJob,
        destinationDirectory: URL,
        options: DocumentOperationOptions,
        configuration: DocumentProcessingConfiguration
    ) throws -> URL {
        let relativeDirectory = relativeDirectoryForOutput(sourceJob: sourceJob)
        let outputDirectory = destinationDirectory.appendingPathComponent(relativeDirectory, isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        switch options.exportFormat {
        case .plainText:
            let outputURL = try uniqueOutputURL(for: sourceJob, in: outputDirectory, format: .plainText, options: options, configuration: configuration)
            try document.plainText.write(to: outputURL, atomically: true, encoding: .utf8)
            return outputURL
        case .markdown:
            let outputURL = try uniqueOutputURL(for: sourceJob, in: outputDirectory, format: .markdown, options: options, configuration: configuration)
            try renderMarkdown(document).write(to: outputURL, atomically: true, encoding: .utf8)
            return outputURL
        case .html:
            let outputURL = try uniqueOutputURL(for: sourceJob, in: outputDirectory, format: .html, options: options, configuration: configuration)
            try renderHTML(document).write(to: outputURL, atomically: true, encoding: .utf8)
            return outputURL
        case .asciidoc:
            return try exportAsciiDoc(document, sourceJob: sourceJob, outputDirectory: outputDirectory, options: options, configuration: configuration)
        case .rtf:
            let outputURL = try uniqueOutputURL(for: sourceJob, in: outputDirectory, format: .rtf, options: options, configuration: configuration)
            try exportRTF(document, to: outputURL)
            return outputURL
        case .pdf:
            let outputURL = try uniqueOutputURL(for: sourceJob, in: outputDirectory, format: .pdf, options: options, configuration: configuration)
            try exportPDF(document, to: outputURL)
            return outputURL
        case .docx:
            let outputURL = try uniqueOutputURL(for: sourceJob, in: outputDirectory, format: .docx, options: options, configuration: configuration)
            try exportDOCX(document, to: outputURL)
            return outputURL
        case .odt:
            return try exportODT(document, sourceJob: sourceJob, outputDirectory: outputDirectory, options: options, configuration: configuration)
        case .pages:
            throw DocumentProcessingError.unavailable(Self.exportUnavailableReason(for: .pages))
        case .numbers:
            throw DocumentProcessingError.unavailable(Self.exportUnavailableReason(for: .numbers))
        }
    }

    private func exportAsciiDoc(
        _ document: DocumentIR,
        sourceJob: DocumentJob,
        outputDirectory: URL,
        options: DocumentOperationOptions,
        configuration: DocumentProcessingConfiguration
    ) throws -> URL {
        let adocText = renderAsciiDoc(document, includeImageLinks: options.exportImagesForAsciiDoc && !document.images.isEmpty)
        guard options.exportImagesForAsciiDoc, !document.images.isEmpty else {
            let outputURL = try uniqueOutputURL(for: sourceJob, in: outputDirectory, format: .asciidoc, options: options, configuration: configuration)
            try adocText.write(to: outputURL, atomically: true, encoding: .utf8)
            return outputURL
        }

        let zipURL = try uniqueOutputURL(
            basename: outputBaseName(sourceJob: sourceJob, options: options, configuration: configuration),
            extension: "zip",
            in: outputDirectory
        )
        let tempDir = try temporaryDirectory(prefix: "adoc-export")
        defer { try? fileManager.removeItem(at: tempDir) }

        let adocURL = tempDir.appendingPathComponent(outputBaseName(sourceJob: sourceJob, options: options, configuration: configuration)).appendingPathExtension("adoc")
        try adocText.write(to: adocURL, atomically: true, encoding: .utf8)
        let imagesDirectory = tempDir.appendingPathComponent("images", isDirectory: true)
        try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        for image in document.images {
            try image.data.write(to: imagesDirectory.appendingPathComponent(image.suggestedFilename))
        }
        try zipDirectory(sourceDirectory: tempDir, outputURL: zipURL)
        return zipURL
    }

    private func exportRTF(_ document: DocumentIR, to url: URL) throws {
        let attributed = NSAttributedString(string: document.plainText)
        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        try data.write(to: url)
    }

    private func exportPDF(_ document: DocumentIR, to url: URL) throws {
        try exportPlainTextPDF(document, to: url)
    }

    private func exportPlainTextPDF(_ document: DocumentIR, to url: URL) throws {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 48
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw DocumentProcessingError.exportFailed(String(localized: "document.error.pdfWriteFailed", bundle: .module))
        }

        let bodyFont = CTFontCreateUIFontForLanguage(.system, 11, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, 11, nil)
        let attributed = NSMutableAttributedString(
            string: document.plainText.isEmpty ? " " : document.plainText,
            attributes: [
                kCTFontAttributeName as NSAttributedString.Key: bodyFont,
                kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor.black,
            ]
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        attributed.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: attributed.length)
        )

        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let textRect = CGRect(
            x: margin,
            y: margin,
            width: pageRect.width - margin * 2,
            height: pageRect.height - margin * 2
        )
        let path = CGMutablePath()
        path.addRect(textRect)

        var currentRange = CFRange(location: 0, length: 0)
        var didWritePage = false
        while currentRange.location < attributed.length {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor.white)
            context.fill(pageRect)
            context.saveGState()
            context.textMatrix = .identity
            context.setAlpha(1)
            context.setFillColor(CGColor.black)

            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
            CTFrameDraw(frame, context)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            context.restoreGState()
            context.endPDFPage()
            didWritePage = true

            guard visibleRange.length > 0 else { break }
            currentRange.location += visibleRange.length
        }

        if !didWritePage {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
    }

    private func exportDOCX(_ document: DocumentIR, to url: URL) throws {
        let tempDir = try temporaryDirectory(prefix: "docx-export")
        defer { try? fileManager.removeItem(at: tempDir) }

        let relsDir = tempDir.appendingPathComponent("_rels", isDirectory: true)
        let wordDir = tempDir.appendingPathComponent("word", isDirectory: true)
        let wordRelsDir = wordDir.appendingPathComponent("_rels", isDirectory: true)
        try fileManager.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: wordRelsDir, withIntermediateDirectories: true)

        try docxContentTypes().write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try docxRootRels().write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
        try docxDocumentRels().write(to: wordRelsDir.appendingPathComponent("document.xml.rels"), atomically: true, encoding: .utf8)
        try docxDocumentXML(document).write(to: wordDir.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        try zipDirectory(sourceDirectory: tempDir, outputURL: url)
    }

    private func exportODT(
        _ document: DocumentIR,
        sourceJob: DocumentJob,
        outputDirectory: URL,
        options: DocumentOperationOptions,
        configuration: DocumentProcessingConfiguration
    ) throws -> URL {
        guard let soffice = Self.sofficeURL() else {
            throw DocumentProcessingError.unavailable(Self.exportUnavailableReason(for: .odt))
        }

        let tempDir = try temporaryDirectory(prefix: "odt-export")
        defer { try? fileManager.removeItem(at: tempDir) }
        let tempDocx = tempDir.appendingPathComponent(outputBaseName(sourceJob: sourceJob, options: options, configuration: configuration)).appendingPathExtension("docx")
        try exportDOCX(document, to: tempDocx)
        try runProcess(
            executable: soffice.path,
            arguments: ["--headless", "--convert-to", "odt", "--outdir", tempDir.path, tempDocx.path],
            currentDirectory: nil
        )
        let generated = tempDir.appendingPathComponent(tempDocx.deletingPathExtension().lastPathComponent).appendingPathExtension("odt")
        guard fileManager.fileExists(atPath: generated.path) else {
            throw DocumentProcessingError.exportFailed(String(localized: "document.error.odtConvertFailed", bundle: .module))
        }
        let outputURL = try uniqueOutputURL(for: sourceJob, in: outputDirectory, format: .odt, options: options, configuration: configuration)
        try fileManager.moveItem(at: generated, to: outputURL)
        return outputURL
    }

    private func uniqueOutputURL(
        for sourceJob: DocumentJob,
        in directory: URL,
        format: DocumentExportFormat,
        options: DocumentOperationOptions,
        configuration: DocumentProcessingConfiguration
    ) throws -> URL {
        try uniqueOutputURL(
            basename: outputBaseName(sourceJob: sourceJob, options: options, configuration: configuration),
            extension: format.fileExtension,
            in: directory
        )
    }

    private func uniqueOutputURL(basename: String, extension ext: String, in directory: URL) throws -> URL {
        let sanitizedBase = sanitizeFilename(basename.isEmpty ? "export" : basename)
        var candidate = directory.appendingPathComponent(sanitizedBase).appendingPathExtension(ext)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(sanitizedBase)-\(index)").appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }

    private func outputBaseName(
        sourceJob: DocumentJob,
        options: DocumentOperationOptions,
        configuration: DocumentProcessingConfiguration
    ) -> String {
        var parts = [sourceJob.sourceURL.deletingPathExtension().lastPathComponent]
        guard options.nameOptions.customizeName else {
            return parts[0]
        }
        if options.nameOptions.appendTimestamp {
            parts.append(Self.timestampFormatter.string(from: Date()))
        }
        if options.nameOptions.appendTargetLanguage, options.shouldTranslate {
            parts.append(configuration.targetLanguage.rawValue)
        }
        let suffix = options.nameOptions.customSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !suffix.isEmpty {
            parts.append(suffix)
        }
        return parts.joined(separator: "-")
    }

    private func relativeDirectoryForOutput(sourceJob: DocumentJob) -> String {
        guard let rootURL = sourceJob.rootURL else { return "" }
        let sourceDirectory = sourceJob.sourceURL.deletingLastPathComponent()
        let rootPath = rootURL.standardizedFileURL.path
        let sourcePath = sourceDirectory.standardizedFileURL.path
        guard sourcePath.hasPrefix(rootPath) else { return "" }
        let suffix = String(sourcePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return suffix
    }

    private func paragraphs(from text: String) -> [DocumentIR.Block] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized.components(separatedBy: "\n\n")
        let paragraphs = parts.isEmpty ? [normalized] : parts
        return paragraphs.map { .paragraph($0.trimmingCharacters(in: .newlines)) }
    }

    private func shouldProcessTableCell(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("=") else { return false }
        if Double(trimmed.replacingOccurrences(of: ",", with: ".")) != nil {
            return false
        }
        return trimmed.rangeOfCharacter(from: .letters) != nil
    }

    private func renderMarkdown(_ document: DocumentIR) -> String {
        document.blocks.map { block in
            switch block {
            case .paragraph(let text):
                return text
            case .table(let rows):
                return renderMarkdownTable(rows)
            }
        }.joined(separator: "\n\n")
    }

    private func renderMarkdownTable(_ rows: [[String]]) -> String {
        guard let first = rows.first else { return "" }
        let header = "| " + first.map(escapeMarkdownCell).joined(separator: " | ") + " |"
        let separator = "| " + first.map { _ in "---" }.joined(separator: " | ") + " |"
        let body = rows.dropFirst().map { "| " + $0.map(escapeMarkdownCell).joined(separator: " | ") + " |" }
        return ([header, separator] + body).joined(separator: "\n")
    }

    private func renderHTML(_ document: DocumentIR) -> String {
        let body = document.blocks.map { block in
            switch block {
            case .paragraph(let text):
                return "<p>\(escapeHTML(text).replacingOccurrences(of: "\n", with: "<br>"))</p>"
            case .table(let rows):
                let renderedRows = rows.map { row in
                    "<tr>" + row.map { "<td>\(escapeHTML($0))</td>" }.joined() + "</tr>"
                }.joined(separator: "\n")
                return "<table>\n\(renderedRows)\n</table>"
            }
        }.joined(separator: "\n")
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; line-height: 1.45; }
        table { border-collapse: collapse; margin: 1em 0; }
        td, th { border: 1px solid #999; padding: 4px 8px; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private func renderAsciiDoc(_ document: DocumentIR, includeImageLinks: Bool) -> String {
        var chunks: [String] = []
        for block in document.blocks {
            switch block {
            case .paragraph(let text):
                chunks.append(text)
            case .table(let rows):
                let table = ["|===", rows.map { "| " + $0.joined(separator: " | ") }.joined(separator: "\n"), "|==="]
                chunks.append(table.joined(separator: "\n"))
            }
        }
        if includeImageLinks {
            for image in document.images {
                chunks.append("image::images/\(image.suggestedFilename)[]")
            }
        }
        return chunks.joined(separator: "\n\n")
    }

    private func docxDocumentXML(_ document: DocumentIR) -> String {
        let body = document.blocks.map { block in
            switch block {
            case .paragraph(let text):
                return docxParagraphXML(text)
            case .table(let rows):
                let renderedRows = rows.map { row in
                    let cells = row.map { cell in
                        "<w:tc>\(docxParagraphXML(cell))</w:tc>"
                    }.joined()
                    return "<w:tr>\(cells)</w:tr>"
                }.joined()
                return "<w:tbl>\(renderedRows)</w:tbl>"
            }
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
        \(body)
        <w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
        </w:body>
        </w:document>
        """
    }

    private func docxParagraphXML(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let content = lines.enumerated().map { index, line in
            let breakXML = index == 0 ? "" : "<w:br/>"
            return "\(breakXML)<w:t xml:space=\"preserve\">\(escapeXML(line))</w:t>"
        }.joined()
        return "<w:p><w:r>\(content)</w:r></w:p>"
    }

    private func docxContentTypes() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """
    }

    private func docxRootRels() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
    }

    private func docxDocumentRels() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
        """
    }

    private func parseDelimited(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var insideQuotes = false
        var iterator = text.makeIterator()

        while let char = iterator.next() {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == delimiter, !insideQuotes {
                row.append(field)
                field = ""
            } else if char == "\n", !insideQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if char != "\r" {
                field.append(char)
            }
        }
        row.append(field)
        if !row.allSatisfy({ $0.isEmpty }) {
            rows.append(row)
        }
        return rows
    }

    private func unzipEntryList(path: String) throws -> [String] {
        let output = try runProcess(executable: "/usr/bin/unzip", arguments: ["-Z1", path], currentDirectory: nil)
        return output.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    private func unzipString(path: String, entry: String) throws -> String {
        let data = try unzipData(path: path, entry: entry)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DocumentProcessingError.extractionFailed(String(localized: "document.error.encodingFailed", bundle: .module))
        }
        return text
    }

    private func unzipData(path: String, entry: String) throws -> Data {
        try runProcessData(executable: "/usr/bin/unzip", arguments: ["-p", path, entry], currentDirectory: nil)
    }

    private func zipDirectory(sourceDirectory: URL, outputURL: URL) throws {
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        try runProcess(
            executable: "/usr/bin/zip",
            arguments: ["-qr", outputURL.path, "."],
            currentDirectory: sourceDirectory
        )
    }

    @discardableResult
    private func runProcess(executable: String, arguments: [String], currentDirectory: URL?) throws -> String {
        let data = try runProcessData(executable: executable, arguments: arguments, currentDirectory: currentDirectory)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func runProcessData(executable: String, arguments: [String], currentDirectory: URL?) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? ""
            throw DocumentProcessingError.exportFailed(errorText.isEmpty ? String(localized: "document.error.processFailed", bundle: .module) : errorText)
        }
        return output
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func wrap(_ line: String, maxCharacters: Int) -> [String] {
        guard line.count > maxCharacters else { return [line] }
        var result: [String] = []
        var current = ""
        for word in line.split(separator: " ") {
            if current.count + word.count + 1 > maxCharacters {
                result.append(current)
                current = String(word)
            } else {
                current += current.isEmpty ? String(word) : " \(word)"
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private func textDrawingString(_ value: String) -> NSString {
        value as NSString
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeXML(_ value: String) -> String {
        escapeHTML(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func escapeMarkdownCell(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }

    private func sanitizeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return value.components(separatedBy: invalid).joined(separator: "-")
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func executableExists(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    private static func sofficeURL() -> URL? {
        let candidates = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/usr/local/bin/soffice",
            "/opt/homebrew/bin/soffice",
        ]
        return candidates.first(where: { executableExists($0) }).map(URL.init(fileURLWithPath:))
    }

    private static func canSafelyExportPages() -> Bool {
        false
    }

    private static func canSafelyExportNumbers() -> Bool {
        false
    }

    private static func exportUnavailableReason(for format: DocumentExportFormat) -> String {
        switch format {
        case .odt:
            return String(localized: "document.error.odtUnavailable", bundle: .module)
        case .pages:
            return String(localized: "document.error.pagesUnavailable", bundle: .module)
        case .numbers:
            return String(localized: "document.error.numbersUnavailable", bundle: .module)
        default:
            return String(localized: "document.error.exportUnavailable", bundle: .module)
        }
    }
}

private final class DOCXDocumentParser: NSObject, XMLParserDelegate {
    private var blocks: [DocumentIR.Block] = []
    private var paragraphText = ""
    private var cellText = ""
    private var currentRow: [String] = []
    private var currentTable: [[String]] = []
    private var currentText = ""
    private var isInText = false
    private var isInTable = false
    private var isInCell = false

    static func parse(_ xml: String) -> [DocumentIR.Block] {
        let parser = DOCXDocumentParser()
        guard let data = xml.data(using: .utf8) else { return [] }
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        parser.flushParagraph()
        return parser.blocks
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch localName(elementName) {
        case "tbl":
            flushParagraph()
            isInTable = true
            currentTable = []
        case "tr":
            currentRow = []
        case "tc":
            isInCell = true
            cellText = ""
        case "t":
            isInText = true
            currentText = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInText else { return }
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch localName(elementName) {
        case "t":
            if isInCell {
                cellText += currentText
            } else {
                paragraphText += currentText
            }
            isInText = false
            currentText = ""
        case "p":
            if !isInCell {
                flushParagraph()
            }
        case "tc":
            currentRow.append(cellText.trimmingCharacters(in: .whitespacesAndNewlines))
            cellText = ""
            isInCell = false
        case "tr":
            if !currentRow.isEmpty {
                currentTable.append(currentRow)
            }
            currentRow = []
        case "tbl":
            if !currentTable.isEmpty {
                blocks.append(.table(currentTable))
            }
            currentTable = []
            isInTable = false
        default:
            break
        }
    }

    private func flushParagraph() {
        let trimmed = paragraphText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            blocks.append(.paragraph(trimmed))
        }
        paragraphText = ""
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}

private final class XLSXSharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var isInText = false

    static func parse(_ xml: String) -> [String] {
        let parser = XLSXSharedStringsParser()
        guard let data = xml.data(using: .utf8) else { return [] }
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if localName(elementName) == "t" {
            isInText = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInText else { return }
        current += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch localName(elementName) {
        case "t":
            isInText = false
        case "si":
            strings.append(current)
            current = ""
        default:
            break
        }
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}

private final class XLSXSheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var rows: [[String]] = []
    private var currentRow: [Int: String] = [:]
    private var currentCellReference = ""
    private var currentCellType = ""
    private var currentValue = ""
    private var isInValue = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    static func parse(_ xml: String, sharedStrings: [String]) -> [[String]] {
        let parser = XLSXSheetParser(sharedStrings: sharedStrings)
        guard let data = xml.data(using: .utf8) else { return [] }
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.rows
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch localName(elementName) {
        case "row":
            currentRow = [:]
        case "c":
            currentCellReference = attributeDict["r"] ?? ""
            currentCellType = attributeDict["t"] ?? ""
            currentValue = ""
        case "v", "t":
            isInValue = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInValue else { return }
        currentValue += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch localName(elementName) {
        case "v", "t":
            isInValue = false
        case "c":
            let column = columnIndex(from: currentCellReference)
            currentRow[column] = resolvedValue()
        case "row":
            guard !currentRow.isEmpty else { return }
            let maxColumn = currentRow.keys.max() ?? 0
            rows.append((0 ... maxColumn).map { currentRow[$0] ?? "" })
        default:
            break
        }
    }

    private func resolvedValue() -> String {
        if currentCellType == "s",
           let index = Int(currentValue),
           sharedStrings.indices.contains(index)
        {
            return sharedStrings[index]
        }
        return currentValue
    }

    private func columnIndex(from reference: String) -> Int {
        let letters = reference.prefix { $0.isLetter }
        var value = 0
        for char in letters {
            guard let scalar = char.unicodeScalars.first else { continue }
            value = value * 26 + Int(scalar.value - UnicodeScalar("A").value + 1)
        }
        return max(value - 1, 0)
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}
