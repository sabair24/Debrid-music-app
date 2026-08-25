/// Een heropname is een andere opname, en mag niet als dubbel gewist worden.
///
/// **Het gemelde geval, en waarom hier een toets op staat.** Op *My Songs* van Sting staat een
/// heropname uit 2019 van "Fields of Gold" (3:47). In de bibliotheek stond de plaat uit 1993
/// (3:39). Dezelfde artiest, dezelfde titel. De app haalde de heropname netjes binnen, besloot toen
/// "die heb je al", en **wiste het zojuist gedownloade bestand van schijf** met de melding
/// *"had je al — beste versie behouden"*.
///
/// Dat is de ergste soort fout die deze app kan maken: verlies dat je niet terugdraait en dat zich
/// als succes meldt. De toetsen hieronder leggen vast dat de klok altijd een stem heeft — dat was
/// namelijk precies wat er misging. Met een officiële uitgave onder de download was `isAuthoritative`
/// waar, en daarmee was de vraag "is dit dezelfde opname?" beantwoord vóórdat er ooit naar een
/// looptijd gekeken werd.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart';
import 'package:flutter_test/flutter_test.dart';

/// Zelfde minimale FLAC als in `place_file_test.dart`: STREAMINFO voor de looptijd plus tags.
Uint8List buildFlac(List<String> comments, {int seconds = 240, int sampleRate = 44100}) {
  final b = BytesBuilder();
  b.add(ascii.encode('fLaC'));
  b.add([0x00, 0x00, 0x00, 0x22]);
  final total = seconds * sampleRate;
  final si = Uint8List(34);
  si[10] = (sampleRate >> 12) & 0xFF;
  si[11] = (sampleRate >> 4) & 0xFF;
  si[12] = (sampleRate & 0x0F) << 4;
  si[13] = (total >> 32) & 0x0F;
  si[14] = (total >> 24) & 0xFF;
  si[15] = (total >> 16) & 0xFF;
  si[16] = (total >> 8) & 0xFF;
  si[17] = total & 0xFF;
  b.add(si);

  final v = BytesBuilder();
  final vendor = utf8.encode('test');
  v.add(_le32(vendor.length));
  v.add(vendor);
  v.add(_le32(comments.length));
  for (final c in comments) {
    final bytes = utf8.encode(c);
    v.add(_le32(bytes.length));
    v.add(bytes);
  }
  final vb = v.takeBytes();
  b.add([0x84, (vb.length >> 16) & 0xFF, (vb.length >> 8) & 0xFF, vb.length & 0xFF]);
  b.add(vb);
  return b.takeBytes();
}

List<int> _le32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

void main() {
  group('het merk wijst naar de uitgave', () {
    test('"(My Songs Version)" op de plaat My Songs is identiteit, geen ruis', () {
      // Deze twee regels zijn het hele verschil. De eerste mag de catalogustitel houden, de tweede
      // hoort door de persing overschreven te worden — daar is die vervanging voor bedoeld.
      expect(versieNoemtDeUitgave('Fields Of Gold (My Songs Version)', 'My Songs'), isTrue);
      expect(versieNoemtDeUitgave('Rock with You (Single Version)', 'Off the Wall'), isFalse);
    });

    test('een deluxe-uitgave telt ook mee', () {
      expect(versieNoemtDeUitgave('Brand New Day (My Songs Version)', 'My Songs (Deluxe)'), isTrue);
    });

    test('"(Live)" noemt nooit een plaat', () {
      // Er blijft na het generieke woord niets over om aan de albumtitel te toetsen, en dat hoort:
      // een live-opname is een andere opname, op welke plaat hij ook staat.
      expect(versieNoemtDeUitgave('Roxanne (Live)', 'My Songs'), isFalse);
      expect(versieNoemtDeUitgave('Fields Of Gold (Radio Edit)', 'My Songs'), isFalse);
    });

    test('een titel zonder merk verandert niets', () {
      expect(versieNoemtDeUitgave('Fields Of Gold', 'My Songs'), isFalse);
      expect(versieNoemtDeUitgave('Fields Of Gold', ''), isFalse);
    });

    test('een merk dat een ándere plaat noemt telt niet', () {
      expect(versieNoemtDeUitgave('Fields Of Gold (My Songs Version)', 'Ten Summoners Tales'),
          isFalse);
    });
  });

  group('de filer wist een heropname niet meer', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('heropname_test'));
    tearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    File staged(String name, Uint8List bytes) {
      final d = Directory('${root.path}${Platform.pathSeparator}_inkomend')
        ..createSync(recursive: true);
      final f = File('${d.path}${Platform.pathSeparator}$name');
      f.writeAsBytesSync(bytes);
      return f;
    }

    File bestaand(String naam, Uint8List bytes) {
      final d = Directory('${root.path}${Platform.pathSeparator}Albums'
          '${Platform.pathSeparator}Sting${Platform.pathSeparator}Ten Summoners Tales')
        ..createSync(recursive: true);
      final f = File('${d.path}${Platform.pathSeparator}$naam');
      f.writeAsBytesSync(bytes);
      return f;
    }

    /// De uitgave onder de download: dit is wat `isAuthoritative` waar maakte en daarmee de klok
    /// buitenspel zette.
    const uitgave = TrackTags(
      title: 'Fields of Gold',
      artist: 'Sting',
      album: 'My Songs',
      albumArtist: 'Sting',
      trackNo: 7,
      trackTotal: 15,
      year: 2019,
      seconds: 227,
    );

    test('DE KERN: 3:47 naast 3:39 blijft bestaan, en wordt niet gewist', () async {
      // Precies het gemelde geval. De bibliotheek zegt "die heb je al" en wijst naar de plaat uit
      // 1993; zonder de klok werd het nieuwe bestand daarop gelegd, verloor het op grootte, en
      // verdween het van schijf.
      final oud = bestaand('06 - Fields of Gold.flac',
          buildFlac(['TITLE=Fields of Gold', 'ARTIST=Sting', 'ALBUM=Ten Summoners Tales'],
              seconds: 219));
      final nieuw = staged('Sting - My Songs - 07 - Fields of Gold.flac',
          buildFlac(['TITLE=Fields of Gold', 'ARTIST=Sting', 'ALBUM=My Songs'], seconds: 227));

      final uit = await placeFileDetailed(nieuw, root.path,
          tags: uitgave, staatAl: (a, t, {int? seconds}) => oud.path);

      expect(uit.how, isNot(Placement.duplicate),
          reason: 'een heropname van 3:47 is niet dezelfde opname als 3:39');
      expect(File(uit.path).existsSync(), isTrue, reason: 'de heropname staat op schijf');
      expect(oud.existsSync(), isTrue, reason: 'en de plaat uit 1993 staat er nog steeds');
    });

    test('dezelfde opname blijft wél één bestand', () async {
      // De andere kant op, en net zo belangrijk: dit is waar de dubbelregel voor bestaat. Zou dit
      // óók twee bestanden opleveren, dan had de reparatie het opwaarderen gesloopt.
      final oud = bestaand('06 - Fields of Gold.flac',
          buildFlac(['TITLE=Fields of Gold', 'ARTIST=Sting', 'ALBUM=Ten Summoners Tales'],
              seconds: 219));
      final nieuw = staged('Fields of Gold.flac',
          buildFlac(['TITLE=Fields of Gold', 'ARTIST=Sting', 'ALBUM=Ten Summoners Tales'],
              seconds: 220));

      final uit = await placeFileDetailed(nieuw, root.path,
          tags: const TrackTags(
            title: 'Fields of Gold',
            artist: 'Sting',
            album: 'Ten Summoners Tales',
            albumArtist: 'Sting',
            trackNo: 6,
            trackTotal: 12,
            year: 1993,
            seconds: 219,
          ),
          staatAl: (a, t, {int? seconds}) => oud.path);

      expect(uit.how, Placement.duplicate, reason: 'één seconde verschil is één opname');
    });

    test('zonder leesbare looptijd blijft alles zoals het was', () async {
      // Het veto spreekt alleen als er aan beide kanten iets te meten valt. Kan dat niet, dan is
      // het oude gedrag beter dan een gok — dit legt vast dat de reparatie geen nieuwe gok is.
      final oud = bestaand('06 - Fields of Gold.mp3', Uint8List.fromList(List.filled(9000, 7)));
      final nieuw = staged('Fields of Gold.mp3', Uint8List.fromList(List.filled(500, 7)));

      final uit = await placeFileDetailed(nieuw, root.path,
          tags: uitgave, staatAl: (a, t, {int? seconds}) => oud.path);

      expect(uit.how, Placement.duplicate);
    });
  });

  group('het ritme van de TorBox-peiling', () {
    test('de eerste seconden snel, daarna rustiger', () {
      // Het liep de verkeerde kant op: het begon op twee seconden en werd elke ronde trager, tot
      // tien. Juist in het venster waarin een gecachte torrent klaar komt zat de app dus het langst
      // niets te doen.
      expect(OnlineService.tempoVoorPeiling(0), 400);
      expect(OnlineService.tempoVoorPeiling(5999), 400);
      expect(OnlineService.tempoVoorPeiling(6000), 1500);
      expect(OnlineService.tempoVoorPeiling(44999), 1500);
      expect(OnlineService.tempoVoorPeiling(45000), 5000);
      expect(OnlineService.tempoVoorPeiling(600000), 5000);
    });

    test('het wordt nooit trager dan vijf seconden en nooit sneller dan 400 ms', () {
      for (var t = 0; t < 300000; t += 250) {
        final d = OnlineService.tempoVoorPeiling(t);
        expect(d, greaterThanOrEqualTo(400));
        expect(d, lessThanOrEqualTo(5000));
      }
    });

    test('het gaat alleen omlaag in tempo, nooit weer omhoog', () {
      // Een ritme dat heen en weer springt is niet te voorspellen en niet uit te leggen.
      var vorige = 0;
      for (var t = 0; t < 300000; t += 250) {
        final d = OnlineService.tempoVoorPeiling(t);
        expect(d, greaterThanOrEqualTo(vorige));
        vorige = d;
      }
    });
  });
}
