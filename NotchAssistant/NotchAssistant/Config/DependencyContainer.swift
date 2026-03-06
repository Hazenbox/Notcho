import Foundation

protocol AudioCapturing: Sendable {
    func startCapture() async throws -> AsyncStream<AudioChunk>
    func stopCapture() async
}

protocol Transcribing: Sendable {
    func transcribe(_ audioChunk: AudioChunk) async throws -> TranscriptChunk
    func downloadModelIfNeeded(progress: @escaping @Sendable (Double) -> Void) async throws
}

protocol SuggestionGenerating: Sendable {
    func generate(context: MeetingContext) async throws -> SuggestionResult
}

protocol MeetingDetecting: Sendable {
    func detectActiveMeeting() async -> Bool
    var isMeetingActive: Bool { get async }
}

protocol ContextAnalyzing: Sendable {
    func addTranscript(_ chunk: TranscriptChunk) async
    func buildContext() async -> MeetingContext
    func detectTopic() async -> String?
    func reset() async
}

@MainActor
final class DependencyContainer {
    static let shared = DependencyContainer()
    
    private init() {}
    
    // Will be populated as we implement each component
    // For Phase 1, these are placeholders
    
    func makeAudioCapture() -> any AudioCapturing {
        fatalError("Audio capture not yet implemented")
    }
    
    func makeTranscriber() -> any Transcribing {
        fatalError("Transcriber not yet implemented")
    }
    
    func makeSuggestionGenerator() -> any SuggestionGenerating {
        fatalError("Suggestion generator not yet implemented")
    }
    
    func makeMeetingDetector() -> any MeetingDetecting {
        fatalError("Meeting detector not yet implemented")
    }
    
    func makeContextAnalyzer() -> any ContextAnalyzing {
        fatalError("Context analyzer not yet implemented")
    }
}
