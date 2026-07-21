import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'catalog.dart';
import 'connectivity.dart';
import 'enrichment.dart';
import 'library.dart';
import 'metadata.dart';
import 'models.dart';
import 'online.dart';
import 'organize.dart';
import 'player.dart';
import 'quality.dart';
import 'recommend.dart';
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
  final player = PlayerStore()
    ..resolver = online.resolveRadio
    ..coverResolver = library.coverForTrack;
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
    await library.loadCorrections(); // apply manual fixes as tracks are built
    await library.loadHidden(); // keep "removed from library only" tracks out
    try {
      await library.scan();
    } catch (_) {}
    await library.enrich(settings);
    // Reopen the last queue where you left off (paused) — covers are loaded by now.
    await player.restore(library.trackByPath);
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
              Text(a.artist,
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
                Text(album.isSingle ? 'Single' : 'Album', style: const TextStyle(color: _muted)),
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
        );
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
                                            Text(m.artist.isEmpty ? '—' : m.artist,
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
                child: Text(t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: isCurrent ? _accent2 : _text)),
              ),
              _qualityBadge(_trackQuality(t)),
              Text(_fmt(t.duration), style: const TextStyle(color: _muted, fontSize: 13)),
              // Delete appears on hover so it can't be hit by accident.
              SizedBox(
                width: 34,
                child: _hover
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 17),
                        color: _muted,
                        tooltip: 'Nummer verwijderen',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
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
      final name = _selected!;
      final albums = _source.where((a) => a.artist == name).toList();
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(t?.artist ?? '', style: const TextStyle(color: _muted, fontSize: 15)),
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
                            Text(t.artist,
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

/// Significant words of a Soulseek filename (lowercased, no extension, no track numbers) —
/// used to recognise the SAME track offered by different peers.
Set<String> _slskWords(String displayName) {
  final noExt = displayName.toLowerCase().replaceAll(RegExp(r'\.[a-z0-9]{2,4}$'), '');
  final words = noExt.split(RegExp(r'[^a-z0-9]+')).where((w) => w.length > 1).toSet();
  words.removeWhere((w) => RegExp(r'^\d{1,3}$').hasMatch(w)); // drop bare track numbers
  return words;
}

/// Containment similarity of two word sets (0..1) — high when one filename's words are a
/// near-subset of the other's, which tolerates "01 - Everybody" vs "Artist - Everybody".
double _slskSim(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final inter = a.intersection(b).length;
  final m = a.length < b.length ? a.length : b.length;
  return inter / m;
}

/// Every peer in [all] offering the same track as [f] (including f itself), best-first.
List<SoulseekFile> _slskCandidates(List<SoulseekFile> all, SoulseekFile f) {
  final key = _slskWords(f.displayName);
  final out = all.where((o) => o.isAudio && _slskSim(key, _slskWords(o.displayName)) >= 0.8).toList();
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

Future<void> _downloadSoulseek(BuildContext context, SoulseekFile f, List<SoulseekFile> all) async {
  try {
    await context.read<DownloadManager>().enqueueSoulseekBest(_slskCandidates(all, f), key: _slskKey(f));
    if (context.mounted) _srcToast(context, '“${f.displayName}” via Soulseek…');
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
        'failed' => 'Mislukt',
        'waiting' => j.queuePlace > 0 ? 'Wacht op peer · plaats ${j.queuePlace}' : 'Wacht op peer',
        'queued' => 'In wachtrij',
        'preparing' => j.progress > 0 ? 'Voorbereiden ${(j.progress * 100).round()}%' : 'Voorbereiden',
        _ => 'Bezig ${(j.progress * 100).round()}%',
      };

  static Color statusColor(DownloadJob j) => switch (j.status) {
        'done' => _accent2,
        'failed' => Colors.redAccent,
        'waiting' => const Color(0xFFE0B341),
        _ => _accent,
      };

  static IconData statusIcon(DownloadJob j) => switch (j.status) {
        'done' => Icons.check_circle_rounded,
        'failed' => Icons.error_rounded,
        'waiting' => Icons.hourglass_top_rounded,
        'queued' => Icons.schedule_rounded,
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
              value: job.status == 'done' ? 1 : (indeterminate || job.progress <= 0 ? null : job.progress),
              backgroundColor: const Color(0xFF2A2F42),
              color: color,
            ),
          ),
          const SizedBox(width: 14),
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
    BuildContext context, List<SoulseekFile> folder, List<SoulseekFile> all) async {
  // Each folder track → its cross-peer candidates, so a busy peer for one track falls back
  // to another peer offering the same song instead of failing the whole album.
  final tracks = [for (final f in folder) _slskCandidates(all, f)];
  final n = await context.read<DownloadManager>().enqueueSoulseekAlbum(tracks);
  if (context.mounted) {
    _srcToast(context, '$n nummer(s) via Soulseek — volg de voortgang in de downloadlijst.');
  }
}

/// Soulseek section header with a "Download album" action for the best complete folder.
/// [all] is the full (unfiltered) result set — used to find fallback peers per track.
Widget _soulseekHeader(BuildContext context, List<SoulseekFile> slsk, bool busy, List<SoulseekFile> all) {
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
        ],
        if (busy) ...const [
          SizedBox(width: 8),
          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: _muted)),
        ],
        const Spacer(),
        if (folder.length >= 2)
          TextButton.icon(
            onPressed: () => _downloadSoulseekAlbum(context, folder, all),
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

Widget _soulseekTile(BuildContext context, SoulseekFile f, List<SoulseekFile> all) {
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
        _downloadControl(context, jobKey: _slskKey(f), onDownload: () => _downloadSoulseek(context, f, all)),
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
          _soulseekHeader(context, slsk, _sBusy, slsk)
        else
          const Padding(
              padding: EdgeInsets.fromLTRB(24, 14, 24, 6),
              child: Text('SOULSEEK · log in via Instellingen',
                  style: TextStyle(color: _muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6))),
        if (ready && slsk.isEmpty && !_sBusy)
          const Padding(
              padding: EdgeInsets.fromLTRB(24, 2, 24, 6),
              child: Text('Geen Soulseek-bronnen.', style: TextStyle(color: _muted, fontSize: 12.5))),
        ..._slskTiles(context, slsk),
      ],
    );
  }
}

/// Rows are built eagerly inside a plain ListView, so a broad query (3500+ hits is normal for a
/// popular track) would build every one of them on every rebuild and lock the UI. Results are
/// quality-sorted, so showing the head is no loss — and the full list is still handed to each
/// tile as its candidate pool, so downloading keeps every fallback peer.
const _slskShown = 250;

List<Widget> _slskTiles(BuildContext context, List<SoulseekFile> slsk) {
  final shown = slsk.length <= _slskShown ? slsk : slsk.sublist(0, _slskShown);
  return [
    ...shown.map((f) => _soulseekTile(context, f, slsk)),
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
                                          ? 'mislukt'
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
    try {
      final (_, tracks) = await _catalog.albumTracks(widget.album.id);
      if (mounted) setState(() { _tracks = tracks; _busy = false; });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
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

  /// Pre-loaded Soulseek copies of one track, matched by title-word overlap (title words must be
  /// (almost) all present in the filename). Empty if the album-wide search didn't cover it.
  List<SoulseekFile> _slskForTitle(String title) {
    final tw = _slskWords(title);
    if (tw.isEmpty) return const [];
    return _albumSlsk.where((f) {
      if (!f.isAudio) return false;
      final fw = _slskWords(f.displayName);
      return fw.isNotEmpty && tw.intersection(fw).length / tw.length >= 0.75;
    }).toList();
  }

  /// The copy of this track already in the library (null if we don't have it). Version markers
  /// are part of the identity, so a Live/Radio-Edit/compilation cut still counts as NOT owned.
  Track? _owned(CatalogTrack t) => context.read<LibraryStore>().ownedTrack(widget.artistName, t.title);

  Future<void> _downloadTrack(CatalogTrack t, int i) async {
    final dm = context.read<DownloadManager>();
    final soulseek = context.read<SoulseekService>();
    if (_owned(t) != null) {
      _srcToast(context, '“${t.title}” heb je al — niet opnieuw gedownload.');
      return;
    }
    var cands = _slskForTitle(t.title);
    if (cands.isEmpty) {
      // Not covered by the album-wide preload → ONE on-demand Soulseek search for just this track.
      if (mounted) _srcToast(context, 'Bron zoeken voor “${t.title}”…');
      try {
        final r = await soulseek.search('${widget.artistName} ${t.title}');
        cands = r.where((f) => f.isAudio).toList();
      } catch (_) {}
    }
    if (cands.isEmpty) {
      if (mounted) _srcToast(context, 'Geen Soulseek-bron gevonden voor “${t.title}”.');
      return;
    }
    try {
      await dm.enqueueSoulseekBest(cands, key: 'alb:${widget.album.id}:$i');
      if (mounted) _srcToast(context, '“${t.title}” via Soulseek…');
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
    final soulseekReady = context.read<SoulseekService>().available;
    final srcCount = soulseekReady ? _slskForTitle(t.title).length : 0;
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
                      jobKey: 'alb:${widget.album.id}:$i',
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
