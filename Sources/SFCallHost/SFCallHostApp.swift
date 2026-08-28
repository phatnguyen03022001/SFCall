#if os(macOS)
import AppKit
import SFCallHostSupport
import SwiftUI

@main
@MainActor
struct SFCallHostApp: App {
    @NSApplicationDelegateAdaptor(SFCallHostAppDelegate.self) private var appDelegate
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
            if smokeConfiguration != nil {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("SFCall native verification is running…")
                        .font(.callout)
                }
                .padding(20)
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
private final class SFCallHostAppDelegate: NSObject, NSApplicationDelegate {
    private var smokeTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let configuration = try? NativeSmokeConfiguration.parse(
            ProcessInfo.processInfo.arguments
        ) else {
            return
        }

        smokeTask = Task { @MainActor in
            let report = await NativeSmokeRunner().run(configuration)

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
