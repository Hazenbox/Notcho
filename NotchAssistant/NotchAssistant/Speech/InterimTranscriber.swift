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
            
            recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    Self.logger.debug("Recognition error: \(error.localizedDescription)")
                }
                
                if let result = result {
                    lastResult = result.bestTranscription.formattedString
                    
                    if result.isFinal {
                        continuation.resume(returning: lastResult)
                    }
                }
            }
            
            Task {
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled {
                    self.stopRecognition()
                    continuation.resume(returning: lastResult)
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
