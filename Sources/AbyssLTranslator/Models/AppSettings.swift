import Foundation
import SwiftUI

struct LLMProfile: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var host: String
    var port: Int
    var useHTTPS: Bool
    var model: String
    var apiKey: String
}

/// Persisted application configuration (API host, keys, defaults).
final class AppSettingsStore: ObservableObject {
    static let defaultEditorFontSize = 13.0
    static let minimumEditorFontSize = 10.0
    static let maximumEditorFontSize = 28.0
    static let minimumCorrectionAlternativeCount = 3
    static let maximumCorrectionAlternativeCount = 8
    static let defaultLocalRequestTimeoutSeconds = 600

    private let defaults: UserDefaults
    private var isApplyingLLMProfile = false

    private enum Keys {
        static let apiKey = "abyssl.apiKey"
        static let serverHost = "abyssl.serverHost"
        static let serverPort = "abyssl.serverPort"
        static let useHTTPS = "abyssl.useHTTPS"
        static let provider = "abyssl.provider"
        static let localApiKey = "abyssl.local.apiKey"
        static let localServerHost = "abyssl.local.serverHost"
        static let localServerPort = "abyssl.local.serverPort"
        static let localUseHTTPS = "abyssl.local.useHTTPS"
        static let localModel = "abyssl.local.model"
        static let localRequestTimeoutSeconds = "abyssl.local.requestTimeoutSeconds"
        static let llmProfiles = "abyssl.llmProfiles"
        static let selectedLLMProfileID = "abyssl.selectedLLMProfileID"
        static let autoTranslate = "abyssl.autoTranslate"
        static let reasoningOnValue = "abyssl.reasoningOnValue"
        static let reasoningOffValue = "abyssl.reasoningOffValue"
        static let reasoningEnabled = "abyssl.reasoningEnabled"
        static let alternativeSuggestionCount = "abyssl.alternativeSuggestionCount"
        static let correctionAlternativeCount = "abyssl.correctionAlternativeCount"
        static let editorFontSize = "abyssl.editorFontSize"
        static let captureShortcutModifier = "abyssl.captureShortcut.modifier"
        static let captureShortcutKey = "abyssl.captureShortcut.key"
        static let selectedModel = "abyssl.selectedModel"
        static let sourceLanguage = "abyssl.sourceLanguage"
        static let targetLanguage = "abyssl.targetLanguage"
        static let styleRegister = "abyssl.styleRegister"
        static let styleComplexity = "abyssl.styleComplexity"
        static let spellingMode = "abyssl.spellingMode"
    }

    @Published var apiKey: String {
        didSet { defaults.set(apiKey, forKey: Keys.apiKey) }
    }

    @Published var serverHost: String {
        didSet { defaults.set(serverHost, forKey: Keys.serverHost) }
    }

    @Published var serverPort: Int {
        didSet { defaults.set(serverPort, forKey: Keys.serverPort) }
    }

    @Published var useHTTPS: Bool {
        didSet { defaults.set(useHTTPS, forKey: Keys.useHTTPS) }
    }

    @Published var reasoningEnabled: Bool {
        didSet { defaults.set(reasoningEnabled, forKey: Keys.reasoningEnabled) }
    }

    @Published var reasoningOnValue: String {
        didSet { defaults.set(reasoningOnValue, forKey: Keys.reasoningOnValue) }
    }

    @Published var reasoningOffValue: String {
        didSet { defaults.set(reasoningOffValue, forKey: Keys.reasoningOffValue) }
    }

    @Published var autoTranslateEnabled: Bool {
        didSet { defaults.set(autoTranslateEnabled, forKey: Keys.autoTranslate) }
    }

    @Published var alternativeSuggestionCount: Int {
        didSet { defaults.set(alternativeSuggestionCount, forKey: Keys.alternativeSuggestionCount) }
    }

    @Published var correctionAlternativeCount: Int {
        didSet { defaults.set(correctionAlternativeCount, forKey: Keys.correctionAlternativeCount) }
    }

    @Published var editorFontSize: Double {
        didSet { defaults.set(editorFontSize, forKey: Keys.editorFontSize) }
    }

    @Published var captureShortcutModifier: TranslationCaptureModifier {
        didSet {
            defaults.set(captureShortcutModifier.rawValue, forKey: Keys.captureShortcutModifier)
            notifyCaptureShortcutChanged()
        }
    }

    @Published var captureShortcutKey: String {
        didSet {
            let normalized = TranslationCaptureShortcut.normalizedKey(captureShortcutKey)
            guard normalized == captureShortcutKey else {
                captureShortcutKey = normalized
                return
            }
            defaults.set(captureShortcutKey, forKey: Keys.captureShortcutKey)
            notifyCaptureShortcutChanged()
        }
    }

    @Published var selectedProvider: TranslationProvider {
        didSet { defaults.set(selectedProvider.rawValue, forKey: Keys.provider) }
    }

    @Published var selectedModel: OpenAIModel {
        didSet { defaults.set(selectedModel.rawValue, forKey: Keys.selectedModel) }
    }

    @Published var localModel: String {
        didSet {
            defaults.set(localModel, forKey: Keys.localModel)
            syncSelectedLLMProfile { $0.model = localModel }
        }
    }

    @Published var localApiKey: String {
        didSet {
            defaults.set(localApiKey, forKey: Keys.localApiKey)
            syncSelectedLLMProfile { $0.apiKey = localApiKey }
        }
    }

    @Published var localServerHost: String {
        didSet {
            defaults.set(localServerHost, forKey: Keys.localServerHost)
            syncSelectedLLMProfile { $0.host = localServerHost }
        }
    }

    @Published var localServerPort: Int {
        didSet {
            defaults.set(localServerPort, forKey: Keys.localServerPort)
            syncSelectedLLMProfile { $0.port = localServerPort }
        }
    }

    @Published var localUseHTTPS: Bool {
        didSet {
            defaults.set(localUseHTTPS, forKey: Keys.localUseHTTPS)
            syncSelectedLLMProfile { $0.useHTTPS = localUseHTTPS }
        }
    }

    @Published var localRequestTimeoutSeconds: Int {
        didSet {
            let clamped = Self.clampedLocalRequestTimeoutSeconds(localRequestTimeoutSeconds)
            guard clamped == localRequestTimeoutSeconds else {
                localRequestTimeoutSeconds = clamped
                return
            }
            defaults.set(localRequestTimeoutSeconds, forKey: Keys.localRequestTimeoutSeconds)
        }
    }

    @Published var llmProfiles: [LLMProfile] {
        didSet { persistLLMProfiles() }
    }

    @Published var selectedLLMProfileID: String {
        didSet {
            defaults.set(selectedLLMProfileID, forKey: Keys.selectedLLMProfileID)
            applySelectedLLMProfile()
        }
    }

    @Published var sourceLanguage: TranslationLanguage {
        didSet { defaults.set(sourceLanguage.rawValue, forKey: Keys.sourceLanguage) }
    }

    @Published var targetLanguage: TranslationLanguage {
        didSet { defaults.set(targetLanguage.rawValue, forKey: Keys.targetLanguage) }
    }

    @Published var styleRegister: RegisterStyle {
        didSet { defaults.set(styleRegister.rawValue, forKey: Keys.styleRegister) }
    }

    @Published var styleComplexity: ComplexityStyle {
        didSet { defaults.set(styleComplexity.rawValue, forKey: Keys.styleComplexity) }
    }

    @Published var spellingMode: SpellingMode {
        didSet { defaults.set(spellingMode.rawValue, forKey: Keys.spellingMode) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.apiKey = defaults.string(forKey: Keys.apiKey) ?? ""

        let host = defaults.string(forKey: Keys.serverHost)
        self.serverHost = (host?.isEmpty == false) ? host! : "api.openai.com"

        let storedPort = defaults.object(forKey: Keys.serverPort) as? Int
        self.serverPort = storedPort ?? 443

        if defaults.object(forKey: Keys.useHTTPS) == nil {
            self.useHTTPS = true
        } else {
            self.useHTTPS = defaults.bool(forKey: Keys.useHTTPS)
        }

        if let raw = defaults.string(forKey: Keys.provider),
           let provider = TranslationProvider(rawValue: raw)
        {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .openAI
        }

        let resolvedLocalApiKey = defaults.string(forKey: Keys.localApiKey) ?? ""
        self.localApiKey = resolvedLocalApiKey
        let localHost = defaults.string(forKey: Keys.localServerHost)
        let resolvedLocalHost = (localHost?.isEmpty == false) ? localHost! : "localhost"
        self.localServerHost = resolvedLocalHost
        let resolvedLocalPort = (defaults.object(forKey: Keys.localServerPort) as? Int) ?? 11434
        self.localServerPort = resolvedLocalPort
        let resolvedLocalUseHTTPS: Bool
        if defaults.object(forKey: Keys.localUseHTTPS) == nil {
            resolvedLocalUseHTTPS = false
        } else {
            resolvedLocalUseHTTPS = defaults.bool(forKey: Keys.localUseHTTPS)
        }
        self.localUseHTTPS = resolvedLocalUseHTTPS
        let resolvedLocalModel = defaults.string(forKey: Keys.localModel)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.localModel = resolvedLocalModel
        let storedLocalRequestTimeoutSeconds = defaults.object(forKey: Keys.localRequestTimeoutSeconds) as? Int
        self.localRequestTimeoutSeconds = Self.clampedLocalRequestTimeoutSeconds(
            storedLocalRequestTimeoutSeconds ?? Self.defaultLocalRequestTimeoutSeconds
        )

        let fallbackProfile = LLMProfile(
            id: UUID().uuidString,
            name: "Default",
            host: resolvedLocalHost,
            port: resolvedLocalPort,
            useHTTPS: resolvedLocalUseHTTPS,
            model: resolvedLocalModel,
            apiKey: resolvedLocalApiKey
        )
        let savedProfiles = Self.loadLLMProfiles(defaults: defaults)
        let resolvedProfiles = savedProfiles.isEmpty ? [fallbackProfile] : savedProfiles
        self.llmProfiles = resolvedProfiles
        let savedProfileID = defaults.string(forKey: Keys.selectedLLMProfileID)
        if let savedProfileID,
           resolvedProfiles.contains(where: { $0.id == savedProfileID })
        {
            self.selectedLLMProfileID = savedProfileID
        } else {
            self.selectedLLMProfileID = resolvedProfiles[0].id
        }

        if defaults.object(forKey: Keys.autoTranslate) == nil {
            self.autoTranslateEnabled = true
        } else {
            self.autoTranslateEnabled = defaults.bool(forKey: Keys.autoTranslate)
        }

        let storedAlternativeSuggestionCount = defaults.object(forKey: Keys.alternativeSuggestionCount) as? Int
        self.alternativeSuggestionCount = min(max(storedAlternativeSuggestionCount ?? 3, 1), 8)
        let storedCorrectionAlternativeCount = defaults.object(forKey: Keys.correctionAlternativeCount) as? Int
        self.correctionAlternativeCount = Self.clampedCorrectionAlternativeCount(storedCorrectionAlternativeCount ?? 3)
        let storedEditorFontSize: Double
        if defaults.object(forKey: Keys.editorFontSize) == nil {
            storedEditorFontSize = Self.defaultEditorFontSize
        } else {
            storedEditorFontSize = defaults.double(forKey: Keys.editorFontSize)
        }
        self.editorFontSize = Self.clampedEditorFontSize(storedEditorFontSize)

        if let raw = defaults.string(forKey: Keys.captureShortcutModifier),
           let value = TranslationCaptureModifier(rawValue: raw)
        {
            self.captureShortcutModifier = value
        } else {
            self.captureShortcutModifier = .control
        }
        self.captureShortcutKey = TranslationCaptureShortcut.normalizedKey(
            defaults.string(forKey: Keys.captureShortcutKey) ?? TranslationCaptureShortcut.defaultKey
        )

        let storedReasoningOn = defaults.string(forKey: Keys.reasoningOnValue)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reasoningOnValue = (storedReasoningOn?.isEmpty == false) ? storedReasoningOn! : "low"
        let storedReasoningOff = defaults.string(forKey: Keys.reasoningOffValue)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reasoningOffValue = (storedReasoningOff?.isEmpty == false) ? storedReasoningOff! : "none"

        self.reasoningEnabled = defaults.bool(forKey: Keys.reasoningEnabled)

        if let raw = defaults.string(forKey: Keys.selectedModel),
           let model = OpenAIModel(rawValue: raw)
        {
            self.selectedModel = model
        } else {
            self.selectedModel = .gpt4oMini
        }

        if let raw = defaults.string(forKey: Keys.sourceLanguage),
           let lang = TranslationLanguage(rawValue: raw)
        {
            self.sourceLanguage = lang
        } else {
            self.sourceLanguage = .automatic
        }

        if let raw = defaults.string(forKey: Keys.targetLanguage),
           let lang = TranslationLanguage(rawValue: raw)
        {
            self.targetLanguage = lang
        } else {
            self.targetLanguage = .englishUS
        }

        if let raw = defaults.string(forKey: Keys.styleRegister),
           let value = RegisterStyle(rawValue: raw)
        {
            self.styleRegister = value
        } else {
            self.styleRegister = .neutral
        }

        if let raw = defaults.string(forKey: Keys.styleComplexity),
           let value = ComplexityStyle(rawValue: raw)
        {
            self.styleComplexity = value
        } else {
            self.styleComplexity = .neutral
        }

        if let raw = defaults.string(forKey: Keys.spellingMode),
           let value = SpellingMode(rawValue: raw)
        {
            self.spellingMode = value
        } else {
            self.spellingMode = .preserve
        }

        applySelectedLLMProfile()
    }

    var selectedLLMProfile: LLMProfile? {
        llmProfiles.first { $0.id == selectedLLMProfileID }
    }

    var selectedLLMProfileName: String {
        selectedLLMProfile?.name ?? ""
    }

    var captureShortcut: TranslationCaptureShortcut {
        TranslationCaptureShortcut(modifier: captureShortcutModifier, key: captureShortcutKey)
    }

    func addLLMProfile() {
        let nextName = uniqueProfileName()
        let profile = LLMProfile(
            id: UUID().uuidString,
            name: nextName,
            host: localServerHost,
            port: localServerPort,
            useHTTPS: localUseHTTPS,
            model: localModel,
            apiKey: localApiKey
        )
        llmProfiles.append(profile)
        selectedLLMProfileID = profile.id
    }

    func deleteSelectedLLMProfile() {
        guard llmProfiles.count > 1 else { return }
        llmProfiles.removeAll { $0.id == selectedLLMProfileID }
        selectedLLMProfileID = llmProfiles[0].id
    }

    func renameSelectedLLMProfile(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = llmProfiles.firstIndex(where: { $0.id == selectedLLMProfileID })
        else {
            return
        }
        llmProfiles[index].name = trimmed
    }

    func baseURL(for provider: TranslationProvider) throws -> URL {
        let scheme = provider == .openAI ? (useHTTPS ? "https" : "http") : (localUseHTTPS ? "https" : "http")
        let host = (provider == .openAI ? serverHost : localServerHost).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw OpenAIError.invalidConfiguration(String(localized: "error.emptyHost", bundle: .module))
        }
        let port = provider == .openAI ? serverPort : localServerPort
        let defaultHTTPS = 443
        let defaultHTTP = 80
        let includePort: Bool
        if scheme == "https" {
            includePort = port != defaultHTTPS
        } else {
            includePort = port != defaultHTTP
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if includePort {
            components.port = port
        }
        guard let base = components.url else {
            throw OpenAIError.invalidConfiguration(String(localized: "error.badURL", bundle: .module))
        }
        return base
    }

    func testConnection(for provider: TranslationProvider) async throws {
        let base = try baseURL(for: provider)
        let endpoint: URL
        switch provider {
        case .openAI:
            endpoint = base.appendingPathComponent("v1").appendingPathComponent("models")
        case .localLLM:
            endpoint = base.appendingPathComponent("v1").appendingPathComponent("models")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        if provider == .openAI {
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                throw OpenAIError.invalidConfiguration(String(localized: "error.missingAPIKey", bundle: .module))
            }
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        } else {
            let key = localApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw OpenAIError.httpStatus(http.statusCode, nil)
        }
    }

    private static func loadLLMProfiles(defaults: UserDefaults) -> [LLMProfile] {
        guard let data = defaults.data(forKey: Keys.llmProfiles),
              let profiles = try? JSONDecoder().decode([LLMProfile].self, from: data)
        else {
            return []
        }
        return profiles.filter {
            !$0.id.isEmpty
                && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (1 ... 65_535).contains($0.port)
        }
    }

    private static func clampedEditorFontSize(_ value: Double) -> Double {
        min(max(value, minimumEditorFontSize), maximumEditorFontSize)
    }

    private static func clampedCorrectionAlternativeCount(_ value: Int) -> Int {
        min(max(value, minimumCorrectionAlternativeCount), maximumCorrectionAlternativeCount)
    }

    private static func clampedLocalRequestTimeoutSeconds(_ value: Int) -> Int {
        max(value, 0)
    }

    private func persistLLMProfiles() {
        if let data = try? JSONEncoder().encode(llmProfiles) {
            defaults.set(data, forKey: Keys.llmProfiles)
        }
    }

    private func applySelectedLLMProfile() {
        guard let profile = selectedLLMProfile else { return }
        isApplyingLLMProfile = true
        defer { isApplyingLLMProfile = false }

        localServerHost = profile.host
        localServerPort = profile.port
        localUseHTTPS = profile.useHTTPS
        localModel = profile.model
        localApiKey = profile.apiKey
    }

    private func syncSelectedLLMProfile(_ update: (inout LLMProfile) -> Void) {
        guard !isApplyingLLMProfile,
              let index = llmProfiles.firstIndex(where: { $0.id == selectedLLMProfileID })
        else {
            return
        }
        update(&llmProfiles[index])
    }

    private func uniqueProfileName() -> String {
        let existingNames = Set(llmProfiles.map(\.name))
        var index = llmProfiles.count + 1
        while existingNames.contains("Profile \(index)") {
            index += 1
        }
        return "Profile \(index)"
    }

    private func notifyCaptureShortcutChanged() {
        NotificationCenter.default.post(name: .abysslCaptureShortcutChanged, object: captureShortcut)
    }
}
