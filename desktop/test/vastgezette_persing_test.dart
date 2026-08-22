/// Een vastgezette persing is een opdracht, en mag geen eeuwige lus worden.
///
/// **Wat hier misging.** De oplosser vroeg Discogs alleen als MusicBrainz niets wist
/// (`if (out.isEmpty)`). Kende MusicBrainz de plaat wél, dan werd een door de gebruiker vastgezette
/// Discogs-persing dus nooit opgehaald, en bleef `discogsRelease` leeg.
///
/// En juist daar kijkt [needsResolve] naar. `known.discogsRelease != pinned` was daardoor **altijd**
/// waar, dus:
///
///   * de albumpagina loste bij elk bezoek de hele keten opnieuw op,
///   * de achtergrondwarmer zette dat album in **elke** ronde op zijn lijst,
///   * en schreef er telkens de door de app zélf gekozen MusicBrainz-persing overheen.
///
/// Dat is letterlijk "ik duid iets aan en het komt terug" — en het kostte permanent verzoeken op een
/// budget dat op kan.
///
/// De oplosser honoreert de pin nu; lukt dat niet, dan stempelt hij `failedMs` en geldt de rem van
/// een dag die dit bestand verder ook aanhoudt. Deze toets bewaakt die rem, want zonder rem is de
/// lus gewoon terug.
library;

import 'package:debridmusic/album_facts.dart';
import 'package:debridmusic/editions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hash = 'abc';
  final nu = DateTime.now().millisecondsSinceEpoch;

  AlbumFacts feiten({int? release, String? mbid, int? failedMs}) => AlbumFacts(
        uid: 'u',
        trackSetHash: hash,
        updatedMs: nu,
        source: 'MusicBrainz',
        mbid: mbid,
        discogsRelease: release,
        tracklist: const [ChoiceTrack('1', 'Een nummer', 200)],
        failedMs: failedMs,
      );

  bool moetOpnieuw(AlbumFacts f, {int? pinned, String? pinnedMbid, int? opMoment}) => needsResolve(
        f,
        trackSetHash: hash,
        nowMs: opMoment ?? nu,
        pinned: pinned,
        pinnedMbid: pinnedMbid,
      );

  group('een pin die nog niet gehaald is', () {
    test('krijgt een eerste poging', () {
      expect(moetOpnieuw(feiten(), pinned: 12345), isTrue);
    });

    test('maar niet meteen een tweede — anders is de lus terug', () {
      // De oplosser stempelde `failedMs` omdat de pin niet gehaald werd. Zonder deze rem kwam dit
      // album in élke sweep terug.
      expect(moetOpnieuw(feiten(failedMs: nu), pinned: 12345), isFalse,
          reason: 'een onhaalbare pin mag niet elke ronde opnieuw geprobeerd worden');
    });

    test('en na een dag wel weer', () {
      final morgen = nu + const Duration(hours: 25).inMilliseconds;
      expect(moetOpnieuw(feiten(failedMs: nu), pinned: 12345, opMoment: morgen), isTrue,
          reason: 'een release die terugkomt, of een token dat weer ingevuld is, moet een kans krijgen');
    });
  });

  group('een pin die gehaald is', () {
    test('vraagt niets meer', () {
      expect(moetOpnieuw(feiten(release: 12345), pinned: 12345), isFalse);
    });

    test('ook niet met een oud stempel eraan', () {
      expect(moetOpnieuw(feiten(release: 12345, failedMs: nu), pinned: 12345), isFalse);
    });

    test('maar een ANDERE pin wel', () {
      expect(moetOpnieuw(feiten(release: 12345), pinned: 999), isTrue);
    });
  });

  group('een vastgezette MusicBrainz-persing gaat voor', () {
    test('een mbid die niet klopt vraagt om opnieuw oplossen', () {
      expect(moetOpnieuw(feiten(mbid: 'oud'), pinnedMbid: 'nieuw'), isTrue);
    });

    test('en een kloppende mbid legt het stil, ook zonder Discogs-nummer', () {
      // Precies de situatie waarin de oplosser Discogs met opzet NIET vraagt: de gebruiker wees
      // MusicBrainz aan, dus een oud Discogs-nummer heeft niets te zeggen.
      expect(moetOpnieuw(feiten(mbid: 'goed'), pinnedMbid: 'goed'), isFalse);
    });
  });

  test('zonder pin verandert er niets aan het oude gedrag', () {
    expect(moetOpnieuw(feiten()), isFalse);
    expect(moetOpnieuw(feiten(release: 42)), isFalse);
  });
}
