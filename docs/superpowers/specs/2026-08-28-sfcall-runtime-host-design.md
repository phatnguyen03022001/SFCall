# SFCall Runtime Smoke Host Design

## Status

Approved direction; implementation pending.

## Purpose

SFCallMac now compiles natively on macOS and its deterministic/runtime wiring is covered by 25 passing tests, but the repository has no runnable macOS process identity. That prevents exercising the remaining native boundaries that require a real app identity and TCC authorization: ScreenCaptureKit, system-audio capture, microphone capture, Speech authorization, source enumeration, and the private HUD.

This design adds the smallest durable macOS host needed to run those smoke tests without turning the smoke harness into the product UI.

## Goals

- Provide a runnable macOS `.app` with a stable bundle identity.
- Allow macOS to present and retain the required privacy/TCC permissions.
- Enumerate existing `CallCaptureSource` application/window choices.
- Start and stop the already-tested `LiveCallHUDSession` against one selected source.
- Make remote/system-audio and microphone STT observable through the existing HUD/session behavior.
- Preserve all current SFCallCore/SFCallMac boundaries and strict Swift 6 concurrency behavior.
- Keep SwiftPM as the source of truth; do not introduce an Xcode project solely for the smoke host.

## Non-goals

- No OpenAI, DeepSeek, GLM, or other remote provider integration.
- No production response generation or `SAY THIS` provider implementation.
- No client/case editor.
- No durable client/case mutation from the host.
- No raw-audio persistence.
- No transcript persistence beyond existing policy.
- No production onboarding, settings, menu-bar UX, updater, signing/notarization, sandbox distribution, or App Store packaging.
- No claim that `NSWindow.sharingType = .none` guarantees invisibility to every third-party capture implementation.

## Architecture

The host is a thin shell over the existing libraries:

```text
SFCallHost.app
  ├─ permission/status UI
  ├─ source picker
  ├─ Start / Stop controls
  └─ smoke-only ephemeral case context
          ↓
     SFCallMac
  ScreenCaptureSourceCatalog
          ↓
  LiveCallHUDSession.start(source:)
          ↓
  ScreenAudioCapture + MicrophoneCapture
          ↓
  AppleSpeechTranscriber(remote + mic)
          ↓
  LiveCallSessionController
          ↓
  PrivateHUDWindowController
          ↓
     SFCallCore
  LiveCallRouter / ResponseRequest
```

`SFCallHost` must not duplicate capture, STT, routing, or HUD logic already owned by `SFCallMac`.

## SwiftPM surface

`Package.swift` gains:

- executable product `SFCallHost`;
- executable target `SFCallHost` depending on `SFCallCore` and `SFCallMac`.

Existing library and test products remain unchanged.

The executable target is the compile-time source for the host, while the smoke-test launcher uses a packaged `.app` so macOS sees a stable application bundle and privacy metadata.

## Host UI

The host uses native macOS UI only and remains intentionally small.

Required controls/state:

- current permission/status summary;
- Refresh Sources action;
- source list containing application/window title and kind;
- selected source;
- Start button;
- Stop button;
- runtime status/error text.

The host window is not the private HUD. `PrivateHUDWindowController` remains a separate floating window managed by `LiveCallHUDSession`.

The host must not auto-start capture on launch. Permission requests and runtime capture should occur only in direct response to the operator initiating the smoke flow.

## Smoke context

The host creates only ephemeral structured context sufficient to construct `LiveCallHUDSession`:

- empty or explicitly smoke-labelled baseline;
- empty client facts;
- response-request observation for diagnostics only.

The host must not create or mutate SQLite case records merely to run the native smoke test.

## Privacy metadata and TCC identity

The packaged host uses a stable bundle identifier:

`com.sfcall.host`

Its `Info.plist` contains clear usage strings for the privacy-sensitive resources exercised by the smoke test:

- `NSMicrophoneUsageDescription`;
- `NSSpeechRecognitionUsageDescription`;
- `NSScreenCaptureUsageDescription`;
- `NSAudioCaptureUsageDescription`.

The bundle also contains the ordinary executable/package identity keys required for a minimal macOS app bundle.

The design intentionally uses a packaged app instead of `swift run` as the canonical smoke-test entrypoint because the smoke test depends on stable TCC identity and app privacy metadata.

## Permission flow

The host exposes permission state and requests only what the smoke flow needs.

Speech:

- inspect `SFSpeechRecognizer.authorizationStatus()`;
- request through the existing Apple Speech authorization API when needed;
- do not start a speech recognizer until authorized.

Microphone:

- inspect current audio capture authorization;
- request microphone access when needed;
- do not start microphone capture when denied/restricted.

Screen/system audio:

- source enumeration/start is the functional permission boundary;
- errors must be surfaced to host status rather than converted into success;
- the host must not modify TCC databases directly.

Permission denial is a valid smoke-test result and must remain recoverable through macOS Settings rather than internal permission bypasses.

## Source enumeration

`ScreenCaptureSourceCatalog` remains the only source-discovery implementation.

The host may present both application and window entries returned by the catalog. It must preserve the existing `CallCaptureSource` value and pass that exact source into `LiveCallHUDSession.start(source:)`.

The host must not rebuild `SCContentFilter` or duplicate ScreenCaptureKit enumeration logic.

## Runtime lifecycle

Start:

1. require one selected source;
2. require/obtain Speech and Microphone authorization as appropriate;
3. construct `PrivateHUDWindowController` once for the active host session;
4. construct `LiveCallHUDSession` with smoke-only case context;
5. call `start(source:localeIdentifier:completion:)` with `en-US` by default;
6. show successful running state only when the existing session startup callback succeeds.

Stop:

1. call `LiveCallHUDSession.stop()`;
2. clear active-session ownership in the host;
3. return UI to idle state while retaining selected source and permission status.

A failed start must not leave the host believing a session is active. Existing `LiveCallSessionController` cleanup remains authoritative for capture/transcriber teardown.

Only one live runtime is allowed per host process.

## ResponseRequest observation

The smoke host may display or log a compact indication that a final remote/client turn generated a `ResponseRequest`.

It must not synthesize a reply, mutate case state, call a remote reasoner, or treat a microphone/user final turn as a response trigger.

This keeps the Task 4 smoke boundary separate from Task 5 provider work.

## App packaging

Add a checked-in host `Info.plist` template and a deterministic local packaging script.

The packaging script must:

1. build the `SFCallHost` SwiftPM product;
2. resolve the actual SwiftPM binary output directory instead of hard-coding architecture-specific paths;
3. create `SFCallHost.app/Contents/MacOS`;
4. copy the executable and `Info.plist` into standard macOS bundle locations;
5. apply local ad-hoc signing with the system `codesign` tool;
6. leave generated `.app` output untracked.

The script must not require a paid Apple Developer certificate for local smoke testing.

Generated app bundles must be ignored by Git.

## Test strategy

All implementation follows causal TDD.

### Deterministic host-state tests

Host coordination/state is separated from framework UI enough to test:

- source refresh success/failure;
- no start without a selected source;
- permission-denied state does not start runtime;
- successful start transitions idle → starting → running;
- failed start transitions starting → failed/idle without retaining an active session;
- stop invokes exactly one active session stop and returns to idle;
- one active runtime maximum.

Tests must not require real TCC permissions.

### Package contract

Verification must prove:

- `SFCallHost` product/target exists;
- host target imports/links `SFCallCore` and `SFCallMac` successfully;
- `xcrun swift build --product SFCallHost` succeeds;
- existing `SFCallMac` build remains green;
- full test suite remains green;
- no new Sendable, actor-isolation, or data-race diagnostics appear.

### Bundle contract

The packaging verification must prove:

- generated path ends in `SFCallHost.app`;
- executable exists at `Contents/MacOS/SFCallHost`;
- `Contents/Info.plist` parses with `plutil`;
- bundle identifier is `com.sfcall.host`;
- all four required privacy usage-description keys are present and nonblank;
- `codesign --verify` succeeds for the locally packaged app.

## Native smoke verification

After compile/unit/bundle verification passes, run the packaged app on the Mac and validate the previously blocked runtime evidence:

- TCC prompts/status for Screen Recording/System Audio, Microphone, and Speech;
- source enumeration;
- HUD appears only after session start succeeds;
- remote/system speech updates CLIENT transcript;
- microphone speech remains a separate user stream and does not overwrite CLIENT text;
- final remote/client speech can emit one `ResponseRequest`;
- final microphone/user speech does not emit a response request;
- `privacyExclusionRequested == true`;
- compatible ScreenCaptureKit self-test records whether HUD exclusion is actually observed;
- Stop tears down runtime and hides HUD without crash/hang.

A missing/denied permission is reported as a native smoke blocker, not bypassed.

## Security and privacy invariants

- Never write raw captured audio to disk.
- Do not add API keys or network providers.
- Do not inspect or modify the TCC database.
- Do not broaden screen capture beyond the operator-selected `CallCaptureSource`.
- Keep `excludesCurrentProcessAudio = true` behavior in the existing remote-audio adapter.
- Keep HUD privacy wording empirical: request/observe exclusion; never promise universal invisibility.
- Do not persist smoke transcripts by default.

## Expected repository changes

Implementation is expected to remain within this bounded set unless causal evidence requires otherwise:

- `Package.swift`;
- `.gitignore` if needed for generated host bundles;
- `Sources/SFCallHost/*`;
- `Tests/SFCallHostTests/*` or equivalent deterministic host tests;
- `Host/Info.plist`;
- `scripts/build-host-app.sh`;
- implementation plan documentation.

No production-provider files are authorized by this design.

## Acceptance criteria

The implementation phase is complete only when:

1. the host product and packaged `.app` build successfully on the target Mac;
2. existing SFCallCore/SFCallMac tests plus new host tests pass;
3. strict concurrency diagnostics remain clean;
4. bundle/privacy metadata verification passes;
5. the packaged app provides a real TCC identity capable of progressing the native smoke test beyond `RUNTIME_HOST_MISSING`;
6. source enumeration and runtime smoke evidence are collected without source mutation;
7. `main` remains untouched until a separate promotion decision.

Passing compile/unit tests alone does not prove native capture/STT permissions; the final native smoke run remains a separate evidence gate.
