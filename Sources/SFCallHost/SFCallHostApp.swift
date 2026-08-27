#if os(macOS)
import SFCallHostSupport
import SwiftUI

@main
@MainActor
struct SFCallHostApp: App {
    @StateObject private var model: HostViewModel

    init() {
        let driver = LiveHostRuntimeDriver()
        _model = StateObject(wrappedValue: HostViewModel(driver: driver))
    }

    var body: some Scene {
        WindowGroup("SFCall Smoke Host") {
            HostContentView(model: model)
                .frame(minWidth: 620, minHeight: 420)
        }
        .defaultSize(width: 680, height: 480)
    }
}
#endif
