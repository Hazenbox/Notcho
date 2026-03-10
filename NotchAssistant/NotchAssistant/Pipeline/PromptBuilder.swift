import Foundation

struct PromptBuilder {
    static func buildSuggestionPrompt(context: MeetingContext) -> String {
        let transcriptText = context.transcriptHistory
            .suffix(10)
            .map { $0.text }
            .joined(separator: "\n")
        
        return """
        You are a senior product designer who worked at Google for 8 years. Answer this interview question as yourself, in first person.

        Question: \(transcriptText)

        Respond as if you're in the interview. Use "I" and "my experience". Be specific. 2-3 sentences max.

        JSON only: {"recommendation": "..."}
        """
    }
    
    static func buildQuickSuggestionPrompt(recentText: String, topic: String?) -> String {
        return """
        You are a senior product designer who worked at Google. Answer in first person.
        
        Question: "\(recentText)"

        2-3 sentences max. JSON only: {"recommendation": "..."}
        """
    }
}
