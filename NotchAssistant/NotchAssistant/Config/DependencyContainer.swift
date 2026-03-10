import Foundation

@MainActor
final class DependencyContainer {
    static let shared = DependencyContainer()
    
    private init() {}
    
    func makeAudioCapture() -> any AudioCapturing {
        let sourceString = UserDefaults.standard.string(forKey: "audioSource") ?? "system"
        let source: AudioSource = AudioSource(rawValue: sourceString) ?? .system
        let manager = AudioCaptureManager()
        Task {
            await manager.setAudioSource(source)
        }
        return manager
    }
    
    func makeTranscriber() -> any Transcribing {
        return WhisperKitTranscriber()
    }
    
    func makeSuggestionGenerator() -> any SuggestionGenerating {
        return SuggestionGenerator()
    }
    
    func makeMeetingDetector() -> any MeetingDetecting {
        return MeetingDetector()
    }
    
    func makePipelineCoordinator() -> PipelineCoordinator {
        return PipelineCoordinator(
            audioCapture: makeAudioCapture(),
            transcriber: makeTranscriber(),
            contextEngine: makeContextAnalyzer(),
            suggestionGenerator: makeSuggestionGenerator(),
            meetingDetector: makeMeetingDetector()
        )
    }
    
    func makeContextAnalyzer() -> any ContextAnalyzing {
        return ContextEngine()
    }
}
