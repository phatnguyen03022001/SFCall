#if os(macOS)
import AppKit
import Foundation
import SFCallCore
import SwiftUI

public enum PrivateHUDAnalysisState: Equatable, Sendable {
    case idle
    case analyzing
    case ready
    case unavailable(String)
}

public struct PrivateHUDContent: Equatable, Sendable {
    public var clientTranscript: String
    public var clientTranslationVietnamese: String
    public var trapDetected: Bool
    public var riskLevel: NegotiationRiskLevel?
    public var riskReasonVietnamese: String
    public var recommendedMoveVietnamese: String
    public var sayThis: String
    public var vietnameseHint: String
    public var confidencePercent: Int?
    public var analysisState: PrivateHUDAnalysisState

    public init(
        clientTranscript: String = "",
        clientTranslationVietnamese: String = "",
        trapDetected: Bool = false,
        riskLevel: NegotiationRiskLevel? = nil,
        riskReasonVietnamese: String = "",
        recommendedMoveVietnamese: String = "",
        sayThis: String = "",
        vietnameseHint: String = "",
        confidencePercent: Int? = nil,
        analysisState: PrivateHUDAnalysisState = .idle
    ) {
        self.clientTranscript = clientTranscript
        self.clientTranslationVietnamese = clientTranslationVietnamese
        self.trapDetected = trapDetected
        self.riskLevel = riskLevel
        self.riskReasonVietnamese = riskReasonVietnamese
        self.recommendedMoveVietnamese = recommendedMoveVietnamese
        self.sayThis = sayThis
        self.vietnameseHint = vietnameseHint
        self.confidencePercent = confidencePercent
        self.analysisState = analysisState
    }
}

@MainActor
private final class PrivateHUDModel: ObservableObject {
    @Published var content = PrivateHUDContent()
}

private struct PrivateHUDView: View {
    @ObservedObject var model: PrivateHUDModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("CLIENT")
                Text(model.content.clientTranscript.isEmpty ? "Listening…" : model.content.clientTranscript)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Divider()
                sectionLabel("TIẾNG VIỆT")
                Text(translationText)
                    .textSelection(.enabled)

                Divider()
                sectionLabel("RISK")
                Text(riskHeadline)
                    .font(.headline)
                if !model.content.riskReasonVietnamese.isEmpty {
                    Text(model.content.riskReasonVietnamese)
                        .foregroundStyle(.secondary)
                }

                Divider()
                sectionLabel("NÊN LÀM")
                Text(model.content.recommendedMoveVietnamese.isEmpty ? analysisPlaceholder : model.content.recommendedMoveVietnamese)

                Divider()
                sectionLabel("SAY THIS")
                Text(model.content.sayThis.isEmpty ? analysisPlaceholder : model.content.sayThis)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)

                if !model.content.vietnameseHint.isEmpty {
                    Text(model.content.vietnameseHint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(18)
            .frame(width: 560, alignment: .leading)
        }
        .frame(maxHeight: 520)
        .background(.regularMaterial)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold))
    }

    private var translationText: String {
        if !model.content.clientTranslationVietnamese.isEmpty {
            return model.content.clientTranslationVietnamese
        }
        return analysisPlaceholder
    }

    private var riskHeadline: String {
        switch model.content.analysisState {
        case .idle:
            return "Waiting for a final client turn…"
        case .analyzing:
            return "Analyzing…"
        case .unavailable(let message):
            return message
        case .ready:
            let level = model.content.riskLevel?.rawValue.uppercased() ?? "UNKNOWN"
            let confidence = model.content.confidencePercent.map { " · \($0)% confidence" } ?? ""
            let trap = model.content.trapDetected ? " · possible trap" : ""
            return level + confidence + trap
        }
    }

    private var analysisPlaceholder: String {
        switch model.content.analysisState {
        case .idle:
            "Waiting for a final client turn…"
        case .analyzing:
            "Analyzing…"
        case .ready:
            "—"
        case .unavailable(let message):
            message
        }
    }
}

@MainActor
public final class PrivateHUDWindowController {
    private let model = PrivateHUDModel()
    private let panel: NSPanel

    public init() {
        panel = NSPanel(
            contentRect: NSRect(x: 80, y: 80, width: 560, height: 440),
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
