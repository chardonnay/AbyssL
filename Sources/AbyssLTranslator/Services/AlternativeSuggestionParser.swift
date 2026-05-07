import Foundation

enum AlternativeSuggestionParser {
    static func parse(_ raw: String, excluding selectedText: String, limit: Int) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloadData = extractJSONObjectData(from: trimmed) ?? trimmed.data(using: .utf8)
        let alternatives = payloadData.flatMap { data -> [String]? in
            struct Payload: Decodable {
                let alternatives: [String]?
            }
            guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
                return nil
            }
            return payload.alternatives
        } ?? trimmed
            .split(whereSeparator: \.isNewline)
            .map { String($0) }

        return cleanedAlternatives(alternatives, excluding: selectedText, limit: limit)
    }

    private static func cleanedAlternatives(
        _ alternatives: [String],
        excluding selectedText: String,
        limit: Int
    ) -> [String] {
        let selected = normalized(selectedText)
        var seen: Set<String> = []
        var result: [String] = []

        for alternative in alternatives {
            let cleaned = alternative
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`-•0123456789. "))
            let normalizedAlternative = normalized(cleaned)
            guard !cleaned.isEmpty,
                  normalizedAlternative != selected,
                  seen.insert(normalizedAlternative).inserted
            else {
                continue
            }
            result.append(cleaned)
            if result.count >= limit {
                break
            }
        }

        return result
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
