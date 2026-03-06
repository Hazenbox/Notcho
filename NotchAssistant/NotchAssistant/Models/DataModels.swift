import Foundation

enum PipelineState: Equatable, Sendable {
    case idle
    case listening
    case processing
    case error(String)
    
    static func == (lhs: PipelineState, rhs: PipelineState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.listening, .listening): return true
        case (.processing, .processing): return true
        case (.error(let lhsMsg), .error(let rhsMsg)): return lhsMsg == rhsMsg
        default: return false
        }
    }
}

struct AudioChunk: Sendable {
    let id: UUID
    let timestamp: Date
    let pcmData: Data
    let sampleRate: Double
    let source: AudioSource
}

enum AudioSource: Sendable {
    case microphone
    case system
    case combined
}

struct TranscriptChunk: Sendable {
    let id: UUID
    let timestamp: Date
    let text: String
    let confidence: Double
    let speakerId: String?
    let isFinal: Bool
}

struct MeetingContext: Sendable {
    let transcriptHistory: [TranscriptChunk]
    let currentTopic: String?
    let keyPoints: [String]
    let speakerChanges: Int
    let meetingDuration: TimeInterval
}

struct SuggestionResult: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let suggestion: String
    let question: String
    let insight: String
    let contextSnapshot: String
}

enum PipelineError: Error, LocalizedError {
    case audioCaptureFailed(String)
    case transcriptionFailed(String)
    case suggestionFailed(String)
    case permissionDenied(String)
    case unsupportedHardware
    case modelDownloadFailed(String)
    case apiKeyMissing
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .audioCaptureFailed(let msg): return "Audio capture failed: \(msg)"
        case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
        case .suggestionFailed(let msg): return "Suggestion failed: \(msg)"
        case .permissionDenied(let msg): return "Permission denied: \(msg)"
        case .unsupportedHardware: return "This app requires Apple Silicon (M1 or later)"
        case .modelDownloadFailed(let msg): return "Model download failed: \(msg)"
        case .apiKeyMissing: return "Claude API key is missing"
        case .networkError(let msg): return "Network error: \(msg)"
        }
    }
}
