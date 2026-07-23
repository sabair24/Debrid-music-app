import DebridMusicKit
import SwiftUI

/// The persistent player along the bottom — the same shape the Windows app has, so the two read
/// as one product rather than two apps that happen to share a library.
struct PlayerBar: View {
    @Environment(AppModel.self) private var model
    @State private var scrubbing: Double?

    var body: some View {
        // Still guarded, so the bar is safe to use anywhere; RootView decides whether to insert
        // it at all (see the note on its safeAreaInset).
        if let track = model.playback.current {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 14) {
                    Artwork(ref: track.artworkRef, size: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(.callout.weight(.medium)).lineLimit(1)
                        Text(track.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(minWidth: 120, alignment: .leading)

                    Spacer(minLength: 8)

                    HStack(spacing: 18) {
                        Button { model.playback.previous() } label: {
                            Image(systemName: "backward.fill")
                        }
                        Button { model.playback.togglePlayPause() } label: {
                            Image(systemName: model.playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                        }
                        Button { model.playback.next() } label: {
                            Image(systemName: "forward.fill")
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        Text(TrackRow.duration(model.playback.position))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { scrubbing ?? model.playback.position },
                                set: { scrubbing = $0 }
                            ),
                            in: 0...max(model.playback.duration, 1),
                            onEditingChanged: { editing in
                                // Commit on release, not continuously: seeking on every pixel of
                                // drag would re-buffer the stream dozens of times.
                                if !editing, let value = scrubbing {
                                    model.playback.seek(to: value)
                                    scrubbing = nil
                                }
                            }
                        )
                        .frame(minWidth: 140, maxWidth: 320)
                        Text(TrackRow.duration(model.playback.duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if let quality = track.qualityLabel {
                        Text(quality)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .foregroundStyle(.secondary)
                    }

                    // Two different things, deliberately side by side.
                    //
                    // This one hands the track to the PC, which sends the file straight to a
                    // Sonos, the KEF or the Shield — the audio never passes through here, so it
                    // stays bit-for-bit what is on disk.
                    Button {
                        model.showingSpeakers = true
                    } label: {
                        Image(systemName: "hifispeaker.2")
                    }
                    .buttonStyle(.plain)
                    .help("Speel af op een speaker of de tv")

                    // And this is the system's own AirPlay picker: routes THIS device's audio,
                    // which is handy for headphones but caps out at 16/44.1 ALAC.
                    RoutePickerButton()
                        .frame(width: 34, height: 30)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
    }
}

#if os(iOS)
import AVKit

struct RoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#else
import AVKit

struct RoutePickerButton: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        AVRoutePickerView()
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
#endif
