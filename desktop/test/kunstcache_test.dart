/// Wat al op schijf ligt, hoort meteen op het scherm te staan.
///
/// **De storing.** Saber op 12-09-2026, met een schermafdruk van "nu speelt": "ik krijg altijd eerst
/// dit als cd afbeelding, dan duurt het gemiddeld 10 sec eer de echte afbeelding er op komt, en dit
/// op alle platformen". En daarna, scherper: "eens de album al zijn covers heeft, automatisch of door
/// mij gekozen, dan is het toch maar rechtstreeks laden van het geheugen, dat moet instant zijn
/// zonder enige wachttijd."
///
/// Hij had gelijk, en de oorzaak zat niet in het tekenen maar in het wachten. `releaseArt` geeft de
/// cache alleen meteen terug als de map het merkteken `done` draagt. Mist er nog één rol — een
/// achterkant die deze plaat gewoon niet heeft, of een map die de achtergrondveeg zonder merkteken
/// achterliet — dan liep eerst de hele zoektocht: Discogs, MusicBrainz (één vraag per seconde) en
/// het Cover Art Archive. Gemeten in `warm.log` op 12-09-2026: veertig keer "archief over andere
/// persingen: niets" in één veeg, elk tot negentien seconden. Al die tijd stond het cd-beeld op de
/// hoes terwijl de echte scan ernaast op schijf lag.
///
/// De tweede meting uit hetzelfde logboek: die brede zoektocht werd bij ELKE veeg opnieuw gedaan,
/// ook als hij de vorige keer niets vond. Daarom het briefje `breed-gezocht`, met dezelfde
/// houdbaarheid van veertien dagen als een onvolledig antwoord.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een eigen appmap per toets, zodat de ene toets de cache van de andere niet leest.
Directory _eigenMap() {
  final d = Directory.systemTemp.createTempSync('dm_kunstcache_');
  setAppDirForTest(d.path);
  addTearDown(() {
    try {
      d.deleteSync(recursive: true);
    } catch (_) {}
  });
  return d;
}

DiscogsService _dienst() => DiscogsService(AppSettings());

final _plaatje = Uint8List.fromList([1, 2, 3, 4]);

void _leg(Directory dir, String naam) {
  dir.createSync(recursive: true);
  File('${dir.path}${Platform.pathSeparator}$naam').writeAsBytesSync(_plaatje);
}

void main() {
  test('DE KERN: een cd die op schijf ligt komt terug zonder merkteken en zonder netwerk', () async {
    _eigenMap();
    final d = _dienst();
    final map = d.artMap('Nirvana', 'Nevermind', 12, null, null, const {});
    _leg(map, 'front');
    _leg(map, 'disc');
    // Geen `done`-bestand: dit is precies de map waar `releaseArt` de hele zoektocht voor zou
    // starten. `cachedReleaseArt` mag niet wachten.
    expect(File('${map.path}${Platform.pathSeparator}done').existsSync(), isFalse,
        reason: 'de toets moet juist de ONAFGERONDE map beproeven');

    final art = await d.cachedReleaseArt('Nirvana', 'Nevermind', expectedTracks: 12);

    expect(art, isNotNull, reason: 'de cd stond op schijf en kwam niet op het scherm');
    expect(art!.disc, isNotNull, reason: 'dit is het beeld dat tien seconden op zich liet wachten');
    expect(art.front, isNotNull);
    expect(art.back, isNull, reason: 'wat er niet ligt mag niet verzonnen worden');
  });

  test('DE VAL: een leeggeruimde map is geen antwoord', () async {
    _eigenMap();
    final d = _dienst();
    // Alleen de map, geen enkele afbeelding. Gaf dit een ReleaseArt terug, dan telt het bovenaan als
    // treffer en OVERSCHRIJFT het wat er al op het scherm stond — een album zonder hoes en zonder
    // cd, waar nooit meer naar gezocht wordt.
    d.artMap('Adele', '30', 12, null, null, const {}).createSync(recursive: true);

    expect(await d.cachedReleaseArt('Adele', '30', expectedTracks: 12), isNull);
  });

  test('DE KERN: de map van de snelle lezer is de map waar de zoektocht in schrijft', () async {
    _eigenMap();
    final d = _dienst();
    // Twee plekken rekenen de sleutel zelf uit: `artMap` (waar `releaseArt` en `cachedReleaseArt`
    // beide door lopen) en `hasReleaseArt`, dat met zijn eigen regel naar `done` kijkt. Lopen die
    // uiteen, dan leest de snelle lezer bestendig de verkeerde map uit zonder dat iets het zegt.
    // Dat is de val waar de derde, dubbele berekening in liep die hier eerst stond.
    final roles = {'disc': 'https://example.invalid/cd.jpg'};
    final map = d.artMap('Gorillaz', 'Demon Days', 15, 1234, 'mbid-1', roles);
    _leg(map, 'front');
    File('${map.path}${Platform.pathSeparator}done').writeAsStringSync('1');

    expect(
        await d.hasReleaseArt('Gorillaz', 'Demon Days',
            expectedTracks: 15, pinned: 1234, pinnedMbid: 'mbid-1', roles: roles),
        isTrue,
        reason: 'artMap en hasReleaseArt wijzen niet naar dezelfde map');
    expect(
        await d.cachedReleaseArt('Gorillaz', 'Demon Days',
            expectedTracks: 15, pinned: 1234, pinnedMbid: 'mbid-1', roles: roles),
        isNotNull);
  });

  test('DE GRENS: een andere persing is een andere map', () async {
    _eigenMap();
    final d = _dienst();
    _leg(d.artMap('Nirvana', 'Nevermind', 12, 13814, null, const {}), 'front');

    expect(await d.cachedReleaseArt('Nirvana', 'Nevermind', expectedTracks: 12, pinned: 13814),
        isNotNull);
    expect(await d.cachedReleaseArt('Nirvana', 'Nevermind', expectedTracks: 12), isNull,
        reason: 'de vastgezette persing lekt naar de niet-vastgezette map');
  });

  test('DE KERN: het briefje houdt de brede zoektocht veertien dagen tegen', () async {
    _eigenMap();
    final d = _dienst();
    final map = d.artMap('Wu-Tang Clan', 'Enter The Wu-Tang', 12, null, null, const {});

    expect(await d.breedGezocht(map), isFalse, reason: 'zonder briefje moet er wél gezocht worden');
    await d.onthoudBreedGezocht(map);
    expect(await d.breedGezocht(map), isTrue,
        reason: 'veertig keer negentien seconden per veeg, precies waar de meting over ging');
  });

  test('DE GRENS: een briefje van vijftien dagen oud geldt niet meer', () async {
    _eigenMap();
    final d = _dienst();
    final map = d.artMap('Wu-Tang Clan', 'Enter The Wu-Tang', 12, null, null, const {});
    await d.onthoudBreedGezocht(map);
    final f = File('${map.path}${Platform.pathSeparator}breed-gezocht');
    f.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 15)));

    // Er komen scans bij bij het Cover Art Archive, en een Discogs-token dat later ingevuld wordt
    // opent een bron die er eerst niet was. "Nu niet gevonden" is niet "bestaat niet".
    expect(await d.breedGezocht(map), isFalse);
    expect(f.existsSync(), isFalse, reason: 'een verlopen briefje hoort opgeruimd te worden');
  });
}
