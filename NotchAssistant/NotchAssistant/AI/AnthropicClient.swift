import Foundation
import SwiftAnthropic
import os.log

actor AnthropicClient {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "AnthropicClient")
    
    private let service: AnthropicService
    private let model: String
    private var retryCount = 0
    private let maxRetries = 3
    
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
        
        return try await sendWithRetry(parameters: parameters)
    }
    
    private func sendWithRetry(parameters: MessageParameter, attempt: Int = 0) async throws -> String {
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
        } catch let urlError as URLError {
            return try await handleURLError(urlError, parameters: parameters, attempt: attempt)
        } catch {
            let errorString = error.localizedDescription.lowercased()
            if errorString.contains("429") || errorString.contains("rate") || errorString.contains("too many") {
                return try await handleRateLimitError(parameters: parameters, attempt: attempt)
            }
            Self.logger.error("Claude API error: \(error.localizedDescription)")
            throw PipelineError.suggestionFailed(error.localizedDescription)
        }
    }
    
    private func handleURLError(_ error: URLError, parameters: MessageParameter, attempt: Int) async throws -> String {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet:
            if attempt < self.maxRetries {
                let delay = pow(2.0, Double(attempt))
                Self.logger.warning("Network error, retrying in \(delay)s (attempt \(attempt + 1)/\(self.maxRetries))")
                try await Task.sleep(for: .seconds(delay))
                return try await sendWithRetry(parameters: parameters, attempt: attempt + 1)
            }
            throw PipelineError.networkError("Network unavailable: \(error.localizedDescription)")
        default:
            throw PipelineError.suggestionFailed(error.localizedDescription)
        }
    }
    
    private func handleRateLimitError(parameters: MessageParameter, attempt: Int) async throws -> String {
        if attempt < self.maxRetries {
            let delay = pow(2.0, Double(attempt + 1))
            Self.logger.warning("Rate limited, retrying in \(delay)s (attempt \(attempt + 1)/\(self.maxRetries))")
            try await Task.sleep(for: .seconds(delay))
            return try await sendWithRetry(parameters: parameters, attempt: attempt + 1)
        }
        throw PipelineError.rateLimited("Too many requests. Please wait before trying again.")
    }
    
    func streamMessage(prompt: String, maxTokens: Int = 1024) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
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
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        if let textContent = event.delta?.text {
                            continuation.yield(textContent)
                        }
                    }
                    
                    continuation.finish()
                    
                } catch {
                    if !Task.isCancelled {
                        Self.logger.error("Streaming error: \(error.localizedDescription)")
                        continuation.finish(throwing: error)
                    }
                }
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
