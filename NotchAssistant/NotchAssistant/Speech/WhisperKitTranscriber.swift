import Foundation
import WhisperKit
import os.log

actor WhisperKitTranscriber: Transcribing {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "WhisperKitTranscriber")
    
    private let modelDownloader: ModelDownloader
    private var whisperKit: WhisperKit?
    private var lastSpeakerId: String?
    private var speakerCount = 0
    
    init(modelName: String = "openai_whisper-base") {
        self.modelDownloader = ModelDownloader(modelName: modelName)
    }
    
    var isModelDownloaded: Bool {
        get async {
            await modelDownloader.isModelDownloaded
        }
    }
    
    func downloadModelIfNeeded(progress: @escaping @Sendable (Double) -> Void) async throws {
        try await modelDownloader.downloadIfNeeded(progress: progress)
        
        if whisperKit == nil {
            try await initializeWhisperKit()
        }
    }
    
    private func initializeWhisperKit() async throws {
        guard let modelPath = await modelDownloader.modelPath else {
            throw PipelineError.modelDownloadFailed("Model path not available")
        }
        
        Self.logger.info("Initializing WhisperKit with model at: \(modelPath.path)")
        
        do {
            whisperKit = try await WhisperKit(
                modelFolder: modelPath.path,
                computeOptions: .init(
                    melCompute: .cpuAndNeuralEngine,
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                ),
                verbose: false
            )
            Self.logger.info("WhisperKit initialized successfully")
        } catch {
            Self.logger.error("Failed to initialize WhisperKit: \(error.localizedDescription)")
            throw PipelineError.transcriptionFailed("WhisperKit initialization failed: \(error.localizedDescription)")
        }
    }
    
    func transcribe(_ audioChunk: AudioChunk) async throws -> TranscriptChunk {
        guard let whisperKit = whisperKit else {
            throw PipelineError.transcriptionFailed("WhisperKit not initialized")
        }
        
        Self.logger.debug("Transcribing audio chunk: \(audioChunk.pcmData.count) bytes")
        
        let audioArray = convertDataToFloatArray(audioChunk.pcmData)
        
        do {
            let results = try await whisperKit.transcribe(
                audioArray: audioArray,
                decodeOptions: .init(
                    task: .transcribe,
                    language: "en",
                    temperatureFallbackCount: 3,
                    sampleLength: 224,
                    usePrefillPrompt: true,
                    skipSpecialTokens: true,
                    withoutTimestamps: true,
                    suppressBlank: true
                )
            )
            
            guard let result = results.first else {
                Self.logger.warning("No transcription results")
                return createEmptyChunk(for: audioChunk)
            }
            
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let confidence = 0.85
            
            let speakerId = detectSpeaker(from: audioArray)
            
            Self.logger.info("Transcribed: \"\(text)\" (confidence: \(confidence))")
            
            return TranscriptChunk(
                id: UUID(),
                timestamp: audioChunk.timestamp,
                text: text,
                confidence: confidence,
                speakerId: speakerId,
                isFinal: true
            )
            
        } catch {
            Self.logger.error("Transcription failed: \(error.localizedDescription)")
            throw PipelineError.transcriptionFailed(error.localizedDescription)
        }
    }
    
    private func convertDataToFloatArray(_ data: Data) -> [Float] {
        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return [] }
            let floatCount = data.count / MemoryLayout<Float>.size
            let floatPointer = baseAddress.assumingMemoryBound(to: Float.self)
            return Array(UnsafeBufferPointer(start: floatPointer, count: floatCount))
        }
    }
    
    private func detectSpeaker(from audioArray: [Float]) -> String {
        let energy = audioArray.map { $0 * $0 }.reduce(0, +) / Float(max(1, audioArray.count))
        
        if energy > 0.01 {
            if lastSpeakerId == nil || energy > 0.1 {
                speakerCount += 1
                lastSpeakerId = "Speaker\(speakerCount)"
            }
        }
        
        return lastSpeakerId ?? "Speaker1"
    }
    
    private func createEmptyChunk(for audioChunk: AudioChunk) -> TranscriptChunk {
        TranscriptChunk(
            id: UUID(),
            timestamp: audioChunk.timestamp,
            text: "",
            confidence: 0.0,
            speakerId: nil,
            isFinal: true
        )
    }
}
