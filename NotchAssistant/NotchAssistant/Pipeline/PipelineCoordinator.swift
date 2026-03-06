import Foundation
import os.log

actor PipelineCoordinator {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "PipelineCoordinator")
    
    private let audioCapture: any AudioCapturing
    private let transcriber: any Transcribing
    private let contextEngine: any ContextAnalyzing
    private let suggestionGenerator: any SuggestionGenerating
    private let meetingDetector: any MeetingDetecting
    
    private var state: PipelineState = .idle
    private var processingTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    
    private let suggestionInterval: TimeInterval = 10.0
    private var lastSuggestionTime: Date?
    
    private var stateUpdateHandler: (@Sendable (PipelineState) -> Void)?
    private var transcriptHandler: (@Sendable (TranscriptChunk) -> Void)?
    private var suggestionHandler: (@Sendable (SuggestionResult) -> Void)?
    private var modelProgressHandler: (@Sendable (Double) -> Void)?
    private var topicHandler: (@Sendable (String) -> Void)?
    
    func setStateHandler(_ handler: @escaping @Sendable (PipelineState) -> Void) {
        stateUpdateHandler = handler
    }
    
    func setTranscriptHandler(_ handler: @escaping @Sendable (TranscriptChunk) -> Void) {
        transcriptHandler = handler
    }
    
    func setSuggestionHandler(_ handler: @escaping @Sendable (SuggestionResult) -> Void) {
        suggestionHandler = handler
    }
    
    func setModelProgressHandler(_ handler: @escaping @Sendable (Double) -> Void) {
        modelProgressHandler = handler
    }
    
    func setTopicHandler(_ handler: @escaping @Sendable (String) -> Void) {
        topicHandler = handler
    }
    
    init(
        audioCapture: any AudioCapturing,
        transcriber: any Transcribing,
        contextEngine: any ContextAnalyzing,
        suggestionGenerator: any SuggestionGenerating,
        meetingDetector: any MeetingDetecting
    ) {
        self.audioCapture = audioCapture
        self.transcriber = transcriber
        self.contextEngine = contextEngine
        self.suggestionGenerator = suggestionGenerator
        self.meetingDetector = meetingDetector
    }
    
    func start() async throws {
        guard state == .idle else {
            Self.logger.warning("Pipeline already running")
            return
        }
        
        Self.logger.info("Starting pipeline")
        updateState(.processing)
        
        Self.logger.info("Downloading/initializing WhisperKit model...")
        let progressHandler = modelProgressHandler
        try await transcriber.downloadModelIfNeeded { progress in
            Self.logger.debug("Model download progress: \(Int(progress * 100))%")
            progressHandler?(progress)
        }
        Self.logger.info("WhisperKit model ready")
        
        updateState(.listening)
        
        let audioStream = try await audioCapture.startCapture()
        
        processingTask = Task {
            for await audioChunk in audioStream {
                guard !Task.isCancelled else { break }
                await processAudioChunk(audioChunk)
            }
        }
        
        startSuggestionLoop()
    }
    
    func stop() async {
        Self.logger.info("Stopping pipeline")
        
        processingTask?.cancel()
        suggestionTask?.cancel()
        
        await audioCapture.stopCapture()
        await contextEngine.reset()
        
        processingTask = nil
        suggestionTask = nil
        
        updateState(.idle)
        Self.logger.info("Pipeline stopped")
    }
    
    private func processAudioChunk(_ audioChunk: AudioChunk) async {
        updateState(.processing)
        
        do {
            let transcript = try await transcriber.transcribe(audioChunk)
            
            if !transcript.text.isEmpty {
                await contextEngine.addTranscript(transcript)
                transcriptHandler?(transcript)
                Self.logger.debug("Processed transcript: \(transcript.text.prefix(50))...")
                
                if let topic = await contextEngine.getCurrentTopic() {
                    topicHandler?(topic)
                }
            }
            
            updateState(.listening)
            
        } catch {
            Self.logger.error("Transcription error: \(error.localizedDescription)")
            updateState(.error(error.localizedDescription))
        }
    }
    
    private func startSuggestionLoop() {
        suggestionTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(suggestionInterval))
                
                guard !Task.isCancelled else { break }
                
                await generateSuggestion()
            }
        }
    }
    
    private func generateSuggestion() async {
        let context = await contextEngine.buildContext()
        
        guard !context.transcriptHistory.isEmpty else {
            Self.logger.debug("Skipping suggestion: no transcript history")
            return
        }
        
        do {
            let suggestion = try await suggestionGenerator.generate(context: context)
            suggestionHandler?(suggestion)
            lastSuggestionTime = Date()
            Self.logger.info("Generated suggestion successfully")
            
        } catch {
            Self.logger.error("Suggestion generation failed: \(error.localizedDescription)")
        }
    }
    
    func requestImmediateSuggestion() async {
        await generateSuggestion()
    }
    
    private func updateState(_ newState: PipelineState) {
        state = newState
        stateUpdateHandler?(newState)
    }
    
    func getCurrentState() -> PipelineState {
        state
    }
}
