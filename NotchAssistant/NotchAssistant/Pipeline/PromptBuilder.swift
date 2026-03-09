import Foundation

struct PromptBuilder {
    static func buildSuggestionPrompt(context: MeetingContext) -> String {
        let transcriptText = context.transcriptHistory
            .suffix(10)
            .map { $0.text }
            .joined(separator: "\n")
        
        return """
        You are a staff-level product designer with 15+ years of experience at Google and Microsoft. You're observing a meeting and providing real-time guidance.

        Recent conversation:
        \(transcriptText)

        Based on what you just heard, provide ONE clear, authoritative recommendation for what the user should say or do next.

        Guidelines:
        - Be direct and confident (no hedging like "you might want to" or "consider")
        - Focus on the single most impactful action
        - Keep it to 2-3 sentences maximum
        - Write as if advising a colleague in the moment

        Respond ONLY with valid JSON:
        {"recommendation": "Your direct recommendation here"}
        """
    }
    
    static func buildQuickSuggestionPrompt(recentText: String, topic: String?) -> String {
        return """
        You are a staff-level product designer. Meeting context:
        "\(recentText)"

        Provide ONE direct recommendation (2-3 sentences). JSON only:
        {"recommendation": "..."}
        """
    }
}
