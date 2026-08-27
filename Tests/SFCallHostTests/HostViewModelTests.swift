#if os(macOS)
import Foundation
import XCTest
import SFCallCore
import SFCallMac
@testable import SFCallHostSupport

final class HostViewModelTests: XCTestCase {
    @MainActor
    func testRefreshSuccessPublishesSourcesAndReadyState() {
        let driver = FakeHostRuntimeDriver()
        driver.sourcesResult = .success([
            HostSourceItem(id: "app:1", kind: .application, title: "Test Call")
        ])
        let model = HostViewModel(driver: driver)

        model.refreshSources()

        XCTAssertEqual(driver.refreshCount, 1)
        XCTAssertEqual(model.status, .ready)
        XCTAssertEqual(model.sources.map(\.id), ["app:1"])
    }

    @MainActor
    func testRefreshFailurePublishesFailedState() {
        let driver = FakeHostRuntimeDriver()
        driver.sourcesResult = .failure(HostTestError.sourceRefresh)
        let model = HostViewModel(driver: driver)

        model.refreshSources()

        XCTAssertEqual(model.status, .failed("source refresh failed"))
        XCTAssertTrue(model.sources.isEmpty)
        XCTAssertNil(model.selectedSourceID)
    }

    @MainActor
    func testGrantRequiredPermissionsRequestsOnceAndPublishesSnapshot() {
        let driver = FakeHostRuntimeDriver()
        driver.permissionSnapshot = HostPermissionSnapshot(
            microphone: .authorized,
            speech: .authorized,
            screenCapture: .authorized,
            systemAudio: .notDetermined
        )
        let model = HostViewModel(driver: driver)

        model.grantRequiredPermissions()

        XCTAssertEqual(driver.permissionRequestCount, 1)
        XCTAssertEqual(model.permissions, driver.permissionSnapshot)
        XCTAssertEqual(model.status, .idle)
    }

    @MainActor
    func testGrantRequiredPermissionsPreservesReadyStateAfterSourceRefresh() {
        let driver = FakeHostRuntimeDriver()
        driver.sourcesResult = .success([
            HostSourceItem(id: "app:1", kind: .application, title: "Test Call")
        ])
        driver.permissionSnapshot = .allAuthorized
        let model = HostViewModel(driver: driver)
        model.refreshSources()

        model.grantRequiredPermissions()

        XCTAssertEqual(driver.permissionRequestCount, 1)
        XCTAssertEqual(model.permissions, .allAuthorized)
        XCTAssertEqual(model.status, .ready)
    }

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
    func testDeniedPermissionDoesNotStartRuntime() {
        let driver = FakeHostRuntimeDriver()
        driver.permissionSnapshot = HostPermissionSnapshot(
            microphone: .denied,
            speech: .authorized,
            screenCapture: .notDetermined,
            systemAudio: .notDetermined
        )
        let model = HostViewModel(driver: driver)
        model.selectedSourceID = "app:1"

        model.start()

        XCTAssertEqual(driver.permissionRequestCount, 1)
        XCTAssertEqual(driver.startCount, 0)
        XCTAssertEqual(model.status, .failed("Microphone and Speech permissions are required."))
    }

    @MainActor
    func testSuccessfulStartTransitionsToRunning() {
        let driver = FakeHostRuntimeDriver()
        driver.permissionSnapshot = .allAuthorized
        let model = HostViewModel(driver: driver)
        model.selectedSourceID = "app:1"

        model.start()

        XCTAssertEqual(driver.startCount, 1)
        XCTAssertEqual(driver.lastStartedSourceID, "app:1")
        XCTAssertEqual(model.status, .running)
    }

    @MainActor
    func testFailedStartDoesNotRetainRunningState() {
        let driver = FakeHostRuntimeDriver()
        driver.permissionSnapshot = .allAuthorized
        driver.startResult = .failure(HostTestError.runtimeStart)
        let model = HostViewModel(driver: driver)
        model.selectedSourceID = "app:1"

        model.start()

        XCTAssertEqual(driver.startCount, 1)
        XCTAssertEqual(model.status, .failed("runtime start failed"))
    }

    @MainActor
    func testStopStopsExactlyOneActiveRuntimeAndReturnsIdle() {
        let driver = FakeHostRuntimeDriver()
        driver.permissionSnapshot = .allAuthorized
        let model = HostViewModel(driver: driver)
        model.selectedSourceID = "app:1"
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
        model.selectedSourceID = "app:1"

        model.start()
        model.start()

        XCTAssertEqual(driver.startCount, 1)
        XCTAssertEqual(model.status, .running)
    }
}

private enum HostTestError: LocalizedError {
    case sourceRefresh
    case runtimeStart

    var errorDescription: String? {
        switch self {
        case .sourceRefresh:
            "source refresh failed"
        case .runtimeStart:
            "runtime start failed"
        }
    }
}

@MainActor
private final class FakeHostRuntimeDriver: HostRuntimeDriving {
    var sourcesResult: Result<[HostSourceItem], Error> = .success([])
    var permissionSnapshot: HostPermissionSnapshot = .allAuthorized
    var startResult: Result<Void, Error> = .success(())

    private(set) var refreshCount = 0
    private(set) var permissionRequestCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastStartedSourceID: String?

    func refreshSources(
        completion: @escaping @MainActor (Result<[HostSourceItem], Error>) -> Void
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

    func start(
        sourceID: String,
        onResponseRequest: @escaping @MainActor @Sendable (ResponseRequest) -> Void,
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    ) {
        startCount += 1
        lastStartedSourceID = sourceID
        completion(startResult)
    }

    func stop() {
        stopCount += 1
    }
}

private extension HostPermissionSnapshot {
    static let allAuthorized = HostPermissionSnapshot(
        microphone: .authorized,
        speech: .authorized,
        screenCapture: .authorized,
        systemAudio: .authorized
    )
}
#endif
