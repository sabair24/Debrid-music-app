/// Een mislukte download laat niets achter in je muziekmap.
///
/// **De storing.** Saber op 12-09-2026, na twee radioritten: *"controleer of het opruimen goed gaat
/// als de radio afsluit"*. Dat bleek bijna overal te kloppen — de duizenden peerverbindingen gingen
/// dicht (950 handles, één socket over), er stonden geen halve bestanden en `stream_cache` was leeg
/// — op één ding na. In de wortel van `D:\Flac music 2024` stonden zes lege mappen:
///
///     impoluto        aangemaakt 13:56
///     katakana2025    aangemaakt 13:57
///     JGutz40         aangemaakt 13:59
///     superluminaire  aangemaakt 13:59
///     ssreverb        aangemaakt 14:00
///     studio308       aangemaakt 12:33
///
/// Allemaal namen van Soulseek-peers, en elk ervan staat in `downloads.log` als een overdracht die
/// níét doorging: *"impoluto mislukt: Geweigerd: Queued na 1m32s"*, *"ssreverb mislukt: Geweigerd:
/// Queued na 1m39s"*. In totaal stonden er elf van die mappen tussen de albums.
///
/// De oorzaak staat in [SlskSession._pump]: die maakt de doelmap aan vóór de eerste byte binnen is.
/// Loopt het daarna stuk, dan werd het halve bestand wél weggegooid en de map niet.
library;

import 'dart:io';

import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

Directory _tijdelijk() {
  final d = Directory.systemTemp.createTempSync('dm_opruim_');
  addTearDown(() {
    try {
      d.deleteSync(recursive: true);
    } catch (_) {}
  });
  return d;
}

void main() {
  test('DE KERN: de map die de mislukte download achterliet gaat weg', () async {
    final wortel = _tijdelijk();
    final peer = Directory('${wortel.path}${Platform.pathSeparator}impoluto')..createSync();

    await ruimLegeMapOp(peer);

    expect(peer.existsSync(), isFalse, reason: 'elf van deze stonden er tussen de albums');
    expect(wortel.existsSync(), isTrue, reason: 'alleen de lege map, niet wat eromheen staat');
  });

  test('DE VAL: een map waar iets in staat blijft staan', () async {
    final wortel = _tijdelijk();
    final album = Directory('${wortel.path}${Platform.pathSeparator}Barry White')..createSync();
    // Twee radiohalen kunnen tegelijk in dezelfde albummap schrijven. Mislukt de ene, dan mag hij
    // de map van de andere niet onder zijn voeten weghalen.
    File('${album.path}${Platform.pathSeparator}Just The Way You Are.flac').writeAsStringSync('x');

    await ruimLegeMapOp(album);

    expect(album.existsSync(), isTrue);
  });

  test('DE GRENS: een map die er niet meer is geeft geen fout', () async {
    final wortel = _tijdelijk();
    final weg = Directory('${wortel.path}${Platform.pathSeparator}bestaat-niet');

    await expectLater(ruimLegeMapOp(weg), completes,
        reason: 'opruimen mag een download nooit alsnog laten struikelen');
  });
}
