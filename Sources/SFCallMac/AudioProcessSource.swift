#if os(macOS)
import AppKit
import CoreAudio
import Foundation

public struct AudioProcessSource: Equatable, Identifiable, Sendable {
    public let id: AudioObjectID
    public let pid: pid_t
    public let title: String
    public let bundleID: String?
    public let isRunningOutput: Bool

    public init(
        id: AudioObjectID,
        pid: pid_t,
        title: String,
        bundleID: String?,
        isRunningOutput: Bool
    ) {
        self.id = id
        self.pid = pid
        self.title = title
        self.bundleID = bundleID
        self.isRunningOutput = isRunningOutput
    }
}

public final class AudioProcessSourceCatalog {
    public init() {}

    public func load() throws -> [AudioProcessSource] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let processes = try AudioHardwareSystem.shared.processes

        return try processes.compactMap { process in
            let pid = try process.pid
            guard pid != ownPID else { return nil }

            let bundleID = try process.bundleID
            let isRunningOutput = try process.isRunningOutput
            let appName = NSRunningApplication(processIdentifier: pid)?.localizedName
            let fallback = bundleID?.split(separator: ".").last.map(String.init)
            let title = appName ?? fallback ?? "Process \(pid)"

            return AudioProcessSource(
                id: process.id,
                pid: pid,
                title: title,
                bundleID: bundleID,
                isRunningOutput: isRunningOutput
            )
        }
        .sorted {
            if $0.isRunningOutput != $1.isRunningOutput {
                return $0.isRunningOutput && !$1.isRunningOutput
            }
            let titleOrder = $0.title.localizedCaseInsensitiveCompare($1.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            return $0.pid < $1.pid
        }
    }
}
#endif
