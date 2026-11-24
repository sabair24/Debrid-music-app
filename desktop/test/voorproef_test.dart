// De voorproef (Saber, 23-11-2026): een fragment van 30 s zonder iets te downloaden, en een Soulseek-proef die na het
// luisteren stopt en opruimt — tenzij je Houden tikt, dan gaat dezelfde download door. Hier met een nepspeler en een
// nephaal: de afloop is waar het stil fout kan gaan.
import 'dart:async';

import 'package:debridmusic/models.dart' show Track;
import 'package:debridmusic/radio.dart' show AlVanJou, Radioplek;
import 'package:debridmusic/soulseek.dart' show SoulseekFile;
import 'package:debridmusic/voorproef.dart';
import 'package:flutter_test/flutter_test.dart';

class _Speler {
  String? klinkt;
  final gespeeld = <(String adres, Duration? duur)>[];
  Future<bool> speel(String adres, String sleutel, Duration? duur) async {
    klinkt = sleutel;
    gespeeld.add((adres, duur));
    return true;
  }

  Future<void> stop(String sleutel) async {
    if (klinkt == sleutel) klinkt = null;
  }
}

Track _t(String p) => Track(path: p, title: 'Jam', artist: 'Michael Jackson', album: 'Dangerous');

Radioplek _plek() => Radioplek(artiest: 'Michael Jackson', titel: 'Jam', seconden: 339);

Future<void> _even() => Future<void>.delayed(const Duration(milliseconds: 40));

void main() {
  late _Speler speler;
  late List<Track> weg;
  late int gestopt;
  late Completer<Track?> landing;
  SoulseekFile? gekregen;

  Voorproef maak({bool alVanJou = false}) {
    speler = _Speler();
    weg = [];
    gestopt = 0;
    landing = Completer<Track?>();
    gekregen = null;
    return Voorproef(
      speel: speler.speel,
      stopSpeler: speler.stop,
      klinktNog: (s) => speler.klinkt == s,
      wacht: const Duration(milliseconds: 10),
      vergeet: (t) async => weg.add(t),
      haal: (plek, {alleen, required klinkt, required bijStop}) async {
        gekregen = alleen;
        bijStop(() => gestopt++);
        klinkt('http://127.0.0.1/groei/1.flac');
        if (alVanJou) throw AlVanJou(_t('D:/al.flac'));
        return landing.future;
      },
    );
  }

  test('DE KERN: de proef klinkt 30 s; daarna stopt de haal, en wat er toch landde gaat weg', () async {
    final v = maak();
    unawaited(v.soulseek('jam', _plek()));
    await _even();
    expect(v.faseVan('jam'), ProefFase.klinkt);
    expect(speler.gespeeld.single, ('http://127.0.0.1/groei/1.flac', kProefDuur));
    expect(v.loopt('jam'), isTrue);
    speler.klinkt = null; // de 30 s zijn om
    await _even();
    expect(gestopt, 1, reason: 'de haal is afgebroken');
    expect(v.faseVan('jam'), ProefFase.niets);
    landing.complete(_t('D:/jam.flac')); // net op tijd binnen
    await _even();
    expect(weg.map((t) => t.path), ['D:/jam.flac'], reason: 'niemand hield hem: weer weg');
  });

  test('DE KERN: Houden laat dezelfde download doorgaan, en geeft het nummer als het landt', () async {
    final v = maak();
    unawaited(v.soulseek('jam', _plek()));
    await _even();
    final gehouden = v.houd('jam');
    expect(v.faseVan('jam'), ProefFase.gehouden);
    speler.klinkt = null;
    await _even();
    expect(gestopt, 0, reason: 'niet afgebroken');
    landing.complete(_t('D:/jam.flac'));
    expect((await gehouden)?.path, 'D:/jam.flac');
    await _even();
    expect(weg, isEmpty);
  });

  test('een nieuwe proef rondt de vorige af; nog eens tikken stopt hem', () async {
    final v = maak();
    unawaited(v.soulseek('jam', _plek()));
    await _even();
    await v.fragment('ander', 'https://deezer/p.mp3');
    expect(gestopt, 1);
    expect(v.faseVan('jam'), ProefFase.niets);
    expect(v.faseVan('ander'), ProefFase.klinkt);
    expect(speler.gespeeld.last, ('https://deezer/p.mp3', null), reason: 'een fragment stopt aan zijn eigen einde');
    await v.stop('ander');
    expect(speler.klinkt, isNull);
    expect(v.faseVan('ander'), ProefFase.niets);
  });

  test('niets gevonden: dat zegt de knop', () async {
    speler = _Speler();
    final v = Voorproef(
      speel: speler.speel,
      stopSpeler: speler.stop,
      klinktNog: (s) => speler.klinkt == s,
      vergeet: (_) async {},
      haal: (plek, {alleen, required klinkt, required bijStop}) async => null,
    );
    await v.soulseek('niets', _plek());
    expect(v.faseVan('niets'), ProefFase.nietGevonden);
  });

  test('al van jou: nooit weggooien, ook niet als niemand hem houdt', () async {
    final v = maak(alVanJou: true);
    await v.soulseek('jam', _plek());
    speler.klinkt = null;
    await _even();
    expect(weg, isEmpty);
  });

  test('één gekozen bestand uit Bronnen gaat mee naar de haal', () async {
    final v = maak();
    final f = SoulseekFile(username: 'uploader', filename: r'@@u\Dangerous\Jam.flac', size: 1);
    unawaited(v.soulseek('bron', _plek(), alleen: f));
    await _even();
    expect(gekregen, same(f));
    await v.stop('bron');
  });

  group('een fragment zoeken (Saber, 24-11-2026: het oortje op albumpagina, Ontdek, artiest, nieuwe releases)', () {
    test('DE KERN: gevonden = het fragment, niets gedownload; niet gevonden = de Soulseek-proef', () async {
      final v = maak();
      await v.zoekEnProef('a', _plek(), () async => 'https://deezer/p.mp3');
      expect(speler.gespeeld.last, ('https://deezer/p.mp3', null));
      expect(gestopt, 0, reason: 'geen haal begonnen');
      await v.stop('a');
      unawaited(v.zoekEnProef('b', _plek(), () async => null));
      await _even();
      expect(speler.gespeeld.last, ('http://127.0.0.1/groei/1.flac', kProefDuur), reason: 'geen fragment: Soulseek');
      await v.stop('b');
    });

    test('tijdens het zoeken staat de knop op zoekt; nog eens tikken stopt, en dan speelt er niets', () async {
      final v = maak();
      final zoek = Completer<String?>();
      unawaited(v.zoekEnProef('a', _plek(), () => zoek.future));
      await _even();
      expect(v.faseVan('a'), ProefFase.zoekt);
      await v.stop('a');
      zoek.complete('https://deezer/p.mp3');
      await _even();
      expect(speler.gespeeld, isEmpty);
      expect(v.faseVan('a'), ProefFase.niets);
    });

    test('een verlopen fragment van Deezer (exp= in het adres) telt niet; iTunes verloopt niet', () {
      final nu = DateTime.fromMillisecondsSinceEpoch(1764000000 * 1000);
      expect(fragmentVerlopen('https://cdnt-preview.dzcdn.net/a.mp3?hdnea=exp=1763999000~acl=x~hmac=y', nu: nu), isTrue);
      expect(fragmentVerlopen('https://cdnt-preview.dzcdn.net/a.mp3?hdnea=exp=1764000030~acl=x', nu: nu), isTrue,
          reason: 'een minuut speling');
      expect(fragmentVerlopen('https://cdnt-preview.dzcdn.net/a.mp3?hdnea=exp=1764090000~acl=x', nu: nu), isFalse);
      expect(fragmentVerlopen('https://audio-ssl.itunes.apple.com/x/mzaf_1.plus.aac.p.m4a', nu: nu), isFalse);
    });
  });
}
