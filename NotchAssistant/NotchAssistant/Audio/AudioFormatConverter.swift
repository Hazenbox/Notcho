import AVFoundation
import os.log

actor AudioFormatConverter {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "AudioFormatConverter")
    
    static let targetSampleRate: Double = 16000.0
    static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: targetSampleRate,
        channels: 1,
        interleaved: false
    )!
    
    private var cachedConverter: AVAudioConverter?
    private var cachedInputFormat: AVAudioFormat?
    
    func convert(buffer: AVAudioPCMBuffer, from inputFormat: AVAudioFormat) -> Data? {
        let targetFormat = Self.targetFormat
        
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            Self.logger.error("Invalid input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels")
            return nil
        }
        
        let converter: AVAudioConverter
        if let cached = cachedConverter,
           let cachedFormat = cachedInputFormat,
           cachedFormat.sampleRate == inputFormat.sampleRate,
           cachedFormat.channelCount == inputFormat.channelCount {
            converter = cached
        } else {
            guard let newConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                Self.logger.error("Failed to create audio converter")
                return nil
            }
            cachedConverter = newConverter
            cachedInputFormat = inputFormat
            converter = newConverter
            Self.logger.debug("Created new converter for format: \(inputFormat.sampleRate) Hz")
        }
        
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio))
        
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            Self.logger.error("Failed to create output buffer")
            return nil
        }
        
        var error: NSError?
        var inputBufferConsumed = false
        
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputBufferConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputBufferConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        switch status {
        case .error:
            Self.logger.error("Conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        case .endOfStream, .inputRanDry:
            Self.logger.debug("Conversion status: \(status.rawValue)")
        case .haveData:
            break
        @unknown default:
            Self.logger.warning("Unknown conversion status: \(status.rawValue)")
        }
        
        return extractPCMData(from: outputBuffer)
    }
    
    private func extractPCMData(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let floatChannelData = buffer.floatChannelData else { return nil }
        
        let frameCount = Int(buffer.frameLength)
        let floatPointer = floatChannelData[0]
        
        return Data(bytes: floatPointer, count: frameCount * MemoryLayout<Float>.size)
    }
    
    func reset() {
        cachedConverter = nil
        cachedInputFormat = nil
    }
}
