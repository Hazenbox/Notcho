import Foundation
import AVFoundation

final class AudioBufferAccumulator: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()
    private let chunkSize: Int
    private let sampleRate: Double
    private var onChunkReady: (@Sendable (Data) -> Void)?
    
    init(chunkDurationSeconds: Double = 2.0, sampleRate: Double = 16000.0) {
        self.sampleRate = sampleRate
        self.chunkSize = Int(chunkDurationSeconds * sampleRate) * 2
    }
    
    func setChunkHandler(_ handler: @escaping @Sendable (Data) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        onChunkReady = handler
    }
    
    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        
        while buffer.count >= chunkSize {
            let chunk = buffer.prefix(chunkSize)
            buffer.removeFirst(chunkSize)
            lock.unlock()
            
            onChunkReady?(Data(chunk))
            
            lock.lock()
        }
        lock.unlock()
    }
    
    func flush() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        
        guard !buffer.isEmpty else { return nil }
        let remaining = buffer
        buffer = Data()
        return remaining
    }
    
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        buffer = Data()
    }
}
