#if os(macOS)
import SFCallHostSupport
import SFCallMac
import SwiftUI

@MainActor
struct HostContentView: View {
    @ObservedObject var model: HostViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SFCall Smoke Host")
                    .font(.title2.weight(.semibold))
                Text("Local ScreenCaptureKit + Apple Speech runtime verification")
                    .foregroundStyle(.secondary)
            }

            GroupBox("Runtime") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(model.status.displayText)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(.vertical, 4)
            }

            GroupBox("Permissions") {
                VStack(spacing: 8) {
                    permissionRow("Microphone", model.permissions.microphone)
                    permissionRow("Speech", model.permissions.speech)
                    permissionRow("Screen Capture", model.permissions.screenCapture)
                    permissionRow("System Audio", model.permissions.systemAudio)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Capture source") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Source", selection: $model.selectedSourceID) {
                        Text("Select a source…").tag(String?.none)
                        ForEach(model.sources) { source in
                            Text("\(source.kind.rawValue.capitalized) — \(source.title)")
                                .tag(Optional(source.id))
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Button("Refresh Sources") {
                            model.refreshSources()
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
                Text("Remote final ResponseRequests")
                Spacer()
                Text("\(model.responseRequestCount)")
                    .font(.system(.body, design: .monospaced))
            }

            Text("This host does not call an LLM. SAY THIS remains empty until provider work is added separately.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(20)
    }

    @ViewBuilder
    private func permissionRow(_ name: String, _ state: HostPermissionState) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(state.rawValue)
                .font(.system(.body, design: .monospaced))
        }
    }
}

private extension HostRuntimeStatus {
    var displayText: String {
        switch self {
        case .idle:
            "idle"
        case .refreshingSources:
            "refreshing sources"
        case .ready:
            "ready"
        case .requestingPermissions:
            "requesting permissions"
        case .starting:
            "starting"
        case .running:
            "running"
        case .failed(let message):
            "failed — \(message)"
        }
    }

    var blocksRefresh: Bool {
        switch self {
        case .refreshingSources, .requestingPermissions, .starting, .running:
            true
        case .idle, .ready, .failed:
            false
        }
    }

    var blocksStart: Bool {
        switch self {
        case .refreshingSources, .requestingPermissions, .starting, .running:
            true
        case .idle, .ready, .failed:
            false
        }
    }
}
#endif
