#if os(macOS)
import Foundation
import XCTest
@testable import SFCallHostSupport

final class NativeSmokeTests: XCTestCase {
    func testListArgumentsParseWithoutRuntimeInput() throws {
        let configuration = try NativeSmokeConfiguration.parse([
            "SFCallHost",
            "--native-smoke-list",
            "--native-smoke-output", "/tmp/sfcall-list.json"
        ])

        XCTAssertEqual(configuration?.mode, .list)
        XCTAssertEqual(configuration?.outputURL.path, "/tmp/sfcall-list.json")
    }

    func testRunArgumentsRequirePIDDurationAndOutput() throws {
        let configuration = try NativeSmokeConfiguration.parse([
            "SFCallHost",
            "--native-smoke-pid", "4242",
            "--native-smoke-seconds", "45",
            "--native-smoke-output", "/tmp/sfcall-run.json"
        ])

        XCTAssertEqual(configuration?.mode, .run(pid: 4242, seconds: 45))
        XCTAssertEqual(configuration?.outputURL.path, "/tmp/sfcall-run.json")
    }

    func testOrdinaryLaunchDoesNotEnterSmokeMode() throws {
        XCTAssertNil(try NativeSmokeConfiguration.parse(["SFCallHost"]))
    }

    func testRunRejectsMissingOutput() {
        XCTAssertThrowsError(
            try NativeSmokeConfiguration.parse([
                "SFCallHost",
                "--native-smoke-pid", "42",
                "--native-smoke-seconds", "30"
            ])
        )
    }

    func testReportRoundTripsAsJSON() throws {
        let report = NativeSmokeReport(
            result: "PASS",
            processes: [
                NativeSmokeProcess(
                    pid: 42,
                    title: "Zoom",
                    bundleID: "us.zoom.xos",
                    isRunningOutput: true
                )
            ],
            microphonePermission: "authorized",
            speechPermission: "authorized",
            systemAudioStarted: true,
            runtimeStarted: true,
            clientFinals: ["We need Friday."],
            userFinals: ["Let me confirm scope."],
            clientRequestCount: 1,
            persistedClientTurns: 1,
            persistedUserTurns: 1,
            intelligenceState: "available",
            translatedClientTextVietnamese: "Chúng tôi cần thứ Sáu.",
            riskLevel: "high",
            confidencePercent: 88,
            riskReasonVietnamese: "Yêu cầu cam kết trước khi chốt phạm vi.",
            recommendedMoveVietnamese: "Chốt phạm vi trước.",
            replyEnglish: "Let me confirm the scope first.",
            replyVietnamese: "Để tôi xác nhận phạm vi trước.",
            stopCleanup: true,
            firstFailure: nil
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(NativeSmokeReport.self, from: data)
        XCTAssertEqual(decoded, report)
    }
}
#endif
