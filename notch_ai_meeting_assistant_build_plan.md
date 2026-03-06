# Notch AI Meeting Assistant — Engineering Build Plan

## 1. Product Summary

A native macOS application that anchors to the MacBook camera notch and acts as
a real-time AI meeting copilot. It captures meeting audio, transcribes
conversations, maintains conversational context, and surfaces AI-generated
suggestions, questions, and insights — all within a discreet overlay UI.

**Hard constraints:**

| Constraint             | Target                          |
| ---------------------- | ------------------------------- |
| Platform               | macOS 14+ (Sonoma)              |
| Language               | Swift 5.9+                      |
| UI framework           | SwiftUI + AppKit (window mgmt)  |
| End-to-end latency     | < 5 seconds (realistic budget)  |
| Screen-share visibility | Invisible (`sharingType = .none`) |
| Build tooling          | Cursor (AI-assisted)            |

---

## 2. System Architecture

```
┌──────────────────────────────────────────────────────────┐
│                      macOS App Process                   │
│                                                          │
│  ┌─────────────┐    AsyncStream<AudioChunk>              │
│  │   Audio      │──────────────────────┐                 │
│  │   Capture    │                      │                 │
│  │   Manager    │                      ▼                 │
│  └─────────────┘              ┌─────────────────┐        │
│                               │  Transcription   │        │
│                               │  Engine          │        │
│  ┌─────────────┐              │  (Whisper.cpp    │        │
│  │  Meeting     │              │   + SFSpeech     │        │
│  │  Detector    │              │   fallback)      │        │
│  └──────┬──────┘              └────────┬────────┘        │
│         │ start/stop                   │                 │
│         ▼                              │ AsyncStream     │
│  ┌─────────────┐                       │ <Transcript     │
│  │  Pipeline    │◄─────────────────────┘  Chunk>         │
│  │  Coordinator │                                        │
│  │  (Actor)     │──────────┐                             │
│  └──────┬──────┘           │                             │
│         │                  ▼                             │
│         │          ┌─────────────────┐                   │
│         │          │  Context Engine  │                   │
│         │          │  (Actor)         │                   │
│         │          └────────┬────────┘                   │
│         │                   │ MeetingContext              │
│         │                   ▼                             │
│         │          ┌─────────────────┐                   │
│         │          │  Suggestion     │                   │
│         │          │  Generator      │                   │
│         │          └────────┬────────┘                   │
│         │                   │ SuggestionResult           │
│         ▼                   ▼                             │
│  ┌────────────────────────────────┐                      │
│  │        Notch UI (SwiftUI)      │                      │
│  │  @Observable ViewModel         │                      │
│  └────────────────────────────────┘                      │
└──────────────────────────────────────────────────────────┘
```

**Concurrency model:** Swift Concurrency (structured concurrency with actors).

- `PipelineCoordinator` is an **actor** — the single owner of pipeline state.
- Audio capture and transcription produce `AsyncStream` values.
- Context Engine and Suggestion Generator are **actors** to avoid data races.
- The UI observes an `@Observable` ViewModel updated on `@MainActor`.

---

## 3. Latency Budget

The original plan targeted < 2s end-to-end. That is not achievable with batch
Whisper + GPT round trips. Here is a realistic breakdown:

| Stage                  | Duration   | Strategy                        |
| ---------------------- | ---------- | ------------------------------- |
| Audio chunk capture    | 3 seconds  | Rolling buffer, emit every 3s   |
| Transcription          | 0.5–1.5s   | Whisper.cpp local (tiny/base)   |
| Context analysis       | < 50ms     | Local string ops, no network    |
| LLM suggestion         | 1–3s       | GPT-4o-mini / streaming         |
| UI render              | < 16ms     | SwiftUI diffing                 |
| **Total**              | **~5–8s**  |                                 |

**Optimizations to approach 5s:**

1. **Overlap capture and processing** — while chunk N+1 is recording, chunk N
   is being transcribed and analyzed.
2. **Stream LLM responses** — show suggestions token-by-token as they arrive.
3. **Debounce LLM calls** — only trigger when the context engine detects a
   meaningful change (new topic, question directed at user, silence gap).
4. **Use Apple SFSpeechRecognizer for interim results** — show live partial
   transcript while Whisper processes the full chunk for accuracy.

---

## 4. Technology Decisions

### 4.1 Audio Capture

| Source         | API                  | Notes                                        |
| -------------- | -------------------- | -------------------------------------------- |
| Microphone     | `AVAudioEngine`      | Requires Microphone permission               |
| System audio   | `ScreenCaptureKit`   | macOS 13+; requires Screen Recording perm    |

**System audio filtering:** Use `SCContentFilter` to capture audio only from
the target meeting app (Zoom, Google Meet, Teams, Slack). The Meeting Detector
identifies the active app and constructs the filter.

**Audio format:**

```swift
let format = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16000,       // Whisper expects 16kHz
    channels: 1,             // mono
    interleaved: false
)!
```

**Fallback:** If ScreenCaptureKit permission is denied, operate in mic-only
mode and inform the user that only their voice will be captured.

### 4.2 Speech-to-Text

**Primary: Whisper.cpp (local)**

- Model: `ggml-base.en` (~140MB) for English, `ggml-small` (~460MB) for
  multilingual.
- Runs on-device — no network latency, no API costs, better privacy.
- Use the Swift binding `whisper.swiftui` or call via C bridge.

**Secondary: Apple SFSpeechRecognizer (interim results)**

- Provides real-time partial transcripts with very low latency.
- Used for the live transcript display while Whisper processes the definitive
  chunk.
- Does not require network on macOS 14+ (on-device model available).

**Cloud fallback: OpenAI Whisper API**

- Used only if local Whisper fails or user opts for higher accuracy.
- Adds 1–3s network latency per chunk.

### 4.3 LLM for Suggestions

**Primary: OpenAI GPT-4o-mini**

- Fast, cheap ($0.15/1M input tokens), good enough for suggestion quality.
- Use streaming (`stream: true`) to display suggestions progressively.

**Fallback: Local LLM via llama.cpp**

- For offline mode or privacy-sensitive users.
- Model: Phi-3-mini or Llama-3.2-1B (fits in ~2GB RAM).

### 4.4 Networking

- HTTP client: `URLSession` with async/await.
- Streaming: `URLSession.AsyncBytes` for SSE parsing of OpenAI streams.
- No third-party HTTP libraries needed.

---

## 5. Data Models

```swift
// MARK: - Audio

struct AudioChunk: Sendable {
    let id: UUID
    let timestamp: Date
    let buffer: AVAudioPCMBuffer
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
    let isInterim: Bool          // true = SFSpeech partial, false = Whisper final
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
    case screenCapturePermissionDenied
    case transcriptionFailed(underlying: Error)
    case llmRequestFailed(underlying: Error)
    case llmRateLimited(retryAfter: TimeInterval)
    case networkUnavailable
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
│   │   └── PermissionManager.swift          // mic, screen recording, accessibility
│   │
│   ├── UI/
│   │   ├── NotchWindowController.swift      // NSPanel setup, positioning, level
│   │   ├── NotchOverlayView.swift           // Main SwiftUI overlay
│   │   ├── TranscriptView.swift             // Live scrolling transcript
│   │   ├── SuggestionCardView.swift         // Single suggestion/question/insight
│   │   ├── StatusIndicatorView.swift        // Listening/processing/error dot
│   │   ├── SettingsView.swift               // API keys, model, role config
│   │   ├── OnboardingView.swift             // Permission walkthrough
│   │   └── NotchViewModel.swift             // @Observable, @MainActor
│   │
│   ├── Audio/
│   │   ├── AudioCaptureManager.swift        // AVAudioEngine mic capture
│   │   ├── SystemAudioCapture.swift         // ScreenCaptureKit system audio
│   │   ├── AudioMixer.swift                 // Merge mic + system into one stream
│   │   └── AudioChunk.swift                 // AudioChunk model
│   │
│   ├── Speech/
│   │   ├── WhisperTranscriber.swift         // Whisper.cpp Swift bridge
│   │   ├── AppleSpeechTranscriber.swift     // SFSpeechRecognizer interim results
│   │   ├── TranscriptionRouter.swift        // Routes to Whisper or Apple or API
│   │   └── WhisperAPIClient.swift           // OpenAI Whisper API fallback
│   │
│   ├── AI/
│   │   ├── ContextEngine.swift              // Actor: maintains MeetingContext
│   │   ├── SuggestionGenerator.swift        // Actor: calls LLM, parses response
│   │   ├── PromptBuilder.swift              // Constructs system/user prompts
│   │   └── OpenAIClient.swift               // URLSession-based, streaming support
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
│       ├── ggml-base.en.bin                 // Whisper model (bundled or downloaded)
│       └── Assets.xcassets
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

Manages the `NSPanel` that anchors to the notch.

```swift
final class NotchWindowController {
    private var panel: NSPanel!

    func setup() {
        panel = NSPanel(
            contentRect: calculateNotchFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar + 1
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false   // allow clicks on suggestions
    }

    private func calculateNotchFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let notchWidth: CGFloat = 200       // collapsed width
        let notchHeight: CGFloat = 32       // collapsed height
        let screenFrame = screen.frame
        let x = screenFrame.midX - notchWidth / 2
        let y = screenFrame.maxY - notchHeight
        return NSRect(x: x, y: y, width: notchWidth, height: notchHeight)
    }

    func expand() {
        // Animate to expanded size (200x400) to show suggestions
    }

    func collapse() {
        // Animate back to compact indicator
    }
}
```

**States:**

| State      | Size     | Content                              |
| ---------- | -------- | ------------------------------------ |
| Collapsed  | 200x32   | Status dot + "Listening" label       |
| Expanded   | 320x420  | Transcript + suggestions + controls  |
| Hidden     | 0x0      | Fully hidden, hotkey to restore      |

### 7.2 AudioCaptureManager

```swift
actor AudioCaptureManager {
    private let engine = AVAudioEngine()

    func startCapture() -> AsyncStream<AudioChunk> {
        AsyncStream { continuation in
            let inputNode = engine.inputNode
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            )!

            inputNode.installTap(
                onBus: 0,
                bufferSize: 48000,   // 3 seconds at 16kHz
                format: format
            ) { buffer, time in
                let chunk = AudioChunk(
                    id: UUID(),
                    timestamp: Date(),
                    buffer: buffer,
                    source: .microphone
                )
                continuation.yield(chunk)
            }

            try? engine.start()

            continuation.onTermination = { _ in
                inputNode.removeTap(onBus: 0)
                self.engine.stop()
            }
        }
    }
}
```

### 7.3 PipelineCoordinator

The central orchestrator. Owns the pipeline lifecycle.

```swift
actor PipelineCoordinator {
    private let audioCapture: AudioCaptureManager
    private let systemAudio: SystemAudioCapture
    private let transcriber: TranscriptionRouter
    private let contextEngine: ContextEngine
    private let suggestionGen: SuggestionGenerator
    private let viewModel: NotchViewModel

    private var pipelineTask: Task<Void, Never>?

    func start(meetingApp: MeetingApp?) {
        pipelineTask = Task {
            let micStream = await audioCapture.startCapture()
            // Optionally merge with system audio stream

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
}
```

### 7.4 ContextEngine

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
        // Heuristic: last sentence ends with "?"
        // or contains question markers ("what do you think", "any thoughts")
        let sentences = text.components(separatedBy: ". ")
        guard let last = sentences.last else { return nil }
        let questionPatterns = ["?", "what do you think", "any thoughts",
                                "does that make sense", "agree"]
        if questionPatterns.contains(where: { last.lowercased().contains($0) }) {
            return last
        }
        return nil
    }

    private func detectTopic(_ text: String) -> String {
        // Extract most frequent noun phrases (simple TF approach)
        // In v2, use LLM for topic extraction
        currentTopic
    }

    private func extractKeyPoints(_ text: String) -> [String] {
        keyPoints
    }

    private func detectSpeakerChange(_ chunk: TranscriptChunk) -> Bool {
        // In MVP: detect significant silence gaps as proxy for speaker change
        false
    }

    private func detectSilenceGap(_ chunk: TranscriptChunk) -> Bool {
        chunk.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
```

### 7.5 SuggestionGenerator + PromptBuilder

```swift
actor SuggestionGenerator {
    private let client: OpenAIClient
    private let promptBuilder: PromptBuilder
    private var lastCallTime: Date = .distantPast
    private let minInterval: TimeInterval = 8     // don't call LLM more than 1x/8s

    func generate(from context: MeetingContext) async throws -> SuggestionResult {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastCallTime)
        if elapsed < minInterval {
            throw PipelineError.llmRateLimited(retryAfter: minInterval - elapsed)
        }
        lastCallTime = now

        let prompt = promptBuilder.build(from: context)
        let response = try await client.chatCompletion(
            model: "gpt-4o-mini",
            messages: prompt,
            stream: true
        )

        return parse(response)
    }
}
```

**Prompt template:**

```swift
struct PromptBuilder {
    var userRole: String = "Senior Product Designer"  // configurable

    func build(from context: MeetingContext) -> [ChatMessage] {
        let system = """
        You are a real-time meeting assistant for a \(userRole).
        You will receive the last 30 seconds of meeting transcript.
        Respond with EXACTLY this JSON format, nothing else:
        {"suggestion": "...", "question": "...", "insight": "..."}

        Rules:
        - suggestion: A concise response the user could say next (1-2 sentences).
        - question: A strategic question that advances the discussion.
        - insight: A brief observation about the conversation dynamics or topic.
        - Be specific to the transcript. Never be generic.
        - If the transcript is unclear or trivial, respond with empty strings.
        """

        let transcript = context.recentTranscript
            .map(\.text)
            .joined(separator: " ")

        let user = """
        Current topic: \(context.topic)
        Key points so far: \(context.keyPoints.joined(separator: "; "))
        \(context.pendingQuestion.map { "A question was asked: \($0)" } ?? "")

        Transcript (last 30s):
        \(transcript)
        """

        return [
            ChatMessage(role: .system, content: system),
            ChatMessage(role: .user, content: user)
        ]
    }
}
```

---

## 8. Permission Handling

The app requires three macOS permissions. Each must be requested with clear
explanation and graceful degradation if denied.

| Permission        | API                              | Required for        | If denied                        |
| ----------------- | -------------------------------- | ------------------- | -------------------------------- |
| Microphone        | `AVCaptureDevice.requestAccess`  | Mic capture         | App cannot function — show error |
| Screen Recording  | `CGPreflightScreenCaptureAccess` | System audio        | Mic-only mode, warn user         |
| Accessibility     | `AXIsProcessTrusted`             | Global hotkeys      | Hotkeys disabled, menu bar only  |

**Onboarding flow:**

1. Welcome screen explaining what the app does.
2. Request Microphone — required, block if denied.
3. Request Screen Recording — optional, explain benefit.
4. Request Accessibility — optional, explain hotkeys.
5. API key entry (OpenAI) — or skip for local-only mode.
6. Ready screen.

---

## 9. Meeting Detection

`MeetingDetector` identifies when a meeting is active so the pipeline starts/
stops automatically.

**Strategy: Monitor running applications.**

```swift
final class MeetingDetector {
    static let knownMeetingApps: [MeetingApp] = [
        MeetingApp(name: "Zoom", bundleID: "us.zoom.xos"),
        MeetingApp(name: "Google Meet", bundleID: "com.google.Chrome",
                   windowTitle: "Meet"),
        MeetingApp(name: "Microsoft Teams", bundleID: "com.microsoft.teams2"),
        MeetingApp(name: "Slack Huddle", bundleID: "com.tinyspeck.slackmacgap"),
        MeetingApp(name: "FaceTime", bundleID: "com.apple.FaceTime"),
        MeetingApp(name: "Discord", bundleID: "com.hnc.Discord"),
    ]

    func detectActiveMeeting() -> MeetingApp? {
        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications
        for app in knownMeetingApps {
            if running.contains(where: { $0.bundleIdentifier == app.bundleID }) {
                // Additional check: is the app's audio session active?
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

## 10. Configuration & Settings

All user-facing settings stored via `@AppStorage` with API keys in Keychain.

```swift
struct AppSettings {
    // Stored in UserDefaults via @AppStorage
    @AppStorage("userRole") var userRole: String = "Software Engineer"
    @AppStorage("transcriptionEngine") var engine: TranscriptionEngine = .whisperLocal
    @AppStorage("llmModel") var llmModel: String = "gpt-4o-mini"
    @AppStorage("audioChunkDuration") var chunkDuration: Double = 3.0
    @AppStorage("transcriptWindow") var transcriptWindow: Double = 30.0
    @AppStorage("llmCallInterval") var llmCallInterval: Double = 8.0
    @AppStorage("meetingDetectionMode") var detectionMode: DetectionMode = .auto
    @AppStorage("privacyMode") var privacyMode: Bool = false   // local-only
}

enum TranscriptionEngine: String, CaseIterable {
    case whisperLocal     // Whisper.cpp on-device
    case appleSpeech      // SFSpeechRecognizer
    case whisperAPI       // OpenAI Whisper API
}

enum DetectionMode: String, CaseIterable {
    case auto             // detect meeting apps
    case manual           // user toggle
    case alwaysOn         // always listening
}
```

---

## 11. Keyboard Shortcuts

| Shortcut   | Action                                |
| ---------- | ------------------------------------- |
| Cmd+Shift+M | Toggle expand/collapse               |
| Cmd+Shift+H | Hide completely                      |
| Cmd+Shift+S | Force generate suggestion now         |
| Cmd+Shift+L | Toggle listening on/off              |
| Cmd+Shift+C | Copy last suggestion to clipboard    |

Registered via `NSEvent.addGlobalMonitorForEvents` (requires Accessibility
permission) with `NSEvent.addLocalMonitorForEvents` as fallback.

---

## 12. Error Handling Strategy

### 12.1 Retry Policy

| Error type           | Retry | Max attempts | Backoff        |
| -------------------- | ----- | ------------ | -------------- |
| Network timeout      | Yes   | 3            | Exponential 1s |
| LLM rate limit       | Yes   | 1            | Wait header    |
| LLM 500 error        | Yes   | 2            | Fixed 2s       |
| Transcription fail   | Yes   | 1            | Switch engine  |
| Permission denied    | No    | —            | Show settings  |
| Audio device lost    | No    | —            | Pause pipeline |

### 12.2 Fallback Chain

```
Transcription: Whisper.cpp → SFSpeechRecognizer → Whisper API
LLM:           GPT-4o-mini → Local LLM (llama.cpp) → Cached response
Audio:         Mic + System → Mic only → Pause + notify
```

### 12.3 UI Error States

- **Transient errors** (network blip): yellow status dot, auto-retry silently.
- **Degraded mode** (system audio denied): orange dot + banner explaining
  limitation.
- **Fatal errors** (mic denied): red dot + overlay with "Open System Settings"
  button.

---

## 13. Privacy & Security

| Feature                        | Implementation                            |
| ------------------------------ | ----------------------------------------- |
| No transcript persistence      | Transcript buffer is in-memory only       |
| Screen-share invisible         | `panel.sharingType = .none`               |
| API keys in Keychain           | `KeychainManager` wraps Security framework |
| Local-only mode                | Whisper.cpp + llama.cpp, zero network     |
| Meeting-only listening         | Auto-start/stop via MeetingDetector       |
| Configurable data retention    | Clear context on meeting end              |

---

## 14. Testing Strategy

### 14.1 Unit Tests

| Component            | What to test                                      |
| -------------------- | ------------------------------------------------- |
| ContextEngine        | Transcript window pruning, question detection     |
| PromptBuilder        | Prompt formatting, edge cases (empty transcript)  |
| MeetingDetector      | Known app matching, edge cases                    |
| SuggestionGenerator  | Rate limiting, JSON parsing, error handling        |
| AppSettings          | Default values, persistence                       |

### 14.2 Integration Tests

| Test                      | Description                                       |
| ------------------------- | ------------------------------------------------- |
| Audio → Transcript        | Feed a WAV file, verify transcription output      |
| Transcript → Context      | Feed transcript chunks, verify context state      |
| Context → Suggestion      | Feed context, verify LLM call + parsed result     |
| Full pipeline             | End-to-end with mock audio input                  |

### 14.3 Manual QA Checklist

- [ ] Notch overlay positions correctly on all MacBook models (14", 16", Air)
- [ ] Overlay invisible during screen share (test with Zoom, Meet)
- [ ] Expand/collapse animation smooth at 60fps
- [ ] Hotkeys work globally when Accessibility granted
- [ ] Pipeline starts automatically when Zoom launches
- [ ] Pipeline stops cleanly when meeting ends
- [ ] App handles sleep/wake without crashing
- [ ] Memory stays under 200MB during 1-hour meeting
- [ ] CPU stays under 15% average during listening

---

## 15. Build Phases & Timeline

### Phase 1: Foundation + Notch UI (Days 1–3)

**Goal:** Visible, correctly positioned notch overlay with expand/collapse.

| Task                                       | Est.  |
| ------------------------------------------ | ----- |
| Xcode project setup, signing, entitlements | 2h    |
| `NotchWindowController` — NSPanel setup    | 4h    |
| Notch positioning across screen sizes      | 3h    |
| `NotchOverlayView` — collapsed state       | 2h    |
| `NotchOverlayView` — expanded state        | 4h    |
| `StatusIndicatorView`                      | 1h    |
| `SuggestionCardView`                       | 3h    |
| Expand/collapse animation                  | 3h    |
| `NotchViewModel` with mock data            | 2h    |
| `sharingType = .none` verification         | 1h    |

**Deliverable:** Overlay shows mock suggestions, invisible during screen share.

### Phase 2: Audio Capture (Days 4–5)

**Goal:** Capture mic audio and (optionally) system audio as 16kHz PCM chunks.

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| `PermissionManager` — mic + screen rec      | 3h    |
| `AudioCaptureManager` — AVAudioEngine tap   | 4h    |
| `SystemAudioCapture` — ScreenCaptureKit     | 6h    |
| `AudioMixer` — merge streams                | 3h    |
| Audio format conversion to 16kHz mono       | 2h    |
| `MeetingDetector` — app detection logic     | 3h    |
| `SCContentFilter` for app-specific capture  | 3h    |

**Deliverable:** Audio chunks stream to console log, verified with playback.

### Phase 3: Transcription (Days 6–7)

**Goal:** Convert audio chunks to text with < 1.5s latency locally.

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| Integrate whisper.cpp via SPM/C bridge      | 6h    |
| `WhisperTranscriber` — load model, infer    | 4h    |
| `AppleSpeechTranscriber` — SFSpeech setup   | 3h    |
| `TranscriptionRouter` — engine selection    | 2h    |
| `WhisperAPIClient` — OpenAI fallback        | 2h    |
| Audio → transcript integration test         | 3h    |

**Deliverable:** Live transcript from mic audio displayed in UI.

### Phase 4: Context Engine + AI Suggestions (Days 8–10)

**Goal:** Maintain conversation state and generate relevant suggestions.

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| `ContextEngine` — sliding window, pruning   | 3h    |
| Question detection heuristics               | 3h    |
| Silence/speaker-change detection            | 2h    |
| `OpenAIClient` — streaming chat completions | 4h    |
| `PromptBuilder` — template + formatting     | 2h    |
| `SuggestionGenerator` — rate limit, parse   | 4h    |
| `KeychainManager` — API key storage         | 2h    |
| Context → suggestion integration test       | 3h    |

**Deliverable:** AI suggestions appear in the overlay based on live transcript.

### Phase 5: Pipeline Integration (Days 11–12)

**Goal:** Wire all components into a reliable end-to-end pipeline.

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| `PipelineCoordinator` — full orchestration  | 6h    |
| Error handling + fallback chains            | 4h    |
| Debounced LLM triggering logic              | 3h    |
| Keyboard shortcuts (global + local)         | 3h    |
| Menu bar integration (status item)          | 2h    |
| `SettingsView` — configuration UI           | 4h    |

**Deliverable:** Fully functional pipeline from audio to suggestions.

### Phase 6: Polish + Testing (Days 13–14)

**Goal:** Stability, performance, and edge case handling.

| Task                                        | Est.  |
| ------------------------------------------- | ----- |
| `OnboardingView` — permission walkthrough   | 3h    |
| Memory profiling (Instruments)              | 3h    |
| CPU profiling under sustained use           | 2h    |
| Screen share invisibility QA                | 1h    |
| Multi-display support testing               | 2h    |
| Sleep/wake resilience                       | 2h    |
| Unit tests for all actors                   | 4h    |
| Integration test suite                      | 3h    |
| Bug fixes + edge cases                      | 4h    |

**Deliverable:** Stable MVP ready for daily use.

### Timeline Summary

| Phase | Days   | Deliverable                    |
| ----- | ------ | ------------------------------ |
| 1     | 1–3    | Notch UI overlay               |
| 2     | 4–5    | Audio capture pipeline         |
| 3     | 6–7    | Live transcription             |
| 4     | 8–10   | AI context + suggestions       |
| 5     | 11–12  | End-to-end integration         |
| 6     | 13–14  | Polish, testing, stability     |

**Total: 14 working days (3 weeks)**

---

## 16. Technical Risks & Mitigations

| Risk                                    | Impact | Mitigation                                   |
| --------------------------------------- | ------ | -------------------------------------------- |
| Whisper.cpp model too slow on older Macs | High   | Fallback to SFSpeech; require Apple Silicon  |
| System audio permission UX confusion    | Medium | Clear onboarding; mic-only fallback          |
| LLM suggestions not useful enough       | High   | Iterate prompts; let user rate suggestions   |
| Memory leak during long meetings        | High   | Strict 30s window; Instruments profiling     |
| App blocked by corporate MDM            | Medium | Document; local-only mode avoids network     |
| macOS update breaks ScreenCaptureKit    | Medium | Abstract behind protocol; SFSpeech fallback  |

---

## 17. Future Roadmap (Post-MVP)

| Feature                    | Description                                       |
| -------------------------- | ------------------------------------------------- |
| Speaker diarization        | Identify who is speaking via voice embeddings     |
| Calendar integration       | Pre-load meeting context from calendar invite     |
| Meeting type profiles      | Different prompt strategies per meeting type      |
| Post-meeting summary       | Generate summary + action items when meeting ends |
| Knowledge base             | Feed user's docs/notes for richer suggestions     |
| Negotiation mode           | Tactical suggestions for negotiation scenarios    |
| Multi-language support     | Whisper multilingual model + translated UI        |

---

End of Document
