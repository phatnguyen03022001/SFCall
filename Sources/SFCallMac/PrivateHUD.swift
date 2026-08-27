#if os(macOS)
import AppKit
import Foundation
import SwiftUI

public struct PrivateHUDContent: Equatable, Sendable {
    public var clientTranscript: String
    public var sayThis: String
    public var vietnameseHint: String

    public init(clientTranscript: String = "", sayThis: String = "", vietnameseHint: String = "") {
        self.clientTranscript = clientTranscript
        self.sayThis = sayThis
        self.vietnameseHint = vietnameseHint
    }
}

@MainActor
private final class PrivateHUDModel: ObservableObject {
    @Published var content = PrivateHUDContent()
}

private struct PrivateHUDView: View {
    @ObservedObject var model: PrivateHUDModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLIENT")
                .font(.caption.weight(.semibold))
            Text(model.content.clientTranscript.isEmpty ? "Listening…" : model.content.clientTranscript)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Divider()

            Text("SAY THIS")
                .font(.caption.weight(.semibold))
            Text(model.content.sayThis.isEmpty ? "Waiting for a final client turn…" : model.content.sayThis)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)

            if !model.content.vietnameseHint.isEmpty {
                Text(model.content.vietnameseHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 520, alignment: .leading)
        .background(.regularMaterial)
    }
}

@MainActor
public final class PrivateHUDWindowController {
    private let model = PrivateHUDModel()
    private let panel: NSPanel

    public init() {
        panel = NSPanel(
            contentRect: NSRect(x: 80, y: 80, width: 520, height: 280),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "SFCall"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.sharingType = .none
        panel.contentView = NSHostingView(rootView: PrivateHUDView(model: model))
    }

    public var windowNumber: Int { panel.windowNumber }
    public var privacyExclusionRequested: Bool { panel.sharingType == .none }

    public func show() {
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }

    public func update(_ content: PrivateHUDContent) {
        model.content = content
    }
}
#endif
