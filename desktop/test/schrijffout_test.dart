/// "3 niet gelukt" — en verder niets.
///
/// **Wat hier misging.** `writeTagFields` ving elke fout op met `catch (_)` en gaf `false` terug. De
/// bellers telden dat op tot een aantal, en het scherm meldde hoeveel bestanden niet geschreven
/// waren. Het commentaar bij die melding beloofde met zoveel woorden dat je "weet waaróm het bestand
/// zelf niet mee is" — en precies dat stond er niet.
///
/// Dat verschil is niet academisch. Een bestand dat openstaat in een andere speler los je op door
/// dat programma dicht te doen; een volle schijf niet; een bestand dat verplaatst is al helemaal
/// niet. Alle drie gaven hetzelfde getal.
///
/// [schrijffoutUitleg] is de vertaling naar gewone taal. Pure rekenkunde, dus hier te toetsen zonder
/// een bestand aan te raken.
library;

import 'dart:io';

import 'package:debridmusic/organize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FileSystemException metCode(int code, [String bericht = 'kon niet schrijven']) =>
      FileSystemException(bericht, '/muziek/01.flac', OSError('iets van het systeem', code));

  test('een bestand dat een ander programma vasthoudt, op Windows', () {
    // ERROR_SHARING_VIOLATION. Verreweg de gewoonste, en de enige die de gebruiker zelf oplost.
    expect(schrijffoutUitleg(metCode(32)), contains('in gebruik door een ander programma'));
  });

  test('en dezelfde situatie op macOS en Linux', () {
    // EBUSY. Zonder deze regel kreeg een Mac de kale systeemtekst terwijl het om precies hetzelfde
    // gaat — en juist daar draait de app naast andere spelers.
    expect(schrijffoutUitleg(metCode(16)), contains('in gebruik door een ander programma'));
  });

  test('geen toestemming', () {
    expect(schrijffoutUitleg(metCode(13)), contains('toestemming'));
    expect(schrijffoutUitleg(metCode(5)), contains('toestemming'));
  });

  test('een volle schijf zegt dat het over ruimte gaat', () {
    // Dit is de reden waarom "in gebruik" als vaste aanname fout was: hier helpt niets dichtdoen.
    expect(schrijffoutUitleg(metCode(28)), contains('ruimte'));
  });

  test('een bestand dat er niet meer staat', () {
    expect(schrijffoutUitleg(metCode(2)), contains('staat er niet meer'));
  });

  test('een onbekende code valt terug op wat het systeem zei, en is nooit leeg', () {
    final tekst = schrijffoutUitleg(metCode(9999, 'iets onverwachts'));
    expect(tekst, contains('iets onverwachts'));
    expect(tekst, contains('iets van het systeem'));
  });

  test('een fout zonder systeemcode levert nog steeds een zin op', () {
    expect(schrijffoutUitleg(const FileSystemException('leeg pad')), isNotEmpty);
    expect(schrijffoutUitleg(StateError('iets heel anders')), contains('iets heel anders'));
  });

  test('nooit een lege uitleg, wat er ook binnenkomt', () {
    // De hele waarde van dit ding is dat er ALTIJD iets te lezen staat. Een lege melding is precies
    // de stand waar we vanaf wilden.
    for (final e in <Object>[
      metCode(0),
      const FileSystemException(''),
      'gewoon een tekst',
      42,
    ]) {
      expect(schrijffoutUitleg(e), isNotEmpty, reason: 'leeg voor $e');
    }
  });
}
