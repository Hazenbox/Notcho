import Testing
import Foundation
@testable import NotchAssistant

@Suite("Hardware Checker Tests")
struct HardwareCheckerTests {
    @Test("Apple Silicon detection returns correct value")
    func testAppleSiliconDetection() {
        #if arch(arm64)
        #expect(HardwareChecker.isAppleSilicon == true)
        #else
        #expect(HardwareChecker.isAppleSilicon == false)
        #endif
    }
}

@Suite("Data Model Tests")
struct DataModelTests {
    @Test("PipelineState equality")
    func testPipelineStateEquality() {
        #expect(PipelineState.idle == PipelineState.idle)
        #expect(PipelineState.listening == PipelineState.listening)
        #expect(PipelineState.processing == PipelineState.processing)
        #expect(PipelineState.error("test") == PipelineState.error("test"))
        #expect(PipelineState.error("test") != PipelineState.error("different"))
        #expect(PipelineState.idle != PipelineState.listening)
    }
    
    @Test("AudioChunk creation")
    func testAudioChunkCreation() {
        let chunk = AudioChunk(
            id: UUID(),
            timestamp: Date(),
            pcmData: Data([0, 1, 2, 3]),
            sampleRate: 16000.0,
            source: .microphone
        )
        
        #expect(chunk.sampleRate == 16000.0)
        #expect(chunk.source == .microphone)
        #expect(chunk.pcmData.count == 4)
    }
    
    @Test("TranscriptChunk creation")
    func testTranscriptChunkCreation() {
        let chunk = TranscriptChunk(
            id: UUID(),
            timestamp: Date(),
            text: "Hello world",
            confidence: 0.95,
            speakerId: "speaker1",
            isFinal: true
        )
        
        #expect(chunk.text == "Hello world")
        #expect(chunk.confidence == 0.95)
        #expect(chunk.isFinal == true)
    }
    
    @Test("SuggestionResult creation")
    func testSuggestionResultCreation() {
        let result = SuggestionResult(
            id: UUID(),
            timestamp: Date(),
            recommendation: "Try this approach",
            contextSnapshot: "Some context"
        )
        
        #expect(result.recommendation == "Try this approach")
        #expect(result.contextSnapshot == "Some context")
    }
    
    @Test("PipelineError descriptions")
    func testPipelineErrorDescriptions() {
        #expect(PipelineError.unsupportedHardware.errorDescription?.contains("Apple Silicon") == true)
        #expect(PipelineError.apiKeyMissing.errorDescription?.contains("API key") == true)
        #expect(PipelineError.networkError("timeout").errorDescription?.contains("timeout") == true)
    }
}

@Suite("Accessibility Identifiers Tests")
struct AccessibilityIdentifiersTests {
    @Test("All identifiers are unique")
    func testIdentifiersUnique() {
        let identifiers = [
            AccessibilityIdentifiers.statusIndicator,
            AccessibilityIdentifiers.transcriptView,
            AccessibilityIdentifiers.suggestionCard,
            AccessibilityIdentifiers.questionCard,
            AccessibilityIdentifiers.insightCard,
            AccessibilityIdentifiers.closeButton,
            AccessibilityIdentifiers.copyButton,
            AccessibilityIdentifiers.copyAllButton,
            AccessibilityIdentifiers.regenerateButton,
            AccessibilityIdentifiers.settingsButton,
            AccessibilityIdentifiers.permissionButton,
            AccessibilityIdentifiers.startButton,
            AccessibilityIdentifiers.stopButton
        ]
        
        let uniqueIdentifiers = Set(identifiers)
        #expect(identifiers.count == uniqueIdentifiers.count)
    }
}

@Suite("Audio Buffer Accumulator Tests")
struct AudioBufferAccumulatorTests {
    @Test("Accumulator emits chunks at correct size")
    func testChunkEmission() async {
        let accumulator = AudioBufferAccumulator(chunkDurationSeconds: 0.1, sampleRate: 16000.0)
        var emittedChunks: [Data] = []
        
        accumulator.setChunkHandler { data in
            emittedChunks.append(data)
        }
        
        let chunkSize = Int(0.1 * 16000.0) * MemoryLayout<Float>.size
        let testData = Data(repeating: 0, count: chunkSize * 3)
        
        accumulator.append(testData)
        
        #expect(emittedChunks.count == 3)
    }
    
    @Test("Flush returns remaining data")
    func testFlush() {
        let accumulator = AudioBufferAccumulator(chunkDurationSeconds: 1.0, sampleRate: 16000.0)
        
        let smallData = Data(repeating: 0, count: 100)
        accumulator.append(smallData)
        
        let flushed = accumulator.flush()
        #expect(flushed?.count == 100)
    }
    
    @Test("Reset clears buffer")
    func testReset() {
        let accumulator = AudioBufferAccumulator(chunkDurationSeconds: 1.0, sampleRate: 16000.0)
        
        let smallData = Data(repeating: 0, count: 100)
        accumulator.append(smallData)
        
        accumulator.reset()
        
        let flushed = accumulator.flush()
        #expect(flushed == nil)
    }
}
