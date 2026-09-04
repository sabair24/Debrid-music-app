/// De speler moet horen dat een naam veranderd is — ook op een gekoppeld toestel.
///
/// **Wat er gemeld werd, op 04-09-2026.** Op de pc de metadata van een INXS-nummer rechtgezet. Op
/// de telefoon klopte de albumpagina meteen — en in de balk onderin bleef "A1.INXS" staan.
/// *"huh, het klopt nu ineens zonder update?? heb de metadata bewerkt, dus die loopt achter dan?"*
///
/// Ja, en het is geen cache. De wachtrij van de speler houdt de `Track`-waarden vast van toen hij
/// gebouwd werd; `Track` is onveranderlijk, dus een correctie maakt NIEUWE objecten en de speler
/// blijft naar de oude wijzen. `PlayerStore.refreshTracks` bestaat precies daarvoor, maar hij is
/// afgeschermd met een teller — anders zou hij bij elke melding de hele wachtrij aflopen, en dat
/// zijn er tijdens het opstarten honderden.
///
/// Die teller werd op zes plekken opgehoogd, en die zitten allemaal in de weg van een pc die zijn
/// eigen schijf leest. De weg van een TOESTEL dat de catalogus van de pc binnenkrijgt — waar élke
/// `Track` in één klap door een nieuwe wordt vervangen — was vergeten. Dus sloeg `refreshTracks`
/// zijn wandeling over en bleven de spelerbalk, het speelscherm en het vergrendelscherm de oude
/// naam tonen tot de app herstart werd.
///
/// Deze toets kijkt naar de teller en niet naar de speler, en dat is met opzet: de teller is de
/// afspraak tussen die twee. Zakt hij, dan staat er ergens een oude naam op het scherm.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';

Track _t(String path, String title, String artist, String album, {int no = 1}) => Track(
      path: path,
      title: title,
      artist: artist,
      album: album,
      trackNo: no,
      trackTotal: 2,
      duration: const Duration(seconds: 240),
      isFlac: true,
      sizeBytes: 4096,
      sampleRate: 44100,
      bitsPerSample: 16,
      year: 1990,
    );

void main() {
  late Directory scratch;
  late LibraryStore pc;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_naamteller_');
    setAppDirForTest(scratch.path);
    pc = LibraryStore()
      ..rootPath = scratch.path
      ..configDirOverride = scratch.path;
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } on FileSystemException {/* een achtergebleven map is geen gezakte toets waard */}
  });

  /// Een telefoon: gekoppeld aan een pc, verder leeg.
  LibraryStore telefoon() => LibraryStore()
    ..remote = RemoteClient(
        RemoteEndpoint(baseUrl: Uri.parse('http://192.168.0.117:47820'), token: 't'));

  /// Wat de pc over de lijn stuurt, als kaart.
  Map<String, dynamic> vanDePc() =>
      jsonDecode(utf8.decode(LanCatalog(pc).snapshot().json)) as Map<String, dynamic>;

  /// De pc met deze nummers erop, klaar om te serveren.
  void pcHeeft(List<Track> ts) {
    pc.tracks
      ..clear()
      ..addAll(ts);
    pc.rebuildAlbums();
  }

  test('een catalogus binnenhalen hoogt de naamteller op', () {
    pcHeeft([_t('${scratch.path}/a1.flac', 'Suicide Blonde', 'A1.INXS', 'X')]);

    final gsm = telefoon();
    final voor = gsm.metaRev;
    expect(gsm.adoptMirror(vanDePc()), isTrue);
    expect(gsm.metaRev, greaterThan(voor),
        reason: 'anders slaat refreshTracks zijn wandeling over en blijft de oude naam staan');
  });

  test('een rechtgezette naam komt ook in de balk terecht', () {
    // Het gemelde geval, van begin tot eind: eerst de vervuilde naam, daarna dezelfde plaat met de
    // naam rechtgezet op de pc.
    pcHeeft([_t('${scratch.path}/a1.flac', 'Suicide Blonde', 'A1.INXS', 'X')]);
    final gsm = telefoon();
    expect(gsm.adoptMirror(vanDePc()), isTrue);
    expect(gsm.tracks.single.artist, 'A1.INXS');
    final naEerste = gsm.metaRev;

    // Op de pc rechtgezet, en de pc stuurt een verse catalogus.
    pcHeeft([_t('${scratch.path}/a1.flac', 'Suicide Blonde', 'INXS', 'X')]);
    // De eerste keer zette adoptMirror het toestel al in kopiestand, dus een tweede catalogus mag
    // eroverheen -- dat is precies wat er gebeurt als de pc iets aan zijn bibliotheek verandert.
    expect(gsm.adoptMirror(vanDePc()), isTrue);

    expect(gsm.tracks.single.artist, 'INXS');
    expect(gsm.metaRev, greaterThan(naEerste),
        reason: 'de speler moet horen dat deze naam veranderd is');
  });

  test('de teller loopt ook op als er nummers bij komen', () {
    pcHeeft([_t('${scratch.path}/a1.flac', 'Suicide Blonde', 'INXS', 'X')]);
    final gsm = telefoon();
    expect(gsm.adoptMirror(vanDePc()), isTrue);
    final naEerste = gsm.metaRev;

    pcHeeft([
      _t('${scratch.path}/a1.flac', 'Suicide Blonde', 'INXS', 'X'),
      _t('${scratch.path}/a2.flac', 'Disappear', 'INXS', 'X', no: 2),
    ]);
    expect(gsm.adoptMirror(vanDePc()), isTrue);

    expect(gsm.tracks.length, 2);
    expect(gsm.metaRev, greaterThan(naEerste));
  });
}
