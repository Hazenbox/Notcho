import Foundation
import os.log

enum JSONResponseParser {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "JSONResponseParser")
    
    struct SuggestionResponse: Codable {
        let suggestion: String
        let question: String
        let insight: String
    }
    
    static func parse(_ response: String) -> SuggestionResponse? {
        let jsonString = extractJSON(from: response)
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            logger.error("Failed to convert response to data")
            return nil
        }
        
        do {
            let parsed = try JSONDecoder().decode(SuggestionResponse.self, from: jsonData)
            return parsed
        } catch {
            logger.error("JSON parsing failed: \(error.localizedDescription)")
            logger.debug("Raw response: \(response)")
            return nil
        }
    }
    
    static func extractJSON(from text: String) -> String {
        var cleaned = text
        
        if let codeBlockStart = cleaned.range(of: "```json") {
            cleaned = String(cleaned[codeBlockStart.upperBound...])
        } else if let codeBlockStart = cleaned.range(of: "```") {
            cleaned = String(cleaned[codeBlockStart.upperBound...])
        }
        
        if let codeBlockEnd = cleaned.range(of: "```") {
            cleaned = String(cleaned[..<codeBlockEnd.lowerBound])
        }
        
        if let jsonStart = cleaned.firstIndex(of: "{"),
           let jsonEnd = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[jsonStart...jsonEnd])
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
