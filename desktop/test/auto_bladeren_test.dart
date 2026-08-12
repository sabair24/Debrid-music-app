/// De boom die Android Auto te zien krijgt.
///
/// Deze toetsen bestaan omdat er in de auto niemand is die kan nakijken wat er misgaat: je tikt iets
/// aan en er gebeurt niets, of er speelt iets anders dan je koos. Alles wat hier vastligt is een
/// geval waarin dat zou kunnen gebeuren.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/auto_bladeren.dart';
import 'package:debridmusic/models.dart';

Track tr(String titel, {String album = 'Alb', String artiest = 'A', String? pad}) => Track(
      path: pad ?? 'D:\\m\\$artiest - $titel.flac',
      title: titel,
      artist: artiest,
      album: album,
      trackNo: 1,
      isFlac: true,
    );

Album alb(String artiest, String titel, List<Track> ts) => Album(titel, artiest, ts);

AutoBron bron({
  List<Album> albums = const [],
  List<Track> recent = const [],
  List<Track> favorieten = const [],
  List<Track> verder = const [],
  List<({String id, String naam})> lijsten = const [],
  Map<String, List<Track>> lijstInhoud = const {},
}) =>
    (
      albums: () => albums,
      recent: () => recent,
      favorieten: () => favorieten,
      verder: () => verder,
      afspeellijsten: () => lijsten,
      nummersVanLijst: (id) => lijstInhoud[id] ?? const [],
    );

void main() {
  group('de wortel', () {
    test('is kort, en het meest gebruikte staat bovenaan', () {
      final k = autoKinderen(AutoId.wortel, bron());
      expect(k.length, lessThanOrEqualTo(6), reason: 'achter het stuur telt elke regel');
      expect(k.first.title, 'Verder waar je was');
      expect([for (final i in k) i.title], containsAllInOrder(['Verder waar je was', 'Albums']));
      expect(k.every((i) => i.playable == false), isTrue, reason: 'de wortel bladert, hij speelt niet');
    });
  });

  group('een album met spaties in de naam', () {
    // DIT is de fout die ik zelf maakte: het id werd op een spatie gesplitst, en vrijwel elke
    // artiest en titel bevat er een. "Vaya Con Dios / The Best Of" opende dan niets, en in de auto
    // zie je dan alleen dat er niets gebeurt.
    final a = alb('Vaya Con Dios', 'The Best Of', [tr('Nah Neh Nah'), tr('Puerto Rico')]);

    test('is terug te vinden via zijn eigen id', () {
      final b = bron(albums: [a]);
      final item = autoKinderen(AutoId.albums, b).single;
      final kinderen = autoKinderen(item.id, b);
      expect([for (final k in kinderen) k.title], ['Nah Neh Nah', 'Puerto Rico']);
    });

    test('en speelt zijn eigen nummers', () {
      final b = bron(albums: [a]);
      final item = autoKinderen(AutoId.albums, b).single;
      expect([for (final t in autoSpeellijstVoor(item.id, b)) t.title],
          ['Nah Neh Nah', 'Puerto Rico']);
    });

    test('het id valt uiteen op de scheider, niet op een spatie', () {
      final paar = splitsAlbumId(autoKinderen(AutoId.albums, bron(albums: [a])).single.id);
      expect(paar?.artiest, 'Vaya Con Dios');
      expect(paar?.titel, 'The Best Of');
    });
  });

  test('een album speelt met één tik — niet eerst openen', () {
    final a = alb('A', 'X', [tr('een'), tr('twee')]);
    expect(autoKinderen(AutoId.albums, bron(albums: [a])).single.playable, isTrue);
  });

  test('een nummer aantikken speelt zijn album verder, vanaf dat nummer', () {
    // Anders stopt de muziek na één liedje, midden op de snelweg.
    final a = alb('A', 'X', [tr('een'), tr('twee'), tr('drie')]);
    final b = bron(albums: [a]);
    // Een album is speelbaar EN doorbladerbaar: één tik speelt hem, maar een hoofdunit die er toch
    // in duikt hoort de nummers te zien in plaats van een leeg scherm.
    final albumItem = autoKinderen(autoKinderen(AutoId.artiesten, b).single.id, b).single;
    expect(albumItem.playable, isTrue);
    expect([for (final k in autoKinderen(albumItem.id, b)) k.title], ['een', 'twee', 'drie']);

    final tweede = '${AutoId.nummerVoorvoegsel}${a.tracks[1].path}';
    expect([for (final t in autoSpeellijstVoor(tweede, b)) t.title], ['twee', 'drie', 'een']);
  });

  test('artiesten komen uit de albums, elk één keer', () {
    final b = bron(albums: [
      alb('Adele', '21', [tr('a')]),
      alb('Adele', '25', [tr('b')]),
      alb('Sia', '1000 Forms', [tr('c')]),
    ]);
    final namen = [for (final i in autoKinderen(AutoId.artiesten, b)) i.title];
    expect(namen, ['Adele', 'Sia']);
  });

  test('een afspeellijst levert zijn eigen nummers', () {
    final b = bron(
      lijsten: [(id: 'p1', naam: 'Zaterdagavond')],
      lijstInhoud: {'p1': [tr('een'), tr('twee')]},
    );
    final lijst = autoKinderen(AutoId.afspeellijsten, b).single;
    expect(lijst.title, 'Zaterdagavond');
    expect([for (final t in autoSpeellijstVoor(lijst.id, b)) t.title], ['een', 'twee']);
  });

  group('grenzen en lege gevallen', () {
    test('een lijst wordt afgekapt', () {
      final veel = [for (var i = 0; i < 500; i++) alb('A$i', 'X$i', [tr('t$i')])];
      expect(autoKinderen(AutoId.albums, bron(albums: veel)).length, autoMaxPerLijst);
    });

    test('een lege knoop zegt "nog niets" in plaats van niets', () {
      // Een leeg scherm leest in een auto als kapot: je tikt, er gebeurt niets, en je kijkt nog eens
      // terwijl je zou moeten rijden.
      final k = autoKinderenMetLeegmelding(AutoId.favorieten, bron());
      expect(k.single.title, 'Nog geen favorieten');
      expect(k.single.playable, isFalse);
    });

    test('de wortel krijgt GEEN leegmelding', () {
      expect(autoKinderenMetLeegmelding(AutoId.wortel, bron()).length, greaterThan(1));
    });

    test('een onbekend id levert niets, en speelt niets', () {
      final b = bron(albums: [alb('A', 'X', [tr('een')])]);
      expect(autoKinderen('kaboem', b), isEmpty);
      expect(autoSpeellijstVoor('kaboem', b), isEmpty,
          reason: 'anders loopt de vorige wachtrij door en denk je dat je iets anders koos');
    });

    test('een album dat er niet meer is speelt niets', () {
      final id = '${AutoId.albumVoorvoegsel}Weg${AutoId.scheider}Ook weg';
      expect(autoSpeellijstVoor(id, bron(albums: [alb('A', 'X', [tr('een')])])), isEmpty);
    });
  });
}
