import SwiftUI
import Observation

@Observable
@MainActor
final class NotchViewModel {
    var state: PipelineState = .idle
    var currentTranscript: String = ""
    var suggestion: SuggestionResult?
    var onHidePanel: (() -> Void)?
    var isRunning = false
    var showOnboarding = false
    var isLoadingModel = false
    var modelDownloadProgress: Double = 0
    
    private var pipeline: PipelineCoordinator?
    private var isSetup = false
    
    func setup() {
        guard !isSetup else { return }
        isSetup = true
        
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
            
            await pipeline?.setModelProgressHandler { [weak self] progress in
                Task { @MainActor in
                    self?.modelDownloadProgress = progress
                    self?.isLoadingModel = progress < 1.0
                }
            }
        }
        
        checkOnboardingNeeded()
    }
    
    func clearError() {
        if case .error = state {
            state = .idle
        }
    }
    
    private func checkOnboardingNeeded() {
        let hasAPIKey = KeychainManager.hasKey(.anthropicAPIKey)
        showOnboarding = !hasAPIKey
    }
    
    func loadMockData() {
        currentTranscript = "Can you walk me through your design process?"
        suggestion = SuggestionResult(
            id: UUID(),
            timestamp: Date(),
            recommendation: "I follow a double-diamond approach: first diverge with research and synthesis to define the right problem, then converge on solutions through rapid prototyping and testing. For example, at my last role I reduced checkout abandonment 23% by spending the first week purely on user interviews before touching any designs.",
            contextSnapshot: currentTranscript
        )
        state = .listening
    }
    
    func runDemoSimulation() async {
        state = .processing
        currentTranscript = "What is design thinking?"
        isRunning = true
        
        guard let apiKey = KeychainManager.loadString(.anthropicAPIKey) else {
            state = .error("API key not found. Please add your Claude API key in Settings.")
            isRunning = false
            return
        }
        
        let client = AnthropicClient(apiKey: apiKey)
        
        let prompt = """
        You are an expert interview coach for product designers. The interviewer asked: "What is design thinking?"

        Provide a clear, expert-level answer (2-4 sentences). JSON only:
        {"recommendation": "Your answer here"}
        """
        
        do {
            let response = try await client.sendMessage(prompt: prompt)
            
            if let parsed = JSONResponseParser.parse(response) {
                suggestion = SuggestionResult(
                    id: UUID(),
                    timestamp: Date(),
                    recommendation: parsed.recommendation,
                    contextSnapshot: currentTranscript
                )
                state = .listening
            } else {
                suggestion = SuggestionResult(
                    id: UUID(),
                    timestamp: Date(),
                    recommendation: String(response.prefix(300)),
                    contextSnapshot: currentTranscript
                )
                state = .listening
            }
        } catch let error as PipelineError {
            state = .error(error.errorDescription ?? "Unknown error")
        } catch let error as URLError {
            state = .error("Network error: \(error.localizedDescription)")
        } catch {
            state = .error("Error: \(error.localizedDescription)")
        }
        
        isRunning = false
    }
    
    func startPipeline() async {
        guard !isRunning else { return }
        
        isLoadingModel = true
        modelDownloadProgress = 0
        
        do {
            try await pipeline?.start()
            isRunning = true
            isLoadingModel = false
        } catch {
            isLoadingModel = false
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
        copyToClipboard(suggestion.recommendation)
    }
    
    func saveAPIKey(_ key: String) {
        _ = KeychainManager.save(key, for: .anthropicAPIKey)
        showOnboarding = false
    }
}
