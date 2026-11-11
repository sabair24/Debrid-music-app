// De telling per nummer op een albumpagina is het laagste werk van de app.
//
// Gemeten op 11-11-2026 (soulseek_login.log): sinds 3.9.722 zoekt een albumpagina per nummer, twee zoekopdrachten per nummer.
// Vanaf de gsm kwamen die als jouw eigen vragen op de pc aan. Om 20:52 wachtte "Milow You Don't Know" — de albumvraag van de
// single die Saber net opende — 78 s in de zoekrem, achter "*ilow North and South", "milow stephanie" en de rest van de plaat
// ervoor; de achtergrond wachtte tot 449 s. Om 21:16 wachtte ⬇ "Scared of Yourself" van Zornik 20 s. Saber: "alles gaat
// enorm traag via gsm en andere platforms".
import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/remote_services.dart' show zoekvraagVoorPc;
import 'package:debridmusic/per_nummer_zoeker.dart';
import 'package:debridmusic/soulseek.dart'
    show
        Zoekrem,
        kZoekPerMinuut,
        kZoekPerVijfMinuten,
        kZoekTellingMarge,
        kZoekTellingMargeVijf,
        kZoekVoorJou,
        kZoekVoorJouVijf,
        kZoekVoorJouVijfRustig;

final _t0 = DateTime(2026, 11, 11, 20, 50);

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('de zoekrem: de telling zoekt alleen in wat over is', () {
    test('DE KERN: een plaat vol tellingen laat de radio en jouw eigen tik meteen door', () {
      fakeAsync((fa) {
        final rem = Zoekrem(klok: () => _t0.add(fa.elapsed));
        var telling = 0, radio = 0, jij = 0;
        for (var i = 0; i < 30; i++) {
          unawaited(rem.neem(telling: true).then((_) => telling++));
        }
        fa.flushMicrotasks();
        expect(telling, kZoekPerMinuut - kZoekVoorJou - kZoekTellingMarge, reason: 'tien per minuut, niet twintig');
        for (var i = 0; i < kZoekTellingMarge; i++) {
          unawaited(rem.neem(achtergrond: true).then((_) => radio++));
        }
        fa.flushMicrotasks();
        expect(radio, kZoekTellingMarge, reason: 'de radio wacht niet achter de tellingen');
        for (var i = 0; i < kZoekVoorJou; i++) {
          unawaited(rem.neem().then((_) => jij++));
        }
        fa.flushMicrotasks();
        expect(jij, kZoekVoorJou, reason: 'jouw eigen tik wacht niet achter de tellingen');
      });
    });

    test('ook in vijf minuten blijft er plaats over voor de achtergrond', () {
      fakeAsync((fa) {
        final rem = Zoekrem(klok: () => _t0.add(fa.elapsed));
        var telling = 0, radio = 0;
        for (var i = 0; i < 60; i++) {
          unawaited(rem.neem(telling: true).then((_) => telling++));
        }
        fa.elapse(const Duration(minutes: 4));
        expect(telling, kZoekPerVijfMinuten - kZoekVoorJouVijf - kZoekTellingMargeVijf);
        for (var i = 0; i < kZoekTellingMargeVijf; i++) {
          unawaited(rem.neem(achtergrond: true).then((_) => radio++));
        }
        fa.flushMicrotasks();
        expect(radio, kZoekTellingMargeVijf, reason: 'de cd-jacht en een betere kopie gaan voor');
      });
    });

    test('een telling telt niet als iets wat jij zocht', () {
      fakeAsync((fa) {
        final rem = Zoekrem(klok: () => _t0.add(fa.elapsed), voorJouVijfRustig: kZoekVoorJouVijfRustig);
        var telling = 0;
        for (var i = 0; i < 60; i++) {
          unawaited(rem.neem(telling: true).then((_) => telling++));
        }
        fa.elapse(const Duration(minutes: 4, seconds: 30));
        expect(telling, kZoekPerVijfMinuten - kZoekVoorJouVijfRustig - kZoekTellingMargeVijf,
            reason: 'anders hield de achtergrond er twintig voor jou vrij, voor zoeken dat niet kwam');
      });
    });

    test('een lage grens laat de telling niet vastlopen', () {
      fakeAsync((fa) {
        final rem = Zoekrem(klok: () => _t0.add(fa.elapsed), maxVijf: 25);
        Duration? gewacht;
        unawaited(rem.neem(telling: true).then((d) => gewacht = d));
        fa.flushMicrotasks();
        expect(gewacht, Duration.zero, reason: '25 - 20 - 6 is min één: er blijft er altijd één');
      });
    });

    test('de marges laten de telling nog iets over', () {
      expect(kZoekPerMinuut - kZoekVoorJou - kZoekTellingMarge, greaterThan(0));
      expect(30 - kZoekVoorJouVijf - kZoekTellingMargeVijf, greaterThan(0), reason: 'ook op de bodem van de zoekgrens (30)');
    });
  });

  group('van een toestel naar de pc', () {
    test('wat de pc al als standaard neemt, gaat niet mee', () {
      expect(zoekvraagVoorPc('milow you don\'t know'), {'q': 'milow you don\'t know'});
      expect(zoekvraagVoorPc('x', extra: const ['24bit']), {'q': 'x', 'extra': '24bit'});
    });

    test('DE KERN: telling, achtergrond en geen terugval reizen mee', () {
      expect(zoekvraagVoorPc('zornik scared of yourself', telling: true, terugval: false),
          {'q': 'zornik scared of yourself', 'telling': '1', 'terugval': '0'});
      expect(zoekvraagVoorPc('x', achtergrond: true), {'q': 'x', 'achtergrond': '1'});
    });

    test('de pc leest ze, en zoekt niet meer voor een toestel dat al opgaf', () {
      final s = _bron('lib/lan/server.dart');
      expect(s, contains("achtergrond: vp['achtergrond'] == '1',"));
      expect(s, contains("telling: vp['telling'] == '1',"));
      expect(s, contains("terugval: vp['terugval'] != '0',"));
      expect(s, contains('nogNodig: () => geduld.elapsed < kToestelZoekGeduld)'));
      final r = _bron('lib/lan/remote_services.dart');
      expect(r, contains('{Map<String, String>? query, Duration timeout = const Duration(seconds: 90)}'),
          reason: 'zo lang wacht het toestel; de pc geeft het eerder op');
      expect(s, contains('static const kToestelZoekGeduld = Duration(seconds: 80);'));
    });
  });

  group('⬇ meteen met een verse telling', () {
    final nu = DateTime(2026, 11, 11, 21, 16);

    test('DE KERN: vers en genoeg: meteen, zonder nieuwe zoekopdracht', () {
      expect(meteenMetTelling(gevondenOp: nu.subtract(const Duration(minutes: 1)), nu: nu, genoeg: true), isTrue);
    });

    test('te oud, te weinig of nooit gezocht: zoals vroeger', () {
      expect(meteenMetTelling(gevondenOp: nu.subtract(kTellingVers + const Duration(seconds: 1)), nu: nu, genoeg: true),
          isFalse);
      expect(meteenMetTelling(gevondenOp: nu.subtract(const Duration(minutes: 1)), nu: nu, genoeg: false), isFalse);
      expect(meteenMetTelling(gevondenOp: null, nu: nu, genoeg: true), isFalse);
      expect(meteenMetTelling(gevondenOp: nu.add(const Duration(minutes: 1)), nu: nu, genoeg: true), isFalse,
          reason: 'een klok die versprong');
    });

    test('op de albumpagina: vóór de nieuwe zoekopdracht, met de tijd van de telling of anders die van de albumvraag', () {
      final bron = _bron('lib/main.dart');
      final begin = bron.indexOf('Future<List<SoulseekFile>> _slskCandidatesForTrack(');
      final lijf = bron.substring(begin, bron.indexOf('Future<void> _downloadTrack(', begin));
      expect(lijf.indexOf('if (meteenMetTelling('), greaterThan(0));
      expect(lijf.indexOf('if (meteenMetTelling('), lessThan(lijf.indexOf('await soulseek.zoekVroeg(')));
      expect(lijf, contains("gevondenOp: _perNummerOp['\${t.title}|\${t.durationSec}'] ?? _albumSlskOp,"));
      expect(lijf, contains('genoeg: vroegGenoeg(eerder, t.durationSec))) {'));
      expect(bron, contains('          _albumSlskOp = DateTime.now();'));
      expect(bron, contains("          _perNummerOp['\${t.title}|\${t.durationSec}'] = DateTime.now();"));
    });
  });

  group('de telling zelf', () {
    test('één ronde en geen jokervariant: één zoekopdracht per nummer', () {
      final o = _bron('lib/online.dart');
      expect(o, contains('    final rondes = terugval && !telling && !stil ? alle : alle.take(1).toList();'));
      expect(o, contains("      if (!telling && variants.isEmpty && jokerHelpt(q)) variants.add('*\${q.substring(1)}');"));
      expect(o, contains('        if (i == 0 && !stil && !telling) {'), reason: 'geen extra woorden');
      final s = _bron('lib/soulseek.dart');
      expect(s, contains('await zoekrem.neem(achtergrond: achtergrond, telling: telling, nogNodig: nogNodig);'));
    });
  });
}
