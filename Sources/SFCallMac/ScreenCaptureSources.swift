#if os(macOS)
import Foundation
import ScreenCaptureKit

public enum CallCaptureSourceKind: String, Sendable {
    case application
    case window
}

public final class CallCaptureSource: Identifiable {
    public let id: String
    public let kind: CallCaptureSourceKind
    public let title: String

    fileprivate let filter: SCContentFilter

    fileprivate init(id: String, kind: CallCaptureSourceKind, title: String, filter: SCContentFilter) {
        self.id = id
        self.kind = kind
        self.title = title
        self.filter = filter
    }
}

public enum ScreenCaptureSourceCatalogError: Error {
    case noDisplayAvailable
}

public final class ScreenCaptureSourceCatalog {
    public init() {}

    public func load(completion: @escaping (Result<[CallCaptureSource], Error>) -> Void) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let content, let display = content.displays.first else {
                completion(.failure(ScreenCaptureSourceCatalogError.noDisplayAvailable))
                return
            }

            let applicationSources = content.applications
                .filter { !$0.applicationName.isEmpty }
                .map { application in
                    CallCaptureSource(
                        id: "app:\(application.processID)",
                        kind: .application,
                        title: application.applicationName,
                        filter: SCContentFilter(display: display, including: [application], exceptingWindows: [])
                    )
                }

            let windowSources = content.windows.compactMap { window -> CallCaptureSource? in
                guard let title = window.title, !title.isEmpty else { return nil }
                let appName = window.owningApplication?.applicationName ?? "Window"
                return CallCaptureSource(
                    id: "window:\(window.windowID)",
                    kind: .window,
                    title: "\(appName) — \(title)",
                    filter: SCContentFilter(desktopIndependentWindow: window)
                )
            }

            completion(.success(applicationSources + windowSources))
        }
    }
}
#endif
