// Op de Shield (Saber, 25-10-2026): "kunnen we op shield ook voor zorgen als ik 2 maal op ok knop druk op de
// afstandsbediening dat ik van gelijk waar, direct naar de now playing venster spring. en als de app koud start, of na
// een update dat de selectie in de menu bar op start begint."
import 'dart:io';

import 'package:debridmusic/tv.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

Duration _ms(int n) => Duration(milliseconds: n);

void main() {
  group('twee keer OK herkennen', () {
    test('DE KERN: twee keer binnen 400 ms is een dubbele druk', () {
      final d = DubbelOk();
      expect(d.neer(_ms(1000)), isFalse, reason: 'de eerste doet gewoon wat hij doet');
      expect(d.neer(_ms(1250)), isTrue);
    });

    test('DE GRENS: precies 400 ms telt nog, 401 niet', () {
      final d = DubbelOk();
      d.neer(_ms(0));
      expect(d.neer(_ms(400)), isTrue);
      final e = DubbelOk();
      e.neer(_ms(0));
      expect(e.neer(_ms(401)), isFalse);
    });

    test('na een dubbele druk begint het opnieuw: drie keer snel is één sprong, niet twee', () {
      final d = DubbelOk();
      d.neer(_ms(0));
      expect(d.neer(_ms(200)), isTrue);
      expect(d.neer(_ms(350)), isFalse);
      expect(d.neer(_ms(500)), isTrue, reason: 'de vierde hoort bij de derde');
    });

    test('een andere toets ertussen (een pijl) maakt er twee losse OK\'s van', () {
      final d = DubbelOk();
      d.neer(_ms(0));
      d.anders();
      expect(d.neer(_ms(150)), isFalse);
    });

    test('rustig na elkaar drukken (een plaat openen, dan een nummer spelen) is geen dubbele druk', () {
      final d = DubbelOk();
      expect(d.neer(_ms(0)), isFalse);
      expect(d.neer(_ms(900)), isFalse);
      expect(d.neer(_ms(1800)), isFalse);
    });

    test('de OK van de afstandsbediening, een spelcomputer en een toetsenbord', () {
      expect(kOkToetsen,
          containsAll([LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.gameButtonA]));
      expect(kOkToetsen, isNot(contains(LogicalKeyboardKey.arrowDown)));
    });
  });

  group('aangesloten (gelezen uit lib/main.dart)', () {
    final main = _bron('lib/main.dart');

    test('op de tv gaat elke toets langs de dubbele OK, na de schermbeveiliging en vóór het vangnet', () {
      final v = main.substring(main.indexOf('  bool _tvVangnet(KeyEvent e) {'));
      expect(v.substring(0, 400), contains('    if (isTv && mounted && _tvStilWekker(e)) return true;\n'
          '    if (isTv && e is KeyDownEvent) _tvAlBediend = true;\n'
          '    if (isTv && mounted && _tvDubbelOk(e)) return true;\n'));
    });

    test('de tweede OK springt, en zijn loslaten wordt opgeslokt', () {
      // Een echte klok, niet de tijd van de toets: op Android is dat de tijd van het laatst getekende beeld, en bij een
      // stilstaand menu werden twee OK's seconden uit elkaar een "dubbele" (Shield, 25-10-2026).
      expect(main, contains('  static final Stopwatch _okKlok = Stopwatch()..start();'));
      expect(main.contains('_dubbelOk.neer(e.timeStamp)'), isFalse, reason: 'e.timeStamp staat stil zolang er niets tekent');
      expect(main, contains('    if (e is! KeyDownEvent || !_dubbelOk.neer(_okKlok.elapsed) || !_magNaarNuSpeelt()) return false;\n'
          '    _okOpslokken = true;\n    _naarNuSpeeltVanOveral();\n    return true;'));
      expect(main, contains('    if (e is KeyUpEvent) {\n      if (!_okOpslokken) return false;\n'
          '      _okOpslokken = false;\n      return true;\n    }'));
      expect(main, contains('      if (e is KeyDownEvent) _dubbelOk.anders();'));
    });

    test('niet als er niets speelt, niet in Nu speelt zelf, en niet op vooruit en terug', () {
      final m = main.substring(main.indexOf('  bool _magNaarNuSpeelt() {'));
      final stuk = m.substring(0, 900);
      expect(stuk, contains('.current == null && !context.read<SpeakerTarget>().isCasting'));
      expect(stuk, contains('hier.findAncestorWidgetOfExactType<DuwKnop>() != null) return false;'));
      expect(stuk, contains('return boven?.settings.name != _nuSpeeltRoute;'));
    });

    test('van overal: een open menu of paneel eerst dicht, dan Nu speelt (of terug naar het Nu speelt dat er ligt)', () {
      expect(main, contains('    nav.popUntil((r) => r is! PopupRoute || r.settings.name == _nuSpeeltRoute);\n'
          '    naarNuSpeelt(context);'));
    });

    test('bij een koude start: de selectie op het tabblad van de pagina (Start), tot je zelf een toets drukt', () {
      expect(main, contains('    if (isTv) _tvBeginOpStart();'));
      final b = main.substring(main.indexOf('  void _tvBeginOpStart() {'));
      final stuk = b.substring(0, 700);
      expect(stuk, contains('      if (!mounted || _tvAlBediend) return;'));
      expect(stuk, contains('      final tab = _tvKnoppen.voor(_view);'));
      expect(stuk, contains('      _tvBalk.requestFocus();\n      tab.requestFocus();'));
      expect(stuk, contains('for (final na in kTvStartSelectieOpnieuw) {'));
      expect(main, contains('  int _view = 5; // 0 albums, 1 artists, 2 online, 3 ontdek, 4 tracks, 5 start (default)'),
          reason: 'een koude start begint op Start');
    });
  });
}
