import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/organize.dart';

/// Leftover folders after the app moves files around.
///
/// The user was deleting these by hand under their artist folder. Every move site now sweeps up
/// after itself; these tests pin the two rules that make that safe — stop at the root, and stop at
/// anything the user actually put there.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('prune_'));
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  Directory dir(String rel) =>
      Directory('${root.path}${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}')
        ..createSync(recursive: true);

  File file(String rel, [String body = 'x']) {
    final f = File('${root.path}${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(body);
    return f;
  }

  test('de map die leeg achterblijft gaat weg', () async {
    final album = dir('Albums/Beyoncé/BEYONCÉ [Platinum Edition]');
    await pruneVacated(album.path, root.path);
    expect(album.existsSync(), isFalse);
  });

  test('en de artiestenmap erboven ook, als die daardoor leeg is', () async {
    final album = dir('Albums/Beyoncé/BEYONCÉ [Platinum Edition]');
    await pruneVacated(album.path, root.path);
    expect(Directory('${root.path}${Platform.pathSeparator}Albums${Platform.pathSeparator}Beyoncé').existsSync(),
        isFalse);
  });

  test('maar niet de artiestenmap waar nog een plaat in staat', () async {
    final gone = dir('Albums/Backstreet Boys/Never Gone');
    file('Albums/Backstreet Boys/Millennium/01 - Larger Than Life.flac');
    await pruneVacated(gone.path, root.path);
    expect(gone.existsSync(), isFalse);
    expect(Directory('${root.path}${Platform.pathSeparator}Albums${Platform.pathSeparator}Backstreet Boys')
        .existsSync(),
        isTrue);
  });

  test('de wortel zelf blijft altijd staan', () async {
    await pruneVacated(root.path, root.path);
    expect(root.existsSync(), isTrue);
  });

  test('en een map buiten de wortel wordt niet aangeraakt', () async {
    final outside = Directory.systemTemp.createTempSync('buiten_');
    addTearDown(() {
      try {
        outside.deleteSync(recursive: true);
      } catch (_) {}
    });
    await pruneVacated(outside.path, root.path);
    expect(outside.existsSync(), isTrue);
  });

  test('een hoes die de gebruiker daar heeft gezet houdt de map overeind', () async {
    final album = dir('Albums/Justice/†');
    file('Albums/Justice/†/folder.jpg');
    await pruneVacated(album.path, root.path);
    expect(album.existsSync(), isTrue);
  });

  test('Thumbs.db houdt hem niet overeind — die heeft Windows zelf neergezet', () async {
    final album = dir('Albums/Daft Punk/Discovery');
    file('Albums/Daft Punk/Discovery/Thumbs.db');
    await pruneVacated(album.path, root.path);
    expect(album.existsSync(), isFalse);
  });

  test('een map met een submap blijft staan', () async {
    final album = dir('Albums/Justice/Cross');
    dir('Albums/Justice/Cross/_dubbel');
    file('Albums/Justice/Cross/_dubbel/01 - D.A.N.C.E..flac');
    await pruneVacated(album.path, root.path);
    expect(album.existsSync(), isTrue);
  });

  test('een lege wortel met een lege boom eronder: alles weg behalve de wortel', () async {
    dir('Albums/A/Een');
    dir('Albums/B/Twee');
    file('Albums/C/Drie/01 - Track.flac');
    await sweepEmptyFolders(root.path);
    expect(Directory('${root.path}${Platform.pathSeparator}Albums${Platform.pathSeparator}A').existsSync(),
        isFalse);
    expect(Directory('${root.path}${Platform.pathSeparator}Albums${Platform.pathSeparator}B').existsSync(),
        isFalse);
    expect(Directory('${root.path}${Platform.pathSeparator}Albums${Platform.pathSeparator}C').existsSync(),
        isTrue);
    expect(root.existsSync(), isTrue);
  });

  test('een lege wortelnaam doet niets — geen kale schijf opruimen', () async {
    await sweepEmptyFolders('');
    await pruneVacated(dir('Albums/X/Y').path, '');
    expect(Directory('${root.path}${Platform.pathSeparator}Albums${Platform.pathSeparator}X${Platform.pathSeparator}Y')
        .existsSync(),
        isTrue);
  });

  test('een map die al weg is laat de ouder toch opruimen', () async {
    final album = dir('Albums/Gone/Album');
    album.deleteSync();
    await pruneVacated(album.path, root.path);
    expect(Directory('${root.path}${Platform.pathSeparator}Albums${Platform.pathSeparator}Gone').existsSync(),
        isFalse);
  });
}
