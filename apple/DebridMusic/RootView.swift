import DebridMusicKit
import SwiftUI

enum LibrarySection: String, CaseIterable, Identifiable {
    case home = "Start"
    case albums = "Albums"
    case artists = "Artiesten"
    case tracks = "Nummers"
    case playlists = "Afspeellijsten"
    case favorites = "Favorieten"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "house"
        case .albums: "square.grid.2x2"
        case .artists: "music.mic"
        case .tracks: "music.note.list"
        case .playlists: "list.bullet"
        case .favorites: "heart"
        }
    }
}

/// The shell: a sidebar, the section, and the player along the bottom.
///
/// `NavigationSplitView` on both platforms — on the Mac it is a real sidebar, on the iPad it
/// slides away in portrait and stays put in landscape, which is the layout an iPad user expects
/// without any of it being written twice.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var section: LibrarySection = .home
    @State private var searchText = ""

    var body: some View {
        Group {
            if model.isPaired {
                library
            } else {
                PairingView()
            }
        }
    }

    private var library: some View {
        // The player sits OUTSIDE the navigation, as app-level chrome.
        //
        // Inside the detail column it disappeared the moment a navigationDestination was pushed:
        // the pushed view takes the whole NavigationStack and squeezes a sibling to zero height.
        // Measured — a plain coloured bar was visible on Start and gone on an album page, while
        // the body kept running. Out here nothing the navigation does can take its space, and it
        // spans the full width under the sidebar too, like the Windows app.
        VStack(spacing: 0) {
            splitView
            PlayerBar()
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            List(LibrarySection.allCases, selection: Binding(
                get: { section },
                set: { section = $0 ?? .home }
            )) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationTitle("DebridMusic")
            #if os(iOS)
            .listStyle(.sidebar)
            #endif
            .safeAreaInset(edge: .bottom) { ConnectionBadge() }
        } detail: {
            VStack(spacing: 0) {
                NavigationStack {
                    content
                        .navigationTitle(section.rawValue)
                        .toolbar {
                            ToolbarItem {
                                Button {
                                    Task { await model.refresh() }
                                } label: {
                                    Label("Synchroniseren", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                        }
                }
                .searchable(text: $searchText, prompt: "Zoek in je bibliotheek")
            }
            .sheet(isPresented: Bindable(model).showingSpeakers) {
                SpeakerPicker()
            }
            .sheet(isPresented: Bindable(model).showingSettings) {
                SettingsView()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !searchText.isEmpty {
            SearchResultsView(query: searchText)
        } else {
            switch section {
            case .home: HomeView()
            case .albums: AlbumGridView(albums: model.library.albums)
            case .artists: ArtistListView()
            case .tracks: TrackListView(tracks: model.library.tracks)
            case .playlists: PlaylistsView()
            case .favorites: FavoritesView()
            }
        }
    }
}

/// Says which PC we're on, and whether it's answering right now.
struct ConnectionBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.connection.reachable ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.connection.serverName.isEmpty ? "Niet verbonden" : model.connection.serverName)
                    .font(.caption)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var statusText: String {
        switch model.library.status {
        case .syncing: return "Synchroniseren…"
        case .failed(let message): return message
        case .idle:
            guard model.connection.reachable else { return "Offline — opgeslagen bibliotheek" }
            return "\(model.library.tracks.count) nummers"
        }
    }
}
