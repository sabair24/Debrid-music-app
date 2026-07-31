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

  test('a white disc on a white bed is a disc', () {
    // Enrique's Escape: a white CD scanned on a white backdrop. The old rule wanted the face to be
    // much darker than the surround and so never saw one of these — measured on the real scan it
    // read 250 / 244 / 231, against 198 / 201 / 186 for a blank booklet page from the same release.
    // Brightness cannot separate those. The hole can.
    //
    // Drawn the way a CD actually is: pale disc, printed label around the middle, clear hub, hole.
    // Without the print it would be one flat shade throughout, which is not a disc but a blank
    // square — and is rightly refused.
    final im = img.Image(width: 300, height: 300);
    img.fill(im, color: img.ColorRgb8(250, 250, 250)); // scanner bed
    img.fillCircle(im, x: 150, y: 150, radius: 145, color: img.ColorRgb8(238, 238, 238)); // disc
    img.fillCircle(im, x: 150, y: 150, radius: 80, color: img.ColorRgb8(120, 120, 120)); // print
    img.fillCircle(im, x: 150, y: 150, radius: 34, color: img.ColorRgb8(248, 248, 248)); // hub
    img.fillCircle(im, x: 150, y: 150, radius: 22, color: img.ColorRgb8(252, 252, 252)); // hole
    expect(looksLikeDisc(_png(im)), isTrue);
  });

  test('a picture disc — printed to the edge, on a dark bed — is a disc too', () {
    // Recognised by its hole rather than by a pale surround, so this no longer has to be given up
    // on. It is a disc; spinning it is right.
    expect(looksLikeDisc(_png(_disc(surround: 30, face: 200))), isTrue);
  });

  test('a flat image with no hole is never claimed', () {
    // The thing the caution is really about: nothing round, nothing punched through the middle.
    expect(looksLikeDisc(_png(_sleeve(250))), isFalse);
    expect(looksLikeDisc(_png(_sleeve(20))), isFalse);
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

    test('a booklet spread listed before the inlay is not taken for the back', () {
      // Random Access Memories, Discogs release 28622347: fourteen scans, eight of them wider than
      // tall — the sleeve at 1.33, the inlay at 1.30, and four spreads at about 2.0. "Wider than
      // tall" alone would take whichever came first, so a spread ahead of the inlay would win.
      final r = assignRoles(
        [true, false, false],
        [600 / 450, 600 / 294, 600 / 462], // sleeve, spread, inlay
        <Uint8List?>[_png(_sleeve(60)), _png(_sleeve(120)), _png(_sleeve(15))],
      );
      expect(r.front, 0);
      expect(r.back, 2, reason: 'the 2.04 spread is not a rear inlay; the 1.30 one is');
    });

    test('a rear inlay wider than the sleeve is still the back', () {
      // Dangerous the other way round: the inlay IS the notably wider scan, and must stay chosen.
      final r = assignRoles(
        [true, false],
        [600 / 593, 600 / 474],
        <Uint8List?>[_png(_sleeve(60)), _png(_sleeve(15))],
      );
      expect(r.back, 1);
    });
  });

  group('the corners of a disc scan', () {
    test('a disc photographed on a two-tone backdrop is not mistaken for one', () {
      // Half the bed light, half dark: the hole test alone passes this, because the middle really
      // is a flat pale patch. A round disc shows the SAME backing in all four corners.
      final im = _disc();
      img.fillRect(im, x1: 0, y1: 0, x2: 299, y2: 60, color: img.ColorRgb8(10, 10, 10));
      expect(looksLikeDisc(_png(im)), isFalse,
          reason: 'corners that disagree this much are not backing around a round disc');
    });

    test('an evenly lit disc still reads as one', () {
      expect(looksLikeDisc(_png(_disc())), isTrue);
    });
  });

  /// De kleur waar een hoes naar neigt, voor de was achter een albumpagina.
  ///
  /// Waarom niet gewoon middelen: dat wordt bruin. Rood naast groen middelt tot modder, en een hoes met
  /// veel wit trekt alles naar grijs — juist de kleuren waar je geen achtergrond van wil.
  group('de kleur waar een hoes naar neigt', () {
    int r(int c) => (c >> 16) & 0xFF;
    int g(int c) => (c >> 8) & 0xFF;
    int b(int c) => c & 0xFF;

    img.Image vlak(int rr, int gg, int bb) {
      final im = img.Image(width: 200, height: 200);
      img.fill(im, color: img.ColorRgb8(rr, gg, bb));
      return im;
    }

    test('een effen rode hoes geeft rood', () {
      final c = dominantColour(_png(vlak(220, 30, 40)));
      expect(c, isNotNull);
      expect(r(c!), greaterThan(180));
      expect(g(c), lessThan(90));
      expect(b(c), lessThan(90));
    });

    test('een grijze hoes geeft niets, en dat is het punt', () {
      // Een verloop van zwart naar wit: overal is de verzadiging nul. Een flauw grijsje achter de
      // pagina is lelijker dan helemaal geen was, dus hier hoort null uit te komen en geen "kleur".
      final im = img.Image(width: 200, height: 200);
      for (var y = 0; y < 200; y++) {
        for (var x = 0; x < 200; x++) {
          final v = (x * 255 / 199).round();
          im.setPixelRgb(x, y, v, v, v);
        }
      }
      expect(dominantColour(_png(im)), isNull);
    });

    test('zwart en wit stemmen niet mee', () {
      expect(dominantColour(_png(vlak(0, 0, 0))), isNull);
      expect(dominantColour(_png(vlak(255, 255, 255))), isNull);
    });

    test('een kleine felle vlek wint van een grote grijze vlakte', () {
      // DE test. Op een hoes die vooral grijs is, is die ene gekleurde vlek precies wat je onthoudt —
      // en een gemiddelde over alle pixels zou hem wegpoetsen tot iets wat nergens in de hoes voorkomt.
      final im = img.Image(width: 200, height: 200);
      img.fill(im, color: img.ColorRgb8(128, 128, 130));
      img.fillRect(im, x1: 80, y1: 80, x2: 119, y2: 119, color: img.ColorRgb8(20, 90, 210));
      final c = dominantColour(_png(im));
      expect(c, isNotNull);
      expect(b(c!), greaterThan(150), reason: 'de blauwe vlek hoort te winnen');
      expect(r(c), lessThan(90));
    });

    test('rommel is geen hoes', () {
      expect(dominantColour(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });
}
