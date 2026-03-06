import Foundation

struct PromptBuilder {
    static func buildSuggestionPrompt(context: MeetingContext) -> String {
        let transcriptText = context.transcriptHistory
            .suffix(10)
            .map { $0.text }
            .joined(separator: "\n")
        
        let topicInfo = context.currentTopic.map { "Current topic: \($0)" } ?? ""
        let keyPointsInfo = context.keyPoints.isEmpty 
            ? "" 
            : "Key points discussed:\n" + context.keyPoints.map { "- \($0)" }.joined(separator: "\n")
        
        let durationMinutes = Int(context.meetingDuration / 60)
        let durationInfo = durationMinutes > 0 ? "Meeting duration: \(durationMinutes) minutes" : ""
        
        return """
        You are an AI meeting assistant. Analyze the following meeting context and provide helpful suggestions.

        \(topicInfo)
        \(durationInfo)
        
        Recent transcript:
        \(transcriptText)
        
        \(keyPointsInfo)
        
        Based on this context, provide:
        1. A helpful suggestion or response the user could say next
        2. A thoughtful question to ask
        3. A brief insight about the conversation
        
        Respond in JSON format:
        {
            "suggestion": "Your suggested response here",
            "question": "Your suggested question here",
            "insight": "Your insight about the conversation"
        }
        
        Keep each response concise (1-2 sentences). Focus on being helpful and relevant to the current discussion.
        """
    }
    
    static func buildQuickSuggestionPrompt(recentText: String, topic: String?) -> String {
        let topicContext = topic.map { " about \($0)" } ?? ""
        
        return """
        Meeting context\(topicContext):
        "\(recentText)"
        
        Provide a brief, helpful suggestion. JSON format:
        {"suggestion": "...", "question": "...", "insight": "..."}
        """
    }
}
