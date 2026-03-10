import Foundation

struct PromptBuilder {
    static func buildSuggestionPrompt(context: MeetingContext) -> String {
        let transcriptText = context.transcriptHistory
            .suffix(10)
            .map { $0.text }
            .joined(separator: "\n")
        
        return """
        You are an expert interview coach helping a product designer ace their interview.

        Question or topic being discussed:
        \(transcriptText)

        Provide a clear, confident answer that demonstrates deep expertise. Think like a staff-level product designer with 15+ years at top companies (Google, Apple, Microsoft).

        Guidelines:
        - Answer the question directly and accurately
        - Use specific examples, frameworks, or methodologies when relevant
        - Keep it concise (2-4 sentences) so it's easy to use in conversation
        - Sound confident and knowledgeable, not academic or generic

        Respond ONLY with valid JSON:
        {"recommendation": "Your answer here"}
        """
    }
    
    static func buildQuickSuggestionPrompt(recentText: String, topic: String?) -> String {
        return """
        You are an expert interview coach for product designers.
        
        Interview question: "\(recentText)"

        Provide a clear, expert-level answer (2-4 sentences). JSON only:
        {"recommendation": "..."}
        """
    }
}
