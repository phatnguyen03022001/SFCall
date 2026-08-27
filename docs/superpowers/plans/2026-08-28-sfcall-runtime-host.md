# SFCall Runtime Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the smallest runnable macOS `.app` host that gives SFCall a stable TCC identity and drives the already-tested local ScreenCaptureKit → Apple Speech → HUD runtime smoke flow.

**Architecture:** Keep `SFCallCore` and `SFCallMac` unchanged as the runtime/domain owners. Add a testable `SFCallHostSupport` SwiftPM target for deterministic host state, permissions, source metadata, and live adapter coordination; add a tiny `SFCallHost` executable target for the SwiftUI/AppKit shell. Package that executable into `SFCallHost.app` with a checked-in `Info.plist`, stable bundle id, privacy usage strings, and local ad-hoc signing.

**Tech Stack:** Swift 6.2+, macOS 14+, SwiftPM, XCTest, SwiftUI/AppKit, AVFoundation, Speech, ScreenCaptureKit, `plutil`, `codesign`.

**Spec:** `docs/superpowers/specs/2026-08-28-sfcall-runtime-host-design.md`

## Global Constraints

- Keep `main` untouched.
- No OpenAI, DeepSeek, GLM, or other remote providers.
- No raw-audio persistence and no new transcript persistence.
- No SQLite mutation from the smoke host.
- Do not inspect or modify the TCC database.
- Only one live runtime per host process.
- Preserve the exact `CallCaptureSource` returned by `ScreenCaptureSourceCatalog` when starting the session.
- Default Speech locale remains `en-US`.
- Bundle identifier is exactly `com.sfcall.host`.
- `Info.plist` must contain nonblank `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `NSScreenCaptureUsageDescription`, and `NSAudioCaptureUsageDescription`.
- Do not weaken Swift 6 Sendable / actor-isolation checks.
- Generated `.app` output must remain untracked.

---

### Task 1: Package surface and deterministic host-state RED

**Files:**
- Modify: `Package.swift`
- Create: `Tests/SFCallHostTests/HostViewModelTests.swift`

**Interfaces:**
- Produces regular target `SFCallHostSupport` depending on `SFCallCore` and `SFCallMac`.
- Produces executable product/target `SFCallHost` depending on `SFCallHostSupport`, `SFCallCore`, and `SFCallMac`.
- Produces test target `SFCallHostTests` depending on `SFCallHostSupport`.

- [ ] **Step 1: Add package target/product declarations only.**

```swift
products: [
    .library(name: "SFCallCore", targets: ["SFCallCore"]),
    .library(name: "SFCallMac", targets: ["SFCallMac"]),
    .executable(name: "SFCallHost", targets: ["SFCallHost"])
]

// targets additions
.target(name: "SFCallHostSupport", dependencies: ["SFCallCore", "SFCallMac"]),
.executableTarget(name: "SFCallHost", dependencies: ["SFCallHostSupport", "SFCallCore", "SFCallMac"]),
.testTarget(name: "SFCallHostTests", dependencies: ["SFCallHostSupport"])
```

- [ ] **Step 2: Write causal RED tests for the host state model.**

Tests import `@testable import SFCallHostSupport` and require these exact public/internal contracts:

```swift
public struct HostSourceItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: CallCaptureSourceKind
    public let title: String
}

public enum HostRuntimeStatus: Equatable, Sendable {
    case idle
    case refreshingSources
    case ready
    case requestingPermissions
    case starting
    case running
    case failed(String)
}

public enum HostPermissionState: String, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

public struct HostPermissionSnapshot: Equatable, Sendable {
    public let microphone: HostPermissionState
    public let speech: HostPermissionState
    public let screenCapture: HostPermissionState
    public let systemAudio: HostPermissionState
}

@MainActor
public protocol HostRuntimeDriving: AnyObject {
    func refreshSources(completion: @escaping @MainActor (Result<[HostSourceItem], Error>) -> Void)
    func requestPermissions(completion: @escaping @MainActor (HostPermissionSnapshot) -> Void)
    func start(sourceID: String, onResponseRequest: @escaping @MainActor @Sendable (ResponseRequest) -> Void, completion: @escaping @MainActor (Result<Void, Error>) -> Void)
    func stop()
}

@MainActor
public final class HostViewModel: ObservableObject {
    @Published public private(set) var status: HostRuntimeStatus
    @Published public private(set) var sources: [HostSourceItem]
    @Published public var selectedSourceID: String?
    @Published public private(set) var permissions: HostPermissionSnapshot
    @Published public private(set) var responseRequestCount: Int

    public func refreshSources()
    public func start()
    public func stop()
}
```

Required tests:

```swift
func testRefreshSuccessPublishesSourcesAndReadyState()
func testRefreshFailurePublishesFailedState()
func testStartWithoutSelectionDoesNotRequestPermissionsOrRuntime()
func testDeniedPermissionDoesNotStartRuntime()
func testSuccessfulStartTransitionsToRunning()
func testFailedStartDoesNotRetainRunningState()
func testStopStopsExactlyOneActiveRuntimeAndReturnsIdle()
func testSecondStartWhileRunningDoesNotStartAnotherRuntime()
```

- [ ] **Step 3: Run focused RED.**

Run:

```bash
xcrun swift test --filter HostViewModelTests
```

Expected: FAIL because `SFCallHostSupport` production types do not yet exist.

- [ ] **Step 4: Commit only package declarations + RED tests.**

```bash
git add Package.swift Tests/SFCallHostTests/HostViewModelTests.swift
git commit -m "test: define runtime host state behavior"
```

---

### Task 2: Implement host state and live macOS runtime driver

**Files:**
- Create: `Sources/SFCallHostSupport/HostModels.swift`
- Create: `Sources/SFCallHostSupport/HostViewModel.swift`
- Create: `Sources/SFCallHostSupport/LiveHostRuntimeDriver.swift`

**Interfaces:**
- Implements the Task 1 contracts exactly.
- Live driver owns the real `[String: CallCaptureSource]` map so UI/state only crosses Sendable source metadata.
- Live driver uses `ScreenCaptureSourceCatalog`, `PrivateHUDWindowController`, and `LiveCallHUDSession`; it must not duplicate capture/STT routing.

- [ ] **Step 1: Implement value models and the runtime-driving protocol.**

Use exact enum/struct signatures from Task 1. Default permission snapshot is all `.notDetermined` except unsupported states mapped to `.unavailable`.

- [ ] **Step 2: Implement `HostViewModel` as `@MainActor ObservableObject`.**

Behavior:

```text
refreshSources:
idle/failed/ready -> refreshingSources
success -> sources sorted by kind/title, preserve selection if id still exists, status ready
failure -> clear sources and selection, status failed(message)

start:
if status == running/starting/requestingPermissions -> no-op
if selectedSourceID == nil -> status failed("Select a capture source first.")
else -> requestingPermissions -> request permissions
if microphone or speech != authorized -> failed("Microphone and Speech permissions are required.")
else -> starting -> driver.start
success -> running
failure -> failed(error.localizedDescription)

response request callback:
increment responseRequestCount only

stop:
only call driver.stop when an active start succeeded
clear active flag
status idle
```

- [ ] **Step 3: Implement `LiveHostRuntimeDriver`.**

`LiveHostRuntimeDriver` is `@MainActor`. `refreshSources` calls `ScreenCaptureSourceCatalog.load` through a small `@unchecked Sendable` transfer box that stores the non-Sendable `[CallCaptureSource]` behind `NSLock` before hopping to MainActor. On the MainActor, update the private `sourceByID` map and return `[HostSourceItem]`.

`requestPermissions`:

```swift
let mic = AVCaptureDevice.authorizationStatus(for: .audio)
let speech = SFSpeechRecognizer.authorizationStatus()
```

Request microphone with `AVCaptureDevice.requestAccess(for: .audio)` only when `.notDetermined`. Request Speech with `AppleSpeechTranscriber.requestAuthorization` only when `.notDetermined`. Marshal completion back to MainActor. Do not query TCC databases.

`start(sourceID:onResponseRequest:completion:)`:

```text
lookup exact CallCaptureSource by id
construct one PrivateHUDWindowController
construct one LiveCallHUDSession with CaseBaseline(version: 0, requirements: []) and [] client facts
start(source: localeIdentifier: "en-US")
on success retain active session
on failure release session/HUD ownership
```

`stop()` calls the active `LiveCallHUDSession.stop()` exactly once and clears ownership.

- [ ] **Step 4: Run focused GREEN and full regression.**

```bash
xcrun swift test --filter HostViewModelTests
xcrun swift build --target SFCallMac
xcrun swift test
```

Expected: host tests PASS, existing tests remain PASS, no Sendable/actor-isolation diagnostics.

- [ ] **Step 5: Commit.**

```bash
git add Sources/SFCallHostSupport
git commit -m "feat: add runtime host coordination"
```

---

### Task 3: Minimal runnable host shell

**Files:**
- Create: `Sources/SFCallHost/SFCallHostApp.swift`
- Create: `Sources/SFCallHost/HostContentView.swift`

**Interfaces:**
- Consumes `HostViewModel` and `LiveHostRuntimeDriver` from `SFCallHostSupport`.
- Produces the single runnable executable product `SFCallHost`.

- [ ] **Step 1: Add SwiftUI app entrypoint.**

```swift
import SFCallHostSupport
import SwiftUI

@main
struct SFCallHostApp: App {
    @StateObject private var model = HostViewModel(driver: LiveHostRuntimeDriver())

    var body: some Scene {
        WindowGroup("SFCall Smoke Host") {
            HostContentView(model: model)
                .frame(minWidth: 620, minHeight: 420)
        }
    }
}
```

- [ ] **Step 2: Add minimal controls.**

Required UI only:

```text
Status text
Microphone / Speech / Screen Capture / System Audio permission summary
Refresh Sources button
Picker/List of source kind + title
Start button
Stop button
ResponseRequest count
```

On initial appearance, do not auto-start capture and do not auto-request permissions. Source refresh may be explicit only.

- [ ] **Step 3: Build executable product.**

```bash
xcrun swift build --product SFCallHost
```

Expected: PASS with no strict-concurrency diagnostics.

- [ ] **Step 4: Run full tests again and commit.**

```bash
xcrun swift test

git add Sources/SFCallHost
git commit -m "feat: add macOS runtime smoke host"
```

---

### Task 4: App bundle metadata, deterministic packaging, and bundle verification

**Files:**
- Create: `Host/Info.plist`
- Create: `scripts/build-host-app.sh`
- Modify: `.gitignore`

**Interfaces:**
- Produces local untracked `.build/SFCallHost.app`.
- Bundle identifier exactly `com.sfcall.host`.

- [ ] **Step 1: Add minimal app metadata.**

`Host/Info.plist` must contain:

```xml
<key>CFBundleDisplayName</key><string>SFCall Host</string>
<key>CFBundleExecutable</key><string>SFCallHost</string>
<key>CFBundleIdentifier</key><string>com.sfcall.host</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>SFCallHost</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSMicrophoneUsageDescription</key><string>SFCall uses the microphone to transcribe your side of a live call locally.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>SFCall uses speech recognition to transcribe live call audio for the private HUD.</string>
<key>NSScreenCaptureUsageDescription</key><string>SFCall captures only the application or window you select so it can transcribe the remote side of a live call.</string>
<key>NSAudioCaptureUsageDescription</key><string>SFCall captures system audio from the selected call source so it can transcribe the remote speaker.</string>
```

- [ ] **Step 2: Add deterministic packaging script.**

Script behavior:

```bash
#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
xcrun swift build --product SFCallHost
BIN_DIR="$(xcrun swift build --show-bin-path)"
APP="$ROOT/.build/SFCallHost.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/SFCallHost" "$APP/Contents/MacOS/SFCallHost"
cp "$ROOT/Host/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/SFCallHost"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict "$APP"
printf '%s\n' "$APP"
```

- [ ] **Step 3: Ignore generated app output.**

`.gitignore` gains:

```text
.build/SFCallHost.app/
```

- [ ] **Step 4: Run bundle contract verification.**

```bash
APP="$(scripts/build-host-app.sh | tail -1)"
test "$APP" = "$(pwd)/.build/SFCallHost.app"
test -x "$APP/Contents/MacOS/SFCallHost"
/usr/bin/plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist" | grep -Fx com.sfcall.host
for key in NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription NSScreenCaptureUsageDescription NSAudioCaptureUsageDescription; do
  value="$(/usr/bin/plutil -extract "$key" raw "$APP/Contents/Info.plist")"
  test -n "${value//[[:space:]]/}"
done
/usr/bin/codesign --verify --deep --strict "$APP"
```

- [ ] **Step 5: Run final compile/test regression and commit.**

```bash
xcrun swift build --product SFCallHost
xcrun swift build --target SFCallMac
xcrun swift test

git add Host/Info.plist scripts/build-host-app.sh .gitignore
git commit -m "build: package SFCall smoke host app"
```

---

### Task 5: Native smoke evidence gate

**Files:**
- No source mutation authorized in this task.

- [ ] **Step 1: Build/package from a clean verified HEAD.**

```bash
git status --short
scripts/build-host-app.sh
open .build/SFCallHost.app
```

- [ ] **Step 2: Request permissions through the app UI only.**

Validate Microphone, Speech, Screen Recording, and System Audio prompts/status. Do not edit TCC databases.

- [ ] **Step 3: Refresh sources and select one harmless English-speaking source.**

Require source enumeration succeeds and the selected exact source starts.

- [ ] **Step 4: Validate runtime behavior.**

```text
HUD appears only after successful start
remote/system English speech updates CLIENT transcript
microphone English speech does not overwrite CLIENT transcript
remote final may increment ResponseRequest count
microphone final must not increment ResponseRequest count
privacyExclusionRequested == true
Stop hides HUD and tears down capture/transcribers without crash/hang
```

- [ ] **Step 5: Record empirical privacy result separately.**

If compatible ScreenCaptureKit self-test is available, record whether HUD exclusion is observed. Never generalize this to all screen-sharing products.

- [ ] **Step 6: Verify repository remains unchanged by smoke testing.**

```bash
git status --short
```

Expected: clean worktree; generated `.app` ignored.
