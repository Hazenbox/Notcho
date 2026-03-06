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
    var isRunning = false
    var showOnboarding = false
    
    private var pipeline: PipelineCoordinator?
    
    func setup() {
        pipeline = DependencyContainer.shared.makePipelineCoordinator()
        
        Task {
            await pipeline?.setStateHandler { [weak self] state in
                Task { @MainActor in
                    self?.state = state
                }
            }
            
            await pipeline?.setTranscriptHandler { [weak self] transcript in
                Task { @MainActor in
                    self?.currentTranscript = transcript.text
                }
            }
            
            await pipeline?.setSuggestionHandler { [weak self] suggestion in
                Task { @MainActor in
                    self?.suggestion = suggestion
                }
            }
        }
        
        checkOnboardingNeeded()
    }
    
    private func checkOnboardingNeeded() {
        let hasAPIKey = KeychainManager.hasKey(.anthropicAPIKey)
        showOnboarding = !hasAPIKey
    }
    
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
    
    func startPipeline() async {
        guard !isRunning else { return }
        
        do {
            try await pipeline?.start()
            isRunning = true
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    func stopPipeline() async {
        guard isRunning else { return }
        
        await pipeline?.stop()
        isRunning = false
    }
    
    func togglePipeline() async {
        if isRunning {
            await stopPipeline()
        } else {
            await startPipeline()
        }
    }
    
    func requestSuggestion() async {
        await pipeline?.requestImmediateSuggestion()
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
    
    func saveAPIKey(_ key: String) {
        _ = KeychainManager.save(key, for: .anthropicAPIKey)
        showOnboarding = false
    }
}
