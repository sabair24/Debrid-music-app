// "Op dit toestel" los van "Mijn downloads", met tabs, Alles afspelen/Shuffle en een eigen zoekveld (Saber, 29-10-2026:
// "downloads en op een toestel opslaan zijn 2 verschillende dingen e … moet ik kunnen shuffelen en allemaal spelen
// kunnen doen, plus ook een zoek functie"). Hier: wat er in welke volgorde staat ([opToestelLijst]), en de bedrading.
import 'dart:io';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/offline.dart';
import 'package:debridmusic/ui/op_toestel.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String pad, String titel, String artiest, String album, {int nr = 1}) =>
    Track(path: pad, title: titel, artist: artiest, album: album, trackNo: nr);

OfflineTrack _o(Track t, DateTime wanneer) => OfflineTrack(
    path: t.path, file: '/kopie/${t.path}', bytes: 1000, title: t.title, artist: t.artist, album: t.album, savedAt: wanneer);

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final crazy = _t('b/crazy.flac', 'Crazy', 'Britney Spears', 'Crazy');
  final toxic = _t('b/toxic.flac', 'Toxic', 'Britney Spears', 'In the Zone', nr: 6);
  final angie = _t('r/angie.flac', 'Angie', 'The Rolling Stones', 'Goats Head Soup', nr: 5);
  final nietHier = _t('r/doom.flac', 'Doo Doo Doo', 'The Rolling Stones', 'Goats Head Soup', nr: 1);
  final albums = [
    Album('Crazy', 'Britney Spears', [crazy]),
    Album('In the Zone', 'Britney Spears', [toxic]),
    Album('Goats Head Soup', 'The Rolling Stones', [nietHier, angie]),
  ];
  final perPad = {for (final t in [crazy, toxic, angie, nietHier]) t.path: t};
  // Zoals OfflineStore.tracks: nieuwste eerst.
  final opgeslagen = [
    _o(angie, DateTime(2026, 10, 29, 9)),
    _o(crazy, DateTime(2026, 10, 28, 20)),
    _o(toxic, DateTime(2026, 10, 27, 12)),
  ];
  ({List<Track> nummers, List<Album> albums}) lijst({String zoek = '', bool az = false}) =>
      opToestelLijst(opgeslagen: opgeslagen, nummerVan: (p) => perPad[p], albums: albums, zoek: zoek, az: az);

  test('DE KERN: laatst opgeslagen eerst, voor nummers en voor platen', () {
    final l = lijst();
    expect([for (final t in l.nummers) t.title], ['Angie', 'Crazy', 'Toxic']);
    expect([for (final a in l.albums) a.title], ['Goats Head Soup', 'Crazy', 'In the Zone'],
        reason: 'een plaat waarvan maar één nummer hier staat, hoort er ook bij — die helft speelt');
  });

  test('A–Z: op artiest (zonder "The"), dan plaat, dan nummer', () {
    final l = lijst(az: true);
    expect([for (final t in l.nummers) t.title], ['Crazy', 'Toxic', 'Angie']);
    expect([for (final a in l.albums) a.title], ['Crazy', 'In the Zone', 'Goats Head Soup']);
  });

  test('zoeken: alleen wat hier staat, op titel, artiest en album, elk woord', () {
    expect([for (final t in lijst(zoek: 'britney').nummers) t.title], ['Crazy', 'Toxic']);
    expect([for (final t in lijst(zoek: 'zone').nummers) t.title], ['Toxic']);
    expect([for (final t in lijst(zoek: 'rolling doo').nummers) t.title], isEmpty,
        reason: '"Doo Doo Doo" staat niet op dit toestel');
    expect([for (final a in lijst(zoek: 'goats').albums) a.title], ['Goats Head Soup']);
    expect([for (final t in lijst(zoek: 'CRÄZY').nummers) t.title], ['Crazy'], reason: 'hoofdletters en accenten tellen niet');
  });

  test('een nummer dat de bibliotheek niet kent, valt weg in plaats van de lijst te breken', () {
    final l = opToestelLijst(
        opgeslagen: [...opgeslagen, _o(_t('x/weg.flac', 'Weg', 'X', 'Y'), DateTime(2026, 10, 29, 10))],
        nummerVan: (p) => perPad[p],
        albums: albums);
    expect(l.nummers, hasLength(3));
  });

  test('DE KERN: Mijn downloads toont niet meer wat op dit toestel staat; Op dit toestel heeft alles', () {
    final main = _bron('lib/main.dart');
    expect(main, isNot(contains('_OfflineSection')), reason: 'downloads en op een toestel opslaan zijn 2 verschillende dingen');
    final pagina = main.substring(main.indexOf('class _OpDitToestelViewState'), main.indexOf('class _Overzetten'));
    for (final k in ['toestel-shuffle', 'toestel-alles', 'toestel-zoek', 'toestel-volgorde', 'toestel-alles-weg']) {
      expect(pagina, contains("ValueKey('$k')"), reason: k);
    }
    expect(pagina, contains('final teSpelen = pcBereikbaar ? lib.tracks : alleHier;'),
        reason: 'Saber: met de pc bereikbaar de hele bibliotheek, zonder pc alleen wat hier staat');
    expect(pagina, contains('_Overzetten(rand: rand)'), reason: 'wat onderweg is naar dit toestel, staat hier');
    for (final tab in ['albums', 'nummers', 'artiesten', 'afspeellijsten', 'favorieten']) {
      expect(main, contains('_ToestelTab.$tab'), reason: tab);
    }
  });
}
