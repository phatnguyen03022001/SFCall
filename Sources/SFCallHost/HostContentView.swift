#if os(macOS)
import SFCallHostSupport
import SwiftUI

@MainActor
struct HostContentView: View {
    @ObservedObject var model: HostViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SFCall Negotiation Copilot")
                        .font(.title2.weight(.semibold))
                    Text("Local process audio + microphone → on-device Speech → negotiation guidance")
                        .foregroundStyle(.secondary)
                }

                GroupBox("Runtime") {
                    VStack(spacing: 8) {
                        valueRow("Status", model.status.displayText)
                        valueRow("Apple Intelligence", model.intelligenceState.rawValue)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Permissions") {
                    VStack(alignment: .leading, spacing: 8) {
                        permissionRow("Microphone", model.permissions.microphone)
                        permissionRow("Speech", model.permissions.speech)
                        permissionRow("System Audio", model.permissions.systemAudio)

                        Divider()

                        Button("Grant Mic + Speech") {
                            model.grantRequiredPermissions()
                        }
                        .disabled(model.status.blocksPermissionGrant)

                        Text("System Audio authorization is finalized when the selected process tap starts.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Audio Source") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Process", selection: $model.selectedSourceID) {
                            Text("Select call audio process…").tag(String?.none)
                            ForEach(model.sources) { source in
                                Text(sourceLabel(source)).tag(Optional(source.id))
                            }
                        }
                        .pickerStyle(.menu)

                        HStack {
                            Button("Refresh Audio Processes") {
                                model.refreshAudioSources()
                            }
                            .disabled(model.status.blocksRefresh)

                            Button("Start") {
                                model.start()
                            }
                            .disabled(model.selectedSourceID == nil || model.status.blocksStart)

                            Button("Stop") {
                                model.stop()
                            }
                            .disabled(model.status != .running)
                        }
                    }
                    .padding(.vertical, 4)
                }

                HStack {
                    Text("Client analysis requests")
                    Spacer()
                    Text("\(model.responseRequestCount)")
                        .font(.system(.body, design: .monospaced))
                }

                GroupBox("Privacy / history") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Final CLIENT and USER transcript turns are stored locally. Raw audio is not stored.")
                        Text("When sharing in Zoom/Meet, share a specific app or window. SFCall cannot guarantee HUD exclusion when the entire display is shared.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                    .padding(.vertical, 4)
                }
            }
            .padding(20)
        }
        .onAppear {
            if model.sources.isEmpty {
                model.refreshAudioSources()
            }
        }
    }

    private func sourceLabel(_ source: HostAudioSourceItem) -> String {
        let activity = source.isRunningOutput ? "●" : "○"
        if let bundleID = source.bundleID, !bundleID.isEmpty {
            return "\(activity) \(source.title) — \(bundleID)"
        }
        return "\(activity) \(source.title)"
    }

    @ViewBuilder
    private func permissionRow(_ name: String, _ state: HostPermissionState) -> some View {
        valueRow(name, state.rawValue)
    }

    @ViewBuilder
    private func valueRow(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

private extension HostRuntimeStatus {
    var displayText: String {
        switch self {
        case .idle: "idle"
        case .refreshingSources: "refreshing audio processes"
        case .ready: "ready"
        case .requestingPermissions: "requesting permissions"
        case .starting: "starting"
        case .running: "running"
        case .failed(let message): "failed — \(message)"
        }
    }

    var blocksPermissionGrant: Bool {
        switch self {
        case .refreshingSources, .requestingPermissions, .starting, .running: true
        case .idle, .ready, .failed: false
        }
    }

    var blocksRefresh: Bool {
        switch self {
        case .refreshingSources, .requestingPermissions, .starting, .running: true
        case .idle, .ready, .failed: false
        }
    }

    var blocksStart: Bool {
        switch self {
        case .refreshingSources, .requestingPermissions, .starting, .running: true
        case .idle, .ready, .failed: false
        }
    }
}
#endif
