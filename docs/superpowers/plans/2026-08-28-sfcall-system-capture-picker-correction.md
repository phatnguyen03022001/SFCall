# SFCall System Capture Picker Correction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the smoke host’s blanket Screen Recording preflight/custom source enumeration path with Apple’s system `SCContentSharingPicker`, while preserving the existing `SCContentFilter` → `ScreenAudioCapture` → dual Apple Speech → HUD/runtime behavior.

**Architecture:** `SFCallMac` gains one narrow system-picker adapter that turns a successful picker callback into the existing `CallCaptureSource`. `SFCallHostSupport` changes from an array/source-ID protocol to one selected-source protocol, and `LiveHostRuntimeDriver` owns exactly one selected `CallCaptureSource`; the SwiftUI host becomes Choose/Change Source instead of Refresh/Picker. Microphone and Speech remain explicit permission requests; Screen Capture becomes session-scoped presentation state after picker selection rather than a blanket `CGPreflightScreenCaptureAccess()` gate.

**Tech Stack:** Swift tools 6.2, Swift 6 strict concurrency, macOS 14+, SwiftPM, XCTest, SwiftUI, AVFoundation, Speech, ScreenCaptureKit, `SCContentSharingPicker`, `SCContentFilter`, stable Apple Development code signing.

**Spec:** `docs/superpowers/specs/2026-08-28-sfcall-system-capture-picker-correction.md`

## Global Constraints

- Target branch is `dev`; keep `main` unchanged.
- Preserve stable signing: bundle id exactly `com.sfcall.host`; ad-hoc signing remains prohibited.
- Do not use `CGPreflightScreenCaptureAccess()` or `CGRequestScreenCaptureAccess()` as a source-selection prerequisite.
- Do not use `tccutil`, inspect/modify TCC databases, or use private macOS APIs.
- Use only `SCContentSharingPicker.shared`; do not instantiate a replacement picker.
- Allowed source modes are exactly `.singleApplication` and `.singleWindow`; no display capture.
- Keep `ScreenCaptureSourceCatalog` in the repository but remove it from the canonical smoke-host path; no unrelated cleanup.
- Preserve the exact picker-provided `SCContentFilter` inside the selected `CallCaptureSource` until replacement or process-lifecycle cleanup.
- Preserve one active runtime maximum, `en-US` Speech locale, separate remote/microphone channels, existing `ResponseRequest` routing, HUD behavior, and Stop cleanup.
- No provider/LLM, SQLite/case-memory, transcript persistence, raw-audio persistence, HUD redesign, or unrelated framework changes.
- No new Swift 6 Sendable/data-race/actor-isolation diagnostics.
- Causal RED must be observed before production implementation, and the RED must fail because the corrected host interface/behavior does not exist yet.
- Native acceptance is mandatory; automated GREEN alone does not close this correction.

---

## File Map

- Create `Sources/SFCallMac/SystemCaptureSourcePicker.swift`: shared system picker integration and callback-to-source adaptation.
- Modify `Sources/SFCallMac/ScreenCaptureSources.swift`: narrow picker-filter factory for `CallCaptureSource`; keep legacy catalog intact.
- Modify `Sources/SFCallHostSupport/HostModels.swift`: one-source selection protocol/state contracts.
- Modify `Sources/SFCallHostSupport/HostViewModel.swift`: choose/change/cancel/failure behavior and start gating.
- Modify `Sources/SFCallHostSupport/LiveHostRuntimeDriver.swift`: retain one exact picker source and remove CoreGraphics preflight/request path.
- Modify `Sources/SFCallHost/HostContentView.swift`: Choose/Change Source UI.
- Modify `Tests/SFCallHostTests/HostViewModelTests.swift`: causal RED and final behavioral coverage.
- Leave `Package.swift`, `ScreenAudioCapture.swift`, `LiveCallHUDSession.swift`, signing scripts, `SFCallCore`, and the legacy `ScreenCaptureSourceCatalog` structurally unchanged unless compilation proves a strictly necessary import/access-level adjustment.

---

### Task 1: Establish the causal host-contract RED

**Files:**
- Modify: `Tests/SFCallHostTests/HostViewModelTests.swift`

**Interfaces under test:**
- Future `HostViewModel.selectedSource: HostSourceItem?`
- Future `HostViewModel.chooseSource()`
- Future `HostSourceSelectionResult.selected(HostSourceItem)` / `.cancelled`
- Future driver `start(onResponseRequest:completion:)` that starts its internally retained selected source.

- [ ] **Step 1: Write corrected source-selection tests before touching production files.**

Add these tests:

```swift
@MainActor
func testStartWithoutSelectionDoesNotRequestPermissionsOrRuntime() {
    let driver = FakeHostRuntimeDriver()
    let model = HostViewModel(driver: driver)

    model.start()

    XCTAssertEqual(driver.permissionRequestCount, 0)
    XCTAssertEqual(driver.startCount, 0)
    XCTAssertEqual(model.status, .failed("Select a capture source first."))
}

@MainActor
func testSuccessfulSourceSelectionPublishesSourceAndSessionAuthorization() {
    let driver = FakeHostRuntimeDriver()
    driver.selectionResult = .success(
        .selected(HostSourceItem(id: "picker:window:1", kind: .window, title: "Chrome — Call"))
    )
    let model = HostViewModel(driver: driver)

    model.chooseSource()

    XCTAssertEqual(driver.chooseSourceCount, 1)
    XCTAssertEqual(model.selectedSource?.id, "picker:window:1")
    XCTAssertEqual(model.permissions.screenCapture, .authorized)
    XCTAssertEqual(model.status, .ready)
}

@MainActor
func testSuccessfulReplacementReplacesPreviousSource() {
    let driver = FakeHostRuntimeDriver()
    let model = HostViewModel(driver: driver)

    driver.selectionResult = .success(
        .selected(HostSourceItem(id: "picker:app:1", kind: .application, title: "Zoom"))
    )
    model.chooseSource()
    driver.selectionResult = .success(
        .selected(HostSourceItem(id: "picker:window:2", kind: .window, title: "Chrome — Meeting"))
    )
    model.chooseSource()

    XCTAssertEqual(model.selectedSource?.id, "picker:window:2")
}

@MainActor
func testCancelWithoutPreviousSourceRemainsUnselected() {
    let driver = FakeHostRuntimeDriver()
    driver.selectionResult = .success(.cancelled)
    let model = HostViewModel(driver: driver)

    model.chooseSource()

    XCTAssertNil(model.selectedSource)
    XCTAssertEqual(model.permissions.screenCapture, .notDetermined)
    XCTAssertEqual(model.status, .idle)
}

@MainActor
func testCancelPreservesPreviousSource() {
    let driver = FakeHostRuntimeDriver()
    let model = HostViewModel(driver: driver)

    driver.selectionResult = .success(
        .selected(HostSourceItem(id: "picker:app:1", kind: .application, title: "Zoom"))
    )
    model.chooseSource()
    driver.selectionResult = .success(.cancelled)
    model.chooseSource()

    XCTAssertEqual(model.selectedSource?.id, "picker:app:1")
    XCTAssertEqual(model.permissions.screenCapture, .authorized)
    XCTAssertEqual(model.status, .ready)
}

@MainActor
func testPickerFailurePreservesPreviousSourceAndSurfacesFailure() {
    let driver = FakeHostRuntimeDriver()
    let model = HostViewModel(driver: driver)

    driver.selectionResult = .success(
        .selected(HostSourceItem(id: "picker:app:1", kind: .application, title: "Zoom"))
    )
    model.chooseSource()
    driver.selectionResult = .failure(HostTestError.sourceSelection)
    model.chooseSource()

    XCTAssertEqual(model.selectedSource?.id, "picker:app:1")
    XCTAssertEqual(model.status, .failed("source selection failed"))
}

@MainActor
func testSourceSelectionIsNotGatedByBlanketScreenCaptureState() {
    let driver = FakeHostRuntimeDriver()
    driver.permissionSnapshot = HostPermissionSnapshot(
        microphone: .authorized,
        speech: .authorized,
        screenCapture: .denied,
        systemAudio: .notDetermined
    )
    driver.selectionResult = .success(
        .selected(HostSourceItem(id: "picker:window:1", kind: .window, title: "Chrome — Call"))
    )
    let model = HostViewModel(driver: driver)

    model.chooseSource()

    XCTAssertEqual(driver.chooseSourceCount, 1)
    XCTAssertEqual(model.selectedSource?.id, "picker:window:1")
}

@MainActor
func testStartUsesRetainedReplacementAndResponseCallback() {
    let driver = FakeHostRuntimeDriver()
    driver.permissionSnapshot = HostPermissionSnapshot(
        microphone: .authorized,
        speech: .authorized,
        screenCapture: .authorized,
        systemAudio: .notDetermined
    )
    let model = HostViewModel(driver: driver)

    driver.selectionResult = .success(
        .selected(HostSourceItem(id: "picker:app:1", kind: .application, title: "Zoom"))
    )
    model.chooseSource()
    driver.selectionResult = .success(
        .selected(HostSourceItem(id: "picker:window:2", kind: .window, title: "Chrome — Call"))
    )
    model.chooseSource()

    model.start()
    driver.emitResponseRequest()

    XCTAssertEqual(driver.lastStartedSourceID, "picker:window:2")
    XCTAssertEqual(model.status, .running)
    XCTAssertEqual(model.responseRequestCount, 1)
}
```

Extend `HostTestError` with `case sourceSelection` returning `"source selection failed"`. The fake driver in this RED commit may intentionally reference the future selection API so the test target fails against the old production protocol.

- [ ] **Step 2: Run focused RED.**

```bash
xcrun swift test --filter HostViewModelTests
```

Expected: non-zero exit caused by missing corrected source-selection contracts such as `HostViewModel.chooseSource`, `HostViewModel.selectedSource`, or `HostSourceSelectionResult`. Do not accept an unrelated package/toolchain failure.

- [ ] **Step 3: Commit the test-only RED.**

```bash
git add Tests/SFCallHostTests/HostViewModelTests.swift
git commit -m "test: require system picker host semantics"
```

Do not modify production files before this RED evidence exists.

---

### Task 2: Make the host protocol and view model GREEN

**Files:**
- Modify: `Sources/SFCallHostSupport/HostModels.swift`
- Modify: `Sources/SFCallHostSupport/HostViewModel.swift`
- Modify: `Tests/SFCallHostTests/HostViewModelTests.swift`

**Produces:**

```swift
public enum HostSourceSelectionResult: Equatable, Sendable {
    case selected(HostSourceItem)
    case cancelled
}

@MainActor
public protocol HostRuntimeDriving: AnyObject {
    func chooseSource(
        completion: @escaping @MainActor (Result<HostSourceSelectionResult, Error>) -> Void
    )
    func requestPermissions(
        completion: @escaping @MainActor (HostPermissionSnapshot) -> Void
    )
    func start(
        onResponseRequest: @escaping @MainActor @Sendable (ResponseRequest) -> Void,
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    )
    func stop()
}
```

- [ ] **Step 1: Replace `.refreshingSources` with `.choosingSource` and replace the old protocol enumeration/start-by-ID methods with the exact contract above.**

- [ ] **Step 2: Replace array/ID view-model state with one selected source.**

```swift
@Published public private(set) var selectedSource: HostSourceItem?

public func chooseSource() {
    guard !isBusyOrRunning else { return }
    let priorSource = selectedSource
    status = .choosingSource

    driver.chooseSource { [weak self] result in
        guard let self else { return }
        switch result {
        case .success(.selected(let item)):
            self.selectedSource = item
            self.permissions = HostPermissionSnapshot(
                microphone: self.permissions.microphone,
                speech: self.permissions.speech,
                screenCapture: .authorized,
                systemAudio: self.permissions.systemAudio
            )
            self.status = .ready
        case .success(.cancelled):
            self.selectedSource = priorSource
            self.status = priorSource == nil ? .idle : .ready
        case .failure(let error):
            self.selectedSource = priorSource
            self.status = .failed(Self.message(for: error))
        }
    }
}
```

Delete `sources`, `selectedSourceID`, `refreshSources`, `canEnumerateSources`, `shouldShowScreenCaptureSettings`, and `sourcePermissionMessage`. `grantRequiredPermissions()` returns to `.ready` iff `selectedSource != nil`, otherwise `.idle`. `start()` requires a selected source, requests Microphone/Speech, and invokes the new driver `start(...)` without a source ID. Include `.choosingSource` in `isBusyOrRunning`.

- [ ] **Step 3: Update the fake driver with exact retained-source behavior.**

```swift
var selectionResult: Result<HostSourceSelectionResult, Error> = .success(.cancelled)
private(set) var chooseSourceCount = 0
private(set) var selectedSourceID: String?
private(set) var lastStartedSourceID: String?
private var responseHandler: (@MainActor @Sendable (ResponseRequest) -> Void)?
```

On `.selected(item)`, retain `item.id`; cancellation/failure preserves it. `start(...)` sets `lastStartedSourceID = selectedSourceID` and stores `onResponseRequest`. `emitResponseRequest()` invokes that stored callback with an existing valid test `ResponseRequest` fixture. Preserve current permission/start/stop counters.

- [ ] **Step 4: Run focused GREEN and commit.**

```bash
xcrun swift test --filter HostViewModelTests
git add Sources/SFCallHostSupport/HostModels.swift \
        Sources/SFCallHostSupport/HostViewModel.swift \
        Tests/SFCallHostTests/HostViewModelTests.swift
git commit -m "refactor: model one system-picked source"
```

Require PASS before commit.

---

### Task 3: Add the ScreenCaptureKit system-picker adapter

**Files:**
- Create: `Sources/SFCallMac/SystemCaptureSourcePicker.swift`
- Modify: `Sources/SFCallMac/ScreenCaptureSources.swift`

**Produces:**

```swift
public enum SystemCaptureSourcePickerResult {
    case selected(CallCaptureSource)
    case cancelled
}

public final class SystemCaptureSourcePicker
```

with a MainActor `present(completion:)` entry point.

- [ ] **Step 1: Add the narrow picker-filter factory.**

```swift
public enum CallCaptureSourceError: LocalizedError, Sendable {
    case unsupportedPickerStyle

    public var errorDescription: String? {
        "SFCall supports one application or one window source."
    }
}

extension CallCaptureSource {
    static func fromPickerFilter(_ filter: SCContentFilter) throws -> CallCaptureSource {
        switch filter.style {
        case .application:
            let candidate = filter.includedApplications.first?.applicationName
            let title = (candidate?.isEmpty == false) ? candidate! : "Selected Application"
            return CallCaptureSource(
                id: "picker:application:\(UUID().uuidString)",
                kind: .application,
                title: title,
                filter: filter
            )

        case .window:
            let window = filter.includedWindows.first
            let pieces = [window?.owningApplication?.applicationName, window?.title]
                .compactMap { value -> String? in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
            return CallCaptureSource(
                id: "picker:window:\(UUID().uuidString)",
                kind: .window,
                title: pieces.isEmpty ? "Selected Window" : pieces.joined(separator: " — "),
                filter: filter
            )

        case .display, .none:
            throw CallCaptureSourceError.unsupportedPickerStyle

        @unknown default:
            throw CallCaptureSourceError.unsupportedPickerStyle
        }
    }
}
```

Keep the existing `filter` storage and legacy catalog unchanged.

- [ ] **Step 2: Implement the adapter against the shared system picker.**

Configure before first presentation:

```swift
var configuration = SCContentSharingPickerConfiguration()
configuration.allowedPickerModes = [.singleApplication, .singleWindow]
configuration.allowsChangingSelectedContent = false

let picker = SCContentSharingPicker.shared
picker.defaultConfiguration = configuration
picker.maximumStreamCount = 1
picker.add(observer)
picker.isActive = true
```

Keep the shared picker active and the observer registered for the adapter/host lifetime, matching Apple’s system-picker lifecycle. Do **not** set `isActive = false` after a successful selection or cancellation. Unregister/deactivate only during adapter teardown; if direct `deinit` isolation is awkward under Swift 6, use a dedicated observer bridge whose reference can be removed on the main queue without capturing a deinitializing `self`.

Each `present(...)` stores exactly one pending completion, fails closed with local `pickerAlreadyActive` if another request is pending, and calls:

```swift
SCContentSharingPicker.shared.present()
```

Implement required observer callbacks:

```swift
func contentSharingPicker(
    _ picker: SCContentSharingPicker,
    didUpdateWith filter: SCContentFilter,
    for stream: SCStream?
)

func contentSharingPicker(
    _ picker: SCContentSharingPicker,
    didCancelFor stream: SCStream?
)

func contentSharingPickerStartDidFailWithError(_ error: any Error)
```

`didUpdateWith` converts the exact filter and completes `.selected(source)`; cancel completes `.cancelled`; start failure propagates the exact error. Every terminal callback consumes and clears the one pending completion exactly once but leaves picker activation/observer registration intact for future Change Source operations.

Because `SCContentFilter`/`CallCaptureSource` are not assumed Sendable, follow the repository’s lock + `DispatchQueue.main.async` + `MainActor.assumeIsolated` transfer pattern rather than sending the filter/source through an unconstrained `Task`.

- [ ] **Step 3: Compile and commit.**

```bash
xcrun swift build --target SFCallMac 2>&1 | tee /tmp/sfcall-picker-mac-build.log
```

Require exit 0 and no new Sendable/data-race/actor-isolation diagnostics, then:

```bash
git add Sources/SFCallMac/SystemCaptureSourcePicker.swift \
        Sources/SFCallMac/ScreenCaptureSources.swift
git commit -m "feat: add system capture source picker"
```

---

### Task 4: Wire the real driver and SwiftUI host

**Files:**
- Modify: `Sources/SFCallHostSupport/LiveHostRuntimeDriver.swift`
- Modify: `Sources/SFCallHost/HostContentView.swift`
- Modify: `Tests/SFCallHostTests/HostViewModelTests.swift` only if compilation exposes a contract mismatch already authorized above.

**Consumes:** `SystemCaptureSourcePicker` and one exact selected `CallCaptureSource`.

- [ ] **Step 1: Remove the legacy source gate from the real driver.**

Delete `import CoreGraphics`, `catalog`, `sourceByID`, `refreshSources`, `requestScreenCaptureIfNeeded`, and `SourceCatalogTransfer`.

Add:

```swift
private let sourcePicker: SystemCaptureSourcePicker
private var selectedSource: CallCaptureSource?

public init(sourcePicker: SystemCaptureSourcePicker = SystemCaptureSourcePicker()) {
    self.sourcePicker = sourcePicker
}
```

Implement `chooseSource(...)` so `.selected(source)` atomically stores the exact `CallCaptureSource`, sets `screenCaptureState = .authorized`, and returns `HostSourceItem(id: source.id, kind: source.kind, title: source.title)`. Cancellation/failure preserves any previous selected source.

Change `requestPermissions()` to sequence only `requestMicrophoneIfNeeded` then `requestSpeechIfNeeded`, then return `currentPermissionSnapshot()`.

Change `start` to the new no-ID signature, guard `selectedSource`, and keep existing HUD/session creation. It must call:

```swift
session.start(source: source, localeIdentifier: "en-US") { result in
    // existing success/failure state handling
}
```

Update `sourceUnavailable` text to instruct the user to choose a source rather than refresh sources.

- [ ] **Step 2: Replace the custom source UI.**

Remove `import AppKit` if unused, the custom SwiftUI `Picker`, `Refresh Sources`, the Screen Recording Settings action, `openScreenRecordingSettings()`, and `blocksRefresh`.

Permissions section labels Screen Capture as `Screen Capture (session)` and uses helper copy:

```text
Grant Required Permissions requests Microphone and Speech. Screen content is selected separately through the macOS system picker.
```

Capture source UI:

```swift
HStack {
    Text("Selected source")
    Spacer()
    Text(model.selectedSource?.title ?? "None")
        .font(.system(.body, design: .monospaced))
}

HStack {
    Button(model.selectedSource == nil ? "Choose Source…" : "Change Source…") {
        model.chooseSource()
    }
    .disabled(model.status.blocksSourceChoice)

    Button("Start") {
        model.start()
    }
    .disabled(model.selectedSource == nil || model.status.blocksStart)

    Button("Stop") {
        model.stop()
    }
    .disabled(model.status != .running)
}
```

Add `.choosingSource` display text `"choosing source"`; include it in `blocksPermissionGrant`, `blocksSourceChoice`, and `blocksStart`.

- [ ] **Step 3: Run focused/compile GREEN and commit.**

```bash
xcrun swift test --filter HostViewModelTests
xcrun swift build --product SFCallHost
xcrun swift build --target SFCallMac
```

Require all PASS, then:

```bash
git add Sources/SFCallHostSupport/LiveHostRuntimeDriver.swift \
        Sources/SFCallHost/HostContentView.swift \
        Tests/SFCallHostTests/HostViewModelTests.swift
git commit -m "feat: use system picker in smoke host"
```

---

### Task 5: Full verification and native acceptance

**Files:**
- No source mutation expected.

- [ ] **Step 1: Run complete automated verification.**

```bash
xcrun swift test --filter HostViewModelTests 2>&1 | tee /tmp/sfcall-picker-focused.log
xcrun swift build --product SFCallHost 2>&1 | tee /tmp/sfcall-picker-host-build.log
xcrun swift build --target SFCallMac 2>&1 | tee /tmp/sfcall-picker-mac-build.log
xcrun swift test 2>&1 | tee /tmp/sfcall-picker-full.log
bash scripts/verify-host-bundle.sh 2>&1 | tee /tmp/sfcall-picker-bundle.log
```

Require focused PASS, host build PASS, SFCallMac build PASS, full tests PASS, `HOST_BUNDLE_VERIFY: PASS`, non-ad-hoc signature, nonblank TeamIdentifier, and nonblank designated requirement.

Check concurrency diagnostics:

```bash
grep -Ei 'sendable|actor-isolat|data race|data-race' \
  /tmp/sfcall-picker-focused.log \
  /tmp/sfcall-picker-host-build.log \
  /tmp/sfcall-picker-mac-build.log \
  /tmp/sfcall-picker-full.log || true
```

Any new Swift concurrency diagnostic fails this task.

- [ ] **Step 2: Verify bounded implementation compare.**

From the implementation base containing this plan, implementation changes may touch only:

```text
Sources/SFCallMac/SystemCaptureSourcePicker.swift
Sources/SFCallMac/ScreenCaptureSources.swift
Sources/SFCallHostSupport/HostModels.swift
Sources/SFCallHostSupport/HostViewModel.swift
Sources/SFCallHostSupport/LiveHostRuntimeDriver.swift
Sources/SFCallHost/HostContentView.swift
Tests/SFCallHostTests/HostViewModelTests.swift
```

The RED and GREEN commits may be separate. No unrelated file may enter the implementation compare. `main` remains unchanged.

- [ ] **Step 3: Run the critical native recovery test from the existing problematic TCC state.**

```bash
open .build/SFCallHost.app
```

Do not run `tccutil`, edit TCC, or require `CGPreflightScreenCaptureAccess()` to become true.

In the UI:
1. Confirm Choose Source is enabled even though the legacy host previously reported blanket Screen Capture denied.
2. Click `Choose Source…`; require Apple’s system content picker to appear.
3. Select one application or one window.
4. Require Selected source non-`None`, `Screen Capture (session) == authorized`, and Start enabled.
5. Cancellation must not become a failure and must preserve an existing selection.
6. If the system picker itself fails, stop and record the exact ScreenCaptureKit error; do not add a legacy enumeration fallback.

- [ ] **Step 4: Run real dual-audio/STT acceptance.**

Choose a browser/window playing clear English speech and click Start. Require runtime `running`, HUD visible, system-audio capture startup, observed remote/CLIENT Apple Speech text, and observed physical-microphone/USER Apple Speech text from a different sentence. Verify a remote/client final turn may increment `Remote final ResponseRequests` while a microphone/user final turn does not; microphone text must not replace CLIENT transcript. Stop must hide HUD and terminate capture/transcription without crash or hang.

Do not report PASS for remote audio/STT or microphone STT unless real spoken input was actually observed.

- [ ] **Step 5: Verify final repository state.**

```bash
git status --short
git branch --show-current
git rev-parse HEAD
git ls-remote origin refs/heads/dev refs/heads/main
```

Require branch `dev`, clean worktree, `main` unchanged, and only the bounded correction lineage on `dev`.

## Execution Stop Boundary

Stop after the corrected implementation is verified and published to `dev` with native evidence recorded. Do not promote to `main`, add a response provider, remove legacy catalog code, or perform unrelated cleanup in this plan.
