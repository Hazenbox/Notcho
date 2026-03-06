import Foundation

protocol Transcribing: Sendable {
    func transcribe(_ audioChunk: AudioChunk) async throws -> TranscriptChunk
    func downloadModelIfNeeded(progress: @escaping @Sendable (Double) -> Void) async throws
    var isModelDownloaded: Bool { get async }
}
