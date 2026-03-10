import Foundation
import os.log

actor AudioCaptureManager: AudioCapturing {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "AudioCaptureManager")
    
    enum AudioSource: String, Sendable {
        case system
        case microphone
    }
    
    private let microphoneCapture: MicrophoneCapture
    private let systemCapture: SystemAudioCapture
    private let permissionManager: PermissionManager
    private var captureTask: Task<Void, Never>?
    private var isCapturing = false
    private var currentSource: AudioSource = .system
    
    init(chunkDuration: Double = 2.0) {
        self.microphoneCapture = MicrophoneCapture(chunkDuration: chunkDuration)
        self.systemCapture = SystemAudioCapture(chunkDuration: chunkDuration)
        self.permissionManager = PermissionManager()
    }
    
    func setAudioSource(_ source: AudioSource) {
        currentSource = source
        Self.logger.info("Audio source set to: \(source.rawValue)")
    }
    
    func startCapture() async throws -> AsyncStream<AudioChunk> {
        guard !isCapturing else {
            Self.logger.warning("Capture already in progress")
            return AsyncStream { $0.finish() }
        }
        
        switch currentSource {
        case .system:
            return try await startSystemCapture()
        case .microphone:
            return try await startMicrophoneCapture()
        }
    }
    
    private func startSystemCapture() async throws -> AsyncStream<AudioChunk> {
        Self.logger.info("Requesting screen recording permission")
        
        let hasPermission = await permissionManager.requestScreenRecordingPermission()
        guard hasPermission else {
            Self.logger.error("Screen recording permission denied")
            throw PipelineError.permissionDenied("Screen Recording access is required for system audio capture")
        }
        
        isCapturing = true
        Self.logger.info("Starting system audio capture")
        
        let rawStream = try await systemCapture.startCapture()
        
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
                        source: .system
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
    
    private func startMicrophoneCapture() async throws -> AsyncStream<AudioChunk> {
        Self.logger.info("Requesting microphone permission")
        
        let hasPermission = await permissionManager.requestMicrophonePermission()
        guard hasPermission else {
            Self.logger.error("Microphone permission denied")
            throw PipelineError.permissionDenied("Microphone access is required")
        }
        
        isCapturing = true
        Self.logger.info("Starting microphone capture")
        
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
        
        switch currentSource {
        case .system:
            await systemCapture.stopCapture()
        case .microphone:
            await microphoneCapture.stopCapture()
        }
        
        isCapturing = false
    }
}
