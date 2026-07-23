import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'artwork.dart';
import 'discogs.dart';

/// The booklet that came in the jewel case, page by page.
///
/// The album page shows three scans — sleeve, back, disc — and [DiscogsArtwork.releaseArt]
/// deliberately stops after six images, because pulling thirty to answer "which one is the
/// disc" would cost megabytes. This is the other half of that trade: when the user actually
/// asks to read the booklet, every scan is fair game.
///
/// A CD booklet is not photographed page by page. Each scan is a SHEET — the booklet held
/// open, two facing pages at once. Michael Jackson's *Bad* has eight of them at 1.97–2.00:1
/// plus three singles (sleeve front, disc, rear inlay): eleven scans, nineteen pages. Telling
/// the two apart is what makes a booklet turnable, and Discogs gives width and height in the
/// release metadata — so it costs nothing to know before a single byte is downloaded.

/// Wide enough to be two pages side by side.
///
/// Real sheets measure 1.97–2.00. A rear inlay wrapping the spine of a jewel case reaches
/// about 1.26, so there is a wide gap to sit in. Note this is NOT [DiscogsImage.isWide]
/// (1.4), which answers a different question — whether a scan can sit behind a page as a
/// backdrop — and would call that rear inlay a spread.
const double kSpreadRatio = 1.7;

/// Which side of a sheet a page is. [whole] is an unsplit scan.
enum Half { left, right, whole }

enum SheetKind { front, back, disc, booklet, other }

const _kindNames = {
  SheetKind.front: 'Voorkant',
  SheetKind.back: 'Achterkant',
  SheetKind.disc: 'Cd',
  SheetKind.booklet: 'Boekje',
  SheetKind.other: 'Scan',
};

class BookletSheet {
  final String uri, thumbUri;
  final int width, height;
  final SheetKind kind;

  const BookletSheet({
    required this.uri,
    required this.thumbUri,
    required this.width,
    required this.height,
    required this.kind,
  });

  double get ratio => height == 0 ? 1 : width / height;
  bool get spread => ratio >= kSpreadRatio;
  String get label => _kindNames[kind] ?? 'Scan';

  Map<String, dynamic> toJson() => {
    'uri': uri,
    'thumbUri': thumbUri,
    'width': width,
    'height': height,
    'kind': kind.name,
  };

  static BookletSheet fromJson(Map<String, dynamic> j) => BookletSheet(
    uri: j['uri'] as String? ?? '',
    thumbUri: j['thumbUri'] as String? ?? '',
    width: (j['width'] as num?)?.toInt() ?? 0,
    height: (j['height'] as num?)?.toInt() ?? 0,
    kind: SheetKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => SheetKind.other),
  );
}

/// One turnable page: a sheet, and which half of it.
class BookletPageRef {
  final int sheet;
  final Half half;
  const BookletPageRef(this.sheet, this.half);
}

class Booklet {
  final int releaseId;
  final List<BookletSheet> sheets;

  /// Where the scans are cached. Empty in tests that build a booklet by hand.
  final String dirPath;

  Booklet({required this.releaseId, required this.sheets, this.dirPath = ''});

  /// Sheets are what Discogs stores; pages are what you turn. A spread yields two.
  List<BookletPageRef> get pages {
    final out = <BookletPageRef>[];
    for (var i = 0; i < sheets.length; i++) {
      if (sheets[i].spread) {
        out.add(BookletPageRef(i, Half.left));
        out.add(BookletPageRef(i, Half.right));
      } else {
        out.add(BookletPageRef(i, Half.whole));
      }
    }
    return out;
  }

  int firstPageOf(int sheet) {
    final p = pages;
    for (var i = 0; i < p.length; i++) {
      if (p[i].sheet == sheet) return i;
    }
    return 0;
  }

  /// Width over height of one page slot.
  ///
  /// Every slot in the book shares it, so the geometry stays put while a leaf turns between
  /// sheets whose ratios differ by a percent or two. Taken from the spreads when there are
  /// any — they are what the reader spends the time on.
  double get pageAspect {
    final pool = <double>[
      for (final s in sheets)
        if (s.spread) s.ratio / 2,
    ];
    if (pool.isEmpty) pool.addAll(sheets.map((s) => s.ratio));
    if (pool.isEmpty) return 1;
    pool.sort();
    return pool[pool.length ~/ 2];
  }

  /// A page turn only means something between two spreads.
  ///
  /// A leaf has a front and a back — that is what makes it a leaf. The sleeve front, the disc
  /// and the rear inlay are separate objects, and they are drawn centred on the spine, which
  /// is the axis a leaf rotates around; turning one tears it down the middle. Those steps
  /// cross over instead.
  bool turns(int from, int to) {
    if (from < 0 || to < 0 || from >= sheets.length || to >= sheets.length) return false;
    return sheets[from].spread && sheets[to].spread;
  }

  File sheetFile(int i, {bool thumb = false}) =>
      File('$dirPath${Platform.pathSeparator}${i.toString().padLeft(2, '0')}${thumb ? 't' : ''}');

  Map<String, dynamic> toJson() => {
    'releaseId': releaseId,
    'sheets': [for (final s in sheets) s.toJson()],
  };
}

extension DiscogsBooklet on DiscogsService {
  String get bookletDir =>
      '${Platform.environment['APPDATA'] ?? Directory.current.path}${Platform.pathSeparator}DebridMusic'
      '${Platform.pathSeparator}booklets';

  /// Every scan of a pressing, with the thumbnails already on disk.
  ///
  /// [pinned] is the release the user chose in the picker, kept in the corrections file. It
  /// matters more here than anywhere else: a booklet is only worth reading if it is the
  /// booklet of the record on the shelf, and guessing a pressing would quietly show pages
  /// from a different edition.
  ///
  /// Only the 150px thumbnails are fetched here — enough to fill the overview, to stand in
  /// while a page loads, and to identify the disc. Full scans come later, per page.
  Future<Booklet?> booklet(
    String artist,
    String album, {
    int expectedTracks = 0,
    int? pinned,
    void Function(int done, int total)? onProgress,
  }) async {
    final key = sha1.convert(utf8.encode('booklet|$artist|$album|${pinned ?? 0}')).toString();
    final dir = Directory('$bookletDir${Platform.pathSeparator}$key');

    final cached = await _readBooklet(dir);
    if (cached != null) return cached;

    final e = await edition(artist, album, expectedTracks: expectedTracks, pinned: pinned);
    if (e == null || e.images.isEmpty) return null;

    final total = e.images.length;
    final thumbs = <Uint8List?>[];
    for (var i = 0; i < total; i++) {
      thumbs.add(await fetchImage(e.images[i].thumb));
      onProgress?.call(i + 1, total);
    }

    // Discogs says only "primary" or "secondary", so which scan is the back and which is the
    // disc has to come out of the pixels — the same problem the album page already solved.
    // The 150px thumbnails are plenty: looksLikeDisc resizes to 64×64 before it looks.
    final roles = assignRoles(
      [for (final im in e.images) im.primary],
      [for (final im in e.images) im.height == 0 ? 1.0 : im.width / im.height],
      thumbs,
    );

    final sheets = <BookletSheet>[];
    for (var i = 0; i < total; i++) {
      final im = e.images[i];
      final ratio = im.height == 0 ? 1.0 : im.width / im.height;
      sheets.add(
        BookletSheet(
          uri: im.uri,
          thumbUri: im.thumb,
          width: im.width,
          height: im.height,
          kind: i == roles.front
              ? SheetKind.front
              : i == roles.disc
              ? SheetKind.disc
              : i == roles.back
              ? SheetKind.back
              : ratio >= kSpreadRatio
              ? SheetKind.booklet
              : SheetKind.other,
        ),
      );
    }

    // Discogs image order is whoever uploaded them, so it is left alone — reordering would be
    // guesswork, and a booklet read out of order is worse than one that starts in the middle.
    // The one exception is a fact rather than a guess: Discogs marks the front explicitly.
    final front = roles.front;
    if (front != null && front > 0) {
      sheets.insert(0, sheets.removeAt(front));
      thumbs.insert(0, thumbs.removeAt(front));
    }

    final b = Booklet(releaseId: e.releaseId, sheets: sheets, dirPath: dir.path);
    await _writeBooklet(dir, b, thumbs);
    return b;
  }

  /// The file for one scan, fetched if it isn't cached yet. Null if it can't be had.
  Future<File?> bookletFile(Booklet b, int sheet, {bool thumb = false}) async {
    if (sheet < 0 || sheet >= b.sheets.length || b.dirPath.isEmpty) return null;
    final f = b.sheetFile(sheet, thumb: thumb);
    if (await f.exists()) return f;
    final bytes = await fetchImage(thumb ? b.sheets[sheet].thumbUri : b.sheets[sheet].uri);
    if (bytes == null) return null;
    try {
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes);
    } catch (_) {
      return null;
    }
    return f;
  }

  Future<Booklet?> _readBooklet(Directory dir) async {
    try {
      final f = File('${dir.path}${Platform.pathSeparator}manifest.json');
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map<String, dynamic>) return null;
      final sheets = [
        for (final s in (j['sheets'] as List<dynamic>? ?? const []))
          BookletSheet.fromJson(s as Map<String, dynamic>),
      ];
      if (sheets.isEmpty) return null;
      return Booklet(
        releaseId: (j['releaseId'] as num?)?.toInt() ?? 0,
        sheets: sheets,
        dirPath: dir.path,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeBooklet(Directory dir, Booklet b, List<Uint8List?> thumbs) async {
    try {
      await dir.create(recursive: true);
      for (var i = 0; i < thumbs.length && i < b.sheets.length; i++) {
        final t = thumbs[i];
        if (t != null) await b.sheetFile(i, thumb: true).writeAsBytes(t);
      }
      await File(
        '${dir.path}${Platform.pathSeparator}manifest.json',
      ).writeAsString(jsonEncode(b.toJson()));
    } catch (_) {
      /* a cache that can't be written is not worth failing over */
    }
  }
}
