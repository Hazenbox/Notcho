import Foundation
import os.log

actor AudioCaptureManager: AudioCapturing {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "AudioCaptureManager")
    
    private let microphoneCapture: MicrophoneCapture
    private let permissionManager: PermissionManager
    private var captureTask: Task<Void, Never>?
    private var isCapturing = false
    
    init(chunkDuration: Double = 2.0) {
        self.microphoneCapture = MicrophoneCapture(chunkDuration: chunkDuration)
        self.permissionManager = PermissionManager()
    }
    
    func startCapture() async throws -> AsyncStream<AudioChunk> {
        guard !isCapturing else {
            Self.logger.warning("Capture already in progress")
            return AsyncStream { $0.finish() }
        }
        
        Self.logger.info("Requesting microphone permission")
        
        let hasPermission = await permissionManager.requestMicrophonePermission()
        guard hasPermission else {
            Self.logger.error("Microphone permission denied")
            throw PipelineError.permissionDenied("Microphone access is required")
        }
        
        isCapturing = true
        Self.logger.info("Starting audio capture")
        
        let rawStream = try await microphoneCapture.startCapture()
        
        return AsyncStream { continuation in
            let task = Task {
                for await pcmData in rawStream {
                    if Task.isCancelled {
                        break
                    }
                    let chunk = AudioChunk(
                        id: UUID(),
                        timestamp: Date(),
                        pcmData: pcmData,
                        sampleRate: AudioFormatConverter.targetSampleRate,
                        source: .microphone
                    )
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
            
            self.captureTask = task
            
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                Task {
                    await self?.stopCapture()
                }
            }
        }
    }
    
    func stopCapture() async {
        guard isCapturing else { return }
        
        Self.logger.info("Stopping audio capture")
        
        captureTask?.cancel()
        captureTask = nil
        await microphoneCapture.stopCapture()
        isCapturing = false
    }
}
