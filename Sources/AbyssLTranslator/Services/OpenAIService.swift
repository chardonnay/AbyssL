import Foundation

enum OpenAIModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case gpt4o = "gpt-4o"
    case gpt4oMini = "gpt-4o-mini"
    case gpt35Turbo = "gpt-3.5-turbo"

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .gpt4o:
            return "model.gpt4o"
        case .gpt4oMini:
            return "model.gpt4oMini"
        case .gpt35Turbo:
            return "model.gpt35Turbo"
        }
    }

    /// Models that commonly support `reasoning_effort` (when exposed by the API).
    var supportsReasoningParameter: Bool {
        switch self {
        case .gpt4o, .gpt4oMini:
            return true
        case .gpt35Turbo:
            return false
        }
    }
}

enum OpenAIError: LocalizedError {
    case invalidConfiguration(String)
    case invalidResponse
    case httpStatus(Int, String?)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return message
        case .invalidResponse:
            return NSLocalizedString("error.invalidResponse", bundle: .module, comment: "")
        case .httpStatus(let code, let body):
            let suffix = body.map { "\n\($0)" } ?? ""
            return String(format: NSLocalizedString("error.httpStatus", bundle: .module, comment: ""), code) + suffix
        case .decodingFailed(let detail):
            return String(format: NSLocalizedString("error.decodingFailed", bundle: .module, comment: ""), detail)
        }
    }
}

/// Structured JSON returned by the chat model (best-effort parsing).
struct TranslationAIResult: Equatable, Sendable {
    var translation: String
    var synonyms: [String]
    var spellingNotes: String?
    var revisedSource: String?
}

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
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

private struct OpenAIErrorEnvelope: Decodable {
    struct Err: Decodable {
        let message: String?
    }

    let error: Err?
}

/// OpenAI-compatible `/v1/chat/completions` client.
actor OpenAIService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translate(
        text: String,
        instruction: String? = nil,
        source: TranslationLanguage,
        target: TranslationLanguage,
        style: StyleSettings,
        model: OpenAIModel,
        reasoning: Bool,
        reasoningEffort: String,
        apiKey: String,
        baseURL: URL
    ) async throws -> TranslationAIResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TranslationAIResult(translation: "", synonyms: [], spellingNotes: nil, revisedSource: nil)
        }

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw OpenAIError.invalidConfiguration(NSLocalizedString("error.missingAPIKey", bundle: .module, comment: ""))
        }

        let systemPrompt = Self.buildSystemPrompt(
            source: source,
            target: target,
            style: style,
            reasoning: reasoning,
            model: model
        )
        let userPrompt = Self.buildUserPayload(text: trimmed, instruction: instruction, source: source, target: target, style: style)

        let endpoint = baseURL.appendingPathComponent("v1").appendingPathComponent("chat").appendingPathComponent("completions")

        let requestBody = ChatRequest(
            model: model.rawValue,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt),
            ],
            temperature: reasoning ? 0.25 : 0.1,
            responseFormat: .init(type: "json_object"),
            reasoningEffort: reasoningEffort
        )

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw OpenAIError.httpStatus(http.statusCode, body)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if let envelope = try? decoder.decode(OpenAIErrorEnvelope.self, from: data), let msg = envelope.error?.message {
            throw OpenAIError.httpStatus(http.statusCode, msg)
        }

        let decoded = try decoder.decode(ChatResponse.self, from: data)
        guard let rawContent = decoded.choices.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawContent.isEmpty
        else {
            throw OpenAIError.invalidResponse
        }

        return Self.parseStructuredJSON(rawContent)
    }

    func suggestAlternatives(
        for selectedText: String,
        in targetContext: String,
        userInstruction: String? = nil,
        target: TranslationLanguage,
        style: StyleSettings,
        count: Int,
        model: OpenAIModel,
        reasoning: Bool,
        reasoningEffort: String,
        apiKey: String,
        baseURL: URL
    ) async throws -> [String] {
        let trimmedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContext = targetContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty, !trimmedContext.isEmpty else { return [] }

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw OpenAIError.invalidConfiguration(NSLocalizedString("error.missingAPIKey", bundle: .module, comment: ""))
        }

        let limitedCount = min(max(count, 1), 8)
        let trimmedInstruction = userInstruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = baseURL.appendingPathComponent("v1").appendingPathComponent("chat").appendingPathComponent("completions")
        let requestBody = ChatRequest(
            model: model.rawValue,
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
            responseFormat: .init(type: "json_object"),
            reasoningEffort: reasoningEffort
        )

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw OpenAIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(ChatResponse.self, from: data)
        guard let rawContent = decoded.choices.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawContent.isEmpty
        else {
            throw OpenAIError.invalidResponse
        }

        return AlternativeSuggestionParser.parse(rawContent, excluding: trimmedSelection, limit: limitedCount)
    }

    func correctWriting(
        text: String,
        instruction: String,
        alternativeCount: Int,
        source: TranslationLanguage,
        model: OpenAIModel,
        reasoning: Bool,
        reasoningEffort: String,
        apiKey: String,
        baseURL: URL
    ) async throws -> WritingCorrectionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return WritingCorrectionResult(correctedText: "", issues: [])
        }

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw OpenAIError.invalidConfiguration(NSLocalizedString("error.missingAPIKey", bundle: .module, comment: ""))
        }
        let limitedAlternativeCount = min(
            max(alternativeCount, AppSettingsStore.minimumCorrectionAlternativeCount),
            AppSettingsStore.maximumCorrectionAlternativeCount
        )

        let endpoint = baseURL.appendingPathComponent("v1").appendingPathComponent("chat").appendingPathComponent("completions")
        let requestBody = ChatRequest(
            model: model.rawValue,
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
            responseFormat: .init(type: "json_object"),
            reasoningEffort: reasoningEffort
        )

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw OpenAIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(ChatResponse.self, from: data)
        guard let rawContent = decoded.choices.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rawContent.isEmpty
        else {
            throw OpenAIError.invalidResponse
        }

        return Self.parseWritingCorrectionJSON(
            rawContent,
            fallbackText: trimmed,
            alternativeLimit: limitedAlternativeCount
        )
    }

    func rewriteWriting(
        text: String,
        instruction: String,
        stylePreset: WritingStylePreset,
        source: TranslationLanguage,
        model: OpenAIModel,
        reasoning: Bool,
        reasoningEffort: String,
        apiKey: String,
        baseURL: URL
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw OpenAIError.invalidConfiguration(NSLocalizedString("error.missingAPIKey", bundle: .module, comment: ""))
        }

        let endpoint = baseURL.appendingPathComponent("v1").appendingPathComponent("chat").appendingPathComponent("completions")
        let requestBody = ChatRequest(
            model: model.rawValue,
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
            responseFormat: .init(type: "json_object"),
            reasoningEffort: reasoningEffort
        )

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw OpenAIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(ChatResponse.self, from: data)
        guard let rawContent = decoded.choices.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawContent.isEmpty
        else {
            throw OpenAIError.invalidResponse
        }

        return Self.parseRewriteJSON(rawContent, fallbackText: trimmed)
    }

    private static func buildSystemPrompt(
        source: TranslationLanguage,
        target: TranslationLanguage,
        style: StyleSettings,
        reasoning: Bool,
        model: OpenAIModel
    ) -> String {
        var parts: [String] = []
        parts.append("You are a professional translator. Respond with a single JSON object ONLY, no markdown, no prose outside JSON.")
        parts.append("Schema: {\"translation\":\"...\",\"synonyms\":[\"...\"],\"spelling_notes\":null or string,\"revised_source\":null or string}")
        parts.append("synonyms must be 3-8 short alternatives in the TARGET language for the translated meaning (single words or short phrases). No duplicates.")
        if reasoning {
            parts.append("Think step-by-step internally but do not output your reasoning. Keep JSON-only output.")
        }
        if model.supportsReasoningParameter == false, reasoning {
            parts.append("Even if reasoning is requested, never reveal chain-of-thought; keep JSON-only.")
        }

        parts.append("Source language tag: \(source.localeTag). Target language tag: \(target.localeTag).")
        parts.append(Self.registerInstruction(style.register))
        parts.append(Self.complexityInstruction(style.complexity))
        parts.append(Self.spellingInstruction(style.spellingMode))

        return parts.joined(separator: "\n")
    }

    private static func registerInstruction(_ register: RegisterStyle) -> String {
        switch register {
        case .neutral:
            return "Tone: neutral; avoid adding politeness not present unless required by target locale conventions."
        case .formal:
            return "Tone: formal register appropriate for professional communication in the target locale."
        case .informal:
            return "Tone: informal register appropriate for everyday chat in the target locale."
        }
    }

    private static func complexityInstruction(_ complexity: ComplexityStyle) -> String {
        switch complexity {
        case .neutral:
            return "Complexity: neutral; translate faithfully without oversimplifying or jargonizing."
        case .technical:
            return "Complexity: technical, precise terminology; preserve domain terms when appropriate."
        case .plain:
            return "Complexity: plain language; short sentences; avoid jargon unless necessary."
        }
    }

    private static func spellingInstruction(_ mode: SpellingMode) -> String {
        switch mode {
        case .preserve:
            return "Spelling: do not rewrite for spelling unless the source is clearly erroneous AND it affects meaning; keep meaning-first translation."
        case .fixSource:
            return "Spelling: silently fix obvious spelling issues in revised_source (source language), then translate the corrected meaning."
        case .fixTarget:
            return "Spelling: ensure target translation uses correct spelling/orthography for the target locale."
        }
    }

    private static func buildUserPayload(
        text: String,
        instruction: String?,
        source: TranslationLanguage,
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
        - If source language is \"auto\", detect language and translate to the target tag: \(target.localeTag).
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
        parts.append(Self.registerInstruction(style.register))
        parts.append(Self.complexityInstruction(style.complexity))
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
        parts.append("You are a professional copy editor. Respond with a single JSON object ONLY, no markdown, no prose outside JSON.")
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
        parts.append("You are a professional writing editor. Respond with a single JSON object ONLY, no markdown, no prose outside JSON.")
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
            let translation = payload.translation ?? ""
            let synonyms = (payload.synonyms ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let dedup = Array(Set(synonyms)).sorted()
            return TranslationAIResult(
                translation: translation,
                synonyms: dedup,
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
            let ch = text[index]
            if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    let endIndex = text.index(after: index)
                    let slice = text[start ..< endIndex]
                    return String(slice).data(using: .utf8)
                }
            }
            index = text.index(after: index)
        }

        return nil
    }
}
