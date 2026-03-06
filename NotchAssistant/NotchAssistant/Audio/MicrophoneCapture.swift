import AVFoundation
import os.log

actor MicrophoneCapture {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "MicrophoneCapture")
    
    private let audioEngine = AVAudioEngine()
    private let accumulator: AudioBufferAccumulator
    private let converter = AudioFormatConverter()
    private var isCapturing = false
    private let processingQueue = DispatchQueue(label: "com.notchassistant.audio.processing", qos: .userInteractive)
    
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
        
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            Self.logger.error("Invalid input format: no audio input device available")
            throw PipelineError.audioCaptureFailed("No microphone available")
        }
        
        Self.logger.debug("Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels")
        
        let localConverter = converter
        let localAccumulator = accumulator
        let localQueue = processingQueue
        
        isCapturing = true
        
        return AsyncStream { continuation in
            localAccumulator.setChunkHandler { data in
                continuation.yield(data)
            }
            
            inputNode.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: inputFormat
            ) { buffer, _ in
                localQueue.async {
                    Task {
                        if let convertedData = await localConverter.convert(buffer: buffer, from: inputFormat) {
                            localAccumulator.append(convertedData)
                        }
                    }
                }
            }
            
            do {
                try self.audioEngine.start()
                Self.logger.info("Audio engine started")
            } catch {
                Self.logger.error("Failed to start audio engine: \(error.localizedDescription)")
                self.isCapturing = false
                continuation.finish()
            }
            
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.stopCapture()
                }
            }
        }
    }
    
    func stopCapture() async {
        guard isCapturing else { return }
        
        Self.logger.info("Stopping microphone capture")
        
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        
        await converter.reset()
        
        if let remaining = accumulator.flush() {
            Self.logger.debug("Flushed \(remaining.count) bytes of remaining audio")
        }
        
        accumulator.reset()
        isCapturing = false
    }
}
