// Een tik op een nummer vraagt wat ermee moet als er al een wachtrij is, en een tik in de wachtrij springt
// zonder opnieuw te schudden (Saber, 21-10-2026: "als ik naar heel men bibliotheek aan het beluisteren ben en
// klik op een liedje is de hele wachtrij weg").
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart' show TikKeuze, tikKeuzeUit, tikVraagtIets;
import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/settings.dart';

Track t(String naam) => Track(
      path: 'D:\\m\\$naam.flac',
      title: naam,
      artist: 'A',
      album: 'Alb',
      trackNo: 1,
      duration: const Duration(seconds: 200),
      isFlac: true,
    );

Wachtrij rij(List<String> namen, int index) {
  final lijst = [for (final n in namen) t(n)];
  return (origineel: lijst, volgorde: List.of(lijst), index: index);
}

List<String> namen(List<Track> l) => [for (final x in l) x.title];

String _lees(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('verplaatsen in plaats van dubbel (Saber: "Verplaatsen")', () {
    test('wat al komt, verhuist naar hierna', () {
      final w = voegInWachtrijVerplaatsend(rij(['a', 'b', 'c', 'd'], 1), [t('d')], hierna: true);
      expect(namen(w.volgorde), ['a', 'b', 'd', 'c']);
      expect(w.index, 1);
      expect(namen(w.origineel), ['a', 'b', 'd', 'c']);
    });

    test('wat al klonk of nu speelt, blijft staan: dat is geschiedenis', () {
      final w = voegInWachtrijVerplaatsend(rij(['a', 'b', 'c'], 1), [t('a')], hierna: false);
      expect(namen(w.volgorde), ['a', 'b', 'c', 'a']);
      final nog = voegInWachtrijVerplaatsend(rij(['a', 'b', 'c'], 1), [t('b')], hierna: true);
      expect(namen(nog.volgorde), ['a', 'b', 'b', 'c'], reason: 'het spelende nummer nog eens, hierna');
    });

    test('achteraan verhuist ook', () {
      final w = voegInWachtrijVerplaatsend(rij(['a', 'b', 'c', 'd'], 0), [t('b')], hierna: false);
      expect(namen(w.volgorde), ['a', 'c', 'd', 'b']);
      expect(w.index, 0);
    });
  });

  group('wanneer het menu komt', () {
    test('alleen als er al een wachtrij is', () {
      expect(tikVraagtIets(speelt: false, radio: false, lengte: 0), isFalse);
      expect(tikVraagtIets(speelt: true, radio: false, lengte: 1), isFalse, reason: 'alleen het spelende nummer');
      expect(tikVraagtIets(speelt: true, radio: false, lengte: 12), isTrue);
      expect(tikVraagtIets(speelt: true, radio: true, lengte: 1), isTrue, reason: 'ook tijdens een radio');
    });

    test('de vaste keuze per toestel: standaard vragen, onbekend = vragen', () {
      expect(AppSettings().tikKeuze, 'vragen');
      expect(tikKeuzeUit('hierna'), TikKeuze.hierna);
      expect(tikKeuzeUit('iets'), TikKeuze.vragen);
    });
  });

  group('aangesloten', () {
    test('elke tik op een nummer in een lijst vraagt; Speel alles en Shuffle alles vervangen gewoon', () {
      final main = _lees('lib/main.dart');
      // Zolang je nummers kiest (Saber, 28-10-2026) kiest een tik; anders vraagt hij, zoals altijd.
      expect(main, contains(': speelGetikt(context, widget.queue, widget.index, cover: widget.albumCover),'),
          reason: 'een album');
      expect(main, contains('onTap: () => nummerKeuze.actief ? nummerKeuze.wissel(t) : speelGetikt(context, tracks, i),'), reason: 'de Tracks-lijst');
      expect(main, contains('onTap: () => speelGetikt(context, nummers, i),'), reason: 'een afspeellijst');
      expect(main, contains('onTap: () => speelGetikt(context, alles, plek),'), reason: 'de favorieten');
      expect(main, contains('speelLijst(context, tracks, schud: false,'), reason: 'Speel alles blijft vervangen');
      expect(main, contains('unawaited(schud ? speler.shuffleAll(nu) : speler.playQueue(nu, 0, cover: cover));'),
          reason: 'via speelLijst, dat de wachtrij vervangt (zonder pc met alleen wat hier staat)');
    });

    test('een tik in de wachtrij springt, zonder opnieuw te schudden', () {
      final main = _lees('lib/main.dart');
      expect(main, contains('onTap: () => p.springNaar(plek),'));
      expect(main, contains('p.springNaar(p.currentIndex + n),'));
      final speler = _lees('lib/player.dart');
      final s = speler.substring(speler.indexOf('  Future<void> springNaar(int plek) async {'));
      expect(s.substring(0, s.indexOf('\n  }\n')), isNot(contains('_rebuildOrder')));
      expect(speler, contains('await springNaar(_index + 1);'), reason: 'nu spelen, rest laten staan');
      expect(speler, contains('_pas(voegInWachtrijVerplaatsend(_nu, nieuw, hierna: hierna));'));
      expect(speler, contains('_voegInRadio(nieuw, hierna: hierna);'), reason: 'ook in een radio');
    });

    test('de instelling staat in Instellingen en wordt bewaard', () {
      expect(_lees('lib/main.dart'), contains('const TikKeuzeInstelling(),'));
      expect(_lees('lib/settings.dart'), contains("'tik_keuze': tikKeuze,"));
    });
  });
}
