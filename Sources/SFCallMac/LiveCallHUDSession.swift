#if os(macOS)
import Foundation
import SFCallCore

@MainActor
public protocol LiveCallHUDPresenting: AnyObject {
    func show()
    func hide()
    func update(_ content: PrivateHUDContent)
}

extension PrivateHUDWindowController: LiveCallHUDPresenting {}

@MainActor
public final class LiveCallHUDSession {
    private let hud: any LiveCallHUDPresenting
    private let controller: LiveCallSessionController

    public init(
        baseline: CaseBaseline,
        clientFacts: [ClientFactRecord],
        hud: any LiveCallHUDPresenting,
        onResponseRequest: @escaping (ResponseRequest) -> Void
    ) {
        self.hud = hud

        let eventBridge = LiveCallHUDEventBridge(
            hud: hud,
            onResponseRequest: onResponseRequest
        )
        self.controller = LiveCallSessionController(
            baseline: baseline,
            clientFacts: clientFacts,
            onHUDUpdate: { content in
                eventBridge.publishHUD(content)
            },
            onResponseRequest: { request in
                eventBridge.publishResponse(request)
            }
        )
    }

    public func start(
        runtime: LiveCallSessionRuntime,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let startBridge = LiveCallHUDStartBridge { [weak self] result in
            guard let self else {
                completion(result)
                return
            }

            switch result {
            case .success:
                self.hud.show()
            case .failure:
                self.hud.hide()
            }
            completion(result)
        }

        controller.start(runtime: runtime) { result in
            startBridge.finish(result)
        }
    }

    public func start(
        source: CallCaptureSource,
        localeIdentifier: String = "en-US",
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        start(
            runtime: .native(
                source: source,
                localeIdentifier: localeIdentifier
            ),
            completion: completion
        )
    }

    public func stop() {
        controller.stop()
        hud.hide()
    }
}

private final class LiveCallHUDEventBridge: @unchecked Sendable {
    private let onHUDUpdate: @MainActor (PrivateHUDContent) -> Void
    private let onResponseRequest: @MainActor (ResponseRequest) -> Void

    @MainActor
    init(
        hud: any LiveCallHUDPresenting,
        onResponseRequest: @escaping (ResponseRequest) -> Void
    ) {
        self.onHUDUpdate = { content in
            hud.update(content)
        }
        self.onResponseRequest = onResponseRequest
    }

    func publishHUD(_ content: PrivateHUDContent) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                onHUDUpdate(content)
            }
        } else {
            DispatchQueue.main.async { [self] in
                MainActor.assumeIsolated {
                    onHUDUpdate(content)
                }
            }
        }
    }

    func publishResponse(_ request: ResponseRequest) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                onResponseRequest(request)
            }
        } else {
            DispatchQueue.main.async { [self] in
                MainActor.assumeIsolated {
                    onResponseRequest(request)
                }
            }
        }
    }
}

private final class LiveCallHUDStartBridge: @unchecked Sendable {
    private let handler: @MainActor (Result<Void, Error>) -> Void

    @MainActor
    init(handler: @escaping @MainActor (Result<Void, Error>) -> Void) {
        self.handler = handler
    }

    func finish(_ result: Result<Void, Error>) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                handler(result)
            }
        } else {
            DispatchQueue.main.async { [self] in
                MainActor.assumeIsolated {
                    handler(result)
                }
            }
        }
    }
}
#endif
