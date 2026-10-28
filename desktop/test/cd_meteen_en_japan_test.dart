// Saber, 26-10-2026, twee dingen op één avond:
//  * "als ik kies voor cd kwaliteit downloaden mag da direct gebeuren, want cd kwaliteit is altijd e" — een cd die hij
//    vraagt, blijft meteen (als versie naast zijn nummer), zonder "cd klaar" en Kiezen. Studio en vinyl blijven: eerst
//    luisteren. En een nummer dat al een cd heeft, zoekt er geen tweede (All Saints: "Ik heb 2 cd kwaliteit").
//  * "Japans wil ik nooit" — de nummerlijst van All Saints kwam van de Japanse cd van 1997 (Never Ever 5:13, nummer 3),
//    omdat die het eerst uitkwam. In de cache stonden 24 albums op een Japanse persing.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/album_facts.dart';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_oordelen.dart';
import 'package:debridmusic/kopiesoort.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/release_format.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soortjacht.dart';
import 'package:debridmusic/tidaler.dart' show Tidaler;
import 'package:debridmusic/twijfel.dart';
import 'package:debridmusic/versies.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

/// Een minimale FLAC: STREAMINFO met [rate], [bits] en [seconden], en één Vorbis-commentaar.
Uint8List _flac({int rate = 44100, int bits = 16, int seconden = 10, String titel = 'Nightvision'}) {
  final b = BytesBuilder()..add(ascii.encode('fLaC'));
  b.add([0x00, 0x00, 0x00, 0x22]);
  final si = Uint8List(34);
  const kanalen = 2;
  final monsters = rate * seconden;
  si[10] = (rate >> 12) & 0xFF;
  si[11] = (rate >> 4) & 0xFF;
  si[12] = ((rate & 0x0F) << 4) | ((kanalen - 1) << 1) | (((bits - 1) >> 4) & 0x01);
  si[13] = (((bits - 1) & 0x0F) << 4) | ((monsters >> 32) & 0x0F);
  si[14] = (monsters >> 24) & 0xFF;
  si[15] = (monsters >> 16) & 0xFF;
  si[16] = (monsters >> 8) & 0xFF;
  si[17] = monsters & 0xFF;
  b.add(si);
  final v = BytesBuilder();
  List<int> le32(int x) => [x & 0xFF, (x >> 8) & 0xFF, (x >> 16) & 0xFF, (x >> 24) & 0xFF];
  final verkoper = utf8.encode('toets'), commentaar = utf8.encode('TITLE=$titel');
  v
    ..add(le32(verkoper.length))
    ..add(verkoper)
    ..add(le32(1))
    ..add(le32(commentaar.length))
    ..add(commentaar);
  final vb = v.takeBytes();
  b.add([0x84, (vb.length >> 16) & 0xFF, (vb.length >> 8) & 0xFF, vb.length & 0xFF]);
  b.add(vb);
  return b.takeBytes();
}

/// Een persing van *All Saints* zoals MusicBrainz haar geeft (de cache van 26-10-2026).
MbRelease _persing(String id, String land, String datum, int nummers, {String? catno}) => MbRelease.from({
      'id': id,
      'title': 'All Saints',
      'status': 'Official',
      'country': land,
      'date': datum,
      'label-info': [
        {'catalog-number': catno ?? 'X-$id', 'label': {'name': 'London Records'}}
      ],
      'media': [
        {'format': 'CD', 'track-count': nummers}
      ],
    });

void main() {
  setUp(resetSoortenVoorToets);
  tearDown(resetSoortenVoorToets);

  group('nooit een Japanse persing', () {
    test('Japans herkennen: de code van MusicBrainz en de naam van Discogs', () {
      expect(isJapansePersing('JP'), isTrue);
      expect(isJapansePersing('Japan'), isTrue);
      expect(isJapansePersing(' japan '), isTrue);
      for (final x in ['GB', 'UK', 'XE', 'Europe', 'US', '', null]) {
        expect(isJapansePersing(x), isFalse, reason: '$x');
      }
      expect(zonderJapansePersingen(['JP', 'GB', 'Japan', 'US'], (x) => x), ['GB', 'US']);
      expect(zonderJapansePersingen(['JP', 'Japan'], (x) => x), ['JP', 'Japan'],
          reason: 'alleen Japans: een Japanse nummerlijst is meer dan geen');
    });

    test('DE KERN: All Saints — de Japanse cd kwam het eerst uit, en staat toch achteraan', () {
      final uit = MusicBrainzService.orderByPreference([
        _persing('jp97', 'JP', '1997-10-15', 12, catno: 'POCD-1260'),
        _persing('xe97', 'XE', '1997-11-24', 13, catno: '828 979.2'),
        _persing('ch98', 'CH', '1998-02-16', 13, catno: '556 004-2'),
        _persing('jp98', 'JP', '1998-05-20', 15, catno: 'POCD-1268'),
      ]);
      expect([for (final r in uit) r.mbid], ['xe97', 'ch98', 'jp97', 'jp98']);
    });

    test('Discogs: ook een Japanse hoofdpersing gaat achter een andere', () {
      DiscogsVersion v(int id, String land) => DiscogsVersion(id, 'CD, Album', 'CD', 'London', 'C$id', land, '1997');
      final uit = DiscogsService.orderByPreference([v(1, 'Japan'), v(2, 'UK'), v(3, 'Europe')], main: 1);
      expect([for (final x in uit) x.id], [2, 3, 1]);
      expect(DiscogsService.orderByPreference([v(1, 'UK'), v(2, 'Europe')], main: 2).first.id, 2,
          reason: 'zonder Japan beslist de hoofdpersing zoals altijd');
    });

    test('aangesloten: de keuze van de nummerlijst ziet geen Japanse persing, en Discogs probeert ze als laatste', () {
      expect(_bron('lib/album_facts_resolver.dart'),
          contains('final all = zonderJapansePersingen(await mb.editionsOf(g.mbid, tracklists: true), (r) => r.country);'));
      final discogs = _bron('lib/discogs.dart');
      expect(discogs, contains('      for (final japans in const [false, true]) {'));
      expect(discogs, contains('final ordered = [for (final v in alle) if (isJapansePersing(v.country) == japans) v];'));
    });

    test('wat al op een persing stond, kiest één keer opnieuw — uit de cache, en het oude antwoord blijft intussen', () {
      const oud = {'uid': 'a', 'schema': kAlbumFactsSchema, 'hash': 'h', 'source': 'MusicBrainz', 'mbid': 'jp97'};
      final f = AlbumFacts.fromJson(oud)!;
      expect(f.persingKeuze, 0);
      expect(needsResolve(f, trackSetHash: 'h', nowMs: 0), isTrue);
      final nieuw = AlbumFacts.fromJson({...oud, 'persing': kPersingKeuze})!;
      expect(needsResolve(nieuw, trackSetHash: 'h', nowMs: 0), isFalse);
      final zonder = AlbumFacts.fromJson({'uid': 'b', 'schema': kAlbumFactsSchema, 'hash': 'h', 'source': 'Discogs'})!;
      expect(needsResolve(zonder, trackSetHash: 'h', nowMs: 0), isFalse, reason: 'geen MusicBrainz-persing: niets te kiezen');
      const vers = AlbumFacts(uid: 'c', trackSetHash: 'h', mbid: 'xe97');
      expect(vers.toJson()['persing'], kPersingKeuze, reason: 'een nieuw antwoord draagt de regel waarmee het gekozen werd');
      expect(needsResolve(vers, trackSetHash: 'h', nowMs: 0), isFalse);
    });
  });

  group('cd meteen', () {
    test('alleen een cd, en alleen als de vingerafdruk zeker is', () {
      expect(cdMeteenHouden(Kopiesoort.cd, .93), isTrue);
      expect(cdMeteenHouden(Kopiesoort.cd, .86), isFalse, reason: 'twijfelzone: eerst luisteren');
      expect(cdMeteenHouden(Kopiesoort.cd, 0), isFalse, reason: 'zonder meting is er niets nagekeken');
      expect(cdMeteenHouden(Kopiesoort.studio, .99), isFalse);
      expect(cdMeteenHouden(Kopiesoort.vinyl, .99), isFalse);
    });

    group('op de pc', () {
      late Directory map;
      late DownloadManager d;
      setUp(() {
        Tidaler.zetVoorToets(pad: null);
        versies.wis();
        resetEchtheidVoorTest();
        map = Directory.systemTemp.createTempSync('dm_cd_meteen_');
        d = DownloadManager(OnlineService(AppSettings()), SoulseekService(AppSettings()), map.path, () async {})
          ..twijfel = Twijfellijst('${map.path}/twijfel.json')
          ..soortvragen = Soortvragen('${map.path}/soortvragen.json');
      });
      tearDown(() {
        Tidaler.resetLookup();
        versies.wis();
        resetEchtheidVoorTest();
        try {
          map.deleteSync(recursive: true);
        } catch (_) {}
      });

      File eigen({int rate = 96000, int bits = 24}) => File('${map.path}/Albums/Daft Punk/Discovery/06 - Nightvision.flac')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_flac(rate: rate, bits: bits, seconden: 235));

      Track nummer(File f) => Track(path: f.path, title: 'Nightvision', artist: 'Daft Punk', album: 'Discovery',
          duration: const Duration(seconds: 228));

      test('DE KERN: de gevraagde cd komt meteen als versie naast je studionummer — geen "klaar", niets te kiezen', () async {
        final mijn = eigen();
        zetSoort(mijn.path, Kopiesoort.studio);
        final v = Soortvraag(pad: mijn.path, soort: Kopiesoort.cd, artiest: 'Daft Punk', titel: 'Nightvision', seconden: 228, sindsMs: 1);
        d.soortvragen!.zet(v);
        final binnen = File('${map.path}/_keuring/a/06 Nightvision.flac')
          ..createSync(recursive: true)
          ..writeAsBytesSync(_flac(seconden: 228));
        expect(await d.zetKlaarVoorToets(v, binnen, 'Soulseek a', r'@@a\Discovery (CD)\06.flac', .93), isTrue);
        final zin = await d.houdCdMeteenVoorToets(v);
        expect(zin, 'cd binnen: Daft Punk — Nightvision');
        expect(zin, isNot(contains('klaar')), reason: 'met "klaar" krijgt de melding een knop Kiezen');
        expect(readFlacTags16(mijn), 24, reason: 'je studio blijft het nummer');
        final vs = versies.versiesVan(mijn.path);
        expect(vs.single.soort, Kopiesoort.cd);
        expect(File(vs.single.pad).existsSync(), isTrue);
        expect(versies.speelVersie(mijn.path, ankerSoort: Kopiesoort.studio), isNull, reason: 'je standaard blijft');
        expect(twijfelVoor(mijn.path), isNull, reason: 'er staat niets meer klaar');
        expect(d.soortvragen!.van(mijn.path), isNull, reason: 'de vraag is beantwoord');
      });

      test('een nummer dat al cd-kwaliteit heeft, of al een cd ernaast, zoekt er geen tweede', () async {
        final cd = eigen(rate: 44100, bits: 16);
        expect(d.heeftSoortAl(cd.path, Kopiesoort.cd), isTrue, reason: '16/44,1 verliesvrij is cd-kwaliteit');
        expect(d.heeftSoortAl(cd.path, Kopiesoort.studio), isFalse);
        expect(await d.vraagSoort([nummer(cd)], Kopiesoort.cd), 'Dit nummer heeft al cd-kwaliteit');
        expect(d.soortvragen!.van(cd.path), isNull);

        final studio = eigen();
        expect(d.heeftSoortAl(studio.path, Kopiesoort.cd), isFalse);
        versies.voegToe(studio.path, Versie(pad: '${map.path}/Albums/Daft Punk/Discovery (cd)/06 - Nightvision.flac', soort: Kopiesoort.cd),
            ankerSoort: Kopiesoort.studio);
        expect(d.heeftSoortAl(studio.path, Kopiesoort.cd), isTrue, reason: 'de cd staat er al als versie');
      });

      test('DE GRENS: een cd die bewezen nep is, heeft geen cd-kwaliteit — die zoekt hij wel', () async {
        final nep = eigen(rate: 44100, bits: 16);
        onthoudOordeelVanPc(
            nep.path,
            Echtheidsoordeel.fromJson({
              'v': 2,
              'bits': 'onbekend',
              'boven': 'onbekend',
              'band': 'afgekapt',
              'afkapHz': 16000,
              'wandDb': 60,
              'vensters': 700,
              'integriteit': 'klopt',
            })!);
        expect(bewezenNep(nep.path), isTrue);
        expect(d.heeftSoortAl(nep.path, Kopiesoort.cd), isFalse);
      });

      test('DE GRENS: een studio-VERSIE die bewezen nep is, telt ook niet — "studio downloaden" zoekt weer', () async {
        // Saber, 27-10-2026, Nothing Compares 2 U: "Kan ik weer klikken op studio downloaden of hoeft dit niet?"
        final cd = eigen(rate: 44100, bits: 16);
        final studio = '${map.path}/Albums/Daft Punk/Discovery (studio)/06 - Nightvision.flac';
        versies.voegToe(cd.path, Versie(pad: studio, soort: Kopiesoort.studio), ankerSoort: Kopiesoort.cd);
        expect(d.heeftSoortAl(cd.path, Kopiesoort.studio), isTrue);
        onthoudOordeelVanPc(
            studio,
            const Echtheidsoordeel(
                    bits: Bitdiepte.spreektNietTegen,
                    boven: Bovenband.onbekend,
                    band: Bandbreedte.vermoedelijk,
                    afkapHz: 20350,
                    wandDb: 41.5)
                .bewezenDoor('je cd loopt door tot 20,95 kHz'));
        expect(d.heeftSoortAl(cd.path, Kopiesoort.studio), isFalse);
      });

      test('een studio-VERSIE met een muur rond 20 kHz is geen bewezen studio — "studio downloaden" zoekt (28-10-2026)', () async {
        final cd = eigen(rate: 44100, bits: 16);
        final studio = '${map.path}/Albums/Daft Punk/Discovery (studio)/06 - Nightvision.flac';
        versies.voegToe(cd.path, Versie(pad: studio, soort: Kopiesoort.studio), ankerSoort: Kopiesoort.cd);
        expect(d.heeftSoortAl(cd.path, Kopiesoort.studio), isTrue);
        onthoudOordeelVanPc(
            studio,
            const Echtheidsoordeel(
                bits: Bitdiepte.spreektNietTegen,
                boven: Bovenband.onbekend,
                band: Bandbreedte.vermoedelijk,
                gebruikteBits: 24,
                afkapHz: 20850,
                wandDb: 63.7));
        expect(bewezenNep(studio), isFalse, reason: 'niet bewezen nep — maar ook niet bewezen studio');
        expect(d.heeftSoortAl(cd.path, Kopiesoort.studio), isFalse);
      });

      test('je NUMMER is een "studio" met een muur rond 20 kHz: ook dan zoekt "studio downloaden" (28-10-2026)', () async {
        final mijn = eigen(rate: 44100, bits: 24);
        zetSoort(mijn.path, Kopiesoort.studio);
        expect(d.heeftSoortAl(mijn.path, Kopiesoort.studio), isTrue);
        onthoudOordeelVanPc(
            mijn.path,
            const Echtheidsoordeel(
                bits: Bitdiepte.spreektNietTegen,
                boven: Bovenband.onbekend,
                band: Bandbreedte.vermoedelijk,
                gebruikteBits: 24,
                afkapHz: 20850,
                wandDb: 63.7));
        expect(d.heeftSoortAl(mijn.path, Kopiesoort.studio), isFalse);
      });

      test('een cd die al klaarstond (van vóór de update) wordt bij het nakijken gehouden; een twijfelachtige niet', () async {
        final mijn = eigen();
        zetSoort(mijn.path, Kopiesoort.studio);
        final v = Soortvraag(pad: mijn.path, soort: Kopiesoort.cd, artiest: 'Daft Punk', titel: 'Nightvision', seconden: 228, sindsMs: 1);
        d.soortvragen!.zet(v);
        final binnen = File('${map.path}/_keuring/b/06 Nightvision.flac')
          ..createSync(recursive: true)
          ..writeAsBytesSync(_flac(seconden: 228));
        expect(await d.zetKlaarVoorToets(v, binnen, 'Soulseek b', r'@@b\30 (2021)\06.flac', .92), isTrue);
        expect(twijfelVoor(mijn.path)?.soort, 'cd', reason: 'zo stonden de acht van 30 klaar');
        await d.soortvragenNakijken();
        expect(twijfelVoor(mijn.path), isNull);
        expect(versies.versiesVan(mijn.path).single.soort, Kopiesoort.cd);
        expect(d.klaarMelding.value, 'Een klaargezette cd is bewaard');

        final ander = File('${map.path}/Albums/Daft Punk/Discovery/07 - Too Long.flac')
          ..createSync(recursive: true)
          ..writeAsBytesSync(_flac(rate: 96000, bits: 24, seconden: 600));
        final w = Soortvraag(pad: ander.path, soort: Kopiesoort.cd, artiest: 'Daft Punk', titel: 'Too Long', seconden: 600, sindsMs: 1);
        d.soortvragen!.zet(w);
        final twijfelachtig = File('${map.path}/_keuring/c/07.flac')
          ..createSync(recursive: true)
          ..writeAsBytesSync(_flac(seconden: 600, titel: 'Too Long'));
        await d.zetKlaarVoorToets(w, twijfelachtig, 'Soulseek c', r'@@c\07.flac', .86);
        await d.soortvragenNakijken();
        expect(twijfelVoor(ander.path)?.soort, 'cd', reason: 'in de twijfelzone kies je zelf');
        d.soortvragen!.verwijder(ander.path);
      });

      test('vragen: wat hij zegt bij een cd, en bij studio zoals altijd', () async {
        final mijn = eigen();
        final zin = await d.vraagSoort([nummer(mijn)], Kopiesoort.cd);
        expect(zin, 'Zoekt cd-kwaliteit voor "Nightvision". Wat hij vindt, bewaart hij meteen — je hoeft niets te kiezen.');
        await d.trekSoortvraagIn(mijn.path);
        expect(await d.vraagSoort([nummer(mijn)], Kopiesoort.vinyl), contains('je vervangt pas als jij kiest'));
        await d.trekSoortvraagIn(mijn.path);
      });

      test('aangesloten: de keuring houdt een cd meteen, een nummer dat niet verliesvrij is wordt vervangen', () {
        final online = _bron('lib/online.dart');
        expect(online, contains('      if (cdMeteenHouden(v.soort, score ?? 0)) {\n        if (await _houdCdMeteen(v.pad, naam) case final zin?) {'));
        expect(online, contains('    final zin = await vervangDoorTwijfel(pad, alsVersie: isVerliesvrij(soortVan(pad)));'));
        expect(online, contains('      if (heeftSoortAl(t.path, soort)) {'));
      });
    });
  });
}

/// De diepte van [f] volgens zijn kop.
int readFlacTags16(File f) {
  final b = f.readAsBytesSync();
  return (((b[8 + 12] & 0x01) << 4) | (b[8 + 13] >> 4)) + 1;
}
