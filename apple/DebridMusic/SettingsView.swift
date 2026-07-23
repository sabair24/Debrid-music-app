import DebridMusicKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var remoteAddress = ""
    @State private var remoteStatus: String?
    @State private var checking = false
    @State private var confirmForget = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Je pc") {
                    LabeledContent("Naam", value: model.connection.serverName)
                    LabeledContent("Thuis", value: model.connection.settings.homeURL?.absoluteString ?? "—")
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(model.connection.reachable ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text(model.connection.reachable ? "Verbonden" : "Niet bereikbaar")
                        }
                    }
                    LabeledContent("Bibliotheek", value: "\(model.library.tracks.count) nummers")
                }

                Section {
                    TextField("bijv. http://pc-van-saber:47820", text: $remoteAddress)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        #endif
                    HStack {
                        Button("Bewaren en testen") {
                            Task { await saveRemote() }
                        }
                        .disabled(checking)
                        if checking { ProgressView().controlSize(.small) }
                        Spacer()
                        if !remoteAddress.isEmpty {
                            Button("Wissen", role: .destructive) {
                                remoteAddress = ""
                                model.connection.setRemoteURL(nil)
                                remoteStatus = nil
                            }
                        }
                    }
                    if let remoteStatus {
                        Text(remoteStatus)
                            .font(.callout)
                            .foregroundStyle(remoteStatus.hasPrefix("Bereikbaar") ? .green : .red)
                    }
                } header: {
                    Text("Buitenshuis")
                } footer: {
                    // Say what this is for, and what it is NOT: nothing here opens a port.
                    Text("Zet Tailscale op je pc en op dit apparaat, en vul hier het Tailscale-adres "
                         + "van je pc in. Thuis wordt altijd eerst het gewone netwerk geprobeerd; "
                         + "lukt dat niet, dan dit adres. Er wordt niets opengezet naar het internet.")
                }

                Section {
                    LabeledContent("Bewaard", value: "\(model.downloads.savedCount) nummers")
                    LabeledContent("Ruimte", value: model.downloads.usedDescription)
                    if model.downloads.pending > 0 {
                        LabeledContent("Bezig", value: "nog \(model.downloads.pending)")
                    }
                    Button("Alles wissen", role: .destructive) { confirmClear = true }
                        .disabled(model.downloads.savedCount == 0)
                } header: {
                    Text("Offline")
                } footer: {
                    Text("Wat je offline bewaart speelt zonder netwerk. De originelen blijven op je pc "
                         + "staan — dit is een kopie, en wissen raakt je bibliotheek niet.")
                }

                Section {
                    Button("Ontkoppelen van deze pc", role: .destructive) { confirmForget = true }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Instellingen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
            .onAppear {
                remoteAddress = model.connection.settings.remoteURL?.absoluteString ?? ""
            }
            .alert("Alles offline wissen?", isPresented: $confirmClear) {
                Button("Wissen", role: .destructive) { model.downloads.removeAll() }
                Button("Annuleren", role: .cancel) {}
            } message: {
                Text("\(model.downloads.savedCount) nummers (\(model.downloads.usedDescription)) "
                     + "worden van dit apparaat verwijderd. Ze blijven op je pc staan.")
            }
            .alert("Ontkoppelen?", isPresented: $confirmForget) {
                Button("Ontkoppelen", role: .destructive) {
                    model.downloads.removeAll()
                    model.connection.forget()
                    dismiss()
                }
                Button("Annuleren", role: .cancel) {}
            } message: {
                Text("Je moet opnieuw koppelen met een code van je pc. Offline bewaarde nummers "
                     + "worden ook gewist.")
            }
        }
    }

    private func saveRemote() async {
        let trimmed = remoteAddress.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let text = trimmed.hasPrefix("http") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: text) else {
            remoteStatus = "Dat is geen geldig adres."
            return
        }
        checking = true
        remoteStatus = nil
        // Confirm before storing: an address that was mistyped would otherwise only reveal itself
        // the first time you are away from home and actually need it.
        do {
            let health = try await APIClient().health(at: url, timeout: 6)
            model.connection.setRemoteURL(url)
            remoteAddress = url.absoluteString
            remoteStatus = "Bereikbaar — \(health.deviceName ?? health.name)"
        } catch {
            remoteStatus = "Geen antwoord op dat adres. Draait Tailscale op allebei?"
        }
        checking = false
    }
}
