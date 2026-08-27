#if os(macOS)
import Foundation
import SFCallCore

public struct LiveCallPresentationUpdate: Equatable, Sendable {
    public let hud: PrivateHUDContent
    public let responseRequest: ResponseRequest?

    public init(hud: PrivateHUDContent, responseRequest: ResponseRequest?) {
        self.hud = hud
        self.responseRequest = responseRequest
    }
}

public final class LiveCallPresentationCoordinator: @unchecked Sendable {
    private let stateLock = NSLock()
    private let router: LiveCallRouter
    private let baseline: CaseBaseline
    private let clientFacts: [ClientFactRecord]
    private var hud = PrivateHUDContent()

    public init(
        baseline: CaseBaseline,
        clientFacts: [ClientFactRecord],
        maxRecentTurns: Int = 6
    ) {
        self.baseline = baseline
        self.clientFacts = clientFacts
        self.router = LiveCallRouter(maxRecentTurns: maxRecentTurns)
    }

    public func ingestRemote(_ transcript: AppleSpeechTranscript) -> LiveCallPresentationUpdate {
        stateLock.lock()
        defer { stateLock.unlock() }

        hud.clientTranscript = transcript.text
        let request = router.ingestRemote(
            text: transcript.text,
            isFinal: transcript.isFinal,
            baseline: baseline,
            clientFacts: clientFacts
        )

        if request != nil {
            clearAdvice()
            hud.analysisState = .analyzing
        }

        return LiveCallPresentationUpdate(hud: hud, responseRequest: request)
    }

    public func ingestMicrophone(_ transcript: AppleSpeechTranscript) -> LiveCallPresentationUpdate {
        stateLock.lock()
        defer { stateLock.unlock() }

        let request = router.ingestMicrophone(
            text: transcript.text,
            isFinal: transcript.isFinal,
            baseline: baseline,
            clientFacts: clientFacts
        )

        return LiveCallPresentationUpdate(hud: hud, responseRequest: request)
    }

    public func applyNegotiationAdvice(_ advice: NegotiationAdvice) -> PrivateHUDContent {
        stateLock.lock()
        defer { stateLock.unlock() }

        hud.clientTranslationVietnamese = advice.translatedClientTextVietnamese
        hud.trapDetected = advice.trapDetected
        hud.riskLevel = advice.riskLevel
        hud.riskReasonVietnamese = advice.riskReasonVietnamese
        hud.recommendedMoveVietnamese = advice.recommendedMoveVietnamese
        hud.sayThis = advice.replyEnglish
        hud.vietnameseHint = advice.replyVietnamese
        hud.confidencePercent = advice.confidencePercent
        hud.analysisState = .ready
        return hud
    }

    public func applyNegotiationFailure(_ message: String) -> PrivateHUDContent {
        stateLock.lock()
        defer { stateLock.unlock() }

        clearAdvice()
        hud.analysisState = .unavailable(message)
        return hud
    }

    private func clearAdvice() {
        hud.clientTranslationVietnamese = ""
        hud.trapDetected = false
        hud.riskLevel = nil
        hud.riskReasonVietnamese = ""
        hud.recommendedMoveVietnamese = ""
        hud.sayThis = ""
        hud.vietnameseHint = ""
        hud.confidencePercent = nil
    }
}
#endif
