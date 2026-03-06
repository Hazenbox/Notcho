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
| Platform                | macOS 14.2+ (Sonoma), Apple Silicon only  |
| Language                | Swift 5.9+ (strict concurrency)           |
| UI framework            | SwiftUI + AppKit (window mgmt)            |
| End-to-end latency      | < 5 seconds (realistic budget)            |
| Screen-share visibility | Invisible (`sharingType = .none`)         |
| LLM provider            | Anthropic Claude via SwiftAnthropic       |
| STT engine              | WhisperKit (local, Swift-native)          |
| System audio            | Core Audio Hardware Taps                  |
| Accessibility           | Full VoiceOver + keyboard navigation      |
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
│  │   (protocol)     │                      ▼                 │
│  │                  │           ┌─────────────────┐          │
│  └─────────────────┘            │  Transcription   │          │
│                                 │  (protocol)      │          │
│  ┌─────────────────┐            │                  │          │
│  │  Core Audio      │────────►  │  WhisperKit      │          │
│  │  Tap Capture     │            │  + SFSpeech      │          │
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
│         │                      │  (SwiftAnthropic)│           │
│         │                      └────────┬────────┘           │
│         │                               │ SuggestionResult   │
│         ▼                               ▼                    │
│  ┌────────────────────────────────────────────┐              │
│  │        Notch UI (SwiftUI + NSVisualEffect) │              │
│  │  @Observable ViewModel · @MainActor        │              │
│  │  Full VoiceOver accessibility              │              │
│  └────────────────────────────────────────────┘              │
└──────────────────────────────────────────────────────────────┘
```

**Concurrency model:** Swift Concurrency (structured concurrency with actors).

- `PipelineCoordinator` is an **actor** — the single owner of pipeline state.
- Audio capture and transcription produce `AsyncStream` values.
- Context Engine and Suggestion Generator are **actors** to avoid data races.
- The UI observes an `@Observable` ViewModel updated on `@MainActor`.
- **All major components use protocol abstractions for testability.**

---

## 3. Latency Budget

| Stage                  | Duration   | Strategy                              |
| ---------------------- | ---------- | ------------------------------------- |
| Audio chunk capture    | 3 seconds  | Rolling buffer, emit every 3s         |
| Transcription          | 0.3–1.0s   | WhisperKit local (base model)         |
| Context analysis       | < 50ms     | Local string ops + NaturalLanguage    |
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
- **Model download on first launch** with progress UI in onboarding
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

**Provider: Anthropic Claude via SwiftAnthropic package**

- Swift Package: `github.com/jamesrochabrun/SwiftAnthropic` (v2.1.8+)
- Production-tested with streaming, tool calling, proper SSE parsing
- No custom HTTP client needed — use the package's `AnthropicService`

| Model          | Speed   | Cost (input/output)     | Use case                  |
| -------------- | ------- | ----------------------- | ------------------------- |
| Claude Haiku   | ~1-2s   | $0.25 / $1.25 per 1M    | Default continuous mode   |
| Claude Sonnet  | ~2-4s   | $3.00 / $15.00 per 1M   | Quality mode (user toggle)|

**Default:** Claude Haiku for cost efficiency. User can enable "Quality Mode"
(Sonnet) for important meetings.

**Cost estimation (Haiku at 1 call per 8 seconds):**

- Per hour: ~$0.19
- Per month (80 hours): ~$15

**Cost estimation (Sonnet):**

- Per hour: ~$2.25
- Per month (80 hours): ~$180

**API version:** Use `anthropic-version: 2024-01-01` (latest stable).

### 4.4 Observability

**Crash Reporting: Sentry**

- Swift Package: `github.com/getsentry/sentry-cocoa`
- Automatic crash reports with stack traces
- Performance monitoring for latency tracking
- Privacy-compliant with data scrubbing

**Analytics: TelemetryDeck**

- Swift Package: `github.com/TelemetryDeck/SwiftClient`
- Privacy-first, GDPR-compliant, no cookie banners
- Track feature usage, model selection, error rates
- No PII collected

---

## 5. Protocol Abstractions (Dependency Injection)

All major components define protocol abstractions for testability and
flexibility. This follows the Dependency Inversion Principle.

```swift
// MARK: - Audio Capture Protocol

protocol AudioCapturing: Sendable {
    func startCapture() -> AsyncStream<AudioChunk>
    func stopCapture()
}

// MARK: - Transcription Protocol

protocol Transcribing: Sendable {
    func transcribe(_ chunk: AudioChunk) async throws -> TranscriptChunk
}

// MARK: - Suggestion Generation Protocol

protocol SuggestionGenerating: Sendable {
    func generate(from context: MeetingContext) async throws -> SuggestionResult
}

// MARK: - Meeting Detection Protocol

protocol MeetingDetecting: Sendable {
    func detectActiveMeeting() -> MeetingApp?
    func startMonitoring(onChange: @escaping (MeetingApp?) -> Void)
    func stopMonitoring()
}

// MARK: - Context Analysis Protocol

protocol ContextAnalyzing: Sendable {
    func update(with chunk: TranscriptChunk) async -> MeetingContext
    func reset() async
}
```

**Benefits:**

- Unit tests inject mock implementations
- Swap implementations without changing consumers
- Clear API contracts between components
- Enables parallel development

---

## 6. Data Models

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
    case unsupportedHardware          // Intel Mac
    case modelDownloadFailed(underlying: Error)
}
```

---

## 7. Project Structure

```
NotchAssistant/
├── NotchAssistant.xcodeproj
├── Package.swift                            // SPM dependencies
├── NotchAssistant/
│   ├── App/
│   │   ├── NotchAssistantApp.swift          // @main, app lifecycle
│   │   ├── AppDelegate.swift                // NSApplicationDelegate, menu bar
│   │   ├── PermissionManager.swift          // mic permission handling
│   │   ├── LoginItemManager.swift           // SMAppService auto-launch
│   │   ├── HardwareChecker.swift            // Apple Silicon verification
│   │   └── DependencyContainer.swift        // DI container for protocols
│   │
│   ├── UI/
│   │   ├── NotchWindowController.swift      // NSPanel setup, positioning
│   │   ├── NotchOverlayView.swift           // Main SwiftUI overlay
│   │   ├── FloatingPillView.swift           // Non-notch Mac fallback
│   │   ├── TranscriptView.swift             // Live scrolling transcript
│   │   ├── SuggestionCardView.swift         // Single suggestion/question/insight
│   │   ├── StatusIndicatorView.swift        // Listening/processing/error dot
│   │   ├── SettingsView.swift               // API key, model, role config
│   │   ├── OnboardingView.swift             // Permission + model download
│   │   ├── ModelDownloadView.swift          // WhisperKit model progress
│   │   └── NotchViewModel.swift             // @Observable, @MainActor
│   │
│   ├── Audio/
│   │   ├── Protocols/
│   │   │   └── AudioCapturing.swift         // Protocol definition
│   │   ├── AudioCaptureManager.swift        // AVAudioEngine mic capture
│   │   ├── CoreAudioTapCapture.swift        // Core Audio Hardware Taps
│   │   ├── AudioMixer.swift                 // Merge mic + system into one stream
│   │   ├── AudioDeviceMonitor.swift         // Route change notifications
│   │   ├── AudioBufferAccumulator.swift     // Thread-safe buffer (lock-based)
│   │   └── AudioChunk.swift                 // AudioChunk model
│   │
│   ├── Speech/
│   │   ├── Protocols/
│   │   │   └── Transcribing.swift           // Protocol definition
│   │   ├── WhisperKitTranscriber.swift      // WhisperKit Swift integration
│   │   ├── AppleSpeechTranscriber.swift     // SFSpeechRecognizer interim results
│   │   ├── TranscriptionRouter.swift        // Routes to WhisperKit or Apple
│   │   └── ModelDownloader.swift            // WhisperKit model download manager
│   │
│   ├── AI/
│   │   ├── Protocols/
│   │   │   └── SuggestionGenerating.swift   // Protocol definition
│   │   ├── ContextEngine.swift              // Actor: maintains MeetingContext
│   │   ├── SuggestionGenerator.swift        // Actor: calls Claude via SwiftAnthropic
│   │   ├── PromptBuilder.swift              // Constructs system/user prompts
│   │   ├── JSONResponseParser.swift         // Robust JSON extraction
│   │   └── TopicExtractor.swift             // NaturalLanguage-based topic detection
│   │
│   ├── Pipeline/
│   │   ├── PipelineCoordinator.swift        // Actor: orchestrates full pipeline
│   │   └── PipelineState.swift              // State enum + error types
│   │
│   ├── Detection/
│   │   ├── Protocols/
│   │   │   └── MeetingDetecting.swift       // Protocol definition
│   │   ├── MeetingDetector.swift            // Detects active meeting apps
│   │   └── MeetingApp.swift                 // Known app bundle IDs + display names
│   │
│   ├── Config/
│   │   ├── AppSettings.swift                // @AppStorage backed settings
│   │   └── KeychainManager.swift            // Secure API key storage
│   │
│   ├── Accessibility/
│   │   ├── AccessibilityIdentifiers.swift   // Centralized accessibility IDs
│   │   └── AccessibilityLabels.swift        // Localized accessibility strings
│   │
│   ├── Localization/
│   │   ├── Localizable.xcstrings            // String catalog
│   │   └── LocalizedStrings.swift           // Type-safe string keys
│   │
│   ├── Observability/
│   │   ├── CrashReporter.swift              // Sentry integration
│   │   └── Analytics.swift                  // TelemetryDeck integration
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
│   ├── Mocks/
│   │   ├── MockAudioCapture.swift
│   │   ├── MockTranscriber.swift
│   │   ├── MockSuggestionGenerator.swift
│   │   └── MockMeetingDetector.swift
│   ├── ContextEngineTests.swift
│   ├── PromptBuilderTests.swift
│   ├── PipelineCoordinatorTests.swift
│   ├── JSONResponseParserTests.swift
│   └── TopicExtractorTests.swift
│
└── README.md
```

---

## 8. Component Specifications

### 8.1 HardwareChecker (Apple Silicon Requirement)

```swift
import Foundation

enum HardwareChecker {
    static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    static func verifyOrExit() {
        guard isAppleSilicon else {
            let alert = NSAlert()
            alert.messageText = String(localized: "Unsupported Hardware")
            alert.informativeText = String(localized: "Notch Assistant requires a Mac with Apple Silicon (M1 or later) for real-time transcription.")
            alert.alertStyle = .critical
            alert.addButton(withTitle: String(localized: "Quit"))
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return
        }
    }
}
```

### 8.2 NotchWindowController

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
            let notchWidth: CGFloat = 200
            let notchHeight: CGFloat = 32
            let safeTop = screen.safeAreaInsets.top
            let x = screenFrame.midX - notchWidth / 2
            let y = screenFrame.maxY - safeTop - notchHeight
            return NSRect(x: x, y: y, width: notchWidth, height: notchHeight)
        } else {
            let pillWidth: CGFloat = 200
            let pillHeight: CGFloat = 32
            let x = screenFrame.midX - pillWidth / 2
            let y = screenFrame.maxY - 60
            return NSRect(x: x, y: y, width: pillWidth, height: pillHeight)
        }
    }

    func expand() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(expandedFrame(), display: true)
        }
    }

    func collapse() {
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

### 8.3 AudioBufferAccumulator (Thread-Safe)

Solves the actor isolation issue with `AVAudioEngine` tap closures.

```swift
import Foundation

/// Thread-safe audio buffer accumulator using locks.
/// Used because AVAudioEngine tap callbacks run on audio thread,
/// not within actor isolation.
final class AudioBufferAccumulator: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()
    private let targetSampleCount: Int
    private let onChunkReady: (Data) -> Void

    init(chunkDurationSeconds: Double, sampleRate: Double, onChunkReady: @escaping (Data) -> Void) {
        self.targetSampleCount = Int(chunkDurationSeconds * sampleRate)
        self.onChunkReady = onChunkReady
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(data)

        // 4 bytes per Float32 sample
        if buffer.count >= targetSampleCount * 4 {
            let chunk = buffer
            buffer = Data()
            // Call outside lock to avoid deadlock
            DispatchQueue.main.async { [weak self] in
                self?.onChunkReady(chunk)
            }
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        buffer = Data()
    }
}
```

### 8.4 AudioCaptureManager (Fixed)

```swift
final class AudioCaptureManager: AudioCapturing, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let targetSampleRate: Double = 16000
    private var accumulator: AudioBufferAccumulator?

    func startCapture() -> AsyncStream<AudioChunk> {
        AsyncStream { continuation in
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

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

            // Thread-safe accumulator
            accumulator = AudioBufferAccumulator(
                chunkDurationSeconds: 3.0,
                sampleRate: targetSampleRate
            ) { [weak self] chunkData in
                let chunk = AudioChunk(
                    id: UUID(),
                    timestamp: Date(),
                    pcmData: chunkData,
                    sampleRate: self?.targetSampleRate ?? 16000,
                    source: .microphone
                )
                continuation.yield(chunk)
            }

            inputNode.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: inputFormat
            ) { [weak self] buffer, _ in
                guard let self = self,
                      let converted = self.convert(buffer, using: converter),
                      let data = converted.toData() else { return }
                self.accumulator?.append(data)
            }

            do {
                try engine.start()
            } catch {
                continuation.finish()
                return
            }

            continuation.onTermination = { [weak self] _ in
                self?.stopCapture()
            }
        }
    }

    func stopCapture() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        accumulator?.reset()
        accumulator = nil
    }

    private func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: frameCount
        ) else { return nil }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        return error == nil ? outputBuffer : nil
    }
}

extension AVAudioPCMBuffer {
    func toData() -> Data? {
        guard let channelData = floatChannelData?[0] else { return nil }
        return Data(bytes: channelData, count: Int(frameLength) * 4)
    }
}
```

### 8.5 PipelineCoordinator (with Proper Cleanup)

```swift
actor PipelineCoordinator {
    private let audioCapture: any AudioCapturing
    private let transcriber: any Transcribing
    private let contextEngine: any ContextAnalyzing
    private let suggestionGen: any SuggestionGenerating
    private let meetingDetector: any MeetingDetecting
    private let viewModel: NotchViewModel
    private let analytics: Analytics

    private var pipelineTask: Task<Void, Never>?
    private var isShuttingDown = false

    init(
        audioCapture: any AudioCapturing,
        transcriber: any Transcribing,
        contextEngine: any ContextAnalyzing,
        suggestionGen: any SuggestionGenerating,
        meetingDetector: any MeetingDetecting,
        viewModel: NotchViewModel,
        analytics: Analytics
    ) {
        self.audioCapture = audioCapture
        self.transcriber = transcriber
        self.contextEngine = contextEngine
        self.suggestionGen = suggestionGen
        self.meetingDetector = meetingDetector
        self.viewModel = viewModel
        self.analytics = analytics
    }

    func start(meetingApp: MeetingApp?) {
        guard !isShuttingDown else { return }

        analytics.track("pipeline_started", properties: [
            "meeting_app": meetingApp?.name ?? "manual"
        ])

        pipelineTask = Task {
            let micStream = audioCapture.startCapture()

            for await chunk in micStream {
                guard !Task.isCancelled else { break }

                do {
                    let transcript = try await transcriber.transcribe(chunk)
                    let context = await contextEngine.update(with: transcript)

                    if shouldGenerateSuggestion(context) {
                        let suggestion = try await suggestionGen.generate(from: context)
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
                    analytics.track("pipeline_error", properties: [
                        "error": String(describing: error)
                    ])
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

    func stop() async {
        isShuttingDown = true
        pipelineTask?.cancel()
        pipelineTask = nil
        audioCapture.stopCapture()
        await contextEngine.reset()
        await viewModel.update(transcript: nil, suggestion: nil, state: .idle)
        isShuttingDown = false
        analytics.track("pipeline_stopped")
    }

    func handleAudioDeviceChange() async {
        await stop()
        try? await Task.sleep(for: .milliseconds(500))
        start(meetingApp: meetingDetector.detectActiveMeeting())
    }

    private func shouldGenerateSuggestion(_ context: MeetingContext) -> Bool {
        context.pendingQuestion != nil ||
        context.silenceGapDetected ||
        context.speakerChangeDetected
    }
}
```

### 8.6 ContextEngine (with Topic Extraction)

```swift
actor ContextEngine: ContextAnalyzing {
    private var transcriptWindow: [TranscriptChunk] = []
    private var currentTopic: String = ""
    private var keyPoints: [String] = []
    private let windowDuration: TimeInterval = 30
    private let topicExtractor = TopicExtractor()

    func update(with chunk: TranscriptChunk) async -> MeetingContext {
        transcriptWindow.append(chunk)
        pruneOldChunks()

        let fullText = transcriptWindow.map(\.text).joined(separator: " ")

        // Extract topic using NaturalLanguage framework
        if let extractedTopic = topicExtractor.extractTopic(from: fullText) {
            currentTopic = extractedTopic
        }

        return MeetingContext(
            topic: currentTopic,
            recentTranscript: transcriptWindow,
            keyPoints: keyPoints,
            pendingQuestion: detectQuestion(fullText),
            speakerChangeDetected: detectSpeakerChange(chunk),
            silenceGapDetected: detectSilenceGap(chunk)
        )
    }

    func reset() async {
        transcriptWindow.removeAll()
        currentTopic = ""
        keyPoints.removeAll()
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

    private func detectSpeakerChange(_ chunk: TranscriptChunk) -> Bool {
        // Use WhisperKit's VAD confidence drop as proxy
        guard transcriptWindow.count >= 2 else { return false }
        let previous = transcriptWindow[transcriptWindow.count - 2]
        return previous.confidence < 0.3 && chunk.confidence > 0.7
    }

    private func detectSilenceGap(_ chunk: TranscriptChunk) -> Bool {
        chunk.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
```

### 8.7 TopicExtractor (NaturalLanguage Framework)

```swift
import NaturalLanguage

final class TopicExtractor: Sendable {
    func extractTopic(from text: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
        tagger.string = text

        var nounCounts: [String: Int] = [:]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameTypeOrLexicalClass
        ) { tag, range in
            if tag == .noun || tag == .organizationName || tag == .placeName {
                let word = String(text[range]).lowercased()
                if word.count > 3 { // Skip short words
                    nounCounts[word, default: 0] += 1
                }
            }
            return true
        }

        // Return most frequent noun as topic
        return nounCounts
            .sorted { $0.value > $1.value }
            .first?
            .key
            .capitalized
    }
}
```

### 8.8 SuggestionGenerator (using SwiftAnthropic)

```swift
import SwiftAnthropic

actor SuggestionGenerator: SuggestionGenerating {
    private let service: AnthropicService
    private let promptBuilder: PromptBuilder
    private let responseParser: JSONResponseParser
    private var lastCallTime: Date = .distantPast
    private let minInterval: TimeInterval = 8
    private let settings: AppSettings

    init(apiKey: String, settings: AppSettings) {
        self.service = AnthropicServiceFactory.service(apiKey: apiKey)
        self.promptBuilder = PromptBuilder()
        self.responseParser = JSONResponseParser()
        self.settings = settings
    }

    func generate(from context: MeetingContext) async throws -> SuggestionResult {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastCallTime)
        if elapsed < minInterval {
            throw PipelineError.llmRateLimited(retryAfter: minInterval - elapsed)
        }
        lastCallTime = now

        let (system, userMessage) = promptBuilder.build(from: context)
        let model: Model = settings.qualityMode ? .claude35Sonnet : .claude35Haiku

        let parameters = MessageParameter(
            model: model,
            messages: [.init(role: .user, content: .text(userMessage))],
            maxTokens: 500,
            system: .text(system)
        )

        var fullResponse = ""

        let stream = try await service.streamMessage(parameters)
        for try await event in stream {
            if case .contentBlockDelta(let delta) = event,
               case .textDelta(let text) = delta.delta {
                fullResponse += text
            }
        }

        return responseParser.parse(fullResponse, context: context)
    }
}
```

### 8.9 JSONResponseParser (Robust)

```swift
final class JSONResponseParser: Sendable {
    func parse(_ response: String, context: MeetingContext) -> SuggestionResult {
        let cleanedJSON = extractJSON(from: response)

        guard let data = cleanedJSON.data(using: .utf8),
              let json = try? JSONDecoder().decode(SuggestionJSON.self, from: data) else {
            // Fallback: use raw response as suggestion
            return SuggestionResult(
                id: UUID(),
                timestamp: Date(),
                suggestion: response.trimmingCharacters(in: .whitespacesAndNewlines),
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

    /// Extracts JSON object from response that may contain markdown fences or preamble
    private func extractJSON(from response: String) -> String {
        var cleaned = response

        // Remove markdown code fences
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")

        // Find JSON object boundaries
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else {
            return response
        }

        return String(cleaned[start...end])
    }

    struct SuggestionJSON: Codable {
        let suggestion: String
        let question: String
        let insight: String
    }
}
```

### 8.10 MeetingDetector (Enhanced)

```swift
import AppKit
import CoreAudio

final class MeetingDetector: MeetingDetecting {
    static let knownMeetingApps: [MeetingApp] = [
        MeetingApp(name: "Zoom", bundleID: "us.zoom.xos", windowPatterns: ["Meeting", "Zoom"]),
        MeetingApp(name: "Google Meet", bundleID: "com.google.Chrome", windowPatterns: ["Meet -", "meet.google.com"]),
        MeetingApp(name: "Microsoft Teams", bundleID: "com.microsoft.teams2", windowPatterns: ["Meeting", "Call"]),
        MeetingApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", windowPatterns: ["Huddle"]),
        MeetingApp(name: "FaceTime", bundleID: "com.apple.FaceTime", windowPatterns: []),
        MeetingApp(name: "Discord", bundleID: "com.hnc.Discord", windowPatterns: ["Voice Connected"]),
        MeetingApp(name: "Webex", bundleID: "com.webex.meetingmanager", windowPatterns: ["Meeting"]),
    ]

    private var workspaceObserver: NSObjectProtocol?

    func detectActiveMeeting() -> MeetingApp? {
        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications

        for app in Self.knownMeetingApps {
            guard let runningApp = running.first(where: { $0.bundleIdentifier == app.bundleID }) else {
                continue
            }

            // Check if app is active or has audio session
            if runningApp.isActive || isAppUsingAudio(bundleID: app.bundleID) {
                // For Chrome-based apps, check window title
                if app.bundleID == "com.google.Chrome" {
                    if hasMatchingWindow(app: runningApp, patterns: app.windowPatterns) {
                        return app
                    }
                } else {
                    return app
                }
            }
        }
        return nil
    }

    func startMonitoring(onChange: @escaping (MeetingApp?) -> Void) {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            onChange(self?.detectActiveMeeting())
        }
    }

    func stopMonitoring() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func isAppUsingAudio(bundleID: String) -> Bool {
        // Check if app has active audio session via Core Audio
        // This is a simplified check; full implementation would query audio devices
        return true // Placeholder
    }

    private func hasMatchingWindow(app: NSRunningApplication, patterns: [String]) -> Bool {
        // Would require Accessibility API to get window titles
        // For MVP, just check if app is active
        return app.isActive
    }
}

struct MeetingApp: Sendable {
    let name: String
    let bundleID: String
    let windowPatterns: [String]
}
```

---

## 9. UI Design — Pure Native macOS System Look

### 9.1 Design Principles

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

### 9.2 Color Palette

```swift
let primaryLabel = NSColor.labelColor
let secondaryLabel = NSColor.secondaryLabelColor
let tertiaryLabel = NSColor.tertiaryLabelColor
let separator = NSColor.separatorColor
let accent = NSColor.controlAccentColor

let listening = NSColor.systemGreen
let processing = NSColor.systemYellow
let error = NSColor.systemRed
```

### 9.3 Typography

```swift
Font.system(.caption, design: .monospaced)  // Transcript: SF Mono, 11pt
Font.system(.body)                          // Suggestions: SF Pro, 13pt
Font.system(.caption2).uppercased()         // Labels: SF Pro, 10pt
Font.system(.caption)                       // Status: SF Pro, 11pt
```

### 9.4 SF Symbols Used

| Purpose           | Symbol                        |
| ----------------- | ----------------------------- |
| Status listening  | `circle.fill` (green tint)    |
| Status processing | `circle.fill` (yellow tint)   |
| Status error      | `exclamationmark.circle.fill` |
| Copy              | `doc.on.doc`                  |
| Regenerate        | `arrow.clockwise`             |
| Close             | `xmark`                       |
| Settings          | `gear`                        |
| Mic active        | `mic.fill`                    |
| Mic muted         | `mic.slash`                   |

---

## 10. Accessibility

All UI elements must be accessible via VoiceOver and keyboard navigation.

### 10.1 Accessibility Identifiers

```swift
enum AccessibilityIdentifiers {
    static let statusIndicator = "status-indicator"
    static let transcriptView = "transcript-view"
    static let suggestionCard = "suggestion-card"
    static let questionCard = "question-card"
    static let insightCard = "insight-card"
    static let copyButton = "copy-button"
    static let regenerateButton = "regenerate-button"
    static let closeButton = "close-button"
    static let expandButton = "expand-button"
}
```

### 10.2 Implementation

```swift
struct StatusIndicatorView: View {
    let state: PipelineState

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(AccessibilityIdentifiers.statusIndicator)
    }

    private var accessibilityLabel: String {
        String(localized: "Meeting Assistant Status")
    }

    private var accessibilityValue: String {
        switch state {
        case .idle: return String(localized: "Idle")
        case .listening: return String(localized: "Listening to meeting")
        case .processing: return String(localized: "Processing audio")
        case .error: return String(localized: "Error occurred")
        }
    }
}

struct SuggestionCardView: View {
    let title: String
    let content: String
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(content)
                .font(.body)

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .accessibilityLabel(String(localized: "Copy to clipboard"))
            .accessibilityHint(String(localized: "Copies this suggestion to your clipboard"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(content)
    }
}
```

### 10.3 Keyboard Navigation

```swift
struct NotchOverlayView: View {
    @FocusState private var focusedElement: FocusableElement?

    enum FocusableElement: Hashable {
        case suggestion, question, insight, regenerate, copyAll, close
    }

    var body: some View {
        VStack {
            // ... content ...
        }
        .focusable()
        .onKeyPress(.tab) {
            advanceFocus()
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }
}
```

---

## 11. Localization

All user-facing strings use `String(localized:)` for i18n support.

### 11.1 String Catalog Structure

```
Localization/
├── Localizable.xcstrings     // Main string catalog
└── InfoPlist.xcstrings       // Info.plist strings
```

### 11.2 Usage Pattern

```swift
// Always use localized strings
Text(String(localized: "Listening", comment: "Status when actively listening"))

// With interpolation
Text(String(localized: "Topic: \(topic)", comment: "Current meeting topic"))

// Accessibility
.accessibilityLabel(String(localized: "Copy suggestion to clipboard"))
```

### 11.3 Initial Localizations

- English (en) — default
- Add more post-MVP based on demand

---

## 12. Permission Handling

| Permission    | API                             | Required for    | If denied                        |
| ------------- | ------------------------------- | --------------- | -------------------------------- |
| Microphone    | `AVCaptureDevice.requestAccess` | Mic capture     | App cannot function — show error |
| Accessibility | `AXIsProcessTrusted`            | Global hotkeys  | Hotkeys disabled, menu bar only  |

**Onboarding flow:**

1. Hardware check (Apple Silicon required)
2. Welcome screen explaining what the app does
3. Request Microphone — required, block if denied
4. WhisperKit model download with progress indicator
5. Request Accessibility — optional, explain hotkeys benefit
6. API key entry (Claude) — required
7. Ready screen

---

## 13. Meeting Detection

See Section 8.10 for enhanced `MeetingDetector` implementation.

**Modes:**

- **Auto:** Start pipeline when meeting app detected, stop when it quits.
- **Manual:** User toggles via hotkey or menu bar click.
- **Always-on:** Pipeline runs continuously (battery-intensive, warn user).

---

## 14. Configuration & Settings

```swift
struct AppSettings {
    @AppStorage("userRole") var userRole: String = "Software Engineer"
    @AppStorage("transcriptionEngine") var engine: TranscriptionEngine = .whisperKit
    @AppStorage("claudeModel") var claudeModel: ClaudeModel = .haiku
    @AppStorage("qualityMode") var qualityMode: Bool = false
    @AppStorage("audioChunkDuration") var chunkDuration: Double = 3.0
    @AppStorage("transcriptWindow") var transcriptWindow: Double = 30.0
    @AppStorage("llmCallInterval") var llmCallInterval: Double = 8.0
    @AppStorage("meetingDetectionMode") var detectionMode: DetectionMode = .auto
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("analyticsEnabled") var analyticsEnabled: Bool = true
}

enum TranscriptionEngine: String, CaseIterable {
    case whisperKit
    case appleSpeech
}

enum ClaudeModel: String, CaseIterable {
    case haiku = "claude-3-5-haiku-latest"
    case sonnet = "claude-3-5-sonnet-latest"
}

enum DetectionMode: String, CaseIterable {
    case auto
    case manual
    case alwaysOn
}
```

---

## 15. Keyboard Shortcuts

| Shortcut    | Action                            |
| ----------- | --------------------------------- |
| Cmd+Shift+M | Toggle expand/collapse            |
| Cmd+Shift+H | Hide completely                   |
| Cmd+Shift+S | Force generate suggestion now     |
| Cmd+Shift+L | Toggle listening on/off           |
| Cmd+Shift+C | Copy last suggestion to clipboard |

Registered via `NSEvent.addGlobalMonitorForEvents` (requires Accessibility
permission) with `NSEvent.addLocalMonitorForEvents` as fallback.

---

## 16. Login Item (Auto-Launch)

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
            CrashReporter.capture(error)
        }
    }

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
```

---

## 17. Error Handling Strategy

### 17.1 Retry Policy

| Error type           | Retry | Max attempts | Backoff        |
| -------------------- | ----- | ------------ | -------------- |
| Network timeout      | Yes   | 3            | Exponential 1s |
| Claude rate limit    | Yes   | 1            | Retry-After hdr|
| Claude 500 error     | Yes   | 2            | Fixed 2s       |
| Transcription fail   | Yes   | 1            | Switch engine  |
| Permission denied    | No    | —            | Show settings  |
| Audio device changed | No    | —            | Restart capture|

### 17.2 Fallback Chain

```
Transcription: WhisperKit → SFSpeechRecognizer
Audio:         Mic + System → Mic only → Pause + notify
```

### 17.3 UI Error States

- **Transient errors** (network blip): yellow status dot, auto-retry silently.
- **Degraded mode** (system audio unavailable): orange dot + banner.
- **Fatal errors** (mic denied): red dot + overlay with "Open System Settings".

---

## 18. Distribution & Signing

### 18.1 Required Entitlements

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

### 18.2 Info.plist Privacy Descriptions

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Notch Assistant needs microphone access to transcribe meeting audio and provide real-time suggestions.</string>
```

### 18.3 Hardened Runtime

Enable in Xcode: Signing & Capabilities → Hardened Runtime → Allow Microphone Access

### 18.4 Code Signing & Notarization
go
```bash
codesign --force --deep --sign "Developer ID Application: Your Name (TEAMID)" \
    --entitlements NotchAssistant.entitlements \
    --options runtime \
    NotchAssistant.app

ditto -c -k --keepParent NotchAssistant.app NotchAssistant.zip

xcrun notarytool submit NotchAssistant.zip \
    --apple-id "you@example.com" \
    --team-id "TEAMID" \
    --password "@keychain:AC_PASSWORD" \
    --wait

xcrun stapler staple NotchAssistant.app
```

---

## 19. Privacy & Security

| Feature                   | Implementation                             |
| ------------------------- | ------------------------------------------ |
| No transcript persistence | Transcript buffer is in-memory only        |
| Screen-share invisible    | `panel.sharingType = .none`                |
| API keys in Keychain      | `KeychainManager` wraps Security framework |
| Meeting-only listening    | Auto-start/stop via MeetingDetector        |
| Clear on meeting end      | `contextEngine.reset()` called on stop     |
| Analytics opt-out         | User toggle in Settings                    |

---

## 20. Testing Strategy

### 20.1 Unit Tests

| Component          | What to test                                  |
| ------------------ | --------------------------------------------- |
| ContextEngine      | Transcript window pruning, question detection |
| PromptBuilder      | Prompt formatting, edge cases                 |
| MeetingDetector    | Known app matching, edge cases                |
| SuggestionGenerator| Rate limiting, JSON parsing                   |
| JSONResponseParser | Markdown fence stripping, malformed JSON      |
| TopicExtractor     | Noun extraction, frequency counting           |
| AppSettings        | Default values, persistence                   |

### 20.2 Integration Tests

| Test                 | Description                                  |
| -------------------- | -------------------------------------------- |
| Audio → Transcript   | Feed a WAV file, verify transcription output |
| Transcript → Context | Feed transcript chunks, verify context state |
| Context → Suggestion | Feed context, verify Claude call + parsed    |
| Full pipeline        | End-to-end with mock audio input             |

### 20.3 Manual QA Checklist

- [ ] Overlay positions correctly on notch MacBooks (14", 16")
- [ ] Floating pill positions correctly on non-notch Macs
- [ ] Overlay invisible during screen share (Zoom, Meet)
- [ ] Expand/collapse animation smooth at 60fps
- [ ] Hotkeys work globally when Accessibility granted
- [ ] Pipeline starts automatically when Zoom launches
- [ ] Pipeline stops cleanly when meeting ends
- [ ] App handles sleep/wake without crashing
- [ ] App handles headphone plug/unplug without crashing
- [ ] Memory stays under 200MB during 1-hour meeting
- [ ] CPU stays under 15% average during listening
- [ ] VoiceOver reads all elements correctly
- [ ] Keyboard navigation works in expanded state
- [ ] Intel Mac shows friendly error and quits
- [ ] Model download shows progress and handles offline

---

## 21. Dependencies (Package.swift)

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchAssistant",
    platforms: [.macOS(.v14)],
    dependencies: [
        // LLM
        .package(url: "https://github.com/jamesrochabrun/SwiftAnthropic", from: "2.1.8"),

        // Speech-to-Text
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.16.0"),

        // Crash Reporting
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.0.0"),

        // Analytics
        .package(url: "https://github.com/TelemetryDeck/SwiftClient", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "NotchAssistant",
            dependencies: [
                .product(name: "SwiftAnthropic", package: "SwiftAnthropic"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "TelemetryDeck", package: "SwiftClient"),
            ]
        ),
        .testTarget(
            name: "NotchAssistantTests",
            dependencies: ["NotchAssistant"]
        ),
    ]
)
```

---

## 22. Build Phases & Timeline

### Phase 1: Foundation + Notch UI (Days 1–2)

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| Xcode project setup, SPM dependencies       | 2h    |
| `HardwareChecker` — Apple Silicon gate      | 1h    |
| `DependencyContainer` — protocol setup      | 2h    |
| `NotchWindowController` with safeAreaInsets | 3h    |
| Non-notch fallback (floating pill)          | 2h    |
| `NotchOverlayView` — collapsed state        | 2h    |
| `NotchOverlayView` — expanded state         | 3h    |
| Accessibility labels + identifiers          | 2h    |
| `NotchViewModel` with mock data             | 1h    |
| `sharingType = .none` verification          | 1h    |

**Deliverable:** Accessible overlay with mock data, invisible during screen share.

### Phase 2: Audio Capture (Days 3–4)

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| `AudioCapturing` protocol                   | 1h    |
| `PermissionManager` — microphone            | 2h    |
| `AudioBufferAccumulator` — thread-safe      | 2h    |
| `AudioCaptureManager` — AVAudioEngine tap   | 3h    |
| Audio format conversion to 16kHz mono       | 2h    |
| `AudioDeviceMonitor` — route changes        | 2h    |
| `MeetingDetector` — enhanced detection      | 3h    |

**Deliverable:** Audio chunks stream with proper concurrency safety.

### Phase 3: Transcription (Days 5–6)

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| `Transcribing` protocol                     | 1h    |
| `ModelDownloader` — WhisperKit download UI  | 3h    |
| `WhisperKitTranscriber` — load model, infer | 4h    |
| `AppleSpeechTranscriber` — SFSpeech setup   | 2h    |
| `TranscriptionRouter` — engine selection    | 2h    |
| Audio → transcript integration test         | 2h    |

**Deliverable:** Live transcript with model download onboarding.

### Phase 4: Context Engine + AI Suggestions (Days 7–9)

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| `ContextAnalyzing` protocol                 | 1h    |
| `ContextEngine` — sliding window, pruning   | 2h    |
| `TopicExtractor` — NaturalLanguage          | 2h    |
| `SuggestionGenerating` protocol             | 1h    |
| `SuggestionGenerator` — SwiftAnthropic      | 3h    |
| `JSONResponseParser` — robust extraction    | 2h    |
| `PromptBuilder` — template + formatting     | 2h    |
| `KeychainManager` — API key storage         | 2h    |
| Context → suggestion integration test       | 2h    |

**Deliverable:** AI suggestions appear in overlay based on live transcript.

### Phase 5: Pipeline Integration (Days 10–11)

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| `PipelineCoordinator` — full orchestration  | 4h    |
| Error handling + fallback chains            | 3h    |
| Keyboard shortcuts (global + local)         | 3h    |
| Menu bar integration (status item)          | 2h    |
| `SettingsView` — configuration UI           | 3h    |
| `CrashReporter` + `Analytics` integration   | 2h    |

**Deliverable:** Fully functional pipeline with observability.

### Phase 6: Polish + Testing (Days 12–14)

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| `OnboardingView` — full walkthrough         | 3h    |
| `LoginItemManager` — auto-launch            | 1h    |
| VoiceOver testing + fixes                   | 2h    |
| Keyboard navigation testing                 | 1h    |
| Memory profiling (Instruments)              | 2h    |
| CPU profiling under sustained use           | 2h    |
| Screen share invisibility QA                | 1h    |
| Multi-display support testing               | 2h    |
| Unit tests with mock protocols              | 4h    |
| Code signing + notarization                 | 3h    |
| Bug fixes + edge cases                      | 4h    |

**Deliverable:** Stable, accessible, notarized MVP.

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

## 23. Technical Risks & Mitigations

| Risk                                     | Impact | Mitigation                                   |
| ---------------------------------------- | ------ | -------------------------------------------- |
| WhisperKit model too slow on older Macs  | High   | Require Apple Silicon, fallback to SFSpeech  |
| Claude API latency spikes                | Medium | Use Haiku, cache recent suggestion           |
| Claude suggestions not useful enough     | High   | Iterate prompts, add user feedback mechanism |
| Memory leak during long meetings         | High   | Strict 30s window, Instruments profiling     |
| App blocked by corporate MDM             | Medium | Document, offer manual API key entry         |
| WhisperKit CoreML audio leak (#393)      | Medium | Pin v0.16.0+, monitor for fixes              |
| Accessibility issues                     | Medium | Test with VoiceOver throughout development   |

---

## 24. Competitive Positioning

**Direct competitors:**

| Product    | Pricing      | Key differentiator                  |
| ---------- | ------------ | ----------------------------------- |
| Convo      | $15-38/mo    | Native Swift, real-time suggestions |
| Shmeetings | $39 one-time | 100% offline, Whisper + Llama       |
| Granola    | $10/mo       | On-device transcription, speaker ID |
| Otter.ai   | $17/mo       | Native Mac app, searchable archives |

**Notch Assistant differentiators:**

1. **Notch-native UX** — anchors to the physical notch
2. **Free / open-source** — vs. $15-38/mo competitors
3. **Claude-powered** — latest Anthropic models
4. **Pure native macOS design** — matches Spotlight aesthetic
5. **Privacy-first** — local transcription, no bot in meetings
6. **Full accessibility** — VoiceOver + keyboard navigation

---

## 25. Future Roadmap (Post-MVP)

| Feature              | Description                                   |
| -------------------- | --------------------------------------------- |
| Speaker diarization  | Identify who is speaking via voice embeddings |
| Calendar integration | Pre-load meeting context from calendar invite |
| Meeting type profiles| Different prompts per meeting type            |
| Post-meeting summary | Generate summary when meeting ends            |
| Knowledge base       | Feed user's docs for richer suggestions       |
| Core Audio Taps      | System audio capture for remote participants  |
| Multi-language       | WhisperKit multilingual + translated UI       |
| Local LLM            | Llama.cpp for fully offline operation         |

---

End of Document
