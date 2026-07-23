import DebridMusicKit
import SwiftUI

/// First run: find the PC, then type the six digits it shows.
struct PairingView: View {
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var selected: DiscoveredServer?
    @State private var manualAddress = ""
    @State private var showManual = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("Koppel met je pc")
                    .font(.title2.weight(.semibold))
                Text("Open DebridMusic op je pc → Instellingen → Apparaat koppelen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            serverPicker

            VStack(spacing: 10) {
                TextField("Zes cijfers", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.title2, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 220)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .onChange(of: code) { _, new in
                        code = String(new.filter(\.isNumber).prefix(6))
                    }

                Button {
                    Task { await pair() }
                } label: {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Koppelen").frame(maxWidth: 160)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.count != 6 || busy || target == nil)
            }

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(message.hasPrefix("Gekoppeld") ? Color.green : Color.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.browser.start() }
        .onDisappear { model.browser.stop() }
    }

    @ViewBuilder
    private var serverPicker: some View {
        VStack(spacing: 8) {
            if model.browser.servers.isEmpty && !showManual {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Zoeken op je netwerk…").foregroundStyle(.secondary)
                }
            }
            ForEach(model.browser.servers) { server in
                Button {
                    selected = server
                } label: {
                    HStack {
                        Image(systemName: "desktopcomputer")
                        VStack(alignment: .leading) {
                            Text(server.name).font(.body.weight(.medium))
                                // verbatim: SwiftUI localises an interpolated Int, so the port
                            // 47820 renders as "47.820" in Dutch — which reads like a typo.
                            Text(verbatim: "\(server.host):\(server.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selected?.id == server.id || (selected == nil && model.browser.servers.count == 1) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: 340)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            if showManual {
                TextField("http://192.168.0.10:47820", text: $manualAddress)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 340)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            } else {
                Button("Adres met de hand invullen") { showManual = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .font(.caption)
            }
        }
    }

    /// Which PC we'd pair with — the typed address wins, then the picked one, then the only one
    /// found (nobody should have to select from a list of one).
    private var target: URL? {
        if showManual, !manualAddress.isEmpty {
            return URL(string: manualAddress.hasPrefix("http") ? manualAddress : "http://\(manualAddress)")
        }
        if let selected { return selected.baseURL }
        return model.browser.servers.count == 1 ? model.browser.servers.first?.baseURL : nil
    }

    private func pair() async {
        guard let url = target else { return }
        busy = true
        message = nil
        do {
            try await model.connection.pair(with: url, code: code, deviceName: ServerIdentity.deviceName)
            message = "Gekoppeld — bibliotheek ophalen…"
            await model.refresh()
        } catch APIError.pairingRefused {
            message = "Code klopt niet of is verlopen. Vraag een nieuwe op je pc."
            code = ""
        } catch {
            message = "Geen verbinding met \(url.host ?? "de pc")."
        }
        busy = false
    }
}
