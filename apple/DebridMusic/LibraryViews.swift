import DebridMusicKit
import SwiftUI

/// One album's sleeve, loaded from the PC.
///
/// A cover that hasn't been fetched yet simply 404s, so the placeholder is the normal state for
/// part of a fresh library rather than an error worth reporting.
struct Artwork: View {
    let ref: String?
    var size: CGFloat = 160

    @Environment(AppModel.self) private var model

    var body: some View {
        AsyncImage(url: model.artworkURL(ref)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.28))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.05))
    }
}

struct AlbumGridView: View {
    let albums: [Album]

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 18)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
                        VStack(alignment: .leading, spacing: 6) {
                            Artwork(ref: album.artworkRef, size: 180)
                            Text(album.title).font(.callout.weight(.medium)).lineLimit(1)
                            Text(album.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if let edition = album.edition {
                                Text(edition).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
    }
}

struct AlbumDetailView: View {
    let album: Album
    @Environment(AppModel.self) private var model

    private var tracks: [Track] { model.library.tracks(ofAlbum: album.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom, spacing: 20) {
                    Artwork(ref: album.artworkRef, size: 200)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(album.title).font(.title.weight(.bold))
                        Text(album.artistName).font(.title3).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            if let year = album.year { Text(String(year)) }
                            Text("\(album.trackCount) nummers")
                            if let edition = album.edition { Text(edition) }
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                        HStack(spacing: 10) {
                            Button {
                                model.play(album: album)
                            } label: {
                                Label("Afspelen", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                Task {
                                    await model.library.toggleFavorite(
                                        album: album.id, on: model.connection.endpoint
                                    )
                                }
                            } label: {
                                Image(systemName: model.library.isFavorite(album: album.id)
                                      ? "heart.fill" : "heart")
                            }
                            .buttonStyle(.bordered)

                            OfflineButton(album: album)
                        }
                        .padding(.top, 6)
                    }
                    Spacer()
                }

                Divider()

                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, number: index + 1) {
                        model.play(tracks: tracks, from: index)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(album.title)
    }
}

/// Keep this album on the device, or give the space back.
struct OfflineButton: View {
    let album: Album
    @Environment(AppModel.self) private var model

    private var trackIds: [String] { model.library.tracks(ofAlbum: album.id).map(\.id) }

    private var busy: Int {
        trackIds.filter { model.downloads.state(of: $0).isBusy }.count
    }

    var body: some View {
        let saved = model.downloads.isSaved(album: trackIds)
        Button {
            if saved {
                model.removeOffline(album: album)
            } else {
                model.saveOffline(album: album)
            }
        } label: {
            if busy > 0 {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("\(busy)")
                }
            } else {
                Image(systemName: saved ? "arrow.down.circle.fill" : "arrow.down.circle")
            }
        }
        .buttonStyle(.bordered)
        .disabled(busy > 0 || (!saved && model.connection.endpoint == nil))
        .help(saved ? "Van dit apparaat verwijderen" : "Offline bewaren")
    }
}

struct TrackRow: View {
    let track: Track
    var number: Int?
    var onPlay: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            if let number {
                Text("\(number)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 26, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .lineLimit(1)
                    .foregroundStyle(model.playback.current?.id == track.id ? Color.accentColor : .primary)
                if number == nil {
                    Text(track.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let quality = track.qualityLabel {
                Text(quality)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await model.library.toggleFavorite(track: track.id, on: model.connection.endpoint) }
            } label: {
                Image(systemName: model.library.isFavorite(track: track.id) ? "heart.fill" : "heart")
                    .foregroundStyle(model.library.isFavorite(track: track.id) ? Color.pink : .secondary)
            }
            .buttonStyle(.plain)
            Text(Self.duration(track.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "–:––" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct TrackListView: View {
    let tracks: [Track]
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(track: track) { model.play(tracks: tracks, from: index) }
            }
        }
    }
}

struct ArtistListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.library.artists) { artist in
            NavigationLink(value: artist) {
                HStack(spacing: 12) {
                    Artwork(ref: artist.artworkRef, size: 44)
                        .clipShape(Circle())
                    VStack(alignment: .leading) {
                        Text(artist.name)
                        Text("\(artist.albumCount) albums")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationDestination(for: Artist.self) { artist in
            AlbumGridView(albums: model.library.albums(ofArtist: artist.id))
                .navigationTitle(artist.name)
        }
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Only when another device left something mid-track — the whole point of the
                // shared position is that it shows up here without being asked for.
                if let progress = model.library.remoteProgress,
                   let track = model.library.track(progress.trackId),
                   progress.deviceId != ServerIdentity.deviceId {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Verder luisteren").font(.headline)
                        HStack(spacing: 12) {
                            Artwork(ref: track.artworkRef, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title).font(.callout.weight(.medium))
                                Text("\(track.artistName) · van \(progress.deviceName)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Hervatten") { model.resumeRemote() }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(12)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                row("Recent toegevoegd", albums: Array(model.library.recentlyAdded.prefix(12)))

                let played = model.library.recentlyPlayed
                if !played.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent gespeeld").font(.headline)
                        ForEach(Array(played.prefix(6).enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track) { model.play(tracks: played, from: index) }
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
    }

    @ViewBuilder
    private func row(_ title: String, albums: [Album]) -> some View {
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(albums) { album in
                            NavigationLink(value: album) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Artwork(ref: album.artworkRef, size: 140)
                                    Text(album.title).font(.caption.weight(.medium)).lineLimit(1)
                                    Text(album.artistName).font(.caption2)
                                        .foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(width: 140)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

struct FavoritesView: View {
    @Environment(AppModel.self) private var model

    private var tracks: [Track] {
        model.library.tracks.filter { model.library.isFavorite(track: $0.id) }
    }
    private var albums: [Album] {
        model.library.albums.filter { model.library.isFavorite(album: $0.id) }
    }

    var body: some View {
        if tracks.isEmpty && albums.isEmpty {
            ContentUnavailableView(
                "Nog geen favorieten",
                systemImage: "heart",
                description: Text("Wat je hier bewaart, staat meteen ook op je Shield en je pc.")
            )
        } else {
            List {
                if !albums.isEmpty {
                    Section("Albums") {
                        ForEach(albums) { album in
                            NavigationLink(value: album) {
                                HStack(spacing: 12) {
                                    Artwork(ref: album.artworkRef, size: 44)
                                    VStack(alignment: .leading) {
                                        Text(album.title)
                                        Text(album.artistName).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                if !tracks.isEmpty {
                    Section("Nummers") {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track) { model.play(tracks: tracks, from: index) }
                        }
                    }
                }
            }
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
        }
    }
}

struct PlaylistsView: View {
    @Environment(AppModel.self) private var model
    @State private var newName = ""
    @State private var creating = false

    var body: some View {
        List {
            ForEach(model.library.playlists) { playlist in
                NavigationLink(value: playlist) {
                    VStack(alignment: .leading) {
                        Text(playlist.name)
                        Text("\(playlist.trackIds.count) nummers")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                let ids = offsets.map { model.library.playlists[$0].id }
                Task {
                    for id in ids {
                        await model.library.deletePlaylist(id, on: model.connection.endpoint)
                    }
                }
            }
        }
        .overlay {
            if model.library.playlists.isEmpty {
                ContentUnavailableView(
                    "Nog geen afspeellijsten",
                    systemImage: "list.bullet",
                    description: Text("Een lijst die je hier maakt, verschijnt ook op je pc en je Shield.")
                )
            }
        }
        .navigationDestination(for: Playlist.self) { playlist in
            let tracks = playlist.trackIds.compactMap { model.library.track($0) }
            TrackListView(tracks: tracks).navigationTitle(playlist.name)
        }
        .toolbar {
            ToolbarItem {
                Button { creating = true } label: { Label("Nieuw", systemImage: "plus") }
            }
        }
        .alert("Nieuwe afspeellijst", isPresented: $creating) {
            TextField("Naam", text: $newName)
            Button("Maken") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                newName = ""
                guard !name.isEmpty else { return }
                Task { await model.library.createPlaylist(named: name, on: model.connection.endpoint) }
            }
            Button("Annuleren", role: .cancel) { newName = "" }
        }
    }
}

struct SearchResultsView: View {
    let query: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let results = model.library.search(query)
        List {
            if !results.albums.isEmpty {
                Section("Albums") {
                    ForEach(results.albums) { album in
                        NavigationLink(value: album) {
                            HStack(spacing: 12) {
                                Artwork(ref: album.artworkRef, size: 44)
                                VStack(alignment: .leading) {
                                    Text(album.title)
                                    Text(album.artistName).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            if !results.tracks.isEmpty {
                Section("Nummers") {
                    ForEach(Array(results.tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(track: track) { model.play(tracks: results.tracks, from: index) }
                    }
                }
            }
        }
        .overlay {
            if results.albums.isEmpty && results.tracks.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
    }
}
