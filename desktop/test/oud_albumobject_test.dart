/// "Dat album staat hier niet (meer)" — terwijl het er gewoon staat.
///
/// **Wat hier misging.** `remoteAlbumId` zoekt in een kaart die op OBJECTIDENTITEIT gesleuteld is, en
/// `_adoptCatalog` maakt bij elke verse catalogus nieuwe [Album]-objecten. Een scherm of een venster
/// dat al open stond houdt dan een exemplaar vast dat nergens meer in staat.
///
/// Gevolg: `remoteAlbumId` gaf null, de pc kreeg geen albumId, en die antwoordde met "Dat album staat
/// hier niet (meer)". Precies de melding die de gebruiker zag, met het album zichtbaar op de
/// achtergrond.
///
/// En het is geen randgeval: één bewerking ververst de catalogus al, dus een tweede bewerking uit
/// hetzelfde venster liep er standaard tegenaan. Bij "Scans toewijzen" gebeuren er drie of vier
/// achter elkaar.
///
/// Een pad is wél stabiel — dezelfde bestanden zijn hetzelfde album — dus dat is de terugval.
library;

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/dtos.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Een catalogus zoals de pc hem stuurt, met één album van twee nummers.
  Map<String, dynamic> catalogusJson({required String albumId, required String titel}) => {
        'artists': [
          {'id': 'a1', 'name': 'Various Artists'}
        ],
        'albums': [
          {
            'id': albumId,
            'artistId': 'a1',
            'artistName': 'Various Artists',
            'title': titel,
            'trackCount': 2,
            'artworkRef': albumId,
          }
        ],
        'tracks': [
          for (var i = 1; i <= 2; i++)
            {
              'id': 't$i',
              'albumId': albumId,
              'artistId': 'a1',
              'title': 'Nummer $i',
              'artistName': 'Various Artists',
              'albumTitle': titel,
              'trackNo': i,
              'durationMs': 200000,
              'streamPath': '/stream/t$i.flac',
              'ext': 'flac',
              'mime': 'audio/flac',
            }
        ],
      };

  late LibraryStore lib;

  setUp(() {
    lib = LibraryStore();
    // Een client is nodig om een catalogus te mogen aannemen; er gaat niets over het net in deze
    // toets — `adoptMirror` raakt hem alleen aan om de streampaden op te lossen.
    lib.remote = RemoteClient(
        RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:1'), token: 'toets'));
    expect(
        lib.adoptMirror(catalogusJson(albumId: 'alb-oud', titel: 'Thunderdome VIII'),
            vanToestel: true),
        isTrue);
  });

  test('een album dat er is, wordt gevonden', () {
    expect(lib.albums, hasLength(1));
    expect(lib.remoteAlbumId(lib.albums.first), 'alb-oud');
  });

  test('een OUD albumobject wordt nog steeds herkend na een verse catalogus', () {
    // Wat een open venster vasthoudt.
    final vastgehouden = lib.albums.first;

    // De pc stuurt een nieuwe catalogus: nieuwe objecten, en hier ook een nieuw id — precies wat er
    // gebeurt als de titel gecorrigeerd wordt, want het id wordt uit de titel afgeleid.
    expect(
        lib.adoptMirror(
            catalogusJson(albumId: 'alb-nieuw', titel: 'Thunderdome VIII: The Devil in Disguise'),
            vanToestel: true),
        isTrue);

    expect(identical(lib.albums.first, vastgehouden), isFalse,
        reason: 'de catalogus hoort nieuwe objecten te maken — anders toetst dit niets');

    // DIT is de bewering. Zonder de terugval op paden gaf dit null, en zag je "Dat album staat hier
    // niet (meer)" terwijl het album gewoon op je scherm stond.
    expect(lib.remoteAlbumId(vastgehouden), 'alb-nieuw',
        reason: 'dezelfde bestanden zijn hetzelfde album, ook als het object vervangen is');
  });

  test('een album met heel andere nummers wordt NIET herkend', () {
    // De terugval mag niet zo ruim zijn dat hij zomaar iets aanwijst: dan zou een bewerking op het
    // verkeerde album landen, en dat is erger dan een nette foutmelding.
    final vreemd = Album('Iets anders', 'Andere Artiest', [
      Track(
        path: '/ergens/anders/01.flac',
        title: 'Onbekend',
        artist: 'Andere Artiest',
        album: 'Iets anders',
        isFlac: true,
      )
    ]);
    expect(lib.remoteAlbumId(vreemd), isNull);
  });

  test('een album zonder nummers levert niets op in plaats van het eerste het beste', () {
    expect(lib.remoteAlbumId(Album('Leeg', 'Niemand', const [])), isNull);
  });

  test('de wire-vorm draagt wat deze toets veronderstelt', () {
    // Als AlbumDto ooit anders gaat heten of vullen, moet deze toets meeveranderen en niet stil
    // groen blijven op een catalogus die nergens meer op lijkt.
    final dto = AlbumDto.fromJson(
        (catalogusJson(albumId: 'x', titel: 'T')['albums'] as List).first as Map<String, dynamic>);
    expect(dto.id, 'x');
    expect(dto.title, 'T');
  });
}
