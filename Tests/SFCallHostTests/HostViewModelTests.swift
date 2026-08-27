#if os(macOS)
import Foundation
import XCTest
import SFCallCore
@testable import SFCallHostSupport

final class HostViewModelTests: XCTestCase {
    @MainActor
    func testRefreshPublishesActiveAudioProcessesFirst() {
        let driver = FakeHostRuntimeDriver()
        driver.sourcesResult = .success([
            HostAudioSourceItem(id: "2", title: "Safari", bundleID: "com.apple.Safari", isRunningOutput: false),
            HostAudioSourceItem(id: "1", title: "Zoom", bundleID: "us.zoom.xos", isRunningOutput: true)
        ])
        let model = HostViewModel(driver: driver)

        model.refreshAudioSources()

        XCTAssertEqual(driver.refreshCount, 1)
        XCTAssertEqual(model.sources.map(\.id), ["1", "2"])
        XCTAssertEqual(model.status, .ready)
    }

    @MainActor
    func testRefreshClearsSelectionWhenProcessDisappears() {
        let driver = FakeHostRuntimeDriver()
        driver.sourcesResult = .success([
            HostAudioSourceItem(id: "1", title: "Zoom", bundleID: nil, isRunningOutput: true)
        ])
        let model = HostViewModel(driver: driver)
        model.refreshAudioSources()
        model.selectedSourceID = "1"

        driver.sourcesResult = .success([])
        model.refreshAudioSources()

        XCTAssertNil(model.selectedSourceID)
    }

    @MainActor
    func testIntelligenceStateComesFromDriver() {
        let driver = FakeHostRuntimeDriver()
        driver.intelligence = .modelNotReady
        let model = HostViewModel(driver: driver)

        XCTAssertEqual(model.intelligenceState, .modelNotReady)
    }

    @MainActor
    func testGrantRequiredPermissionsRequestsMicAndSpeechSnapshot() {
        let driver = FakeHostRuntimeDriver()
        driver.permissionSnapshot = HostPermissionSnapshot(
            microphone: .authorized,
            speech: .authorized,
            systemAudio: .notDetermined
        )
        let model = HostViewModel(driver: driver)

        model.grantRequiredPermissions()

        XCTAssertEqual(driver.permissionRequestCount, 1)
        XCTAssertEqual(model.permissions, driver.permissionSnapshot)
    }

    @MainActor
    func testStartWithoutAudioSelectionDoesNotRequestPermissionsOrRuntime() {
        let driver = FakeHostRuntimeDriver()
        let model = HostViewModel(driver: driver)

        model.start()

        XCTAssertEqual(driver.permissionRequestCount, 0)
        XCTAssertEqual(driver.startCount, 0)
        XCTAssertEqual(model.status, .failed("Select an audio source first."))
    }

    @MainActor
    func testDeniedMicDoesNotStartRuntime() {
        let driver = FakeHostRuntimeDriver()
        driver.permissionSnapshot = HostPermissionSnapshot(
            microphone: .denied,
            speech: .authorized,
            systemAudio: .notDetermined
        )
        let model = HostViewModel(driver: driver)
        model.selectedSourceID = "1"

        model.start()

        XCTAssertEqual(driver.permissionRequestCount, 1)
        XCTAssertEqual(driver.startCount, 0)
        XCTAssertEqual(model.status, .failed("Microphone and Speech permissions are required."))
    }

    @MainActor
    func testSuccessfulStartUsesSelectedAudioProcessAndPublishesSystemAudioAuthorization() {
        let driver = FakeHostRuntimeDriver()
        driver.permissionSnapshot = HostPermissionSnapshot(
            microphone: .authorized,
            speech: .authorized,
            systemAudio: .notDetermined
        )
        let model = HostViewModel(driver: driver)
        model.selectedSourceID = "42"

        model.start()

        XCTAssertEqual(driver.lastStartedSourceID, "42")
        XCTAssertEqual(model.status, .running)
        XCTAssertEqual(model.permissions.systemAudio, .authorized)
    }

    @MainActor
    func testStopStopsExactlyOneActiveRuntime() {
        let driver = FakeHostRuntimeDriver()
        driver.permissionSnapshot = .allAuthorized
        let model = HostViewModel(driver: driver)
        model.selectedSourceID = "1"
        model.start()

        model.stop()
        model.stop()

        XCTAssertEqual(driver.stopCount, 1)
        XCTAssertEqual(model.status, .idle)
    }

    @MainActor
    func testSecondStartWhileRunningDoesNotStartAnotherRuntime() {
        let driver = FakeHostRuntimeDriver()
        driver.permissionSnapshot = .allAuthorized
        let model = HostViewModel(driver: driver)
        model.selectedSourceID = "1"

        model.start()
        model.start()

        XCTAssertEqual(driver.startCount, 1)
    }
}

@MainActor
private final class FakeHostRuntimeDriver: HostRuntimeDriving {
    var sourcesResult: Result<[HostAudioSourceItem], Error> = .success([])
    var permissionSnapshot: HostPermissionSnapshot = .allAuthorized
    var startResult: Result<Void, Error> = .success(())
    var intelligence: HostIntelligenceState = .available

    private(set) var refreshCount = 0
    private(set) var permissionRequestCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastStartedSourceID: String?

    func refreshAudioSources(
        completion: @escaping @MainActor (Result<[HostAudioSourceItem], Error>) -> Void
    ) {
        refreshCount += 1
        completion(sourcesResult)
    }

    func requestPermissions(
        completion: @escaping @MainActor (HostPermissionSnapshot) -> Void
    ) {
        permissionRequestCount += 1
        completion(permissionSnapshot)
    }

    func currentPermissions() -> HostPermissionSnapshot {
        permissionSnapshot
    }

    func intelligenceState() -> HostIntelligenceState {
        intelligence
    }

    func start(
        sourceID: String,
        onResponseRequest: @escaping @MainActor @Sendable (ResponseRequest) -> Void,
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    ) {
        startCount += 1
        lastStartedSourceID = sourceID
        if case .success = startResult {
            permissionSnapshot = HostPermissionSnapshot(
                microphone: permissionSnapshot.microphone,
                speech: permissionSnapshot.speech,
                systemAudio: .authorized
            )
        }
        completion(startResult)
    }

    func stop() { stopCount += 1 }
}

private extension HostPermissionSnapshot {
    static let allAuthorized = HostPermissionSnapshot(
        microphone: .authorized,
        speech: .authorized,
        systemAudio: .authorized
    )
}
#endif
