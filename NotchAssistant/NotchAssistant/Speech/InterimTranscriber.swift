import Foundation
import Speech
import os.log

actor InterimTranscriber {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "InterimTranscriber")
    
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    init(locale: Locale = Locale(identifier: "en-US")) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }
    
    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }
    
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Self.logger.info("Speech recognition authorization: \(String(describing: status))")
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    func startInterimRecognition(audioBuffer: Data) async -> String? {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            Self.logger.warning("Speech recognizer not available")
            return nil
        }
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        
        recognitionRequest = request
        
        return await withCheckedContinuation { continuation in
            var lastResult: String?
            var hasResumed = false
            let resumeLock = NSLock()
            
            func safeResume(with result: String?) {
                resumeLock.lock()
                defer { resumeLock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: result)
            }
            
            recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    Self.logger.debug("Recognition error: \(error.localizedDescription)")
                }
                
                if let result = result {
                    lastResult = result.bestTranscription.formattedString
                    
                    if result.isFinal {
                        safeResume(with: lastResult)
                    }
                }
            }
            
            Task {
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled {
                    self.stopRecognition()
                    safeResume(with: lastResult)
                }
            }
        }
    }
    
    func stopRecognition() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }
}
