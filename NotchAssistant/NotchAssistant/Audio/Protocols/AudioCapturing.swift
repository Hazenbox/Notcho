import Foundation

protocol AudioCapturing: Sendable {
    func startCapture() async throws -> AsyncStream<AudioChunk>
    func stopCapture() async
}
