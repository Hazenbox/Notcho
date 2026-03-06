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
    
    func convert(buffer: AVAudioPCMBuffer, from inputFormat: AVAudioFormat) -> Data? {
        guard let targetFormat = Self.targetFormat as AVAudioFormat? else {
            Self.logger.error("Failed to create target format")
            return nil
        }
        
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            Self.logger.error("Failed to create audio converter")
            return nil
        }
        
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        
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
        
        if status == .error {
            Self.logger.error("Conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }
        
        return extractPCMData(from: outputBuffer)
    }
    
    private func extractPCMData(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let floatChannelData = buffer.floatChannelData else { return nil }
        
        let frameCount = Int(buffer.frameLength)
        let floatPointer = floatChannelData[0]
        
        return Data(bytes: floatPointer, count: frameCount * MemoryLayout<Float>.size)
    }
}
