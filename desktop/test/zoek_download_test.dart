// De downloadknop bij de nummers in Online zoeken → Bladeren (Saber, 20-10-2026: "de automatische download
// functie bij nummers daar ook zien, zo kan ik snel een losse song zoeken en downloaden").
//
// Online zoeken is zonder Soulseek, Deezer en een bibliotheek niet als widget te bouwen; de aansluiting
// staat daarom hier als brontekst vast, net als in discografie_vast_test.dart.
import 'dart:io';

import 'package:debridmusic/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final main = _bron('lib/main.dart');
  final catalog = _bron('lib/catalog.dart');

  test('elke rij in Nummers heeft de downloadknop van de albumpagina', () {
    final rij = main.substring(main.indexOf('Widget _browseTrackRow('), main.indexOf('String _zoekSleutel('));
    expect(rij, contains('_downloadControl(context,'));
    expect(rij, contains('jobKey: _zoekSleutel(t), onDownload: () => _downloadHit(t)'));
    expect(rij, contains('ownedTrack(t.artist, t.title) != null'), reason: 'wat je al hebt, krijgt het vinkje');
    expect(rij, contains('SourcesView(query: t.query)'), reason: 'een tik op de rij opent nog steeds de bronnen');
  });

  test('de knop kiest op looptijd: geen radio-edit of liveversie onder de naam van het nummer', () {
    final f = main.substring(main.indexOf('Future<void> _downloadHit('), main.indexOf('/// Zelfde geheugen van één als bij [SourcesView]'));
    expect(f, contains('titel: t.title, seconden: t.seconden, artiest: t.artist, album: t.album'));
    expect(f, contains('seconds: t.seconden,'));
    expect(f, contains('dm.zoekEnHaal('), reason: 'dezelfde weg als op de albumpagina, ook vanaf de telefoon');
  });

  test('een zoektreffer draagt de looptijd en het album van Deezer', () {
    expect("seconden: (t['duration'] as num?)?.toInt(),".allMatches(catalog).length, 2,
        reason: 'searchTracks en chartTracks');
    const h = CatalogTrackHit('Remember', 'Josh Groban', null, album: 'Troy', seconden: 245);
    expect(h.seconden, 245);
    expect(h.album, 'Troy');
    expect(const CatalogTrackHit('X', 'Y', null).seconden, isNull, reason: 'oude aanroepen blijven werken');
  });
}
