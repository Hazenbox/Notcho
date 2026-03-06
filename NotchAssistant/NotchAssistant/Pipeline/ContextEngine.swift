import Foundation
import os.log

actor ContextEngine: ContextAnalyzing {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "ContextEngine")
    
    private var transcriptHistory: [TranscriptChunk] = []
    private var currentTopic: String?
    private var keyPoints: [String] = []
    private var speakerChanges: Int = 0
    private var lastSpeakerId: String?
    private var meetingStartTime: Date?
    
    private let topicExtractor = TopicExtractor()
    private let maxHistoryLength: Int
    private let keyPointThreshold: Int
    
    init(maxHistoryLength: Int = 50, keyPointThreshold: Int = 10) {
        self.maxHistoryLength = maxHistoryLength
        self.keyPointThreshold = keyPointThreshold
    }
    
    func addTranscript(_ chunk: TranscriptChunk) async {
        if meetingStartTime == nil {
            meetingStartTime = Date()
        }
        
        transcriptHistory.append(chunk)
        
        if transcriptHistory.count > maxHistoryLength {
            transcriptHistory.removeFirst()
        }
        
        detectSpeakerChange(chunk)
        
        if transcriptHistory.count % 5 == 0 {
            await updateTopic()
        }
        
        await extractKeyPoint(from: chunk)
        
        Self.logger.debug("Context updated: \(self.transcriptHistory.count) chunks, topic: \(self.currentTopic ?? "none")")
    }
    
    func buildContext() async -> MeetingContext {
        let duration = meetingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        
        return MeetingContext(
            transcriptHistory: transcriptHistory,
            currentTopic: currentTopic,
            keyPoints: keyPoints,
            speakerChanges: speakerChanges,
            meetingDuration: duration
        )
    }
    
    func detectTopic() async -> String? {
        await updateTopic()
        return currentTopic
    }
    
    func reset() async {
        Self.logger.info("Resetting context engine")
        transcriptHistory = []
        currentTopic = nil
        keyPoints = []
        speakerChanges = 0
        lastSpeakerId = nil
        meetingStartTime = nil
    }
    
    private func detectSpeakerChange(_ chunk: TranscriptChunk) {
        if let speakerId = chunk.speakerId,
           speakerId != lastSpeakerId,
           lastSpeakerId != nil {
            speakerChanges += 1
            Self.logger.debug("Speaker change detected: \(speakerId)")
        }
        lastSpeakerId = chunk.speakerId
    }
    
    private func updateTopic() async {
        let recentText = transcriptHistory
            .suffix(10)
            .map { $0.text }
            .joined(separator: " ")
        
        if let topic = await topicExtractor.extractTopic(from: recentText) {
            currentTopic = topic
        }
    }
    
    private func extractKeyPoint(from chunk: TranscriptChunk) async {
        let text = chunk.text.lowercased()
        
        let keyPhrases = [
            "important", "key point", "to summarize", "in conclusion",
            "decision", "action item", "deadline", "agree", "disagree",
            "next steps", "follow up", "priority", "critical"
        ]
        
        for phrase in keyPhrases {
            if text.contains(phrase) {
                let keyPoint = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !keyPoints.contains(keyPoint) {
                    keyPoints.append(keyPoint)
                    Self.logger.debug("Key point extracted: \(keyPoint)")
                    
                    if keyPoints.count > keyPointThreshold {
                        keyPoints.removeFirst()
                    }
                }
                break
            }
        }
    }
    
    func getRecentTranscript(chunks: Int = 5) -> String {
        transcriptHistory
            .suffix(chunks)
            .map { $0.text }
            .joined(separator: " ")
    }
}
