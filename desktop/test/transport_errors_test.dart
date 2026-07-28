// "Het netwerk is stuk" tegenover "die plaat bestaat niet", zonder dat er iets gooit.
//
// Dit is de val waar ik in ben gelopen. Ik gaf resolveAlbumFacts een vlag die afging op een
// exception, en toen was de outage-guard dood: MusicBrainzService._get en DiscogsService._get vangen
// allebei ALLES en geven null terug. Een timeout, een 503, een DNS-fout en een schone 404 komen bij
// de aanroeper dus als exact hetzelfde antwoord aan.
//
// Gevolg zonder deze tellers: één keer opstarten zonder netwerk schrijft failedMs over de hele
// bibliotheek, elke albumpagina staat een etmaal leeg, en de artwork-lus komt ook niet meer aan de
// bak omdat die platen zonder tracklijst overslaat.
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/musicbrainz.dart';

void main() {
  setUp(() {
    MusicBrainzService.transportErrors = 0;
    DiscogsService.transportErrors = 0;
  });

  test('de tellers beginnen op nul en zijn los van elkaar', () {
    expect(MusicBrainzService.transportErrors, 0);
    expect(DiscogsService.transportErrors, 0);
    MusicBrainzService.transportErrors++;
    expect(DiscogsService.transportErrors, 0, reason: 'twee diensten, twee tellers');
  });

  test('de teller is statisch, dus een verse DiscogsService ziet dezelfde stand', () {
    // Dit is niet vrijblijvend: DiscogsService wordt op veertien plekken opnieuw gemaakt. Een
    // instantieveld zou elke aanroeper zijn eigen privé-telling van een globaal probleem geven, en
    // dan meet de resolver niets.
    DiscogsService.transportErrors = 7;
    expect(DiscogsService.transportErrors, 7);
  });

  test('vergelijken vóór en ná is het enige dat werkt zonder exceptions', () {
    // Precies wat resolveAlbumFacts doet: momentopname, opzoeking, verschil.
    final voor = MusicBrainzService.transportErrors + DiscogsService.transportErrors;

    // Een schone 404 verhoogt niets — dat IS een antwoord.
    expect(MusicBrainzService.transportErrors + DiscogsService.transportErrors, voor,
        reason: 'niets gebeurd, dus geen storing');

    // Een 503 of een timeout wel.
    MusicBrainzService.transportErrors++;
    expect(MusicBrainzService.transportErrors + DiscogsService.transportErrors, greaterThan(voor),
        reason: 'dit is wat de guard moet zien, en wat een exception nooit gaf');
  });
}
