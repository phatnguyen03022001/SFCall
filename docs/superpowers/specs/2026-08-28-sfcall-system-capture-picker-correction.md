# SFCall System Capture Picker Correction

Date: 2026-08-28
Status: Approved design, implementation not started
Repository: `phatnguyen03022001/SFCall`
Target branch: `dev`
Design base: `68f6cd93ac929966fae3ec8472373b70bdec2b1b`

## Purpose

Replace the SFCall smoke host's custom ScreenCaptureKit source-enumeration permission gate with Apple's system content-sharing picker while preserving the existing capture, STT, routing, HUD, signing, and provider boundaries.

This correction exists because the current host can remain permanently blocked at `CGPreflightScreenCaptureAccess() == false` even after all of the following have been independently established on the target Mac:

- the host is signed with a stable Apple Development identity rather than ad-hoc signing;
- the bundle identifier is stable as `com.sfcall.host`;
- the TeamIdentifier and designated requirement are stable across rebuilds;
- System Settings shows SFCall Host enabled for Screen Capture;
- the app has been quit and relaunched;
- the Mac has been fully rebooted;
- one supported post-reboot permission request still returns denied.

The result is an architectural mismatch: the host treats blanket Screen Capture preflight as the authority for whether a user may choose content, although the downstream SFCall capture path only requires an `SCContentFilter` representing content the user explicitly selected.

## Authority and supersession

This document supersedes only the source-selection and Screen Capture permission semantics in:

- `docs/superpowers/specs/2026-08-28-sfcall-runtime-host-design.md`
- `docs/superpowers/specs/2026-08-28-sfcall-runtime-host-stable-signing-correction.md`

The stable-signing requirements remain fully authoritative. The host must continue to use a stable Apple Development signing identity with bundle identifier `com.sfcall.host`; ad-hoc signing remains prohibited for the canonical TCC-dependent smoke path.

All unrelated runtime-host design decisions remain unchanged unless explicitly replaced below.

## Scope

This correction changes only how the smoke host obtains and represents a capture source and how it reports Screen Capture session state.

In scope:

- use Apple's `SCContentSharingPicker` as the canonical source selector;
- allow the user to select one application or one window;
- receive the system-selected `SCContentFilter` through picker observer callbacks;
- wrap that filter in the existing `CallCaptureSource` abstraction;
- retain one currently selected source in the host driver;
- replace custom source enumeration UI with Choose/Change Source UI;
- remove `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()` from the host's source-selection gate;
- keep Microphone and Speech permission requests explicit;
- make Screen Capture status in the smoke host session-scoped rather than a blanket TCC truth claim;
- preserve existing runtime start, capture, STT, routing, HUD, stop, and signing behavior.

Out of scope:

- changes to `SFCallCore`;
- changes to `LiveCallRouter` semantics;
- changes to Apple Speech transcription logic;
- changes to microphone capture;
- changes to screen/system-audio stream configuration except what is strictly necessary to accept a picker-provided filter;
- LLM/provider integration;
- SQLite/case-memory changes;
- HUD redesign;
- signing changes;
- TCC database inspection or mutation;
- `tccutil` automation;
- private macOS APIs;
- broad cleanup or deletion of the existing `ScreenCaptureSourceCatalog` unless a later task explicitly authorizes it.

## Architectural decision

The canonical host source-selection path becomes:

```text
User clicks Choose Source…
        ↓
SCContentSharingPicker
        ↓
User chooses one application or one window
        ↓
SCContentSharingPickerObserver receives SCContentFilter
        ↓
SystemCaptureSourcePicker adapts filter into CallCaptureSource
        ↓
LiveHostRuntimeDriver stores one selected source
        ↓
HostViewModel publishes selected-source presentation state
        ↓
Start
        ↓
LiveCallHUDSession
        ↓
ScreenAudioCapture
        ↓
CLIENT Apple Speech
```

The existing custom `SCShareableContent` catalog is no longer part of the smoke host's canonical path. It may remain in `SFCallMac` for now to avoid unrelated cleanup.

## Component design

### 1. `SystemCaptureSourcePicker`

Add a focused adapter in `SFCallMac` responsible only for integrating `SCContentSharingPicker` with SFCall's source abstraction.

Responsibilities:

- own or coordinate access to the shared system content picker;
- configure the picker to allow only a single application or a single window;
- register and unregister an observer safely;
- present the system picker on request;
- convert a successful picker update into exactly one `CallCaptureSource` carrying the provided `SCContentFilter`;
- derive a stable human-facing label from the selected filter when sufficient metadata is available;
- report picker cancellation separately from picker failure;
- avoid blanket Screen Recording preflight as a prerequisite for showing the picker.

It must not:

- start capture;
- request Microphone or Speech permission;
- call the response provider;
- mutate core case state;
- own HUD state.

### 2. `CallCaptureSource`

The existing `CallCaptureSource` remains the downstream capture contract. It already carries the `SCContentFilter` used by `ScreenAudioCapture`.

The implementation may add a narrow internal/public initializer or factory needed by `SystemCaptureSourcePicker`, but it must not broaden `CallCaptureSource` into an unrelated general-purpose ScreenCaptureKit wrapper.

Source kinds remain application/window. No display-level capture is added by this correction.

### 3. `LiveHostRuntimeDriver`

Replace the host's source-catalog map with one currently selected source.

Current model:

```text
refreshSources()
    → [HostSourceItem]
    → sourceByID[id] = CallCaptureSource
    → start(sourceID: ...)
```

Corrected model:

```text
chooseSource()
    → picker result
    → selected CallCaptureSource?
    → startSelectedSource()
```

The driver must preserve exact object identity for the selected `CallCaptureSource` until it is replaced or the host lifecycle intentionally clears it.

`requestPermissions()` after this correction requests only permissions that the host independently owns and can meaningfully report before capture:

- Microphone;
- Speech recognition.

It must not use `CGPreflightScreenCaptureAccess()` or `CGRequestScreenCaptureAccess()` to decide whether source selection is available.

After a successful picker selection, the driver may report the host's Screen Capture session state as authorized for the selected content. This is a smoke-host presentation state, not a claim that blanket Screen Recording TCC access is globally granted.

System Audio remains `notDetermined` until live capture actually starts. A successful runtime start may transition System Audio to authorized as today.

### 4. `HostRuntimeDriving`

Update the host-driver protocol so it expresses the actual workflow rather than the legacy enumeration model.

The corrected protocol must provide operations equivalent to:

- choose/change source;
- request required non-source permissions;
- start the currently selected source;
- stop.

Callbacks/results must remain MainActor-safe and testable with a fake driver.

Do not expose `SCContentFilter` directly to the SwiftUI view model. ScreenCaptureKit types remain behind the host-driver/source adapter boundary.

### 5. `HostViewModel`

Replace source-array state with one selected-source presentation value.

Required observable behavior:

- before selection: no selected source, Start disabled;
- Choose Source is available independently of `CGPreflightScreenCaptureAccess()`;
- successful selection publishes the source label and session Screen Capture state;
- Change Source invokes the picker again;
- a new successful selection atomically replaces the old selection;
- cancellation before any source exists leaves the host unselected;
- cancellation after a source exists preserves the old source;
- picker failure does not silently erase an existing selected source;
- Start still requires both Microphone and Speech permission;
- successful Start increments no counters by itself and preserves existing response-request semantics;
- Stop preserves existing cleanup behavior.

The view model must not infer global TCC truth from picker success. Its state labels must make the session-scoped meaning clear.

### 6. `HostContentView`

Remove the canonical custom source dropdown and Refresh Sources workflow from the smoke host.

Replace it with a compact flow equivalent to:

```text
Capture Source

Screen Capture (session)    notDetermined

[ Choose Source… ]

Selected source:
None
```

After successful selection:

```text
Capture Source

Screen Capture (session)    authorized

Selected source:
Google Chrome — <window title>

[ Change Source… ]   [ Start ]   [ Stop ]
```

The previous `Open Screen Recording Settings` action is no longer the canonical recovery path for source selection and should be removed from the corrected host UI unless implementation evidence shows it is still independently useful and the design is amended first.

The Permissions section continues to report Microphone and Speech. System Audio may remain visible as runtime state. Screen Capture must be labeled so users do not mistake the picker-selected session authorization for universal/macOS-wide Screen Recording permission.

## Permission semantics

The corrected host distinguishes three different concepts that were previously conflated:

1. **Microphone permission** — app-owned TCC permission requested through AVFoundation.
2. **Speech permission** — app-owned authorization requested through Speech APIs.
3. **Screen content selection** — explicit user choice through the ScreenCaptureKit system picker, yielding an `SCContentFilter` for the selected application/window.

The smoke host must not require blanket Screen Recording preflight before concept 3.

The host must not claim that successful picker selection means every screen/window is capturable. It only means the current session has a user-selected source suitable for the subsequent ScreenCaptureKit operation.

## Picker result semantics

### Successful selection

- produce exactly one selected `CallCaptureSource`;
- replace any previous selected source atomically;
- update the presentation label;
- mark Screen Capture session state as authorized;
- enable Start subject to normal runtime state.

### Cancellation

- not an error;
- if no source was selected previously, remain unselected;
- if a source was already selected, preserve it;
- do not transition host status to failed merely because the user dismissed the picker.

### Picker failure

- surface the exact meaningful error through host status;
- preserve an existing selected source unless ScreenCaptureKit explicitly invalidates it;
- do not reinterpret picker failure as Microphone/Speech denial;
- do not fall back automatically to legacy blanket enumeration.

### Source replacement

- one selected source at a time;
- successful replacement invalidates the old host selection;
- active runtime source changes are not supported by this correction: changing source while running must remain disabled or otherwise fail closed until Stop.

## Runtime invariants preserved

The following existing invariants remain authoritative:

- exactly one active `LiveCallHUDSession`;
- screen/system audio and microphone channels remain separate;
- only final CLIENT/remote turns generate `ResponseRequest` through the existing router;
- final microphone/user turns do not generate remote response requests;
- raw audio is not persisted by this slice;
- HUD behavior remains unchanged;
- Stop must terminate capture/transcription and hide the HUD without crash or hang;
- no provider/LLM is called by the smoke host yet.

## Causal TDD requirements

Implementation must use causal TDD.

Before production mutation, add focused failing tests that prove the old interface cannot satisfy the corrected design. At minimum cover:

1. Start disabled/no start attempt before a source is selected.
2. Successful picker selection publishes one selected source.
3. Successful replacement replaces the prior source.
4. Cancel with no previous source preserves unselected state.
5. Cancel with a previous source preserves that source.
6. Picker failure surfaces failure without deleting an existing source.
7. Microphone/Speech permission flow remains required for Start.
8. Source selection is not gated by Screen Capture preflight state.
9. Screen Capture session presentation becomes authorized only after successful picker selection.
10. Start uses the exact currently selected source and preserves existing response-request callback behavior.

Tests should prefer the HostViewModel/driver protocol boundary. ScreenCaptureKit system UI itself is verified natively rather than mocked as proof of macOS behavior.

RED evidence must be attributable to the missing corrected interface/behavior, not to unrelated compilation breakage.

## Verification requirements

After GREEN implementation, run at least:

```bash
xcrun swift test --filter HostViewModelTests
xcrun swift build --product SFCallHost
xcrun swift build --target SFCallMac
xcrun swift test
bash scripts/verify-host-bundle.sh
```

Require:

- focused tests PASS;
- full test suite PASS;
- host build PASS;
- SFCallMac build PASS;
- no new Sendable/data-race diagnostics;
- no new actor-isolation diagnostics;
- stable non-ad-hoc signing still PASS;
- TeamIdentifier and designated requirement remain valid.

## Native acceptance test

The architecture is not accepted merely because unit tests pass. Native macOS evidence is required on the currently problematic machine.

The key recovery test intentionally starts from the existing condition where the old host reports Screen Capture denied.

Without TCC database changes and without requiring blanket preflight to become authorized:

1. launch the stable-signed `SFCallHost.app`;
2. click Choose Source;
3. require Apple's system content picker to appear;
4. choose one application/window;
5. require SFCall to receive a selected source and enable Start;
6. start runtime;
7. require HUD start and system-audio capture startup;
8. play real English speech in the selected remote source and observe CLIENT STT;
9. speak a different sentence into the physical microphone and observe USER STT separately;
10. verify remote-final ResponseRequest behavior and microphone-final non-generation;
11. Stop cleanly.

If the system picker itself cannot produce a filter on the target Mac, stop and collect the exact ScreenCaptureKit failure. Do not reintroduce blanket preflight as a workaround without a new design decision.

## Publication boundary

Implementation is not authorized by this document alone until:

1. this design spec is reviewed;
2. an implementation plan is written against the reviewed spec;
3. execution follows causal TDD;
4. only the bounded system-picker correction is published to `dev`;
5. `main` remains untouched unless separately authorized.

## Success criteria

This correction is complete only when all of the following are true:

- SFCallHost no longer requires `CGPreflightScreenCaptureAccess() == true` before the user can choose a source;
- the canonical source selector is Apple's system content-sharing picker;
- one application/window selection yields the exact `SCContentFilter` consumed by the existing capture pipeline;
- cancel/replacement/failure semantics are deterministic and covered by tests;
- Microphone and Speech permission handling remains correct;
- stable signing verification remains green;
- native system-picker selection succeeds on the target Mac without TCC database manipulation;
- real remote/system audio and physical microphone speech are both observed through separate STT channels;
- routing and Stop cleanup remain correct;
- no provider/LLM or unrelated framework cleanup is included.