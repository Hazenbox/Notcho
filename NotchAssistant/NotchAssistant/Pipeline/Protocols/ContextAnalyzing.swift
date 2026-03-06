import Foundation

protocol ContextAnalyzing: Sendable {
    func addTranscript(_ chunk: TranscriptChunk) async
    func buildContext() async -> MeetingContext
    func detectTopic() async -> String?
    func getCurrentTopic() async -> String?
    func reset() async
}
