/// "Uitgave kiezen…" staat in het menu van elk nummer en elke albumtegel, niet alleen op de
/// albumpagina.
///
/// **Waarom dit bestaat.** Saber op 06-10-2026, met een schermafdruk van het driepuntjesmenu op "Nu
/// speelt": *"vanuit de 3 dots menu wil ik de uitgave kunnen kiezen, nu moet ik eerst naar de album
/// gaan en dan daar uitgave kiezen. wil dit sneller kunnen doen. dus ook bij de andere menu
/// bottomsheets"*. Het menu had alleen "Juiste uitgave zoeken…", en dat verplaatst één NUMMER naar
/// een andere plaat — iets anders dan de persing van het hele album kiezen.
///
/// Brontekst, want `_nummerMenu` en `_albumMenu` zijn privé en hangen aan een handvol diensten.
/// Wat hier vastligt: de regel staat er, opent dezelfde galerij als de knop op de albumpagina, met
/// dezelfde voorwaarden — en de albumpagina eronder merkt een keuze die buiten haar om gemaakt is.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _bron() => File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');

/// Het lijf van een functie op het hoogste niveau, van zijn kop tot de volgende `\n}\n`.
String _lijf(String bron, String kop) {
  final begin = bron.indexOf(kop);
  expect(begin, isNonNegative, reason: '$kop niet gevonden');
  return bron.substring(begin, bron.indexOf('\n}\n', begin));
}

void main() {
  test('DE KERN: het menu van een nummer opent de galerij meteen', () {
    final menu = _lijf(_bron(), 'ItemMenu _nummerMenu(');
    final regel = menu.indexOf("'Uitgave kiezen…'");
    expect(regel, isNonNegative, reason: 'eerst naar het album en dan pas kiezen, dat was de klacht');
    expect(menu.substring(regel, regel + 160), contains('ReleaseGallery(album)'),
        reason: 'dezelfde galerij als de knop op de albumpagina, met hoes, achterkant en cd');
    // Vlak onder "Ga naar album", in hetzelfde blok: daar zoek je hem, en op een telefoon staat het
    // laatste blok onder de vouw.
    expect(regel, greaterThan(menu.indexOf("'Ga naar album'")));
    expect(regel, lessThan(menu.indexOf("'Ga naar artiest'")));
  });

  test('DE KERN: het menu van een albumtegel ook', () {
    final menu = _lijf(_bron(), 'ItemMenu _albumMenu(');
    final regel = menu.indexOf("'Uitgave kiezen…'");
    expect(regel, isNonNegative, reason: '"dus ook bij de andere menu bottomsheets"');
    expect(menu.substring(regel, regel + 160), contains('ReleaseGallery(a)'));
  });

  test('DE GRENS: dezelfde voorwaarden als op de albumpagina — geen single, geen tv', () {
    final bron = _bron();
    final nummer = _lijf(bron, 'ItemMenu _nummerMenu(');
    final album = _lijf(bron, 'ItemMenu _albumMenu(');
    expect(nummer, contains("if (album != null && !album.isSingle)\n          if (!isTv) MenuRegel(Icons.photo_library_outlined, 'Uitgave kiezen…',"),
        reason: 'een single heeft geen persing om uit te kiezen; de knop op de albumpagina ontbreekt daar ook');
    expect(album, contains("if (!a.isSingle)\n          if (!isTv) MenuRegel(Icons.photo_library_outlined, 'Uitgave kiezen…',"));
  });

  test('DE VAL: de albumpagina eronder ziet een persing die via het menu gekozen is', () {
    final bron = _bron();
    final begin = bron.indexOf('class _AlbumDetailPageState');
    final staat = bron.substring(begin, bron.indexOf('\n}\n', begin));
    final bouw = staat.substring(staat.indexOf('  Widget build(BuildContext context) {'));
    final kijk = bouw.indexOf('final vraag = _vraagMet(lib);');
    expect(kijk, isNonNegative,
        reason: 'zonder dit bleef de tracklijst die van de vorige persing; alleen de hoes werd nieuw');
    expect(bouw.substring(kijk, kijk + 400), contains('if (mounted) _loadOfficial();'));
    expect(bouw.substring(kijk, kijk + 400),
        contains('vraag != _officialFor && vraag != _herlaadVoor'),
        reason: 'één keer per nieuwe vraag, anders laadt elke herbouw opnieuw');
    expect(bouw.substring(0, kijk), isNot(contains('_officialVraag')),
        reason: '`context.read` in build gooit een fout in een debugbouw; vandaar _vraagMet(lib)');
  });
}
