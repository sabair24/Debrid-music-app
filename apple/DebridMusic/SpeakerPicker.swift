import DebridMusicKit
import SwiftUI

/// "Speel af op…" — this device, the TV, or a speaker.
///
/// Everything except "this device" is played BY THE PC: it sends the file straight to the
/// speaker, so the audio never makes a detour through the iPad and stays bit-for-bit what is on
/// disk. It also means the music keeps playing when you put the iPad down.
struct SpeakerPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var devices: [CastDevice] = []
    @State private var loading = true
    @State private var error: String?

    /// What to send. Empty means "whatever is playing here now".
    var trackIds: [String] = []
    var startIndex: Int = 0

    private var queue: [String] {
        trackIds.isEmpty ? model.playback.queue.map(\.id) : trackIds
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        dismiss()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dit apparaat")
                                Text("Speelt hier af").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "ipad.and.iphone")
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Elders in huis") {
                    if loading {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Zoeken naar speakers…").foregroundStyle(.secondary)
                        }
                    } else if devices.isEmpty {
                        Text("Niets gevonden. Staan je speakers aan?")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(devices) { device in
                        Button {
                            Task { await send(to: device) }
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                    if let caveat = device.caveat(for: model.playback.current) {
                                        // Say it plainly rather than let a hi-res track quietly
                                        // sound different from what the badge promised.
                                        Text(caveat).font(.caption).foregroundStyle(.orange)
                                    } else {
                                        Text(device.isShield ? "Bit-perfect via HDMI" : device.model)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            } icon: {
                                Image(systemName: device.icon)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.callout)
                    }
                }
            }
            .navigationTitle("Speel af op")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Klaar") { dismiss() }
                }
                ToolbarItem {
                    Button {
                        Task { await load() }
                    } label: {
                        Label("Opnieuw zoeken", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let endpoint = model.connection.endpoint else {
            error = "Geen verbinding met je pc."
            loading = false
            return
        }
        loading = true
        error = nil
        do {
            devices = try await model.cast.devices(from: endpoint)
        } catch {
            self.error = "Zoeken mislukt — je pc antwoordde niet."
        }
        loading = false
    }

    private func send(to device: CastDevice) async {
        guard let endpoint = model.connection.endpoint else { return }
        let ids = queue
        guard !ids.isEmpty else {
            error = "Kies eerst iets om af te spelen."
            return
        }
        do {
            try await model.cast.play(
                trackIds: ids,
                startingAt: trackIds.isEmpty ? model.playback.index : startIndex,
                on: device,
                endpoint: endpoint
            )
            // Stop here once it plays there — otherwise the same song runs in two rooms.
            model.playback.stop()
            dismiss()
        } catch APIError.malformed(let message) {
            error = message
        } catch {
            // self.error: a bare `catch` binds `error` to the thrown value and shadows the state.
            self.error = "\(device.name) wilde niet starten."
        }
    }
}
