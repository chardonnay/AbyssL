import AppKit
import Foundation

enum TranslationCaptureModifier: String, CaseIterable, Identifiable, Sendable {
    case control
    case option
    case command
    case shift

    var id: String { rawValue }

    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .control:
            return .control
        case .option:
            return .option
        case .command:
            return .command
        case .shift:
            return .shift
        }
    }

    var cgEventFlag: CGEventFlags {
        switch self {
        case .control:
            return .maskControl
        case .option:
            return .maskAlternate
        case .command:
            return .maskCommand
        case .shift:
            return .maskShift
        }
    }

    var localizationKey: String {
        switch self {
        case .control:
            return "settings.captureShortcut.modifier.control"
        case .option:
            return "settings.captureShortcut.modifier.option"
        case .command:
            return "settings.captureShortcut.modifier.command"
        case .shift:
            return "settings.captureShortcut.modifier.shift"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .control:
            return "Ctrl"
        case .option:
            return "Option"
        case .command:
            return "Command"
        case .shift:
            return "Shift"
        }
    }
}

struct TranslationCaptureShortcut: Equatable, Sendable {
    static let defaultKey = "c"
    static let `default` = TranslationCaptureShortcut(modifier: .control, key: defaultKey)

    var modifier: TranslationCaptureModifier
    var key: String

    var normalizedKey: String {
        Self.normalizedKey(key)
    }

    var displayName: String {
        let keyName = normalizedKey.uppercased()
        return "\(modifier.shortDisplayName)+\(keyName)+\(keyName)"
    }

    static func normalizedKey(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalar = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .first { allowed.contains($0) }
        return scalar.map { String($0).lowercased() } ?? defaultKey
    }
}
