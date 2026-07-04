import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'catalog.dart';
import 'enrichment.dart';
import 'library.dart';
import 'models.dart';
import 'online.dart';
import 'player.dart';
import 'recommend.dart';
import 'settings.dart';
import 'soulseek.dart';
import 'tidal.dart';
import 'torbox.dart';

const _bg = Color(0xFF0C0D12);
const _panel = Color(0xFF181B26);
const _panel2 = Color(0xFF1F2331);
const _line = Color(0xFF272B3A);
const _text = Color(0xFFE8EAF2);
const _muted = Color(0xFF9AA0B4);
const _accent = Color(0xFF7C5CFF);
const _accent2 = Color(0xFF00D4C8);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1240, 820),
      minimumSize: Size(940, 640),
      center: true,
      title: 'DebridMusic',
      titleBarStyle: TitleBarStyle.normal,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  final settings = AppSettings();
  await settings.load();
  final library = LibraryStore();
  final online = OnlineService(settings);
  final soulseek = SoulseekService(settings);
  final tidal = TidalService(settings);
  final player = PlayerStore()..resolver = online.resolveRadio;
  final downloads = DownloadManager(online, soulseek, library.rootPath, () async {
    await library.scan();
    await library.enrich(settings);
  });
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettings>.value(value: settings),
        ChangeNotifierProvider<LibraryStore>.value(value: library),
        ChangeNotifierProvider<PlayerStore>.value(value: player),
        Provider<OnlineService>.value(value: online),
        Provider<SoulseekService>.value(value: soulseek),
        Provider<TidalService>.value(value: tidal),
        ChangeNotifierProvider<DownloadManager>.value(value: downloads),
      ],
      child: const DebridApp(),
    ),
  );
  // Scan, then fill in missing covers + artist photos (cache-first, then web).
  // Wrapped so a scan hiccup can never prevent enrichment from running.
  () async {
    try {
      await library.scan();
    } catch (_) {}
    await library.enrich(settings);
    await library.enrichArtists(settings);
  }();
}

class DebridApp extends StatelessWidget {
  const DebridApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DebridMusic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          secondary: _accent2,
          surface: _panel,
        ),
        fontFamily: 'Segoe UI',
      ),
      home: const HomeShell(),
    );
  }
}

// ── Cover helpers ────────────────────────────────────────────────────────────
Widget cover(Uint8List? bytes, {double size = 160, double radius = 12, bool circle = false}) {
  final shape = circle ? BoxShape.circle : BoxShape.rectangle;
  final br = circle ? null : BorderRadius.circular(radius);
  if (bytes != null) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(shape: shape, borderRadius: br),
      child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: shape,
      borderRadius: br,
      gradient: const LinearGradient(colors: [Color(0xFF242838), Color(0xFF1A1D29)]),
    ),
    child: Icon(Icons.music_note_rounded, color: _muted.withValues(alpha: .4), size: size * .34),
  );
}

// ── Home shell ───────────────────────────────────────────────────────────────
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _view = 0; // 0 albums, 1 artists

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _railView(),
                Container(width: 1, color: _line),
                Expanded(child: _content()),
              ],
            ),
          ),
          const PlayerBar(),
        ],
      ),
    );
  }

  Widget _railView() {
    return Container(
      width: 210,
      color: const Color(0xFF10121B),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 18),
            child: Row(
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(colors: [_accent, _accent2]),
                  ),
                  child: const Icon(Icons.music_note_rounded, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Text('DebridMusic', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
          ),
          _navBtn(Icons.album_rounded, 'Albums', 0),
          _navBtn(Icons.people_alt_rounded, 'Artiesten', 1),
          _navBtn(Icons.travel_explore_rounded, 'Online zoeken', 2),
          const Spacer(),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => showDialog(context: context, builder: (_) => const SettingsDialog()),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                child: Row(
                  children: [
                    Icon(Icons.settings_rounded, size: 18, color: _muted),
                    SizedBox(width: 11),
                    Text('Instellingen',
                        style: TextStyle(color: _muted, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
          Consumer<LibraryStore>(
            builder: (_, lib, __) => Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                lib.scanning
                    ? 'Bibliotheek scannen… ${lib.scanned}'
                    : (lib.enriching
                        ? 'Covers ophalen…'
                        : '${lib.albums.length} albums · ${lib.tracks.length} nummers'),
                style: const TextStyle(color: Color(0xFF5F6478), fontSize: 11.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, String label, int index) {
    final active = _view == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active ? _accent.withValues(alpha: .15) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _view = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: active ? Colors.white : _muted),
                const SizedBox(width: 11),
                Text(label,
                    style: TextStyle(
                        color: active ? Colors.white : _muted, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (_view == 2) return const OnlineSearchScreen();
    return Consumer<LibraryStore>(
      builder: (_, lib, __) {
        if (lib.scanning && lib.albums.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (lib.albums.isEmpty) {
          return const Center(
              child: Text('Geen muziek gevonden in D:\\Flac music 2024',
                  style: TextStyle(color: _muted)));
        }
        return _view == 0 ? AlbumsGrid(albums: lib.albums) : ArtistsView(lib: lib);
      },
    );
  }
}

// ── Albums grid ──────────────────────────────────────────────────────────────
class AlbumsGrid extends StatelessWidget {
  final List<Album> albums;
  final String? title;
  const AlbumsGrid({super.key, required this.albums, this.title});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
          sliver: SliverToBoxAdapter(
            child: Text(title ?? 'Albums',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
              childAspectRatio: .78,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) => AlbumCard(album: albums[i]),
              childCount: albums.length,
            ),
          ),
        ),
      ],
    );
  }
}

class AlbumCard extends StatefulWidget {
  final Album album;
  const AlbumCard({super.key, required this.album});
  @override
  State<AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<AlbumCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final a = widget.album;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => AlbumDetailPage(album: a))),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          transform: _hover ? Matrix4.translationValues(0, -3, 0) : Matrix4.identity(),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _hover ? _panel2 : _panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: LayoutBuilder(builder: (_, c) => cover(a.cover, size: c.maxWidth))),
              const SizedBox(height: 9),
              Text(a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              Text(a.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Album detail ─────────────────────────────────────────────────────────────
class AlbumDetailPage extends StatelessWidget {
  final Album album;
  const AlbumDetailPage({super.key, required this.album});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  backgroundColor: _bg,
                  pinned: true,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                SliverToBoxAdapter(child: _header(context)),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => TrackRow(
                        track: album.tracks[i], index: i, queue: album.tracks, albumCover: album.cover),
                    childCount: album.tracks.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
          const PlayerBar(),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final player = context.read<PlayerStore>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          cover(album.cover, size: 200),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Album', style: TextStyle(color: _muted)),
                const SizedBox(height: 6),
                Text(album.title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  [
                    album.artist,
                    if (album.year != null) '${album.year}',
                    if (album.genre != null) album.genre!,
                    '${album.tracks.length} nummers',
                  ].join(' · '),
                  style: const TextStyle(color: _muted),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                      ),
                      onPressed: () => player.playQueue(album.tracks, 0, cover: album.cover),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Afspelen'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _panel2,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      ),
                      onPressed: () => startRadio(context, album.artist),
                      icon: const Icon(Icons.radio_rounded, size: 20),
                      label: const Text('Radio'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TrackRow extends StatefulWidget {
  final Track track;
  final int index;
  final List<Track> queue;
  final Uint8List? albumCover;
  const TrackRow(
      {super.key, required this.track, required this.index, required this.queue, this.albumCover});
  @override
  State<TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<TrackRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final current = context.watch<PlayerStore>().current;
    final isCurrent = current?.path == t.path;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context
            .read<PlayerStore>()
            .playQueue(widget.queue, widget.index, cover: widget.albumCover),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: isCurrent
                ? _accent.withValues(alpha: .16)
                : (_hover ? _panel : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: _hover
                    ? const Icon(Icons.play_arrow_rounded, size: 18, color: _accent)
                    : Text('${t.trackNo > 0 ? t.trackNo : widget.index + 1}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: _muted, fontSize: 13)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: isCurrent ? _accent2 : _text)),
              ),
              if (t.isFlac)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2521),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF24493F)),
                  ),
                  child: const Text('FLAC', style: TextStyle(color: _accent2, fontSize: 10.5)),
                ),
              Text(_fmt(t.duration), style: const TextStyle(color: _muted, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Artists ──────────────────────────────────────────────────────────────────
class ArtistsView extends StatefulWidget {
  final LibraryStore lib;
  const ArtistsView({super.key, required this.lib});
  @override
  State<ArtistsView> createState() => _ArtistsViewState();
}

class _ArtistsViewState extends State<ArtistsView> {
  String? _selected;
  @override
  Widget build(BuildContext context) {
    if (_selected != null) {
      final name = _selected!;
      final albums = widget.lib.albums.where((a) => a.artist == name).toList();
      final trackCount = albums.fold<int>(0, (s, a) => s + a.tracks.length);
      final img = widget.lib.artistImages[name];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 0, 0),
            child: TextButton.icon(
              onPressed: () => setState(() => _selected = null),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Artiesten'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
            child: Row(
              children: [
                cover(img, size: 96, circle: true),
                const SizedBox(width: 18),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('${albums.length} albums · $trackCount nummers',
                        style: const TextStyle(color: _muted)),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
                      onPressed: () => startRadio(context, name),
                      icon: const Icon(Icons.radio_rounded, size: 18),
                      label: const Text('Radio'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.lib.artistBios[name] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: BioText(name, widget.lib.artistBios[name]!),
            ),
          Expanded(child: AlbumsGrid(albums: albums, title: 'Albums')),
        ],
      );
    }
    final artists = widget.lib.artists;
    return CustomScrollView(
      slivers: [
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(24, 22, 24, 8),
          sliver: SliverToBoxAdapter(
            child: Text('Artiesten', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                childAspectRatio: .82),
            delegate: SliverChildBuilderDelegate((_, i) {
              final name = artists[i];
              final art = widget.lib.artistImages[name] ??
                  widget.lib.albums.firstWhere((a) => a.artist == name).cover;
              return GestureDetector(
                onTap: () => setState(() => _selected = name),
                child: Column(
                  children: [
                    Expanded(
                        child: LayoutBuilder(
                            builder: (_, c) => cover(art, size: c.maxWidth, circle: true))),
                    const SizedBox(height: 8),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              );
            }, childCount: artists.length),
          ),
        ),
      ],
    );
  }
}

// ── Now-playing bar ──────────────────────────────────────────────────────────
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerStore>();
    final t = p.current;
    return Container(
      height: 84,
      decoration: const BoxDecoration(
        color: Color(0xFF12141D),
        border: Border(top: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          SizedBox(
            width: 280,
            child: Row(
              children: [
                GestureDetector(
                  onTap: t == null
                      ? null
                      : () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const NowPlayingScreen())),
                  child: MouseRegion(
                    cursor: t == null ? MouseCursor.defer : SystemMouseCursors.click,
                    child: cover(p.currentCover, size: 54, radius: 8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t?.title ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                          p.radioMode && p.radioStatus.isNotEmpty
                              ? p.radioStatus
                              : (t?.artist ?? 'Niets aan het spelen'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.radioMode && p.radioStatus.isNotEmpty ? _accent2 : _muted, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.shuffle_rounded, size: 20),
                      color: p.shuffle ? _accent : _muted,
                      onPressed: p.toggleShuffle,
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded),
                      color: _muted,
                      onPressed: p.hasPrev || p.position > const Duration(seconds: 3) ? p.prev : null,
                    ),
                    const SizedBox(width: 2),
                    Container(
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: IconButton(
                        icon: Icon(p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        color: _bg,
                        iconSize: 26,
                        onPressed: t == null ? null : p.playPause,
                      ),
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded),
                      color: _muted,
                      onPressed: p.hasNext ? p.next : null,
                    ),
                    IconButton(
                      icon: Icon(p.repeat == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                          size: 20),
                      color: p.repeat == RepeatMode.off ? _muted : _accent,
                      onPressed: p.cycleRepeat,
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(_fmt(p.position), style: const TextStyle(color: _muted, fontSize: 11.5)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          activeTrackColor: _accent,
                          inactiveTrackColor: const Color(0xFF2A2F42),
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: _progress(p),
                          onChanged: t == null || p.duration.inMilliseconds == 0
                              ? null
                              : (v) => p.seek(Duration(
                                  milliseconds: (v * p.duration.inMilliseconds).round())),
                        ),
                      ),
                    ),
                    Text(_fmt(p.duration), style: const TextStyle(color: _muted, fontSize: 11.5)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 280),
        ],
      ),
    );
  }

  double _progress(PlayerStore p) {
    if (p.duration.inMilliseconds == 0) return 0;
    return (p.position.inMilliseconds / p.duration.inMilliseconds).clamp(0.0, 1.0);
  }
}

// ── Now playing (full screen, enlargeable art) ───────────────────────────────
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerStore>();
    final t = p.current;
    final prog = p.duration.inMilliseconds == 0
        ? 0.0
        : (p.position.inMilliseconds / p.duration.inMilliseconds).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          if (p.currentCover != null)
            Positioned.fill(
              child: Opacity(opacity: .22, child: Image.memory(p.currentCover!, fit: BoxFit.cover)),
            ),
          Positioned.fill(child: Container(color: _bg.withValues(alpha: .5))),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: p.currentCover == null
                      ? null
                      : () => showDialog(context: context, builder: (_) => _ZoomView(p.currentCover!)),
                  child: MouseRegion(
                    cursor: p.currentCover == null ? MouseCursor.defer : SystemMouseCursors.zoomIn,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: .5), blurRadius: 44, offset: const Offset(0, 22))
                        ],
                      ),
                      child: cover(p.currentCover, size: 360, radius: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Text(t?.title ?? '—',
                    style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(t?.artist ?? '', style: const TextStyle(color: _muted, fontSize: 15)),
                const SizedBox(height: 26),
                SizedBox(
                  width: 540,
                  child: Row(
                    children: [
                      Text(_fmt(p.position), style: const TextStyle(color: _muted, fontSize: 12)),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                            activeTrackColor: _accent,
                            inactiveTrackColor: const Color(0xFF2A2F42),
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: prog,
                            onChanged: t == null || p.duration.inMilliseconds == 0
                                ? null
                                : (v) => p.seek(Duration(milliseconds: (v * p.duration.inMilliseconds).round())),
                          ),
                        ),
                      ),
                      Text(_fmt(p.duration), style: const TextStyle(color: _muted, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.shuffle_rounded),
                        iconSize: 24,
                        color: p.shuffle ? _accent : _muted,
                        onPressed: p.toggleShuffle),
                    const SizedBox(width: 12),
                    IconButton(
                        icon: const Icon(Icons.skip_previous_rounded),
                        iconSize: 34,
                        color: _text,
                        onPressed: p.hasPrev || p.position > const Duration(seconds: 3) ? p.prev : null),
                    const SizedBox(width: 8),
                    Container(
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: IconButton(
                        icon: Icon(p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        color: _bg,
                        iconSize: 40,
                        onPressed: t == null ? null : p.playPause,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                        icon: const Icon(Icons.skip_next_rounded),
                        iconSize: 34,
                        color: _text,
                        onPressed: p.hasNext ? p.next : null),
                    const SizedBox(width: 12),
                    IconButton(
                        icon: Icon(p.repeat == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded),
                        iconSize: 24,
                        color: p.repeat == RepeatMode.off ? _muted : _accent,
                        onPressed: p.cycleRepeat),
                  ],
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomView extends StatelessWidget {
  final Uint8List bytes;
  const _ZoomView(this.bytes);
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Center(child: Image.memory(bytes)),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Online search (TorBox) ───────────────────────────────────────────────────
String _fmtBytes(int b) => b >= 1000000000
    ? '${(b / 1e9).toStringAsFixed(2)} GB'
    : b >= 1000000
        ? '${(b / 1e6).round()} MB'
        : '${(b / 1e3).round()} KB';

// Shared source-result rendering + actions (used by direct search AND browse sources).
void _srcToast(BuildContext context, String m) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
}

// ── Radio / Smart Shuffle ────────────────────────────────────────────────────
String _radioNorm(String s) {
  var x = s.toLowerCase();
  final f = x.indexOf(' feat');
  if (f > 0) x = x.substring(0, f);
  return x.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// Build a Radio queue around [artist]: Deezer recommendations, matched against the
/// local library (owned tracks play instantly; the rest resolve via TorBox on demand).
Future<void> startRadio(BuildContext context, String artist) async {
  final player = context.read<PlayerStore>();
  final lib = context.read<LibraryStore>();
  _srcToast(context, '📻 Radio starten voor $artist…');
  List<RecTrack> recs;
  try {
    recs = await RecommendService().mixRadio(artist);
  } catch (_) {
    recs = const [];
  }
  if (!context.mounted) return;
  if (recs.isEmpty) {
    _srcToast(context, 'Geen radio gevonden voor $artist.');
    return;
  }
  final index = <String, Track>{};
  for (final t in lib.tracks) {
    index.putIfAbsent('${_radioNorm(t.artist)}|${_radioNorm(t.title)}', () => t);
  }
  final items = recs
      .map((r) => RadioItem(
            artist: r.artist,
            title: r.title,
            local: index['${_radioNorm(r.artist)}|${_radioNorm(r.title)}'],
          ))
      .toList();
  await player.playRadio(items);
}

Future<void> _playTorrent(BuildContext context, SearchResult r) async {
  _srcToast(context, 'Bron voorbereiden…');
  try {
    final url = await context.read<OnlineService>().resolveStreamUrl(r);
    if (context.mounted) context.read<PlayerStore>().playUrl(url, title: r.name, artist: r.source);
  } catch (e) {
    if (context.mounted) _srcToast(context, 'Kan niet afspelen: $e');
  }
}

Future<void> _downloadTorrent(BuildContext context, SearchResult r) async {
  try {
    final n = await context.read<DownloadManager>().enqueue(r);
    if (context.mounted) _srcToast(context, '$n nummer(s) naar downloads');
  } catch (e) {
    if (context.mounted) _srcToast(context, 'Download mislukt: $e');
  }
}

void _pickTorrentTracks(BuildContext context, SearchResult r) {
  showDialog(context: context, builder: (_) => _TrackPickerDialog(r));
}

Future<void> _downloadSoulseek(BuildContext context, SoulseekFile f) async {
  try {
    await context.read<DownloadManager>().enqueueSoulseek(f);
    if (context.mounted) _srcToast(context, '“${f.displayName}” via Soulseek…');
  } catch (e) {
    if (context.mounted) _srcToast(context, 'Download mislukt: $e');
  }
}

Widget _flacBadge() => Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2521),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF24493F)),
      ),
      child: const Text('FLAC', style: TextStyle(color: _accent2, fontSize: 10.5)),
    );

Widget _sourceHeader(String title, int count, bool loading) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
      child: Row(
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(color: _muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6)),
          const SizedBox(width: 8),
          Text('$count', style: const TextStyle(color: _muted, fontSize: 11.5)),
          if (loading) ...const [
            SizedBox(width: 8),
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: _muted)),
          ],
        ],
      ),
    );

Widget _torrentTile(BuildContext context, SearchResult r) {
  final flac = RegExp('flac', caseSensitive: false).hasMatch(r.name);
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(8)),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text('${r.source} · ${r.seeders} seeders · ${_fmtBytes(r.size)}',
                      style: const TextStyle(color: _muted, fontSize: 12)),
                  if (r.cached)
                    const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Text('⚡ Instant', style: TextStyle(color: _accent2, fontSize: 12))),
                ],
              ),
            ],
          ),
        ),
        if (flac) _flacBadge(),
        IconButton(icon: const Icon(Icons.play_arrow_rounded), color: _accent, tooltip: 'Beste nummer afspelen', onPressed: () => _playTorrent(context, r)),
        IconButton(icon: const Icon(Icons.queue_music_rounded), color: _muted, tooltip: 'Kies nummer', onPressed: () => _pickTorrentTracks(context, r)),
        IconButton(icon: const Icon(Icons.download_rounded), color: _muted, tooltip: 'Alles downloaden', onPressed: () => _downloadTorrent(context, r)),
      ],
    ),
  );
}

Widget _soulseekTile(BuildContext context, SoulseekFile f) {
  final status = f.freeSlots ? 'vrij' : 'wachtrij ${f.queueLength}';
  final quality = f.isFlac ? 'FLAC' : ((f.bitrate ?? 0) > 0 ? '${f.bitrate}kbps' : '');
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(8)),
    child: Row(
      children: [
        Icon(f.freeSlots ? Icons.circle : Icons.schedule_rounded, size: 10, color: f.freeSlots ? _accent2 : _muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(f.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('$status · ${f.username} · ${_fmtBytes(f.size)}${quality.isNotEmpty ? " · $quality" : ""}',
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ],
          ),
        ),
        if (f.isFlac) _flacBadge(),
        IconButton(icon: const Icon(Icons.download_rounded), color: _accent, tooltip: 'Downloaden via Soulseek', onPressed: () => _downloadSoulseek(context, f)),
      ],
    ),
  );
}

/// Network cover with a graceful placeholder (album browse / artist photos from Deezer).
Widget _netCover(String? url, {double size = 160, double radius = 12, bool circle = false}) {
  final shape = circle ? BoxShape.circle : BoxShape.rectangle;
  final br = circle ? null : BorderRadius.circular(radius);
  final placeholder = Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: shape,
      borderRadius: br,
      gradient: const LinearGradient(colors: [Color(0xFF242838), Color(0xFF1A1D29)]),
    ),
    child: Icon(circle ? Icons.person_rounded : Icons.album_rounded, color: _muted.withValues(alpha: .4), size: size * .34),
  );
  if (url == null || url.isEmpty) return placeholder;
  return Container(
    width: size,
    height: size,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(shape: shape, borderRadius: br),
    child: Image.network(url, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (c, w, p) => p == null ? w : placeholder),
  );
}

/// Combined torrent + Soulseek sources for one query — the "streams" list under a track/album.
class SourcesView extends StatefulWidget {
  final String query;
  const SourcesView({super.key, required this.query});
  @override
  State<SourcesView> createState() => _SourcesViewState();
}

class _SourcesViewState extends State<SourcesView> {
  List<SearchResult> _torrents = [];
  List<SoulseekFile> _slsk = [];
  bool _tBusy = true, _sBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final online = context.read<OnlineService>();
    final soulseek = context.read<SoulseekService>();
    if (mounted) setState(() { _tBusy = true; _sBusy = soulseek.available; });
    if (soulseek.available) {
      soulseek.search(widget.query).then((r) {
        if (mounted) setState(() { _slsk = r; _sBusy = false; });
      }).catchError((_) { if (mounted) setState(() => _sBusy = false); });
    }
    try {
      final r = await online.search(widget.query);
      if (mounted) setState(() => _torrents = r);
    } catch (_) {}
    if (mounted) setState(() => _tBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ready = context.read<SoulseekService>().available;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sourceHeader('Torrents · TorBox', _torrents.length, _tBusy),
        if (_torrents.isEmpty && !_tBusy)
          const Padding(
              padding: EdgeInsets.fromLTRB(24, 2, 24, 6),
              child: Text('Geen torrents gevonden.', style: TextStyle(color: _muted, fontSize: 12.5))),
        ..._torrents.map((r) => _torrentTile(context, r)),
        if (ready)
          _sourceHeader('Soulseek · P2P', _slsk.length, _sBusy)
        else
          const Padding(
              padding: EdgeInsets.fromLTRB(24, 14, 24, 6),
              child: Text('SOULSEEK · log in via Instellingen',
                  style: TextStyle(color: _muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6))),
        if (ready && _slsk.isEmpty && !_sBusy)
          const Padding(
              padding: EdgeInsets.fromLTRB(24, 2, 24, 6),
              child: Text('Geen Soulseek-bronnen.', style: TextStyle(color: _muted, fontSize: 12.5))),
        ..._slsk.map((f) => _soulseekTile(context, f)),
      ],
    );
  }
}

class OnlineSearchScreen extends StatefulWidget {
  const OnlineSearchScreen({super.key});
  @override
  State<OnlineSearchScreen> createState() => _OnlineSearchScreenState();
}

class _OnlineSearchScreenState extends State<OnlineSearchScreen> {
  final _c = TextEditingController();
  final _catalog = CatalogService();
  int _mode = 0; // 0 = Bladeren, 1 = Direct, 2 = TIDAL
  // browse
  List<CatalogArtist> _artists = [];
  bool _artistsBusy = false;
  // direct
  List<SearchResult> _torrents = [];
  List<SoulseekFile> _slsk = [];
  bool _busy = false, _slskBusy = false;
  String? _status;
  // tidal
  List<TidalTrack> _tidalTracks = [];
  bool _tidalBusy = false, _tidalConnecting = false;
  int? _tidalExpanded;

  Future<void> _search() async {
    final q = _c.text.trim();
    if (q.isEmpty) return;
    if (_mode == 0) {
      await _searchArtists(q);
    } else if (_mode == 1) {
      await _searchDirect(q);
    } else {
      await _searchTidal(q);
    }
  }

  Future<void> _searchTidal(String q) async {
    final tidal = context.read<TidalService>();
    if (!tidal.connected) return;
    setState(() { _tidalBusy = true; _tidalTracks = []; _tidalExpanded = null; _status = null; });
    try {
      final t = await tidal.searchTracks(q);
      if (mounted) setState(() { _tidalTracks = t; _status = t.isEmpty ? 'Geen TIDAL-resultaten.' : null; });
    } catch (e) {
      if (mounted) setState(() => _status = 'TIDAL-zoeken mislukt: $e');
    } finally {
      if (mounted) setState(() => _tidalBusy = false);
    }
  }

  Future<void> _connectTidal() async {
    final tidal = context.read<TidalService>();
    setState(() => _tidalConnecting = true);
    try {
      await tidal.login();
      if (mounted) _srcToast(context, 'TIDAL verbonden ✓');
    } catch (e) {
      if (mounted) _srcToast(context, 'TIDAL-login mislukt: $e');
    } finally {
      if (mounted) setState(() => _tidalConnecting = false);
    }
  }

  Future<void> _manualTidal() async {
    final tidal = context.read<TidalService>();
    final ctrl = TextEditingController();
    final pasted = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('TIDAL-code plakken', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Plak de volledige "debridmusic://…"-URL (of enkel de code) die je browser na het inloggen toonde.',
                  style: TextStyle(color: _muted, fontSize: 12.5)),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFF14161F),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _line)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuleren')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Verbind'),
          ),
        ],
      ),
    );
    if (pasted == null || pasted.isEmpty) return;
    setState(() => _tidalConnecting = true);
    try {
      await tidal.completeManual(pasted);
      if (mounted) _srcToast(context, 'TIDAL verbonden ✓');
    } catch (e) {
      if (mounted) _srcToast(context, 'Mislukt: $e');
    } finally {
      if (mounted) setState(() => _tidalConnecting = false);
    }
  }

  Future<void> _searchArtists(String q) async {
    setState(() { _artistsBusy = true; _artists = []; _status = null; });
    try {
      final a = await _catalog.searchArtists(q);
      if (mounted) setState(() { _artists = a; _status = a.isEmpty ? 'Geen artiesten gevonden.' : null; });
    } catch (e) {
      if (mounted) setState(() => _status = 'Zoeken mislukt: $e');
    } finally {
      if (mounted) setState(() => _artistsBusy = false);
    }
  }

  Future<void> _searchDirect(String q) async {
    final online = context.read<OnlineService>();
    final soulseek = context.read<SoulseekService>();
    setState(() {
      _busy = true;
      _slskBusy = soulseek.available;
      _torrents = [];
      _slsk = [];
      _status = 'Zoeken over Pirate Bay, BitSearch, Knaben${soulseek.available ? " + Soulseek…" : "…"}';
    });
    if (soulseek.available) {
      soulseek.search(q).then((r) {
        if (mounted) setState(() { _slsk = r; _slskBusy = false; });
      }).catchError((_) {
        if (mounted) setState(() => _slskBusy = false);
      });
    }
    try {
      final r = await online.search(q);
      if (mounted) setState(() { _torrents = r; _status = null; });
    } catch (e) {
      if (mounted) setState(() => _status = 'Torrent-zoeken mislukt: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setMode(int m) {
    if (m == _mode) return;
    setState(() { _mode = m; _status = null; });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final soulseekReady = context.read<SoulseekService>().available;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 22, 24, 8),
          child: Text('Online zoeken', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Row(children: [
            _modeChip('Bladeren', 0),
            const SizedBox(width: 8),
            _modeChip('Direct zoeken', 1),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: _mode == 0
                        ? 'Zoek een artiest…'
                        : (_mode == 2 ? 'Zoek in TIDAL…' : 'Artiest, album of nummer…'),
                    filled: true,
                    fillColor: _panel,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _line)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _line)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18)),
                onPressed: (_busy || _artistsBusy || _tidalBusy) ? null : _search,
                child: const Text('Zoek'),
              ),
            ],
          ),
        ),
        Consumer<DownloadManager>(
          builder: (_, dm, __) {
            final recent = dm.jobs.take(5).toList();
            if (recent.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                children: recent
                    .map((j) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text(j.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5))),
                              SizedBox(
                                width: 160,
                                child: LinearProgressIndicator(
                                  value: j.status == 'done' ? 1 : j.progress,
                                  backgroundColor: const Color(0xFF2A2F42),
                                  color: j.status == 'failed'
                                      ? Colors.red
                                      : (j.status == 'done' ? _accent2 : _accent),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 54,
                                child: Text(
                                  j.status == 'done'
                                      ? 'klaar'
                                      : (j.status == 'failed' ? 'mislukt' : '${(j.progress * 100).round()}%'),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(color: _muted, fontSize: 11.5),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            );
          },
        ),
        if (_status != null)
          Padding(padding: const EdgeInsets.all(24), child: Text(_status!, style: const TextStyle(color: _muted))),
        Expanded(
            child: _mode == 0
                ? _browseResults()
                : (_mode == 1 ? _directResults(soulseekReady) : _tidalResults())),
      ],
    );
  }

  Widget _tidalResults() {
    final tidal = context.read<TidalService>();
    if (!tidal.configured) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Stel je TIDAL Client ID + Secret in via Instellingen (⚙) om TIDAL te gebruiken.',
              textAlign: TextAlign.center, style: TextStyle(color: _muted)),
        ),
      );
    }
    if (!tidal.connected) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text('Verbind je TIDAL-account om je muziek te doorzoeken.\n'
                  'Je logt in op TIDAL zelf — DebridMusic ziet je wachtwoord niet.',
                  textAlign: TextAlign.center, style: TextStyle(color: _muted)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
              icon: _tidalConnecting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.link_rounded, size: 18),
              label: Text(_tidalConnecting ? 'Bezig… (log in in je browser)' : 'Verbind TIDAL'),
              onPressed: _tidalConnecting ? null : _connectTidal,
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _tidalConnecting ? null : _manualTidal,
              child: const Text('Lukt het automatisch niet? Plak de URL handmatig',
                  style: TextStyle(color: _muted, fontSize: 12.5)),
            ),
          ],
        ),
      );
    }
    if (_tidalBusy) return const Center(child: CircularProgressIndicator(color: _accent));
    if (_tidalTracks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Verbonden met TIDAL ✓  — zoek een nummer; de bronnen (torrent/Soulseek) verschijnen eronder.',
              textAlign: TextAlign.center, style: TextStyle(color: _muted)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _tidalTracks.length,
      itemBuilder: (_, i) => _tidalTrackRow(i, _tidalTracks[i]),
    );
  }

  Widget _tidalTrackRow(int i, TidalTrack t) {
    final open = _tidalExpanded == i;
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _tidalExpanded = open ? null : i),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(color: open ? _panel : Colors.transparent, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (t.artist.isNotEmpty)
                        Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(open ? Icons.expand_less_rounded : Icons.travel_explore_rounded, size: 18, color: open ? _accent : _muted),
              ],
            ),
          ),
        ),
        if (open) Padding(padding: const EdgeInsets.only(bottom: 8), child: SourcesView(query: t.sourceQuery)),
      ],
    );
  }

  Widget _modeChip(String label, int m) {
    final sel = _mode == m;
    return GestureDetector(
      onTap: () => _setMode(m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _accent : _panel,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: sel ? _accent : _line),
        ),
        child: Text(label, style: TextStyle(color: sel ? Colors.white : _muted, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _browseResults() {
    if (_artistsBusy) return const Center(child: CircularProgressIndicator(color: _accent));
    if (_artists.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Zoek een artiest om hun albums en bronnen (torrent/Soulseek) te bladeren.',
              textAlign: TextAlign.center, style: TextStyle(color: _muted)),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .8),
      itemCount: _artists.length,
      itemBuilder: (_, i) {
        final a = _artists[i];
        return InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtistBrowsePage(a))),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: [
              _netCover(a.picture, size: 116, circle: true),
              const SizedBox(height: 6),
              Text(a.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        );
      },
    );
  }

  Widget _directResults(bool soulseekReady) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_torrents.isNotEmpty) _sourceHeader('Torrents · TorBox', _torrents.length, _busy),
        ..._torrents.map((r) => _torrentTile(context, r)),
        if (_status == null || _slsk.isNotEmpty || _slskBusy)
          (soulseekReady
              ? _sourceHeader('Soulseek · P2P', _slsk.length, _slskBusy)
              : const Padding(
                  padding: EdgeInsets.fromLTRB(24, 16, 24, 6),
                  child: Text('SOULSEEK · log in via Instellingen om P2P mee te zoeken',
                      style: TextStyle(color: _muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6)))),
        ..._slsk.map((f) => _soulseekTile(context, f)),
      ],
    );
  }
}

/// Resolves a torrent's audio files and lets the user play or download any single track.
class _TrackPickerDialog extends StatefulWidget {
  final SearchResult result;
  const _TrackPickerDialog(this.result);
  @override
  State<_TrackPickerDialog> createState() => _TrackPickerDialogState();
}

class _TrackPickerDialogState extends State<_TrackPickerDialog> {
  bool _loading = true;
  String? _error;
  TbTorrent? _torrent;
  List<TbFile> _files = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (t, f) = await context.read<OnlineService>().tracklist(widget.result);
      if (!mounted) return;
      setState(() {
        _torrent = t;
        _files = f;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _play(TbFile f) async {
    try {
      final url = await context.read<OnlineService>().resolveTrackUrl(_torrent!.id, f.id);
      if (!mounted) return;
      context.read<PlayerStore>().playUrl(url, title: f.label, artist: widget.result.source);
      Navigator.pop(context);
    } catch (e) {
      _snack('Afspelen mislukt: $e');
    }
  }

  Future<void> _download(TbFile f) async {
    try {
      await context.read<DownloadManager>().enqueue(widget.result, fileId: f.id);
      _snack('“${f.label}” naar downloads');
    } catch (e) {
      _snack('Download mislukt: $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.result.name,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Kies een nummer om af te spelen of los te downloaden',
                style: TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(children: [
                    CircularProgressIndicator(color: _accent),
                    SizedBox(height: 14),
                    Text('Bron voorbereiden bij TorBox…', style: TextStyle(color: _muted, fontSize: 12.5)),
                  ]),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _files.length,
                  itemBuilder: (_, i) {
                    final f = _files[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                                Text('${_fmtBytes(f.size)}${f.isFlac ? " · FLAC" : ""}',
                                    style: const TextStyle(color: _muted, fontSize: 11.5)),
                              ],
                            ),
                          ),
                          IconButton(
                              icon: const Icon(Icons.play_arrow_rounded, size: 22),
                              color: _accent,
                              tooltip: 'Afspelen',
                              onPressed: () => _play(f)),
                          IconButton(
                              icon: const Icon(Icons.download_rounded, size: 20),
                              color: _muted,
                              tooltip: 'Download dit nummer',
                              onPressed: () => _download(f)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Sluiten')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Collapsed artist bio (3 lines) that opens the full text in a dialog on tap.
class BioText extends StatelessWidget {
  final String artist;
  final String text;
  const BioText(this.artist, this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: _panel,
          title: Text(artist, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Text(text, style: const TextStyle(color: Color(0xFFC7CBDA), fontSize: 13.5, height: 1.5)),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Sluiten'))],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 13, height: 1.45)),
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Text('Lees meer', style: TextStyle(color: _accent, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Stremio-style online browse: artist → albums → tracks → sources ──────────
class ArtistBrowsePage extends StatefulWidget {
  final CatalogArtist artist;
  const ArtistBrowsePage(this.artist, {super.key});
  @override
  State<ArtistBrowsePage> createState() => _ArtistBrowsePageState();
}

class _ArtistBrowsePageState extends State<ArtistBrowsePage> {
  final _catalog = CatalogService();
  List<CatalogAlbum> _albums = [];
  String? _bio;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadBio();
  }

  Future<void> _load() async {
    try {
      final a = await _catalog.artistAlbums(widget.artist.id);
      if (mounted) setState(() { _albums = a; _busy = false; });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadBio() async {
    final enricher = CoverEnricher(context.read<AppSettings>());
    var bio = await enricher.cachedBio(widget.artist.name);
    bio ??= await enricher.fetchArtistBio(widget.artist.name);
    if (mounted && bio != null) setState(() => _bio = bio);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 20, 10),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: 4),
                  _netCover(widget.artist.picture, size: 76, circle: true),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.artist.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(_busy ? 'Albums laden…' : '${_albums.length} albums',
                            style: const TextStyle(color: _muted, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_bio != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: BioText(widget.artist.name, _bio!),
              ),
            ),
          if (_busy)
            const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: _accent))))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: .74),
                delegate: SliverChildBuilderDelegate((_, i) => _albumCard(_albums[i]), childCount: _albums.length),
              ),
            ),
        ],
      ),
    );
  }

  Widget _albumCard(CatalogAlbum al) {
    final sub = [
      if (al.year != null) al.year!,
      if (al.isSingle) 'Single' else if (al.trackCount > 0) '${al.trackCount} nummers',
    ].join(' · ');
    return InkWell(
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AlbumBrowsePage(widget.artist.name, al))),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: LayoutBuilder(builder: (_, c) => _netCover(al.cover, size: c.maxWidth))),
          const SizedBox(height: 6),
          Text(al.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 11)),
        ],
      ),
    );
  }
}

class AlbumBrowsePage extends StatefulWidget {
  final String artistName;
  final CatalogAlbum album;
  const AlbumBrowsePage(this.artistName, this.album, {super.key});
  @override
  State<AlbumBrowsePage> createState() => _AlbumBrowsePageState();
}

class _AlbumBrowsePageState extends State<AlbumBrowsePage> {
  static const _albumLevel = -1;
  final _catalog = CatalogService();
  List<CatalogTrack> _tracks = [];
  bool _busy = true;
  int? _expanded; // track index whose sources are shown; -1 = whole album

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (_, tracks) = await _catalog.albumTracks(widget.album.id);
      if (mounted) setState(() { _tracks = tracks; _busy = false; });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle(int i) => setState(() => _expanded = _expanded == i ? null : i);

  @override
  Widget build(BuildContext context) {
    final al = widget.album;
    return Scaffold(
      backgroundColor: _bg,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 20, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
                const SizedBox(width: 4),
                _netCover(al.cover, size: 128),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      Text(al.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                          '${widget.artistName}${al.year != null ? " · ${al.year}" : ""}${_tracks.isNotEmpty ? " · ${_tracks.length} nummers" : ""}',
                          style: const TextStyle(color: _muted, fontSize: 13)),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: _panel2, foregroundColor: Colors.white),
                        icon: Icon(_expanded == _albumLevel ? Icons.expand_less_rounded : Icons.travel_explore_rounded, size: 18),
                        label: const Text('Bronnen voor album'),
                        onPressed: () => _toggle(_albumLevel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_expanded == _albumLevel)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SourcesView(query: '${widget.artistName} ${al.title}'),
            ),
          if (_busy)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: _accent)))
          else if (_tracks.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('Geen tracklijst gevonden.', style: TextStyle(color: _muted)))
          else
            ..._tracks.asMap().entries.map((e) => _trackRow(e.key, e.value)),
        ],
      ),
    );
  }

  Widget _trackRow(int i, CatalogTrack t) {
    final open = _expanded == i;
    return Column(
      children: [
        InkWell(
          onTap: () => _toggle(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
            color: open ? _panel : Colors.transparent,
            child: Row(
              children: [
                SizedBox(
                    width: 26,
                    child: Text(t.position > 0 ? '${t.position}' : '${i + 1}',
                        style: const TextStyle(color: _muted, fontSize: 13))),
                Expanded(
                    child: Text(t.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                Text(t.durationLabel, style: const TextStyle(color: _muted, fontSize: 12)),
                const SizedBox(width: 10),
                Icon(open ? Icons.expand_less_rounded : Icons.travel_explore_rounded,
                    size: 18, color: open ? _accent : _muted),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SourcesView(query: '${widget.artistName} ${t.title}'),
          ),
      ],
    );
  }
}

// ── Settings dialog ──────────────────────────────────────────────────────────
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});
  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _discogs, _torbox, _slskUser, _slskPass, _lastfm;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppSettings>();
    _discogs = TextEditingController(text: s.discogsToken);
    _torbox = TextEditingController(text: s.torboxToken);
    _slskUser = TextEditingController(text: s.soulseekUser);
    _slskPass = TextEditingController(text: s.soulseekPass);
    _lastfm = TextEditingController(text: s.lastfmKey);
  }

  @override
  void dispose() {
    _discogs.dispose();
    _torbox.dispose();
    _slskUser.dispose();
    _slskPass.dispose();
    _lastfm.dispose();
    super.dispose();
  }

  Widget _field(String label, TextEditingController c, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 12.5)),
          const SizedBox(height: 5),
          TextField(
            controller: c,
            obscureText: obscure,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF14161F),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _line)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _line)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _accent)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 640),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Instellingen', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Sleutels blijven alleen op deze PC.', style: TextStyle(color: _muted, fontSize: 13)),
            const SizedBox(height: 18),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _field('TorBox API-sleutel', _torbox),
                    _field('Discogs token', _discogs),
                    Row(
                      children: [
                        Expanded(child: _field('Soulseek gebruiker', _slskUser)),
                        const SizedBox(width: 12),
                        Expanded(child: _field('Soulseek wachtwoord', _slskPass, obscure: true)),
                      ],
                    ),
                    _field('Last.fm API-sleutel', _lastfm),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuleren')),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _accent),
                  onPressed: () async {
                    final s = context.read<AppSettings>();
                    final lib = context.read<LibraryStore>();
                    s.discogsToken = _discogs.text.trim();
                    s.torboxToken = _torbox.text.trim();
                    s.soulseekUser = _slskUser.text.trim();
                    s.soulseekPass = _slskPass.text.trim();
                    s.lastfmKey = _lastfm.text.trim();
                    await s.save();
                    if (context.mounted) Navigator.pop(context);
                    lib.enrich(s); // pick up covers that need the (new) Discogs token
                  },
                  child: const Text('Opslaan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _fmt(Duration? d) {
  if (d == null) return '0:00';
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
