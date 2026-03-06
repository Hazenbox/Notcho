import Foundation
import SwiftAnthropic
import os.log

actor AnthropicClient {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "AnthropicClient")
    
    private let service: AnthropicService
    private let model: String
    
    init(apiKey: String, model: String = "claude-3-haiku-20240307") {
        self.service = AnthropicServiceFactory.service(
            apiKey: apiKey,
            betaHeaders: nil
        )
        self.model = model
    }
    
    func sendMessage(prompt: String, maxTokens: Int = 1024) async throws -> String {
        Self.logger.info("Sending message to Claude (\(self.model))")
        
        let message = MessageParameter.Message(
            role: .user,
            content: .text(prompt)
        )
        
        let parameters = MessageParameter(
            model: .claude35Haiku,
            messages: [message],
            maxTokens: maxTokens
        )
        
        do {
            let response = try await service.createMessage(parameters)
            
            guard let content = response.content.first else {
                throw PipelineError.suggestionFailed("Empty response from Claude")
            }
            
            switch content {
            case .text(let text, _):
                Self.logger.info("Received response: \(text.prefix(100))...")
                return text
            default:
                throw PipelineError.suggestionFailed("Unexpected response type")
            }
            
        } catch let error as PipelineError {
            throw error
        } catch {
            Self.logger.error("Claude API error: \(error.localizedDescription)")
            throw PipelineError.suggestionFailed(error.localizedDescription)
        }
    }
    
    func streamMessage(prompt: String, maxTokens: Int = 1024) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let message = MessageParameter.Message(
                        role: .user,
                        content: .text(prompt)
                    )
                    
                    let parameters = MessageParameter(
                        model: .claude35Haiku,
                        messages: [message],
                        maxTokens: maxTokens
                    )
                    
                    let stream = try await self.service.streamMessage(parameters)
                    
                    for try await event in stream {
                        if let textContent = event.delta?.text {
                            continuation.yield(textContent)
                        }
                    }
                    
                    continuation.finish()
                    
                } catch {
                    Self.logger.error("Streaming error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
