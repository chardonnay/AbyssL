import Foundation

/// Register tone and complexity used in prompts.
struct StyleSettings: Codable, Equatable, Sendable {
    var register: RegisterStyle
    var complexity: ComplexityStyle
    var spellingMode: SpellingMode

    static let `default` = StyleSettings(
        register: .neutral,
        complexity: .neutral,
        spellingMode: .preserve
    )
}

enum RegisterStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case neutral
    case formal
    case informal

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .neutral:
            return "style.register.neutral"
        case .formal:
            return "style.register.formal"
        case .informal:
            return "style.register.informal"
        }
    }
}

enum ComplexityStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case neutral
    case technical
    case plain

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .neutral:
            return "style.complexity.neutral"
        case .technical:
            return "style.complexity.technical"
        case .plain:
            return "style.complexity.plain"
        }
    }
}

enum SpellingMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case preserve
    case fixSource
    case fixTarget

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .preserve:
            return "spelling.preserve"
        case .fixSource:
            return "spelling.fixSource"
        case .fixTarget:
            return "spelling.fixTarget"
        }
    }
}
