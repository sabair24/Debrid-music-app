import 'dart:typed_data';

import 'package:debridmusic/artwork.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Telling a scan of the disc apart from a scan of the sleeve.
///
/// Discogs labels one image "primary" and calls everything else "secondary" — back cover, disc,
/// inlay, booklet, all the same word. The disc has to be identified from the pixels, because it is
/// the one that slides out from behind the cover when the record plays, and sliding out a back
/// cover would just look broken.
Uint8List _png(img.Image im) => Uint8List.fromList(img.encodePng(im));

/// A disc: white surround, dark printed face, white hole in the middle.
img.Image _disc({int face = 20, int surround = 250}) {
  final im = img.Image(width: 300, height: 300);
  img.fill(im, color: img.ColorRgb8(surround, surround, surround));
  img.fillCircle(im, x: 150, y: 150, radius: 145, color: img.ColorRgb8(face, face, face));
  img.fillCircle(im, x: 150, y: 150, radius: 22, color: img.ColorRgb8(surround, surround, surround));
  return im;
}

/// A sleeve: printing to all four edges.
img.Image _sleeve(int shade) {
  final im = img.Image(width: 300, height: 300);
  img.fill(im, color: img.ColorRgb8(shade, shade, shade));
  return im;
}

void main() {
  test('a dark disc on a white bed is a disc', () {
    // Dangerous: black disc, gold print, white surround, white hole.
    expect(looksLikeDisc(_png(_disc())), isTrue);
  });

  test('a dark back cover is not', () {
    // The Dangerous back cover is black to all four edges.
    expect(looksLikeDisc(_png(_sleeve(15))), isFalse);
  });

  test('a light back cover is not either', () {
    expect(looksLikeDisc(_png(_sleeve(245))), isFalse, reason: 'pale corners alone are not a disc');
  });

  test('a picture disc — printed edge to edge, no white surround — is not claimed', () {
    final im = _disc(surround: 30, face: 200);
    expect(looksLikeDisc(_png(im)), isFalse,
        reason: 'better to skip the animation than to spin the wrong picture');
  });

  test('the primary image is the front, whatever it looks like', () {
    expect(guessKind(0, true, _png(_disc())), ArtKind.front);
  });

  test('a disc is recognised wherever it sits in the list', () {
    expect(guessKind(3, false, _png(_disc())), ArtKind.disc);
  });

  test('the first secondary is taken for the back cover', () {
    expect(guessKind(1, false, _png(_sleeve(15))), ArtKind.back);
  });

  test('later secondaries are booklet pages and stay unassigned', () {
    expect(guessKind(4, false, _png(_sleeve(15))), ArtKind.other);
  });

  test('unreadable bytes never crash the page', () {
    expect(looksLikeDisc(Uint8List.fromList([1, 2, 3])), isFalse);
  });

  group('assigning roles across a whole release', () {
    test('Dangerous: front, the wide inlay, and the first disc of three candidates', () {
      // 31 scans, three of which read as a disc: the CD and two booklet pages with pale margins.
      // The back inlay is the one that is wider than tall — 600x474 among a stack of 600x598.
      final primary = [true, false, false, false, false];
      final ratios = [600 / 593, 600 / 474, 600 / 599, 600 / 598, 600 / 598];
      final datas = <Uint8List?>[
        _png(_sleeve(60)),
        _png(_sleeve(15)),
        _png(_disc()),
        _png(_sleeve(200)),
        _png(_disc()), // a second disc-like scan further down
      ];
      final r = assignRoles(primary, ratios, datas);
      expect(r.front, 0);
      expect(r.back, 1, reason: 'the inlay is the wide one');
      expect(r.disc, 2, reason: 'only one disc can slide out; the first wins');
    });

    test('with no wide scan, the first spare secondary is the back', () {
      final r = assignRoles(
        [true, false, false],
        [1.0, 1.0, 1.0],
        <Uint8List?>[_png(_sleeve(60)), _png(_disc()), _png(_sleeve(15))],
      );
      expect(r.disc, 1);
      expect(r.back, 2, reason: 'the disc is already spoken for');
    });

    test('a release with only a front cover', () {
      final r = assignRoles([true], [1.0], <Uint8List?>[_png(_sleeve(60))]);
      expect(r.front, 0);
      expect(r.back, isNull);
      expect(r.disc, isNull);
    });

    test('images that could not be fetched are simply not the disc', () {
      final r = assignRoles([true, false], [1.0, 1.0], <Uint8List?>[_png(_sleeve(60)), null]);
      expect(r.disc, isNull);
      expect(r.back, 1);
    });

    test('no primary marked: the first scan is the front', () {
      final r = assignRoles([false, false], [1.0, 1.2], <Uint8List?>[_png(_sleeve(60)), _png(_sleeve(15))]);
      expect(r.front, 0);
    });
  });
}
