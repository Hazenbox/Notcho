import Foundation
import WhisperKit
import os.log

actor ModelDownloader {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "ModelDownloader")
    
    private let modelName: String
    private var downloadedModelPath: URL?
    
    init(modelName: String = "openai_whisper-base") {
        self.modelName = modelName
    }
    
    var isModelDownloaded: Bool {
        downloadedModelPath != nil || checkLocalModelExists()
    }
    
    var modelPath: URL? {
        downloadedModelPath ?? getLocalModelPath()
    }
    
    private func checkLocalModelExists() -> Bool {
        guard let path = getLocalModelPath() else { return false }
        return FileManager.default.fileExists(atPath: path.path)
    }
    
    private func getLocalModelPath() -> URL? {
        guard let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        
        let modelDir = supportDir
            .appendingPathComponent("NotchAssistant")
            .appendingPathComponent("Models")
            .appendingPathComponent(modelName)
        
        guard FileManager.default.fileExists(atPath: modelDir.path) else { return nil }
        return modelDir
    }
    
    func downloadIfNeeded(progress: @escaping @Sendable (Double) -> Void) async throws {
        if isModelDownloaded {
            Self.logger.info("Model already downloaded")
            progress(1.0)
            return
        }
        
        Self.logger.info("Starting model download: \(self.modelName)")
        
        do {
            let folder = try await WhisperKit.download(
                variant: modelName,
                progressCallback: { downloadProgress in
                    let totalProgress = downloadProgress.fractionCompleted
                    Self.logger.debug("Download progress: \(totalProgress * 100)%")
                    progress(totalProgress)
                }
            )
            
            downloadedModelPath = folder
            Self.logger.info("Model downloaded to: \(folder.path)")
            progress(1.0)
            
        } catch {
            Self.logger.error("Model download failed: \(error.localizedDescription)")
            throw PipelineError.modelDownloadFailed(error.localizedDescription)
        }
    }
}
