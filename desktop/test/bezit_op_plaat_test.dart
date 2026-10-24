/// "Heb ik dit al?" op een albumpagina, als alleen de gast anders geschreven staat.
///
/// Saber, 24-10-2026, bij Céline Dion *D'eux*: "de app zeg dat ik de song nog niet heb, maar ik heb em wel nog, de app
/// moet beter worden in wat ik al heb en niet, ook verschillende versie's uit elkaar houden enzo". De pagina noemde
/// "J'irai où tu iras (with Jean-Jacques Goldman)", het bestand heet "J'irai où tu iras" — FLAC 24/44.1, 3:26.
library;

import 'dart:io';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String titel, int sec, {String artiest = 'Céline Dion'}) => Track(
    path: 'D:\\m\\$titel.flac', title: titel, artist: artiest, album: "D'eux", duration: Duration(seconds: sec));

void main() {
  const deux = [
    "Pour que tu m'aimes encore", 'Le Ballet', "J'irai où tu iras (with Jean-Jacques Goldman)", 'Vole',
  ];

  test('DE KERN: het duet op de plaat is het bestand zonder gast', () {
    final eigen = _t("J'irai où tu iras", 206);
    expect(eigenOpPlaat("J'irai où tu iras (with Jean-Jacques Goldman)", [eigen], albumTitels: deux, seconden: 207),
        same(eigen));
  });

  test('en omgekeerd: het bestand noemt de gast, de plaat niet', () {
    final eigen = _t('Lose Control (feat. Ciara & Fat Man Scoop)', 226, artiest: 'Missy Elliott');
    expect(eigenOpPlaat('Lose Control', [eigen], albumTitels: const ['Lose Control', 'Teary Eyed'], seconden: 227),
        same(eigen));
  });

  test('DE GRENS: staat dezelfde titel ook solo op de plaat (Adele), dan is de gast het verschil', () {
    final solo = _t('Easy On Me', 224, artiest: 'Adele');
    expect(
        eigenOpPlaat('Easy On Me (with Chris Stapleton)', [solo],
            albumTitels: const ['Easy On Me', 'My Little Love', 'Easy On Me (with Chris Stapleton)'], seconden: 225),
        isNull);
  });

  test('met beide in de bibliotheek: dezelfde vorm gaat voor', () {
    final solo = _t('Easy On Me', 224, artiest: 'Adele');
    final duet = _t('Easy On Me (feat. Chris Stapleton)', 225, artiest: 'Adele');
    expect(
        eigenOpPlaat('Easy On Me (with Chris Stapleton)', [solo, duet],
            albumTitels: const ['Easy On Me (with Chris Stapleton)'], seconden: 225),
        same(duet),
        reason: 'een single met alleen het duet: het duet, niet de solo');
  });

  test('DE VAL: een andere lengte is een andere versie — live of een edit zonder merk', () {
    final live = _t("J'irai où tu iras", 262);
    expect(eigenOpPlaat("J'irai où tu iras (with Jean-Jacques Goldman)", [live], albumTitels: deux, seconden: 207),
        isNull);
    expect(eigenOpPlaat("J'irai où tu iras (with Jean-Jacques Goldman)", [live], albumTitels: deux), same(live),
        reason: 'zonder officiële lengte beslist de titel');
  });

  test('de albumpagina vraagt het zo, op beide plekken', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(RegExp(r'ownedOpPlaat\(widget\.artistName, t\.title,').allMatches(main).length, 2);
    expect(main, isNot(contains('ownedTrack(widget.artistName, t.title)')));
  });
}
