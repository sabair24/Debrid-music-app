@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:debridmusic/musicbrainz.dart';

/// What resolution the artwork actually arrives at.
///
/// The scans shown on the album page used to be fetched at 500px, which is visibly soft once a
/// cover fills the now-playing screen. These pin the size that is fetched instead — and pin the
/// reason it is not simply "always the original": on this very release the disc's original is
/// 3008×2980 and 11.8 MB.
void main() {
  setUpAll(() => HttpOverrides.global = null);

  test('front, back and disc all arrive at 1200px, not 500', () async {
    final mb = MusicBrainzService();
    final images = await mb.art('f8920e1b-5552-4301-85ac-cc9b0ab6e454'); // Escape, XE 2002
    expect(images, isNotEmpty);

    for (final want in ['front', 'back', 'disc']) {
      final i = images.firstWhere((x) => switch (want) {
            'front' => x.isFront,
            'back' => x.isBack,
            _ => x.isDisc,
          });
      final bytes = await mb.fetchImage(i.full);
      expect(bytes, isNotNull, reason: '$want could not be fetched');
      final decoded = img.decodeImage(bytes!);
      expect(decoded, isNotNull);
      expect(decoded!.width, greaterThan(1000),
          reason: '$want came back ${decoded.width}px — the 500px copy is what looked soft');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the disc is taken at 1200, not its 12 MB original', () async {
    final mb = MusicBrainzService();
    final images = await mb.art('f8920e1b-5552-4301-85ac-cc9b0ab6e454');
    final disc = images.firstWhere((x) => x.isDisc);
    // The original of this one is 3008px; taking it would cost ~70x the bytes for detail no window
    // here can show, cached per album.
    expect(disc.full, isNot(disc.url));
    final bytes = await mb.fetchImage(disc.full);
    expect(bytes!.length, lessThan(2 * 1024 * 1024),
        reason: 'got ${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB for one disc scan');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a row thumbnail stays small — there can be seventy-five of them', () async {
    final mb = MusicBrainzService();
    final images = await mb.art('f8920e1b-5552-4301-85ac-cc9b0ab6e454');
    final front = images.firstWhere((x) => x.isFront);
    final bytes = await mb.fetchImage(front.thumb);
    final decoded = img.decodeImage(bytes!);
    expect(decoded!.width, lessThanOrEqualTo(300), reason: 'a 58px row does not need more');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
