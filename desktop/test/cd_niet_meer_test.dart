// Een cd-versie die je verwijdert, komt niet terug (Saber, 12-11-2026, Rachid Taha "Diwân (cd)": "deze heb ik verwijderd
// nu al 2 maal, maar blijft terug komen ?? ik wil die niet meer"). De cd-jacht had bij zijn studio-kopie van "Ya Rayah"
// een cd gezocht en als versie bewaard; na het verwijderen had het nummer weer geen cd, en haalde de jacht hem opnieuw.
import 'dart:io';

import 'package:debridmusic/cd_niet_meer.dart';
import 'package:debridmusic/kopiesoort.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart' show setAppDirForTest;
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soortjacht.dart';
import 'package:debridmusic/twijfel.dart';
import 'package:debridmusic/versies.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  late Directory wortel;
  final sep = Platform.pathSeparator;
  String pad(String map, String naam) => '${wortel.path}${sep}Albums${sep}Rachid Taha$sep$map$sep$naam';
  File schrijf(String p) => File(p)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('flac');

  setUp(() {
    wortel = Directory.systemTemp.createTempSync('dm_cd_niet_meer_');
    setAppDirForTest(wortel.path);
    versies.wis();
  });
  tearDown(() async {
    versies.wis();
    await cdNietMeer.haalWeg(cdNietMeer.alle.toList());
    try {
      wortel.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('de lijst: hoofdletters en schuine strepen tellen niet, bewaren en inlezen', () async {
    final f = File('${wortel.path}${sep}cd_niet_meer.json');
    final l = CdNietMeer(bestand: f);
    await l.zet([r'D:\Muziek\Rachid Taha\Diwân\01 - Ya Rayah.flac']);
    expect(l.bevat('d:/muziek/rachid taha/diwân/01 - ya rayah.flac'), isTrue);
    final terug = CdNietMeer(bestand: f);
    await terug.laad();
    expect(terug.bevat(r'D:\Muziek\Rachid Taha\Diwân\01 - Ya Rayah.flac'), isTrue);
    await terug.haalWeg([r'd:\muziek\rachid taha\diwân\01 - ya rayah.flac']);
    expect(terug.bevat(r'D:\Muziek\Rachid Taha\Diwân\01 - Ya Rayah.flac'), isFalse);
  });

  test('DE KERN: je verwijdert "Diwân (cd)" — het nummer krijgt geen cd meer, de cd-jacht slaat het over', () async {
    final studio = schrijf(pad('Diwân', '01 - Ya Rayah.flac')).path;
    final cd = schrijf(pad('Diwân (cd)', '01 - Ya Rayah.flac')).path;
    versies.voegToe(studio, Versie(pad: cd, soort: Kopiesoort.cd), ankerSoort: Kopiesoort.studio);
    final ander = schrijf(pad('Ole Ole', '01 - Ya Rayah (live).flac')).path;

    final lib = LibraryStore()
      ..configDirOverride = wortel.path
      ..tracks.addAll([Track(path: cd, title: 'Ya Rayah', artist: 'Rachid Taha', album: 'Diwân (cd)')]);
    expect(await lib.removeTracks([cd], fromDisk: true), 1);
    expect(cdNietMeer.bevat(studio), isTrue, reason: 'het nummer waar de cd bij hoorde');
    expect(cdNietMeer.bevat(cd), isFalse);

    final d = DownloadManager(OnlineService(AppSettings()), SoulseekService(AppSettings()), wortel.path, () async {})
      ..twijfel = Twijfellijst('${wortel.path}${sep}twijfel.json')
      ..soortvragen = Soortvragen('${wortel.path}${sep}soortvragen.json')
      ..cdjacht = Soortvragen('${wortel.path}${sep}cdjacht.json', toon: false)
      ..cdjachtNummers = (() => [
            Track(path: studio, title: 'Ya Rayah', artist: 'Rachid Taha', album: 'Diwân'),
            Track(path: ander, title: 'Ya Rayah (live)', artist: 'Rachid Taha', album: 'Ole Ole'),
          ])
      ..cdjachtVanaf = DateTime(2000);
    await d.cdjachtVegen();
    expect(d.cdjacht!.van(studio), isNull, reason: 'je gooide zijn cd weg: niet opnieuw zoeken');
    expect(d.cdjacht!.van(ander), isNotNull, reason: 'een ander nummer zonder cd zoekt hij gewoon');
  });

  test('een studio- of vinylversie weggooien, of een gewoon nummer: geen invloed op de cd-jacht', () async {
    final studio = schrijf(pad('Diwân', '02 - Ida.flac')).path;
    final vinyl = schrijf(pad('Diwân (vinyl)', '02 - Ida.flac')).path;
    versies.voegToe(studio, Versie(pad: vinyl, soort: Kopiesoort.vinyl), ankerSoort: Kopiesoort.studio);
    final los = schrijf(pad('Made in Medina', '01 - Barra Barra.flac')).path;
    final lib = LibraryStore()..configDirOverride = wortel.path;
    await lib.removeTracks([vinyl, los], fromDisk: true);
    expect(cdNietMeer.alle, isEmpty);
  });

  test('aangesloten: zelf om cd vragen heft het op, de jacht en de terugzetter kijken ernaar', () {
    final o = _bron('lib/online.dart');
    expect(o, contains('    if (soort == Kopiesoort.cd) await cdNietMeer.haalWeg([for (final t in te) t.path]);'));
    expect(o, contains('      if (cdNietMeer.bevat(t.path)) {\n        if (v != null) c.verwijder(t.path);\n        continue;\n      }'));
    expect(o, contains('    for (final v in [for (final v in open) if (v.vanzelf && cdNietMeer.bevat(v.pad)) v]) {'));
    final m = _bron('lib/main.dart');
    expect(m, contains('          cdNodig: (anker) => !heeftSchoneCd(anker) && !cdNietMeer.bevat(anker),'));
    expect(m, contains('  if (mode.owner) await cdNietMeer.laad();'));
  });
}
