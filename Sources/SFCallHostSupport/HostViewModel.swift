#if os(macOS)
import Combine
import Foundation
import SFCallCore

@MainActor
public final class HostViewModel: ObservableObject {
    @Published public private(set) var status: HostRuntimeStatus = .idle
    @Published public private(set) var sources: [HostSourceItem] = []
    @Published public var selectedSourceID: String?
    @Published public private(set) var permissions: HostPermissionSnapshot = .unknown
    @Published public private(set) var responseRequestCount = 0

    private let driver: any HostRuntimeDriving
    private var hasActiveRuntime = false

    public init(driver: any HostRuntimeDriving) {
        self.driver = driver
    }

    public func refreshSources() {
        guard !isBusyOrRunning else { return }
        status = .refreshingSources

        driver.refreshSources { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let items):
                let sorted = items.sorted {
                    if $0.kind.rawValue != $1.kind.rawValue {
                        return $0.kind.rawValue < $1.kind.rawValue
                    }
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                self.sources = sorted
                if let selectedSourceID = self.selectedSourceID,
                   !sorted.contains(where: { $0.id == selectedSourceID }) {
                    self.selectedSourceID = nil
                }
                self.status = .ready

            case .failure(let error):
                self.sources = []
                self.selectedSourceID = nil
                self.status = .failed(Self.message(for: error))
            }
        }
    }

    public func grantRequiredPermissions() {
        guard !isBusyOrRunning else { return }
        let returnStatus: HostRuntimeStatus = sources.isEmpty ? .idle : .ready
        status = .requestingPermissions

        driver.requestPermissions { [weak self] snapshot in
            guard let self else { return }
            self.permissions = snapshot
            self.status = returnStatus
        }
    }

    public func start() {
        guard !isBusyOrRunning else { return }
        guard let selectedSourceID else {
            status = .failed("Select a capture source first.")
            return
        }

        status = .requestingPermissions
        driver.requestPermissions { [weak self] snapshot in
            guard let self else { return }
            self.permissions = snapshot

            guard snapshot.microphone == .authorized,
                  snapshot.speech == .authorized else {
                self.hasActiveRuntime = false
                self.status = .failed("Microphone and Speech permissions are required.")
                return
            }

            self.status = .starting
            self.driver.start(
                sourceID: selectedSourceID,
                onResponseRequest: { [weak self] _ in
                    self?.responseRequestCount += 1
                },
                completion: { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.hasActiveRuntime = true
                        self.status = .running
                    case .failure(let error):
                        self.hasActiveRuntime = false
                        self.status = .failed(Self.message(for: error))
                    }
                }
            )
        }
    }

    public func stop() {
        if hasActiveRuntime {
            driver.stop()
            hasActiveRuntime = false
        }
        status = .idle
    }

    private var isBusyOrRunning: Bool {
        switch status {
        case .refreshingSources, .requestingPermissions, .starting, .running:
            true
        case .idle, .ready, .failed:
            false
        }
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }
}
#endif
