import Foundation
import os.log

actor SuggestionGenerator: SuggestionGenerating {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "SuggestionGenerator")
    
    private var anthropicClient: AnthropicClient?
    private let model: String
    private var lastSuggestionTime: Date?
    private let minInterval: TimeInterval = 3.0
    
    init(model: String = "claude-3-haiku-20240307") {
        self.model = model
    }
    
    func configure(apiKey: String) {
        anthropicClient = AnthropicClient(apiKey: apiKey, model: model)
        Self.logger.info("Configured SuggestionGenerator with model: \(self.model)")
    }
    
    func generate(context: MeetingContext) async throws -> SuggestionResult {
        if anthropicClient == nil {
            if let storedKey = KeychainManager.loadString(.anthropicAPIKey) {
                anthropicClient = AnthropicClient(apiKey: storedKey, model: model)
            } else {
                throw PipelineError.apiKeyMissing
            }
        }
        
        if let lastTime = lastSuggestionTime,
           Date().timeIntervalSince(lastTime) < minInterval {
            Self.logger.debug("Rate limiting: skipping suggestion")
            throw PipelineError.suggestionFailed("Rate limited")
        }
        
        Self.logger.info("Generating suggestion for context with \(context.transcriptHistory.count) chunks")
        
        let prompt = PromptBuilder.buildSuggestionPrompt(context: context)
        
        let response = try await anthropicClient!.sendMessage(prompt: prompt)
        
        guard let parsed = JSONResponseParser.parse(response) else {
            Self.logger.warning("Failed to parse response, using raw text")
            return createFallbackResult(from: response, context: context)
        }
        
        lastSuggestionTime = Date()
        
        let contextSnapshot = context.transcriptHistory
            .suffix(5)
            .map { $0.text }
            .joined(separator: " ")
        
        return SuggestionResult(
            id: UUID(),
            timestamp: Date(),
            suggestion: parsed.suggestion,
            question: parsed.question,
            insight: parsed.insight,
            contextSnapshot: contextSnapshot
        )
    }
    
    private func createFallbackResult(from response: String, context: MeetingContext) -> SuggestionResult {
        let contextSnapshot = context.transcriptHistory
            .suffix(5)
            .map { $0.text }
            .joined(separator: " ")
        
        return SuggestionResult(
            id: UUID(),
            timestamp: Date(),
            suggestion: response.prefix(200).description,
            question: "Could you elaborate on that?",
            insight: "Unable to parse structured response",
            contextSnapshot: contextSnapshot
        )
    }
}
