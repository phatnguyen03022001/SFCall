#if os(macOS)
import AppKit
import SFCallHostSupport
import SwiftUI

@main
@MainActor
struct SFCallHostApp: App {
    @StateObject private var model: HostViewModel
    private let smokeConfiguration: NativeSmokeConfiguration?

    init() {
        let driver = LiveHostRuntimeDriver()
        _model = StateObject(wrappedValue: HostViewModel(driver: driver))
        smokeConfiguration = try? NativeSmokeConfiguration.parse(
            ProcessInfo.processInfo.arguments
        )
    }

    var body: some Scene {
        WindowGroup("SFCall Host") {
            if let smokeConfiguration {
                NativeSmokeLaunchView(configuration: smokeConfiguration)
                    .frame(width: 420, height: 120)
            } else {
                HostContentView(model: model)
                    .frame(minWidth: 620, minHeight: 420)
            }
        }
        .defaultSize(width: 680, height: 480)
    }
}

@MainActor
private struct NativeSmokeLaunchView: View {
    let configuration: NativeSmokeConfiguration
    @State private var started = false

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("SFCall native verification is running…")
                .font(.callout)
        }
        .padding(20)
        .task {
            guard !started else { return }
            started = true

            let report: NativeSmokeReport
            do {
                report = await try NativeSmokeRunner().run(configuration)
            } catch {
                report = NativeSmokeReport(
                    result: "RUNTIME_FAIL",
                    firstFailure: error.localizedDescription
                )
            }

            do {
                try report.write(to: configuration.outputURL)
            } catch {
                let message = "SFCall native smoke could not write report: \(error)\n"
                if let data = message.data(using: .utf8) {
                    try? FileHandle.standardError.write(contentsOf: data)
                }
            }

            NSApplication.shared.terminate(nil)
        }
    }
}
#endif
