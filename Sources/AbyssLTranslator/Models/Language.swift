import Foundation

/// Supported translation languages for source/target pickers.
enum TranslationLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case englishUS
    case englishUK
    case german
    case french
    case spanish
    case italian
    case portuguese
    case dutch
    case polish
    case russian
    case japanese
    case korean
    case chineseSimplified
    case chineseTraditional

    var id: String { rawValue }

    /// BCP-47 / ISO-style tag sent to the model for precise locale handling.
    var localeTag: String {
        switch self {
        case .automatic:
            return "auto"
        case .englishUS:
            return "en-US"
        case .englishUK:
            return "en-GB"
        case .german:
            return "de-DE"
        case .french:
            return "fr-FR"
        case .spanish:
            return "es-ES"
        case .italian:
            return "it-IT"
        case .portuguese:
            return "pt-PT"
        case .dutch:
            return "nl-NL"
        case .polish:
            return "pl-PL"
        case .russian:
            return "ru-RU"
        case .japanese:
            return "ja-JP"
        case .korean:
            return "ko-KR"
        case .chineseSimplified:
            return "zh-Hans"
        case .chineseTraditional:
            return "zh-Hant"
        }
    }

    var displayNameKey: String {
        switch self {
        case .automatic:
            return "language.automatic"
        case .englishUS:
            return "language.enUS"
        case .englishUK:
            return "language.enGB"
        case .german:
            return "language.de"
        case .french:
            return "language.fr"
        case .spanish:
            return "language.es"
        case .italian:
            return "language.it"
        case .portuguese:
            return "language.pt"
        case .dutch:
            return "language.nl"
        case .polish:
            return "language.pl"
        case .russian:
            return "language.ru"
        case .japanese:
            return "language.ja"
        case .korean:
            return "language.ko"
        case .chineseSimplified:
            return "language.zhHans"
        case .chineseTraditional:
            return "language.zhHant"
        }
    }
}
