# SFCall Negotiation Copilot MVP Design

Date: 2026-08-28
Status: Approved vision, implementation authorized
Repository: `phatnguyen03022001/SFCall`
Target branch: `dev`
Design base: `26653acece79f4f80a21164de7a3d1bcddd96887`

## Product vision

SFCall is a realtime negotiation copilot for English-language calls. Its job is not to capture or share the user's screen. Its job is to help a Vietnamese-speaking user understand the other party, keep the user's own microphone channel separate, retain conversational context, detect negotiation risk, and present a short actionable reply while the call continues.

The core loop is:

```text
Zoom / Google Meet / browser call
        |
        +-- remote/process audio ----> CLIENT STT ----+
        |                                             |
        +-- physical microphone -----> USER STT ------+----> conversation context
                                                       |     + local history
                                                       |     + case baseline/facts
                                                       v
                                              negotiation advisor
                                                       |
                         +-----------------------------+-----------------------------+
                         |                             |                             |
                  Vietnamese translation        risk / next move             short reply
                                                                               EN + VI
                                                       |
                                                       v
                                                  local HUD
```

The MVP optimizes for one Apple Silicon Mac running current macOS/Xcode. Broad backward compatibility is not an MVP requirement.

## Authority and supersession

This design supersedes the source-selection, remote-audio capture, and Screen Capture permission semantics in:

- `docs/superpowers/specs/2026-08-28-sfcall-runtime-host-design.md`
- `docs/superpowers/specs/2026-08-28-sfcall-system-capture-picker-correction.md`
- their corresponding implementation plans where those plans describe ScreenCaptureKit as the canonical remote-audio path.

The unpushed local system-picker candidate reported at `328d86a05eba3fc5d2459b9cbb58e41f2dada19f` is not canonical authority and must not be published.

The stable Apple Development signing correction remains authoritative. Bundle identifier remains `com.sfcall.host`; ad-hoc signing remains prohibited.

## MVP scope

In scope:

1. Enumerate Core Audio processes that are currently connected to the HAL and identify which are producing output audio.
2. Let the user select one process as the remote-call audio source.
3. Capture only that process's outgoing audio with a Core Audio process tap and a private aggregate device.
4. Keep physical microphone capture separate.
5. Feed both channels to separate Apple on-device Speech recognizers.
6. Route remote transcript as CLIENT and microphone transcript as USER.
7. Persist final transcript turns locally in SQLite; never persist raw audio.
8. On each final CLIENT turn, produce one structured negotiation analysis with:
   - faithful Vietnamese translation of what the client said;
   - risk/trap indication;
   - concise Vietnamese explanation;
   - recommended next move in Vietnamese;
   - 1-3 short English sentences the user can say;
   - Vietnamese meaning of that reply;
   - model confidence from 0-100, clearly presented as model confidence rather than a success guarantee.
9. Use Apple's on-device Foundation Models framework as the MVP negotiation advisor when available.
10. Present transcript and advice in the floating SFCall HUD.
11. Preserve stable local app signing and supported macOS privacy prompts.
12. Explicitly communicate safe-share behavior: sharing a specific app/window is the supported privacy workflow; sharing the entire display is not guaranteed to hide SFCall.

Out of scope:

- pretending to guarantee 95% negotiation success;
- automatic contract acceptance or autonomous commitments;
- price/deadline commitments invented by the model;
- remote cloud LLM providers;
- account/login/sync;
- multi-user or team features;
- automatic Zoom/Meet meeting detection;
- browser-tab-level audio isolation inside one browser process;
- audio persistence;
- call recording files;
- video/screen capture as an input to SFCall;
- OCR or visual reasoning;
- hiding SFCall from arbitrary entire-display capture by another application;
- bypassing TCC, `tccutil`, TCC database access, private APIs, or capture-evasion tricks;
- production-grade analytics, billing, update distribution, or App Store packaging.

## Platform assumptions

- Native macOS app on Apple Silicon.
- Canonical development/test machine is current macOS 26.x with Xcode 26.x / Swift 6.x.
- Core Audio process taps require macOS 14.2 or newer, but this MVP may use APIs available in the current toolchain and is validated on the canonical current machine.
- Foundation Models reasoning requires macOS 26+ and Apple Intelligence availability.
- Apple Speech must remain on-device (`requiresOnDeviceRecognition = true`).
- Vietnamese is an Apple Intelligence-supported language on the canonical OS generation, but runtime availability must still be checked.

## Remote audio architecture

### Process source model

`SFCallMac` owns an `AudioProcessSource` value containing:

- Core Audio process object ID;
- PID;
- human-readable process/app name;
- optional bundle identifier;
- whether output audio is currently running.

`AudioProcessSourceCatalog` enumerates HAL process objects, excludes SFCall's own process, and sorts actively-outputting processes first.

The UI does not call this a screen/window source. It is explicitly an **Audio Source**.

For Zoom, the user selects the Zoom process producing audio. For Google Meet, the user selects the Chrome/Safari process or helper process currently producing the meeting audio. Browser-tab isolation is not promised by this MVP.

### Core Audio tap

`CoreAudioProcessTapCapture` is the canonical remote audio source.

Startup sequence:

```text
selected AudioProcessSource.objectID
        -> CATapDescription(stereoMixdownOfProcesses: [...])
        -> AudioHardwareCreateProcessTap
        -> read tap stream format
        -> private aggregate device containing tap
        -> AudioDeviceCreateIOProcIDWithBlock
        -> AudioDeviceStart
        -> AVAudioPCMBuffer callback
```

The tap is unmuted so the user continues hearing the call normally. The aggregate device is private. Start/stop must destroy IO proc, aggregate device, and process tap deterministically.

The first actual tap start is the authority for the System Audio permission prompt. SFCall does not invent a separate blanket permission preflight.

## Audio/STT channel invariant

Remote and microphone channels remain physically and logically separate:

```text
CoreAudioProcessTapCapture -> remote AppleSpeechTranscriber -> CLIENT
MicrophoneCapture          -> mic AppleSpeechTranscriber    -> USER
```

Remote audio changes from ScreenCaptureKit `CMSampleBuffer` delivery to Core Audio `AVAudioPCMBuffer` delivery. The remote Speech transcriber therefore consumes PCM just like the microphone transcriber.

Only final CLIENT turns generate a `ResponseRequest`. Final USER turns are retained in history/context but never generate a remote response request by themselves.

## Local conversation history

The MVP persists final transcript turns locally using the existing `SQLiteCaseStore` call-session schema.

Retention policy for the canonical host:

```text
audio: never
transcript: persist
persistStructuredMemory: true
```

A lightweight host persistence bootstrap reuses one local default case across launches using identifiers stored in `UserDefaults`. If the stored case no longer exists, it creates a new local client/case and stores the new identifiers.

Only final CLIENT/USER transcript turns are written. Partial speech hypotheses are never persisted.

The current MVP does not need a full history browser. Persistence is considered complete when the current call creates a persistent call session and final turns can be loaded back from SQLite.

## Negotiation intelligence

### Domain contract

`SFCallCore` defines a provider-neutral structured result:

```text
NegotiationAdvice
- translatedClientTextVietnamese
- trapDetected
- riskLevel: low | medium | high
- riskReasonVietnamese
- recommendedMoveVietnamese
- replyEnglish
- replyVietnamese
- confidencePercent: 0...100
```

`NegotiationAdviceProvider` accepts the existing `ResponseRequest` and returns `NegotiationAdvice` asynchronously.

### MVP provider

`AppleNegotiationAdvisor` in `SFCallMac` uses `FoundationModels` when available.

It must check `SystemLanguageModel.default.availability` before inference. If Apple Intelligence is disabled, unsupported, or not ready, capture/STT/history continue working and the HUD reports that negotiation intelligence is unavailable instead of failing the call runtime.

The provider uses guided structured generation rather than parsing free-form text.

Prompt rules:

- Translate the latest CLIENT utterance faithfully into Vietnamese.
- Use only supplied transcript, requirements, and client facts.
- Never invent facts, prices, deadlines, approvals, scope, or commitments.
- Flag pressure, ambiguity, contradiction, premature commitment, scope expansion, unfavorable assumptions, and missing information when supported by context.
- When evidence is weak, recommend clarification rather than confident accusation.
- Reply English must be 1-3 short A2-B1 sentences suitable to say aloud.
- Reply may refuse, buy time, clarify, negotiate, or confirm, but may not create an unverified commitment.
- `confidencePercent` is confidence in the analysis based on available evidence; it is not a probability of winning the negotiation.

The product goal may target high decision quality over time, but the UI and code must never claim a guaranteed 95% accuracy/success rate without an empirical evaluation dataset.

## Advice lifecycle

On every final CLIENT turn:

1. Router emits `ResponseRequest`.
2. HUD immediately shows analysis state `analyzing` while preserving the client transcript.
3. Driver submits the request to `NegotiationAdviceProvider`.
4. On success, session/controller applies the structured advice to the HUD.
5. On provider failure/unavailability, HUD shows a concise advice error while call capture, STT, routing, and persistence continue.

A later CLIENT final may supersede an older in-flight analysis. The implementation must guard against stale advice replacing advice for a newer client turn. MVP solution: generation/request token and apply only the latest token.

Microphone turns do not clear valid client advice.

## HUD content

The HUD remains a floating local panel and presents, at minimum:

```text
CLIENT
<latest English transcript>

TIẾNG VIỆT
<translation>

RISK
<LOW | MEDIUM | HIGH>  <confidence>%
<why>

NÊN LÀM
<next move>

SAY THIS
<1-3 English sentences>
<reply meaning in Vietnamese>
```

The current `NSWindow.sharingType = .none` must not be described as a privacy guarantee. Apple documents that `.none` is legacy and should not be used to hide content from capture.

Supported privacy workflow:

- If the user must share during a call, share the specific target app/window in Zoom/Meet.
- SFCall remains a separate local window and is outside that selected shared window.

Unsupported guarantee:

- If the user shares the entire display, SFCall cannot guarantee that Zoom/Meet or another capturing app will omit the HUD.

The host UI must state this succinctly.

## Host UI MVP

The smoke host becomes a usable MVP shell with these controls/state:

```text
Runtime status
Microphone permission
Speech permission
System Audio status
Apple Intelligence status

Audio Source
[Refresh Audio Processes]
[process dropdown]

[Grant Mic + Speech]
[Start]
[Stop]

History: local transcript / no raw audio
Safe share: share a specific window/app; entire-display privacy is not guaranteed
```

No Screen Recording permission row, no Screen Capture source picker, no Screen Recording settings button.

## Privacy metadata

Canonical Info.plist keys:

- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`
- `NSAudioCaptureUsageDescription`

`NSScreenCaptureUsageDescription` is no longer required by the canonical MVP because SFCall no longer captures screen content.

The bundle verifier must continue to verify bundle ID, non-ad-hoc signature, TeamIdentifier, and designated requirement. Its privacy-key assertions must match the three canonical permissions above.

## Testing strategy

Automated tests must cover:

- negotiation advice domain clamping/semantics;
- CLIENT-only ResponseRequest invariant remains intact;
- microphone turns are surfaced for persistence without generating ResponseRequest;
- presentation advice application and stale-advice guard;
- provider failure does not stop runtime;
- host source refresh/select/start semantics use audio process IDs, not screen sources;
- permission sequence requests only Microphone and Speech before Start;
- history bootstrap uses persistent transcript retention and final-turn-only writes;
- remote runtime routes `AVAudioPCMBuffer` into remote Speech;
- stop cleans all audio components;
- bundle verifier no longer requires Screen Capture privacy metadata.

Native acceptance on the canonical Mac must prove:

1. Process list identifies the process producing call/browser audio.
2. First tap start triggers or respects supported System Audio permission.
3. Selected process audio produces CLIENT STT.
4. Physical microphone produces USER STT separately.
5. Final CLIENT creates one ResponseRequest/advice cycle.
6. Final USER does not create a new remote advice request.
7. Final turns persist and can be loaded from SQLite.
8. Apple Foundation Models advice appears when available.
9. Advice contains Vietnamese translation, risk, next move, EN reply, VI meaning.
10. Stop cleans capture/transcription without crash or hang.

## Success criteria

The MVP pivot is complete only when:

- ScreenCaptureKit is no longer in the canonical host remote-audio path;
- the host selects an audio process rather than a window/screen source;
- Core Audio process tap feeds CLIENT STT;
- microphone remains independent USER STT;
- final transcript history persists locally while raw audio does not;
- a final CLIENT turn produces structured local negotiation advice through Foundation Models when available;
- the HUD renders translation + risk + next move + concise reply;
- unavailable intelligence degrades gracefully without killing the call;
- privacy wording is accurate about specific-window sharing vs entire-display sharing;
- stable signing remains verified;
- full automated tests and native smoke pass on the canonical Mac.
