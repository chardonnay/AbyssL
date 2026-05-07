import Foundation
import SwiftUI

@MainActor
final class TranslationStatusState: ObservableObject {
    @Published var isTranslating: Bool = false
}

enum AlternativeApplicationMode {
    case selection
    case fullTarget
}

@MainActor
final class TranslationOutputState: ObservableObject {
    @Published var targetText: String = ""
    @Published var synonyms: [String] = []
    @Published var spellingNotes: String?
    @Published var revisedSourceText: String?
    @Published var lastError: String?
    @Published var selectedTargetText: String = ""
    @Published var isSuggestingAlternatives: Bool = false
    @Published var selectedAlternativeIndex: Int = 0
    @Published var alternativeApplicationMode: AlternativeApplicationMode = .selection
    @Published var lastAlternativeInstruction: String?

    /// Inserted into the target editor at the caret when selecting a synonym.
    @Published var pendingTargetInsertion: String?

    var selectedAlternative: String? {
        guard synonyms.indices.contains(selectedAlternativeIndex) else { return nil }
        return synonyms[selectedAlternativeIndex]
    }

    var canReloadAlternatives: Bool {
        if let instruction = lastAlternativeInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
           !instruction.isEmpty
        {
            switch alternativeApplicationMode {
            case .selection:
                return !selectedTargetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .fullTarget:
                return !targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        return !selectedTargetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
final class TranslationInputState: ObservableObject {
    @Published private(set) var hasSourceText: Bool = false

    func updateHasSourceText(for text: String) {
        let nextHasSourceText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasSourceText != nextHasSourceText {
            hasSourceText = nextHasSourceText
        }
    }

    func clear() {
        hasSourceText = false
    }
}

@MainActor
final class TranslationViewModel: ObservableObject {
    let input = TranslationInputState()
    let status = TranslationStatusState()
    let output = TranslationOutputState()

    @Published var sourceLanguage: TranslationLanguage = .automatic
    @Published var targetLanguage: TranslationLanguage = .englishUS
    @Published var selectedProvider: TranslationProvider
    @Published var selectedModel: OpenAIModel
    @Published var localModel: String
    @Published var autoTranslateEnabled: Bool
    @Published var reasoningOnValue: String
    @Published var reasoningOffValue: String
    @Published var reasoningEnabled: Bool
    @Published var style: StyleSettings
    @Published var activeMode: MainWorkspaceMode = .translator
    @Published var correctionText: String = ""
    @Published var correctionIssues: [WritingCorrectionIssue] = []
    @Published var writingInstruction: String = ""
    @Published var selectedWritingStylePreset: WritingStylePreset = .standard
    @Published var isCorrectingWriting: Bool = false
    @Published var isRewritingWriting: Bool = false
    @Published var documentJobs: [DocumentJob] = []
    @Published var documentOptions = DocumentOperationOptions()
    @Published var documentOutputDirectory: URL?
    @Published var documentProgress = DocumentBatchProgress()
    @Published var documentResults: [DocumentProcessingResult] = []
    @Published var isDocumentDropTargeted = false
    @Published var documentStatusMessage: String?

    private let openAIService: OpenAIService
    private let localLLMService: LocalLLMService
    private let documentProcessingService: DocumentProcessingService
    private let settings: AppSettingsStore
    private var sourceText: String = ""

    private var translateTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var alternativeTask: Task<Void, Never>?
    private var correctionTask: Task<Void, Never>?
    private var rewriteTask: Task<Void, Never>?
    private var documentTask: Task<Void, Never>?

    private enum ScheduleReason {
        case sourceTyping
        case languageChange
        case styleChange
        case settingsChange
        case manual
    }

    init(
        openAIService: OpenAIService = OpenAIService(),
        localLLMService: LocalLLMService = LocalLLMService(),
        settings: AppSettingsStore
    ) {
        self.openAIService = openAIService
        self.localLLMService = localLLMService
        self.documentProcessingService = DocumentProcessingService(openAIService: openAIService, localLLMService: localLLMService)
        self.settings = settings
        self.selectedProvider = settings.selectedProvider
        self.selectedModel = settings.selectedModel
        self.localModel = settings.localModel
        self.autoTranslateEnabled = settings.autoTranslateEnabled
        self.reasoningOnValue = settings.reasoningOnValue
        self.reasoningOffValue = settings.reasoningOffValue
        self.reasoningEnabled = settings.reasoningEnabled
        self.sourceLanguage = settings.sourceLanguage
        self.targetLanguage = settings.targetLanguage
        self.style = StyleSettings(
            register: settings.styleRegister,
            complexity: settings.styleComplexity,
            spellingMode: settings.spellingMode
        )
    }

    func persistLanguagesAndStyle() {
        settings.sourceLanguage = sourceLanguage
        settings.targetLanguage = targetLanguage
        settings.styleRegister = style.register
        settings.styleComplexity = style.complexity
        settings.spellingMode = style.spellingMode
        settings.selectedProvider = selectedProvider
        settings.selectedModel = selectedModel
        settings.localModel = localModel
        settings.autoTranslateEnabled = autoTranslateEnabled
        settings.reasoningOnValue = reasoningOnValue
        settings.reasoningOffValue = reasoningOffValue
        settings.reasoningEnabled = reasoningEnabled
    }

    func handleLanguageChange() {
        guard autoTranslateEnabled else { return }
        scheduleTranslate(reason: .languageChange)
    }

    func handleModelOrReasoningChange() {
        guard autoTranslateEnabled else { return }
        scheduleTranslate(reason: .settingsChange)
    }

    func handleStyleChange() {
        guard autoTranslateEnabled else { return }
        scheduleTranslate(reason: .styleChange)
    }

    func onSourceChanged(to text: String) {
        sourceText = text
        input.updateHasSourceText(for: text)
        guard autoTranslateEnabled else { return }
        scheduleTranslate(reason: .sourceTyping)
    }

    func translateNow(sourceText text: String? = nil) {
        if let text {
            onSourceChanged(to: text)
        }
        scheduleTranslate(reason: .manual, debounce: false)
    }

    var hasCorrectionText: Bool {
        !correctionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isWritingBusy: Bool {
        isCorrectingWriting || isRewritingWriting
    }

    var canRunPrimaryAction: Bool {
        switch activeMode {
        case .translator:
            return input.hasSourceText && !status.isTranslating
        case .correction:
            return hasCorrectionText && !isWritingBusy
        case .document:
            return canProcessDocuments
        }
    }

    var supportedDocumentJobs: [DocumentJob] {
        documentJobs.filter { DocumentProcessingService.isKindSupported($0.inputKind) }
    }

    var hasSpreadsheetDocumentInput: Bool {
        supportedDocumentJobs.contains { $0.inputKind.isSpreadsheet }
    }

    var availableDocumentExportFormats: [DocumentExportFormat] {
        DocumentProcessingService.availableExportFormats(hasSpreadsheetInput: hasSpreadsheetDocumentInput)
    }

    var canProcessDocuments: Bool {
        !documentProgress.isRunning
            && documentOutputDirectory != nil
            && !supportedDocumentJobs.isEmpty
            && (documentOptions.shouldCorrect || documentOptions.shouldTranslate)
            && DocumentProcessingService.canExport(documentOptions.exportFormat, hasSpreadsheetInput: hasSpreadsheetDocumentInput)
    }

    func addDocumentURLs(_ urls: [URL]) {
        let nextJobs = DocumentProcessingService.collectJobs(from: urls)
        guard !nextJobs.isEmpty else {
            documentStatusMessage = String(localized: "document.drop.empty", bundle: .module)
            return
        }

        var existing = Set(documentJobs.map(\.sourceURL.standardizedFileURL.path))
        for job in nextJobs where !existing.contains(job.sourceURL.standardizedFileURL.path) {
            documentJobs.append(job)
            existing.insert(job.sourceURL.standardizedFileURL.path)
        }
        documentResults = []
        documentStatusMessage = String(
            format: String(localized: "document.drop.summary", bundle: .module),
            nextJobs.count,
            nextJobs.filter { DocumentProcessingService.isKindSupported($0.inputKind) }.count
        )
        ensureSelectedDocumentFormatIsAvailable()
    }

    func clearDocumentJobs() {
        documentTask?.cancel()
        documentJobs = []
        documentResults = []
        documentProgress = DocumentBatchProgress()
        documentStatusMessage = nil
    }

    func removeDocumentJob(_ job: DocumentJob) {
        documentJobs.removeAll { $0.id == job.id }
        ensureSelectedDocumentFormatIsAvailable()
    }

    func setDocumentOutputDirectory(_ url: URL?) {
        documentOutputDirectory = url
    }

    func ensureSelectedDocumentFormatIsAvailable() {
        let available = availableDocumentExportFormats
        guard !available.contains(documentOptions.exportFormat),
              let fallback = available.first
        else {
            return
        }
        documentOptions.exportFormat = fallback
    }

    func startDocumentProcessing() {
        guard let outputDirectory = documentOutputDirectory else {
            documentStatusMessage = String(localized: "document.error.noOutputDirectory", bundle: .module)
            return
        }
        let jobs = documentJobs
        guard !jobs.isEmpty else { return }
        guard documentOptions.shouldCorrect || documentOptions.shouldTranslate else {
            documentStatusMessage = String(localized: "document.error.noOperation", bundle: .module)
            return
        }

        documentTask?.cancel()
        let options = documentOptions

        documentTask = Task { [weak self] in
            guard let self else { return }
            self.output.lastError = nil
            self.documentResults = []
            self.documentStatusMessage = nil
            do {
                let configuration = try self.documentProcessingConfiguration()
                let results = await self.documentProcessingService.process(
                    jobs: jobs,
                    destinationDirectory: outputDirectory,
                    options: options,
                    configuration: configuration
                ) { [weak self] progress in
                    self?.documentProgress = progress
                }
                guard !Task.isCancelled else { return }
                self.documentResults = results
                self.documentStatusMessage = String(
                    format: String(localized: "document.result.summary", bundle: .module),
                    results.filter { $0.status == .success }.count,
                    results.count
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.output.lastError = error.localizedDescription
                self.documentProgress.isRunning = false
                self.documentProgress.finishedAt = Date()
            }
        }
    }

    func cancelDocumentProcessing() {
        documentTask?.cancel()
        documentProgress.isRunning = false
        documentProgress.finishedAt = Date()
        documentStatusMessage = String(localized: "document.result.cancelled", bundle: .module)
    }

    func correctWritingNow() {
        let textSnapshot = correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textSnapshot.isEmpty else { return }

        correctionTask?.cancel()
        rewriteTask?.cancel()
        let sourceLang = sourceLanguage
        let providerSnapshot = selectedProvider
        let modelSnapshot = selectedModel
        let localModelSnapshot = localModel
        let instructionSnapshot = writingInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let correctionAlternativeCount = min(
            max(settings.correctionAlternativeCount, AppSettingsStore.minimumCorrectionAlternativeCount),
            AppSettingsStore.maximumCorrectionAlternativeCount
        )
        let reasoningSnapshot = currentReasoningSnapshot()

        correctionTask = Task { [weak self] in
            guard let self else { return }
            self.isCorrectingWriting = true
            self.status.isTranslating = true
            self.output.lastError = nil
            defer {
                self.isCorrectingWriting = false
                self.status.isTranslating = false
            }

            do {
                let result: WritingCorrectionResult
                switch providerSnapshot {
                case .openAI:
                    let baseURL = try self.settings.baseURL(for: .openAI)
                    result = try await self.openAIService.correctWriting(
                        text: textSnapshot,
                        instruction: instructionSnapshot,
                        alternativeCount: correctionAlternativeCount,
                        source: sourceLang,
                        model: modelSnapshot,
                        reasoning: reasoningSnapshot.enabled,
                        reasoningEffort: reasoningSnapshot.effort,
                        apiKey: self.settings.apiKey,
                        baseURL: baseURL
                    )
                case .localLLM:
                    let baseURL = try self.settings.baseURL(for: .localLLM)
                    result = try await self.localLLMService.correctWriting(
                        text: textSnapshot,
                        instruction: instructionSnapshot,
                        alternativeCount: correctionAlternativeCount,
                        source: sourceLang,
                        model: localModelSnapshot,
                        reasoning: reasoningSnapshot.enabled,
                        reasoningEffort: reasoningSnapshot.effort,
                        apiKey: self.settings.localApiKey,
                        baseURL: baseURL,
                        timeoutSeconds: self.settings.localRequestTimeoutSeconds
                    )
                }

                guard !Task.isCancelled else { return }
                self.correctionText = result.correctedText
                self.correctionIssues = Self.issuesWithRanges(result.issues, in: result.correctedText)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.output.lastError = error.localizedDescription
            }
        }
    }

    func rewriteCorrectionText() {
        let textSnapshot = correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textSnapshot.isEmpty else { return }

        rewriteTask?.cancel()
        correctionTask?.cancel()
        let sourceLang = sourceLanguage
        let preset = selectedWritingStylePreset
        let providerSnapshot = selectedProvider
        let modelSnapshot = selectedModel
        let localModelSnapshot = localModel
        let instructionSnapshot = writingInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoningSnapshot = currentReasoningSnapshot()

        rewriteTask = Task { [weak self] in
            guard let self else { return }
            self.isRewritingWriting = true
            self.status.isTranslating = true
            self.output.lastError = nil
            defer {
                self.isRewritingWriting = false
                self.status.isTranslating = false
            }

            do {
                let rewritten: String
                switch providerSnapshot {
                case .openAI:
                    let baseURL = try self.settings.baseURL(for: .openAI)
                    rewritten = try await self.openAIService.rewriteWriting(
                        text: textSnapshot,
                        instruction: instructionSnapshot,
                        stylePreset: preset,
                        source: sourceLang,
                        model: modelSnapshot,
                        reasoning: reasoningSnapshot.enabled,
                        reasoningEffort: reasoningSnapshot.effort,
                        apiKey: self.settings.apiKey,
                        baseURL: baseURL
                    )
                case .localLLM:
                    let baseURL = try self.settings.baseURL(for: .localLLM)
                    rewritten = try await self.localLLMService.rewriteWriting(
                        text: textSnapshot,
                        instruction: instructionSnapshot,
                        stylePreset: preset,
                        source: sourceLang,
                        model: localModelSnapshot,
                        reasoning: reasoningSnapshot.enabled,
                        reasoningEffort: reasoningSnapshot.effort,
                        apiKey: self.settings.localApiKey,
                        baseURL: baseURL,
                        timeoutSeconds: self.settings.localRequestTimeoutSeconds
                    )
                }

                guard !Task.isCancelled else { return }
                self.correctionText = rewritten
                self.correctionIssues = []
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.output.lastError = error.localizedDescription
            }
        }
    }

    func clearCorrectionContent() {
        correctionTask?.cancel()
        rewriteTask?.cancel()
        correctionText = ""
        correctionIssues = []
        isCorrectingWriting = false
        isRewritingWriting = false
        output.lastError = nil
        status.isTranslating = false
    }

    func applySynonym(_ synonym: String) {
        let trimmed = synonym.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch output.alternativeApplicationMode {
        case .selection:
            output.pendingTargetInsertion = trimmed
        case .fullTarget:
            output.targetText = trimmed
            output.selectedTargetText = ""
        }
    }

    func selectPreviousAlternative() {
        guard !output.synonyms.isEmpty else { return }
        output.selectedAlternativeIndex = (output.selectedAlternativeIndex - 1 + output.synonyms.count) % output.synonyms.count
    }

    func selectNextAlternative() {
        guard !output.synonyms.isEmpty else { return }
        output.selectedAlternativeIndex = (output.selectedAlternativeIndex + 1) % output.synonyms.count
    }

    func suggestAlternativesForSelectedTarget() {
        startAlternativeSuggestion(userInstruction: nil)
    }

    func suggestAlternativesForSelectedTarget(userInstruction: String) {
        startAlternativeSuggestion(userInstruction: userInstruction, allowFullTargetFallback: true)
    }

    func reloadAlternatives() {
        if let instruction = output.lastAlternativeInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
           !instruction.isEmpty
        {
            startAlternativeSuggestion(
                userInstruction: instruction,
                allowFullTargetFallback: output.alternativeApplicationMode == .fullTarget
            )
        } else {
            startAlternativeSuggestion(userInstruction: nil)
        }
    }

    private func startAlternativeSuggestion(userInstruction: String?, allowFullTargetFallback: Bool = false) {
        let trimmedInstruction = userInstruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedText = output.selectedTargetText.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetContext = output.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetContext.isEmpty else { return }

        let focusText: String
        let applicationMode: AlternativeApplicationMode
        if selectedText.isEmpty, trimmedInstruction?.isEmpty == false, allowFullTargetFallback {
            focusText = targetContext
            applicationMode = .fullTarget
        } else {
            guard !selectedText.isEmpty else { return }
            focusText = selectedText
            applicationMode = .selection
        }

        alternativeTask?.cancel()
        let targetLang = targetLanguage
        let styleSnapshot = style
        let providerSnapshot = selectedProvider
        let modelSnapshot = selectedModel
        let localModelSnapshot = localModel
        let suggestionCount = min(max(settings.alternativeSuggestionCount, 1), 8)
        let reasoningSnapshot = currentReasoningSnapshot()

        alternativeTask = Task { [weak self] in
            guard let self else { return }
            self.output.isSuggestingAlternatives = true
            self.output.lastError = nil
            defer { self.output.isSuggestingAlternatives = false }

            do {
                let alternatives: [String]
                switch providerSnapshot {
                case .openAI:
                    let baseURL = try self.settings.baseURL(for: .openAI)
                    alternatives = try await self.openAIService.suggestAlternatives(
                        for: focusText,
                        in: targetContext,
                        userInstruction: trimmedInstruction,
                        target: targetLang,
                        style: styleSnapshot,
                        count: suggestionCount,
                        model: modelSnapshot,
                        reasoning: reasoningSnapshot.enabled,
                        reasoningEffort: reasoningSnapshot.effort,
                        apiKey: self.settings.apiKey,
                        baseURL: baseURL
                    )
                case .localLLM:
                    let baseURL = try self.settings.baseURL(for: .localLLM)
                    alternatives = try await self.localLLMService.suggestAlternatives(
                        for: focusText,
                        in: targetContext,
                        userInstruction: trimmedInstruction,
                        target: targetLang,
                        style: styleSnapshot,
                        count: suggestionCount,
                        model: localModelSnapshot,
                        reasoning: reasoningSnapshot.enabled,
                        reasoningEffort: reasoningSnapshot.effort,
                        apiKey: self.settings.localApiKey,
                        baseURL: baseURL,
                        timeoutSeconds: self.settings.localRequestTimeoutSeconds
                    )
                }

                guard !Task.isCancelled else { return }
                self.output.synonyms = alternatives
                self.output.selectedAlternativeIndex = 0
                self.output.alternativeApplicationMode = applicationMode
                self.output.lastAlternativeInstruction = trimmedInstruction
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.output.lastError = error.localizedDescription
            }
        }
    }

    func clearSourceContent() {
        translateTask?.cancel()
        debounceTask?.cancel()
        alternativeTask?.cancel()
        sourceText = ""
        input.clear()
        output.targetText = ""
        output.synonyms = []
        output.selectedAlternativeIndex = 0
        output.alternativeApplicationMode = .selection
        output.lastAlternativeInstruction = nil
        output.spellingNotes = nil
        output.revisedSourceText = nil
        output.selectedTargetText = ""
        output.isSuggestingAlternatives = false
        output.pendingTargetInsertion = nil
        output.lastError = nil
        status.isTranslating = false
    }

    func captureSelectionFromFrontApp() {
        PasteboardHelper.copyFrontmostSelectionToPasteboard()
        // Allow the system to finish updating the pasteboard.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            if let text = PasteboardHelper.stringFromPasteboard(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.sourceText = text
                self.input.updateHasSourceText(for: text)
                self.scheduleTranslate(reason: .manual, debounce: false)
            }
        }
    }

    private func scheduleTranslate(reason: ScheduleReason, debounce: Bool? = nil) {
        translateTask?.cancel()

        let shouldDebounce: Bool
        if let debounce {
            shouldDebounce = debounce
        } else {
            switch reason {
            case .sourceTyping:
                shouldDebounce = true
            case .languageChange, .styleChange, .settingsChange, .manual:
                shouldDebounce = false
            }
        }

        if shouldDebounce {
            debounceTask?.cancel()
            debounceTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 450_000_000)
                await MainActor.run {
                    self?.startTranslateTask()
                }
            }
        } else {
            startTranslateTask()
        }
    }

    private func startTranslateTask() {
        translateTask?.cancel()
        let sourceSnapshot = sourceText
        let sourceLang = sourceLanguage
        let targetLang = targetLanguage
        let styleSnapshot = style
        let providerSnapshot = selectedProvider
        let modelSnapshot = selectedModel
        let localModelSnapshot = localModel
        let reasoningSnapshot = currentReasoningSnapshot()

        translateTask = Task { [weak self] in
            guard let self else { return }
            self.status.isTranslating = true
            self.output.lastError = nil
            defer { self.status.isTranslating = false }

            do {
                let result: TranslationAIResult
                switch providerSnapshot {
                case .openAI:
                    let baseURL = try self.settings.baseURL(for: .openAI)
                    let apiKey = self.settings.apiKey
                    result = try await self.openAIService.translate(
                        text: sourceSnapshot,
                        source: sourceLang,
                        target: targetLang,
                        style: styleSnapshot,
                        model: modelSnapshot,
                        reasoning: reasoningSnapshot.enabled,
                        reasoningEffort: reasoningSnapshot.effort,
                        apiKey: apiKey,
                        baseURL: baseURL
                    )
                case .localLLM:
                    let baseURL = try self.settings.baseURL(for: .localLLM)
                    result = try await self.localLLMService.translate(
                        text: sourceSnapshot,
                        source: sourceLang,
                        target: targetLang,
                        style: styleSnapshot,
                        model: localModelSnapshot,
                        reasoning: reasoningSnapshot.enabled,
                        reasoningEffort: reasoningSnapshot.effort,
                        apiKey: self.settings.localApiKey,
                        baseURL: baseURL,
                        timeoutSeconds: self.settings.localRequestTimeoutSeconds
                    )
                }

                guard !Task.isCancelled else { return }

                self.output.targetText = result.translation
                self.output.synonyms = result.synonyms
                self.output.selectedAlternativeIndex = 0
                self.output.alternativeApplicationMode = .selection
                self.output.lastAlternativeInstruction = nil
                self.output.spellingNotes = result.spellingNotes
                self.output.revisedSourceText = result.revisedSource

                // Keep source text stable while typing; revised source stays available in `revisedSourceText`.
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.output.lastError = error.localizedDescription
            }
        }
    }

    private func currentReasoningSnapshot() -> (enabled: Bool, effort: String) {
        let requestedReasoning = reasoningEnabled
        let effort = (requestedReasoning ? reasoningOnValue : reasoningOffValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = requestedReasoning ? "low" : "none"
        let normalizedEffort = effort.isEmpty ? fallback : effort
        let enabled = requestedReasoning
            && normalizedEffort.lowercased() != "none"
            && normalizedEffort.lowercased() != "off"
        return (enabled, normalizedEffort)
    }

    private func documentProcessingConfiguration() throws -> DocumentProcessingConfiguration {
        let reasoningSnapshot = currentReasoningSnapshot()
        return DocumentProcessingConfiguration(
            provider: selectedProvider,
            selectedModel: selectedModel,
            localModel: localModel,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            style: style,
            reasoningEnabled: reasoningSnapshot.enabled,
            reasoningEffort: reasoningSnapshot.effort,
            apiKey: settings.apiKey,
            localApiKey: settings.localApiKey,
            openAIBaseURL: try settings.baseURL(for: .openAI),
            localBaseURL: try settings.baseURL(for: .localLLM),
            localRequestTimeoutSeconds: settings.localRequestTimeoutSeconds,
            correctionAlternativeCount: min(
                max(settings.correctionAlternativeCount, AppSettingsStore.minimumCorrectionAlternativeCount),
                AppSettingsStore.maximumCorrectionAlternativeCount
            )
        )
    }

    private static func issuesWithRanges(
        _ issues: [WritingCorrectionIssue],
        in correctedText: String
    ) -> [WritingCorrectionIssue] {
        let nsText = correctedText as NSString
        var searchLocation = 0
        var resolved: [WritingCorrectionIssue] = []

        for issue in issues {
            let replacement = issue.correctedText
            let replacementLength = (replacement as NSString).length
            guard replacementLength > 0 else { continue }

            let forwardRange = NSRange(
                location: min(searchLocation, nsText.length),
                length: max(0, nsText.length - min(searchLocation, nsText.length))
            )
            var foundRange = nsText.range(of: replacement, options: [], range: forwardRange)
            if foundRange.location == NSNotFound {
                foundRange = nsText.range(of: replacement)
            }
            guard foundRange.location != NSNotFound else { continue }

            var resolvedIssue = issue
            resolvedIssue.range = CorrectionTextRange(nsRange: foundRange)
            resolved.append(resolvedIssue)
            searchLocation = NSMaxRange(foundRange)
        }

        return resolved
    }

    var registerStyleBinding: Binding<RegisterStyle> {
        Binding(
            get: { self.style.register },
            set: { self.style.register = $0 }
        )
    }

    var complexityStyleBinding: Binding<ComplexityStyle> {
        Binding(
            get: { self.style.complexity },
            set: { self.style.complexity = $0 }
        )
    }

    var spellingModeBinding: Binding<SpellingMode> {
        Binding(
            get: { self.style.spellingMode },
            set: { self.style.spellingMode = $0 }
        )
    }
}
