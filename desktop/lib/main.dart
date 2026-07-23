import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;
// Flutter 3.36+ exports a RepeatMode of its own (for RepeatingAnimationBuilder), which collides
// with the player's. Ours is the one this app means everywhere.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'booklet_view.dart';
import 'catalog.dart';
import 'credits.dart';
import 'discogs.dart';
import 'editions.dart';
import 'connectivity.dart';
import 'enrichment.dart';
import 'lan/sharing.dart';
import 'library.dart';
import 'metadata.dart';
import 'models.dart';
import 'musicbrainz.dart';
import 'online.dart';
import 'organize.dart';
import 'player.dart';
import 'quality.dart';
import 'recommend.dart';
import 'release_format.dart';
import 'rutracker.dart';
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

/// A loopback port this app holds while it runs. Binding it is the lock; connecting to it is how
/// a second copy says "you're already running, come to the front".
const _instancePort = 47821;

/// Claim the single-instance lock, or hand over to the copy that already holds it.
///
/// Two copies means two Soulseek logins on one account, and Soulseek allows exactly one: they kick
/// each other in turn until the account is refused. That has happened here, so a second launch
/// must never become a second login.
Future<bool> _claimSingleInstance() async {
  try {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _instancePort);
    server.listen((s) async {
      s.destroy();
      await windowManager.show();
      await windowManager.focus();
    });
    return true;
  } on SocketException {
    try {
      final s = await Socket.connect(InternetAddress.loopbackIPv4, _instancePort,
          timeout: const Duration(seconds: 2));
      s.destroy();
      return false; // somebody answered — it really is us, already running
    } catch (_) {
      // The port belongs to something else entirely. Refusing to start over that would be worse
      // than the duplicate we're guarding against.
      return true;
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  if (!await _claimSingleInstance()) {
    exit(0);
  }
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
  // Before anything reads it: the download manager captures the root by value, and the LAN
  // server derives every track id from paths relative to it.
  if (settings.musicRoot.trim().isNotEmpty) library.rootPath = settings.musicRoot.trim();
  final online = OnlineService(settings);
  final soulseek = SoulseekService(settings);
  final tidal = TidalService(settings);
  final musicbrainz = MusicBrainzService();
  final player = PlayerStore()
    ..resolver = online.resolveRadio
    ..coverResolver = library.coverForTrack;
  final downloads = DownloadManager(online, soulseek, library.rootPath, () async {
    await library.scan();
    await library.enrich(settings);
  });

  // Share this library with the Mac, the iPad and the Shield. Started before the scan finishes:
  // a device probing /health then gets a real answer straight away, and the catalogue fills in
  // by itself as the scan lands.
  final sharing = LanSharing(library: library, settings: settings);
  unawaited(sharing.applySettings());
  // What plays here counts too: the position and the play count go into the same shared state
  // the iPad and the Shield write to, so carrying on elsewhere works in both directions.
  player.onProgress = (track, position, playing, queue, index) {
    sharing.reportProgress(
        track.path, position, playing, [for (final t in queue) t.path], index);
  };
  player.onPlayed = (track) {
    sharing.reportPlayed(track.path);
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettings>.value(value: settings),
        ChangeNotifierProvider<LibraryStore>.value(value: library),
        ChangeNotifierProvider<PlayerStore>.value(value: player),
        Provider<OnlineService>.value(value: online),
        // One instance for the whole app. The 1100 ms spacing MusicBrainz asks for is held in
        // INSTANCE fields, so two widgets each constructing their own would fire unspaced and
        // earn a 503 — and an album page builds three of these panels side by side.
        Provider<MusicBrainzService>.value(value: musicbrainz),
        Provider<SoulseekService>.value(value: soulseek),
        Provider<TidalService>.value(value: tidal),
        ChangeNotifierProvider<DownloadManager>.value(value: downloads),
        ChangeNotifierProvider<LanSharing>.value(value: sharing),
      ],
      child: const DebridApp(),
    ),
  );
  // Scan, then fill in missing covers + artist photos (cache-first, then web).
  // Wrapped so a scan hiccup can never prevent enrichment from running.
  () async {
    await library.loadCorrections(); // apply manual fixes as tracks are built
    await library.loadHidden(); // keep "removed from library only" tracks out
    await library.loadMerged(); // records the user told us to keep together
    await library.loadArtistArtChoice(); // portraits and backdrops the user picked
    await library.loadStyles(); // what each record sounds like, for discovery
    try {
      await library.scan();
    } catch (_) {}
    await library.enrich(settings);
    // Reopen the last queue where you left off (paused) — covers are loaded by now.
    await player.restore(library.trackByPath);
    // Downloads that were still running when the app (or the PC) went down. After the scan, so
    // anything that did finish is already in the library and won't be fetched twice.
    try {
      await downloads.resumePending();
    } catch (_) {}
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

/// Album ordering options for the Albums view.
enum AlbumSort { titel, artiest, jaarNieuw, jaarOud, toegevoegd }

extension AlbumSortX on AlbumSort {
  String get label => switch (this) {
        AlbumSort.titel => 'Titel (A–Z)',
        AlbumSort.artiest => 'Artiest',
        AlbumSort.jaarNieuw => 'Jaar (nieuw→oud)',
        AlbumSort.jaarOud => 'Jaar (oud→nieuw)',
        AlbumSort.toegevoegd => 'Recent toegevoegd',
      };
}

// ── Home shell ───────────────────────────────────────────────────────────────
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _view = 5; // 0 albums, 1 artists, 2 online, 3 ontdek, 4 tracks, 5 start (default)

  // Library search + quality filter (applies to Albums / Tracks / Artiesten).
  final _searchCtl = TextEditingController();
  String _q = '';
  QFilter _qFilter = QFilter.all;
  AlbumSort _sort = AlbumSort.titel;

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  bool get _searchable => _view == 0 || _view == 1 || _view == 4;

  /// Does this track match the current search box + quality filter?
  bool _matches(Track t) {
    if (!_qFilter.matches(qualityFromFile(
        name: t.title, ext: t.isFlac ? 'flac' : 'mp3', isFlac: t.isFlac, durationSec: t.duration?.inSeconds))) {
      return false;
    }
    if (_q.isEmpty) return true;
    final q = normKey(_q);
    if (normKey(t.title).contains(q) || normKey(t.artist).contains(q) || normKey(t.album).contains(q)) {
      return true;
    }
    // Second pass with punctuation squashed out, so "backstreets back" finds "Backstreet's Back".
    final qs = searchKey(_q);
    if (qs.isEmpty) return false;
    return searchKey(t.title).contains(qs) ||
        searchKey(t.artist).contains(qs) ||
        searchKey(t.album).contains(qs);
  }

  /// Frosted pill that sits at the top of every screen. It really does blur what's behind it —
  /// the ambient glow in [_contentArea] gives the glass something to pick up, so it reads as a
  /// pane of glass rather than a flat rounded box.
  Widget _glassPill({required Widget child}) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: .085),
                    Colors.white.withValues(alpha: .028),
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: .10)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .34),
                    blurRadius: 26,
                    offset: const Offset(0, 9),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      );

  Widget _searchBar() => _glassPill(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtl,
                onChanged: (v) => setState(() => _q = v.trim()),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Zoek in je bibliotheek — artiest, album of nummer…',
                  hintStyle: const TextStyle(color: _muted, fontSize: 13.5),
                  prefixIcon: const Icon(Icons.search_rounded, size: 19, color: _muted),
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 17, color: _muted),
                          tooltip: 'Wissen',
                          onPressed: () => setState(() {
                            _q = '';
                            _searchCtl.clear();
                          }),
                        ),
                  // No box of its own: the pill IS the field's surface.
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(width: 10),
            ...QFilter.values.map((f) {
              final sel = _qFilter == f;
              return Padding(
                padding: const EdgeInsets.only(left: 6),
                // Translucent so the controls sit ON the glass instead of punching holes in it.
                child: ChoiceChip(
                  label: Text(_qFilterLabel(f), style: const TextStyle(fontSize: 12)),
                  selected: sel,
                  onSelected: (_) => setState(() => _qFilter = f),
                  backgroundColor: Colors.white.withValues(alpha: .06),
                  selectedColor: _accent,
                  labelStyle: TextStyle(color: sel ? Colors.white : _muted),
                  side: BorderSide(color: sel ? _accent : Colors.white.withValues(alpha: .12)),
                  shape: const StadiumBorder(),
                  showCheckmark: false,
                ),
              );
            }),
            if (_view == 0) ...[
              const SizedBox(width: 8),
              PopupMenuButton<AlbumSort>(
                tooltip: 'Sorteren',
                initialValue: _sort,
                onSelected: (s) => setState(() => _sort = s),
                color: _panel,
                position: PopupMenuPosition.under,
                itemBuilder: (_) => AlbumSort.values
                    .map((s) => PopupMenuItem(value: s, child: Text(s.label, style: const TextStyle(fontSize: 13))))
                    .toList(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: .12)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.sort_rounded, size: 16, color: _muted),
                    const SizedBox(width: 6),
                    Text(_sort.label, style: const TextStyle(fontSize: 12.5, color: _muted)),
                    const Icon(Icons.arrow_drop_down_rounded, size: 18, color: _muted),
                  ]),
                ),
              ),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _topBar(),
          Expanded(
            child: Column(
              children: [
                if (_searchable) _searchBar(),
                Expanded(child: _content()),
              ],
            ),
          ),
          const PlayerBar(),
        ],
      ),
    );
  }

  /// Brand, the navigation pill bar, and the library count — the old left rail, laid out
  /// horizontally. The soft glow behind it is what the glass has to blur; on a flat panel
  /// frosted glass is indistinguishable from a plain rounded box.
  Widget _topBar() => SizedBox(
        height: 64,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: -150,
              height: 300,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: .75,
                      colors: [_accent.withValues(alpha: .34), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 11, 18, 8),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: const LinearGradient(colors: [_accent, _accent2]),
                    ),
                    child: const Icon(Icons.music_note_rounded, size: 17, color: Colors.white),
                  ),
                  const SizedBox(width: 9),
                  const Text('DebridMusic',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  const Spacer(),
                  Consumer<DownloadManager>(
                    builder: (_, dm, __) => _NavPills(
                      active: _view,
                      onSelect: (i) => setState(() => _view = i),
                      badge: dm.jobs.where((j) => j.busy).length,
                    ),
                  ),
                  const Spacer(),
                  Consumer<LibraryStore>(
                    builder: (_, lib, __) => Text(
                      lib.scanning
                          ? 'Scannen… ${lib.scanned}'
                          : (lib.enriching
                              ? 'Covers ophalen…'
                              : '${lib.albums.length} albums · ${lib.tracks.length} nummers'),
                      style: const TextStyle(color: _muted, fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.settings_rounded, size: 19),
                    color: _muted,
                    tooltip: 'Instellingen',
                    onPressed: () => showDialog(context: context, builder: (_) => const SettingsDialog()),
                  ),
                ],
              ),
            ),
          ],
        ),
      );


  Widget _content() {
    if (_view == 5) return const HomeStartView();
    if (_view == 6) return const DownloadsView();
    if (_view == 2) return const OnlineSearchScreen();
    if (_view == 3) return const OntdekView();
    if (_view == 4) return TracksView(match: _matches, query: _q);
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
        // An album stays in view when any of its tracks matches (so searching an artist or a
        // single song still surfaces the album it lives on).
        final albums = lib.albums.where((a) => a.tracks.any(_matches)).toList();
        if (albums.isEmpty) {
          return Center(
            child: Text('Niets gevonden voor “$_q”.', style: const TextStyle(color: _muted)),
          );
        }
        return _view == 0
            ? AlbumsGrid(albums: _sortAlbums(albums), title: _q.isEmpty ? null : '${albums.length} resultaten')
            : ArtistsView(lib: lib, albums: albums);
      },
    );
  }

  List<Album> _sortAlbums(List<Album> src) {
    final list = [...src];
    switch (_sort) {
      case AlbumSort.titel:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case AlbumSort.artiest:
        list.sort((a, b) {
          final c = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          return c != 0 ? c : (a.year ?? 0).compareTo(b.year ?? 0);
        });
      case AlbumSort.jaarNieuw:
        list.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
      case AlbumSort.jaarOud:
        list.sort((a, b) => (a.year ?? 9999).compareTo(b.year ?? 9999));
      case AlbumSort.toegevoegd:
        list.sort((a, b) => b.addedMs.compareTo(a.addedMs));
    }
    return list;
  }

  String _qFilterLabel(QFilter f) => switch (f) {
        QFilter.all => 'Alles',
        QFilter.lossless => 'Lossless',
        QFilter.hires => 'Hi-Res',
        QFilter.mp3 => 'MP3',
      };
}

// ── Top navigation ───────────────────────────────────────────────────────────
/// The sections, as a row of labels inside one glass bar, with a pill that SLIDES to whichever
/// section you're in.
///
/// Item widths are measured from the text rather than read back after layout, so the pill's
/// geometry is known in the same frame it animates in — no first-frame jump, no post-frame
/// measuring pass. That also means the label's weight must not change between states (only its
/// colour does), or the pill would no longer match what it sits behind.
class _NavPills extends StatefulWidget {
  final int active;
  final ValueChanged<int> onSelect;
  final int badge; // downloads in progress, shown on "Mijn downloads"
  const _NavPills({required this.active, required this.onSelect, required this.badge});

  @override
  State<_NavPills> createState() => _NavPillsState();
}

class _NavPillsState extends State<_NavPills> {
  int? _hover;

  static const _items = <(int, String)>[
    (5, 'Start'),
    (0, 'Albums'),
    (4, 'Tracks'),
    (1, 'Artiesten'),
    (2, 'Online zoeken'),
    (3, 'Ontdek'),
    (6, 'Mijn downloads'),
  ];
  static const _style = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const _padH = 15.0;
  static const _badgeW = 21.0;

  double _width(int i) {
    final tp = TextPainter(
      text: TextSpan(text: _items[i].$2, style: _style),
      textDirection: TextDirection.ltr,
    )..layout();
    final badge = _items[i].$1 == 6 && widget.badge > 0 ? _badgeW : 0.0;
    return tp.width + _padH * 2 + badge;
  }

  @override
  Widget build(BuildContext context) {
    final widths = [for (var i = 0; i < _items.length; i++) _width(i)];
    final offsets = <double>[];
    var total = 0.0;
    for (final w in widths) {
      offsets.add(total);
      total += w;
    }
    final activeIdx = _items.indexWhere((e) => e.$1 == widget.active);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: .085),
                Colors.white.withValues(alpha: .028),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: .10)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: .34), blurRadius: 26, offset: const Offset(0, 9)),
            ],
          ),
          child: SizedBox(
            height: 32,
            width: total,
            child: Stack(
              children: [
                if (activeIdx >= 0)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    left: offsets[activeIdx],
                    width: widths[activeIdx],
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: .17),
                            Colors.white.withValues(alpha: .07),
                          ],
                        ),
                        border: Border.all(color: Colors.white.withValues(alpha: .20)),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      SizedBox(
                        width: widths[i],
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => setState(() => _hover = i),
                          onExit: (_) => setState(() => _hover = _hover == i ? null : _hover),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => widget.onSelect(_items[i].$1),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _items[i].$2,
                                  style: _style.copyWith(
                                    color: _items[i].$1 == widget.active
                                        ? Colors.white
                                        : (_hover == i ? Colors.white70 : _muted),
                                  ),
                                ),
                                if (_items[i].$1 == 6 && widget.badge > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: _accent,
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Text('${widget.badge}',
                                        style: const TextStyle(
                                            fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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
    // Only on the real library view (no search title), the app offers to tidy albums it found to be
    // duplicates of one you already own. It never moves anything on its own — this just opens the
    // dry-run.
    final dupes = title == null ? context.watch<LibraryStore>().duplicates : const <RedundantAlbum>[];
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
          sliver: SliverToBoxAdapter(
            child: Text(title ?? 'Albums',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ),
        ),
        if (dupes.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            sliver: SliverToBoxAdapter(
              child: InkWell(
                onTap: () async {
                  final done = await showDialog<bool>(
                      context: context, builder: (_) => RedundantCleanupDialog(found: dupes));
                  if (done == true && context.mounted) {
                    _srcToast(context, 'Bibliotheek opgeruimd');
                  }
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _accent.withValues(alpha: .4)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.auto_delete_outlined, size: 18, color: _accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        dupes.length == 1
                            ? '1 album is een dubbele van een album dat je al hebt — opruimen?'
                            : '${dupes.length} albums zijn dubbels van albums die je al hebt — opruimen?',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: _muted),
                  ]),
                ),
              ),
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
        // Grows on hover, like the TV app. 1.06 is deliberate: the grid's 20px gap is wider than
        // the ~6px a card gains per side, so a raised card never collides with its neighbours
        // (grid children paint in order, so an overlap would be drawn OVER the raised card).
        child: AnimatedScale(
          scale: _hover ? 1.06 : 1,
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _hover ? _panel2 : _panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _hover ? Colors.white.withValues(alpha: .16) : _line),
              boxShadow: _hover
                  ? [BoxShadow(color: Colors.black.withValues(alpha: .45), blurRadius: 22, offset: const Offset(0, 10))]
                  : const [],
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
              Text(
                  // Six identical "Backstreet Boys" tiles are unusable, however correct the split
                  // is. Naming the pressing is what makes them tellable apart — and choosable.
                  a.edition == null ? a.artist : '${a.artist} · ${a.edition}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Album detail ─────────────────────────────────────────────────────────────
class AlbumDetailPage extends StatefulWidget {
  final Album album;
  const AlbumDetailPage({super.key, required this.album});
  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  late Album album = widget.album;

  // A correction rebuilds the album list into new objects; re-point at the regrouped
  // album (matched by track path) so this page shows the fixed title/artist/cover.
  void _refresh() {
    final paths = widget.album.tracks.map((t) => t.path).toSet();
    for (final a in context.read<LibraryStore>().albums) {
      if (a.tracks.any((t) => paths.contains(t.path))) {
        setState(() => album = a);
        return;
      }
    }
    setState(() {});
  }

  Future<void> _edit() async {
    final changed = await showDialog<bool>(context: context, builder: (_) => MetadataEditor(album));
    if (changed == true && mounted) {
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Metadata bijgewerkt'), duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the library so a delete (or correction) shows up here immediately — _buildAlbums
    // creates NEW Album objects, so holding on to the original would keep showing stale tracks.
    final lib = context.watch<LibraryStore>();
    final paths = album.tracks.map((t) => t.path).toSet();
    Album? fresh;
    for (final a in lib.albums) {
      if (a.tracks.any((t) => paths.contains(t.path))) {
        fresh = a;
        break;
      }
    }
    if (fresh != null) {
      album = fresh;
    } else if (lib.albums.isNotEmpty && !lib.scanning) {
      // Every track of this album is gone — there's nothing left to show.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
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
                  actions: [
                    if (!album.isSingle)
                      IconButton(
                        icon: const Icon(Icons.auto_stories_outlined),
                        tooltip: 'Boekje doorbladeren',
                        onPressed: () {
                          // Read the pinned pressing here, not inside the route: a booklet is
                          // only worth reading if it is the one that came with this record.
                          final pinned = context.read<LibraryStore>().pinnedRelease(album);
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => BookletScreen(
                              artist: album.artist,
                              album: album.title,
                              pinned: pinned,
                              expectedTracks: album.tracks.length,
                            ),
                          ));
                        },
                      ),
                    if (!album.isSingle)
                      IconButton(
                        icon: const Icon(Icons.photo_library_outlined),
                        tooltip: 'Uitgave kiezen — met hoes, achterkant en cd',
                        onPressed: () async {
                          final picked = await showDialog<bool>(
                              context: context, builder: (_) => ReleaseGallery(album));
                          if (picked == true && mounted) _refresh();
                        },
                      ),
                    if (!album.isSingle)
                      IconButton(
                        icon: const Icon(Icons.merge_rounded),
                        tooltip: 'Een ander album hierin samenvoegen',
                        onPressed: () async {
                          final source = await showDialog<Album>(
                              context: context, builder: (_) => PickAlbumDialog(exclude: album));
                          if (source == null || !context.mounted) return;
                          final done = await showDialog<bool>(
                              context: context,
                              builder: (_) => MergeAlbumsDialog(album: album, absorb: source));
                          if (done == true && mounted) _refresh();
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded),
                      tooltip: 'Metadata corrigeren',
                      onPressed: _edit,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: album.isSingle ? 'Nummer verwijderen' : 'Album verwijderen',
                      onPressed: () async {
                        await _confirmDelete(context, '“${album.title}”',
                            album.tracks.map((t) => t.path).toList());
                        if (context.mounted) Navigator.of(context).maybePop();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                SliverToBoxAdapter(child: _header(context)),
                if (!album.isSingle)
                  SliverToBoxAdapter(
                    child: AlbumInfoPanel(
                        artist: album.artist,
                        album: album.title,
                        trackCount: album.tracks.length,
                        pinned: context.watch<LibraryStore>().pinnedRelease(album),
                        pinnedMbid: context.watch<LibraryStore>().pinnedMbid(album)),
                  ),
                if (!album.isSingle)
                  SliverToBoxAdapter(
                    child: CreditsPanel(artist: album.artist, album: album.title),
                  ),
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

  /// Is the track playing right now one of THIS album's? The disc only turns for the record it
  /// belongs to — every sleeve in the library spinning at once would be nonsense.
  bool _albumIsPlaying(BuildContext context) {
    final p = context.watch<PlayerStore>();
    if (!p.playing) return false;
    final now = p.current?.path;
    return now != null && album.tracks.any((t) => t.path == now);
  }

  Widget _header(BuildContext context) {
    final player = context.read<PlayerStore>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AlbumArt(
            artist: album.artist,
            album: album.title,
            size: 200,
            fallback: album.cover,
            chosen: album.correctedCover,
            pinned: context.watch<LibraryStore>().pinnedRelease(album),
            pinnedMbid: context.watch<LibraryStore>().pinnedMbid(album),
            trackCount: album.tracks.length,
            playing: _albumIsPlaying(context),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(album.isSingle ? 'Single' : 'Album', style: const TextStyle(color: _muted)),
                const SizedBox(height: 6),
                Text(album.title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                // The artist is a link: from a record you're holding, the obvious next question is
                // "what else did they make".
                Row(
                  children: [
                    ArtistNames(names: [album.artist], style: const TextStyle(color: _muted)),
                    Text(
                      [
                        '',
                        if (album.year != null) '${album.year}',
                        if (album.genre != null) album.genre!,
                        '${album.tracks.length} nummers',
                      ].join(' · '),
                      style: const TextStyle(color: _muted),
                    ),
                  ],
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
                    // Offered only where there is something to merge: the library holds more than
                    // one pressing of this record, or the user already told us to keep them one.
                    if (album.edition != null || context.watch<LibraryStore>().isMerged(album)) ...[
                      const SizedBox(width: 10),
                      Builder(builder: (context) {
                        final merged = context.watch<LibraryStore>().isMerged(album);
                        return FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _panel2,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          ),
                          onPressed: () {
                            if (merged) {
                              // Splitting moves nothing, so it needs no plan.
                              context.read<LibraryStore>().unmergeEditions(album);
                              _srcToast(context, 'Uitgaves weer apart');
                              return;
                            }
                            // Merging rewrites the folder tree. Show what it would do first.
                            showDialog<bool>(
                                context: context, builder: (_) => MergeAlbumsDialog(album: album));
                          },
                          icon: Icon(merged ? Icons.call_split_rounded : Icons.merge_rounded, size: 20),
                          label: Text(merged ? 'Uitgaves splitsen' : 'Uitgaves samenvoegen'),
                        );
                      }),
                    ],
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

/// Manual metadata editor: search Deezer/Discogs/MusicBrainz for the correct
/// release and apply its cover/artist/title to a wrong album or single.
class MetadataEditor extends StatefulWidget {
  final Album album;
  const MetadataEditor(this.album, {super.key});
  @override
  State<MetadataEditor> createState() => _MetadataEditorState();
}

class _MetadataEditorState extends State<MetadataEditor> {
  late final TextEditingController _artist = TextEditingController(text: widget.album.artist);
  late final TextEditingController _title = TextEditingController(text: widget.album.title);
  late final TextEditingController _query =
      TextEditingController(text: '${widget.album.artist} ${widget.album.title}'.trim());
  String _provider = 'Deezer';
  bool _searching = false;
  bool _applying = false;
  List<MetaResult> _results = const [];
  MetaResult? _picked;

  /// The release id, held separately from [_picked]. Kept apart on purpose: the pin arrived empty
  /// once and everything downstream then silently fell back to guessing, so this no longer depends
  /// on the picked object still being the same instance at apply time.
  int? _pickedRelease;

  /// The MusicBrainz pressing picked, when the answer came from there.
  String? _pickedMbid;
  Uint8List? _pickedCover;

  @override
  void dispose() {
    _artist.dispose();
    _title.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _results = const [];
    });
    final res = await MetadataSearch(context.read<AppSettings>())
        .search(_provider, _query.text, track: widget.album.isSingle);
    if (!mounted) return;
    setState(() {
      _results = res;
      _searching = false;
    });
  }

  Future<void> _pick(MetaResult m) async {
    final newTitle = widget.album.isSingle ? m.title : m.album;
    setState(() {
      _picked = m;
      _pickedRelease = m.releaseId;
      _pickedMbid = m.mbid;
      _pickedCover = null;
      if (m.artist.isNotEmpty) _artist.text = m.artist;
      if (newTitle.isNotEmpty) _title.text = newTitle;
    });
    if (m.coverUrl != null) {
      final bytes = await CoverEnricher(context.read<AppSettings>()).downloadImage(m.coverUrl!);
      if (mounted && identical(_picked, m)) setState(() => _pickedCover = bytes);
    }
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    await context.read<LibraryStore>().applyCorrection(
          widget.album,
          context.read<AppSettings>(),
          artist: _artist.text,
          albumTitle: widget.album.isSingle ? null : _title.text,
          title: widget.album.isSingle ? _title.text : null,
          coverBytes: _pickedCover,
          discogsRelease: _pickedRelease,
          mbid: _pickedMbid,
        );
    // Says out loud what was pinned. The pin went missing twice while every line of the path read
    // correctly, so this is no longer something to reason about — it is something to see.
    if (mounted) {
      _srcToast(
          context,
          _pickedMbid != null
              ? 'Aangepast — MusicBrainz-uitgave vastgezet'
              : _pickedRelease == null
                  ? 'Aangepast — geen uitgave vastgezet'
                  : 'Aangepast — uitgave $_pickedRelease vastgezet');
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isSingle = widget.album.isSingle;
    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 580,
        height: 640,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Metadata corrigeren',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(false)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cover(_pickedCover ?? widget.album.cover, size: 88),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      children: [
                        _field(_artist, 'Artiest'),
                        const SizedBox(height: 8),
                        _field(_title, isSingle ? 'Titel' : 'Album'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _provider,
                        dropdownColor: _panel2,
                        items: MetadataSearch.providers
                            .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                            .toList(),
                        onChanged: (v) => setState(() => _provider = v ?? 'Deezer'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _query,
                      onSubmitted: (_) => _search(),
                      decoration: _inputDeco('Zoeken…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _accent),
                    onPressed: _searching ? null : _search,
                    child: const Text('Zoeken'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _searching
                    ? const Center(child: CircularProgressIndicator(color: _accent))
                    : _results.isEmpty
                        ? const Center(
                            child: Text('Zoek hierboven een correcte versie.',
                                style: TextStyle(color: _muted)))
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (_, i) {
                              final m = _results[i];
                              final sel = identical(_picked, m);
                              return InkWell(
                                onTap: () => _pick(m),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: sel ? _accent.withValues(alpha: 0.18) : _panel2,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: sel ? _accent : Colors.transparent),
                                  ),
                                  child: Row(
                                    children: [
                                      _netCover(m.coverUrl, size: 44, radius: 6),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(m.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w600)),
                                            Text(
                                                // The pressing, where the provider knows it. Five
                                                // rows reading "30 — Adele" give nothing to choose
                                                // between; a format and a catalogue number do.
                                                m.detail ?? (m.artist.isEmpty ? '—' : m.artist),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: _muted, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                      if (sel) const Icon(Icons.check_circle_rounded, color: _accent),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Annuleren', style: TextStyle(color: _muted)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _accent),
                    onPressed: _applying ? null : _apply,
                    child: _applying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Toepassen'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label) => TextField(controller: c, decoration: _inputDeco(label));

  InputDecoration _inputDeco(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _muted),
        isDense: true,
        filled: true,
        fillColor: _panel2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      );
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
                child: Builder(builder: (context) {
                  // Guests named in this track's own tags, shown under the title. No catalogue
                  // lookup here — that would be one network call per row of every album.
                  final guests = splitFeatured(t.artist, t.title).featured;
                  final title = Text(titleWithoutFeat(t.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600, color: isCurrent ? _accent2 : _text));
                  if (guests.isEmpty) return title;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      // Only the guests — the album already belongs to the main artist.
                      ArtistNames(names: guests, style: const TextStyle(color: _muted, fontSize: 11.5)),
                    ],
                  );
                }),
              ),
              _qualityBadge(_trackQuality(t)),
              Text(_fmt(t.duration), style: const TextStyle(color: _muted, fontSize: 13)),
              // Both appear on hover, so neither can be hit by accident.
              SizedBox(
                width: 36,
                child: _hover
                    ? IconButton(
                        icon: const Icon(Icons.drive_file_move_outline, size: 17),
                        color: _muted,
                        tooltip: 'Naar ander album verplaatsen',
                        // A bare icon with no padding is a hit area the size of the glyph — hard to
                        // land on with a mouse, and the row underneath swallows every near miss and
                        // starts playing instead. Give it something to aim at.
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        // The album comes from the library rather than a parameter: every caller
                        // of this row would otherwise have to thread it through.
                        onPressed: () {
                          final from = context.read<LibraryStore>().albumForPath(t.path);
                          if (from == null) return;
                          showDialog<bool>(context: context, builder: (_) => MoveTrackDialog(track: t, from: from));
                        },
                      )
                    : null,
              ),
              SizedBox(
                width: 36,
                child: _hover
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 17),
                        color: _muted,
                        tooltip: 'Nummer verwijderen',
                        // A bare icon with no padding is a hit area the size of the glyph — hard to
                        // land on with a mouse, and the row underneath swallows every near miss and
                        // starts playing instead. Give it something to aim at.
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () => _confirmDelete(context, '“${t.title}”', [t.path]),
                      )
                    : null,
              ),
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

  /// Albums already narrowed by the shell's search/filter (defaults to the whole library).
  final List<Album>? albums;
  const ArtistsView({super.key, required this.lib, this.albums});
  @override
  State<ArtistsView> createState() => _ArtistsViewState();
}

class _ArtistsViewState extends State<ArtistsView> {
  String? _selected;

  List<Album> get _source => widget.albums ?? widget.lib.albums;

  @override
  Widget build(BuildContext context) {
    if (_selected != null) {
      return ArtistDetailView(
        name: _selected!,
        libraryAlbums: _source.where((a) => a.artist == _selected!).toList(),
        onBack: () => setState(() => _selected = null),
        onArtist: (n) => setState(() => _selected = n),
      );
    }
    // Only artists that still have a matching album after the shell's search/filter.
    final visible = {for (final a in _source) a.artist};
    final artists = widget.lib.artists.where(visible.contains).toList();
    if (artists.isEmpty) {
      return const Center(child: Text('Geen artiesten gevonden.', style: TextStyle(color: _muted)));
    }
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
          sliver: SliverToBoxAdapter(
            child: Text('Artiesten${artists.length == widget.lib.artists.length ? "" : " · ${artists.length}"}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
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
                  _source.firstWhere((a) => a.artist == name).cover;
              return _ArtistCard(
                name: name,
                image: art,
                onTap: () => setState(() => _selected = name),
              );
            }, childCount: artists.length),
          ),
        ),
      ],
    );
  }
}

/// Who made this record. Names are links wherever there is something behind them, which is the
/// thread Roon pulls: from a record you like, to the producer, to everything else they touched.
class CreditsPanel extends StatefulWidget {
  final String artist, album;
  const CreditsPanel({super.key, required this.artist, required this.album});

  @override
  State<CreditsPanel> createState() => _CreditsPanelState();
}

class _CreditsPanelState extends State<CreditsPanel> {
  List<Credit> _credits = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CreditsPanel old) {
    super.didUpdateWidget(old);
    if (old.artist != widget.artist || old.album != widget.album) {
      setState(() => _credits = const []);
      _load();
    }
  }

  Future<void> _load() async {
    final artist = widget.artist, album = widget.album;
    final c = await CreditsService(context.read<AppSettings>()).forAlbum(artist, album);
    if (!mounted || artist != widget.artist || album != widget.album) return;
    setState(() => _credits = c);
  }

  @override
  Widget build(BuildContext context) {
    if (_credits.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CREDITS',
              style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final c in _credits.take(14))
                _CreditChip(credit: c),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreditChip extends StatefulWidget {
  final Credit credit;
  const _CreditChip({required this.credit});

  @override
  State<_CreditChip> createState() => _CreditChipState();
}

class _CreditChipState extends State<_CreditChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => PersonPage(widget.credit.name, role: widget.credit.role))),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: _hover ? _panel2 : _panel,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _hover ? Colors.white.withValues(alpha: .18) : _line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.credit.role,
                  style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(width: 7),
              Text(widget.credit.name,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: _hover ? Colors.white : null)),
            ],
          ),
        ),
      ),
    );
  }
}

/// What one person made. Reached by tapping a credit; a name with nothing behind it says so
/// plainly rather than showing an empty page.
class PersonPage extends StatefulWidget {
  final String name;
  final String? role;
  const PersonPage(this.name, {super.key, this.role});

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  List<CreditedWork> _works = const [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await CreditsService(context.read<AppSettings>()).producedBy(widget.name);
    if (!mounted) return;
    setState(() {
      _works = w;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: ArtistBackdrop(
        name: widget.name,
        child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                ArtistHero(
                  name: widget.name,
                  ownBackdrop: false,
                  subtitle: widget.role == null ? null : '${widget.role} · ${_works.length} producties',
                  actions: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
                      onPressed: () => openArtist(context, widget.name),
                      icon: const Icon(Icons.person_rounded, size: 18),
                      label: const Text('Als artiest'),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 0, 0),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
          if (_busy)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: _accent)),
              ),
            )
          else if (_works.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Text('Geen verdere producties gevonden voor deze naam.',
                    style: TextStyle(color: _muted)),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
                child: Text('Werkte mee aan  ${_works.length}',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final w = _works[i];
                  return ListTile(
                    title: Text(w.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: w.year == null ? null : Text(w.year!, style: const TextStyle(color: _muted, fontSize: 12)),
                    trailing: const Icon(Icons.search_rounded, size: 17, color: _muted),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: _bg,
                        appBar: AppBar(backgroundColor: _bg, title: Text(w.title)),
                        body: SingleChildScrollView(child: SourcesView(query: '${widget.name} ${w.title}')),
                      ),
                    )),
                  );
                },
                childCount: _works.length,
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
        ),
      ),
    );
  }
}

/// Everything about one artist on a single page: what you own, their whole catalogue with the
/// gaps visible, who they sound like, and who worked on the records.
///
/// The split is the point — "in mijn bibliotheek" answers "what can I play", "discografie"
/// answers "what else is there", and a release you already own is marked as such so the gap in a
/// collection is obvious at a glance.
class ArtistDetailView extends StatefulWidget {
  final String name;
  final List<Album> libraryAlbums;
  final VoidCallback onBack;
  final void Function(String name)? onArtist;
  const ArtistDetailView({
    super.key,
    required this.name,
    required this.libraryAlbums,
    required this.onBack,
    this.onArtist,
  });

  @override
  State<ArtistDetailView> createState() => _ArtistDetailViewState();
}

class _ArtistDetailViewState extends State<ArtistDetailView> {
  final _catalog = CatalogService();
  List<CatalogAlbum> _discography = [];
  List<CatalogArtist> _related = [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ArtistDetailView old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name) {
      setState(() {
        _discography = [];
        _related = [];
        _busy = true;
      });
      _load();
    }
  }

  Future<void> _load() async {
    final name = widget.name;
    try {
      final hits = await _catalog.searchArtists(name);
      if (hits.isEmpty) {
        if (mounted && name == widget.name) setState(() => _busy = false);
        return;
      }
      final id = hits.first.id;
      final albums = await _catalog.artistAlbums(id);
      final related = await _catalog.relatedArtists(id);
      if (!mounted || name != widget.name) return;
      setState(() {
        _discography = albums;
        _related = related;
        _busy = false;
      });
    } catch (_) {
      if (mounted && name == widget.name) setState(() => _busy = false);
    }
  }

  /// The library album matching a catalogue release, if you own it.
  Album? _owned(CatalogAlbum a) {
    final key = normKey(a.title);
    for (final l in widget.libraryAlbums) {
      if (normKey(l.title) == key) return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final trackCount = widget.libraryAlbums.fold<int>(0, (s, a) => s + a.tracks.length);
    final bio = lib.artistBios[widget.name];

    // Split the way a discography is actually read: the records first, the odds and ends after.
    final main = _discography.where((a) => a.recordType == 'album').toList();
    final rest = _discography.where((a) => a.recordType != 'album').toList();

    return ArtistBackdrop(
      name: widget.name,
      fallbackImage: lib.artistImages[widget.name],
      child: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Stack(
            children: [
              ArtistHero(
                name: widget.name,
                ownBackdrop: false,
                subtitle: '${widget.libraryAlbums.length} albums · $trackCount nummers in je bibliotheek',
                fallbackImage: lib.artistImages[widget.name],
                actions: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
                    onPressed: () => startRadio(context, widget.name),
                    icon: const Icon(Icons.radio_rounded, size: 18),
                    label: const Text('Radio'),
                  ),
                  const SizedBox(width: 10),
                  // The app guesses portrait-vs-backdrop from the shape of a picture; a guess is
                  // exactly the thing worth being able to overrule.
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: _panel2,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                    onPressed: () =>
                        showDialog<void>(context: context, builder: (_) => ArtistArtGallery(widget.name)),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Foto kiezen'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 0, 0),
                child: TextButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Artiesten'),
                ),
              ),
            ],
          ),
        ),
        if (bio != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
              child: BioText(widget.name, bio),
            ),
          ),
        _header('In mijn bibliotheek', '${widget.libraryAlbums.length}'),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190, mainAxisSpacing: 20, crossAxisSpacing: 20, childAspectRatio: .78),
            delegate: SliverChildBuilderDelegate(
              (_, i) => AlbumCard(album: widget.libraryAlbums[i]),
              childCount: widget.libraryAlbums.length,
            ),
          ),
        ),
        if (_busy)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2.4)),
            ),
          ),
        if (main.isNotEmpty) ...[
          _header('Discografie', '${main.length} albums'),
          _discoGrid(main),
        ],
        if (rest.isNotEmpty) ...[
          _header('Singles & EP’s', '${rest.length}'),
          _discoGrid(rest),
        ],
        if (_related.isNotEmpty) ...[
          _header('Klinkt als', '${_related.length}'),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 176,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _related.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) {
                  final r = _related[i];
                  return _RelatedArtistCard(
                    artist: r,
                    inLibrary: lib.hasArtist(r.name),
                    onTap: () {
                      // Someone you already own opens your own page; anyone else opens theirs.
                      if (lib.hasArtist(r.name) && widget.onArtist != null) {
                        widget.onArtist!(lib.displayArtist(r.name));
                      } else {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtistBrowsePage(r)));
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
      ),
    );
  }

  Widget _header(String title, String badge) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
          child: Row(
            children: [
              Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Text(badge, style: const TextStyle(color: _muted, fontSize: 12.5)),
            ],
          ),
        ),
      );

  Widget _discoGrid(List<CatalogAlbum> items) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190, mainAxisSpacing: 20, crossAxisSpacing: 20, childAspectRatio: .78),
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final a = items[i];
              final owned = _owned(a);
              return _DiscoCard(
                album: a,
                artist: widget.name,
                owned: owned,
              );
            },
            childCount: items.length,
          ),
        ),
      );
}

/// A release from the catalogue, marked with whether it's already on your shelf.
class _DiscoCard extends StatefulWidget {
  final CatalogAlbum album;
  final String artist;
  final Album? owned;
  const _DiscoCard({required this.album, required this.artist, this.owned});

  @override
  State<_DiscoCard> createState() => _DiscoCardState();
}

class _DiscoCardState extends State<_DiscoCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.album;
    final have = widget.owned != null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => have
              ? AlbumDetailPage(album: widget.owned!)
              : AlbumBrowsePage(widget.artist, a),
        )),
        child: AnimatedScale(
          scale: _hover ? 1.06 : 1,
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _hover ? _panel2 : _panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: have ? _accent2.withValues(alpha: .45) : _line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, c) => Stack(
                      children: [
                        _netCover(a.cover, size: c.maxWidth),
                        if (have)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(color: _accent2, shape: BoxShape.circle),
                              child: const Icon(Icons.check_rounded, size: 13, color: Colors.black),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Text(a.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                Text(
                  have ? 'in je bibliotheek' : (a.year ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: have ? _accent2 : _muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A "sounds like" artist, flagged when you already own something of theirs.
class _RelatedArtistCard extends StatefulWidget {
  final CatalogArtist artist;
  final bool inLibrary;
  final VoidCallback onTap;
  const _RelatedArtistCard({required this.artist, required this.inLibrary, required this.onTap});

  @override
  State<_RelatedArtistCard> createState() => _RelatedArtistCardState();
}

class _RelatedArtistCardState extends State<_RelatedArtistCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 118,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hover ? 1.06 : 1,
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOut,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    _netCover(widget.artist.picture, size: 118, circle: true),
                    if (widget.inLibrary)
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: _accent2, shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded, size: 12, color: Colors.black),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(widget.artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12.5, color: _hover ? Colors.white : null)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An artist in the grid. Grows on hover like the album cards, so both grids behave the same.
class _ArtistCard extends StatefulWidget {
  final String name;
  final Uint8List? image;
  final VoidCallback onTap;
  const _ArtistCard({required this.name, required this.image, required this.onTap});

  @override
  State<_ArtistCard> createState() => _ArtistCardState();
}

class _ArtistCardState extends State<_ArtistCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover ? 1.06 : 1,
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (_, c) => AnimatedContainer(
                    duration: const Duration(milliseconds: 170),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: _hover
                          ? [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: .45),
                                  blurRadius: 22,
                                  offset: const Offset(0, 10))
                            ]
                          : const [],
                    ),
                    child: cover(widget.image, size: c.maxWidth, circle: true),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _hover ? Colors.white : null)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Artist credits ───────────────────────────────────────────────────────────
/// Open an artist's discography. Goes to the catalogue rather than your own shelf on purpose:
/// a guest like Beyoncé usually isn't in your library at all, and even for an artist you do own
/// the interesting thing here is their whole catalogue — that's what tapping a name promises.
Future<void> openArtist(BuildContext context, String name) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final hits = await CatalogService().searchArtists(name);
  if (hits.isEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text('Geen artiestenpagina gevonden voor $name'), duration: const Duration(seconds: 2)),
    );
    return;
  }
  // Prefer an exact name match over the first (fuzzy) hit.
  final artist = hits.firstWhere((a) => artistKey(a.name) == artistKey(name), orElse: () => hits.first);
  navigator.push(MaterialPageRoute(builder: (_) => ArtistBrowsePage(artist)));
}

/// "Lady Gaga · Beyoncé" — every name tappable.
///
/// The guest credit lives wherever the ripper put it: the artist tag, the title, or — for the
/// Lady Gaga file on this machine — nowhere at all. So when the tags name nobody and [lookup] is
/// on, the catalogue is asked who else played on it.
class ArtistLine extends StatefulWidget {
  final String artist;
  final String title;
  final TextStyle style;
  final bool lookup;
  const ArtistLine({
    super.key,
    required this.artist,
    required this.title,
    required this.style,
    this.lookup = false,
  });

  @override
  State<ArtistLine> createState() => _ArtistLineState();
}

class _ArtistLineState extends State<ArtistLine> {
  List<String> _extra = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(ArtistLine old) {
    super.didUpdateWidget(old);
    if (old.artist != widget.artist || old.title != widget.title) {
      setState(() => _extra = const []);
      _fetch();
    }
  }

  Future<void> _fetch() async {
    if (!widget.lookup) return;
    final local = splitFeatured(widget.artist, widget.title);
    if (local.featured.isNotEmpty) return; // the tags already say who's on it
    final artist = widget.artist, title = widget.title;
    final names = await CatalogService().trackContributors(artist, titleWithoutFeat(title));
    if (!mounted || artist != widget.artist || title != widget.title) return;
    final guests = names.where((n) => artistKey(n) != artistKey(local.main)).toList();
    if (guests.isNotEmpty) setState(() => _extra = guests);
  }

  @override
  Widget build(BuildContext context) {
    final split = splitFeatured(widget.artist, widget.title);
    final lib = context.watch<LibraryStore>();
    return ArtistNames(
      names: [lib.displayArtist(split.main), ...split.featured, ..._extra],
      style: widget.style,
    );
  }
}

/// A row of artist names, each tappable. Takes the names as-is — the caller decides who's on it.
class ArtistNames extends StatefulWidget {
  final List<String> names;
  final TextStyle style;
  const ArtistNames({super.key, required this.names, required this.style});

  @override
  State<ArtistNames> createState() => _ArtistNamesState();
}

class _ArtistNamesState extends State<ArtistNames> {
  String? _hover;

  @override
  Widget build(BuildContext context) {
    final names = widget.names;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < names.length; i++) ...[
          if (i > 0)
            Text(' · ', style: widget.style.copyWith(color: widget.style.color?.withValues(alpha: .5))),
          Flexible(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = names[i]),
              onExit: (_) => setState(() => _hover = _hover == names[i] ? null : _hover),
              child: GestureDetector(
                onTap: () => openArtist(context, names[i]),
                child: Text(
                  names[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _hover == names[i]
                      ? widget.style.copyWith(color: Colors.white, decoration: TextDecoration.underline)
                      : widget.style,
                ),
              ),
            ),
          ),
        ],
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(t?.title ?? '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          // What quality am I actually hearing? (local files only — a streamed
                          // source's real quality isn't known here.)
                          if (t != null && t.sizeBytes > 0) _qualityBadge(_trackQuality(t)),
                        ],
                      ),
                      if (p.radioMode && p.radioStatus.isNotEmpty)
                        Text(p.radioStatus,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _accent2, fontSize: 12.5))
                      else if (t == null)
                        const Text('Niets aan het spelen',
                            style: TextStyle(color: _muted, fontSize: 12.5))
                      else
                        // Everyone on the track, each name tappable — a guest artist is exactly
                        // who you want to look up while their verse is playing.
                        ArtistLine(
                          artist: t.artist,
                          title: t.title,
                          lookup: true,
                          style: const TextStyle(color: _muted, fontSize: 12.5),
                        ),
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
                      // Same sleeve-and-disc as the album page, at the size this screen deserves.
                      // The album is taken from the track that is playing, so the disc that comes
                      // out is the one this song is actually on.
                      child: t == null
                          ? cover(p.currentCover, size: 360, radius: 16)
                          : Builder(builder: (context) {
                              // Ask the library which album this track is on, rather than resolving
                              // the record again from its artist and title. Without it this screen
                              // did its own Discogs lookup and showed a different artist's album
                              // that shared a title, while the album page had the right one pinned.
                              final lib = context.watch<LibraryStore>();
                              final al = lib.albumForPath(t.path);
                              return AlbumArt(
                                artist: al?.artist ?? t.artist,
                                album: al?.title ?? t.album,
                                size: 360,
                                fallback: p.currentCover,
                                chosen: al?.correctedCover,
                                trackCount: al?.tracks.length ?? 0,
                                pinned: al == null ? null : lib.pinnedRelease(al),
                                pinnedMbid: al == null ? null : lib.pinnedMbid(al),
                                playing: p.playing,
                              );
                            }),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Text(t?.title ?? '—',
                    style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (t != null)
                      ArtistLine(
                        artist: t.artist,
                        title: t.title,
                        lookup: true,
                        style: const TextStyle(color: _muted, fontSize: 15),
                      ),
                    if (t != null && t.sizeBytes > 0) _qualityBadge(_trackQuality(t)),
                  ],
                ),
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
  // Drop version/edition suffixes — "(2012 Remaster)", "[Live]", "- Single Version" —
  // so a clean library file matches a Deezer title that carries them (and vice-versa).
  x = x.replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ');
  final f = x.indexOf(' feat');
  if (f > 0) x = x.substring(0, f);
  return x.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// Build a Radio queue around [artist]: Deezer recommendations, matched against the
/// local library (owned tracks play instantly; the rest resolve via TorBox on demand).
List<RadioItem> _radioItemsFor(List<RecTrack> recs, LibraryStore lib) {
  final index = <String, Track>{};
  for (final t in lib.tracks) {
    index.putIfAbsent('${_radioNorm(t.artist)}|${_radioNorm(t.title)}', () => t);
  }
  return recs
      .map((r) => RadioItem(
            artist: r.artist,
            title: r.title,
            local: index['${_radioNorm(r.artist)}|${_radioNorm(r.title)}'],
          ))
      .toList();
}

/// Library-forward ordering for Smart Shuffle: play mostly tracks the listener already
/// owns (instant, gap-free) with online discovery sprinkled in (~2 owned : 1 online).
/// Starts on an owned track so there's no first-track sourcing wait, and never leaves a
/// long silent stretch churning through uncached online tracks. If the seed yields no
/// owned tracks (e.g. a discovery seed), the mix is returned unchanged (all discovery).
List<RadioItem> _smartShuffle(List<RadioItem> items) {
  final owned = items.where((i) => i.isLocal).toList();
  final online = items.where((i) => !i.isLocal).toList();
  if (owned.isEmpty || online.isEmpty) return items;
  final out = <RadioItem>[];
  var oi = 0, ni = 0;
  while (oi < owned.length || ni < online.length) {
    if (oi < owned.length) out.add(owned[oi++]);
    if (oi < owned.length) out.add(owned[oi++]);
    if (ni < online.length) out.add(online[ni++]);
  }
  return out;
}

Future<void> startRadio(BuildContext context, String artist) async {
  final player = context.read<PlayerStore>();
  final lib = context.read<LibraryStore>();
  _srcToast(context, '📻 Radio starten voor $artist…');
  final rec = RecommendService();
  List<RecTrack> recs;
  try {
    recs = await rec.mixRadio(artist);
  } catch (_) {
    recs = const [];
  }
  if (!context.mounted) return;
  if (recs.isEmpty) {
    _srcToast(context, 'Geen radio gevonden voor $artist.');
    return;
  }
  // Library-forward smart shuffle: lead with owned tracks (instant), mix in discovery.
  final items = _smartShuffle(_radioItemsFor(recs, lib));
  // Keep it endless: fetch a fresh (also library-forward) batch when the queue runs low.
  player.radioExtend = () async {
    try {
      return _smartShuffle(_radioItemsFor(await rec.mixRadio(artist), lib));
    } catch (_) {
      return <RadioItem>[];
    }
  };
  await player.playRadio(items);
}

bool _genericArtist(String s) {
  final x = s.trim().toLowerCase();
  return x.isEmpty || x == 'various' || x == 'various artists' || x == 'va' || x == 'onbekende artiest';
}

// ── Tracks (flat, all library songs) ─────────────────────────────────────────
class TracksView extends StatelessWidget {
  /// Library search + quality filter from the shell (null = show everything).
  final bool Function(Track)? match;
  final String query;
  const TracksView({super.key, this.match, this.query = ''});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final player = context.watch<PlayerStore>();
    final all = lib.tracks;
    final tracks = match == null ? all : all.where(match!).toList();
    if (lib.scanning && all.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (all.isEmpty) {
      return const Center(child: Text('Geen tracks gevonden.', style: TextStyle(color: _muted)));
    }
    if (tracks.isEmpty) {
      return Center(
        child: Text(query.isEmpty ? 'Niets binnen dit filter.' : 'Niets gevonden voor “$query”.',
            style: const TextStyle(color: _muted)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 24, 10),
          child: Row(
            children: [
              const Text('Tracks', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Text('${tracks.length}', style: const TextStyle(color: _muted, fontSize: 14)),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
                onPressed: () => player.shuffleAll(tracks),
                icon: const Icon(Icons.shuffle_rounded, size: 18),
                label: const Text('Shuffle alles'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: _panel2,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                onPressed: () => player.playQueue(tracks, 0),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Speel alles'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: tracks.length,
            itemExtent: 56, // fixed height → smooth scrolling at 10k+ tracks
            itemBuilder: (_, i) {
              final t = tracks[i];
              final isCurrent = !player.radioMode && player.current?.path == t.path;
              return InkWell(
                onTap: () => player.playQueue(tracks, i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  color: isCurrent ? _panel : Colors.transparent,
                  child: Row(
                    children: [
                      SizedBox(width: 22, child: Text('${i + 1}', style: const TextStyle(color: _muted, fontSize: 11))),
                      cover(lib.coverForTrack(t), size: 40, radius: 6),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isCurrent ? _accent : _text)),
                            // Through displayArtist: the track's own tag may spell the artist
                            // differently from the name shown everywhere else.
                            Text(lib.displayArtist(t.artist),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: _muted)),
                          ],
                        ),
                      ),
                      _qualityBadge(_trackQuality(t)),
                      const SizedBox(width: 4),
                      Text(_fmt(t.duration), style: const TextStyle(color: _muted, fontSize: 12)),
                      const SizedBox(width: 10),
                      Icon(isCurrent && player.playing ? Icons.volume_up_rounded : Icons.play_arrow_rounded,
                          color: isCurrent ? _accent : _muted, size: 19),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Ontdek (discovery feed) ──────────────────────────────────────────────────
// ── Start / welcome screen (TIDAL-style rows) ────────────────────────────────
class HomeStartView extends StatefulWidget {
  const HomeStartView({super.key});
  @override
  State<HomeStartView> createState() => _HomeStartViewState();
}

class _HomeStartViewState extends State<HomeStartView> {
  final _catalog = CatalogService();
  final _rec = RecommendService();
  List<CatalogAlbumHit> _charts = [];
  List<CatalogAlbumHit> _releases = [];
  List<RecTrack> _forYou = [];
  bool _chartsLoading = true;
  bool _seedsRequested = false; // the library's artists have been used to load the personal rows
  bool _seedsLoading = false;

  @override
  void initState() {
    super.initState();
    // Charts need no library — load them right away.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCharts());
  }

  Future<void> _loadCharts() async {
    try {
      final c = await _catalog.chartAlbums();
      if (mounted) setState(() => _charts = c);
    } catch (_) {}
    if (mounted) setState(() => _chartsLoading = false);
  }

  /// The personal rows depend on the scanned library. On a cold start the scan is still running
  /// when this view first builds, so we load these ONCE the library actually has artists (driven
  /// from build via context.watch) — not eagerly with an empty seed list.
  Future<void> _loadSeeds(List<String> seeds) async {
    if (mounted) setState(() => _seedsLoading = true);
    final relF = _catalog.latestFromArtists(seeds);
    final fyF = _rec.discover(seeds.take(6).toList());
    List<CatalogAlbumHit> rel = [];
    List<RecTrack> fy = [];
    try {
      rel = await relF;
    } catch (_) {}
    try {
      fy = await fyF;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _releases = rel;
      _forYou = fy;
      _seedsLoading = false;
    });
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return 'Goedenacht';
    if (h < 12) return 'Goedemorgen';
    if (h < 18) return 'Goedemiddag';
    return 'Goedenavond';
  }

  Future<void> _playRec(RecTrack t) async {
    final online = context.read<OnlineService>();
    final player = context.read<PlayerStore>();
    _srcToast(context, 'Bron voorbereiden voor ${t.title}…');
    try {
      final url = await online.resolveRadio(t.artist, t.title, instantOnly: false);
      if (!mounted) return;
      if (url == null) {
        _srcToast(context, 'Geen bron gevonden — zoek het op via Online zoeken.');
        return;
      }
      player.playUrl(url, title: t.title, artist: t.artist);
    } catch (_) {
      if (mounted) _srcToast(context, 'Kan niet afspelen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final artists = lib.artists.where((a) => !_genericArtist(a)).toList();
    // Fire the personal rows the first time the library actually has artists.
    if (!_seedsRequested && artists.isNotEmpty) {
      _seedsRequested = true;
      final seeds = [...artists]..shuffle();
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSeeds(seeds));
    }
    final recent = [...lib.albums.where((a) => a.addedMs > 0)]..sort((a, b) => b.addedMs.compareTo(a.addedMs));
    final anyLoading = _chartsLoading || _seedsLoading || (!_seedsRequested && lib.scanning);
    // New releases by artists you own lead the hero; the global chart fills in until those are
    // loaded (or if you have no library yet), so the top of the page is never an empty band.
    final hero = _releases.isNotEmpty ? _releases : _charts;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 2),
          child: Text('${_greeting()} 👋', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 0, 28, 6),
          child: Text('Ontdek nieuwe muziek en pak op waar je gebleven was',
              style: TextStyle(color: _muted, fontSize: 13.5)),
        ),
        if (hero.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 4),
            child: HeroCarousel(hits: hero.take(7).toList()),
          ),
        if (recent.isNotEmpty) _section('Recent toegevoegd', _localRow(recent.take(15).toList())),
        if (_forYou.isNotEmpty || _seedsLoading)
          _section('Aanbevolen voor jou',
              _forYou.isEmpty ? _loadingRow() : _recRow(_forYou.take(15).toList())),
        if (_charts.isNotEmpty || _chartsLoading)
          _section('Top van dit moment',
              _charts.isEmpty ? _loadingRow() : _catalogRow(_charts.take(20).toList())),
        if (_releases.isNotEmpty || _seedsLoading)
          _section('Nieuw van jouw artiesten',
              _releases.isEmpty ? _loadingRow() : _catalogRow(_releases.take(20).toList())),
        if (!anyLoading && _charts.isEmpty && _releases.isEmpty && _forYou.isEmpty && recent.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 40, 28, 0),
            child: Text('Nog niks om te tonen — download wat muziek of ga naar Online zoeken.',
                style: TextStyle(color: _muted)),
          ),
      ],
    );
  }

  Widget _section(String title, Widget row) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 12),
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          // Taller than the tile itself: a horizontal ListView gives its children a TIGHT height
          // and clips them, so without slack the hover growth would be sliced off top and bottom.
          SizedBox(height: 204, child: row),
        ],
      );

  Widget _loadingRow() => const Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2.4));

  Widget _localRow(List<Album> albums) => ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: albums.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _card(
            cover(albums[i].cover, size: 140), albums[i].title, albums[i].artist,
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AlbumDetailPage(album: albums[i])))),
      );

  Widget _catalogRow(List<CatalogAlbumHit> hits) => ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: hits.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _card(
            _netCover(hits[i].album.cover, size: 140), hits[i].album.title, hits[i].artist,
            () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => AlbumBrowsePage(hits[i].artist, hits[i].album)))),
      );

  Widget _recRow(List<RecTrack> ts) => ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: ts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _card(_netCover(ts[i].cover, size: 140), ts[i].title, ts[i].artist, () => _playRec(ts[i])),
      );

  Widget _card(Widget art, String title, String subtitle, VoidCallback onTap) =>
      _HoverCard(art: art, title: title, subtitle: subtitle, onTap: onTap);
}

/// A tile in one of the home rows. Same hover growth as the album and artist grids, so the whole
/// app responds the same way to the pointer.
class _HoverCard extends StatefulWidget {
  final Widget art;
  final String title, subtitle;
  final VoidCallback onTap;
  const _HoverCard({required this.art, required this.title, required this.subtitle, required this.onTap});

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hover ? 1.06 : 1,
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOut,
            // min + centred: the row hands out a tight height, and a Column that fills it would
            // scale past the row's edges and get clipped.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: _hover
                        ? [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: .45),
                                blurRadius: 22,
                                offset: const Offset(0, 10))
                          ]
                        : const [],
                  ),
                  child: widget.art,
                ),
                const SizedBox(height: 8),
                Text(widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5, color: _hover ? Colors.white : null)),
                Text(widget.subtitle,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OntdekView extends StatefulWidget {
  const OntdekView({super.key});
  @override
  State<OntdekView> createState() => _OntdekViewState();
}

class _OntdekViewState extends State<OntdekView> {
  final _rec = RecommendService();
  List<RecTrack> _tracks = [];
  bool _busy = false;
  String? _status;
  int? _expanded;
  int? _playing; // row whose source is being resolved (shows a spinner)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final lib = context.read<LibraryStore>();
    final seeds = lib.artists.where((a) => !_genericArtist(a)).toList()..shuffle();
    if (seeds.isEmpty) {
      setState(() => _status = 'Nog geen bibliotheek om op te ontdekken.');
      return;
    }
    setState(() {
      _busy = true;
      _tracks = [];
      _status = null;
      _expanded = null;
    });
    final owned = <String>{};
    for (final t in lib.tracks) {
      owned.add('${_radioNorm(t.artist)}|${_radioNorm(t.title)}');
    }
    List<RecTrack> recs;
    try {
      recs = await _rec.discover(seeds.take(4).toList());
    } catch (_) {
      recs = const [];
    }
    final fresh = recs
        .where((r) => !owned.contains('${_radioNorm(r.artist)}|${_radioNorm(r.title)}'))
        .toList();
    if (mounted) {
      setState(() {
        _tracks = fresh;
        _busy = false;
        _status = fresh.isEmpty ? 'Niets nieuws gevonden — ververs eens.' : null;
      });
    }
  }

  Future<void> _play(int i, RecTrack t) async {
    final online = context.read<OnlineService>();
    final player = context.read<PlayerStore>();
    setState(() => _playing = i);
    _srcToast(context, 'Bron voorbereiden voor ${t.title}…');
    try {
      final url = await online.resolveRadio(t.artist, t.title, instantOnly: false);
      if (!mounted) return;
      if (url == null) {
        _srcToast(context, 'Geen bron gevonden — open de bronnen (⬇) om te downloaden.');
        return;
      }
      player.playUrl(url, title: t.title, artist: t.artist);
    } catch (e) {
      if (mounted) _srcToast(context, 'Kan niet afspelen: $e');
    } finally {
      if (mounted) setState(() => _playing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
          child: Row(
            children: [
              const Text('Ontdek', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              const Expanded(
                  child: Text('Nieuwe muziek op basis van je bibliotheek',
                      style: TextStyle(color: _muted, fontSize: 13))),
              IconButton(
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                  color: _muted,
                  tooltip: 'Ververs'),
            ],
          ),
        ),
        if (_status != null)
          Padding(padding: const EdgeInsets.all(24), child: Text(_status!, style: const TextStyle(color: _muted))),
        if (_busy)
          const Expanded(child: Center(child: CircularProgressIndicator(color: _accent)))
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: _tracks.length,
              itemBuilder: (_, i) => _row(i, _tracks[i]),
            ),
          ),
      ],
    );
  }

  Widget _row(int i, RecTrack t) {
    final open = _expanded == i;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: open ? _panel : Colors.transparent, borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              _netCover(t.cover, size: 44, radius: 6),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12)),
                  ],
                ),
              ),
              _playing == i
                  ? const SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _accent))))
                  : IconButton(icon: const Icon(Icons.play_arrow_rounded), color: _accent, tooltip: 'Afspelen', onPressed: () => _play(i, t)),
              IconButton(icon: const Icon(Icons.radio_rounded, size: 20), color: _muted, tooltip: 'Radio hieruit', onPressed: () => startRadio(context, t.artist)),
              IconButton(
                  icon: Icon(open ? Icons.expand_less_rounded : Icons.download_rounded, size: 20),
                  color: _muted,
                  tooltip: 'Bronnen / download',
                  onPressed: () => setState(() => _expanded = open ? null : i)),
            ],
          ),
        ),
        if (open) Padding(padding: const EdgeInsets.only(bottom: 8), child: SourcesView(query: t.query)),
      ],
    );
  }
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

void _downloadTorrent(BuildContext context, SearchResult r) {
  context.read<DownloadManager>().enqueue(r);
  _srcToast(context, r.cached
      ? 'Downloaden gestart — zie de downloadlijst.'
      : 'Voorbereiden bij TorBox (kan even duren bij weinig seeders) — zie de downloadlijst.');
}

void _pickTorrentTracks(BuildContext context, SearchResult r) {
  showDialog(context: context, builder: (_) => _TrackPickerDialog(r));
}

/// Every peer in [all] offering the same track as [f] (including f itself), best-first.
/// The rule itself lives in organize.dart, where it can be tested without a live peer.
List<SoulseekFile> _slskCandidates(List<SoulseekFile> all, SoulseekFile f) {
  final out =
      all.where((o) => o.isAudio && sameRecording(f.filename, f.durationSec, o.filename, o.durationSec)).toList();
  return out.isEmpty ? [f] : out;
}

/// Ask what "delete" should mean, then do it. [what] names the thing ("het album “Bad”"), and
/// [paths] are the files it covers. Deliberately two distinct choices — removing something from
/// the library must never silently wipe the files off disk.
Future<void> _confirmDelete(BuildContext context, String what, List<String> paths) async {
  final n = paths.length;
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _panel,
      title: Text('$what verwijderen?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: Text(
        'Dit gaat over $n bestand${n == 1 ? "" : "en"}.\n\n'
        '• Alleen uit bibliotheek: het blijft op je pc staan, maar verdwijnt uit de app.\n'
        '• Ook van pc: de bestanden worden definitief verwijderd.',
        style: const TextStyle(color: _muted, fontSize: 13, height: 1.45),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'library'),
          child: const Text('Alleen uit bibliotheek'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () => Navigator.pop(ctx, 'disk'),
          child: const Text('Ook van pc'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;

  final lib = context.read<LibraryStore>();
  final fromDisk = choice == 'disk';
  final deleted = await lib.removeTracks(paths, fromDisk: fromDisk);
  if (!context.mounted) return;
  _srcToast(
      context,
      fromDisk
          ? '$what verwijderd — $deleted bestand${deleted == 1 ? "" : "en"} van je pc gewist.'
          : '$what uit je bibliotheek gehaald (bestanden staan er nog).');
}

String _slskKey(SoulseekFile f) => '${f.username}|${f.filename}';

Future<void> _downloadSoulseek(BuildContext context, SoulseekFile f, List<SoulseekFile> all,
    {TrackTags? authority}) async {
  try {
    // false means it was refused — this track is already downloading. Say so; a "started" message
    // for something that never started is worse than no message.
    final started = await context
        .read<DownloadManager>()
        .enqueueSoulseekBest(_slskCandidates(all, f), key: _slskKey(f), authority: authority);
    if (context.mounted) {
      _srcToast(context,
          started ? '“${f.displayName}” via Soulseek…' : '“${f.displayName}” loopt al — zie Mijn downloads.');
    }
  } catch (e) {
    if (context.mounted) _srcToast(context, 'Download mislukt: $e');
  }
}

/// A download button that turns into a live progress ring while THIS key's job runs — so the
/// user sees progress right on the tile/track row, without opening the download list. Shows a
/// check when done and a retry (with the failure reason as tooltip) when it failed.
/// Everything the app is downloading, in one place — the equivalent of the native Soulseek
/// transfer list. Split into what's still running and what's finished, because a track that is
/// merely WAITING for an uploader's slot is not a failure and shouldn't look like one.
class DownloadsView extends StatelessWidget {
  const DownloadsView({super.key});

  static String statusLabel(DownloadJob j) => switch (j.status) {
        'done' => 'Klaar',
        // A download the user stopped themselves didn't fail — saying "Mislukt" makes it look
        // like something went wrong with it.
        'failed' => j.cancelled ? 'Gestopt' : 'Mislukt',
        'waiting' => j.queuePlace > 0 ? 'Wacht op peer · plaats ${j.queuePlace}' : 'Wacht op peer',
        'queued' => 'In wachtrij',
        // Already on disk and playable; a better copy is still being chased.
        'upgrading' => 'Speelbaar · upgrade',
        'preparing' => j.progress > 0 ? 'Voorbereiden ${(j.progress * 100).round()}%' : 'Voorbereiden',
        _ => 'Bezig ${(j.progress * 100).round()}%',
      };

  static Color statusColor(DownloadJob j) => switch (j.status) {
        'done' => _accent2,
        'failed' => Colors.redAccent,
        'waiting' => const Color(0xFFE0B341),
        'upgrading' => _accent2, // green: you can play it, this is a bonus not a problem
        _ => _accent,
      };

  static IconData statusIcon(DownloadJob j) => switch (j.status) {
        'done' => Icons.check_circle_rounded,
        'failed' => Icons.error_rounded,
        'waiting' => Icons.hourglass_top_rounded,
        'queued' => Icons.schedule_rounded,
        'upgrading' => Icons.upgrade_rounded,
        _ => Icons.downloading_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadManager>(
      builder: (_, dm, __) {
        final active = dm.jobs.where((j) => j.busy).toList();
        final finished = dm.jobs.where((j) => !j.busy).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 30),
          children: [
            Row(
              children: [
                const Text('Mijn downloads',
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                const SizedBox(width: 14),
                if (active.isNotEmpty)
                  // Counted from the jobs themselves: a download waiting in an uploader's queue has
                  // handed its parallel slot back, so the scheduler's counters would read 0 here.
                  Text('${active.where((j) => j.status == 'downloading' || j.status == 'preparing').length} bezig'
                      ' · ${active.where((j) => j.status == 'waiting' || j.status == 'queued').length} wachtend',
                      style: const TextStyle(color: _muted, fontSize: 12.5)),
                const Spacer(),
                if (finished.isNotEmpty)
                  TextButton.icon(
                    onPressed: dm.clearFinished,
                    icon: const Icon(Icons.clear_all_rounded, size: 16),
                    label: const Text('Wis afgeronde'),
                    style: TextButton.styleFrom(foregroundColor: _muted),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (dm.jobs.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(
                  child: Text('Nog geen downloads.\nStart er een vanuit een album of via Online zoeken.',
                      textAlign: TextAlign.center, style: TextStyle(color: _muted, height: 1.6)),
                ),
              ),
            if (active.isNotEmpty) ...[
              const _DlHeader('BEZIG'),
              ...active.map((j) => _DlRow(job: j)),
              const SizedBox(height: 22),
            ],
            if (finished.isNotEmpty) ...[
              const _DlHeader('AFGEROND'),
              ...finished.map((j) => _DlRow(job: j)),
            ],
          ],
        );
      },
    );
  }
}

class _DlHeader extends StatelessWidget {
  final String text;
  const _DlHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8)),
      );
}

class _DlRow extends StatelessWidget {
  final DownloadJob job;
  const _DlRow({required this.job});

  @override
  Widget build(BuildContext context) {
    final color = DownloadsView.statusColor(job);
    final indeterminate = job.status == 'queued' || job.status == 'waiting';
    // Playable already: show the bar full, whatever is still running for it is a bonus.
    final filled = job.status == 'done' || job.status == 'upgrading';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          Icon(DownloadsView.statusIcon(job), size: 19, color: color),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(job.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                if (job.detail != null && job.detail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(job.detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: job.status == 'failed' ? Colors.red.shade300 : _muted)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 190,
            child: LinearProgressIndicator(
              value: filled ? 1 : (indeterminate || job.progress <= 0 ? null : job.progress),
              backgroundColor: const Color(0xFF2A2F42),
              color: color,
            ),
          ),
          const SizedBox(width: 14),
          // Stop what you no longer want — a slot freed here is a slot another download gets.
          SizedBox(
            width: 34,
            child: job.busy && job.canCancel
                ? Consumer<DownloadManager>(
                    builder: (_, dm, __) => IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      color: _muted,
                      tooltip: 'Download stoppen',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => dm.cancelJob(job),
                    ),
                  )
                : null,
          ),
          SizedBox(
            width: 150,
            child: Text(DownloadsView.statusLabel(job),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

Widget _downloadControl(BuildContext context,
    {required String jobKey, required VoidCallback onDownload, String tooltip = 'Downloaden via Soulseek'}) {
  return Consumer<DownloadManager>(
    builder: (_, dm, __) {
      final job = dm.jobByKey(jobKey);
      final status = job?.status;
      if (status == 'queued') {
        // Waiting for a download slot — show a queue clock, NOT a spinner (a spinning ring here
        // looked like a stuck download when several tracks were started at once).
        return const Padding(
          padding: EdgeInsets.all(9),
          child: Tooltip(
            message: 'In wachtrij…',
            child: Icon(Icons.schedule_rounded, color: _muted, size: 19),
          ),
        );
      }
      if (status == 'waiting') {
        // The uploader has us in its queue and will start when a slot frees — exactly what the
        // native client shows as "Queued". Not a failure, so no red: an hourglass plus the place.
        final place = job!.queuePlace;
        return Tooltip(
          message: job.detail ?? 'Wachten op peer…',
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(alignment: Alignment.center, children: [
              const Icon(Icons.hourglass_top_rounded, color: Color(0xFFE0B341), size: 19),
              if (place > 0)
                Positioned(
                  bottom: 2,
                  child: Text('$place',
                      style: const TextStyle(fontSize: 8.5, color: _muted, fontWeight: FontWeight.w700)),
                ),
            ]),
          ),
        );
      }
      if (status == 'downloading' || status == 'preparing') {
        final pct = (job!.progress * 100).round();
        return Tooltip(
          message: job.detail ?? 'Bezig…',
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    value: job.progress > 0 ? job.progress : null,
                    color: _accent,
                    backgroundColor: const Color(0xFF2A2F42)),
              ),
              Text('$pct', style: const TextStyle(fontSize: 8.5, color: _muted, fontWeight: FontWeight.w700)),
            ]),
          ),
        );
      }
      if (status == 'upgrading') {
        // Downloaded and playable — the arrow says a better copy is still being fetched.
        return Tooltip(
          message: job?.detail ?? 'Speelbaar · betere kwaliteit onderweg',
          child: const Padding(
            padding: EdgeInsets.all(9),
            child: Icon(Icons.upgrade_rounded, color: _accent2, size: 20),
          ),
        );
      }
      if (status == 'done') {
        return const Padding(padding: EdgeInsets.all(9), child: Icon(Icons.check_circle_rounded, color: _accent2, size: 20));
      }
      if (status == 'failed') {
        return IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: Colors.redAccent,
            tooltip: job?.detail != null ? 'Mislukt: ${job!.detail} — opnieuw' : 'Mislukt — opnieuw proberen',
            onPressed: onDownload);
      }
      return IconButton(icon: const Icon(Icons.download_rounded), color: _accent, tooltip: tooltip, onPressed: onDownload);
    },
  );
}

/// The most complete album folder among Soulseek hits (most audio files from ONE peer's
/// folder) — so "Download album" grabs a coherent album from a single source.
List<SoulseekFile> _bestSoulseekFolder(List<SoulseekFile> files) {
  final groups = <String, List<SoulseekFile>>{};
  for (final f in files) {
    final p = f.filename.replaceAll('/', '\\');
    final folder = p.contains('\\') ? p.substring(0, p.lastIndexOf('\\')) : p;
    groups.putIfAbsent('${f.username}|$folder', () => []).add(f);
  }
  final ranked = groups.values.toList()
    ..sort((a, b) {
      if (a.length != b.length) return b.length.compareTo(a.length); // most tracks
      final fa = a.where((f) => f.freeSlots).length, fb = b.where((f) => f.freeSlots).length;
      return fb.compareTo(fa); // then most free-slot peers
    });
  return ranked.isEmpty ? const [] : ranked.first;
}

Future<void> _downloadSoulseekAlbum(
    BuildContext context, List<SoulseekFile> folder, List<SoulseekFile> all,
    {ReleaseAuthority? authority}) async {
  // Each folder track → its cross-peer candidates, so a busy peer for one track falls back
  // to another peer offering the same song instead of failing the whole album.
  final tracks = [for (final f in folder) _slskCandidates(all, f)];
  // Which official track each file actually is, decided by name and running time rather than by
  // the number the uploader happened to type in front of it.
  final authorities = [
    for (final f in folder) authority?.match(f.displayName, f.durationSec ?? 0)
  ];
  final n = await context
      .read<DownloadManager>()
      .enqueueSoulseekAlbum(tracks, authorities: authorities);
  if (context.mounted) {
    _srcToast(context, '$n nummer(s) via Soulseek — volg de voortgang in de downloadlijst.');
  }
}

/// Soulseek section header with a "Download album" action for the best complete folder.
/// [all] is the full (unfiltered) result set — used to find fallback peers per track.
Widget _soulseekHeader(BuildContext context, List<SoulseekFile> slsk, bool busy, List<SoulseekFile> all,
    {ReleaseAuthority? authority}) {
  final folder = _bestSoulseekFolder(slsk);
  return Padding(
    padding: const EdgeInsets.fromLTRB(24, 14, 18, 6),
    child: Row(
      children: [
        const Text('SOULSEEK · P2P',
            style: TextStyle(color: _muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6)),
        const SizedBox(width: 8),
        Text('${slsk.length}', style: const TextStyle(color: _muted, fontSize: 11.5)),
        // Back-off notice: after a refused login the app stops touching Soulseek entirely, so the
        // user knows WHY there are no results (instead of thinking the search is just empty).
        if (context.read<SoulseekService>().blocked) ...[
          const SizedBox(width: 10),
          Icon(Icons.pause_circle_outline_rounded, size: 13, color: Colors.orange.shade300),
          const SizedBox(width: 4),
          Text(
              'gepauzeerd — login geweigerd, wacht nog ${(context.read<SoulseekService>().blockedFor?.inMinutes ?? 0) + 1} min',
              style: TextStyle(color: Colors.orange.shade300, fontSize: 11.5)),
          const SizedBox(width: 6),
          // This wait is OUR guard, not Soulseek's. When the official client is logged in fine,
          // the account clearly isn't blocked and the user should never be stuck behind it.
          TextButton(
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 26)),
            onPressed: () {
              context.read<SoulseekService>().retryLoginNow();
              _srcToast(context, 'Soulseek opnieuw proberen…');
            },
            child: const Text('nu opnieuw proberen', style: TextStyle(fontSize: 11.5)),
          ),
        ],
        if (busy) ...const [
          SizedBox(width: 8),
          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: _muted)),
        ],
        const Spacer(),
        if (folder.length >= 2)
          TextButton.icon(
            onPressed: () => _downloadSoulseekAlbum(context, folder, all, authority: authority),
            icon: const Icon(Icons.library_add_rounded, size: 16),
            label: Text('Download album (${folder.length})'),
            style: TextButton.styleFrom(foregroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 8)),
          ),
      ],
    ),
  );
}

Widget _qualityBadge(Quality q) {
  Color fg, bg, border;
  switch (q.tier) {
    case QTier.hires: // hi-res lossless (24-bit / >48kHz / DSD) — gold
      fg = const Color(0xFFF2C14E);
      bg = const Color(0xFF2A2413);
      border = const Color(0xFF5A4A1E);
      break;
    case QTier.lossless: // CD-quality lossless — teal
      fg = _accent2;
      bg = const Color(0xFF0F2521);
      border = const Color(0xFF24493F);
      break;
    case QTier.lossy: // MP3/AAC — blue-grey
      fg = const Color(0xFFA9B6E8);
      bg = const Color(0xFF161A2C);
      border = const Color(0xFF2A3350);
      break;
    case QTier.unknown: // unclear — subtle grey
      fg = _muted;
      bg = const Color(0xFF1A1D29);
      border = _line;
      break;
  }
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 8),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: border)),
    child: Text(q.label, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w600)),
  );
}

/// Quality of a LOCAL library track (real bitrate from size÷duration, so a 16/44 FLAC and a
/// 24-bit hi-res FLAC read differently).
Quality _trackQuality(Track t) => qualityFromFile(
      name: t.title,
      ext: t.ext,
      isFlac: t.isFlac,
      durationSec: t.duration?.inSeconds,
      size: t.sizeBytes,
    );

Quality _slskQuality(SoulseekFile f) => qualityFromFile(
      name: f.displayName,
      ext: f.ext,
      isFlac: f.isFlac,
      bitrate: f.bitrate,
      durationSec: f.durationSec,
      size: f.size,
      isVbr: f.isVbr,
    );

/// A row of quality-filter chips (Alles / Lossless / Hi-Res / MP3), shared by the
/// direct-search results and the browse "Bronnen" panel.
Widget _filterChipsRow(QFilter current, ValueChanged<QFilter> onChanged) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 20, 2),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, size: 15, color: _muted),
          const SizedBox(width: 8),
          ...QFilter.values.map((f) {
            final sel = current == f;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () => onChanged(f),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: sel ? _accent : _panel,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sel ? _accent : _line),
                  ),
                  child: Text(f.label,
                      style: TextStyle(
                          color: sel ? Colors.white : _muted, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            );
          }),
        ],
      ),
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
  final q = qualityFromName(r.name);
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
        _qualityBadge(q),
        IconButton(icon: const Icon(Icons.play_arrow_rounded), color: _accent, tooltip: 'Beste nummer afspelen', onPressed: () => _playTorrent(context, r)),
        IconButton(icon: const Icon(Icons.queue_music_rounded), color: _muted, tooltip: 'Kies nummer', onPressed: () => _pickTorrentTracks(context, r)),
        IconButton(icon: const Icon(Icons.download_rounded), color: _muted, tooltip: 'Alles downloaden', onPressed: () => _downloadTorrent(context, r)),
      ],
    ),
  );
}

Widget _soulseekTile(BuildContext context, SoulseekFile f, List<SoulseekFile> all, {TrackTags? authority}) {
  final status = f.freeSlots ? 'vrij' : 'wachtrij ${f.queueLength}';
  final q = _slskQuality(f);
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
              Text(
                  '$status · ${f.username} · ${_fmtBytes(f.size)}'
                  '${f.durationSec != null && f.durationSec! > 0 ? " · ${_fmt(Duration(seconds: f.durationSec!))}" : ""}',
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ],
          ),
        ),
        _qualityBadge(q),
        _downloadControl(context,
            jobKey: _slskKey(f),
            onDownload: () => _downloadSoulseek(context, f, all, authority: authority)),
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

  /// The official release this list of sources belongs to, when it was opened from an album page.
  ///
  /// Soulseek serves one song under a dozen names and each carries its own tags. Without this the
  /// peer decides what track it is; with it, the record does and Soulseek only supplies the audio.
  /// Null when the sources were opened from a loose search, where there is no release to appeal to.
  final ReleaseAuthority? authority;

  /// The one track these sources are for, when this list is under a track row.
  final ChoiceTrack? track;
  const SourcesView({super.key, required this.query, this.authority, this.track});
  @override
  State<SourcesView> createState() => _SourcesViewState();
}

class _SourcesViewState extends State<SourcesView> {
  List<SearchResult> _torrents = [];
  List<SoulseekFile> _slsk = [];
  bool _tBusy = true, _sBusy = false;
  QFilter _filter = QFilter.all;

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
      soulseek.search(widget.query, onPartial: (p) {
        if (mounted) setState(() => _slsk = p);
      }).then((r) {
        if (mounted) setState(() { _slsk = r; _sBusy = false; });
      }).catchError((_) { if (mounted) setState(() => _sBusy = false); });
    }
    try {
      final r = await online.search(widget.query, onPartial: (p) {
        if (mounted) setState(() => _torrents = p);
      });
      if (mounted) setState(() => _torrents = r);
    } catch (_) {}
    if (mounted) setState(() => _tBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ready = context.read<SoulseekService>().available;
    final torrents = _torrents.where((r) => _filter.matches(qualityFromName(r.name))).toList();
    final slsk = _slsk.where((f) => _filter.matches(_slskQuality(f))).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_torrents.isNotEmpty || _slsk.isNotEmpty)
          _filterChipsRow(_filter, (f) => setState(() => _filter = f)),
        _sourceHeader('Torrents · TorBox', torrents.length, _tBusy),
        if (torrents.isEmpty && !_tBusy)
          const Padding(
              padding: EdgeInsets.fromLTRB(24, 2, 24, 6),
              child: Text('Geen torrents gevonden.', style: TextStyle(color: _muted, fontSize: 12.5))),
        ...torrents.map((r) => _torrentTile(context, r)),
        if (ready)
          _soulseekHeader(context, slsk, _sBusy, slsk, authority: widget.authority)
        else
          const Padding(
              padding: EdgeInsets.fromLTRB(24, 14, 24, 6),
              child: Text('SOULSEEK · log in via Instellingen',
                  style: TextStyle(color: _muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6))),
        if (ready && slsk.isEmpty && !_sBusy)
          const Padding(
              padding: EdgeInsets.fromLTRB(24, 2, 24, 6),
              child: Text('Geen Soulseek-bronnen.', style: TextStyle(color: _muted, fontSize: 12.5))),
        // Whichever copy the user picks, the record decides what it is. That is the whole point:
        // this same song is offered as "13 …", "19. …" and "…The Essential … - 01 - …".
        ..._slskTiles(context, slsk, authority: _trackAuthority),
      ],
    );
  }

  /// What the track under this list IS, when it was opened from an album page.
  TrackTags? get _trackAuthority {
    final a = widget.authority, t = widget.track;
    if (a == null || t == null) return null;
    // The position IS the number: this tracklist came from the official release. Never indexOf on
    // the track — ChoiceTrack has no equality, so it would miss every time and fall back to
    // something that is not a track number at all.
    final stated = int.tryParse(t.position) ?? 0;
    if (stated > 0) return a.forTrack(t, stated);
    final at = a.tracks.indexWhere((x) => normKey(x.title) == normKey(t.title));
    return at < 0 ? null : a.forTrack(t, at + 1);
  }
}

/// Rows are built eagerly inside a plain ListView, so a broad query (3500+ hits is normal for a
/// popular track) would build every one of them on every rebuild and lock the UI. Results are
/// quality-sorted, so showing the head is no loss — and the full list is still handed to each
/// tile as its candidate pool, so downloading keeps every fallback peer.
const _slskShown = 250;

List<Widget> _slskTiles(BuildContext context, List<SoulseekFile> slsk, {TrackTags? authority}) {
  final shown = slsk.length <= _slskShown ? slsk : slsk.sublist(0, _slskShown);
  return [
    ...shown.map((f) => _soulseekTile(context, f, slsk, authority: authority)),
    if (slsk.length > _slskShown)
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
        child: Text(
          'Nog ${slsk.length - _slskShown} bronnen niet getoond — de beste staan bovenaan. '
          'Verfijn je zoekopdracht om ze te zien.',
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
      ),
  ];
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
  // browse (artists + albums + tracks)
  List<CatalogArtist> _artists = [];
  List<CatalogAlbumHit> _albumHits = [];
  List<CatalogTrackHit> _trackHits = [];
  bool _browseBusy = false;
  int? _trackExpanded;
  // direct
  List<SearchResult> _torrents = [];
  List<SoulseekFile> _slsk = [];
  bool _busy = false, _slskBusy = false;
  String? _status;
  QFilter _filter = QFilter.all;
  int _searchGen = 0; // guards streaming callbacks from a superseded search
  // tidal
  List<TidalTrack> _tidalTracks = [];
  bool _tidalBusy = false, _tidalConnecting = false;
  int? _tidalExpanded;

  Future<void> _search() async {
    final q = _c.text.trim();
    if (q.isEmpty) return;
    if (_mode == 0) {
      await _searchBrowse(q);
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

  /// Append what Discogs has that Deezer does not.
  ///
  /// Deezer catalogues what streams and is the faster, cleaner search, so it stays first and the
  /// list is usable before Discogs answers at all. Discogs is where the editions, the promos and
  /// the regional issues live — the versions Deezer has no entry for.
  ///
  /// Deduped on artist + title, so the same record never appears twice; a different EDITION of it
  /// carries a different title and still comes through, which is the whole reason to add it.
  Future<void> _addDiscogsAlbums(String q) async {
    try {
      final extra = await DiscogsService(context.read<AppSettings>()).searchAlbums(q);
      if (!mounted || extra.isEmpty) return;
      String key(CatalogAlbumHit h) => '${artistKey(h.artist)}|${normKey(h.album.title)}';
      final seen = {for (final h in _albumHits) key(h)};
      final add = [
        for (final h in extra)
          if (seen.add(key(h))) h
      ];
      if (add.isEmpty) return;
      setState(() {
        _albumHits = [..._albumHits, ...add];
        _status = null;
      });
    } catch (_) {/* Deezer on its own is still a working search */}
  }

  /// Add what MusicBrainz knows: albums, tracks and artists.
  ///
  /// Runs AFTER Deezer, never inside its Future.wait — MusicBrainz spaces its requests 1100 ms
  /// apart, and putting it in the same wait would hold the fast results hostage to the slow one.
  ///
  /// Every query is scoped to an artist first. MusicBrainz ranks on text alone with no popularity
  /// signal at all: bare "thriller" returns Part Chimp and Swoop before Michael Jackson, and bare
  /// "quit playing games" returns Mar.Ko before the Backstreet Boys. Scoped, both are exact.
  Future<void> _addMusicBrainzHits(String q) async {
    final mb = context.read<MusicBrainzService>();
    try {
      // "Artist - Album" first, then the whole query as an artist name, then whatever the Deezer
      // pass already decided the artist was. Any of the three gives the scoping that makes this work.
      var artist = '', rest = q.trim();
      final dash = q.indexOf(' - ');
      if (dash > 0) {
        artist = q.substring(0, dash).trim();
        rest = q.substring(dash + 3).trim();
      } else if (_artists.isNotEmpty) {
        artist = _artists.first.name;
      }

      final found = await mb.searchArtists(q, max: 8);
      if (!mounted) return;
      if (found.isNotEmpty) {
        final have = {for (final a in _artists) artistKey(a.name)};
        final add = [
          for (final a in found)
            if (have.add(artistKey(a.name)))
              CatalogArtist(0, a.name, null, 0,
                  origin: CatalogRef.musicbrainz(a.mbid), detail: a.line)
        ];
        if (add.isNotEmpty) setState(() => _artists = [..._artists, ...add]);
        if (artist.isEmpty) artist = found.first.name;
      }

      // Records, not pressings — otherwise twenty CDs of one album are twenty cards.
      final groups = await mb.searchReleaseGroups(rest, artist: artist);
      if (!mounted) return;
      if (groups.isNotEmpty) {
        final have = {
          for (final h in _albumHits) '${artistKey(h.artist)}|${normKey(h.album.title)}'
        };
        final add = <CatalogAlbumHit>[];
        for (final g in groups) {
          if (!have.add('${artistKey(g.artist)}|${normKey(g.title)}')) continue;
          add.add(CatalogAlbumHit(
            CatalogAlbum(0, g.title, null, g.firstDate, 0,
                g.primaryType.toLowerCase().isEmpty ? 'album' : g.primaryType.toLowerCase(),
                // A GROUP, not a release. Opening it resolves a pressing first — only a pressing
                // has a tracklist, and handing a group id to the release endpoint loads nothing.
                origin: CatalogRef.musicbrainzGroup(g.mbid)),
            g.artist,
          ));
          if (add.length >= 12) break;
        }
        if (add.isNotEmpty) setState(() => _albumHits = [..._albumHits, ...add]);
      }

      final recs = await mb.searchRecordings(rest, artist: artist);
      if (!mounted || recs.isEmpty) return;
      // MusicBrainz returns one row per release a recording appears on, so a popular song comes
      // back twenty-five times. Without this the track list is one title repeated.
      final have = {for (final t in _trackHits) '${artistKey(t.artist)}|${normKey(t.title)}'};
      final add = [
        for (final r in recs)
          if (have.add('${artistKey(r.artist)}|${normKey(r.title)}'))
            CatalogTrackHit(r.title, r.artist, null)
      ];
      if (add.isNotEmpty) setState(() => _trackHits = [..._trackHits, ...add.take(12)]);
    } catch (_) {/* Deezer and Discogs on their own are still a working search */}
  }

  Future<void> _searchBrowse(String q) async {
    setState(() {
      _browseBusy = true;
      _artists = [];
      _albumHits = [];
      _trackHits = [];
      _trackExpanded = null;
      _status = null;
    });
    try {
      final res = await Future.wait([
        _catalog.searchArtists(q),
        _catalog.searchAlbums(q),
        _catalog.searchTracks(q),
      ]);
      if (!mounted) return;
      setState(() {
        _artists = res[0] as List<CatalogArtist>;
        _albumHits = res[1] as List<CatalogAlbumHit>;
        _trackHits = res[2] as List<CatalogTrackHit>;
        _status = (_artists.isEmpty && _albumHits.isEmpty && _trackHits.isEmpty)
            ? 'Niets gevonden.'
            : null;
      });
      await _addDiscogsAlbums(q);
      await _addMusicBrainzHits(q);
      if (mounted && _artists.isEmpty && _albumHits.isEmpty && _trackHits.isEmpty) {
        setState(() => _status = 'Niets gevonden.');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Zoeken mislukt: $e');
    } finally {
      if (mounted) setState(() => _browseBusy = false);
    }
  }

  Future<void> _searchDirect(String q) async {
    final online = context.read<OnlineService>();
    final soulseek = context.read<SoulseekService>();
    final gen = ++_searchGen; // a newer search invalidates this one's streaming callbacks
    bool live() => mounted && gen == _searchGen;
    setState(() {
      _busy = true;
      _slskBusy = soulseek.available;
      _torrents = [];
      _slsk = [];
      _status = 'Zoeken…';
    });
    if (soulseek.available) {
      soulseek.search(q, onPartial: (p) {
        if (live()) setState(() => _slsk = p); // stream results as peers respond
      }).then((r) {
        if (live()) setState(() { _slsk = r; _slskBusy = false; });
      }).catchError((_) {
        if (live()) setState(() => _slskBusy = false);
      });
    }
    try {
      final r = await online.search(q, onPartial: (p) {
        if (live()) setState(() { _torrents = p; _status = null; }); // fast sources show first
      });
      if (live()) setState(() { _torrents = r; _status = null; });
    } catch (e) {
      if (live()) setState(() => _status = 'Torrent-zoeken mislukt: $e');
    } finally {
      if (live()) setState(() => _busy = false);
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
                        ? 'Zoek artiest, album of nummer…'
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
                onPressed: (_busy || _browseBusy || _tidalBusy) ? null : _search,
                child: const Text('Zoek'),
              ),
            ],
          ),
        ),
        Consumer<DownloadManager>(
          builder: (_, dm, __) {
            final recent = dm.jobs.take(5).toList();
            if (recent.isEmpty) return const SizedBox.shrink();
            final hasFinished = dm.jobs.any((j) => j.status == 'done' || j.status == 'failed');
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text('DOWNLOADS',
                          style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6)),
                      const Spacer(),
                      if (hasFinished)
                        TextButton.icon(
                          onPressed: () => dm.clearFinished(),
                          icon: const Icon(Icons.clear_all_rounded, size: 15),
                          label: const Text('Wis afgeronde'),
                          style: TextButton.styleFrom(
                              foregroundColor: _muted,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              textStyle: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  ...recent
                    .map((j) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(j.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12.5)),
                                      if (j.detail != null && j.detail!.isNotEmpty)
                                        Text(j.detail!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 10.5,
                                                color: j.status == 'failed' ? Colors.red.shade300 : _muted)),
                                    ],
                                  )),
                              SizedBox(
                                width: 160,
                                child: LinearProgressIndicator(
                                  value: j.status == 'done'
                                      ? 1
                                      : (j.status == 'preparing' && j.progress <= 0 ? null : j.progress),
                                  backgroundColor: const Color(0xFF2A2F42),
                                  color: j.status == 'failed'
                                      ? Colors.red
                                      : (j.status == 'done' ? _accent2 : _accent),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 70,
                                child: Text(
                                  j.status == 'done'
                                      ? 'klaar'
                                      : (j.status == 'failed'
                                          ? (j.cancelled ? 'gestopt' : 'mislukt')
                                          : (j.status == 'queued'
                                              ? 'wachtrij'
                                              : (j.status == 'preparing'
                                                  ? (j.progress > 0 ? 'TorBox ${(j.progress * 100).round()}%' : 'voorbereiden')
                                                  : '${(j.progress * 100).round()}%'))),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(color: _muted, fontSize: 11.5),
                                ),
                              ),
                            ],
                          ),
                        )),
                ],
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
    if (_browseBusy) return const Center(child: CircularProgressIndicator(color: _accent));
    if (_artists.isEmpty && _albumHits.isEmpty && _trackHits.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Zoek een artiest, album of nummer — bronnen (torrent/Soulseek) verschijnen eronder.',
              textAlign: TextAlign.center, style: TextStyle(color: _muted)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_artists.isNotEmpty) ...[
          _browseHeader('Artiesten', _artists.length),
          SizedBox(
            height: 158,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _artists.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final a = _artists[i];
                return InkWell(
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtistBrowsePage(a))),
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 116,
                    child: Column(
                      children: [
                        _netCover(a.picture, size: 116, circle: true),
                        const SizedBox(height: 6),
                        Text(a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (_albumHits.isNotEmpty) ...[
          _browseHeader('Albums', _albumHits.length),
          SizedBox(
            height: 186,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _albumHits.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final h = _albumHits[i];
                return InkWell(
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => AlbumBrowsePage(h.artist, h.album))),
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 132,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _netCover(h.album.cover, size: 132, radius: 10),
                        const SizedBox(height: 6),
                        Text(h.album.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Text(h.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: _muted)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (_trackHits.isNotEmpty) ...[
          _browseHeader('Nummers', _trackHits.length),
          ..._trackHits.asMap().entries.map((e) => _browseTrackRow(e.key, e.value)),
        ],
      ],
    );
  }

  Widget _browseHeader(String title, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
        child: Text('${title.toUpperCase()}  ·  $count',
            style: const TextStyle(
                color: _muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6)),
      );

  Widget _browseTrackRow(int i, CatalogTrackHit t) {
    final open = _trackExpanded == i;
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _trackExpanded = open ? null : i),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration:
                BoxDecoration(color: open ? _panel : Colors.transparent, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                _netCover(t.cover, size: 42, radius: 6),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      Text(t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: _muted)),
                    ],
                  ),
                ),
                Icon(open ? Icons.expand_less_rounded : Icons.chevron_right_rounded, color: _muted),
              ],
            ),
          ),
        ),
        if (open) Padding(padding: const EdgeInsets.only(bottom: 8), child: SourcesView(query: t.query)),
      ],
    );
  }

  Widget _directResults(bool soulseekReady) {
    final torrents = _torrents.where((r) => _filter.matches(qualityFromName(r.name))).toList();
    final slsk = _slsk.where((f) => _filter.matches(_slskQuality(f))).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_torrents.isNotEmpty || _slsk.isNotEmpty)
          _filterChipsRow(_filter, (f) => setState(() => _filter = f)),
        if (torrents.isNotEmpty) _sourceHeader('Torrents · TorBox', torrents.length, _busy),
        ...torrents.map((r) => _torrentTile(context, r)),
        if (_status == null || _slsk.isNotEmpty || _slskBusy)
          (soulseekReady
              ? _soulseekHeader(context, slsk, _slskBusy, slsk)
              : const Padding(
                  padding: EdgeInsets.fromLTRB(24, 16, 24, 6),
                  child: Text('SOULSEEK · log in via Instellingen om P2P mee te zoeken',
                      style: TextStyle(color: _muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6)))),
        ..._slskTiles(context, slsk),
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
  double _prep = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (t, f) = await context.read<OnlineService>().tracklist(widget.result, onProgress: (p, s) {
        if (mounted) setState(() => _prep = p);
      });
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

  void _download(TbFile f) {
    context.read<DownloadManager>().enqueue(widget.result, fileId: f.id);
    _snack('“${f.label}” naar downloads');
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                child: Center(
                  child: Column(children: [
                    const CircularProgressIndicator(color: _accent),
                    const SizedBox(height: 16),
                    Text(
                        _prep > 0
                            ? 'TorBox haalt de torrent op… ${(_prep * 100).round()}%'
                            : 'Bron voorbereiden bij TorBox…',
                        style: const TextStyle(color: _muted, fontSize: 12.5)),
                    if (_prep > 0) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                            value: _prep, minHeight: 4, backgroundColor: _panel2, color: _accent),
                      ),
                    ],
                    if (!widget.result.cached) ...const [
                      SizedBox(height: 10),
                      Text('Niet-gecachte torrents met weinig seeders kunnen even duren.',
                          textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 11)),
                    ],
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
      // Capped where the long text actually lives, so artist bios and album blurbs both get it.
      // Align is load-bearing: a list hands its children a TIGHT width and a bare ConstrainedBox
      // cannot shrink below that — without it the cap silently does nothing.
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 13, height: 1.45)),
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Text('Lees meer',
                    style: TextStyle(color: _accent, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The banner at the top of the start page: the newest releases, one at a time, large.
///
/// The cover doubles as the backdrop — blurred, darkened and bled to the edges — because an album
/// has no separate wide artwork the way a film has a still. Auto-advances, but stops the moment
/// the pointer is on it so it can't slide away mid-read.
class HeroCarousel extends StatefulWidget {
  final List<CatalogAlbumHit> hits;
  const HeroCarousel({super.key, required this.hits});

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final _page = PageController();
  Timer? _timer;
  int _index = 0;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    if (widget.hits.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || _hover || !_page.hasClients) return;
      _page.animateToPage((_index + 1) % widget.hits.length,
          duration: const Duration(milliseconds: 550), curve: Curves.easeInOutCubic);
    });
  }

  void _go(int delta) {
    if (!_page.hasClients) return;
    final n = widget.hits.length;
    _page.animateToPage((_index + delta + n) % n,
        duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 260,
          child: Stack(
            children: [
              PageView.builder(
                controller: _page,
                itemCount: widget.hits.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _slide(widget.hits[i]),
              ),
              if (widget.hits.length > 1) ...[
                _arrow(Alignment.centerLeft, Icons.chevron_left_rounded, -1),
                _arrow(Alignment.centerRight, Icons.chevron_right_rounded, 1),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < widget.hits.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 260),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _index ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _index ? Colors.white : Colors.white.withValues(alpha: .38),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _arrow(Alignment side, IconData icon, int delta) => Align(
        alignment: side,
        child: AnimatedOpacity(
          opacity: _hover ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Material(
              color: Colors.black.withValues(alpha: .45),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _go(delta),
                child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 26, color: Colors.white)),
              ),
            ),
          ),
        ),
      );

  Widget _slide(CatalogAlbumHit hit) {
    final cover = hit.album.cover;
    return GestureDetector(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => AlbumBrowsePage(hit.artist, hit.album))),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cover != null)
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            // Without this the blurred art is too busy to read white text on. Kept dark even at
            // the far edge: a mostly-white sleeve blurs to near-white and washed the banner out.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.black.withValues(alpha: .88), Colors.black.withValues(alpha: .62)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 168,
                      height: 168,
                      child: cover == null
                          ? Container(color: _panel2)
                          : Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: _panel2)),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('NIEUWE RELEASE',
                            style: TextStyle(
                                color: _accent2, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        Text(hit.album.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, height: 1.1)),
                        const SizedBox(height: 6),
                        Text(hit.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, color: Color(0xFFC7CBDA))),
                        if (hit.album.year != null) ...[
                          const SizedBox(height: 2),
                          Text('${hit.album.year}', style: const TextStyle(fontSize: 12.5, color: _muted)),
                        ],
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => AlbumBrowsePage(hit.artist, hit.album))),
                          icon: const Icon(Icons.playlist_add_rounded, size: 18),
                          label: const Text('Bekijken'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A cinematic banner for an artist: wide backdrop, and the act's OWN wordmark rather than their
/// name set in the app's typeface.
///
/// The wordmark is the point. There is no way to render text in an artist's official lettering —
/// those fonts aren't distributed — but the logo itself is an image of exactly that lettering, so
/// showing it is the real thing instead of an imitation. Falls back to plain text for the acts
/// that have no logo (about one in four).
/// The artist's own photo, blurred, standing behind a WHOLE page rather than behind a banner.
///
/// It does not scroll: the records and tracks move over a wash that stays put, so the page reads
/// as one thing about one artist instead of a strip of atmosphere with a list bolted under it.
/// The scrim is light at the top, where the portrait and wordmark are, and settles to near-solid
/// below that — album titles and track rows have to stay readable over it.
class ArtistBackdrop extends StatefulWidget {
  final String name;
  final Uint8List? fallbackImage;
  final Widget child;
  const ArtistBackdrop({super.key, required this.name, this.fallbackImage, required this.child});

  @override
  State<ArtistBackdrop> createState() => _ArtistBackdropState();
}

class _ArtistBackdropState extends State<ArtistBackdrop> {
  ArtistArt? _art;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ArtistBackdrop old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name) {
      setState(() => _art = null);
      _load();
    }
  }

  Uint8List? _chosenBackdrop;
  String? _loadedUrl;

  Future<void> _load() async {
    final name = widget.name;
    final settings = context.read<AppSettings>();
    final art = await CoverEnricher(settings).artistArt(name);
    if (!mounted || name != widget.name) return;
    setState(() => _art = art);
    // A picture the user picked outranks anything the shape heuristic chose. Fetched here rather
    // than stored as bytes, so the choice survives independently of any cache being cleared.
    final lib = context.read<LibraryStore>();
    for (final kind in const ['backdrop']) {
      final url = lib.chosenArtistArt(name, kind);
      if (url == null) continue;
      final bytes = await CoverEnricher(settings).downloadImage(url);
      if (!mounted || name != widget.name || bytes == null) continue;
      if (kind == 'backdrop') setState(() => _chosenBackdrop = bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Same as the hero: a fresh pick has to show without leaving the page and coming back.
    final chosen = context.watch<LibraryStore>().chosenArtistArt(widget.name, 'backdrop');
    if (chosen != _loadedUrl) {
      _loadedUrl = chosen;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    final img = _chosenBackdrop ?? _art?.backdropBytes ?? _art?.thumbBytes ?? widget.fallbackImage;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (img != null)
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              // Overscanned, or the blur samples past the image and the edges fade to nothing.
              child: Transform.scale(
                scale: 1.25,
                child: Image.memory(img,
                    fit: BoxFit.cover, alignment: Alignment.topCenter, errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // The hero fills roughly the top third, so the scrim stays light that far down and
              // only closes in below it, where the records and tracks have to stay readable.
              colors: [
                Colors.black.withValues(alpha: .26),
                Colors.black.withValues(alpha: .40),
                const Color(0xFF0B0D14).withValues(alpha: .86),
                const Color(0xFF0B0D14).withValues(alpha: .92),
              ],
              stops: const [0, .30, .58, 1],
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class ArtistHero extends StatefulWidget {
  final String name;
  final String? subtitle;
  final Uint8List? fallbackImage;
  final List<Widget> actions;

  /// False when an [ArtistBackdrop] is already washing the whole page — the hero then contributes
  /// only the portrait and the wordmark, and doesn't paint a second, differently-cropped copy.
  final bool ownBackdrop;
  const ArtistHero({
    super.key,
    required this.name,
    this.subtitle,
    this.fallbackImage,
    this.actions = const [],
    this.ownBackdrop = true,
  });

  @override
  State<ArtistHero> createState() => _ArtistHeroState();
}

class _ArtistHeroState extends State<ArtistHero> {
  ArtistArt? _art;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ArtistHero old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name) {
      setState(() => _art = null);
      _load();
    }
  }

  /// The URLs this hero last fetched, so a fresh pick can be spotted while the page stays open.
  String? _loadedPortraitUrl, _loadedBackdropUrl;

  /// Re-fetch when the user picks a different photo. Without this the choice was saved and simply
  /// not shown until you left the page and came back — a setting that appears to do nothing.
  void _syncChoice() {
    final lib = context.watch<LibraryStore>();
    final p = lib.chosenArtistArt(widget.name, 'portrait');
    final b = lib.chosenArtistArt(widget.name, 'backdrop');
    if (p == _loadedPortraitUrl && b == _loadedBackdropUrl) return;
    _loadedPortraitUrl = p;
    _loadedBackdropUrl = b;
    // After this frame: build must not kick off a setState of its own.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final name = widget.name;
    final settings = context.read<AppSettings>();
    final art = await CoverEnricher(settings).artistArt(name);
    if (!mounted || name != widget.name) return;
    setState(() => _art = art);
    // Same as the page backdrop: a picture the user picked outranks the shape heuristic.
    final lib = context.read<LibraryStore>();
    for (final kind in const ['portrait', 'backdrop']) {
      final url = lib.chosenArtistArt(name, kind);
      if (url == null) continue;
      final bytes = await CoverEnricher(settings).downloadImage(url);
      if (!mounted || name != widget.name || bytes == null) continue;
      setState(() => kind == 'portrait' ? _chosenPortrait = bytes : _chosenBackdrop = bytes);
    }
  }

  Uint8List? _chosenPortrait, _chosenBackdrop;

  @override
  Widget build(BuildContext context) {
    _syncChoice();
    final logo = _art?.logoBytes;
    final portrait = _chosenPortrait ?? _art?.thumbBytes ?? widget.fallbackImage;
    final backdrop = _chosenBackdrop ?? _art?.backdropBytes ?? widget.fallbackImage;

    return SizedBox(
      // Room for a 270px portrait with the wordmark and buttons beside it. The backdrop is very
      // wide, so every extra pixel of height is another band of it that isn't cropped away.
      height: 400,
      // A blur paints outside its child's bounds, and the overscan pushes it further still — without
      // this the wash ran on down the page and the biography underneath was hard to read.
      child: ClipRect(
        child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred on purpose. Every artist image any database has is 16:9 — fanart, widethumb,
          // all of it — and a banner this wide can only show a quarter of one. Sharp, that quarter
          // was a gamble: it framed Michael Jackson but gave Stromae a band of forehead, because his
          // photo is a close-up that no crop can survive. So the backdrop is atmosphere drawn from
          // the artist's own colours, and the portrait beside it is what you actually recognise.
          if (backdrop != null && widget.ownBackdrop)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
              // Overscanned: a blur samples past the edges, and at 1.0 the sides faded out.
              child: Transform.scale(
                scale: 1.15,
                child: Image.memory(backdrop,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -.3),
                    errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ),
          // Dark enough at the bottom that the wordmark and buttons always read. Skipped when the
          // page already carries the wash — a second gradient on top of it just muddies the top.
          if (widget.ownBackdrop)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: .30),
                    Colors.black.withValues(alpha: .38),
                    Colors.black.withValues(alpha: .82),
                    const Color(0xFF0B0D14),
                  ],
                  stops: const [0, .40, .82, 1],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // The portrait is what makes this a page about a PERSON. A wide backdrop cropped
                // to a banner shows a horizontal slice, and whether the face is in it is luck.
                if (portrait != null) ...[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      // Lifts it off a backdrop that is, by design, the same photo's colours.
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .55), blurRadius: 28, offset: const Offset(0, 10))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(portrait,
                          width: 270,
                          height: 270,
                          fit: BoxFit.cover,
                          alignment: const Alignment(0, -.25),
                          errorBuilder: (_, __, ___) => const SizedBox()),
                    ),
                  ),
                  const SizedBox(width: 26),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (logo != null)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 96, maxWidth: 460),
                          child: Image.memory(logo,
                              fit: BoxFit.contain,
                              alignment: Alignment.centerLeft,
                              errorBuilder: (_, __, ___) => _plainName()),
                        )
                      else
                        _plainName(),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 8),
                        Text(widget.subtitle!, style: const TextStyle(color: Color(0xFFC7CBDA), fontSize: 13.5)),
                      ],
                      if (widget.actions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(children: widget.actions),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _plainName() => Text(widget.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -.5));
}

/// What this release IS: the official blurb plus year, genre, label and rating — the album
/// equivalent of a film's synopsis panel. Silent when nothing is known, so a page never shows
/// an empty box.
class AlbumInfoPanel extends StatefulWidget {
  final String artist, album;

  /// How many tracks the library holds for this album — used to reject a Discogs pressing that
  /// is really a single or a sampler filed under the same master.
  final int trackCount;

  /// The Discogs release the user pinned to this album, if any.
  final int? pinned;

  /// Or the MusicBrainz one, when they pinned there instead.
  final String? pinnedMbid;
  const AlbumInfoPanel(
      {super.key,
      required this.artist,
      required this.album,
      this.trackCount = 0,
      this.pinned,
      this.pinnedMbid});

  @override
  State<AlbumInfoPanel> createState() => _AlbumInfoPanelState();
}

class _AlbumInfoPanelState extends State<AlbumInfoPanel> {
  AlbumInfo? _info;
  DiscogsEdition? _edition;
  Uint8List? _back;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AlbumInfoPanel old) {
    super.didUpdateWidget(old);
    // The PIN counts as a change too. Without it, picking a different release of the same record
    // changed nothing here: the name stays "Adele – 30", so this saw no difference and never
    // refetched. The front cover did change, because that comes down a different path entirely —
    // which is exactly what it looked like from the outside.
    if (old.artist != widget.artist ||
        old.album != widget.album ||
        old.pinned != widget.pinned ||
        old.pinnedMbid != widget.pinnedMbid) {
      setState(() {
        _info = null;
        _edition = null;
        _back = null;
      });
      _load();
    }
  }

  Future<void> _load() async {
    final artist = widget.artist, album = widget.album;
    final settings = context.read<AppSettings>();
    // The blurb comes from TheAudioDB, which is the only one of the two that writes one. Discogs
    // knows what the record IS: which pressing, on whose label, under what catalogue number.
    final info = await CoverEnricher(settings).albumInfo(artist, album);
    if (!mounted || artist != widget.artist || album != widget.album) return;
    setState(() => _info = info);
    final discogs = DiscogsService(settings);
    final ed =
        await discogs.edition(artist, album, expectedTracks: widget.trackCount, pinned: widget.pinned).catchError((_) => null);
    if (!mounted || artist != widget.artist || album != widget.album) return;
    setState(() => _edition = ed);
    // Remember what this record sounds like. The map fills in as albums are opened, which is what
    // makes browsing by style possible without sweeping the whole library up front.
    if (ed != null && mounted) {
      unawaited(context.read<LibraryStore>().rememberStyles(artist, album, [...ed.genres, ...ed.styles]));
    }
    // The scans come off the same cached edition, so this costs nothing beyond the images.
    final art = await discogs
        .releaseArt(artist, album,
            expectedTracks: widget.trackCount, pinned: widget.pinned, pinnedMbid: widget.pinnedMbid)
        .catchError((_) => null);
    if (!mounted || artist != widget.artist || album != widget.album) return;
    setState(() => _back = art?.back);
  }

  /// "CD" reads oddly next to a year; "File" reads as nothing at all.
  static String _formatLabel(String f) => switch (f.toLowerCase()) {
        'file' => 'digitaal',
        'vinyl' => 'vinyl',
        'cd' => 'cd',
        'cdr' => 'cd-r',
        'cassette' => 'cassette',
        _ => f.toLowerCase(),
      };

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final ed = _edition;
    if (info == null && ed == null) return const SizedBox.shrink();
    // Discogs describes one specific pressing, so where the two disagree its year and label are
    // the ones that belong to the record in front of you.
    final genres = <String>{...ed?.genres ?? const [], ...ed?.styles ?? const []};
    if (genres.isEmpty) {
      if (info?.genre != null) genres.add(info!.genre!);
      if (info?.style != null) genres.add(info!.style!);
    }
    // The RECORD's year leads, not the pressing's: Demon Days is a 2005 album, even when the copy
    // being described is the 2014 digital reissue.
    final year = ed?.albumYear ?? ed?.year ?? info?.year;
    final facts = <String>[
      if (year != null) '$year',
      ...genres.take(4),
      if ((ed?.label ?? info?.label) != null) (ed?.label ?? info?.label)!,
    ];
    // The pressing itself, kept apart from the genre soup: this is the line that says WHICH copy
    // of the record the page is describing.
    final pressing = <String>[
      if (ed != null && ed.format.isNotEmpty) _formatLabel(ed.format),
      // Only when it differs from the album's own year — otherwise it just repeats the line above.
      if (ed?.year != null && ed!.year != year) '${ed.year}',
      if (ed?.catno != null && ed!.catno!.isNotEmpty && ed.catno!.toLowerCase() != 'none') ed.catno!,
      if (ed?.country != null && ed!.country!.isNotEmpty) ed.country!,
    ];
    final text = info?.text;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
      // Capped: on a maximised window the blurb would otherwise run the full 1400px, and a line
      // that long is genuinely hard to read back to the next line.
      //
      // Align first, and that is not decoration: a list hands its children a TIGHT width, and a
      // bare ConstrainedBox cannot shrink below a tight constraint — the cap silently did nothing
      // until this was added. Align loosens the constraint so the cap can take effect.
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (info?.score != null) ...[
                const Icon(Icons.star_rounded, size: 16, color: Color(0xFFE0B341)),
                const SizedBox(width: 4),
                Text(info!.score!.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
              ],
              Flexible(
                // Every style is a door. Clicking "Synth-pop" is the difference between a label on
                // a page and a way into the rest of the music that sounds like this.
                child: Wrap(spacing: 5, runSpacing: 2, children: [
                  for (var i = 0; i < facts.length; i++) ...[
                    if (i > 0) const Text('·', style: TextStyle(color: _muted, fontSize: 12.5)),
                    if (genres.contains(facts[i]))
                      InkWell(
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => StylePage(facts[i]))),
                        borderRadius: BorderRadius.circular(4),
                        child: Text(facts[i],
                            style: const TextStyle(color: _accent2, fontSize: 12.5)),
                      )
                    else
                      Text(facts[i], style: const TextStyle(color: _muted, fontSize: 12.5)),
                  ],
                ]),
              ),
            ],
          ),
          if (pressing.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.album_outlined, size: 13, color: _muted),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                    // Named, so it is always plain whether the page is describing the release YOU
                    // chose or the one the app picked for itself.
                    '${widget.pinned != null ? "Jouw uitgave" : "Uitgave"}: ${pressing.join(' · ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12)),
              ),
            ]),
          ],
          // The back of the sleeve, next to the line describing the pressing it belongs to. Click
          // to see it full size — the track list and the small print are the reason to look.
          if (_back != null) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.all(40),
                  child: InteractiveViewer(child: Image.memory(_back!)),
                ),
              ),
              borderRadius: BorderRadius.circular(6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(_back!, height: 116, fit: BoxFit.contain),
              ),
            ),
          ],
          if (text != null && text.isNotEmpty) ...[
            const SizedBox(height: 8),
            BioText('${widget.artist} — ${widget.album}', text),
          ],
        ],
        ),
        ),
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
    final ref = widget.artist.ref;
    try {
      // A MusicBrainz artist has no Deezer id, so asking Deezer for album id 0 returns nothing —
      // and this page draws an empty grid with no empty state, so it looks like a working page for
      // an artist with no records. It also has the better answer: MusicBrainz carries the regional
      // oddities and the compilations a streaming catalogue has never listed.
      if (ref.isMb) {
        final groups = await context.read<MusicBrainzService>().discographyOf(ref.id);
        if (!mounted) return;
        setState(() {
          _albums = [
            for (final g in groups)
              CatalogAlbum(0, g.title, null, g.firstDate, 0,
                  g.primaryType.toLowerCase().isEmpty ? 'album' : g.primaryType.toLowerCase(),
                  origin: CatalogRef.musicbrainzGroup(g.mbid))
          ];
          _busy = false;
        });
        return;
      }
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
      body: ArtistBackdrop(
        name: widget.artist.name,
        child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                ArtistHero(
                  name: widget.artist.name,
                  ownBackdrop: false,
                  subtitle: _busy ? 'Albums laden…' : '${_albums.length} albums',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 0, 0),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
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

  // Soulseek sources for the WHOLE album, pre-loaded in the background with ONE search when the
  // page opens — so tapping a track's download button is instant (no per-track search). Kept to
  // one search per album-open on purpose (never a per-track burst) so we don't trip the login block.
  List<SoulseekFile> _albumSlsk = [];
  bool _slskBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preloadSoulseek());
  }

  Future<void> _load() async {
    // Where this album came from decides who can describe it. The sign of the id used to say, and
    // it had run out of values — it also meant two different things at once, since a negative id
    // was a Discogs RELEASE from search but a Discogs MASTER from a style page. Feeding a master
    // to the release endpoint is why an album opened from a style page had no tracklist at all.
    final ref = widget.album.ref;
    switch (ref.source) {
      case CatalogSource.musicbrainz:
        await _loadMusicBrainzRelease(ref.id);
        return;
      case CatalogSource.musicbrainzGroup:
        await _loadMusicBrainzGroup(ref.id);
        return;
      case CatalogSource.discogsRelease:
        await _loadDiscogsRelease(ref.intId);
        return;
      case CatalogSource.discogsMaster:
        await _loadDiscogsMaster(ref.intId);
        return;
      case CatalogSource.deezer:
        break;
    }
    try {
      final (_, tracks) = await _catalog.albumTracks(widget.album.id);
      if (mounted) setState(() { _tracks = tracks; _busy = false; });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
    await _preferOfficialTracklist();
  }

  /// A record, not a pressing — so resolve its best pressing first. Only a pressing has a
  /// tracklist, and this is the single easiest way to ship a page that loads nothing.
  Future<void> _loadMusicBrainzGroup(String groupMbid) async {
    try {
      final mb = context.read<MusicBrainzService>();
      final editions = MusicBrainzService.orderByPreference(await mb.editionsOf(groupMbid));
      if (editions.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await _loadMusicBrainzRelease(editions.first.mbid);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadMusicBrainzRelease(String mbid) async {
    try {
      final e = await context.read<MusicBrainzService>().release(mbid);
      if (!mounted) return;
      setState(() {
        _tracks = [
          for (var i = 0; i < (e?.tracks.length ?? 0); i++)
            CatalogTrack(
              // No Deezer id exists for these; the index keys the row and Soulseek is searched by
              // name anyway, which is all this page does with it.
              -(i + 1),
              e!.tracks[i].title,
              widget.artistName,
              e.tracks[i].seconds ?? 0,
              i + 1,
            )
        ];
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A Discogs MASTER groups every pressing of a record and has no tracklist of its own; the style
  /// page hands these out, and they were being read as releases.
  Future<void> _loadDiscogsMaster(int masterId) async {
    try {
      final dg = DiscogsService(context.read<AppSettings>());
      final versions = DiscogsService.orderByPreference(await dg.versionsOf(masterId));
      if (versions.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await _loadDiscogsRelease(versions.first.id);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadDiscogsRelease(int releaseId) async {
    try {
      final e = await DiscogsService(context.read<AppSettings>()).release(releaseId);
      if (!mounted) return;
      setState(() {
        _tracks = [
          for (var i = 0; i < (e?.tracklist.length ?? 0); i++)
            CatalogTrack(
              // No Deezer id exists for these; the index is enough to key a row and to search
              // Soulseek with, which is all this page does with it.
              -(i + 1),
              e!.tracklist[i].title,
              widget.artistName,
              e.tracklist[i].seconds ?? 0,
              i + 1,
            )
        ];
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Replace Deezer's tracklist with the one from the pressing itself.
  ///
  /// Deezer catalogues the streaming edition, and it names tracks after whichever recording it
  /// licensed: on *Off the Wall* it lists "Rock with You (Single Version)", while the record simply
  /// has "Rock with You". Discogs describes an actual pressing, so its tracklist is the album's.
  ///
  /// Only swapped when the two agree about the SHAPE of the record — same number of tracks. A
  /// different count means a different edition, and renaming your tracks from the wrong one would
  /// be worse than leaving Deezer's names alone.
  Future<void> _preferOfficialTracklist() async {
    if (_tracks.isEmpty || !mounted) return;
    // MusicBrainz first, Discogs as the supplement. MusicBrainz needs no token, so for anyone who
    // has not entered a Discogs one this stops being a guaranteed no-op.
    var titles = <String>[], secs = <int>[];
    // Both read before the first await: after one, this widget may be gone and its context with it.
    final mb = context.read<MusicBrainzService>();
    final settings = context.read<AppSettings>();
    try {
      final hits = await mb.searchReleases(
          widget.artistName, DiscogsService.plainTitle(widget.album.title),
          expectedTracks: _tracks.length);
      if (hits.isNotEmpty) {
        final full = await mb.release(hits.first.mbid);
        final ts = full?.tracks ?? const <MbTrack>[];
        if (ts.length == _tracks.length) {
          titles = [for (final t in ts) t.title];
          secs = [for (final t in ts) t.seconds ?? 0];
          // When the RECORD came out, not when this pressing did — a 2009 reissue of a 1996 album
          // is still a 1996 album. Kept because a download has to be stamped with it, and the
          // search hit this page was opened from carries no date at all.
          _officialYear = full?.albumYear ?? full?.year;
        }
      }
    } catch (_) {/* fall through to Discogs */}

    if (titles.isEmpty) {
      try {
        final e = await DiscogsService(settings)
            .edition(widget.artistName, widget.album.title, expectedTracks: _tracks.length);
        final dg = e?.tracklist ?? const <DiscogsTrack>[];
        if (dg.length == _tracks.length) {
          titles = [for (final t in dg) t.title];
          secs = [for (final t in dg) t.seconds ?? 0];
          _officialYear = e?.albumYear ?? e?.year;
        }
      } catch (_) {/* the Deezer list is a fine fallback */}
    }
    if (!mounted || titles.length != _tracks.length) return;

    // Index-aligned, so a pressing that agrees on the COUNT but not the order would rename every
    // track after the first difference. The running times are the check that they are the same
    // record in the same order; a couple of disagreements is normal, wholesale is not.
    var wrong = 0;
    for (var i = 0; i < titles.length; i++) {
      final a = _tracks[i].durationSec, b = secs[i];
      if (a > 0 && b > 0 && (a - b).abs() > 15) wrong++;
    }
    if (wrong > titles.length / 3) return;

    setState(() {
      _tracks = [
        for (var i = 0; i < _tracks.length; i++)
          CatalogTrack(
            _tracks[i].id,
            titles[i].isEmpty ? _tracks[i].title : titles[i],
            _tracks[i].artist,
            // Keep Deezer's running time when the pressing doesn't state one.
            secs[i] > 0 ? secs[i] : _tracks[i].durationSec,
            _tracks[i].position,
          )
      ];
    });
  }

  Future<void> _preloadSoulseek() async {
    if (!mounted) return;
    final soulseek = context.read<SoulseekService>();
    if (!soulseek.available) return;
    setState(() => _slskBusy = true);
    try {
      final r = await soulseek.search('${widget.artistName} ${widget.album.title}', onPartial: (p) {
        if (mounted) setState(() => _albumSlsk = p);
      });
      if (mounted) setState(() { _albumSlsk = r; _slskBusy = false; });
    } catch (_) {
      if (mounted) setState(() => _slskBusy = false);
    }
  }

  /// Pre-loaded Soulseek copies of one track. Empty if the album-wide search didn't cover it.
  /// Deezer's running time is passed along because the title alone can't tell a track from a
  /// medley that contains it, nor from a remix of about the same length.
  List<SoulseekFile> _slskForTitle(CatalogTrack t) => _albumSlsk
      .where((f) => f.isAudio && fileOffersTitle(t.title, t.durationSec, widget.artistName, f.filename, f.durationSec))
      .toList();

  /// The copy of this track already in the library (null if we don't have it). Version markers
  /// are part of the identity, so a Live/Radio-Edit/compilation cut still counts as NOT owned.
  Track? _owned(CatalogTrack t) => context.read<LibraryStore>().ownedTrack(widget.artistName, t.title);

  /// What year the RECORD is from, according to whichever catalogue described it.
  ///
  /// Not from widget.album: a search hit carries no release date, so leaving it out meant DATE was
  /// never written and each downloaded file kept whatever year its uploader had put in — one album
  /// came out of three peers stamped 1996, 1998 and 1999.
  int? _officialYear;

  /// This album, as the official release the sources should be judged against.
  ///
  /// The tracklist here has already been through [_preferOfficialTracklist], so it is MusicBrainz's
  /// or Discogs's idea of the record rather than a streaming catalogue's — and emphatically rather
  /// than a Soulseek uploader's.
  ReleaseAuthority get _release => ReleaseAuthority(
        artist: widget.artistName,
        album: widget.album.title,
        albumArtist: widget.artistName,
        year: _officialYear ?? int.tryParse(widget.album.year ?? ''),
        tracks: [
          for (var i = 0; i < _tracks.length; i++)
            ChoiceTrack('${_numberOf(_tracks[i], i)}', _tracks[i].title, _tracks[i].durationSec)
        ],
      );

  /// This track's number on the record.
  ///
  /// Deezer's album endpoint does not return `track_position` at all — it only exists on the
  /// per-track endpoint — so every position here is 0 and the numbers on screen are really just row
  /// indexes. Taking `position` at face value filed a download as "We've Got It Goin' On.flac"
  /// with no number in front of it. The list is in release order either way, so the index IS the
  /// number whenever the catalogue declines to say.
  int _numberOf(CatalogTrack t, int i) => t.position > 0 ? t.position : i + 1;

  /// What this track IS, from the page the user is looking at.
  ///
  /// This tracklist has already been through _preferOfficialTracklist, so its titles and order come
  /// from MusicBrainz or Discogs rather than from a streaming catalogue — and certainly rather than
  /// from whichever peer serves the file. Soulseek offers this same song as "13 Anywhere for You",
  /// "19. Backstreet Boys - Anywhere For You" and "…The Essential Backstreet Boys - 01 - …";
  /// downloading any of them must still produce track 2 of this album.
  TrackTags _authorityFor(CatalogTrack t, int i) => TrackTags(
        title: t.title,
        artist: widget.artistName,
        album: widget.album.title,
        albumArtist: widget.artistName,
        trackNo: _numberOf(t, i),
        trackTotal: _tracks.length,
        year: _officialYear ?? int.tryParse(widget.album.year ?? ''),
      );

  /// Every peer copy of this track worth trying — the preload's, plus a fresh targeted search.
  ///
  /// The album-wide preload often lists a track's copies only from peers that are now offline, so
  /// a download built on it alone can report "no source" while a live copy plainly exists. A search
  /// aimed at this one track finds those live peers. Both sets are filtered to this exact title and
  /// running time, so the pool can never fill with a different song from the same user — which is
  /// what happened when the old path took every audio result the search returned and, after the
  /// query broadened to just the artist, would have downloaded the wrong song under this one's tags.
  Future<List<SoulseekFile>> _slskCandidatesForTrack(CatalogTrack t) async {
    final soulseek = context.read<SoulseekService>();
    final pool = <String, SoulseekFile>{
      for (final f in _slskForTitle(t)) '${f.username}|${f.filename}': f
    };
    try {
      final r = await soulseek.search(soulseekQuery(widget.artistName, t.title));
      for (final f in r) {
        if (!f.isAudio) continue;
        if (!fileOffersTitle(t.title, t.durationSec, widget.artistName, f.filename, f.durationSec)) {
          continue;
        }
        pool.putIfAbsent('${f.username}|${f.filename}', () => f);
      }
    } catch (_) {/* the preload's copies are still worth a try on their own */}
    return pool.values.toList();
  }

  Future<void> _downloadTrack(CatalogTrack t, int i) async {
    final dm = context.read<DownloadManager>();
    final soulseek = context.read<SoulseekService>();
    if (_owned(t) != null) {
      _srcToast(context, '“${t.title}” heb je al — niet opnieuw gedownload.');
      return;
    }
    if (!soulseek.available) {
      _srcToast(context, 'Stel je Soulseek-login in (Instellingen).');
      return;
    }
    if (mounted) _srcToast(context, 'Bron zoeken voor “${t.title}”…');
    final cands = await _slskCandidatesForTrack(t);
    if (!mounted) return;
    if (cands.isEmpty) {
      _srcToast(context, 'Geen Soulseek-bron gevonden voor “${t.title}”.');
      return;
    }
    try {
      final started = await dm.enqueueSoulseekBest(cands,
          key: 'alb:${widget.album.ref.keyPart}:$i', authority: _authorityFor(t, i));
      if (mounted) {
        _srcToast(context, started ? '“${t.title}” via Soulseek…' : '“${t.title}” loopt al — zie Mijn downloads.');
      }
    } catch (e) {
      if (mounted) _srcToast(context, 'Download mislukt: $e');
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
              child: SourcesView(query: '${widget.artistName} ${al.title}', authority: _release),
            ),
          AlbumInfoPanel(artist: widget.artistName, album: al.title),
          CreditsPanel(artist: widget.artistName, album: al.title),
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
    final soulseekReady = context.read<SoulseekService>().available;
    final srcCount = soulseekReady ? _slskForTitle(t).length : 0;
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
                    child: Text('${_numberOf(t, i)}',
                        style: const TextStyle(color: _muted, fontSize: 13))),
                // Which tracks of this record you already have — the gap in the album, at a glance.
                Builder(builder: (context) {
                  final have = context.watch<LibraryStore>().ownedTrack(widget.artistName, t.title) != null;
                  return SizedBox(
                    width: 22,
                    child: have
                        ? const Icon(Icons.check_circle_rounded, size: 14, color: _accent2)
                        : const SizedBox.shrink(),
                  );
                }),
                Expanded(
                    child: Text(t.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                // "N bronnen klaar" hint (or a tiny spinner while the album search is still running).
                if (soulseekReady && srcCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('$srcCount ⌄',
                        style: const TextStyle(color: _accent2, fontSize: 11, fontWeight: FontWeight.w600)),
                  )
                else if (soulseekReady && _slskBusy)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.6, color: _muted)),
                  ),
                Text(t.durationLabel, style: const TextStyle(color: _muted, fontSize: 12)),
                if (_owned(t) != null)
                  const Padding(
                    padding: EdgeInsets.all(9),
                    child: Tooltip(
                      message: 'Al in je bibliotheek',
                      child: Icon(Icons.library_add_check_rounded, color: _accent2, size: 19),
                    ),
                  )
                else if (soulseekReady)
                  _downloadControl(context,
                      jobKey: 'alb:${widget.album.ref.keyPart}:$i',
                      onDownload: () => _downloadTrack(t, i),
                      tooltip: 'Download via Soulseek'),
                const SizedBox(width: 2),
                Icon(open ? Icons.expand_less_rounded : Icons.travel_explore_rounded,
                    size: 18, color: open ? _accent : _muted),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SourcesView(
                query: '${widget.artistName} ${t.title}',
                authority: _release,
                track: ChoiceTrack('${_numberOf(t, i)}', t.title, t.durationSec)),
          ),
      ],
    );
  }
}

// ── Settings dialog ──────────────────────────────────────────────────────────
/// Which build is this, and where is it running from?
///
/// Read from the RUNNING executable rather than a constant in the source: a hand-maintained
/// number drifts the moment someone forgets to bump it, and the whole point here is to stop
/// guessing. The install path is shown for the same reason — a second copy left behind
/// elsewhere on disk looks identical until you can see which one you actually opened.
class _AboutSection extends StatefulWidget {
  const _AboutSection();

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  String _version = '…';
  String _path = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var version = '?';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.buildNumber.isEmpty ? info.version : '${info.version}+${info.buildNumber}';
    } catch (_) {/* fall through to the placeholder */}
    if (!mounted) return;
    setState(() {
      _version = version;
      _path = Platform.resolvedExecutable;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Info', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _accent.withValues(alpha: .35)),
              ),
              child: Text('DebridMusic $_version',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
            const SizedBox(width: 10),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 15),
              color: _muted,
              tooltip: 'Versie kopiëren',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: 'DebridMusic $_version'));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Versie gekopieerd'), duration: Duration(seconds: 2)),
                );
              },
            ),
          ],
        ),
        if (_path.isNotEmpty) ...[
          const SizedBox(height: 6),
          // Zero-width spaces after each separator: a path has no spaces, so Flutter would
          // otherwise break it after the "C:" and the rest reads as if it started at \Users.
          SelectableText(_path.replaceAll(r'\', '\\\u200B'),
              style: const TextStyle(color: _muted, fontSize: 11, height: 1.35)),
        ],
      ],
    );
  }
}

/// Sharing this library with the Mac, the iPad and the Shield.
///
/// The address and the token are the whole pairing story, so they are shown plainly and can be
/// copied — and offered as a QR code, because typing a 32-character token on a TV remote is not
/// something anyone should be asked to do.
class _SharingSection extends StatefulWidget {
  const _SharingSection();

  @override
  State<_SharingSection> createState() => _SharingSectionState();
}

class _SharingSectionState extends State<_SharingSection> {
  late final TextEditingController _root;
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    _root = TextEditingController(text: context.read<LibraryStore>().rootPath);
  }

  @override
  void dispose() {
    _root.dispose();
    super.dispose();
  }

  void _copy(String value, String what) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what gekopieerd'), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sharing = context.watch<LanSharing>();
    final settings = context.read<AppSettings>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Delen met andere apparaten',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            Switch(
              value: settings.lanEnabled,
              activeThumbColor: _accent,
              onChanged: (on) async {
                settings.lanEnabled = on;
                await settings.save();
                await sharing.applySettings();
              },
            ),
          ],
        ),
        const Text(
          'Zet dit aan en je Mac, iPad en Shield zien dezelfde bibliotheek — '
          'inclusief je eigen covers en persingen.',
          style: TextStyle(color: _muted, fontSize: 11.5, height: 1.35),
        ),
        if (settings.lanEnabled) ...[
          const SizedBox(height: 10),
          if (sharing.error != null)
            Text(sharing.error!, style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12))
          else if (!sharing.running)
            const Text('Starten…', style: TextStyle(color: _muted, fontSize: 12))
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Adres', style: TextStyle(color: _muted, fontSize: 11.5)),
                      for (final url in sharing.addresses)
                        InkWell(
                          onTap: () => _copy(url, 'Adres'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(url,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 6),
                                const Icon(Icons.copy_rounded, size: 13, color: _muted),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      const Text('Toegangscode', style: TextStyle(color: _muted, fontSize: 11.5)),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _showToken ? sharing.token : '•' * 16,
                              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(_showToken ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                size: 15),
                            color: _muted,
                            tooltip: _showToken ? 'Verbergen' : 'Tonen',
                            onPressed: () => setState(() => _showToken = !_showToken),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 15),
                            color: _muted,
                            tooltip: 'Code kopiëren',
                            onPressed: () => _copy(sharing.token, 'Toegangscode'),
                          ),
                        ],
                      ),
                      Text(
                        sharing.discoverable
                            ? 'Je apparaten vinden deze pc vanzelf.'
                            : 'Automatisch vinden lukt niet — vul het adres hierboven met de hand in.',
                        style: const TextStyle(color: _muted, fontSize: 11, height: 1.35),
                      ),
                    ],
                  ),
                ),
                if (sharing.pairingCode != null) ...[
                  const SizedBox(width: 14),
                  // White backing on purpose: a QR on a dark panel is unreadable to most scanners.
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: QrImageView(
                      data: sharing.pairingCode!,
                      size: 96,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            // Pairing by six digits, because the alternative is typing 32 hex characters on a
            // TV remote with an on-screen keyboard.
            if (sharing.pairingCodeDigits != null)
              Row(
                children: [
                  for (final digit in sharing.pairingCodeDigits!.split(''))
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: _accent.withValues(alpha: .35)),
                      ),
                      child: Text(digit,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: sharing.stopPairing,
                    style: TextButton.styleFrom(
                        foregroundColor: _muted, textStyle: const TextStyle(fontSize: 12)),
                    child: const Text('Klaar'),
                  ),
                ],
              )
            else
              Row(
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: _accent, textStyle: const TextStyle(fontSize: 12.5)),
                    onPressed: sharing.startPairing,
                    icon: const Icon(Icons.add_link_rounded, size: 16),
                    label: const Text('Apparaat koppelen'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () async {
                      final ok = await _confirmRotate();
                      if (ok) await sharing.rotateToken();
                    },
                    icon: const Icon(Icons.autorenew_rounded, size: 15),
                    label: const Text('Nieuwe toegangscode'),
                    style: TextButton.styleFrom(
                        foregroundColor: _muted, textStyle: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            if (sharing.pairingCodeDigits != null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Typ deze zes cijfers op je Shield of iPad. Vijf minuten geldig.',
                    style: TextStyle(color: _muted, fontSize: 11, height: 1.35)),
              ),
          ],
        ],
        const SizedBox(height: 12),
        const Text('Muziekmap', style: TextStyle(color: _muted, fontSize: 12.5)),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _root,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFF14161F),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: _line)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: _line)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: _accent)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () async {
                final path = _root.text.trim();
                if (path.isEmpty) return;
                final lib = context.read<LibraryStore>();
                settings.musicRoot = path;
                await settings.save();
                lib.rootPath = path;
                await lib.scan();
              },
              style: TextButton.styleFrom(foregroundColor: _accent),
              child: const Text('Opnieuw scannen'),
            ),
          ],
        ),
      ],
    );
  }

  Future<bool> _confirmRotate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('Nieuwe toegangscode?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
          'Je Mac, iPad en Shield verliezen de verbinding en moeten opnieuw gekoppeld worden.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuleren')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Vervangen'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});
  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _discogs, _torbox, _slskUser, _slskPass, _lastfm, _rtUser, _rtPass, _slskPort;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppSettings>();
    _discogs = TextEditingController(text: s.discogsToken);
    _torbox = TextEditingController(text: s.torboxToken);
    _slskUser = TextEditingController(text: s.soulseekUser);
    _slskPass = TextEditingController(text: s.soulseekPass);
    _slskPort = TextEditingController(text: s.soulseekPort > 0 ? s.soulseekPort.toString() : "");
    _lastfm = TextEditingController(text: s.lastfmKey);
    _rtUser = TextEditingController(text: s.rutrackerUser);
    _rtPass = TextEditingController(text: s.rutrackerPass);
  }

  bool _testing = false;
  bool _rtBusy = false;
  bool _tidying = false;
  String? _tidyResult;
  final Map<String, ConnResult> _conn = {};

  @override
  void dispose() {
    _discogs.dispose();
    _torbox.dispose();
    _slskUser.dispose();
    _slskPass.dispose();
    _slskPort.dispose();
    _lastfm.dispose();
    _rtUser.dispose();
    _rtPass.dispose();
    super.dispose();
  }

  /// Sort the app's download folder into Albums/Singles/Compilaties per artist and drop exact
  /// duplicate tracks (best format/size wins). Never touches the user's own collection.
  Future<void> _tidyDownloads() async {
    final lib = context.read<LibraryStore>();
    setState(() {
      _tidying = true;
      _tidyResult = null;
    });
    try {
      final root = '${lib.rootPath}${Platform.pathSeparator}DebridMusic Downloads';
      final report = await tidyDownloads(root);
      await lib.scan();
      if (mounted) setState(() => _tidyResult = 'Klaar — $report');
    } catch (e) {
      if (mounted) setState(() => _tidyResult = 'Opruimen mislukt: $e');
    } finally {
      if (mounted) setState(() => _tidying = false);
    }
  }

  /// Test the credentials as currently typed (without saving to disk).
  Future<void> _testAll() async {
    final real = context.read<AppSettings>();
    final probe = AppSettings()
      ..torboxToken = _torbox.text.trim()
      ..discogsToken = _discogs.text.trim()
      ..soulseekUser = _slskUser.text.trim()
      ..soulseekPass = _slskPass.text.trim()
      ..soulseekPort = int.tryParse(_slskPort.text.trim()) ?? 0
      ..rutrackerUser = _rtUser.text.trim()
      ..rutrackerPass = _rtPass.text
      ..rutrackerCookie = real.rutrackerCookie; // RuTracker validity depends on the live session
    // Soulseek deliberately uses the app's REAL service, not a probe copy: a probe would have its
    // own client, so testing the connection would open a SECOND login on an account that allows
    // one — kicking the live session and provoking a re-login. It also wouldn't see the app's
    // back-off, so "Test" could keep hammering an account that is already blocked.
    final checker = ConnectionChecker(probe, TorBox(() => probe.torboxToken),
        context.read<SoulseekService>(), RuTrackerService(probe));
    setState(() {
      _testing = true;
      for (final k in ['torbox', 'discogs', 'soulseek', 'rutracker']) {
        _conn[k] = const ConnResult(ConnState.checking);
      }
    });
    Future<void> run(String key, Future<ConnResult> Function() f) async {
      final r = await f();
      if (mounted) setState(() => _conn[key] = r);
    }

    await Future.wait([
      run('torbox', checker.torboxCheck),
      run('discogs', checker.discogsCheck),
      run('soulseek', checker.soulseekCheck),
      run('rutracker', checker.rutrackerCheck),
    ]);
    if (mounted) setState(() => _testing = false);
  }

  /// Log in to RuTracker (persisting the typed creds first), solving a CAPTCHA if asked.
  Future<void> _rtLogin() async {
    final settings = context.read<AppSettings>();
    final rt = context.read<OnlineService>().rutracker;
    settings.rutrackerUser = _rtUser.text.trim();
    settings.rutrackerPass = _rtPass.text;
    await settings.save();
    setState(() {
      _rtBusy = true;
      _conn['rutracker'] = const ConnResult(ConnState.checking);
    });
    try {
      var result = await rt.login();
      while (result.captcha != null && mounted) {
        final answer = await _captchaDialog(result.captcha!);
        if (answer == null || answer.isEmpty) {
          if (mounted) setState(() => _conn['rutracker'] = const ConnResult(ConnState.fail, 'Login geannuleerd'));
          return;
        }
        result = await rt.login(captchaAnswer: answer, captcha: result.captcha);
      }
      if (!mounted) return;
      setState(() => _conn['rutracker'] = result.ok
          ? ConnResult(ConnState.ok, 'Ingelogd als ${settings.rutrackerUser}')
          : ConnResult(ConnState.fail, result.error ?? 'Login mislukt'));
    } finally {
      if (mounted) setState(() => _rtBusy = false);
    }
  }

  Future<String?> _captchaDialog(RtCaptcha cap) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('RuTracker CAPTCHA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Typ de tekens uit de afbeelding over.',
                  style: TextStyle(color: _muted, fontSize: 12.5)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(6),
                color: Colors.white,
                child: Image.network(cap.imageUrl,
                    height: 72,
                    errorBuilder: (_, __, ___) =>
                        const Text('Afbeelding kon niet laden', style: TextStyle(color: Colors.black54))),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                onSubmitted: (v) => Navigator.pop(context, v.trim()),
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
            child: const Text('Verstuur'),
          ),
        ],
      ),
    );
  }

  Widget _statusRow(String label, String key, {Widget? trailing}) {
    final r = _conn[key];
    IconData icon;
    Color color;
    String text;
    switch (r?.state) {
      case ConnState.ok:
        icon = Icons.check_circle_rounded;
        color = _accent2;
        text = r!.detail;
        break;
      case ConnState.fail:
        icon = Icons.cancel_rounded;
        color = Colors.redAccent;
        text = r!.detail;
        break;
      case ConnState.absent:
        icon = Icons.remove_circle_outline_rounded;
        color = _muted;
        text = r!.detail;
        break;
      case ConnState.checking:
        icon = Icons.hourglass_top_rounded;
        color = _muted;
        text = 'Testen…';
        break;
      default:
        icon = Icons.circle_outlined;
        color = _muted;
        text = 'Nog niet getest';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          r?.state == ConnState.checking
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _muted))
              : Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          SizedBox(
              width: 84,
              child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: color))),
          if (trailing != null) trailing,
        ],
      ),
    );
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
                    _field('Soulseek luisterpoort (zelfde als de native app)', _slskPort),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                          'Zonder open poort ziet de app alleen peers die zelf bereikbaar zijn — dat is waarom '
                          'de native app soms méér vindt. Vul dezelfde poort in die SoulseekQt gebruikt (die '
                          'staat al doorgestuurd in je router) en zet er een Windows Firewall-uitzondering op.',
                          style: TextStyle(color: _muted, fontSize: 11.5)),
                    ),
                    Row(
                      children: [
                        Expanded(child: _field('RuTracker gebruiker', _rtUser)),
                        const SizedBox(width: 12),
                        Expanded(child: _field('RuTracker wachtwoord', _rtPass, obscure: true)),
                      ],
                    ),
                    _field('Last.fm API-sleutel', _lastfm),
                    const SizedBox(height: 4),
                    const Divider(color: _line, height: 1),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Verbindingen',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _testing ? null : _testAll,
                          icon: _testing
                              ? const SizedBox(
                                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _accent))
                              : const Icon(Icons.wifi_tethering_rounded, size: 16),
                          label: Text(_testing ? 'Testen…' : 'Test verbindingen'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    _statusRow('TorBox', 'torbox'),
                    _statusRow('Discogs', 'discogs'),
                    _statusRow('Soulseek', 'soulseek'),
                    _statusRow('RuTracker', 'rutracker',
                        trailing: TextButton(
                          onPressed: _rtBusy ? null : _rtLogin,
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                          child: Text(_rtBusy ? 'Bezig…' : 'Inloggen', style: const TextStyle(fontSize: 12.5)),
                        )),
                    const SizedBox(height: 10),
                    const Divider(color: _line, height: 1),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Downloads opruimen',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                              SizedBox(height: 2),
                              Text(
                                  'Sorteert je downloads in Albums / Singles / Compilaties per artiest en '
                                  'gooit dubbele nummers weg (beste kwaliteit blijft). Raakt alleen de map '
                                  '“DebridMusic Downloads” aan — je eigen collectie blijft ongemoeid.',
                                  style: TextStyle(color: _muted, fontSize: 11.5)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: _panel2, foregroundColor: Colors.white),
                          onPressed: _tidying ? null : _tidyDownloads,
                          icon: _tidying
                              ? const SizedBox(
                                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _accent))
                              : const Icon(Icons.cleaning_services_rounded, size: 16),
                          label: Text(_tidying ? 'Bezig…' : 'Opruimen'),
                        ),
                      ],
                    ),
                    if (_tidyResult != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_tidyResult!, style: TextStyle(color: _accent2, fontSize: 12)),
                      ),
                    // Tracks removed "from library only" are still on disk — offer them back.
                    Consumer<LibraryStore>(
                      builder: (_, lib, __) => lib.hiddenCount == 0
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                        '${lib.hiddenCount} nummer(s) verborgen uit je bibliotheek '
                                        '(staan nog wel op je pc).',
                                        style: const TextStyle(color: _muted, fontSize: 11.5)),
                                  ),
                                  const SizedBox(width: 10),
                                  TextButton.icon(
                                    onPressed: () => lib.restoreHidden(),
                                    icon: const Icon(Icons.undo_rounded, size: 15),
                                    label: const Text('Terugzetten'),
                                    style: TextButton.styleFrom(
                                        foregroundColor: _accent, textStyle: const TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: _line, height: 1),
                    const SizedBox(height: 12),
                    const _SharingSection(),
                    const SizedBox(height: 14),
                    const Divider(color: _line, height: 1),
                    const SizedBox(height: 12),
                    const _AboutSection(),
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
                    s.soulseekPort = int.tryParse(_slskPort.text.trim()) ?? 0;
                    s.rutrackerUser = _rtUser.text.trim();
                    s.rutrackerPass = _rtPass.text;
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

/// The album sleeve, with the disc sliding out from behind it while the record plays.
///
/// Both scans come from Discogs, which does not label them — see artwork.dart for how the disc is
/// told apart from a back cover. When there is no disc scan the sleeve simply sits there, which is
/// what every album looked like before.
class AlbumArt extends StatefulWidget {
  final String artist, album;
  final Uint8List? fallback;

  /// A sleeve the user picked by hand. It outranks anything Discogs offers — an automatic source
  /// correcting a deliberate choice is the app arguing with its owner.
  final Uint8List? chosen;
  final double size;
  final int trackCount;
  final bool playing;

  /// The Discogs release the user pinned, if any — see LibraryStore.pinnedRelease.
  final int? pinned;

  /// Or the MusicBrainz one — see LibraryStore.pinnedMbid.
  final String? pinnedMbid;
  const AlbumArt({
    super.key,
    required this.artist,
    required this.album,
    required this.size,
    this.fallback,
    this.chosen,
    this.trackCount = 0,
    this.playing = false,
    this.pinned,
    this.pinnedMbid,
  });

  @override
  State<AlbumArt> createState() => _AlbumArtState();
}

class _AlbumArtState extends State<AlbumArt> with TickerProviderStateMixin {
  ReleaseArt? _art;
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
    reverseDuration: const Duration(milliseconds: 450),
  );
  // Roughly a third of an RPM on screen — enough to read as turning, slow enough not to nag.
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 9));

  @override
  void initState() {
    super.initState();
    _load();
    _sync();
  }

  @override
  void didUpdateWidget(AlbumArt old) {
    super.didUpdateWidget(old);
    // Same as the info panel: a new pin is a new set of scans, even when the album's name is
    // unchanged. This is why the disc never followed the release you picked.
    if (old.artist != widget.artist ||
        old.album != widget.album ||
        old.pinned != widget.pinned ||
        old.pinnedMbid != widget.pinnedMbid) {
      setState(() => _art = null);
      _load();
    }
    if (old.playing != widget.playing) _sync();
  }

  void _sync() {
    if (widget.playing) {
      _slide.forward();
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _slide.reverse();
      // Left where it stopped rather than snapped back to zero: a record that stops turning
      // stops where it is.
      _spin.stop();
    }
  }

  Future<void> _load() async {
    final artist = widget.artist, album = widget.album;
    try {
      final art = await DiscogsService(context.read<AppSettings>())
          .releaseArt(artist, album,
            expectedTracks: widget.trackCount, pinned: widget.pinned, pinnedMbid: widget.pinnedMbid);
      if (!mounted || artist != widget.artist || album != widget.album) return;
      setState(() => _art = art);
      // Hand it to the library too. Without this the correction lived only on the open page: the
      // album showed the right sleeve, and going back to the grid showed the wrong one again.
      final front = art?.front;
      if (front != null && mounted) {
        context.read<LibraryStore>().adoptAlbumCover(artist, album, front);
      }
    } catch (_) {/* no artwork is not an error worth showing */}
  }

  @override
  void dispose() {
    _slide.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final front = widget.chosen ?? _art?.front ?? widget.fallback;
    final disc = _art?.disc;
    // How far the disc comes out. Started at .42 — enough to see it, not enough to enjoy it — so
    // it now clears the sleeve by a good margin while the label still sits behind the card.
    final travel = s * .62;

    final sleeve = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: front == null
          ? Container(width: s, height: s, color: _panel2, child: const Icon(Icons.album, color: _muted))
          : Image.memory(front, width: s, height: s, fit: BoxFit.cover),
    );

    if (disc == null) return sleeve;

    return SizedBox(
      width: s + travel,
      height: s,
      child: AnimatedBuilder(
        animation: Listenable.merge([_slide, _spin]),
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_slide.value);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Behind the sleeve, and drawn first so it stays there.
              Positioned(
                left: t * travel,
                top: s * .04,
                child: Transform.rotate(
                  angle: _spin.value * 6.283185,
                  child: ClipOval(
                    child: Image.memory(disc, width: s * .92, height: s * .92, fit: BoxFit.cover),
                  ),
                ),
              ),
              Positioned(left: 0, top: 0, child: sleeve),
            ],
          );
        },
      ),
    );
  }
}

/// Pick which pressing describes an album — showing, before you choose, what each one carries.
///
/// The metadata editor could already pin a release, but it listed them as bare names and said
/// nothing about their artwork. Choosing blind meant finding out afterwards that a pressing had no
/// disc scan, and the animation had nothing to spin.
class ReleaseGallery extends StatefulWidget {
  final Album album;
  const ReleaseGallery(this.album, {super.key});

  @override
  State<ReleaseGallery> createState() => _ReleaseGalleryState();
}

class _ReleaseGalleryState extends State<ReleaseGallery> {
  List<ReleaseChoice>? _choices;
  String? _error;

  /// Which source has reported in. Discogs takes far longer, so the list is live before it lands
  /// and the footer has to be able to say so.
  bool _mbDone = false, _dgDone = false, _dgFailed = false;
  bool _busy = false;

  /// Which formats to show. Everything Discogs has is fetched; this only narrows what is listed,
  /// so switching filters never costs another request.
  String _filter = 'Alles';

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// MusicBrainz first, Discogs appended — which is the order the user asked for and also the
  /// order the two can deliver in. One release-group browse names every pressing at once, so the
  /// dialog fills in about two seconds; Discogs needs a request per pressing and takes fifteen.
  ///
  /// So the list is shown as soon as MusicBrainz answers rather than waiting for both. A user
  /// staring at a spinner while a source they did not ask about finishes is the thing to avoid.
  Future<void> _load() async {
    final lib = context.read<LibraryStore>();
    final settings = context.read<AppSettings>();
    final pinnedMb = lib.pinnedMbid(widget.album);
    final pinnedDg = lib.pinnedRelease(widget.album);

    try {
      final mb = await context
          .read<MusicBrainzService>()
          .editionChoices(widget.album.artist, widget.album.title, pinnedMbid: pinnedMb);
      if (!mounted) return;
      setState(() {
        _choices = mb;
        _mbDone = true;
      });
    } catch (_) {
      if (mounted) setState(() => _mbDone = true);
    }

    // Discogs supplements: it has scans for pressings the archive has never seen. Its failures are
    // reported separately, because "Discogs is unreachable" and "this record has no pressings" are
    // very different things to be told.
    // Everything MusicBrainz found, kept aside so each progressive Discogs update can be merged
    // against it without the two lists fighting over the same variable.
    final fromMb = [...?_choices];
    void merge(List<ReleaseChoice> dg) {
      if (!mounted) return;
      final have = {for (final c in fromMb) c.dedupeKey};
      setState(() => _choices = [...fromMb, ...dg.where((c) => have.add(c.dedupeKey))]);
    }

    try {
      // The rows appear as soon as the versions listing lands — one request for a whole master —
      // and each pressing's scans fill in behind them. Waiting for all of it before showing
      // anything is what limited this to a couple of dozen after half a minute.
      await DiscogsService(settings).releaseChoices(widget.album.artist, widget.album.title,
          pinned: pinnedDg, onPartial: merge);
      if (mounted) setState(() => _dgDone = true);
    } catch (_) {
      if (mounted) setState(() { _dgDone = true; _dgFailed = true; });
    }
    if (mounted && (_choices?.isEmpty ?? true)) {
      setState(() => _error = _dgFailed
          ? 'Geen uitgaves gevonden. Discogs was niet bereikbaar, dus de aanvulling ontbreekt.'
          : 'Geen uitgaves gevonden.');
    }
  }

  Future<void> _choose(ReleaseChoice c) async {
    if (_busy) return;
    setState(() => _busy = true);
    final lib = context.read<LibraryStore>();
    final settings = context.read<AppSettings>();
    final mbSvc = context.read<MusicBrainzService>();
    try {
      Uint8List? front;
      if (c.front != null) {
        // Each catalogue serves its own images; Discogs wants its token on the request.
        front = c.isMb
            ? await mbSvc.fetchImage(c.front!.uri)
            : await DiscogsService(settings).fetchImage(c.front!.uri);
      }
      if (!mounted) return;
      await lib.applyCorrection(widget.album, settings,
          coverBytes: front,
          discogsRelease: c.isMb ? null : c.releaseId,
          mbid: c.isMb ? c.mbid : null);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      // The pin may already be on disk; saying nothing would leave the dialog dead and the button
      // spinning, which is how a failure here used to present.
      if (mounted) {
        setState(() => _busy = false);
        _srcToast(context, 'Kon deze uitgave niet toepassen.');
      }
    }
  }

  /// Take this pressing's numbering for the library's own files.
  ///
  /// Separate from choosing it, because they are different decisions: one describes the record,
  /// the other rewrites what the tracklist says. A user with correct tags wants only the first.
  Future<void> _renumber(ReleaseChoice c) async {
    final lib = context.read<LibraryStore>();
    final mbSvc = context.read<MusicBrainzService>();
    var list = c.tracklist;
    if (list.isEmpty && c.isMb && c.mbid != null) {
      // Only the first few pressings arrive with a tracklist; this one is being asked for by name.
      final full = await mbSvc.release(c.mbid!);
      if (full != null) list = await mbSvc.tracklistOf(full);
    }
    if (!mounted || list.isEmpty) {
      if (mounted) _srcToast(context, 'Deze uitgave geeft geen nummering.');
      return;
    }
    final plan = lib.planRenumber(widget.album, list);
    if (!mounted) return;
    final done = await showDialog<bool>(
        context: context, builder: (_) => RenumberDialog(album: widget.album, plan: plan));
    if (done == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    // Both, because an album pinned to a MusicBrainz pressing marked no row at all before: the
    // gallery only ever asked about the Discogs pin.
    final pinnedKey = lib.pinnedMbid(widget.album) != null
        ? 'mb:${lib.pinnedMbid(widget.album)}'
        : (lib.pinnedRelease(widget.album) != null
            ? 'dg:${lib.pinnedRelease(widget.album)}'
            : null);
    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 820,
        height: 660,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('Uitgave kiezen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop(false)),
              ]),
              Text('${widget.album.artist} — ${widget.album.title}',
                  style: const TextStyle(color: _muted, fontSize: 12.5)),
              const SizedBox(height: 14),
              // Filters over what was fetched, not another trip to Discogs.
              Row(children: [
                for (final f in const ['Alles', 'CD', 'Vinyl', 'Digitaal'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => setState(() => _filter = f),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: _filter == f ? _accent : Colors.white.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(f,
                            style: TextStyle(
                                fontSize: 12,
                                color: _filter == f ? Colors.white : _muted,
                                fontWeight: _filter == f ? FontWeight.w600 : FontWeight.w400)),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
              Expanded(child: _body(pinnedKey)),
              // MusicBrainz answers in about two seconds and Discogs in fifteen, so the list is
              // usable long before it is finished. Say which, rather than let a short list look
              // like the whole answer.
              if (_mbDone && !_dgDone)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Row(children: [
                    SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(strokeWidth: 1.6, color: _muted)),
                    SizedBox(width: 8),
                    Text('Discogs vult nog aan…', style: TextStyle(color: _muted, fontSize: 11.5)),
                  ]),
                ),
              if (_dgDone && _dgFailed)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Discogs was niet bereikbaar — dit zijn alleen de MusicBrainz-uitgaves.',
                      style: TextStyle(color: _muted, fontSize: 11.5)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(String? pinnedKey) {
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: _muted)));
    final list = _choices;
    if (list == null) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(strokeWidth: 2, color: _accent),
          SizedBox(height: 14),
          // Honest about the wait: this is several Discogs calls plus their images, and Discogs
          // allows sixty a minute.
          Text('Uitgaves en scans ophalen…', style: TextStyle(color: _muted, fontSize: 12.5)),
        ]),
      );
    }
    if (list.isEmpty) return const Center(child: Text('Geen uitgaves gevonden.', style: TextStyle(color: _muted)));
    // 'File' is what Discogs calls a digital release; nobody looking for one thinks of it that way.
    // Through the shared bucketing, not substring matching: MusicBrainz says `12" Vinyl`,
    // `Digital Media` and `Enhanced CD` where Discogs says `Vinyl` and `File`, and one rule has
    // to cover both or the filters silently hide half the list.
    final shown = _filter == 'Alles'
        ? list
        : list.where((c) {
            final m = majorFormat(c.format);
            if (_filter == 'CD') return m == 'CD' || m == 'CDr';
            if (_filter == 'Vinyl') return m == 'Vinyl';
            return m == 'File';
          }).toList();
    if (shown.isEmpty) {
      return const Center(child: Text('Geen uitgaves in dit formaat.', style: TextStyle(color: _muted)));
    }
    return ListView.separated(
      itemCount: shown.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final c = shown[i];
        final isPinned = pinnedKey != null && pinnedKey == c.key;
        return InkWell(
          onTap: () => _choose(c),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isPinned ? _accent.withValues(alpha: .16) : _panel2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isPinned ? _accent : Colors.transparent),
            ),
            child: Row(children: [
              // The three scans side by side, so what you get is visible rather than described.
              _thumb(c.front, 'hoes'),
              const SizedBox(width: 8),
              _thumb(c.back, 'achter'),
              const SizedBox(width: 8),
              _thumb(c.disc, 'cd'),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.line, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  if ((c.label ?? '').isNotEmpty)
                    Text(c.label!, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Row(children: [
                    // Which catalogue this row came from. The user asked to choose the source, so
                    // it has to be visible rather than inferred from the row's shape.
                    _source(c.isMb),
                    const SizedBox(width: 6),
                    // Until this pressing has been looked up we do not know whether it has a back
                    // or a disc, and saying "–" would be a claim we have not earned. While the
                    // batch is still running it is genuinely on its way; once it has stopped, the
                    // deeper rows simply were not opened, and the label has to say that rather
                    // than promise a spinner that will never finish.
                    if (!c.detailed) ...[
                      if (!_dgDone) ...[
                        const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.4, color: _muted)),
                        const SizedBox(width: 6),
                        const Text('scans nog ophalen…',
                            style: TextStyle(color: _muted, fontSize: 10.5)),
                      ] else
                        const Text('scans niet opgehaald — kies om te zien',
                            style: TextStyle(color: _muted, fontSize: 10.5)),
                    ] else ...[
                      _tag('achterkant', c.hasBack),
                      const SizedBox(width: 6),
                      _tag('cd-scan', c.hasDisc),
                    ],
                  ]),
                ]),
              ),
              IconButton(
                icon: const Icon(Icons.format_list_numbered_rounded, size: 19),
                tooltip: 'Nummering van deze uitgave overnemen',
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                onPressed: () => _renumber(c),
              ),
              if (isPinned) const Icon(Icons.check_circle_rounded, color: _accent, size: 20),
            ]),
          ),
        );
      },
    );
  }

  Widget _thumb(ChoiceImage? img, String label) => Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: img == null
              ? Container(
                  width: 58,
                  height: 58,
                  color: Colors.white.withValues(alpha: .04),
                  child: const Icon(Icons.close_rounded, size: 16, color: _muted))
              : _netCover(img.thumb, size: 58, radius: 6),
        ),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
      ]);

  /// Which catalogue found this pressing. The user asked to be able to choose the source, so the
  /// source has to be readable on the row rather than inferred from what the row happens to carry.
  Widget _source(bool isMb) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: (isMb ? _accent : _accent2).withValues(alpha: .18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(isMb ? 'MusicBrainz' : 'Discogs',
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w600, color: isMb ? _accent : _accent2)),
      );

  /// Present or absent, stated rather than implied — the reason this dialog exists.
  Widget _tag(String text, bool on) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: on ? _accent2.withValues(alpha: .16) : Colors.white.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(on ? Icons.check_rounded : Icons.remove_rounded, size: 11, color: on ? _accent2 : _muted),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: on ? _accent2 : _muted, fontSize: 10.5)),
        ]),
      );
}

/// Choose an artist's portrait and the backdrop behind their page.
///
/// Discogs holds dozens of photos per act (twenty-nine for Daft Punk) and TheAudioDB adds its own
/// fanart and thumbs, but neither labels what a picture is FOR. The app guesses by shape — squarish
/// reads as a portrait, wide as a backdrop — and a guess is exactly the thing worth overruling.
class ArtistArtGallery extends StatefulWidget {
  final String artist;
  const ArtistArtGallery(this.artist, {super.key});

  @override
  State<ArtistArtGallery> createState() => _ArtistArtGalleryState();
}

class _ArtistArtGalleryState extends State<ArtistArtGallery> {
  List<DiscogsImage>? _images;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = context.read<AppSettings>();
    try {
      final a = await DiscogsService(settings).artist(widget.artist);
      final extra = <DiscogsImage>[];
      // TheAudioDB's fanart is the widest thing either source has, and is usually the better
      // backdrop; Discogs almost never has anything that shape.
      final tadb = await CoverEnricher(settings).artistArt(widget.artist);
      for (final url in [tadb?.backdrop, tadb?.thumb]) {
        if (url != null && url.isNotEmpty) extra.add(DiscogsImage(url, url, 0, 0, false));
      }
      if (!mounted) return;
      setState(() => _images = [...a?.images ?? const <DiscogsImage>[], ...extra]);
    } catch (_) {
      if (mounted) setState(() => _error = 'Kon de foto\'s niet ophalen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final portrait = lib.chosenArtistArt(widget.artist, 'portrait');
    final backdrop = lib.chosenArtistArt(widget.artist, 'backdrop');
    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 860,
        height: 680,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('Foto kiezen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop()),
              ]),
              Text(widget.artist, style: const TextStyle(color: _muted, fontSize: 12.5)),
              const SizedBox(height: 4),
              const Text('Klik een foto voor het portret · rechtsklik voor de achtergrond',
                  style: TextStyle(color: _muted, fontSize: 11.5)),
              const SizedBox(height: 14),
              Expanded(child: _body(portrait, backdrop)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(String? portrait, String? backdrop) {
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: _muted)));
    final list = _images;
    if (list == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: _accent));
    }
    if (list.isEmpty) return const Center(child: Text('Geen foto\'s gevonden.', style: TextStyle(color: _muted)));
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .82),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final img = list[i];
        final isPortrait = portrait == img.uri;
        final isBackdrop = backdrop == img.uri;
        final lib = context.read<LibraryStore>();
        return GestureDetector(
          onTap: () => lib.setArtistArt(widget.artist, 'portrait', img.uri),
          onSecondaryTap: () => lib.setArtistArt(widget.artist, 'backdrop', img.uri),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: isPortrait
                      ? _accent
                      : isBackdrop
                          ? _accent2
                          : Colors.transparent,
                  width: 2),
            ),
            child: Column(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: _netCover(img.thumb, size: 150, radius: 6),
                ),
              ),
              if (isPortrait || isBackdrop)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(isPortrait ? 'portret' : 'achtergrond',
                      style: TextStyle(fontSize: 10, color: isPortrait ? _accent : _accent2)),
                ),
            ]),
          ),
        );
      },
    );
  }
}

/// Move a track into another album — showing, before anything is touched, what happens on disk.
///
/// The one operation here that rewrites the folder tree, so it states its plan first. A file that
/// can't be moved still gets regrouped: the tags are what decide where a track lives, and leaving
/// it correct-but-in-place beats refusing the whole thing.
class MoveTrackDialog extends StatefulWidget {
  final Track track;
  final Album from;
  const MoveTrackDialog({super.key, required this.track, required this.from});

  @override
  State<MoveTrackDialog> createState() => _MoveTrackDialogState();
}

class _MoveTrackDialogState extends State<MoveTrackDialog> {
  final _query = TextEditingController();
  Album? _target;
  bool _moveFiles = true;
  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final target = _target;
    if (target == null) return;
    setState(() => _busy = true);
    final moved = await context
        .read<LibraryStore>()
        .moveTracksToAlbum([widget.track], target, context.read<AppSettings>(), moveFiles: _moveFiles);
    if (!mounted) return;
    _srcToast(context, moved > 0 ? 'Verplaatst — $moved bestand mee verhuisd' : 'Verplaatst — bestand bleef staan');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final q = normKey(_query.text);
    final options = lib.albums
        .where((a) => !a.isSingle && a != widget.from)
        .where((a) => q.isEmpty || normKey('${a.artist} ${a.title}').contains(q))
        .take(40)
        .toList();
    final plan = _target == null ? const <MovePlan>[] : lib.planMove([widget.track], _target!);

    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 640,
        height: 600,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Nummer verplaatsen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(widget.track.title, style: const TextStyle(color: _muted, fontSize: 12.5)),
            const SizedBox(height: 14),
            TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Zoek een album…', isDense: true),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final a = options[i];
                  final sel = identical(_target, a);
                  return InkWell(
                    onTap: () => setState(() => _target = a),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 5),
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: sel ? _accent.withValues(alpha: .18) : _panel2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: sel ? _accent : Colors.transparent),
                      ),
                      child: Row(children: [
                        cover(a.cover, size: 34, radius: 5),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text('${a.artist} · ${a.tracks.length} nummers',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: _muted, fontSize: 11.5)),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              value: _moveFiles,
              onChanged: (v) => setState(() => _moveFiles = v ?? true),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Bestand mee verplaatsen', style: TextStyle(fontSize: 13)),
              subtitle: Text(
                // The plan, in words, before the button is pressed.
                plan.isEmpty
                    ? 'Kies eerst een album.'
                    : plan.first.movesFile
                        ? 'Naar: ${File(plan.first.to!).parent.path}'
                        : 'Doelmap onbekend — alleen de indeling verandert.',
                style: const TextStyle(color: _muted, fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuleren')),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: (_target == null || _busy) ? null : _go,
                child: _busy
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Verplaatsen'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Take an official pressing's numbering for a mistagged album — showing every change first.
///
/// Rippers get this wrong constantly: one album here arrived with two number sixes, two number
/// tens and a track with no number at all, so its tracklist could not be read or played in order.
/// The pressing knows; the tags do not. But rewriting what a user's library says about their own
/// files is not something to do silently, so the whole list is shown and collisions are refused.
class RenumberDialog extends StatefulWidget {
  final Album album;
  final RenumberPlan plan;
  const RenumberDialog({super.key, required this.album, required this.plan});

  @override
  State<RenumberDialog> createState() => _RenumberDialogState();
}

class _RenumberDialogState extends State<RenumberDialog> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    await context.read<LibraryStore>().applyRenumber(widget.plan);
    if (!mounted) return;
    _srcToast(context, 'Nummering overgenomen');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final blocked = plan.collides || plan.titleCollides;
    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 700,
        height: 620,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Nummering overnemen',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('${widget.album.artist} · ${widget.album.title}',
                style: const TextStyle(color: _muted, fontSize: 12.5)),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: blocked ? Colors.red.withValues(alpha: .12) : _panel2,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  plan.collides
                      ? 'Geweigerd: twee nummers zouden hetzelfde nummer krijgen.'
                      : plan.titleCollides
                          ? 'Geweigerd: twee nummers zouden dezelfde titel krijgen — dan verdwijnt er één uit de lijst.'
                          : plan.changing.isEmpty
                              ? 'De nummering klopt al.'
                              : '${plan.changing.length} van de ${plan.steps.length} worden aangepast · ${plan.total} nummers',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                if (plan.unmatched.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                      '${plan.unmatched.length} niet herkend op deze uitgave — die houden hun eigen tags.',
                      style: const TextStyle(color: _muted, fontSize: 11.5)),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: plan.steps.length,
                itemBuilder: (_, i) {
                  final st = plan.steps[i];
                  final was = st.track.trackNo > 0 ? '${st.track.trackNo}' : '—';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      SizedBox(
                        width: 62,
                        child: Text(st.unmatched ? '$was  ·' : '$was → ${st.newNo}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: st.changes ? FontWeight.w700 : FontWeight.w400,
                                color: st.unmatched
                                    ? _muted
                                    : st.changes
                                        ? _accent
                                        : _muted)),
                      ),
                      Expanded(
                        child: Text(
                          st.official != null && st.official!.title != st.track.title
                              ? '${st.track.title}  →  ${st.official!.title}'
                              : st.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5, color: st.unmatched ? _muted : Colors.white),
                        ),
                      ),
                    ]),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuleren')),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: (_busy || blocked || plan.changing.isEmpty) ? null : _go,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Overnemen'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Pick one album out of the library. Pops the chosen [Album], or null.
class PickAlbumDialog extends StatefulWidget {
  /// The album doing the asking — never offered as an answer to itself.
  final Album exclude;
  const PickAlbumDialog({super.key, required this.exclude});

  @override
  State<PickAlbumDialog> createState() => _PickAlbumDialogState();
}

class _PickAlbumDialogState extends State<PickAlbumDialog> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final q = normKey(_query.text);
    final options = lib.albums
        .where((a) => !a.isSingle && a != widget.exclude)
        .where((a) => q.isEmpty || normKey('${a.artist} ${a.title}').contains(q))
        .take(60)
        .toList();

    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 620,
        height: 560,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Welk album samenvoegen?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Dit album gaat op in “${widget.exclude.title}”.',
                style: const TextStyle(color: _muted, fontSize: 12.5)),
            const SizedBox(height: 14),
            TextField(
              controller: _query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Zoek een album…', isDense: true),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final a = options[i];
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(a),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 5),
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        cover(a.cover, size: 34, radius: 5),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text('${a.artist} · ${a.tracks.length} nummers',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: _muted, fontSize: 11.5)),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: () => Navigator.of(context).pop(), child: const Text('Annuleren')),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Clean up albums that are wholly duplicates of one you already own — the dry-run before it acts.
///
/// The stale fragments and junk singles the library found on its own: a "Special Edition" holding
/// three tracks that are all in the real album, an unknown-artist WAV that is really track two.
/// Nothing moves until Opruimen — and even then the loser of each pair goes to _dubbel, never the
/// bin, because the better copy is sometimes the one in the fragment.
class RedundantCleanupDialog extends StatefulWidget {
  final List<RedundantAlbum> found;
  const RedundantCleanupDialog({super.key, required this.found});

  @override
  State<RedundantCleanupDialog> createState() => _RedundantCleanupDialogState();
}

class _RedundantCleanupDialogState extends State<RedundantCleanupDialog> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    final lib = context.read<LibraryStore>();
    for (final r in widget.found) {
      await lib.consolidate(r);
    }
    if (!mounted) return;
    _srcToast(context, 'Dubbele albums opgeruimd');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final found = widget.found;
    final totalTracks = found.fold<int>(0, (n, r) => n + r.pairs.length);
    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 760,
        height: 640,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Dubbele albums opruimen',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              '${found.length} ${found.length == 1 ? 'album gaat' : 'albums gaan'} op in een album dat je al hebt · '
              '$totalTracks ${totalTracks == 1 ? 'nummer' : 'nummers'}',
              style: const TextStyle(color: _muted, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: found.length,
                itemBuilder: (_, i) {
                  final r = found[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(11),
                    decoration:
                        BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(9)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r.source.title}  →  ${r.target.title}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(
                        r.upgrades > 0
                            ? '${r.upgrades} van de ${r.pairs.length} ${r.upgrades == 1 ? 'is' : 'zijn'} beter en vervangt wat je hebt · de rest naar _dubbel'
                            : 'alle ${r.pairs.length} zijn dubbel · naar _dubbel',
                        style: const TextStyle(color: _muted, fontSize: 11.5),
                      ),
                      const SizedBox(height: 6),
                      for (final p in r.pairs)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(children: [
                            Icon(p.dupWins ? Icons.upgrade_rounded : Icons.content_copy_rounded,
                                size: 14, color: p.dupWins ? _accent : _accent2),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                p.dupWins
                                    ? '${p.owned.trackNo}. ${p.owned.title} — betere kopie behouden, oude naar _dubbel'
                                    : '${p.owned.trackNo}. ${p.owned.title} — dubbel naar _dubbel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5),
                              ),
                            ),
                          ]),
                        ),
                    ]),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuleren')),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: _busy ? null : _go,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Opruimen'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Put a record back together — showing, file by file, what that does on disk before it does it.
///
/// Two ways in. With no [absorb] it gathers the editions of ONE record that are scattered over
/// several folders. With [absorb] it swallows another album whole, the way Roon does.
///
/// The plan is the point. Merging used to change only the grouping, which left the folders exactly
/// as jumbled as before; moving files without showing the plan first is the other way to get it
/// wrong. So nothing moves until the list below has been read and confirmed.
class MergeAlbumsDialog extends StatefulWidget {
  final Album album;

  /// The album being absorbed into [album], for a Roon-style merge of two different records.
  final Album? absorb;
  const MergeAlbumsDialog({super.key, required this.album, this.absorb});

  @override
  State<MergeAlbumsDialog> createState() => _MergeAlbumsDialogState();
}

class _MergeAlbumsDialogState extends State<MergeAlbumsDialog> {
  bool _moveFiles = true;
  bool _busy = false;

  /// Worked out ONCE, when the dialog opens. Re-planning on every rebuild would read the folder
  /// again mid-run and could carry out something other than what was on screen when the user
  /// pressed the button — and it walks the disk, which has no business happening per frame.
  late final MergePlan _plan;

  @override
  void initState() {
    super.initState();
    final lib = context.read<LibraryStore>();
    _plan = widget.absorb != null
        ? MergePlan(
            widget.album.tracks.isEmpty ? null : File(widget.album.tracks.first.path).parent.path,
            lib.planMove(widget.absorb!.tracks, widget.album))
        : lib.planMerge(widget.album);
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    final lib = context.read<LibraryStore>();
    final settings = context.read<AppSettings>();
    int moved;
    if (widget.absorb != null) {
      moved = await lib.moveTracksToAlbum(widget.absorb!.tracks, widget.album, settings,
          moveFiles: _moveFiles, plan: _plan.items);
    } else {
      // Regroup first: the tags are what decide, and the user's word beats them.
      await lib.mergeEditions(widget.album);
      moved = _moveFiles ? await lib.gatherAlbumFiles(widget.album, plan: _plan.items) : 0;
    }
    if (!mounted) return;
    _srcToast(context,
        moved > 0 ? 'Samengevoegd — $moved ${moved == 1 ? 'bestand' : 'bestanden'} verhuisd' : 'Samengevoegd');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    // Only what actually happens. A screen of "blijft staan" is noise between the user and the
    // three lines they need to check.
    final acts = plan.items.where((i) => i.fate != MoveFate.stays).toList();

    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 720,
        height: 620,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.absorb == null ? 'Uitgaves samenvoegen' : 'Albums samenvoegen',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              widget.absorb == null
                  ? '${widget.album.artist} · ${widget.album.title}'
                  : '${widget.absorb!.title} → ${widget.album.title}',
              style: const TextStyle(color: _muted, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(9)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(plan.isNoop ? 'Alles staat al in één map' : plan.summary,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                if (plan.folder != null) ...[
                  const SizedBox(height: 3),
                  Text('Doelmap: ${plan.folder}',
                      style: const TextStyle(color: _muted, fontSize: 11.5)),
                ],
                if (plan.parking > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                      'Bij dezelfde bestandsnaam houdt de beste kopie de naam; de andere gaat naar '
                      '$dupeFolder. Er wordt niets gewist.',
                      style: const TextStyle(color: _muted, fontSize: 11.5)),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: acts.isEmpty
                  ? const Center(
                      child: Text('Geen enkel bestand hoeft te verhuizen.',
                          style: TextStyle(color: _muted, fontSize: 12.5)))
                  : ListView.builder(
                      itemCount: acts.length,
                      itemBuilder: (_, i) {
                        final p = acts[i];
                        final dupe = p.fate == MoveFate.toDupes;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(dupe ? Icons.content_copy_rounded : Icons.arrow_forward_rounded,
                                size: 15, color: dupe ? _accent2 : _accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child:
                                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5)),
                                Text(
                                  // Where it comes from, and the folder it lands in. The full
                                  // target path is already in the header, so only the last part is
                                  // repeated here — for a duplicate that is "_dubbel" itself.
                                  '${File(p.from).parent.path}  →  '
                                  '${p.to == null ? '—' : File(p.to!).parent.path.split(Platform.pathSeparator).last}',
                                  maxLines: 2,
                                  style: TextStyle(
                                      color: dupe ? _accent2.withValues(alpha: .85) : _muted,
                                      fontSize: 10.5),
                                ),
                              ]),
                            ),
                          ]),
                        );
                      },
                    ),
            ),
            CheckboxListTile(
              value: _moveFiles,
              onChanged: (v) => setState(() => _moveFiles = v ?? true),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Bestanden mee verplaatsen', style: TextStyle(fontSize: 13)),
              subtitle: const Text('Uit: alleen de indeling verandert, de mappen blijven zoals ze zijn.',
                  style: TextStyle(color: _muted, fontSize: 11.5)),
            ),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuleren')),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: _busy ? null : _go,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Samenvoegen'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Everything that sounds like one thing — your own records first, then more of it.
///
/// A Discogs style is much finer than a genre: not "Electronic" but "Deep House", "Synth-pop",
/// "Happy Hardcore". That granularity is what makes this browsing by feel rather than by category,
/// which is the whole point of going deeper than Deezer's handful of genres.
class StylePage extends StatefulWidget {
  final String style;
  const StylePage(this.style, {super.key});

  @override
  State<StylePage> createState() => _StylePageState();
}

class _StylePageState extends State<StylePage> {
  List<CatalogAlbumHit>? _more;

  /// False shows the records that define a style; true shows what sits behind them.
  bool _deep = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Discogs can search by style directly, which is the one thing Deezer cannot do at all.
      final hits = await DiscogsService(context.read<AppSettings>()).searchByStyle(widget.style, deep: _deep);
      if (mounted) setState(() => _more = hits);
    } catch (_) {
      if (mounted) setState(() => _more = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final mine = lib.albumsWithStyle(widget.style);
    final have = {for (final a in mine) '${artistKey(a.artist)}|${normKey(a.title)}'};
    // Anything already owned is not a discovery — it is the shelf it came from.
    final more = [
      for (final h in _more ?? const <CatalogAlbumHit>[])
        if (!have.contains('${artistKey(h.artist)}|${normKey(h.album.title)}')) h
    ];

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          backgroundColor: _bg,
          pinned: true,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).pop()),
          title: Text(widget.style, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        if (mine.isNotEmpty) ...[
          SliverToBoxAdapter(child: _sectionTitle('In mijn bibliotheek', '${mine.length}')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 175, mainAxisSpacing: 18, crossAxisSpacing: 18, childAspectRatio: .78),
              delegate: SliverChildBuilderDelegate((_, i) => AlbumCard(album: mine[i]), childCount: mine.length),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: Row(children: [
            _sectionTitle('Meer in deze stijl', _more == null ? '…' : '${more.length}'),
            const Spacer(),
            // Two ways into a style: the records that define it, or everything behind them.
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Row(children: [
                for (final d in const [false, true])
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: InkWell(
                      onTap: _deep == d
                          ? null
                          : () {
                              setState(() {
                                _deep = d;
                                _more = null;
                              });
                              _load();
                            },
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: _deep == d ? _accent : Colors.white.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(d ? 'Minder bekend' : 'Bekend',
                            style: TextStyle(
                                fontSize: 12,
                                color: _deep == d ? Colors.white : _muted,
                                fontWeight: _deep == d ? FontWeight.w600 : FontWeight.w400)),
                      ),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
        if (_more == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
            ),
          )
        else if (more.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Text('Niets nieuws gevonden in deze stijl.', style: TextStyle(color: _muted)),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 175, mainAxisSpacing: 18, crossAxisSpacing: 18, childAspectRatio: .78),
              delegate: SliverChildBuilderDelegate(
                (_, i) => _OnlineAlbumCard(more[i]),
                childCount: more.length,
              ),
            ),
          ),
      ]),
    );
  }

  Widget _sectionTitle(String t, String badge) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
        child: Row(children: [
          Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text(badge, style: const TextStyle(color: _muted, fontSize: 12.5)),
        ]),
      );
}

/// An album that isn't yours yet — tapping it opens the sources for it.
class _OnlineAlbumCard extends StatelessWidget {
  final CatalogAlbumHit hit;
  const _OnlineAlbumCard(this.hit);

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AlbumBrowsePage(hit.artist, hit.album))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _netCover(hit.album.cover, size: c.maxWidth, radius: 8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(hit.album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          Text([hit.artist, if (hit.album.year != null) hit.album.year!].join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12)),
        ]),
      );
}
