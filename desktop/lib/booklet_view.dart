import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv.dart';
import 'package:provider/provider.dart';

import 'artwork.dart' show decodeWidth;
import 'booklet.dart';
import 'discogs.dart';
import 'settings.dart';
import 'ui/kleuren.dart';

// Same four values as the album pages use. Duplicated rather than imported: main.dart already
// imports this file, and a theme constant is not worth a cycle.
const _bg = kAchtergrond;
const _panel = kPaneel;
const _muted = kGedempt;
const _accent = kAccent;

/// Paper showing where a page hasn't loaded yet.
const _paper = Color(0xFF15161C);

const _turnMs = 560;
const _crossMs = 380;

/// Finds the booklet for a record, then hands it to [BookletView].
///
/// Split in two so the reading half never depends on Discogs: [BookletView] takes a booklet
/// and a way to fetch a scan, which is all it needs, and can be driven from a cache, a test,
/// or anything else that has those two things.
class BookletScreen extends StatefulWidget {
  final String artist, album;
  final int? pinned;
  final int expectedTracks;

  const BookletScreen({
    super.key,
    required this.artist,
    required this.album,
    this.pinned,
    this.expectedTracks = 0,
  });

  @override
  State<BookletScreen> createState() => _BookletScreenState();
}

class _BookletScreenState extends State<BookletScreen> {
  Booklet? _b;
  String? _error;
  int _fetched = 0, _toFetch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _b = null;
    });
    try {
      final svc = DiscogsService(context.read<AppSettings>());
      if (!svc.available) {
        setState(
          () => _error = 'Er is geen Discogs-token ingesteld, dus er zijn geen scans op te halen.',
        );
        return;
      }
      final b = await svc.booklet(
        widget.artist,
        widget.album,
        expectedTracks: widget.expectedTracks,
        pinned: widget.pinned,
        onProgress: (done, total) {
          if (mounted) setState(() => (_fetched = done, _toFetch = total));
        },
      );
      if (!mounted) return;
      if (b == null || b.sheets.isEmpty) {
        setState(() => _error = 'Discogs heeft geen scans voor deze uitgave.');
        return;
      }
      setState(() => _b = b);
    } catch (_) {
      if (mounted) setState(() => _error = 'Kon het boekje niet ophalen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _b;
    if (b != null) {
      final svc = DiscogsService(context.read<AppSettings>());
      return BookletView(title: widget.album, booklet: b, fetch: (i) => svc.bookletFile(b, i));
    }
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text(widget.album, style: const TextStyle(fontSize: 16)),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error ?? (_toFetch > 0 ? 'Scans ophalen… $_fetched / $_toFetch' : 'Boekje zoeken…'),
              style: const TextStyle(color: _muted),
              textAlign: TextAlign.center,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(onPressed: _load, child: const Text('Opnieuw proberen')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Read a booklet a page at a time.
///
/// Two things shape this screen, both of them facts about how CD booklets are archived rather
/// than choices:
///
/// A scan is a SHEET, not a page — the booklet held open, two facing pages at once. So every
/// wide scan is windowed into halves (never cropped) and the two halves turn as one leaf.
///
/// And the sleeve front, the disc and the rear inlay are not leaves of that booklet. They get
/// the whole width, centred on the spine, and moving to or from one crosses over instead of
/// turning — see [Booklet.turns].
class BookletView extends StatefulWidget {
  final Booklet booklet;
  final String title;

  /// The full scan of a sheet, fetched and cached. Null when it can't be had — the thumbnail
  /// keeps standing in.
  final Future<File?> Function(int sheet) fetch;

  final int initialPage;

  const BookletView({
    super.key,
    required this.booklet,
    required this.fetch,
    this.title = '',
    this.initialPage = 0,
  });

  @override
  State<BookletView> createState() => _BookletViewState();
}

class _BookletViewState extends State<BookletView> with TickerProviderStateMixin {
  Booklet get _b => widget.booklet;

  /// Position, as an index into the flattened page list.
  late int _p = widget.initialPage.clamp(0, _b.pages.length - 1);

  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _turnMs),
  );
  late final AnimationController _cross = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _crossMs),
  );

  int _turnDir = 0;
  int? _turnTo;
  int? _crossFrom;
  int _crossDir = 1;

  /// Best file on disk per sheet: the thumbnail at first, the full scan once it lands.
  final Map<int, File> _file = {};
  final Set<int> _full = {};
  final Set<int> _fetching = {};

  bool _grid = false;
  int? _zoom;

  // Drag state.
  double _dragFrom = 0;
  int _dragDir = 0;
  bool _dragNoLeaf = false;

  @override
  void initState() {
    super.initState();
    _turn.addListener(() => setState(() {}));
    _cross.addListener(() => setState(() {}));
    // The thumbnails are already on disk after the booklet was built — show those at once and
    // let the full scans replace them as they arrive.
    for (var i = 0; i < _b.sheets.length; i++) {
      final t = _b.sheetFile(i, thumb: true);
      if (t.path.isNotEmpty && t.existsSync()) _file[i] = t;
    }
    _prefetch();
  }

  @override
  void dispose() {
    _turn.dispose();
    _cross.dispose();
    super.dispose();
  }

  // ── Model helpers ─────────────────────────────────────────────────────────

  List<BookletPageRef> get _pages => _b.pages;
  int get _sheet => _pages[_p].sheet;
  bool get _busy => _turn.isAnimating || _cross.isAnimating;

  bool _canGo(int dir) {
    final s = _sheet + dir;
    return s >= 0 && s < _b.sheets.length;
  }

  /// The full scan of a sheet, and of its neighbours, so a turn lands on something sharp.
  void _prefetch() {
    for (final i in [_sheet, _sheet + 1, _sheet - 1]) {
      if (i < 0 || i >= _b.sheets.length) continue;
      if (_full.contains(i) || _fetching.contains(i)) continue;
      _fetching.add(i);
      widget.fetch(i).then((f) {
        _fetching.remove(i);
        if (f == null || !mounted) return;
        setState(() {
          _file[i] = f;
          _full.add(i);
        });
      });
    }
  }

  // ── Moving ────────────────────────────────────────────────────────────────

  void _go(int dir) {
    if (_busy || !_canGo(dir)) return;
    final to = _sheet + dir;
    // With a page enlarged, the turn happens behind the overlay where nobody can see it — but it
    // HAPPENED: the arrows walked the booklet invisibly, and closing the zoom dropped you on a spread
    // you never chose. Take the zoom along instead, which is what pressing right while looking at a
    // page plainly means.
    if (_zoom != null) {
      _crossTo(to);
      setState(() => _zoom = to);
      _prefetch();
      return;
    }
    if (_b.turns(_sheet, to)) {
      _turnDir = dir;
      _turnTo = to;
      _turn.value = dir > 0 ? 0 : 1;
      _finishTurn(commit: true);
    } else {
      _crossTo(to);
    }
    _prefetch();
  }

  void _finishTurn({required bool commit}) {
    final dir = _turnDir;
    final to = commit ? (dir > 0 ? 1.0 : 0.0) : (dir > 0 ? 0.0 : 1.0);
    _turn.animateTo(to, curve: Curves.easeOutCubic).whenCompleteOrCancel(() {
      if (!mounted) return;
      setState(() {
        if (commit && _turnTo != null) _p = _b.firstPageOf(_turnTo!);
        _turnTo = null;
        _turnDir = 0;
      });
      _prefetch();
    });
  }

  void _crossTo(int sheet) {
    setState(() {
      _crossFrom = _sheet;
      _crossDir = sheet > _sheet ? 1 : -1;
      _p = _b.firstPageOf(sheet);
    });
    _cross.forward(from: 0).whenCompleteOrCancel(() {
      if (mounted) setState(() => _crossFrom = null);
    });
  }

  void _goToSheet(int sheet) {
    if (_busy || sheet == _sheet) return;
    _crossTo(sheet);
    _prefetch();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        actions: [
          Center(
            child: Text(
              '${_b.sheets[_sheet].label} · ${_p + 1} / ${_pages.length}',
              style: const TextStyle(color: _muted, fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.zoom_in_rounded),
            tooltip: 'Vergroten',
            onPressed: () => setState(() => _zoom = _sheet),
          ),
          IconButton(
            icon: Icon(Icons.grid_view_rounded, color: _grid ? _accent : null),
            tooltip: 'Overzicht',
            onPressed: () => setState(() => _grid = !_grid),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // BACK peels one layer at a time — enlargement, then overview, then the book itself.
      //
      // The enlargement and the overview are drawn INTO this screen rather than pushed as routes,
      // so Android's BACK went straight past them and closed the whole booklet. Escape already did
      // the layered thing on a keyboard; this gives the same behaviour to the button a remote user
      // actually reaches for.
      body: PopScope(
        // Only on a television. Elsewhere BACK is a keyboard's Escape (already handled below) or
        // an iPad's swipe-back gesture, and a PopScope that refuses to pop turns that gesture into
        // a dead end on a platform that never needed this.
        canPop: !isTv || (_zoom == null && !_grid),
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          setState(() {
            if (_zoom != null) {
              _zoom = null;
            } else {
              _grid = false;
            }
          });
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            children: [
              Positioned.fill(child: _stage()),
              if (_grid) Positioned.fill(child: _overview()),
              if (_zoom != null) Positioned.fill(child: _zoomView(_zoom!)),
            ],
          ),
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    // While the page overview is open, the arrows belong to the grid.
    //
    // Keys bubble from the focused thumbnail up through this Focus, so taking left and right here
    // meant the highlight could only ever walk one column: every sideways press turned a page of a
    // book you were not looking at. OK already made this exception below; the arrows need it too.
    if (_grid &&
        (e.logicalKey == LogicalKeyboardKey.arrowRight ||
            e.logicalKey == LogicalKeyboardKey.arrowLeft ||
            e.logicalKey == LogicalKeyboardKey.arrowUp ||
            e.logicalKey == LogicalKeyboardKey.arrowDown)) {
      return KeyEventResult.ignored;
    }
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.pageDown:
      case LogicalKeyboardKey.space:
      // A remote's skip-forward is the closest thing it has to "next page", and on a Shield it is
      // right under your thumb.
      case LogicalKeyboardKey.mediaTrackNext:
        _go(1);
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.pageUp:
      case LogicalKeyboardKey.mediaTrackPrevious:
        _go(-1);
      // OK on the book enlarges the page you are looking at, and OK again puts it back. The two
      // toolbar buttons above are unreachable from here — this Focus owns every key while the book
      // has the highlight — so without this a remote could turn pages and do nothing else.
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.gameButtonA:
      case LogicalKeyboardKey.enter:
        if (_grid) return KeyEventResult.ignored;
        setState(() => _zoom = _zoom == null ? _sheet : null);
      case LogicalKeyboardKey.home:
        _goToSheet(0);
      case LogicalKeyboardKey.end:
        _goToSheet(_b.sheets.length - 1);
      case LogicalKeyboardKey.escape:
        if (_zoom != null) {
          setState(() => _zoom = null);
        } else if (_grid) {
          setState(() => _grid = false);
        } else {
          Navigator.of(context).maybePop();
        }
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ── The book ──────────────────────────────────────────────────────────────

  Widget _stage() {
    return LayoutBuilder(
      builder: (context, c) {
        const pad = 26.0;
        final availW = c.maxWidth - pad * 2;
        final availH = c.maxHeight - pad * 2;
        if (availW <= 0 || availH <= 0) return const SizedBox.shrink();

        final ar = _b.pageAspect;
        final ph = math.min(availH, availW / (2 * ar));
        final pw = ph * ar;

        // While crossing, the first half of the animation still shows the sheet being left.
        final crossing = _crossFrom != null;
        final cv = _cross.value;
        final showSheet = crossing && cv < .5 ? _crossFrom! : _sheet;
        final fade = crossing ? (cv < .5 ? 1 - cv * 2 : cv * 2 - 1) : 1.0;
        final slide = crossing
            ? (cv < .5 ? -_crossDir * 22 * (cv * 2) : _crossDir * 22 * (1 - (cv * 2 - 1)))
            : 0.0;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _go(d.localPosition.dx < c.maxWidth / 2 ? -1 : 1),
          onHorizontalDragStart: (d) {
            _dragFrom = d.localPosition.dx;
            _dragDir = 0;
            _dragNoLeaf = false;
          },
          onHorizontalDragUpdate: (d) => _onDrag(d.localPosition.dx, pw),
          onHorizontalDragEnd: (d) => _onDragEnd(d.primaryVelocity ?? 0, pw),
          child: Center(
            child: Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(slide, 0),
                child: SizedBox(width: pw * 2, height: ph, child: _book(showSheet, pw, ph)),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _book(int sheet, double pw, double ph) {
    final b = _b;
    final turning = _turnTo != null;
    final t = _turn.value;

    // Staging for a turn: the leaf lifting off one sheet carries the next sheet's facing page
    // on its reverse, which is exactly what makes a real page turn read as one.
    final a = turning ? (_turnDir > 0 ? sheet : _turnTo!) : sheet;
    final z = turning ? (_turnDir > 0 ? _turnTo! : sheet) : sheet;

    final single = !b.sheets[sheet].spread && !turning;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (single)
          Positioned.fill(child: _faceOf(sheet, Half.whole, pw, ph))
        else ...[
          Positioned(left: 0, top: 0, width: pw, height: ph, child: _faceOf(a, Half.left, pw, ph)),
          Positioned(
            left: pw,
            top: 0,
            width: pw,
            height: ph,
            child: _faceOf(z, Half.right, pw, ph),
          ),
          if (!turning)
            Positioned(
              left: pw - 13,
              top: 0,
              width: 26,
              height: ph,
              child: const IgnorePointer(child: _Crease()),
            ),
          if (turning) ...[
            // Shadow the lifted leaf throws across the page it is uncovering.
            Positioned(
              left: pw,
              top: 0,
              width: pw * .34,
              height: ph,
              child: IgnorePointer(child: _Cast(alpha: (t * (1 - t) * 2.6).clamp(0.0, 1.0) * .45)),
            ),
            Positioned(
              left: pw,
              top: 0,
              width: pw,
              height: ph,
              child: IgnorePointer(child: _leaf(a, z, t, pw, ph)),
            ),
          ],
        ],
      ],
    );
  }

  /// The turning leaf: this sheet's right page on the front, the next sheet's left page on
  /// the back. Flutter has no backface-visibility, so the two faces are swapped at the
  /// halfway point and the back is mirrored — otherwise it would come round reversed.
  Widget _leaf(int a, int z, double t, double pw, double ph) {
    final front = t < .5;
    Widget child = front
        ? _faceOf(a, Half.right, pw, ph)
        : Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(math.pi),
            child: _faceOf(z, Half.left, pw, ph),
          );

    child = Stack(
      fit: StackFit.expand,
      children: [
        child,
        // Paper catching the light: the front darkens as it turns away, the back brightens as
        // it comes round.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: front ? Alignment.centerRight : Alignment.centerLeft,
              end: front ? Alignment.centerLeft : Alignment.centerRight,
              colors: [
                Colors.black.withValues(alpha: .5 * (front ? t : 1 - t)),
                Colors.transparent,
              ],
              stops: const [0, .55],
            ),
          ),
        ),
      ],
    );

    return Transform(
      alignment: Alignment.centerLeft, // the spine is the axis
      transform: Matrix4.identity()
        ..setEntry(3, 2, 1 / 2400) // perspective, vanishing point on the spine
        ..rotateY(-math.pi * t),
      child: child,
    );
  }

  /// One printed side.
  ///
  /// A half is WINDOWED out of the sheet rather than cropped: the whole scan is laid out at
  /// page height and the slot clips it, so not a pixel is resampled away. It is never allowed
  /// to be narrower than two slots — the sheets are 1.97–2.00:1 rather than exactly 2:1, and
  /// without that floor a sliver of the facing page shows at the gutter.
  Widget _faceOf(int sheet, Half half, double pw, double ph) {
    final b = _b;
    if (sheet < 0 || sheet >= b.sheets.length) return const SizedBox.shrink();
    final s = b.sheets[sheet];
    final f = _file[sheet];
    if (f == null) return const ColoredBox(color: _paper);

    // Booklet scans are routinely 2000-3000 px. Decoded whole, twelve pages is roughly 190 MB of
    // ARGB — against an image cache of 100 MB, which means guaranteed evict-and-decode-again on
    // every turn of the page. The zoom view below is the one place that still gets the full scan.
    final img = Image.file(
      f,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      cacheWidth: decodeWidth(pw * 2),
      filterQuality: FilterQuality.medium,
    );

    if (half == Half.whole) {
      // Not a leaf of the booklet — centred on the spine and bounded only by height. Nothing
      // classed single can be wider than the whole book: at 1.98 it would have been a spread.
      return Center(
        child: SizedBox(
          height: ph,
          width: math.min(ph * s.ratio, pw * 2),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 28, offset: Offset(0, 12))],
            ),
            child: Image.file(f, fit: BoxFit.contain, gaplessPlayback: true, cacheWidth: decodeWidth(pw * 2)),
          ),
        ),
      );
    }

    return ClipRect(
      child: DecoratedBox(
        decoration: const BoxDecoration(color: _paper),
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          alignment: half == Half.left ? Alignment.centerLeft : Alignment.centerRight,
          child: SizedBox(width: math.max(ph * s.ratio, pw * 2), height: ph, child: img),
        ),
      ),
    );
  }

  // ── Drag ──────────────────────────────────────────────────────────────────

  void _onDrag(double x, double pw) {
    if (_cross.isAnimating) return;
    final dx = x - _dragFrom;
    if (_dragDir == 0) {
      if (dx.abs() < 8) return;
      final dir = dx < 0 ? 1 : -1;
      if (!_canGo(dir)) return;
      _dragDir = dir;
      _dragNoLeaf = !_b.turns(_sheet, _sheet + dir);
      if (!_dragNoLeaf) {
        setState(() {
          _turnDir = dir;
          _turnTo = _sheet + dir;
          _turn.value = dir > 0 ? 0 : 1;
        });
      }
    }
    if (_dragNoLeaf) return;
    final prog = (dx.abs() / pw).clamp(0.0, 1.0);
    _turn.value = _dragDir > 0 ? prog : 1 - prog;
  }

  void _onDragEnd(double velocity, double pw) {
    if (_dragDir == 0) return;
    final dir = _dragDir;
    _dragDir = 0;
    final prog = _dragNoLeaf ? 1.0 : (dir > 0 ? _turn.value : 1 - _turn.value);
    final flung = velocity.abs() > 420 && (velocity < 0) == (dir > 0);
    if (_dragNoLeaf) {
      if (flung || prog > .32) _crossTo(_sheet + dir);
      return;
    }
    _finishTurn(commit: prog > .32 || flung);
  }

  // ── Overview ──────────────────────────────────────────────────────────────

  Widget _overview() {
    final b = _b;
    return GestureDetector(
      onTap: () => setState(() => _grid = false),
      child: ColoredBox(
        color: _bg.withValues(alpha: .97),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                childAspectRatio: 1.35,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: b.sheets.length,
              itemBuilder: (_, i) {
                final f = _file[i];
                final current = i == _sheet;
                return InkWell(
                  onTap: () {
                    setState(() => _grid = false);
                    _goToSheet(i);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: _panel,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: current ? _accent : Colors.white10),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      children: [
                        Expanded(
                          child: f == null
                              ? const ColoredBox(color: _paper)
                              // Thumbnails in the overview grid — about 260 points wide.
                              : Image.file(f, fit: BoxFit.contain, cacheWidth: decodeWidth(260)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          b.sheets[i].spread
                              ? '${b.sheets[i].label} · dubbele pagina'
                              : b.sheets[i].label,
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ── Zoom ──────────────────────────────────────────────────────────────────

  /// The whole sheet, both halves at once — at this size the spread is the point.
  Widget _zoomView(int sheet) {
    final f = _file[sheet];
    return ColoredBox(
      color: const Color(0xFF07070A),
      child: Stack(
        children: [
          Positioned.fill(
            child: f == null
                ? const SizedBox.shrink()
                : InteractiveViewer(
                    maxScale: 8,
                    child: Center(child: Image.file(f, fit: BoxFit.contain)),
                  ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
              onPressed: () => setState(() => _zoom = null),
            ),
          ),
          if (!_full.contains(sheet))
            const Positioned(
              bottom: 18,
              left: 0,
              right: 0,
              child: Center(
                child: Text('scan laden…', style: TextStyle(color: _muted, fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}

/// The crease down the middle of an open spread.
class _Crease extends StatelessWidget {
  const _Crease();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.transparent, Colors.black38, Colors.black38, Colors.transparent],
        stops: [0, .45, .55, 1],
      ),
    ),
  );
}

class _Cast extends StatelessWidget {
  final double alpha;
  const _Cast({required this.alpha});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Colors.black.withValues(alpha: alpha),
          Colors.transparent,
        ],
      ),
    ),
  );
}
