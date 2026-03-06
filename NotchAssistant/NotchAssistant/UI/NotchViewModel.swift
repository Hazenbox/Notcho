import SwiftUI
import Observation

@Observable
@MainActor
final class NotchViewModel {
    var isExpanded = false
    var state: PipelineState = .idle
    var currentTranscript: String = ""
    var currentTopic: String = ""
    var suggestion: SuggestionResult?
    var onExpandToggle: (() -> Void)?
    
    // Mock data for Phase 1 testing
    func loadMockData() {
        currentTopic = "Sprint Planning"
        currentTranscript = "...so the rollout plan is to start with two pilot teams and measure adoption over the next four weeks. What do you all think about this approach?"
        suggestion = SuggestionResult(
            id: UUID(),
            timestamp: Date(),
            suggestion: "We could start with the mobile team — they've shown the most interest in the new design system.",
            question: "What metric should we use to define adoption success for the pilot?",
            insight: "The discussion is leaning toward an incremental rollout strategy.",
            contextSnapshot: currentTranscript
        )
        state = .listening
    }
    
    func update(transcript: TranscriptChunk?, suggestion: SuggestionResult?, state: PipelineState) {
        if let transcript = transcript {
            currentTranscript = transcript.text
        }
        self.suggestion = suggestion
        self.state = state
    }
    
    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    func copyAllSuggestions() {
        guard let suggestion = suggestion else { return }
        let text = """
        Suggestion: \(suggestion.suggestion)
        
        Question: \(suggestion.question)
        
        Insight: \(suggestion.insight)
        """
        copyToClipboard(text)
    }
}
