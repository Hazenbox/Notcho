import AVFoundation
import os.log

actor MicrophoneCapture {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "MicrophoneCapture")
    
    private let audioEngine = AVAudioEngine()
    private let accumulator: AudioBufferAccumulator
    private let converter = AudioFormatConverter()
    private var isCapturing = false
    
    init(chunkDuration: Double = 2.0) {
        self.accumulator = AudioBufferAccumulator(
            chunkDurationSeconds: chunkDuration,
            sampleRate: AudioFormatConverter.targetSampleRate
        )
    }
    
    func startCapture() throws -> AsyncStream<Data> {
        guard !isCapturing else {
            Self.logger.warning("Capture already running")
            return AsyncStream { $0.finish() }
        }
        
        Self.logger.info("Starting microphone capture")
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        Self.logger.debug("Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels")
        
        return AsyncStream { continuation in
            self.accumulator.setChunkHandler { data in
                continuation.yield(data)
            }
            
            inputNode.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: inputFormat
            ) { [weak self] buffer, _ in
                guard let self = self else { return }
                
                Task {
                    if let convertedData = await self.converter.convert(buffer: buffer, from: inputFormat) {
                        self.accumulator.append(convertedData)
                    }
                }
            }
            
            do {
                try self.audioEngine.start()
                self.isCapturing = true
                Self.logger.info("Audio engine started")
            } catch {
                Self.logger.error("Failed to start audio engine: \(error.localizedDescription)")
                continuation.finish()
            }
            
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.stopCapture()
                }
            }
        }
    }
    
    func stopCapture() {
        guard isCapturing else { return }
        
        Self.logger.info("Stopping microphone capture")
        
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        
        if let remaining = accumulator.flush() {
            Self.logger.debug("Flushed \(remaining.count) bytes of remaining audio")
        }
        
        accumulator.reset()
        isCapturing = false
    }
}
