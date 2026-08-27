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
        hud.sayThis = ""
        hud.vietnameseHint = request == nil ? "" : "Đang chuẩn bị câu trả lời…"

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
        hud.sayThis = ""
        hud.vietnameseHint = ""

        return LiveCallPresentationUpdate(hud: hud, responseRequest: request)
    }
}
#endif
