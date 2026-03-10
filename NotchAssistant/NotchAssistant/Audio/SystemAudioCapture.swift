import ScreenCaptureKit
import AVFoundation
import CoreMedia
import os.log

actor SystemAudioCapture {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "SystemAudioCapture")
    
    private var stream: SCStream?
    private var streamOutput: SystemAudioStreamOutput?
    private var isCapturing = false
    private let accumulator: AudioBufferAccumulator
    private let converter = AudioFormatConverter()
    private let audioQueue = DispatchQueue(label: "com.notchassistant.audio.system", qos: .userInteractive)
    
    init(chunkDuration: Double = 2.0) {
        self.accumulator = AudioBufferAccumulator(
            chunkDurationSeconds: chunkDuration,
            sampleRate: AudioFormatConverter.targetSampleRate
        )
    }
    
    func startCapture() async throws -> AsyncStream<Data> {
        guard !isCapturing else {
            Self.logger.warning("System audio capture already running")
            return AsyncStream { $0.finish() }
        }
        
        Self.logger.info("Starting system audio capture")
        
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        
        guard let display = content.displays.first else {
            throw PipelineError.audioCaptureFailed("No display available")
        }
        
        let excludedApps = content.applications.filter {
            Bundle.main.bundleIdentifier == $0.bundleIdentifier
        }
        
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )
        
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.queueDepth = 8
        
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        
        isCapturing = true
        
        let localAccumulator = self.accumulator
        let localConverter = self.converter
        let localAudioQueue = self.audioQueue
        
        return AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }
            
            localAccumulator.setChunkHandler { data in
                continuation.yield(data)
            }
            
            let output = SystemAudioStreamOutput { sampleBuffer in
                guard let pcmBuffer = sampleBuffer.asPCMBuffer else { return }
                
                Task {
                    if let convertedData = await localConverter.convert(
                        buffer: pcmBuffer,
                        from: pcmBuffer.format
                    ) {
                        localAccumulator.append(convertedData)
                    }
                }
            }
            
            Task { @MainActor in
                await self.setStreamOutput(output)
                
                do {
                    let stream = SCStream(filter: filter, configuration: config, delegate: output)
                    try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: localAudioQueue)
                    
                    try await stream.startCapture()
                    Self.logger.info("System audio capture started successfully")
                    
                    await self.setStream(stream)
                } catch {
                    Self.logger.error("Failed to start capture: \(error.localizedDescription)")
                    await self.setIsCapturing(false)
                    continuation.finish()
                }
            }
            
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.stopCapture()
                }
            }
        }
    }
    
    private func setStreamOutput(_ output: SystemAudioStreamOutput) {
        self.streamOutput = output
    }
    
    private func setStream(_ stream: SCStream) {
        self.stream = stream
    }
    
    private func setIsCapturing(_ value: Bool) {
        self.isCapturing = value
    }
    
    func stopCapture() async {
        guard isCapturing else { return }
        
        Self.logger.info("Stopping system audio capture")
        
        do {
            try await stream?.stopCapture()
        } catch {
            Self.logger.error("Error stopping capture: \(error.localizedDescription)")
        }
        
        stream = nil
        streamOutput = nil
        
        await converter.reset()
        
        if let remaining = accumulator.flush() {
            Self.logger.debug("Flushed \(remaining.count) bytes of remaining audio")
        }
        accumulator.reset()
        
        isCapturing = false
    }
}

private class SystemAudioStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "SystemAudioStreamOutput")
    
    private let audioHandler: (CMSampleBuffer) -> Void
    
    init(audioHandler: @escaping (CMSampleBuffer) -> Void) {
        self.audioHandler = audioHandler
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        audioHandler(sampleBuffer)
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Self.logger.error("Stream stopped with error: \(error.localizedDescription)")
    }
}

extension CMSampleBuffer {
    var asPCMBuffer: AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(self),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return nil
        }
        
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: asbd.mSampleRate,
            channels: asbd.mChannelsPerFrame,
            interleaved: false
        ) else {
            return nil
        }
        
        let frameCount = CMSampleBufferGetNumSamples(self)
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(self) else {
            return nil
        }
        
        var dataPointer: UnsafeMutablePointer<Int8>?
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        
        guard status == kCMBlockBufferNoErr, let srcData = dataPointer else {
            return nil
        }
        
        let channelCount = Int(asbd.mChannelsPerFrame)
        
        if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            if channelCount == 1, let floatData = pcmBuffer.floatChannelData?[0] {
                memcpy(floatData, srcData, min(totalLength, frameCount * MemoryLayout<Float>.size))
            } else if channelCount >= 1, let floatData = pcmBuffer.floatChannelData {
                let srcFloats = UnsafeRawPointer(srcData).bindMemory(to: Float.self, capacity: frameCount * channelCount)
                
                if asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 {
                    for ch in 0..<channelCount {
                        let srcChannel = srcFloats.advanced(by: ch * frameCount)
                        memcpy(floatData[ch], srcChannel, frameCount * MemoryLayout<Float>.size)
                    }
                } else {
                    for frame in 0..<frameCount {
                        for ch in 0..<channelCount {
                            floatData[ch][frame] = srcFloats[frame * channelCount + ch]
                        }
                    }
                }
            }
        } else if asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 {
            let bitsPerChannel = asbd.mBitsPerChannel
            
            if bitsPerChannel == 16, let floatData = pcmBuffer.floatChannelData {
                let srcInt16 = UnsafeRawPointer(srcData).bindMemory(to: Int16.self, capacity: frameCount * channelCount)
                let scale = 1.0 / Float(Int16.max)
                
                for frame in 0..<frameCount {
                    for ch in 0..<min(channelCount, Int(format.channelCount)) {
                        let sampleIndex = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
                            ? ch * frameCount + frame
                            : frame * channelCount + ch
                        floatData[ch][frame] = Float(srcInt16[sampleIndex]) * scale
                    }
                }
            } else if bitsPerChannel == 32, let floatData = pcmBuffer.floatChannelData {
                let srcInt32 = UnsafeRawPointer(srcData).bindMemory(to: Int32.self, capacity: frameCount * channelCount)
                let scale = 1.0 / Float(Int32.max)
                
                for frame in 0..<frameCount {
                    for ch in 0..<min(channelCount, Int(format.channelCount)) {
                        let sampleIndex = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
                            ? ch * frameCount + frame
                            : frame * channelCount + ch
                        floatData[ch][frame] = Float(srcInt32[sampleIndex]) * scale
                    }
                }
            }
        }
        
        return pcmBuffer
    }
}
