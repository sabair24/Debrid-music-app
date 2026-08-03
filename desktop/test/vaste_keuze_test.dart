/// Wat er gebeurt als de gebruiker ZELF een regel uit de Soulseek-lijst aanklikt.
///
/// Saber wees het aan op Joe Dassin / "L'été indien": de best gerangschikte kopie is daar een ánder
/// nummer. De app pakte hem toch, elke keer, en omdat de dubbelcontrole daarna elke volgende poging
/// weigerde met "loopt al", viel er niets meer te kiezen.
///
/// Drie dingen overrulden de klik: de sortering op kwaliteit, de poolsplitsing (een aangeklikte MP3
/// kwam pas aan bod nadat élke lossless kopie van iets anders geprobeerd was), en `bestPerPeer` in
/// [DownloadManager.sweepOrderFor], die het aangeklikte bestand kon laten wegvallen als diezelfde peer
/// ook iets hoger scorends aanbood.
///
/// De ruil die de gebruiker koos: terugvallen mag, maar alleen op peers die EXACT hetzelfde bestand
/// aanbieden. Nooit een andere rip, nooit een andere versie.
library;

import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

SoulseekFile f(
  String peer,
  String naam, {
  int kbps = 1000,
  int? duur = 268,
  int? grootte,
  bool free = true,
  int queue = 0,
}) =>
    SoulseekFile(
      username: peer,
      filename: 'Muziek\\Joe Dassin\\$naam',
      size: grootte ?? (kbps * (duur ?? 268) / 8).round() * 1000,
      bitrate: kbps,
      durationSec: duur,
      freeSlots: free,
      queueLength: queue,
    );

void main() {
  group('is dit hetzelfde BESTAND', () {
    test('dezelfde rip bij een andere peer, op tags na', () {
      // Tags en een ingesloten hoes schelen makkelijk een halve megabyte; byte-gelijkheid eisen zou
      // elke echte kopie afwijzen.
      final a = f('peer-a', "L'ete indien.flac", grootte: 30000000);
      final b = f('peer-b', "L'ete indien.flac", grootte: 30400000);
      expect(zelfdeBestand(a.filename, a.size, a.durationSec, b.filename, b.size, b.durationSec),
          isTrue);
    });

    test('DE ZAAK JOE DASSIN: een ander nummer uit dezelfde map telt niet mee', () {
      // Precies het geval waarop de gebruiker vastliep. `sameRecording` is hier bewust ruim genoeg om
      // ja te zeggen tegen van alles; deze functie bestaat om dat NIET te doen.
      final gekozen = f('peer-a', "L'ete indien.flac", duur: 268);
      final ander = f('peer-b', "Et si tu n'existais pas.flac", duur: 205);
      expect(
          zelfdeBestand(gekozen.filename, gekozen.size, gekozen.durationSec, ander.filename,
              ander.size, ander.durationSec),
          isFalse);
    });

    test('een live- of remixversie met bijna dezelfde duur telt niet mee', () {
      final a = f('peer-a', "L'ete indien.flac", duur: 268);
      final b = f('peer-b', "L'ete indien (Live).flac", duur: 269);
      expect(zelfdeBestand(a.filename, a.size, a.durationSec, b.filename, b.size, b.durationSec),
          isFalse);
    });

    test('mp3 en flac met dezelfde naam zijn niet hetzelfde bestand', () {
      final a = f('peer-a', "L'ete indien.flac", grootte: 30000000);
      final b = f('peer-b', "L'ete indien.mp3", grootte: 30000000);
      expect(zelfdeBestand(a.filename, a.size, a.durationSec, b.filename, b.size, b.durationSec),
          isFalse);
    });

    test('een grootteverschil van dertig procent is een andere rip', () {
      final a = f('peer-a', "L'ete indien.flac", grootte: 30000000);
      final b = f('peer-b', "L'ete indien.flac", grootte: 21000000);
      expect(zelfdeBestand(a.filename, a.size, a.durationSec, b.filename, b.size, b.durationSec),
          isFalse);
    });

    test('een andere map bij dezelfde bestandsnaam telt wél mee', () {
      // Peers ordenen hun schijf anders; de bestandsnaam is wat blijft.
      const a = 'D\\Muziek\\Dassin\\09 - Salut.flac';
      const b = 'shared\\FLAC\\Joe Dassin - Eternel\\09 - Salut.flac';
      expect(zelfdeBestand(a, 25000000, 240, b, 25100000, 240), isTrue);
    });

    test('meldt een peer niets, dan beslissen naam en extensie', () {
      const a = 'x\\Salut.flac';
      const b = 'y\\Salut.flac';
      expect(zelfdeBestand(a, 0, null, b, 0, null), isTrue);
      expect(zelfdeBestand(a, 0, null, 'y\\Salut.mp3', 0, null), isFalse);
    });
  });

  group('de aangeklikte kopie blijft vooraan', () {
    test('ook als een andere peer een vrij slot én een hogere score heeft', () {
      // Zonder dit verdween de keuze naar achteren: vrije slots gaan vóór, en score daarna.
      final gekozen = f('trage-peer', "L'ete indien.flac", kbps: 950, free: false, queue: 40);
      final snellere = f('snelle-peer', "L'ete indien.flac", kbps: 4000);
      final orde = DownloadManager.sweepOrderFor([snellere, gekozen], first: gekozen);
      expect(orde.first.username, 'trage-peer');
      expect(orde.length, 2, reason: 'de andere blijft als terugval beschikbaar');
    });

    test('en wordt niet weggestreept als diezelfde peer iets beters aanbiedt', () {
      // `bestPerPeer` houdt per peer één bestand over, op score. Precies daardoor kon het
      // aangeklikte bestand volledig uit de probeervolgorde verdwijnen.
      final gekozen = f('collector', "L'ete indien.flac", kbps: 950);
      final beterVanZelfdePeer = f('collector', "L'ete indien.flac", kbps: 4000);
      final orde = DownloadManager.sweepOrderFor([beterVanZelfdePeer, gekozen], first: gekozen);
      expect(orde.first.bitrate, 950, reason: 'de keuze van de gebruiker, niet de beste van die peer');
    });

    test('zonder een keuze verandert er niets aan de oude volgorde', () {
      // Bewaakt de automatische kant: die moet blijven doen wat hij deed.
      final busyHiRes = f('busy-collector', "L'ete indien.flac", kbps: 6000, free: false);
      final freeCd = f('free-peer', "L'ete indien.flac", kbps: 950);
      expect(DownloadManager.sweepOrderFor([busyHiRes, freeCd]).first.username, 'free-peer');
    });
  });
}
