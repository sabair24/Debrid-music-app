import 'dart:io';

import 'package:debridmusic/enrichment.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een vraag aan TheAudioDB waar iemand nu op een scherm op wacht, staat niet drie seconden achter een
/// andere. Gemeten op 21-10-2026 op de gsm (▶ KATSEYE — Gabriela): de cd-vraag van Nu speelt wachtte
/// twee keer precies 3,1 s. Twaalf vragen binnen twee seconden kregen bij TheAudioDB alle twaalf een
/// volledig antwoord; de drie seconden zijn geijkt op een lange veeg van de hele bibliotheek.
void main() {
  const afstand = Duration(seconds: 3);
  final nu = DateTime(2026, 10, 21, 6, 2, 4);

  test('een kleine reeks gaat meteen, ook vlak na een andere vraag', () {
    final verstuurd = [nu.subtract(const Duration(milliseconds: 100))];
    expect(
        audioDbVoorrangWacht(
            verstuurd: verstuurd, laatste: nu.subtract(const Duration(milliseconds: 100)), nu: nu, afstand: afstand),
        Duration.zero);
  });

  test('na een salvo weer de afstand van de rij', () {
    final verstuurd = [for (var i = 0; i < kAudioDbSalvo; i++) nu.subtract(Duration(seconds: i))];
    expect(audioDbVoorrangWacht(verstuurd: verstuurd, laatste: nu.subtract(const Duration(seconds: 1)), nu: nu, afstand: afstand),
        const Duration(seconds: 2));
  });

  test('wat buiten het venster valt, telt niet meer', () {
    final verstuurd = [
      for (var i = 0; i < kAudioDbSalvo; i++) nu.subtract(kAudioDbSalvoVenster + Duration(seconds: 1 + i))
    ];
    expect(audioDbVoorrangWacht(verstuurd: verstuurd, laatste: nu, nu: nu, afstand: afstand), Duration.zero);
    expect(verstuurd, isEmpty);
  });

  test('een klok die terugsprong, wacht nooit langer dan de afstand', () {
    final toekomst = nu.add(const Duration(hours: 1));
    final verstuurd = [for (var i = 0; i < kAudioDbSalvo; i++) nu.subtract(Duration(milliseconds: i))];
    final w = audioDbVoorrangWacht(verstuurd: verstuurd, laatste: toekomst, nu: nu, afstand: afstand);
    expect(w <= afstand, isTrue);
  });

  test('aangesloten: Nu speelt en de albumpagina vragen met voorrang, de opwarmer niet', () {
    final d = File('lib/discogs.dart').readAsStringSync();
    expect(d, contains('_tadbBeelden(artist, album, step, voorrang: !freeOnly)'));
    expect(d, contains('albumInfo(artist, album, voorrang: voorrang)'));
    final e = File('lib/enrichment.dart').readAsStringSync();
    final info = e.substring(e.indexOf('Future<AlbumInfo?> albumInfo('));
    expect(info.substring(0, info.indexOf('searchalbum.php')),
        contains('await (voorrang ? _audioDbVoorrang() : _audioDbSlot());'));
    final m = File('lib/main.dart').readAsStringSync();
    expect(m, contains('albumInfo(artist, album, voorrang: true)'));
  });
}
