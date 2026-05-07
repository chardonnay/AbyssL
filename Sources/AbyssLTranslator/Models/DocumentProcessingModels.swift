import AppKit
import Foundation

enum DocumentExportFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf
    case docx
    case odt
    case markdown
    case html
    case asciidoc
    case plainText
    case rtf
    case pages
    case numbers

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .pdf:
            return "document.format.pdf"
        case .docx:
            return "document.format.docx"
        case .odt:
            return "document.format.odt"
        case .markdown:
            return "document.format.markdown"
        case .html:
            return "document.format.html"
        case .asciidoc:
            return "document.format.asciidoc"
        case .plainText:
            return "document.format.plainText"
        case .rtf:
            return "document.format.rtf"
        case .pages:
            return "document.format.pages"
        case .numbers:
            return "document.format.numbers"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf:
            return "pdf"
        case .docx:
            return "docx"
        case .odt:
            return "odt"
        case .markdown:
            return "md"
        case .html:
            return "html"
        case .asciidoc:
            return "adoc"
        case .plainText:
            return "txt"
        case .rtf:
            return "rtf"
        case .pages:
            return "pages"
        case .numbers:
            return "numbers"
        }
    }

    var systemImage: String {
        switch self {
        case .pdf:
            return "doc.richtext"
        case .docx, .odt, .pages:
            return "doc.text"
        case .markdown, .html, .asciidoc:
            return "chevron.left.forwardslash.chevron.right"
        case .plainText:
            return "text.alignleft"
        case .rtf:
            return "textformat"
        case .numbers:
            return "tablecells"
        }
    }

    var supportsTables: Bool {
        switch self {
        case .docx, .html, .markdown, .asciidoc, .numbers:
            return true
        case .pdf, .odt, .plainText, .rtf, .pages:
            return false
        }
    }
}

enum DocumentInputKind: String, Sendable {
    case plainText
    case markdown
    case asciidoc
    case html
    case rtf
    case pdf
    case docx
    case odt
    case csv
    case tsv
    case xlsx
    case pages
    case numbers
    case unsupported

    var isSpreadsheet: Bool {
        switch self {
        case .csv, .tsv, .xlsx, .numbers:
            return true
        default:
            return false
        }
    }
}

struct DocumentNameOptions: Equatable, Sendable {
    var customizeName = false
    var appendTimestamp = false
    var appendTargetLanguage = false
    var customSuffix = ""
}

struct DocumentOperationOptions: Equatable, Sendable {
    var shouldCorrect = true
    var shouldTranslate = true
    var instruction = ""
    var exportFormat: DocumentExportFormat = .pdf
    var exportImagesForAsciiDoc = false
    var nameOptions = DocumentNameOptions()
}

struct DocumentJob: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceURL: URL
    let rootURL: URL?
    let inputKind: DocumentInputKind
    var statusMessage: String?

    init(sourceURL: URL, rootURL: URL?, inputKind: DocumentInputKind, statusMessage: String? = nil) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.rootURL = rootURL
        self.inputKind = inputKind
        self.statusMessage = statusMessage
    }

    var displayName: String {
        sourceURL.lastPathComponent
    }
}

struct DocumentBatchProgress: Equatable, Sendable {
    var total: Int = 0
    var completed: Int = 0
    var currentFile: String?
    var startedAt: Date?
    var finishedAt: Date?
    var isRunning = false

    var remaining: Int {
        max(total - completed, 0)
    }

    var elapsedSeconds: Int {
        guard let startedAt else { return 0 }
        let endDate = finishedAt ?? Date()
        return max(Int(endDate.timeIntervalSince(startedAt)), 0)
    }
}

struct DocumentProcessingResult: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case success
        case skipped
        case failed
    }

    let id: UUID
    var sourceURL: URL
    var outputURL: URL?
    var status: Status
    var message: String

    init(sourceURL: URL, outputURL: URL?, status: Status, message: String) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.status = status
        self.message = message
    }
}

struct DocumentIR: Sendable {
    struct ImageAsset: Identifiable, Sendable {
        let id: String
        let suggestedFilename: String
        let data: Data
    }

    enum Block: Sendable {
        case paragraph(String)
        case table([[String]])
    }

    var blocks: [Block]
    var images: [ImageAsset]
    var sourceKind: DocumentInputKind

    var plainText: String {
        blocks.map { block in
            switch block {
            case .paragraph(let text):
                return text
            case .table(let rows):
                return rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
            }
        }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n\n")
    }

    var isSpreadsheet: Bool {
        sourceKind.isSpreadsheet
    }
}

struct DocumentProcessingConfiguration: Sendable {
    var provider: TranslationProvider
    var selectedModel: OpenAIModel
    var localModel: String
    var sourceLanguage: TranslationLanguage
    var targetLanguage: TranslationLanguage
    var style: StyleSettings
    var reasoningEnabled: Bool
    var reasoningEffort: String
    var apiKey: String
    var localApiKey: String
    var openAIBaseURL: URL
    var localBaseURL: URL
    var localRequestTimeoutSeconds: Int
    var correctionAlternativeCount: Int
}
