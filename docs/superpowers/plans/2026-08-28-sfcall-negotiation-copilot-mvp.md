# SFCall Negotiation Copilot MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pivot SFCall from ScreenCaptureKit source capture to a local-first realtime negotiation copilot that taps one call process's outgoing audio, keeps the microphone separate, persists final turns, and renders structured Vietnamese negotiation guidance.

**Architecture:** `SFCallMac` replaces the canonical remote-audio adapter with a Core Audio process tap delivering PCM into the existing on-device Speech pipeline. `SFCallCore` gains a provider-neutral negotiation result/provider contract; `AppleNegotiationAdvisor` uses Foundation Models when available. The host selects an audio process, persists final turns through the existing SQLite call-session schema, and renders translation/risk/next-move/reply in the local HUD.

**Tech Stack:** Swift 6.x, SwiftPM, macOS 26+, Core Audio/AudioToolbox, AVFoundation, Speech, FoundationModels, SwiftUI/AppKit, SQLite, XCTest, stable Apple Development codesigning.

**Spec:** `docs/superpowers/specs/2026-08-28-sfcall-negotiation-copilot-mvp-design.md`

## Global Constraints

- Target branch `dev`; keep `main` unchanged.
- Do not publish or merge the unpushed local system-picker candidate `328d86a05eba3fc5d2459b9cbb58e41f2dada19f`.
- No ScreenCaptureKit source selection in the canonical host flow.
- No `CGPreflightScreenCaptureAccess`, `CGRequestScreenCaptureAccess`, `tccutil`, TCC DB access, private APIs, or capture-evasion tricks.
- Remote audio comes from one selected Core Audio process; browser-tab isolation is out of scope.
- Raw audio is never persisted.
- Persist only final CLIENT/USER transcript turns.
- Apple Speech remains on-device.
- Only final CLIENT turns trigger negotiation advice; USER turns never independently trigger advice.
- Advice must not invent prices, deadlines, approvals, scope, commitments, or facts.
- Reply English is 1-3 short A2-B1 sentences.
- `confidencePercent` is model-confidence only, never a 95% success guarantee.
- Foundation Models unavailability must degrade gracefully without stopping capture/STT/history.
- Keep stable `com.sfcall.host` Apple Development signing; no ad-hoc fallback.
- Safe-share contract: share a specific app/window; entire-display HUD exclusion is not guaranteed.
- Native macOS RED/GREEN and real audio acceptance are delegated to Luna after GitHub implementation is complete.

---

### Task 1: Negotiation domain and causal RED

**Files:**
- Create: `Tests/SFCallCoreTests/NegotiationAdviceTests.swift`
- Create: `Sources/SFCallCore/Negotiation.swift`

**Produces:**

```swift
public enum NegotiationRiskLevel: String, Codable, Equatable, Sendable {
    case low, medium, high
}

public struct NegotiationAdvice: Equatable, Codable, Sendable {
    public let translatedClientTextVietnamese: String
    public let trapDetected: Bool
    public let riskLevel: NegotiationRiskLevel
    public let riskReasonVietnamese: String
    public let recommendedMoveVietnamese: String
    public let replyEnglish: String
    public let replyVietnamese: String
    public let confidencePercent: Int
}

public protocol NegotiationAdviceProvider: Sendable {
    func advise(for request: ResponseRequest) async throws -> NegotiationAdvice
}
```

- [ ] Commit tests first requiring confidence clamping to `0...100` and exact field preservation. This is the causal RED commit; Luna later checks out this commit and verifies failure due only to missing `NegotiationAdvice` contracts.
- [ ] Implement the minimal domain types. Clamp confidence in the initializer with `min(100, max(0, confidencePercent))`.
- [ ] Do not add negotiation heuristics to `SFCallCore`.

### Task 2: Core Audio process source and PCM remote runtime

**Files:**
- Create: `Sources/SFCallMac/AudioProcessSource.swift`
- Create: `Sources/SFCallMac/CoreAudioProcessTapCapture.swift`
- Modify: `Sources/SFCallMac/LiveCallSessionRuntime.swift`
- Modify: `Sources/SFCallMac/LiveCallSessionController.swift`
- Modify: `Tests/SFCallMacTests/LiveCallSessionWiringTests.swift`

**Produces:**

```swift
public struct AudioProcessSource: Equatable, Identifiable, Sendable {
    public let id: AudioObjectID
    public let pid: pid_t
    public let title: String
    public let bundleID: String?
    public let isRunningOutput: Bool
}

public final class AudioProcessSourceCatalog {
    public func load() throws -> [AudioProcessSource]
}

public final class CoreAudioProcessTapCapture: LiveCallRemoteAudioSource
```

- [ ] Update wiring tests first so fake remote audio delivers `AVAudioPCMBuffer`, and assert remote PCM is appended only to remote Speech while mic PCM is appended only to microphone Speech.
- [ ] Enumerate `try AudioHardwareSystem.shared.processes`, exclude SFCall PID, read `pid`, `bundleID`, `isRunningOutput`, and sort running-output first then title.
- [ ] Implement process tap with `CATapDescription(stereoMixdownOfProcesses:)`, unmuted behavior, one private aggregate device, one IOProc, deterministic stop/destroy.
- [ ] Change `LiveCallRemoteAudioSource` to deliver `AVAudioPCMBuffer` and update controller/runtime accordingly.
- [ ] `LiveCallSessionRuntime.native` accepts `AudioProcessSource`, not `CallCaptureSource`.

### Task 3: Advice presentation and transcript-event boundary

**Files:**
- Modify: `Sources/SFCallMac/PrivateHUD.swift`
- Modify: `Sources/SFCallMac/LiveCallPresentationCoordinator.swift`
- Modify: `Sources/SFCallMac/LiveCallSessionController.swift`
- Modify: `Sources/SFCallMac/LiveCallHUDSession.swift`
- Modify: `Tests/SFCallMacTests/LiveCallPresentationCoordinatorTests.swift`
- Modify: `Tests/SFCallMacTests/LiveCallHUDSessionTests.swift`

**Produces:** HUD state for CLIENT English, Vietnamese translation, risk/confidence, reason, next move, English reply, Vietnamese reply meaning, and analysis status.

- [ ] Tests first: final CLIENT enters analyzing state; applying advice fills fields; mic turn does not clear current advice; provider failure sets unavailable/error state without losing transcript; transcript-event callback receives both channels.
- [ ] Add `applyNegotiationAdvice(_:)` and `applyNegotiationFailure(_:)` through presentation/controller/HUD-session boundaries.
- [ ] Add a transcript callback carrying `(TranscriptSpeaker, text, isFinal)` so host persistence does not inspect HUD text.
- [ ] Keep `panel.sharingType = .none` only as legacy requested behavior if existing tests depend on it; remove any guarantee wording.

### Task 4: Apple Foundation Models advisor

**Files:**
- Create: `Sources/SFCallMac/AppleNegotiationAdvisor.swift`

**Produces:** `AppleNegotiationAdvisor: NegotiationAdviceProvider` and a small availability description used by the host.

- [ ] Use `SystemLanguageModel.default.availability` before generation.
- [ ] Use a fresh `LanguageModelSession(instructions:)` per advice request.
- [ ] Use `@Generable` guided output rather than JSON/free-text parsing.
- [ ] Prompt contains latest client utterance, confirmed requirements, client facts, and bounded recent turns from `ResponseRequest`.
- [ ] Instructions explicitly prohibit invented commitments and require Vietnamese analysis plus 1-3 A2-B1 English reply sentences.
- [ ] Map generated risk enum/result into `NegotiationAdvice`, clamping confidence through the domain initializer.
- [ ] Unavailable model throws a localized advisor error; caller degrades gracefully.

### Task 5: Local transcript persistence bootstrap

**Files:**
- Create: `Sources/SFCallHostSupport/HostCallHistoryStore.swift`
- Create: `Tests/SFCallHostTests/HostCallHistoryStoreTests.swift`

**Produces:** a MainActor host history helper backed by `SQLiteCaseStore`.

- [ ] Test first with temporary SQLite DB + isolated `UserDefaults` suite: first prepare creates local client/case/session, second prepare reuses case, retention is audio-never/transcript-persist/structured-memory true, partial turns are ignored by helper, final turns load back.
- [ ] Default DB path is Application Support/SFCall/sfcall.sqlite3.
- [ ] Store the default case UUID in UserDefaults; validate it through `baseline(for:)`; recreate if stale.
- [ ] Each Start creates a fresh call session with persistent transcript retention.
- [ ] No raw audio file APIs.

### Task 6: Host audio-source flow, advice lifecycle, and persistence wiring

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/SFCallHostSupport/HostModels.swift`
- Modify: `Sources/SFCallHostSupport/HostViewModel.swift`
- Modify: `Sources/SFCallHostSupport/LiveHostRuntimeDriver.swift`
- Modify: `Sources/SFCallHost/HostContentView.swift`
- Modify: `Tests/SFCallHostTests/HostViewModelTests.swift`

**Produces:** process-based host selection and full MVP runtime wiring.

- [ ] Raise package platform to macOS 26 for the canonical MVP/FoundationModels surface.
- [ ] Replace screen `HostSourceItem` with `HostAudioSourceItem(id,title,bundleID,isRunningOutput)`.
- [ ] Permission snapshot contains Microphone, Speech, System Audio only. Add a separate `HostIntelligenceState` from Foundation Models availability.
- [ ] Driver protocol: refresh audio sources, request Mic+Speech, start selected source, stop.
- [ ] ViewModel tests first: refresh/sort, selection invalidation on refresh, no start without selection, mic/speech denial blocks start, screen permission does not exist, one runtime maximum.
- [ ] `LiveHostRuntimeDriver` stores exact `AudioProcessSource` by stable string ID, creates `LiveCallSessionRuntime.native(source:)`, starts persistent session, persists final transcript callback, and sends CLIENT `ResponseRequest` asynchronously to advisor.
- [ ] Use monotonically increasing advice generation token; only latest CLIENT analysis may update HUD.
- [ ] Advisor failure/unavailability updates HUD but never stops call runtime.
- [ ] UI labels `Audio Source`; buttons are Refresh Audio Processes, Start, Stop, Grant Mic + Speech. Show System Audio + Apple Intelligence states. Remove screen/window picker, Screen Capture row, and Screen Recording settings recovery.
- [ ] UI states: local transcript history/no raw audio; safe-share note that specific app/window sharing is recommended and entire-display privacy is not guaranteed.

### Task 7: Bundle metadata and verifier

**Files:**
- Modify: `Host/Info.plist`
- Modify: `scripts/verify-host-bundle.sh`

- [ ] Set minimum system version consistently with the macOS 26 MVP.
- [ ] Canonical privacy keys are exactly Mic, Speech, Audio Capture for required runtime permissions; verifier no longer requires Screen Capture usage text.
- [ ] Preserve bundle id, stable Apple Development signature, TeamIdentifier, designated requirement checks unchanged.

### Task 8: Final review and Luna handoff

- [ ] Review compare from `34f64ef2c9f988dd62dc24841f7d6a4c90c78e67` to final `dev`: no canonical ScreenCaptureKit host path; no TCC/private API; no cloud provider; bounded MVP only.
- [ ] Confirm `main` remains `4cdfdb07f0440bc040db128bd2bb692769288d7a`.
- [ ] Luna verifies causal RED commit, final focused/full tests/build/signing, native process enumeration/tap/system-audio permission, real remote CLIENT STT, real mic USER STT, persistence, Foundation Models advice, routing, and Stop cleanup.
- [ ] Native PASS is required before claiming MVP runtime acceptance.
