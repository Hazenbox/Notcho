import Foundation

protocol MeetingDetecting: Sendable {
    func detectActiveMeeting() async -> Bool
    var isMeetingActive: Bool { get async }
}

@MainActor
final class DependencyContainer {
    static let shared = DependencyContainer()
    
    private init() {}
    
    func makeAudioCapture() -> any AudioCapturing {
        return AudioCaptureManager()
    }
    
    func makeTranscriber() -> any Transcribing {
        return WhisperKitTranscriber()
    }
    
    func makeSuggestionGenerator() -> any SuggestionGenerating {
        return SuggestionGenerator()
    }
    
    func makeMeetingDetector() -> any MeetingDetecting {
        fatalError("Meeting detector not yet implemented")
    }
    
    func makeContextAnalyzer() -> any ContextAnalyzing {
        return ContextEngine()
    }
}
