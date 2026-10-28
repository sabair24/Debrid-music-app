/// De echte map voor wat je op een gsm of iPad bewaart (Saber, 28-10-2026): "ik moet ook direct naar de map
/// kunnen gaan" — Muziek/Debrid Music, "Zoals op de pc", en wat er al verborgen stond "Verhuizen naar de map".
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/dtos.dart';
import 'package:debridmusic/offline.dart';
import 'package:debridmusic/paths.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  late Directory app;
  late Directory openbaar;
  final sep = Platform.pathSeparator;

  setUp(() {
    app = Directory.systemTemp.createTempSync('dm_toestelapp_');
    openbaar = Directory.systemTemp.createTempSync('dm_toestelmuziek_');
    setAppDirForTest(app.path);
  });
  tearDown(() {
    for (final d in [app, openbaar]) {
      try {
        d.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows houdt soms nog even een greep vast.
      }
    }
  });

  OfflineStore metMap(Map<String, String> pcPaden, {List<String>? gescand}) => OfflineStore()
    ..openbareMap = (() => openbaar)
    ..pcPadVoor = ((p) => pcPaden[p])
    ..naWijziging = ((b) => gescand?.add(b));

  test('de plek in de map is die van de pc, met de eigen extensie, en nooit erbuiten', () {
    final o = metMap({
      'a': 'Britney Spears/Crazy (1999)/01 - Crazy.ape',
      'b': '../../Windows/kwaad.flac',
      'c': 'Artiest/Wat?: "raar" <ja>.flac',
    });
    expect(o.openbaarPad('a', 'flac'),
        '${openbaar.path}${sep}Britney Spears${sep}Crazy (1999)${sep}01 - Crazy.flac',
        reason: 'een omgezette APE wordt FLAC, op dezelfde plek');
    expect(o.openbaarPad('b', 'flac'), '${openbaar.path}${sep}Windows${sep}kwaad.flac', reason: 'nooit uit de map');
    expect(o.openbaarPad('c', 'flac'), '${openbaar.path}${sep}Artiest${sep}Wat__ _raar_ _ja_.flac',
        reason: 'tekens die de gedeelde opslag van Android weigert');
    expect(o.openbaarPad('onbekend', 'flac'), isNull, reason: 'zonder pad van de pc in de eigen map, zoals eerst');
    expect((OfflineStore()..pcPadVoor = ((_) => 'A/B.flac')).openbaarPad('x', 'flac'), isNull,
        reason: 'zonder openbare map (geen toestemming) ook');
  });

  test('ophalen: het hele bestand in de map, het halve nooit', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final inhoud = List<int>.generate(50000, (i) => i % 251);
    server.listen((req) async {
      req.response.headers.contentLength = inhoud.length;
      req.response.add(inhoud);
      await req.response.close();
    });
    final gescand = <String>[];
    final o = metMap({'nummer': 'Britney Spears/Crazy/01 - Crazy.flac'}, gescand: gescand);
    await o.load();
    final gelukt = await o.download(
        libraryPath: 'nummer',
        url: 'http://127.0.0.1:${server.port}/stream/x.flac',
        title: 'Crazy',
        artist: 'Britney Spears',
        album: 'Crazy');
    await server.close(force: true);
    expect(gelukt, isTrue);
    final verwacht = '${openbaar.path}${sep}Britney Spears${sep}Crazy${sep}01 - Crazy.flac';
    expect(o.localFor('nummer'), verwacht);
    expect(File(verwacht).lengthSync(), inhoud.length);
    expect(gescand, [verwacht], reason: 'Android moet het nieuwe bestand inlezen');
    final rest = openbaar.listSync(recursive: true).whereType<File>().map((f) => f.path).toList();
    expect(rest, [verwacht], reason: 'geen .part of stempel tussen je muziek');
  });

  test('verhuizen: wat verborgen stond gaat één keer naar de map, zonder opnieuw te downloaden', () async {
    final oud = File('${app.path}${sep}offline${sep}abc123.flac')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3, 4]);
    File('${app.path}${sep}offline.json').writeAsStringSync(jsonEncode([
      {'path': 'nummer', 'file': oud.path, 'bytes': 4, 'title': 'Rehab', 'artist': 'Amy Winehouse', 'album': 'Back to Black'},
      {'path': 'zonderpad', 'file': oud.path, 'bytes': 4, 'title': 'X', 'artist': 'Y', 'album': 'Z'},
    ]));
    final gescand = <String>[];
    final o = metMap({'nummer': 'Amy Winehouse/Back to Black/01 - Rehab.flac'}, gescand: gescand);
    await o.load();
    expect(await o.verhuisNaarOpenbaar(), 1);
    final nieuw = '${openbaar.path}${sep}Amy Winehouse${sep}Back to Black${sep}01 - Rehab.flac';
    expect(o.localFor('nummer'), nieuw);
    expect(File(nieuw).readAsBytesSync(), [1, 2, 3, 4]);
    expect(oud.existsSync(), isFalse);
    expect(gescand, [nieuw]);
    expect(await o.verhuisNaarOpenbaar(), 0, reason: 'een tweede keer is er niets meer te doen');
    // En de index op schijf weet het ook, na een herstart.
    final weer = metMap({});
    await weer.load();
    expect(weer.localFor('nummer'), nieuw);
  });

  test('weghalen: het bestand en de lege mappen weg, en zelf gewist in Bestanden = niet meer op dit toestel', () async {
    final bestand = File('${openbaar.path}${sep}Amy Winehouse${sep}Back to Black${sep}01 - Rehab.flac')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1]);
    final ander = File('${openbaar.path}${sep}Amy Winehouse${sep}Frank${sep}01 - Stronger.flac')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2]);
    File('${app.path}${sep}offline.json').writeAsStringSync(jsonEncode([
      {'path': 'rehab', 'file': bestand.path, 'bytes': 1, 'title': 'Rehab', 'artist': 'Amy Winehouse', 'album': 'Back to Black'},
      {'path': 'stronger', 'file': ander.path, 'bytes': 1, 'title': 'Stronger', 'artist': 'Amy Winehouse', 'album': 'Frank'},
    ]));
    final gescand = <String>[];
    final o = metMap({}, gescand: gescand);
    await o.load();
    await o.remove('rehab');
    expect(bestand.existsSync(), isFalse);
    expect(Directory('${openbaar.path}${sep}Amy Winehouse${sep}Back to Black').existsSync(), isFalse);
    expect(Directory('${openbaar.path}${sep}Amy Winehouse').existsSync(), isTrue, reason: 'Frank staat er nog');
    expect(gescand, [bestand.path]);
    // Zelf in Bestanden weggehaald: de app past zich aan en haalt het niet opnieuw op.
    ander.deleteSync();
    expect(o.localFor('stronger'), isNull);
    expect(o.has('stronger'), isFalse);
  });

  test('de pc geeft het pad mee in de catalogus', () {
    final d = TrackDto.fromJson({
      'id': 't1', 'albumId': 'a', 'artistId': 'r', 'title': 'Crazy', 'artistName': 'Britney Spears',
      'albumTitle': 'Crazy', 'streamPath': '/stream/t1.flac', 'ext': 'flac', 'rel': 'Britney Spears/Crazy/01 - Crazy.flac',
    });
    expect(d.rel, 'Britney Spears/Crazy/01 - Crazy.flac');
    expect(d.toJson()['rel'], 'Britney Spears/Crazy/01 - Crazy.flac');
    expect(TrackDto.fromJson({...d.toJson()}..remove('rel')).rel, isNull, reason: 'een oudere pc stuurt het niet');
    expect(_bron('lib/lan/catalog.dart'), contains('          rel: relPathOf(t.path, root),\n'));
    expect(_bron('lib/library.dart'), contains('    if (d.rel case final r?) _pcPaden[pad] = r;\n'));
  });

  test('aangesloten: de toestemming op Android, de map op de iPad, en de app kijkt opnieuw na terugkomst', () {
    final manifest = _bron('android/app/src/main/AndroidManifest.xml');
    expect(manifest, contains('<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>'));
    final kotlin = _bron('android/app/src/main/kotlin/com/debridmusic/app/MainActivity.kt');
    expect(kotlin, contains('"debridmusic/bestanden"'));
    expect(kotlin, contains('Environment.isExternalStorageManager()'));
    expect(kotlin, contains('Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION'));
    expect(kotlin, contains('MediaScannerConnection.scanFile'));
    final plist = _bron('ios/Runner/Info.plist');
    expect(plist, contains('<key>UIFileSharingEnabled</key>\n\t<true/>'));
    expect(plist, contains('<key>LSSupportsOpeningDocumentsInPlace</key>\n\t<true/>'));
    final main = _bron('lib/main.dart');
    expect(main, contains('  offline.openbareMap = () => openbareMapNu.value;\n'));
    expect(main, contains('  offline.pcPadVoor = library.pcPadVan;\n'));
    expect(main, contains('  toestelLeven = AppLifecycleListener(onResume: () => unawaited(kijkOpenbaar()));\n'));
    expect(main, contains('    final n = await offline.verhuisNaarOpenbaar();\n'));
    expect(main, contains('      const ToestelMapKaart(),\n'));
  });
}
