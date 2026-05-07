import Foundation

enum MainWorkspaceMode: String, CaseIterable, Identifiable {
    case translator
    case correction
    case document

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .translator:
            return "mode.translator"
        case .correction:
            return "mode.correction"
        case .document:
            return "mode.document"
        }
    }

    var systemImage: String {
        switch self {
        case .translator:
            return "globe"
        case .correction:
            return "text.badge.checkmark"
        case .document:
            return "doc.text.magnifyingglass"
        }
    }
}

enum WritingStylePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case standard
    case formal
    case concise

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .standard:
            return "writing.style.standard"
        case .formal:
            return "writing.style.formal"
        case .concise:
            return "writing.style.concise"
        }
    }

    var promptInstruction: String {
        switch self {
        case .standard:
            return "Style: preserve the author's original register and flow while making the wording clear and natural."
        case .formal:
            return "Style: rewrite in a formal, professional register suitable for business communication."
        case .concise:
            return "Style: rewrite concisely with shorter sentences and no unnecessary filler, while preserving meaning."
        }
    }
}

struct CorrectionTextRange: Equatable, Sendable {
    var location: Int
    var length: Int

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }

    init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    init(nsRange: NSRange) {
        self.location = nsRange.location
        self.length = nsRange.length
    }
}

struct WritingCorrectionIssue: Identifiable, Equatable, Sendable {
    var id: UUID
    var originalText: String
    var correctedText: String
    var message: String
    var alternatives: [String]
    var range: CorrectionTextRange?

    init(
        id: UUID = UUID(),
        originalText: String,
        correctedText: String,
        message: String,
        alternatives: [String] = [],
        range: CorrectionTextRange? = nil
    ) {
        self.id = id
        self.originalText = originalText
        self.correctedText = correctedText
        self.message = message
        self.alternatives = alternatives
        self.range = range
    }
}

struct WritingCorrectionResult: Equatable, Sendable {
    var correctedText: String
    var issues: [WritingCorrectionIssue]
}
