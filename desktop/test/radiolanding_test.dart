/// Wat de radio doet als een haal terugkomt — met een nummer, met "van jou", of met "straks".
///
/// Drie uitkomsten die tot de eindbeoordeling van 26-09-2026 geen toets hadden:
///
/// - **Van jou.** Een haal die landde op muziek die je al had (je mp3 opgevolgd door een FLAC) gaf
///   niets terug, en dan bleef er een lege plek in de radio. Nu klinkt hij, maar staat hij niet in de
///   notitie: de radio mag nooit opruimen wat van jou is.
/// - **Een duim die niet weg kon.** Dan blijft het nummer in de notitie, zodat het overzicht het
///   straks opnieuw aanbiedt in plaats van dat het ongemerkt op je schijf blijft staan.
/// - **Straks.** Een pauze in het ophalen had geen gezicht; nu staat de reden in het radiopaneel.
library;

import 'dart:io';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/radio.dart';
import 'package:debridmusic/radiovoorraad.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Alleen wat de radio van de speler gebruikt.
class _Speler implements PlayerStore {
  final rij = <RadioItem>[];

  @override
  Future<List<RadioItem>> Function()? radioExtend;

  @override
  void Function(List<RadioItem> gespeeld)? bijRadioEinde;

  @override
  void Function(RadioItem item, {required bool bestand})? bijRadioOverslaan;

  // Speelt niet en staat niet droog: dan houdt de poort van het bijvullen dicht (zie `bijvulBesluit`),
  // en meten deze toetsen alleen het landen.
  @override
  bool get playing => false;

  @override
  bool get radioDroog => false;

  @override
  bool get wilVerder => false;

  @override
  List<RadioItem> get radioQueue => rij;

  @override
  int get radioIndex => 0;

  // Nog niets geladen: dan weet de radio de resttijd niet, en telt hij nummers zoals voorheen.
  @override
  Duration duration = Duration.zero;

  @override
  Duration get positieErgens => Duration.zero;

  @override
  Future<void> playRadio(List<RadioItem> items, {int start = 0}) async {
    rij
      ..clear()
      ..addAll(items);
  }

  @override
  void voegToeAanRadio(List<RadioItem> meer) => rij.addAll(meer);

  @override
  Future<bool> haalUitRadio(String pad) async {
    rij.removeWhere((r) => r.local?.path == pad);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bron implements Radiobron {
  _Bron(this.antwoord);
  final Future<Track?> Function(Radioplek p) antwoord;
  bool vergeetLukt = true;
  final vergeten = <String>[];

  @override
  Future<String?> begin() async => null;

  @override
  void einde() {}

  @override
  void staak() {}

  @override
  Future<Track?> haal(Radioplek p) => antwoord(p);

  @override
  Future<bool> vergeet({required String pad, required String artiest, required String titel}) async {
    vergeten.add(pad);
    return vergeetLukt;
  }
}

Track _t(String titel) =>
    Track(path: '${Directory.systemTemp.path}${Platform.pathSeparator}$titel.flac', title: titel, artist: titel, album: '');

Future<void> _totAllesTerug(RadioBesturing r) async {
  for (var i = 0; i < 200; i++) {
    if (!r.plan.any((p) => p.stand == Haalstand.onderweg)) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late Directory wortel;
  setUp(() {
    wortel = Directory.systemTemp.createTempSync('dm_landing_');
    setAppDirForTest(wortel.path);
  });
  tearDown(() {
    try {
      wortel.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('DE KERN: wat op je eigen muziek landt klinkt, maar is niet van de radio', () async {
    final a = _t('Cappella'), b = _t('Haddaway'), c = _t('Corona');
    final speler = _Speler();
    final radio = RadioBesturing(
        speler: speler,
        bron: _Bron((p) async => switch (p.artiest) {
              'Haddaway' => throw AlVanJou(b),
              'Corona' => c,
              _ => null,
            }));
    addTearDown(radio.stop);
    await radio.start([
      Radioplek(artiest: 'Cappella', titel: 'Move On Baby', eigen: a),
      Radioplek(artiest: 'Haddaway', titel: 'What Is Love'),
      Radioplek(artiest: 'Corona', titel: 'The Rhythm of the Night'),
    ]);
    await _totAllesTerug(radio);

    expect(radio.plan[1].stand, anyOf(Haalstand.geland, Haalstand.inRij),
        reason: 'eerst bleef hier een lege plek');
    expect([for (final r in speler.rij) r.local?.path], contains(b.path),
        reason: 'het klinkt: daarvoor werd het gehaald');
    expect(radio.plan[1].eigen, same(b));
    expect(radio.plan[1].doorRadio, isFalse);
    expect(radio.plan[2].doorRadio, isTrue);
    expect(radio.gehaald, 1);
    expect(await radio.gooiWeg(b), isNull, reason: 'bij muziek van jou staat er geen duim');

    radio.stop();
    expect([for (final g in radio.openstaand!.gehaald) g.pad], [c.path],
        reason: 'alleen wat de radio zelf ophaalde komt in het opruimoverzicht');
  });

  test('DE VAL: een duim die niet weg kon, blijft in de notitie', () async {
    final c = _t('Corona');
    final bron = _Bron((p) async => c)..vergeetLukt = false;
    final radio = RadioBesturing(speler: _Speler(), bron: bron);
    addTearDown(radio.stop);
    await radio.start([Radioplek(artiest: 'Corona', titel: 'The Rhythm of the Night')]);
    await _totAllesTerug(radio);

    expect(await radio.gooiWeg(c), isFalse);
    expect(bron.vergeten, [c.path]);
    radio.stop();
    expect([for (final g in radio.openstaand!.gehaald) g.pad], [c.path],
        reason: 'anders blijft het voorgoed op je schijf staan zonder dat iemand weet waarvandaan');
  });

  test('DE KERN: afstemmen laat een zaad dat nog wacht staan', () {
    final zaad = Radioplek(artiest: '2 Fabiola', titel: 'Freak Out', zaad: true);
    final ander = Radioplek(artiest: 'Cappella', titel: 'Move On Baby');
    final nieuw = stemPlanAf([zaad, ander], [Radioplek(artiest: 'Corona', titel: 'The Rhythm of the Night')]);
    expect(nieuw, contains(zaad),
        reason: 'het nieuwe plan weert het zaadnummer met opzet; zonder dit was het voorgoed weg');
    expect(nieuw, isNot(contains(ander)));
  });

  test('DE KERN: een keuring zonder antwoord laat de plek wachten, niet ongekeurd door', () async {
    var gehaald = 0;
    final radio = RadioBesturing(
        speler: _Speler(),
        bron: _Bron((p) async {
          gehaald++;
          return null;
        }));
    addTearDown(radio.stop);
    await radio.start([Radioplek(artiest: 'Michael Jackson', titel: 'Smooth Criminal')],
        keur: (p) async => throw const RadioKeuringLater());
    await _totAllesTerug(radio);
    expect(radio.plan.single.stand, Haalstand.wacht,
        reason: '27-09-2026: veertien nummers gingen zo ongekeurd door, "Smooth Criminal" erbij');
    expect(gehaald, 0, reason: 'zonder oordeel wordt er niets gehaald');
    expect(radio.pauze, isNull, reason: 'geen pauze voor de hele radio — alleen deze plek wacht');
  });

  test('DE KERN: een nieuwe radio over een lopende opent geen overzicht', () async {
    final c = _t('Corona');
    final radio = RadioBesturing(speler: _Speler(), bron: _Bron((p) async => c));
    addTearDown(radio.stop);
    await radio.start([Radioplek(artiest: 'Corona', titel: 'The Rhythm of the Night')]);
    await _totAllesTerug(radio);
    expect(radio.gehaald, 1);

    var overzichtGezien = false;
    radio.addListener(() {
      if (radio.openstaand != null) overzichtGezien = true;
    });
    await radio.start([Radioplek(artiest: 'The Cranberries', titel: 'Zombie')]);
    expect(overzichtGezien, isFalse,
        reason: '27-09-2026, van Sade naar Zombie: "47 naar de prullenbak" over de radio die net begon');
    expect(radio.openstaand, isNull);

    radio.stop();
    expect([for (final g in radio.openstaand!.gehaald) g.pad], contains(c.path),
        reason: 'wat de vorige radio haalde gaat mee, en komt bij het afsluiten wel in het overzicht');
  });

  test('DE GRENS: een pauze heeft een reden, en de plek wacht', () async {
    final radio = RadioBesturing(
        speler: _Speler(),
        bron: _Bron((p) async => throw const RadioLaterOpnieuw('de koppeling met je pc geldt niet meer')));
    addTearDown(radio.stop);
    expect(radio.pauze, isNull);
    await radio.start([Radioplek(artiest: 'Corona', titel: 'The Rhythm of the Night')]);
    await _totAllesTerug(radio);

    expect(radio.plan.single.stand, Haalstand.wacht, reason: 'niet afgeschreven, straks opnieuw');
    expect(radio.pauze, 'de koppeling met je pc geldt niet meer');
  });

  group('de pc zelf: wat je al hebt, klinkt als van jou', () {
    // Alleen voor deze toets, en nooit gebruikt: de voortoets hieronder komt vóór elke aanmelding.
    AppSettings instellingen() => AppSettings()
      ..soulseekUser = 'toets'
      ..soulseekPass = 'toets';

    test('DE KERN: de voortoets van de haal meldt je eigen bestand, geen lege plek', () async {
      final eigen = File('${wortel.path}${Platform.pathSeparator}Freak Out.flac')..writeAsStringSync('x');
      final cfg = instellingen();
      final d = DownloadManager(OnlineService(cfg), SoulseekService(cfg), wortel.path, () async {})
        ..mapVanBestaande = (artist, title, {seconds, nietIn}) => eigen.path;
      await expectLater(d.haalVoorRadio(artiest: '2 Fabiola', titel: 'Freak Out'),
          throwsA(isA<RadioAlGehad>().having((e) => e.pad, 'pad', eigen.path)),
          reason: 'eerst gaf dit null, en dan bleef er een lege plek in de radio');
    });

    test('DE VAL: een pad dat er niet meer is, is gewoon niets', () async {
      final cfg = instellingen();
      final d = DownloadManager(OnlineService(cfg), SoulseekService(cfg), wortel.path, () async {})
        ..mapVanBestaande = (artist, title, {seconds, nietIn}) => '${wortel.path}${Platform.pathSeparator}weg.flac';
      expect(await d.haalVoorRadio(artiest: '2 Fabiola', titel: 'Freak Out'), isNull);
    });

    test('DE KERN: de radio van de pc maakt er "van jou" van', () async {
      final t = _t('Freak Out');
      final cfg = instellingen();
      final bron = EigenRadiobron(
        downloads: _AlGehad(OnlineService(cfg), SoulseekService(cfg), wortel.path, () async {}, t.path),
        soulseek: SoulseekService(cfg),
        library: _Bibliotheek(t),
        instellingen: cfg,
      );
      await expectLater(bron.haal(Radioplek(artiest: '2 Fabiola', titel: 'Freak Out')),
          throwsA(isA<AlVanJou>().having((e) => e.nummer, 'nummer', same(t))));
    });
  });
}

/// Een haal die op muziek landt die je al had.
class _AlGehad extends DownloadManager {
  _AlGehad(super.online, super.soulseek, super.musicRoot, super.onLibraryChanged, this.pad);
  final String pad;

  @override
  Future<String?> haalVoorRadio(
      {required String artiest, required String titel, int? seconden, int? jaar}) async {
    throw RadioAlGehad(pad);
  }
}

/// Een bibliotheek die het bestand meteen kent.
class _Bibliotheek extends LibraryStore {
  _Bibliotheek(this.t);
  final Track t;

  @override
  Future<Track?> voegBestandToe(String pad) async => t;
}
