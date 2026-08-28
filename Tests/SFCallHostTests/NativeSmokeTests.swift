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
            remotePCMBufferCount: 12,
            remotePCMFrameCount: 12_288,
            microphonePCMBufferCount: 10,
            microphonePCMFrameCount: 10_240,
            remotePCMSampleRate: 48_000,
            remotePCMChannelCount: 2,
            remotePCMCommonFormat: "pcmFormatFloat32",
            remotePCMInterleaved: false,
            remotePCMMaxRMS: 0.42,
            remotePCMNonSilentBufferCount: 11,
            microphonePCMSampleRate: 48_000,
            microphonePCMChannelCount: 1,
            microphonePCMCommonFormat: "pcmFormatFloat32",
            microphonePCMInterleaved: false,
            microphonePCMMaxRMS: 0.31,
            microphonePCMNonSilentBufferCount: 9,
            remoteSpeechTaskState: "running",
            remoteSpeechErrorDomain: "kLSRErrorDomain",
            remoteSpeechErrorCode: 1101,
            remoteSpeechErrorMessage: "Connection to speech process was invalidated.",
            microphoneSpeechTaskState: "running",
            microphoneSpeechErrorDomain: nil,
            microphoneSpeechErrorCode: nil,
            microphoneSpeechErrorMessage: nil,
            clientPartials: ["We need"],
            userPartials: ["Let me"],
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

    func testHostSmokeLaunchIsOwnedByApplicationLifecycle() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceURL = repositoryRoot
            .appendingPathComponent("Sources/SFCallHost/SFCallHostApp.swift")
        let source = try String(contentsOf: appSourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("@NSApplicationDelegateAdaptor"))
        XCTAssertTrue(source.contains("applicationDidFinishLaunching"))
        XCTAssertFalse(source.contains(".task {"))
    }
}
#endif
