import Foundation

protocol SuggestionGenerating: Sendable {
    func generate(context: MeetingContext) async throws -> SuggestionResult
}
