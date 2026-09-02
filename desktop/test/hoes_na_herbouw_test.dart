/// Een hoes die binnenkomt ná een herscan hoort alsnog op het scherm.
///
/// **Waarom dit bestaat.** Gemeld op 02-09-2026: Linkin Park — Hybrid Theory (Deluxe Edition) bleef
/// zonder albumhoes staan, en metadata corrigeren hielp niet.
///
/// Dat corrigeren kón ook niet helpen, want de hoes was allang binnen. Hij stond om 19:11:45 op
/// schijf — `covers/2e3dc76b.jpg`, 44 kB, precies de sleutel van dit album — terwijl `/art/<album>`
/// 404 bleef geven. Eén herstart van de app en hij stond er.
///
/// Wat ertussen zat: het verrijken pakt een Album-object vast en schrijft de bytes er later in. Een
/// scan vervangt élk Album-object, en na een download loopt er juist een scan. Komt de hoes een
/// seconde ná die herbouw binnen, dan landt hij op een object dat niemand meer gebruikt.
///
/// De uid overleeft een herbouw wel — daar is hij voor — dus daar wordt het levende album mee
/// teruggevonden.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';

Track _t(String pad, String titel) => Track(
      path: pad,
      title: titel,
      artist: 'Linkin Park',
      album: 'Hybrid Theory (Deluxe Edition)',
      isFlac: true,
    );

void main() {
  test('DE KERN: de uid wijst na een herbouw hetzelfde album aan', () {
    // Dit is de eigenschap waar de reparatie op leunt. Zou de uid meebewegen met het OBJECT in
    // plaats van met de plaat, dan is er na een scan niets meer om de hoes aan op te hangen.
    final lib = LibraryStore()
      ..tracks.addAll([
        _t(r'D:\m\08. In The End.flac', 'In The End'),
        _t(r'D:\m\09. A Place For My Head.flac', 'A Place For My Head'),
      ])
      ..rebuildAlbums();

    final voor = lib.albums.single;
    final uid = lib.uidOf(voor);
    expect(uid, isNotEmpty, reason: 'zonder uid valt er niets terug te vinden');

    lib.rebuildAlbums();
    final na = lib.albums.single;

    expect(identical(na, voor), isFalse,
        reason: 'een herbouw maakt nieuwe objecten — dat is precies waar de fout in zat');
    expect(lib.uidOf(na), uid, reason: 'maar de plaat is dezelfde, en de uid zegt dat');
  });

  test('en een hoes op het oude object is via de uid op het nieuwe te zetten', () {
    final lib = LibraryStore()
      ..tracks.add(_t(r'D:\m\08. In The End.flac', 'In The End'))
      ..rebuildAlbums();

    final oud = lib.albums.single;
    final uid = lib.uidOf(oud);

    // Zoals het ging: de scan vervangt de albums terwijl er nog een hoes onderweg is.
    lib.rebuildAlbums();
    final levend = lib.albums.single;
    expect(levend.cover, isNull, reason: 'nog geen hoes, dat is de uitgangssituatie');

    // En dan komt hij binnen, met het oude object in de hand.
    final bytes = Uint8List.fromList(List<int>.filled(4096, 7));
    oud.enriched = bytes;
    for (final a in lib.albums) {
      if (lib.uidOf(a) == uid) a.enriched ??= bytes;
    }

    expect(levend.cover, isNotNull,
        reason: 'anders staat de hoes wel op schijf en niet op het scherm, tot de volgende start');
  });
}
