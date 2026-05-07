import Foundation

enum TranslationProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case openAI
    case localLLM

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .openAI:
            return "provider.openai"
        case .localLLM:
            return "provider.local"
        }
    }
}
