import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'artwork.dart';
import 'discogs.dart';
import 'musicbrainz.dart';

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
/// the two apart is what makes a booklet turnable.
///
/// Which archive those scans come from decides whether there is anything to turn at all.
/// Discogs is the app's catalogue everywhere else, but its uploaders mostly scan a page at a
/// time — no sheet is ever 2:1, so nothing turns. The Cover Art Archive holds the booklet
/// opened flat far more often, and at 1200px against Discogs' ~600. So both are asked, and
/// whichever actually has facing pages wins.

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

/// Where a booklet's scans came from.
enum BookletSource { discogs, coverArtArchive }

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
  final BookletSource source;

  /// Where the scans are cached. Empty in tests that build a booklet by hand.
  final String dirPath;

  Booklet({
    required this.releaseId,
    required this.sheets,
    this.source = BookletSource.discogs,
    this.dirPath = '',
  });

  /// Sheets are what the archives store; pages are what you turn. A spread yields two.
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

  int get spreadCount => sheets.where((s) => s.spread).length;

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
    'source': source.name,
    'sheets': [for (final s in sheets) s.toJson()],
  };
}

/// Width and height straight out of the file header, without decoding the pixels.
///
/// The Cover Art Archive does not publish image dimensions, and its thumbnails keep the
/// aspect ratio of the full scan — so reading twenty bytes off each 250px thumbnail is enough
/// to know which ones are spreads, and costs nothing next to decoding them.
({int w, int h})? imageSize(Uint8List b) {
  final d = ByteData.sublistView(b);
  // PNG: IHDR is always the first chunk.
  if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return (w: d.getUint32(16), h: d.getUint32(20));
  }
  // JPEG: walk the segment markers to the first start-of-frame.
  if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
    var i = 2;
    while (i < b.length - 9) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final m = b[i + 1];
      if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
        return (w: d.getUint16(i + 7), h: d.getUint16(i + 5));
      }
      final len = d.getUint16(i + 2);
      if (len < 2) return null;
      i += 2 + len;
    }
  }
  return null;
}

/// Which archive to read the booklet from.
///
/// The whole difference between a booklet you can turn and a stack of pictures is whether the
/// scans are facing pages, so that is what decides it. On a tie the Cover Art Archive wins —
/// same pages, twice the resolution. When NEITHER has a spread, Discogs stays: the page turn
/// is off the table either way, and its scans are the pressing the user pinned.
bool preferCoverArtArchive({
  required int caaSheets,
  required int caaSpreads,
  required int discogsSheets,
  required int discogsSpreads,
}) {
  if (caaSheets == 0) return false;
  if (discogsSheets == 0) return true;
  if (caaSpreads != discogsSpreads) return caaSpreads > discogsSpreads;
  return caaSpreads > 0;
}

/// The Cover Art Archive's scans for this very pressing, sized and ready to compare.
///
/// [barcode] is what makes this a match rather than a guess: it names the physical product, so
/// the pages are the ones in the case on the shelf. Catalogue number is the next best key.
/// With neither, the best-ranked pressing of the record is used, and that really can be a
/// different edition — a risk worth taking only because the alternative is no booklet at all.
///
/// Goes through [MusicBrainzService], which already serialises, spaces and disk-caches both
/// the webservice and the archive.
Future<List<BookletSheet>> coverArtSheets(
  MusicBrainzService mb, {
  String? barcode,
  String? catno,
  required String artist,
  required String album,
  int expectedTracks = 0,
}) async {
  final releases = await mb.searchReleases(artist, album, expectedTracks: expectedTracks);
  if (releases.isEmpty) return const [];

  String norm(String? s) => (s ?? '').replaceAll(RegExp('[^0-9a-zA-Z]'), '').toLowerCase();
  final bc = norm(barcode), cn = norm(catno);
  final ordered = <MbRelease>[
    if (bc.isNotEmpty) ...releases.where((r) => norm(r.barcode) == bc),
    if (cn.isNotEmpty) ...releases.where((r) => norm(r.catno) == cn),
    ...releases,
  ];

  // Which pressing had its booklet scanned OPEN. This has to be measured, and *Bad* is
  // exactly why: three MusicBrainz releases carry that barcode, and only one of them has the
  // booklet as facing pages — the others were scanned a page at a time. A `Booklet` type says
  // what a scan depicts, never what shape it is, so going by the label picks a page-by-page
  // pressing and the booklet never turns.
  var best = const <MbImage>[];
  var bestSpreads = -1;
  final seen = <String>{};
  for (final r in ordered) {
    if (!seen.add(r.mbid)) continue;
    if (seen.length > 3) break;
    final images = await mb.art(r.mbid);
    if (images.isEmpty) continue;
    final n = await _spreadsAmongBooklets(images);
    if (n > bestSpreads) {
      bestSpreads = n;
      best = images;
    }
    if (n > 0) break; // scanned open — no need to price the alternatives
  }
  if (best.isEmpty) return const [];

  return sizedFromThumbnails([
    for (final i in best)
      BookletSheet(uri: i.full, thumbUri: i.thumb, width: 0, height: 0, kind: _kindOf(i)),
  ]);
}

/// How many of a pressing's booklet scans are facing pages.
///
/// Only the booklet scans are measured, and only the first handful: this runs once per
/// candidate pressing purely to choose between them, and the winner gets measured in full
/// afterwards. A sleeve front would never be 2:1, so there is nothing to learn from it here.
Future<int> _spreadsAmongBooklets(List<MbImage> images) async {
  var n = 0;
  final booklets = [
    for (final i in images)
      if (i.types.any((t) => t.toLowerCase() == 'booklet')) i,
  ];
  for (final i in booklets.take(6)) {
    final bytes = await _plainGet(i.thumb);
    final size = bytes == null ? null : imageSize(bytes);
    if (size != null && size.h > 0 && size.w / size.h >= kSpreadRatio) n++;
  }
  return n;
}

/// Unlike Discogs, this archive labels what a scan depicts, so the captions come straight from
/// it and there is nothing to work out from the pixels.
SheetKind _kindOf(MbImage i) {
  if (i.isFront) return SheetKind.front;
  if (i.isBack) return SheetKind.back;
  if (i.isDisc) return SheetKind.disc;
  final t = [for (final x in i.types) x.toLowerCase()];
  if (t.contains('booklet') || t.contains('tray')) return SheetKind.booklet;
  return SheetKind.other;
}

/// Fill in each scan's dimensions by reading the header of its thumbnail.
///
/// The archive's thumbnails keep the aspect ratio of the full scan, so a 250px copy is enough
/// to tell a 2:1 sheet from a single page. A scan whose thumbnail can't be had keeps zero,
/// which simply means it is not treated as a spread.
Future<List<BookletSheet>> sizedFromThumbnails(
  List<BookletSheet> sheets, {
  Future<Uint8List?> Function(String url)? get,
}) async {
  final fetch = get ?? _plainGet;
  final out = <BookletSheet>[];
  for (final s in sheets) {
    final bytes = await fetch(s.thumbUri);
    final size = bytes == null ? null : imageSize(bytes);
    out.add(
      size == null
          ? s
          : BookletSheet(
              uri: s.uri,
              thumbUri: s.thumbUri,
              width: size.w,
              height: size.h,
              kind: s.kind,
            ),
    );
  }
  return out;
}

/// One retry, because a thumbnail that doesn't arrive costs more than a lost picture: an
/// unmeasured sheet counts as a single page, and a single page in the middle of a booklet
/// breaks the run of page turns around it. Seen for real against the archive — one scan in
/// thirteen came back empty on a first pass.
Future<Uint8List?> _plainGet(String url) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    if (attempt > 0) await Future<void>.delayed(const Duration(milliseconds: 400));
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (r.statusCode == 200 && r.bodyBytes.length > 500) return r.bodyBytes;
    } catch (_) {
      /* fall through to the retry */
    }
  }
  return null;
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
  /// Only the thumbnails are fetched here — enough to fill the overview, to stand in while a
  /// page loads, to measure which scans are spreads, and for [assignRoles] to spot the disc.
  /// Full scans come later, per page.
  Future<Booklet?> booklet(
    String artist,
    String album, {
    int expectedTracks = 0,
    int? pinned,
    void Function(int done, int total)? onProgress,
  }) async {
    // v2 in the key: booklets cached before the Cover Art Archive was consulted would
    // otherwise keep answering with the Discogs-only version forever.
    final key = sha1.convert(utf8.encode('booklet2|$artist|$album|${pinned ?? 0}')).toString();
    final dir = Directory('$bookletDir${Platform.pathSeparator}$key');

    final cached = await _readBooklet(dir);
    if (cached != null) return cached;

    final e = await edition(artist, album, expectedTracks: expectedTracks, pinned: pinned);

    // What Discogs has for the pinned pressing. Dimensions come with the metadata, so which
    // scans are spreads is already known — no download needed to find out.
    final discogs = <BookletSheet>[
      for (final im in e?.images ?? const <DiscogsImage>[])
        BookletSheet(
          uri: im.uri,
          thumbUri: im.thumb,
          width: im.width,
          height: im.height,
          kind: SheetKind.other,
        ),
    ];
    final primary = [for (final im in e?.images ?? const <DiscogsImage>[]) im.primary];

    final caa = await _caaFor(e, artist, album);

    final useCaa = preferCoverArtArchive(
      caaSheets: caa.length,
      caaSpreads: caa.where((s) => s.spread).length,
      discogsSheets: discogs.length,
      discogsSpreads: discogs.where((s) => s.spread).length,
    );

    var sheets = useCaa ? caa : discogs;
    if (sheets.isEmpty) return null;

    final thumbs = <Uint8List?>[];
    for (var i = 0; i < sheets.length; i++) {
      thumbs.add(await _grab(sheets[i].thumbUri, viaDiscogs: !useCaa));
      onProgress?.call(i + 1, sheets.length);
    }

    if (!useCaa) {
      // Discogs says only "primary" or "secondary", so which scan is the back and which is
      // the disc has to come out of the pixels — the same problem the album page solved.
      // The thumbnails are plenty: looksLikeDisc resizes to 64×64 before it looks.
      final roles = assignRoles(primary, [for (final s in sheets) s.ratio], thumbs);
      sheets = [
        for (var i = 0; i < sheets.length; i++)
          BookletSheet(
            uri: sheets[i].uri,
            thumbUri: sheets[i].thumbUri,
            width: sheets[i].width,
            height: sheets[i].height,
            kind: i == roles.front
                ? SheetKind.front
                : i == roles.disc
                ? SheetKind.disc
                : i == roles.back
                ? SheetKind.back
                : sheets[i].spread
                ? SheetKind.booklet
                : SheetKind.other,
          ),
      ];
      // Order is whoever uploaded them, so it is left alone — reordering would be guesswork,
      // and a booklet read out of order is worse than one that starts in the middle. The one
      // exception is a fact rather than a guess: Discogs marks the front explicitly.
      final front = roles.front;
      if (front != null && front > 0) {
        sheets.insert(0, sheets.removeAt(front));
        thumbs.insert(0, thumbs.removeAt(front));
      }
    }

    final b = Booklet(
      releaseId: e?.releaseId ?? 0,
      source: useCaa ? BookletSource.coverArtArchive : BookletSource.discogs,
      dirPath: dir.path,
      sheets: sheets,
    );
    await _writeBooklet(dir, b, thumbs);
    return b;
  }

  /// The Cover Art Archive's scans for this very pressing, sized and ready to compare.
  ///
  /// Empty whenever the record can't be matched or the archive has nothing, in which case the
  /// caller simply keeps what Discogs gave it.
  Future<List<BookletSheet>> _caaFor(DiscogsEdition? e, String artist, String album) async {
    return coverArtSheets(
      MusicBrainzService(),
      barcode: e?.barcode,
      catno: e?.catno,
      artist: artist,
      album: album,
    );
  }

  /// Discogs images need the app's token; the Cover Art Archive is open.
  Future<Uint8List?> _grab(String url, {required bool viaDiscogs}) async {
    if (viaDiscogs) return fetchImage(url);
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      return r.statusCode == 200 && r.bodyBytes.length > 500 ? r.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  /// The file for one scan, fetched if it isn't cached yet. Null if it can't be had.
  Future<File?> bookletFile(Booklet b, int sheet, {bool thumb = false}) async {
    if (sheet < 0 || sheet >= b.sheets.length || b.dirPath.isEmpty) return null;
    final f = b.sheetFile(sheet, thumb: thumb);
    if (await f.exists()) return f;
    final url = thumb ? b.sheets[sheet].thumbUri : b.sheets[sheet].uri;
    final bytes = await _grab(url, viaDiscogs: b.source == BookletSource.discogs);
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
        source: BookletSource.values.firstWhere(
          (v) => v.name == j['source'],
          orElse: () => BookletSource.discogs,
        ),
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
