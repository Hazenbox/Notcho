# Notch AI Meeting Assistant — Engineering Build Plan

## 1. Product Summary

A native macOS application that anchors to the MacBook camera notch and acts as
a real-time AI meeting copilot. It captures meeting audio, transcribes
conversations, maintains conversational context, and surfaces AI-generated
suggestions, questions, and insights — all within a discreet overlay UI that
looks and feels like a native macOS system feature.

**Hard constraints:**

| Constraint              | Target                                    |
| ----------------------- | ----------------------------------------- |
| Platform                | macOS 14.2+ (Sonoma)                      |
| Language                | Swift 5.9+                                |
| UI framework            | SwiftUI + AppKit (window mgmt)            |
| End-to-end latency      | < 5 seconds (realistic budget)            |
| Screen-share visibility | Invisible (`sharingType = .none`)         |
| LLM provider            | Anthropic Claude (Sonnet / Haiku)         |
| STT engine              | WhisperKit (local, Swift-native)          |
| System audio            | Core Audio Hardware Taps                  |
| Build tooling           | Cursor (AI-assisted)                      |

---

## 2. System Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      macOS App Process                       │
│                                                              │
│  ┌─────────────────┐    AsyncStream<AudioChunk>              │
│  │   Audio          │──────────────────────┐                 │
│  │   Capture        │                      │                 │
│  │   Manager        │                      ▼                 │
│  │  (AVAudioEngine) │           ┌─────────────────┐          │
│  └─────────────────┘            │  Transcription   │          │
│                                 │  Engine          │          │
│  ┌─────────────────┐            │  (WhisperKit     │          │
│  │  Core Audio      │            │   + SFSpeech     │          │
│  │  Tap Capture     │────────►  │   fallback)      │          │
│  │  (System Audio)  │            └────────┬────────┘          │
│  └─────────────────┘                      │                  │
│                                           │ AsyncStream      │
│  ┌─────────────────┐                      │ <Transcript      │
│  │  Meeting         │                      │  Chunk>          │
│  │  Detector        │                      │                  │
│  └──────┬──────────┘                      │                  │
│         │ start/stop                      ▼                  │
│         ▼                      ┌─────────────────┐           │
│  ┌─────────────────┐           │  Context Engine  │           │
│  │  Pipeline        │◄─────────│  (Actor)         │           │
│  │  Coordinator     │           └────────┬────────┘           │
│  │  (Actor)         │                    │ MeetingContext     │
│  └──────┬──────────┘                    ▼                    │
│         │                      ┌─────────────────┐           │
│         │                      │  Suggestion     │           │
│         │                      │  Generator      │           │
│         │                      │  (Claude API)   │           │
│         │                      └────────┬────────┘           │
│         │                               │ SuggestionResult   │
│         ▼                               ▼                    │
│  ┌────────────────────────────────────────────┐              │
│  │        Notch UI (SwiftUI + NSVisualEffect) │              │
│  │  @Observable ViewModel · @MainActor        │              │
│  │  Pure native macOS system look             │              │
│  └────────────────────────────────────────────┘              │
└──────────────────────────────────────────────────────────────┘
```

**Concurrency model:** Swift Concurrency (structured concurrency with actors).

- `PipelineCoordinator` is an **actor** — the single owner of pipeline state.
- Audio capture and transcription produce `AsyncStream` values.
- Context Engine and Suggestion Generator are **actors** to avoid data races.
- The UI observes an `@Observable` ViewModel updated on `@MainActor`.

---

## 3. Latency Budget

| Stage                  | Duration   | Strategy                              |
| ---------------------- | ---------- | ------------------------------------- |
| Audio chunk capture    | 3 seconds  | Rolling buffer, emit every 3s         |
| Transcription          | 0.3–1.0s   | WhisperKit local (base model)         |
| Context analysis       | < 50ms     | Local string ops, no network          |
| LLM suggestion         | 2–4s       | Claude Sonnet streaming               |
| UI render              | < 16ms     | SwiftUI diffing                       |
| **Total**              | **~5–8s**  |                                       |

**Optimizations to approach 5s:**

1. **Overlap capture and processing** — while chunk N+1 is recording, chunk N
   is being transcribed and analyzed.
2. **Stream LLM responses** — show suggestions token-by-token as they arrive.
3. **Debounce LLM calls** — only trigger when the context engine detects a
   meaningful change (new topic, question directed at user, silence gap).
4. **Use Apple SFSpeechRecognizer for interim results** — show live partial
   transcript while WhisperKit processes the full chunk for accuracy.

---

## 4. Technology Decisions

### 4.1 Audio Capture

| Source         | API                            | Notes                                        |
| -------------- | ------------------------------ | -------------------------------------------- |
| Microphone     | `AVAudioEngine`                | Requires Microphone permission               |
| System audio   | Core Audio Hardware Taps       | macOS 14.2+; `AudioHardwareCreateProcessTap` |

**Why Core Audio Taps over ScreenCaptureKit:**

- Designed specifically for audio capture (not screen-first)
- Higher audio quality
- Avoids confusing "Screen Recording" permission for an audio-only app
- Per-process audio isolation natively supported
- Available on macOS 14.2+

**System audio filtering:** Use Core Audio Taps to capture audio only from
the target meeting app (Zoom, Google Meet, Teams, Slack). The Meeting Detector
identifies the active app and constructs the tap.

**Audio format:**

```swift
let format = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16000,       // WhisperKit expects 16kHz
    channels: 1,             // mono
    interleaved: false
)!
```

**Fallback:** If system audio capture fails or permission is denied, operate
in mic-only mode and inform the user.

### 4.2 Speech-to-Text

**Primary: WhisperKit (local, Swift-native)**

- Swift Package: `github.com/argmaxinc/WhisperKit` (v0.16.0+)
- Model: `base` (~140MB) for English, `small` for multilingual
- Runs on-device — no network latency, no API costs, better privacy
- Built-in Voice Activity Detection (VAD) for silence detection
- Native Apple Silicon optimization (Core ML, Neural Engine)
- No C bridge needed (pure Swift)

**Known issue:** CoreML audio resource leak in WhisperKit (issue #393) can
cause elevated `coreaudiod` CPU. Mitigate by using v0.16.0+ and monitoring
for fixes.

**Secondary: Apple SFSpeechRecognizer (interim results)**

- Provides real-time partial transcripts with very low latency
- Used for the live transcript display while WhisperKit processes the
  definitive chunk
- Does not require network on macOS 14+ (on-device model available)

### 4.3 LLM for Suggestions

**Provider: Anthropic Claude**

| Model          | Speed   | Cost (input/output)     | Use case                  |
| -------------- | ------- | ----------------------- | ------------------------- |
| Claude Haiku   | ~1-2s   | $0.25 / $1.25 per 1M    | Default continuous mode   |
| Claude Sonnet  | ~2-4s   | $3.00 / $15.00 per 1M   | Quality mode (user toggle)|

**Default:** Claude 3.5 Sonnet for quality suggestions. User can switch to
Haiku for faster/cheaper continuous suggestions in Settings.

**Streaming:** Use Anthropic Messages API with `stream: true`. Parse SSE
events via `URLSession.AsyncBytes`.

**Cost estimation (Sonnet at 1 call per 8 seconds):**

- ~350 tokens input (system + 30s transcript) + ~100 tokens output per call
- Per call: ~$0.005
- Per hour (450 calls): ~$2.25
- Per month (80 hours meetings): ~$180

**Cost estimation (Haiku):**

- Per hour: ~$0.19
- Per month (80 hours): ~$15

**Recommendation:** Default to Haiku for continuous mode, let user enable
"Quality Mode" (Sonnet) for important meetings.

### 4.4 Networking

- HTTP client: `URLSession` with async/await
- Streaming: `URLSession.AsyncBytes` for SSE parsing of Claude streams
- Base URL: `https://api.anthropic.com/v1/messages`
- Headers: `x-api-key`, `anthropic-version: 2023-06-01`
- No third-party HTTP libraries needed

---

## 5. Data Models

```swift
// MARK: - Audio

struct AudioChunk: Sendable {
    let id: UUID
    let timestamp: Date
    let pcmData: Data              // converted from AVAudioPCMBuffer
    let sampleRate: Double
    let source: AudioSource
}

enum AudioSource: Sendable {
    case microphone
    case systemAudio(appBundleID: String)
}

// MARK: - Transcription

struct TranscriptChunk: Sendable, Identifiable {
    let id: UUID
    let text: String
    let timestamp: Date
    let duration: TimeInterval
    let confidence: Float
    let isInterim: Bool          // true = SFSpeech partial, false = WhisperKit final
}

// MARK: - Context

struct MeetingContext: Sendable {
    let topic: String
    let recentTranscript: [TranscriptChunk]   // last 30s window
    let keyPoints: [String]
    let pendingQuestion: String?               // question detected, user may respond
    let speakerChangeDetected: Bool
    let silenceGapDetected: Bool
}

// MARK: - Suggestions

struct SuggestionResult: Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let suggestion: String
    let question: String
    let insight: String
    let contextSnapshot: String               // transcript that generated this
}

// MARK: - Pipeline State

enum PipelineState: Sendable {
    case idle
    case listening
    case processing
    case error(PipelineError)
}

enum PipelineError: Error, Sendable {
    case microphonePermissionDenied
    case systemAudioUnavailable
    case transcriptionFailed(underlying: Error)
    case llmRequestFailed(underlying: Error)
    case llmRateLimited(retryAfter: TimeInterval)
    case networkUnavailable
    case audioDeviceChanged
}
```

---

## 6. Project Structure

```
NotchAssistant/
├── NotchAssistant.xcodeproj
├── NotchAssistant/
│   ├── App/
│   │   ├── NotchAssistantApp.swift          // @main, app lifecycle
│   │   ├── AppDelegate.swift                // NSApplicationDelegate, menu bar
│   │   ├── PermissionManager.swift          // mic permission handling
│   │   └── LoginItemManager.swift           // SMAppService auto-launch
│   │
│   ├── UI/
│   │   ├── NotchWindowController.swift      // NSPanel setup, positioning
│   │   ├── NotchOverlayView.swift           // Main SwiftUI overlay
│   │   ├── FloatingPillView.swift           // Non-notch Mac fallback
│   │   ├── TranscriptView.swift             // Live scrolling transcript
│   │   ├── SuggestionCardView.swift         // Single suggestion/question/insight
│   │   ├── StatusIndicatorView.swift        // Listening/processing/error dot
│   │   ├── SettingsView.swift               // API key, model, role config
│   │   ├── OnboardingView.swift             // Permission walkthrough
│   │   └── NotchViewModel.swift             // @Observable, @MainActor
│   │
│   ├── Audio/
│   │   ├── AudioCaptureManager.swift        // AVAudioEngine mic capture
│   │   ├── CoreAudioTapCapture.swift        // Core Audio Hardware Taps
│   │   ├── AudioMixer.swift                 // Merge mic + system into one stream
│   │   ├── AudioDeviceMonitor.swift         // Route change notifications
│   │   └── AudioChunk.swift                 // AudioChunk model
│   │
│   ├── Speech/
│   │   ├── WhisperKitTranscriber.swift      // WhisperKit Swift integration
│   │   ├── AppleSpeechTranscriber.swift     // SFSpeechRecognizer interim results
│   │   └── TranscriptionRouter.swift        // Routes to WhisperKit or Apple
│   │
│   ├── AI/
│   │   ├── ContextEngine.swift              // Actor: maintains MeetingContext
│   │   ├── SuggestionGenerator.swift        // Actor: calls Claude, parses response
│   │   ├── PromptBuilder.swift              // Constructs system/user prompts
│   │   └── AnthropicClient.swift            // URLSession-based, streaming support
│   │
│   ├── Pipeline/
│   │   ├── PipelineCoordinator.swift        // Actor: orchestrates full pipeline
│   │   └── PipelineState.swift              // State enum + error types
│   │
│   ├── Detection/
│   │   ├── MeetingDetector.swift            // Detects active meeting apps
│   │   └── MeetingApp.swift                 // Known app bundle IDs + display names
│   │
│   ├── Config/
│   │   ├── AppSettings.swift                // @AppStorage backed settings
│   │   └── KeychainManager.swift            // Secure API key storage
│   │
│   ├── Models/
│   │   ├── TranscriptChunk.swift
│   │   ├── MeetingContext.swift
│   │   └── SuggestionResult.swift
│   │
│   └── Resources/
│       ├── Assets.xcassets
│       ├── NotchAssistant.entitlements
│       └── Info.plist
│
├── NotchAssistantTests/
│   ├── ContextEngineTests.swift
│   ├── PromptBuilderTests.swift
│   ├── PipelineCoordinatorTests.swift
│   └── MockTranscriber.swift
│
└── README.md
```

---

## 7. Component Specifications

### 7.1 NotchWindowController

Manages the `NSPanel` that anchors to the notch. Uses `NSScreen.safeAreaInsets`
for dynamic notch detection.

```swift
final class NotchWindowController {
    private var panel: NSPanel!

    var hasNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }

    func setup() {
        panel = NSPanel(
            contentRect: calculateFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar + 1
        panel.sharingType = .none                    // invisible during screen share
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false

        // Add vibrancy background
        let visualEffect = NSVisualEffectView(frame: panel.contentView!.bounds)
        visualEffect.material = .sidebar             // matches Spotlight
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(visualEffect, positioned: .below, relativeTo: nil)
    }

    private func calculateFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.frame

        if hasNotch {
            // Notch-anchored positioning
            let notchWidth: CGFloat = 200       // collapsed width
            let notchHeight: CGFloat = 32       // collapsed height
            let safeTop = screen.safeAreaInsets.top
            let x = screenFrame.midX - notchWidth / 2
            let y = screenFrame.maxY - safeTop - notchHeight
            return NSRect(x: x, y: y, width: notchWidth, height: notchHeight)
        } else {
            // Floating pill for non-notch Macs
            let pillWidth: CGFloat = 200
            let pillHeight: CGFloat = 32
            let x = screenFrame.midX - pillWidth / 2
            let y = screenFrame.maxY - 60       // 60pt from top
            return NSRect(x: x, y: y, width: pillWidth, height: pillHeight)
        }
    }

    func expand() {
        // Animate to expanded size (320x440) to show suggestions
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(expandedFrame(), display: true)
        }
    }

    func collapse() {
        // Animate back to compact indicator
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(calculateFrame(), display: true)
        }
    }

    private func expandedFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let width: CGFloat = 320
        let height: CGFloat = 440
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - (hasNotch ? screen.safeAreaInsets.top : 60) - height
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
```

**States:**

| State      | Size     | Content                              |
| ---------- | -------- | ------------------------------------ |
| Collapsed  | 200x32   | Status dot + "Listening" label       |
| Expanded   | 320x440  | Transcript + suggestions + controls  |
| Hidden     | 0x0      | Fully hidden, hotkey to restore      |

### 7.2 AudioCaptureManager

```swift
actor AudioCaptureManager {
    private let engine = AVAudioEngine()
    private let targetSampleRate: Double = 16000

    func startCapture() -> AsyncStream<AudioChunk> {
        AsyncStream { continuation in
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            // Convert to 16kHz mono for WhisperKit
            guard let converter = AVAudioConverter(
                from: inputFormat,
                to: AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: targetSampleRate,
                    channels: 1,
                    interleaved: false
                )!
            ) else {
                continuation.finish()
                return
            }

            var audioBuffer = Data()
            let chunkDuration: TimeInterval = 3.0
            let samplesPerChunk = Int(targetSampleRate * chunkDuration)

            inputNode.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: inputFormat
            ) { buffer, time in
                // Convert and accumulate
                let convertedBuffer = self.convert(buffer, using: converter)
                if let data = convertedBuffer?.toData() {
                    audioBuffer.append(data)
                }

                // Emit chunk when we have enough samples
                if audioBuffer.count >= samplesPerChunk * 4 { // 4 bytes per Float32
                    let chunk = AudioChunk(
                        id: UUID(),
                        timestamp: Date(),
                        pcmData: audioBuffer,
                        sampleRate: self.targetSampleRate,
                        source: .microphone
                    )
                    continuation.yield(chunk)
                    audioBuffer = Data()
                }
            }

            do {
                try engine.start()
            } catch {
                continuation.finish()
                return
            }

            continuation.onTermination = { _ in
                inputNode.removeTap(onBus: 0)
                self.engine.stop()
            }
        }
    }

    private func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter
    ) -> AVAudioPCMBuffer? {
        // Conversion implementation
        // ...
    }
}

extension AVAudioPCMBuffer {
    func toData() -> Data? {
        guard let channelData = floatChannelData?[0] else { return nil }
        return Data(bytes: channelData, count: Int(frameLength) * 4)
    }
}
```

### 7.3 AudioDeviceMonitor

Handles audio route changes (headphones plugged in, Bluetooth disconnect, etc.)

```swift
final class AudioDeviceMonitor {
    private var propertyListenerBlock: AudioObjectPropertyListenerBlock?

    func startMonitoring(onChange: @escaping () -> Void) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        propertyListenerBlock = { _, _ in
            DispatchQueue.main.async {
                onChange()
            }
            return 0
        }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil,
            propertyListenerBlock!
        )
    }

    func stopMonitoring() {
        // Remove listener
    }
}
```

### 7.4 PipelineCoordinator

The central orchestrator. Owns the pipeline lifecycle.

```swift
actor PipelineCoordinator {
    private let audioCapture: AudioCaptureManager
    private let coreAudioTap: CoreAudioTapCapture
    private let transcriber: TranscriptionRouter
    private let contextEngine: ContextEngine
    private let suggestionGen: SuggestionGenerator
    private let viewModel: NotchViewModel
    private let deviceMonitor: AudioDeviceMonitor

    private var pipelineTask: Task<Void, Never>?

    func start(meetingApp: MeetingApp?) {
        pipelineTask = Task {
            let micStream = await audioCapture.startCapture()

            for await chunk in micStream {
                guard !Task.isCancelled else { break }

                // Step 1: Transcribe
                do {
                    let transcript = try await transcriber.transcribe(chunk)

                    // Step 2: Update context
                    let context = await contextEngine.update(with: transcript)

                    // Step 3: Generate suggestion (only if context warrants it)
                    if context.pendingQuestion != nil
                        || context.silenceGapDetected
                        || context.speakerChangeDetected {

                        let suggestion = try await suggestionGen.generate(
                            from: context
                        )
                        await viewModel.update(
                            transcript: transcript,
                            suggestion: suggestion,
                            state: .listening
                        )
                    } else {
                        await viewModel.update(
                            transcript: transcript,
                            suggestion: nil,
                            state: .listening
                        )
                    }
                } catch let error as PipelineError {
                    await viewModel.update(
                        transcript: nil,
                        suggestion: nil,
                        state: .error(error)
                    )
                } catch {
                    // Swallow transient errors, keep pipeline running
                }
            }
        }
    }

    func stop() {
        pipelineTask?.cancel()
        pipelineTask = nil
    }

    func handleAudioDeviceChange() async {
        // Restart capture with new device
        stop()
        try? await Task.sleep(for: .milliseconds(500))
        start(meetingApp: nil)
    }
}
```

### 7.5 ContextEngine

```swift
actor ContextEngine {
    private var transcriptWindow: [TranscriptChunk] = []
    private var currentTopic: String = ""
    private var keyPoints: [String] = []
    private let windowDuration: TimeInterval = 30

    func update(with chunk: TranscriptChunk) -> MeetingContext {
        transcriptWindow.append(chunk)
        pruneOldChunks()

        let fullText = transcriptWindow.map(\.text).joined(separator: " ")

        return MeetingContext(
            topic: detectTopic(fullText),
            recentTranscript: transcriptWindow,
            keyPoints: extractKeyPoints(fullText),
            pendingQuestion: detectQuestion(fullText),
            speakerChangeDetected: detectSpeakerChange(chunk),
            silenceGapDetected: detectSilenceGap(chunk)
        )
    }

    private func pruneOldChunks() {
        let cutoff = Date().addingTimeInterval(-windowDuration)
        transcriptWindow.removeAll { $0.timestamp < cutoff }
    }

    private func detectQuestion(_ text: String) -> String? {
        let sentences = text.components(separatedBy: ". ")
        guard let last = sentences.last else { return nil }
        let questionPatterns = ["?", "what do you think", "any thoughts",
                                "does that make sense", "agree", "your take"]
        if questionPatterns.contains(where: { last.lowercased().contains($0) }) {
            return last
        }
        return nil
    }

    private func detectTopic(_ text: String) -> String {
        currentTopic
    }

    private func extractKeyPoints(_ text: String) -> [String] {
        keyPoints
    }

    private func detectSpeakerChange(_ chunk: TranscriptChunk) -> Bool {
        false
    }

    private func detectSilenceGap(_ chunk: TranscriptChunk) -> Bool {
        chunk.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
```

### 7.6 AnthropicClient

```swift
actor AnthropicClient {
    private let apiKey: String
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!

    struct Message: Codable {
        let role: String
        let content: String
    }

    struct Request: Codable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        let stream: Bool
    }

    func streamCompletion(
        model: String,
        system: String,
        messages: [Message]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var request = URLRequest(url: baseURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                let body = Request(
                    model: model,
                    max_tokens: 500,
                    system: system,
                    messages: messages,
                    stream: true
                )
                request.httpBody = try? JSONEncoder().encode(body)

                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: PipelineError.llmRequestFailed(
                            underlying: NSError(domain: "HTTP", code: (response as? HTTPURLResponse)?.statusCode ?? 0)
                        ))
                        return
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if jsonString == "[DONE]" { break }

                            if let data = jsonString.data(using: .utf8),
                               let event = try? JSONDecoder().decode(StreamEvent.self, from: data),
                               let text = event.delta?.text {
                                continuation.yield(text)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    struct StreamEvent: Codable {
        let type: String
        let delta: Delta?

        struct Delta: Codable {
            let type: String?
            let text: String?
        }
    }
}
```

### 7.7 SuggestionGenerator + PromptBuilder

```swift
actor SuggestionGenerator {
    private let client: AnthropicClient
    private let promptBuilder: PromptBuilder
    private var lastCallTime: Date = .distantPast
    private let minInterval: TimeInterval = 8
    private let settings: AppSettings

    func generate(from context: MeetingContext) async throws -> SuggestionResult {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastCallTime)
        if elapsed < minInterval {
            throw PipelineError.llmRateLimited(retryAfter: minInterval - elapsed)
        }
        lastCallTime = now

        let (system, userMessage) = promptBuilder.build(from: context)
        let model = settings.qualityMode
            ? "claude-3-5-sonnet-latest"
            : "claude-3-5-haiku-latest"

        var fullResponse = ""
        let stream = client.streamCompletion(
            model: model,
            system: system,
            messages: [AnthropicClient.Message(role: "user", content: userMessage)]
        )

        for try await chunk in stream {
            fullResponse += chunk
        }

        return parse(fullResponse, context: context)
    }

    private func parse(_ response: String, context: MeetingContext) -> SuggestionResult {
        // Parse JSON from response
        // Expected format: {"suggestion": "...", "question": "...", "insight": "..."}
        guard let data = response.data(using: .utf8),
              let json = try? JSONDecoder().decode(SuggestionJSON.self, from: data) else {
            return SuggestionResult(
                id: UUID(),
                timestamp: Date(),
                suggestion: response,
                question: "",
                insight: "",
                contextSnapshot: context.recentTranscript.map(\.text).joined(separator: " ")
            )
        }

        return SuggestionResult(
            id: UUID(),
            timestamp: Date(),
            suggestion: json.suggestion,
            question: json.question,
            insight: json.insight,
            contextSnapshot: context.recentTranscript.map(\.text).joined(separator: " ")
        )
    }

    struct SuggestionJSON: Codable {
        let suggestion: String
        let question: String
        let insight: String
    }
}
```

**Prompt template:**

```swift
struct PromptBuilder {
    var userRole: String = "Software Engineer"

    func build(from context: MeetingContext) -> (system: String, user: String) {
        let system = """
        You are a real-time meeting assistant for a \(userRole).
        You receive the last 30 seconds of meeting transcript.

        Respond with ONLY valid JSON in this exact format:
        {"suggestion": "...", "question": "...", "insight": "..."}

        Rules:
        - suggestion: A concise response the user could say next (1-2 sentences).
        - question: A strategic question that advances the discussion.
        - insight: A brief observation about the conversation dynamics or topic.
        - Be specific to the transcript. Never be generic.
        - If the transcript is unclear or trivial, use empty strings.
        - Output ONLY the JSON object, no markdown, no explanation.
        """

        let transcript = context.recentTranscript
            .map(\.text)
            .joined(separator: " ")

        let user = """
        Current topic: \(context.topic.isEmpty ? "Not yet detected" : context.topic)
        Key points: \(context.keyPoints.isEmpty ? "None" : context.keyPoints.joined(separator: "; "))
        \(context.pendingQuestion.map { "A question was asked: \($0)" } ?? "")

        Transcript (last 30s):
        \(transcript)
        """

        return (system, user)
    }
}
```

---

## 8. UI Design — Pure Native macOS System Look

The overlay looks and feels like a native macOS system feature (similar to
Spotlight, Notification Center, or Control Center).

### 8.1 Design Principles

| Element          | Specification                                   |
| ---------------- | ----------------------------------------------- |
| Background       | `NSVisualEffectView` with `.sidebar` material   |
| Blending         | `.behindWindow` mode                            |
| Corner radius    | 10pt (matches Spotlight)                        |
| Shadow           | System popover shadow                           |
| Icons            | SF Symbols only                                 |
| Colors           | System colors only (`controlAccentColor`, etc.) |
| Typography       | SF Pro, SF Mono exclusively                     |
| Animations       | Spring (damping 0.7, ~300ms)                    |

### 8.2 Color Palette

```swift
// All colors from system palette
let primaryLabel = NSColor.labelColor
let secondaryLabel = NSColor.secondaryLabelColor
let tertiaryLabel = NSColor.tertiaryLabelColor
let separator = NSColor.separatorColor
let accent = NSColor.controlAccentColor

// Status colors (system semantic)
let listening = NSColor.systemGreen
let processing = NSColor.systemYellow
let error = NSColor.systemRed
```

### 8.3 Typography

```swift
// Transcript
Font.system(.caption, design: .monospaced)  // SF Mono, 11pt

// Suggestions
Font.system(.body)                          // SF Pro, 13pt

// Labels
Font.system(.caption2).uppercased()         // SF Pro, 10pt, uppercase

// Status
Font.system(.caption)                       // SF Pro, 11pt
```

### 8.4 Visual States

**Collapsed (Idle):**

```
    ┌──────────────────────┐
    │  ● Listening         │    ← 200x32, status dot + label
    └──────────────────────┘
```

**Compact (Suggestion Ready):**

```
    ┌────────────────────────────────┐
    │  ● Listening                   │
    │                                │
    │  Topic: Sprint planning        │
    │  "Consider suggesting..."      │    ← 260x80, teaser
    └────────────────────────────────┘
```

**Expanded (Full View):**

```
    ┌─────────────────────────────────────────┐
    │  ● Listening                       ✕    │
    │                                         │
    │  ┌─────────────────────────────────┐    │
    │  │ ...so the rollout plan is to    │    │
    │  │ start with two pilot teams...   │    │  ← Live transcript
    │  └─────────────────────────────────┘    │
    │                                         │
    │  TOPIC: Design System Rollout           │
    │                                         │
    │  ┌─ SUGGESTION ────────────────────┐    │
    │  │ We could start with mobile—     │ ⧉  │
    │  │ they've shown the most interest │    │
    │  └─────────────────────────────────┘    │
    │                                         │
    │  ┌─ QUESTION ──────────────────────┐    │
    │  │ What metric defines success?    │ ⧉  │
    │  └─────────────────────────────────┘    │
    │                                         │
    │  ┌─ INSIGHT ───────────────────────┐    │
    │  │ Discussion leaning incremental  │    │
    │  └─────────────────────────────────┘    │
    │                                         │
    │  [ ↻ Regenerate ]        [ ⧉ Copy All ] │
    └─────────────────────────────────────────┘
                   320x440
```

### 8.5 SF Symbols Used

| Purpose          | Symbol                        |
| ---------------- | ----------------------------- |
| Status listening | `circle.fill` (green tint)    |
| Status processing| `circle.fill` (yellow tint)   |
| Status error     | `exclamationmark.circle.fill` |
| Copy             | `doc.on.doc`                  |
| Regenerate       | `arrow.clockwise`             |
| Close            | `xmark`                       |
| Settings         | `gear`                        |
| Mic active       | `mic.fill`                    |
| Mic muted        | `mic.slash`                   |

---

## 9. Permission Handling

The app requires Microphone permission. Accessibility is optional for global
hotkeys.

| Permission        | API                              | Required for        | If denied                        |
| ----------------- | -------------------------------- | ------------------- | -------------------------------- |
| Microphone        | `AVCaptureDevice.requestAccess`  | Mic capture         | App cannot function — show error |
| Accessibility     | `AXIsProcessTrusted`             | Global hotkeys      | Hotkeys disabled, menu bar only  |

**Onboarding flow:**

1. Welcome screen explaining what the app does.
2. Request Microphone — required, block if denied.
3. Request Accessibility — optional, explain hotkeys benefit.
4. API key entry (Claude) — required.
5. Ready screen.

---

## 10. Meeting Detection

`MeetingDetector` identifies when a meeting is active so the pipeline starts/
stops automatically.

```swift
final class MeetingDetector {
    static let knownMeetingApps: [MeetingApp] = [
        MeetingApp(name: "Zoom", bundleID: "us.zoom.xos"),
        MeetingApp(name: "Google Meet", bundleID: "com.google.Chrome", windowTitle: "Meet"),
        MeetingApp(name: "Microsoft Teams", bundleID: "com.microsoft.teams2"),
        MeetingApp(name: "Slack Huddle", bundleID: "com.tinyspeck.slackmacgap"),
        MeetingApp(name: "FaceTime", bundleID: "com.apple.FaceTime"),
        MeetingApp(name: "Discord", bundleID: "com.hnc.Discord"),
        MeetingApp(name: "Webex", bundleID: "com.webex.meetingmanager"),
    ]

    func detectActiveMeeting() -> MeetingApp? {
        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications
        for app in knownMeetingApps {
            if running.contains(where: { $0.bundleIdentifier == app.bundleID }) {
                return app
            }
        }
        return nil
    }
}
```

**Modes:**

- **Auto:** Start pipeline when meeting app detected, stop when it quits.
- **Manual:** User toggles via hotkey or menu bar click.
- **Always-on:** Pipeline runs continuously (battery-intensive, warn user).

---

## 11. Configuration & Settings

```swift
struct AppSettings {
    @AppStorage("userRole") var userRole: String = "Software Engineer"
    @AppStorage("transcriptionEngine") var engine: TranscriptionEngine = .whisperKit
    @AppStorage("claudeModel") var claudeModel: ClaudeModel = .haiku
    @AppStorage("qualityMode") var qualityMode: Bool = false    // Sonnet vs Haiku
    @AppStorage("audioChunkDuration") var chunkDuration: Double = 3.0
    @AppStorage("transcriptWindow") var transcriptWindow: Double = 30.0
    @AppStorage("llmCallInterval") var llmCallInterval: Double = 8.0
    @AppStorage("meetingDetectionMode") var detectionMode: DetectionMode = .auto
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
}

enum TranscriptionEngine: String, CaseIterable {
    case whisperKit       // WhisperKit on-device
    case appleSpeech      // SFSpeechRecognizer
}

enum ClaudeModel: String, CaseIterable {
    case haiku = "claude-3-5-haiku-latest"
    case sonnet = "claude-3-5-sonnet-latest"
}

enum DetectionMode: String, CaseIterable {
    case auto             // detect meeting apps
    case manual           // user toggle
    case alwaysOn         // always listening
}
```

---

## 12. Keyboard Shortcuts

| Shortcut    | Action                                |
| ----------- | ------------------------------------- |
| Cmd+Shift+M | Toggle expand/collapse                |
| Cmd+Shift+H | Hide completely                       |
| Cmd+Shift+S | Force generate suggestion now         |
| Cmd+Shift+L | Toggle listening on/off               |
| Cmd+Shift+C | Copy last suggestion to clipboard     |

Registered via `NSEvent.addGlobalMonitorForEvents` (requires Accessibility
permission) with `NSEvent.addLocalMonitorForEvents` as fallback.

---

## 13. Login Item (Auto-Launch)

```swift
import ServiceManagement

final class LoginItemManager {
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update login item: \(error)")
        }
    }

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
```

---

## 14. Error Handling Strategy

### 14.1 Retry Policy

| Error type           | Retry | Max attempts | Backoff        |
| -------------------- | ----- | ------------ | -------------- |
| Network timeout      | Yes   | 3            | Exponential 1s |
| Claude rate limit    | Yes   | 1            | Wait header    |
| Claude 500 error     | Yes   | 2            | Fixed 2s       |
| Transcription fail   | Yes   | 1            | Switch engine  |
| Permission denied    | No    | —            | Show settings  |
| Audio device changed | No    | —            | Restart capture|

### 14.2 Fallback Chain

```
Transcription: WhisperKit → SFSpeechRecognizer
Audio:         Mic + System → Mic only → Pause + notify
```

### 14.3 UI Error States

- **Transient errors** (network blip): yellow status dot, auto-retry silently.
- **Degraded mode** (system audio unavailable): orange dot + banner.
- **Fatal errors** (mic denied): red dot + overlay with "Open System Settings".

---

## 15. Distribution & Signing

### 15.1 Required Entitlements

**NotchAssistant.entitlements:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.device.microphone</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

**Note:** App Sandbox is disabled for direct distribution. If targeting Mac App
Store, sandbox must be enabled with appropriate exceptions.

### 15.2 Info.plist Privacy Descriptions

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Notch Assistant needs microphone access to transcribe meeting audio and provide real-time suggestions.</string>
```

### 15.3 Hardened Runtime

Enable Hardened Runtime in Xcode:
- Signing & Capabilities → + Capability → Hardened Runtime
- Enable: Allow Microphone Access

### 15.4 Code Signing

```bash
# Sign with Developer ID for direct distribution
codesign --force --deep --sign "Developer ID Application: Your Name (TEAMID)" \
    --entitlements NotchAssistant.entitlements \
    --options runtime \
    NotchAssistant.app
```

### 15.5 Notarization

```bash
# Create ZIP for notarization
ditto -c -k --keepParent NotchAssistant.app NotchAssistant.zip

# Submit for notarization
xcrun notarytool submit NotchAssistant.zip \
    --apple-id "you@example.com" \
    --team-id "TEAMID" \
    --password "@keychain:AC_PASSWORD" \
    --wait

# Staple the ticket
xcrun stapler staple NotchAssistant.app
```

---

## 16. Privacy & Security

| Feature                        | Implementation                            |
| ------------------------------ | ----------------------------------------- |
| No transcript persistence      | Transcript buffer is in-memory only       |
| Screen-share invisible         | `panel.sharingType = .none`               |
| API keys in Keychain           | `KeychainManager` wraps Security framework|
| Meeting-only listening         | Auto-start/stop via MeetingDetector       |
| Configurable data retention    | Clear context on meeting end              |

---

## 17. Testing Strategy

### 17.1 Unit Tests

| Component            | What to test                                      |
| -------------------- | ------------------------------------------------- |
| ContextEngine        | Transcript window pruning, question detection     |
| PromptBuilder        | Prompt formatting, edge cases (empty transcript)  |
| MeetingDetector      | Known app matching, edge cases                    |
| SuggestionGenerator  | Rate limiting, JSON parsing, error handling       |
| AppSettings          | Default values, persistence                       |

### 17.2 Integration Tests

| Test                      | Description                                       |
| ------------------------- | ------------------------------------------------- |
| Audio → Transcript        | Feed a WAV file, verify transcription output      |
| Transcript → Context      | Feed transcript chunks, verify context state      |
| Context → Suggestion      | Feed context, verify Claude call + parsed result  |
| Full pipeline             | End-to-end with mock audio input                  |

### 17.3 Manual QA Checklist

- [ ] Overlay positions correctly on notch MacBooks (14", 16")
- [ ] Floating pill positions correctly on non-notch Macs
- [ ] Overlay invisible during screen share (test with Zoom, Meet)
- [ ] Expand/collapse animation smooth at 60fps
- [ ] Hotkeys work globally when Accessibility granted
- [ ] Pipeline starts automatically when Zoom launches
- [ ] Pipeline stops cleanly when meeting ends
- [ ] App handles sleep/wake without crashing
- [ ] App handles headphone plug/unplug without crashing
- [ ] Memory stays under 200MB during 1-hour meeting
- [ ] CPU stays under 15% average during listening

---

## 18. Build Phases & Timeline

### Phase 1: Foundation + Notch UI (Days 1–2)

**Goal:** Visible, correctly positioned notch overlay with expand/collapse.

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| Xcode project setup, signing, entitlements  | 2h    |
| Evaluate DynamicNotchKit vs custom NSPanel  | 2h    |
| `NotchWindowController` with safeAreaInsets | 3h    |
| Non-notch fallback (floating pill)          | 2h    |
| `NotchOverlayView` — collapsed state        | 2h    |
| `NotchOverlayView` — expanded state         | 3h    |
| `StatusIndicatorView` with SF Symbols       | 1h    |
| `SuggestionCardView` — native look          | 2h    |
| Expand/collapse spring animation            | 2h    |
| `NotchViewModel` with mock data             | 1h    |
| `sharingType = .none` verification          | 1h    |

**Deliverable:** Overlay shows mock suggestions, invisible during screen share.

### Phase 2: Audio Capture (Days 3–4)

**Goal:** Capture mic audio as 16kHz PCM chunks.

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| `PermissionManager` — microphone            | 2h    |
| `AudioCaptureManager` — AVAudioEngine tap   | 4h    |
| Audio format conversion to 16kHz mono       | 2h    |
| `AudioDeviceMonitor` — route changes        | 3h    |
| `MeetingDetector` — app detection logic     | 2h    |
| Core Audio Taps research (stretch goal)     | 3h    |

**Deliverable:** Audio chunks stream to console, verified with playback.

### Phase 3: Transcription (Days 5–6)

**Goal:** Convert audio chunks to text with < 1s latency locally.

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| Add WhisperKit via SPM                      | 1h    |
| `WhisperKitTranscriber` — load model, infer | 4h    |
| `AppleSpeechTranscriber` — SFSpeech setup   | 3h    |
| `TranscriptionRouter` — engine selection    | 2h    |
| Audio → transcript integration test         | 2h    |

**Deliverable:** Live transcript from mic audio displayed in UI.

### Phase 4: Context Engine + AI Suggestions (Days 7–9)

**Goal:** Maintain conversation state and generate relevant suggestions.

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| `ContextEngine` — sliding window, pruning   | 3h    |
| Question detection heuristics               | 2h    |
| Silence/speaker-change detection            | 2h    |
| `AnthropicClient` — streaming completions   | 4h    |
| `PromptBuilder` — template + formatting     | 2h    |
| `SuggestionGenerator` — rate limit, parse   | 3h    |
| `KeychainManager` — API key storage         | 2h    |
| Context → suggestion integration test       | 2h    |

**Deliverable:** AI suggestions appear in overlay based on live transcript.

### Phase 5: Pipeline Integration (Days 10–11)

**Goal:** Wire all components into a reliable end-to-end pipeline.

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| `PipelineCoordinator` — full orchestration  | 5h    |
| Error handling + fallback chains            | 3h    |
| Debounced LLM triggering logic              | 2h    |
| Keyboard shortcuts (global + local)         | 3h    |
| Menu bar integration (status item)          | 2h    |
| `SettingsView` — configuration UI           | 3h    |

**Deliverable:** Fully functional pipeline from audio to suggestions.

### Phase 6: Polish + Testing (Days 12–14)

**Goal:** Stability, performance, distribution readiness.

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| `OnboardingView` — permission walkthrough   | 3h    |
| `LoginItemManager` — auto-launch            | 1h    |
| Memory profiling (Instruments)              | 2h    |
| CPU profiling under sustained use           | 2h    |
| Screen share invisibility QA                | 1h    |
| Multi-display support testing               | 2h    |
| Sleep/wake resilience                       | 1h    |
| Audio device change testing                 | 2h    |
| Unit tests for all actors                   | 3h    |
| Code signing + notarization                 | 3h    |
| Bug fixes + edge cases                      | 4h    |

**Deliverable:** Stable, notarized MVP ready for distribution.

### Timeline Summary

| Phase | Days   | Deliverable                    |
| ----- | ------ | ------------------------------ |
| 1     | 1–2    | Notch UI overlay               |
| 2     | 3–4    | Audio capture pipeline         |
| 3     | 5–6    | Live transcription             |
| 4     | 7–9    | AI context + suggestions       |
| 5     | 10–11  | End-to-end integration         |
| 6     | 12–14  | Polish, signing, testing       |

**Total: 14 working days (3 weeks)**

---

## 19. Technical Risks & Mitigations

| Risk                                     | Impact | Mitigation                                   |
| ---------------------------------------- | ------ | -------------------------------------------- |
| WhisperKit model too slow on older Macs  | High   | Fallback to SFSpeech; require Apple Silicon  |
| Claude API latency spikes                | Medium | Use Haiku for speed; cache recent suggestion |
| Claude suggestions not useful enough     | High   | Iterate prompts; let user rate suggestions   |
| Memory leak during long meetings         | High   | Strict 30s window; Instruments profiling     |
| App blocked by corporate MDM             | Medium | Document; offer manual API key entry         |
| WhisperKit CoreML audio leak (issue #393)| Medium | Pin v0.16.0+; monitor for fixes              |

---

## 20. Competitive Positioning

**Direct competitors:**

| Product      | Pricing       | Key differentiator                          |
| ------------ | ------------- | ------------------------------------------- |
| Convo        | $15-38/mo     | Native Swift, real-time suggestions         |
| Shmeetings   | $39 one-time  | 100% offline, Whisper + Llama               |
| Granola      | $10/mo        | On-device transcription, speaker ID         |
| Otter.ai     | $17/mo        | Native Mac app, searchable archives         |

**Notch Assistant differentiators:**

1. **Notch-native UX** — anchors to the physical notch, feels like a macOS
   system feature (no other app does this for meetings)
2. **Free / open-source** — vs. $15-38/mo competitors
3. **Claude-powered** — leverages latest Anthropic models
4. **Pure native macOS design** — matches Spotlight, not a generic floating panel
5. **Privacy-first** — local transcription, no bot in meetings, optional
   local-only mode

---

## 21. Future Roadmap (Post-MVP)

| Feature                    | Description                                       |
| -------------------------- | ------------------------------------------------- |
| Speaker diarization        | Identify who is speaking via voice embeddings     |
| Calendar integration       | Pre-load meeting context from calendar invite     |
| Meeting type profiles      | Different prompt strategies per meeting type      |
| Post-meeting summary       | Generate summary + action items when meeting ends |
| Knowledge base             | Feed user's docs/notes for richer suggestions     |
| Core Audio Taps            | System audio capture for remote participant audio |
| Multi-language support     | WhisperKit multilingual model + translated UI     |
| Local LLM option           | Llama.cpp for fully offline operation             |

---

End of Document
