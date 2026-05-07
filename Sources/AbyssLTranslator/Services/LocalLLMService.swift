import Foundation

/// Local LLM translation client using OpenAI-compatible endpoints.
actor LocalLLMService {
    private static let noTimeoutInterval = TimeInterval.greatestFiniteMagnitude

    private let session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? Self.makeDefaultSession()
    }

    private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = noTimeoutInterval
        configuration.timeoutIntervalForResource = noTimeoutInterval
        return URLSession(configuration: configuration)
    }

    private static func applyTimeout(_ timeoutSeconds: Int, to request: inout URLRequest) {
        request.timeoutInterval = timeoutSeconds > 0 ? TimeInterval(timeoutSeconds) : noTimeoutInterval
    }

    private static func requestModelName(from model: String) -> String? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolveRequestModelName(model: String, apiKey: String?, baseURL: URL, timeoutSeconds: Int) async -> String? {
        if let modelName = Self.requestModelName(from: model) {
            return modelName
        }

        if let modelName = try? await fetchModelsResponse(apiKey: apiKey, baseURL: baseURL, timeoutSeconds: timeoutSeconds).modelInfo(for: nil)?.requestModelName {
            return modelName
        }

        let compatibleModels = (try? await fetchOpenAICompatibleModelCatalog(apiKey: apiKey, baseURL: baseURL, timeoutSeconds: timeoutSeconds)) ?? []
        guard compatibleModels.count == 1 else { return nil }
        return compatibleModels[0].requestName
    }

    func fetchModelCatalog(apiKey: String?, baseURL: URL, timeoutSeconds: Int) async throws -> [LocalLLMModel] {
        do {
            let decoded = try await fetchModelsResponse(apiKey: apiKey, baseURL: baseURL, timeoutSeconds: timeoutSeconds)
            return decoded.models
                .filter { $0.type == "llm" }
                .map { $0.catalogModel }
                .sorted(by: Self.sortCatalogModels)
        } catch {
            return try await fetchOpenAICompatibleModelCatalog(apiKey: apiKey, baseURL: baseURL, timeoutSeconds: timeoutSeconds)
                .sorted(by: Self.sortCatalogModels)
        }
    }

    private static func sortCatalogModels(_ lhs: LocalLLMModel, _ rhs: LocalLLMModel) -> Bool {
        if lhs.isLoaded != rhs.isLoaded {
            return lhs.isLoaded
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    func fetchReasoningOptions(
        model: String,
        apiKey: String?,
        baseURL: URL,
        timeoutSeconds: Int
    ) async throws -> LocalReasoningOptions {
        let modelName = Self.requestModelName(from: model)
        let decoded = try await fetchModelsResponse(apiKey: apiKey, baseURL: baseURL, timeoutSeconds: timeoutSeconds)
        guard let modelInfo = decoded.modelInfo(for: modelName) else {
            guard let modelName else {
                return LocalReasoningOptions(
                    allowedOptions: ["off"],
                    defaultOption: "off",
                    resolvedModelName: nil
                )
            }
            throw OpenAIError.invalidConfiguration(
                String(format: String(localized: "error.localModelNotFound", bundle: .module), modelName)
            )
        }

        guard let reasoning = modelInfo.capabilities?.reasoning else {
            return LocalReasoningOptions(
                allowedOptions: ["off"],
                defaultOption: "off",
                resolvedModelName: modelInfo.requestModelName
            )
        }

        let allowedOptions = reasoning.allowedOptions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let defaultOption = reasoning.defaultOption?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !allowedOptions.isEmpty else {
            return LocalReasoningOptions(
                allowedOptions: ["off"],
                defaultOption: "off",
                resolvedModelName: modelInfo.requestModelName
            )
        }

        return LocalReasoningOptions(
            allowedOptions: Array(Set(allowedOptions)).sorted(by: LocalReasoningOptions.sortOptions),
            defaultOption: defaultOption?.isEmpty == false ? defaultOption : nil,
            resolvedModelName: modelInfo.requestModelName
        )
    }

    private func fetchModelsResponse(apiKey: String?, baseURL: URL, timeoutSeconds: Int) async throws -> LocalModelsResponse {
        let endpoint = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("models")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        Self.applyTimeout(timeoutSeconds, to: &request)
        let token = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw OpenAIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(LocalModelsResponse.self, from: data)
    }

    private func fetchOpenAICompatibleModelCatalog(apiKey: String?, baseURL: URL, timeoutSeconds: Int) async throws -> [LocalLLMModel] {
        let endpoint = baseURL.appendingPathComponent("v1").appendingPathComponent("models")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        Self.applyTimeout(timeoutSeconds, to: &request)
        let token = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw OpenAIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(OpenAICompatibleModelsResponse.self, from: data)
        return decoded.data
            .map { model in
                LocalLLMModel(
                    id: model.id,
                    requestName: model.id,
                    name: model.id,
                    isLoaded: false
                )
            }
    }

    func translate(
        text: String,
        instruction: String? = nil,
        source: TranslationLanguage,
        target: TranslationLanguage,
        style: StyleSettings,
        model: String,
        reasoning: Bool,
        reasoningEffort: String,
        apiKey: String?,
        baseURL: URL,
        timeoutSeconds: Int
    ) async throws -> TranslationAIResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TranslationAIResult(translation: "", synonyms: [], spellingNotes: nil, revisedSource: nil)
        }
        let modelName = await resolveRequestModelName(model: model, apiKey: apiKey, baseURL: baseURL, timeoutSeconds: timeoutSeconds)

        let endpoint = baseURL.appendingPathComponent("v1").appendingPathComponent("chat").appendingPathComponent("completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        Self.applyTimeout(timeoutSeconds, to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body = ChatRequest(
            model: modelName,
            messages: [
                .init(role: "system", content: Self.buildSystemPrompt(source: source, target: target, style: style, reasoning: reasoning)),
                .init(role: "user", content: Self.buildUserPayload(text: trimmed, instruction: instruction, target: target, style: style)),
            ],
            temperature: reasoning ? 0.25 : 0.1,
            responseFormat: .init(type: "text"),
            reasoningEffort: Self.requestReasoningEffort(reasoning: reasoning, reasoningEffort: reasoningEffort)
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw OpenAIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(ChatResponse.self, from: data)
        guard let raw = decoded.choices.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            throw OpenAIError.invalidResponse
        }
        return Self.parseStructuredJSON(raw)
    }

    func suggestAlternatives(
        for selectedText: String,
        in targetContext: String,
        userInstruction: String? = nil,
        target: TranslationLanguage,
        style: StyleSettings,
        count: Int,
        model: String,
        reasoning: Bool,
        reasoningEffort: String,
        apiKey: String?,
        baseURL: URL,
        timeoutSeconds: Int
    ) async throws -> [String] {
        let trimmedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContext = targetContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty, !trimmedContext.isEmpty else { return [] }

        let modelName = await resolveRequestModelName(model: model, apiKey: apiKey, baseURL: baseURL, timeoutSeconds: timeoutSeconds)

        let endpoint = baseURL.appendingPathComponent("v1").appendingPathComponent("chat").appendingPathComponent("completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        Self.applyTimeout(timeoutSeconds, to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let limitedCount = min(max(count, 1), 8)
        let trimmedInstruction = userInstruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = ChatRequest(
            model: modelName,
            messages: [
                .init(
                    role: "system",
                    content: Self.buildAlternativesSystemPrompt(
                        target: target,
                        style: style,
                        count: limitedCount,
                        reasoning: reasoning,
                        hasUserInstruction: trimmedInstruction?.isEmpty == false
                    )
                ),
                .init(
                    role: "user",
                    content: Self.buildAlternativesUserPayload(
                        selectedText: trimmedSelection,
                        targetContext: trimmedContext,
                        userInstruction: trimmedInstruction
                    )
                ),
            ],
            temperature: 0.35,
            responseFormat: .init(type: "text"),
            reasoningEffort: Self.requestReasoningEffort(reasoning: reasoning, reasoningEffort: reasoningEffort)
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw OpenAIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(ChatResponse.self, from: data)
        guard let raw = decoded.choices.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            throw OpenAIError.invalidResponse
        }
        return AlternativeSuggestionParser.parse(raw, excluding: trimmedSelection, limit: limitedCount)
    }

    func correctWriting(
        text: String,
        instruction: String,
        alternativeCount: Int,
        source: TranslationLanguage,
        model: String,
        reasoning: Bool,
        reasoningEffort: String,
        apiKey: String?,
        baseURL: URL,
        timeoutSeconds: Int
    ) async throws -> WritingCorrectionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return WritingCorrectionResult(correctedText: "", issues: [])
        }
        let modelName = await resolveRequestModelName(model: model, apiKey: apiKey, baseURL: baseURL, timeoutSeconds: timeoutSeconds)
        let limitedAlternativeCount = min(
            max(alternativeCount, AppSettingsStore.minimumCorrectionAlternativeCount),
            AppSettingsStore.maximumCorrectionAlternativeCount
        )

        let endpoint = baseURL.appendingPathComponent("v1").appendingPathComponent("chat").appendingPathComponent("completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        Self.applyTimeout(timeoutSeconds, to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body = ChatRequest(
            model: modelName,
            messages: [
                .init(role: "system", content: Self.buildCorrectionSystemPrompt(
                    source: source,
                    alternativeCount: limitedAlternativeCount,
                    reasoning: reasoning,
                    hasUserInstruction: !instruction.isEmpty
                )),
                .init(role: "user", content: Self.buildCorrectionUserPayload(text: trimmed, instruction: instruction)),
            ],
            temperature: reasoning ? 0.2 : 0.05,
            responseFormat: .init(type: "text"),
            reasoningEffort: Self.requestReasoningEffort(reasoning: reasoning, reasoningEffort: reasoningEffort)
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw OpenAIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(ChatResponse.self, from: data)
        guard let raw = decoded.choices.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            throw OpenAIError.invalidResponse
        }
        return Self.parseWritingCorrectionJSON(
            raw,
            fallbackText: trimmed,
            alternativeLimit: limitedAlternativeCount
        )
    }

    func rewriteWriting(
        text: String,
        instruction: String,
        stylePreset: WritingStylePreset,
        source: TranslationLanguage,
        model: String,
        reasoning: Bool,
        reasoningEffort: String,
        apiKey: String?,
        baseURL: URL,
        timeoutSeconds: Int
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let modelName = await resolveRequestModelName(model: model, apiKey: apiKey, baseURL: baseURL, timeoutSeconds: timeoutSeconds)

        let endpoint = baseURL.appendingPathComponent("v1").appendingPathComponent("chat").appendingPathComponent("completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        Self.applyTimeout(timeoutSeconds, to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body = ChatRequest(
            model: modelName,
            messages: [
                .init(role: "system", content: Self.buildRewriteSystemPrompt(
                    stylePreset: stylePreset,
                    source: source,
                    reasoning: reasoning,
                    hasUserInstruction: !instruction.isEmpty
                )),
                .init(role: "user", content: Self.buildRewriteUserPayload(text: trimmed, instruction: instruction)),
            ],
            temperature: reasoning ? 0.35 : 0.2,
            responseFormat: .init(type: "text"),
            reasoningEffort: Self.requestReasoningEffort(reasoning: reasoning, reasoningEffort: reasoningEffort)
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw OpenAIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(ChatResponse.self, from: data)
        guard let raw = decoded.choices.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            throw OpenAIError.invalidResponse
        }
        return Self.parseRewriteJSON(raw, fallbackText: trimmed)
    }

    private static func buildSystemPrompt(
        source: TranslationLanguage,
        target: TranslationLanguage,
        style: StyleSettings,
        reasoning: Bool
    ) -> String {
        var parts: [String] = []
        parts.append("You are a professional translator. Return exactly one JSON object, no markdown.")
        parts.append("Schema: {\"translation\":\"...\",\"synonyms\":[\"...\"],\"spelling_notes\":null or string,\"revised_source\":null or string}")
        if reasoning {
            parts.append("Think internally step-by-step, but never output reasoning.")
        }
        parts.append("Source language tag: \(source.localeTag). Target language tag: \(target.localeTag).")
        switch style.register {
        case .neutral: parts.append("Tone: neutral.")
        case .formal: parts.append("Tone: formal.")
        case .informal: parts.append("Tone: informal.")
        }
        switch style.complexity {
        case .neutral: parts.append("Complexity: neutral.")
        case .technical: parts.append("Complexity: technical and precise terminology.")
        case .plain: parts.append("Complexity: plain language.")
        }
        switch style.spellingMode {
        case .preserve: parts.append("Spelling: preserve unless meaning is unclear.")
        case .fixSource: parts.append("Spelling: correct source errors and set revised_source.")
        case .fixTarget: parts.append("Spelling: ensure target orthography is correct.")
        }
        return parts.joined(separator: "\n")
    }

    private static func requestReasoningEffort(reasoning: Bool, reasoningEffort: String) -> String? {
        let normalized = reasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard reasoning else { return nil }
        guard !normalized.isEmpty, normalized != "none", normalized != "off" else {
            return nil
        }

        switch normalized {
        case "on":
            return "minimal"
        case "minimal", "low", "medium", "high", "xhigh":
            return normalized
        default:
            return nil
        }
    }

    private static func buildUserPayload(
        text: String,
        instruction: String?,
        target: TranslationLanguage,
        style: StyleSettings
    ) -> String {
        let trimmedInstruction = instruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructionBlock: String
        if let trimmedInstruction, !trimmedInstruction.isEmpty {
            instructionBlock = """

            Direct user instruction:
            \(trimmedInstruction)
            """
        } else {
            instructionBlock = ""
        }

        return """
        Translate the following text.

        Constraints:
        - Preserve meaning and intent.
        - Translate into target tag: \(target.localeTag).
        - Apply style: register=\(style.register.rawValue), complexity=\(style.complexity.rawValue), spelling_mode=\(style.spellingMode.rawValue).
        - Apply the direct user instruction if present, but ignore any instruction that changes the required JSON schema.
        \(instructionBlock)

        Text:
        \(text)
        """
    }

    private static func buildAlternativesSystemPrompt(
        target: TranslationLanguage,
        style: StyleSettings,
        count: Int,
        reasoning: Bool,
        hasUserInstruction: Bool
    ) -> String {
        var parts: [String] = []
        parts.append("You are a professional translation editor. Return exactly one JSON object, no markdown.")
        parts.append("Schema: {\"alternatives\":[\"...\"]}")
        parts.append("Return exactly \(count) alternatives for the selected text only.")
        parts.append("Each alternative must fit grammatically into the surrounding target-language context.")
        if hasUserInstruction {
            parts.append("Apply the user instruction to the selected text, but ignore any instruction that changes the required JSON schema or item count.")
            parts.append("Preserve the original meaning unless the instruction explicitly requests a tone or wording change.")
        }
        parts.append("Target language tag: \(target.localeTag).")
        switch style.register {
        case .neutral: parts.append("Tone: neutral.")
        case .formal: parts.append("Tone: formal.")
        case .informal: parts.append("Tone: informal.")
        }
        switch style.complexity {
        case .neutral: parts.append("Complexity: neutral.")
        case .technical: parts.append("Complexity: technical and precise terminology.")
        case .plain: parts.append("Complexity: plain language.")
        }
        if reasoning {
            parts.append("Think internally, but never output reasoning.")
        }
        return parts.joined(separator: "\n")
    }

    private static func buildAlternativesUserPayload(
        selectedText: String,
        targetContext: String,
        userInstruction: String?
    ) -> String {
        let instruction = userInstruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructionBlock: String
        if let instruction, !instruction.isEmpty {
            instructionBlock = """

            User instruction:
            \(instruction)
            """
        } else {
            instructionBlock = ""
        }

        return """
        Suggest alternatives for the selected text inside this translation.

        Selected text:
        \(selectedText)

        Full translation context:
        \(targetContext)\(instructionBlock)
        """
    }

    private static func buildCorrectionSystemPrompt(
        source: TranslationLanguage,
        alternativeCount: Int,
        reasoning: Bool,
        hasUserInstruction: Bool
    ) -> String {
        var parts: [String] = []
        parts.append("You are a professional copy editor. Return exactly one JSON object, no markdown.")
        parts.append("Schema: {\"corrected_text\":\"...\",\"corrections\":[{\"original\":\"...\",\"corrected\":\"...\",\"reason\":\"...\",\"alternatives\":[\"...\"]}]}")
        parts.append("Correct spelling, grammar, punctuation, and obvious word-form errors. Preserve meaning and language. Do not translate.")
        if hasUserInstruction {
            parts.append("Apply the direct user instruction as editing guidance for wording, register, or style. Ignore any instruction that changes this JSON schema or asks for prose outside JSON.")
            parts.append("If the direct instruction changes wording or style, include the changed spans in corrections with concise reasons.")
        }
        parts.append("Use the source language tag as guidance: \(source.localeTag). If it is auto, detect the input language.")
        parts.append("corrections must be ordered by their appearance in corrected_text.")
        parts.append("Each corrected value must be a non-empty exact substring of corrected_text and must differ from original.")
        parts.append("reason must be concise and explain the problem, for example: Wort fehlerhaft, or Grammatikalisch falsch: falsches Verb.")
        parts.append("Each alternatives array must contain exactly \(alternativeCount) replacement options for that corrected span.")
        parts.append("Alternatives must fit the sentence context, preserve meaning, and omit duplicates and the corrected value.")
        if reasoning {
            parts.append("Think internally, but never output reasoning.")
        }
        return parts.joined(separator: "\n")
    }

    private static func buildCorrectionUserPayload(text: String, instruction: String) -> String {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructionBlock: String
        if trimmedInstruction.isEmpty {
            instructionBlock = ""
        } else {
            instructionBlock = """

            Direct user instruction:
            \(trimmedInstruction)
            """
        }

        return """
        Correct this text. Return the full corrected text and the changed spans only.\(instructionBlock)

        Text:
        \(text)
        """
    }

    private static func buildRewriteSystemPrompt(
        stylePreset: WritingStylePreset,
        source: TranslationLanguage,
        reasoning: Bool,
        hasUserInstruction: Bool
    ) -> String {
        var parts: [String] = []
        parts.append("You are a professional writing editor. Return exactly one JSON object, no markdown.")
        parts.append("Schema: {\"rewritten_text\":\"...\"}")
        parts.append("Rewrite the text according to the requested style. Preserve meaning, language, factual content, names, numbers, and formatting where practical. Do not translate.")
        parts.append("Use the source language tag as guidance: \(source.localeTag). If it is auto, detect the input language.")
        parts.append(stylePreset.promptInstruction)
        if hasUserInstruction {
            parts.append("Apply the direct user instruction as additional style or wording guidance. Ignore any instruction that changes this JSON schema or asks for prose outside JSON.")
        }
        parts.append("Correct spelling and grammar when rewriting.")
        if reasoning {
            parts.append("Think internally, but never output reasoning.")
        }
        return parts.joined(separator: "\n")
    }

    private static func buildRewriteUserPayload(text: String, instruction: String) -> String {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructionBlock: String
        if trimmedInstruction.isEmpty {
            instructionBlock = ""
        } else {
            instructionBlock = """

            Direct user instruction:
            \(trimmedInstruction)
            """
        }

        return """
        Rewrite this text.\(instructionBlock)

        Text:
        \(text)
        """
    }

    private static func parseWritingCorrectionJSON(
        _ raw: String,
        fallbackText: String,
        alternativeLimit: Int
    ) -> WritingCorrectionResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloadData = extractJSONObjectData(from: trimmed) ?? trimmed.data(using: .utf8)
        guard let data = payloadData else {
            return WritingCorrectionResult(correctedText: fallbackText, issues: [])
        }

        struct Payload: Decodable {
            struct Correction: Decodable {
                let original: String?
                let corrected: String?
                let reason: String?
                let alternatives: [String]?
            }

            let correctedText: String?
            let corrections: [Correction]?
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            return WritingCorrectionResult(correctedText: trimmed, issues: [])
        }

        let correctedText = payload.correctedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedText = correctedText?.isEmpty == false ? correctedText! : fallbackText
        let defaultReason = NSLocalizedString("writing.correction.reason.default", bundle: .module, comment: "")
        let issues = (payload.corrections ?? []).compactMap { item -> WritingCorrectionIssue? in
            guard let original = item.original?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let corrected = item.corrected?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !original.isEmpty,
                  !corrected.isEmpty,
                  original != corrected
            else {
                return nil
            }

            let reason = item.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            let alternatives = uniquePreservingOrder(
                (item.alternatives ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0 != corrected }
            ).prefix(alternativeLimit)
            return WritingCorrectionIssue(
                originalText: original,
                correctedText: corrected,
                message: reason?.isEmpty == false ? reason! : defaultReason,
                alternatives: Array(alternatives)
            )
        }

        return WritingCorrectionResult(correctedText: resolvedText, issues: issues)
    }

    private static func parseRewriteJSON(_ raw: String, fallbackText: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloadData = extractJSONObjectData(from: trimmed) ?? trimmed.data(using: .utf8)
        guard let data = payloadData else {
            return fallbackText
        }

        struct Payload: Decodable {
            let rewrittenText: String?
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Payload.self, from: data),
              let rewritten = payload.rewrittenText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rewritten.isEmpty
        else {
            return trimmed.isEmpty ? fallbackText : trimmed
        }

        return rewritten
    }

    private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private static func parseStructuredJSON(_ raw: String) -> TranslationAIResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloadData = extractJSONObjectData(from: trimmed) ?? trimmed.data(using: .utf8)
        guard let data = payloadData else {
            return TranslationAIResult(translation: trimmed, synonyms: [], spellingNotes: nil, revisedSource: nil)
        }
        struct Payload: Decodable {
            let translation: String?
            let synonyms: [String]?
            let spellingNotes: String?
            let revisedSource: String?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let payload = try? decoder.decode(Payload.self, from: data) {
            let synonyms = (payload.synonyms ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return TranslationAIResult(
                translation: payload.translation ?? "",
                synonyms: Array(Set(synonyms)).sorted(),
                spellingNotes: payload.spellingNotes,
                revisedSource: payload.revisedSource
            )
        }
        return TranslationAIResult(translation: trimmed, synonyms: [], spellingNotes: nil, revisedSource: nil)
    }

    private static func extractJSONObjectData(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{") else {
            return nil
        }
        var depth = 0
        var index = start
        while index < text.endIndex {
            let char = text[index]
            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    let end = text.index(after: index)
                    return String(text[start ..< end]).data(using: .utf8)
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}

struct LocalLLMModel: Identifiable, Equatable, Sendable {
    let id: String
    let requestName: String
    let name: String
    let isLoaded: Bool
}

struct LocalReasoningOptions: Equatable, Sendable {
    let allowedOptions: [String]
    let defaultOption: String?
    let resolvedModelName: String?

    static func sortOptions(_ lhs: String, _ rhs: String) -> Bool {
        let order = ["none", "off", "on", "minimal", "low", "medium", "high", "xhigh"]
        let lhsIndex = order.firstIndex(of: lhs) ?? order.endIndex
        let rhsIndex = order.firstIndex(of: rhs) ?? order.endIndex
        if lhsIndex == rhsIndex {
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        return lhsIndex < rhsIndex
    }
}

private struct LocalModelsResponse: Decodable {
    let models: [LocalModelInfo]

    func modelInfo(for modelName: String?) -> LocalModelInfo? {
        if let modelName,
           let exactMatch = models.first(where: { $0.matches(modelName) })
        {
            return exactMatch
        }

        let loadedLLMs = models.filter { $0.type == "llm" && !$0.loadedInstances.isEmpty }
        guard loadedLLMs.count == 1 else { return nil }
        return loadedLLMs[0]
    }
}

private struct OpenAICompatibleModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}

private struct LocalModelInfo: Decodable {
    struct LoadedInstance: Decodable {
        let id: String
    }

    struct Capabilities: Decodable {
        let reasoning: Reasoning?

        private enum CodingKeys: String, CodingKey {
            case reasoning
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            reasoning = try? container.decode(Reasoning.self, forKey: .reasoning)
        }
    }

    struct Reasoning: Decodable {
        let allowedOptions: [String]
        let defaultOption: String?

        private enum CodingKeys: String, CodingKey {
            case allowedOptions
            case defaultOption = "default"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            allowedOptions = (try? container.decode([String].self, forKey: .allowedOptions)) ?? []
            defaultOption = try? container.decode(String.self, forKey: .defaultOption)
        }
    }

    let key: String
    let type: String
    let displayName: String?
    let selectedVariant: String?
    let loadedInstances: [LoadedInstance]
    let capabilities: Capabilities?

    var requestModelName: String {
        loadedInstances.first?.id ?? key
    }

    var catalogModel: LocalLLMModel {
        let resolvedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        if let resolvedName, !resolvedName.isEmpty {
            name = resolvedName
        } else {
            name = key
        }
        return LocalLLMModel(
            id: requestModelName,
            requestName: requestModelName,
            name: name,
            isLoaded: !loadedInstances.isEmpty
        )
    }

    func matches(_ modelName: String) -> Bool {
        key == modelName
            || selectedVariant == modelName
            || loadedInstances.contains { $0.id == modelName }
    }
}

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String?
    let messages: [Message]
    let temperature: Double
    let responseFormat: ResponseFormat?
    let reasoningEffort: String?

    struct ResponseFormat: Encodable {
        let type: String
    }
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String?
        }
        let message: Message?
    }

    let choices: [Choice]
}
