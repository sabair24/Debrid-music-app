/// Wat een rondgang over de Shield op 11-09-2026 liet zien, en dat het niet terugkomt.
///
/// Bekeken met schermafdrukken, op de tv zelf, met de afstandsbediening:
///
/// 1. De albumpagina viel uit elkaar zodra het wachtrijpaneel openstond: de titel letter voor
///    letter onder elkaar. De kop koos zijn vorm op de SCHERMbreedte, niet op de ruimte die hij kreeg.
/// 2. In Albums kwam omlaag vanuit het menu niet op de eerste plaat uit maar op "Wachtrij" in de
///    spelerbalk, en van onderen het menu in lichtte niets op: een sprong naar een scope gaf de focus
///    aan wat daar onthouden was, of aan de scope zelf -- ook als dat niet in beeld stond.
/// 3. In "Ook in" op de artiestpagina liepen de namen in elkaar en viel de focusrand scheef: een
///    tekstlink die bij focus uitvergroot, zoals een tegel dat hoort te doen.
/// 4. "1 albums", "1 nummers".
/// 5. Onder elk gefocust icoon op de tv stond een onderschrift zonder staart: "Wachtrij" werd
///    "Wachtrii". Het vak was 20 punten, de tekst op de Shield bijna 24 (hij staat daar op 1,35).
///
/// Bronbewakers, net als tv_bovenbalk_test.dart: een widgettest pumpt geen Shield en geen tweede
/// route, en zou precies de omstandigheid waarin dit misging nooit nabootsen.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late final String bron = File('lib/main.dart').readAsStringSync();

  String stuk(String begin, String eind) {
    final a = bron.indexOf(begin);
    expect(a, greaterThan(-1), reason: '"$begin" is hernoemd of verdwenen');
    final b = bron.indexOf(eind, a);
    expect(b, greaterThan(a), reason: '"$eind" staat niet meer na "$begin"');
    return bron.substring(a, b);
  }

  test('1. de albumkop kiest zijn vorm op de ruimte die hij krijgt', () {
    final kop = stuk('Widget _header(BuildContext context)', 'Widget _kop(BuildContext context');
    expect(kop, contains('LayoutBuilder'),
        reason: 'zonder LayoutBuilder weet de kop niet dat het wachtrijpaneel de helft inneemt');
    final lijf = stuk('Widget _kop(BuildContext context, double breedte)', 'return Padding(');
    expect(lijf, contains('final available = breedte - pad * 2;'));
    expect(lijf, isNot(contains('MediaQuery.sizeOf(context).width')),
        reason: 'de schermbreedte is precies wat hier fout ging');
    expect(lijf, contains('available < 200.0 * (1 + discTravelFactor(context))'),
        reason: 'gestapeld zodra hoes, cd en een leesbare titel niet naast elkaar passen');
  });

  test('2. een sprong landt op iets dat in beeld staat', () {
    final sprong = stuk('KeyEventResult _tvSprong', 'FocusNode? _landingsplek(');
    expect(sprong, contains('_landingsplek(scope, richting, vanwaar)?.requestFocus()'),
        reason: 'zonder landingsplek krijgt de scope zelf de focus, en die tekent geen rand');
    final landing = stuk('FocusNode? _landingsplek(', '\n  }\n');
    expect(landing, contains('scherm.overlaps(r)'),
        reason: 'wat onthouden was mag alleen winnen als het in beeld staat');
    expect(landing, contains('scope.focusedChild'),
        reason: 'terug naar waar je in een lange lijst was blijft het eerste antwoord');
    expect(landing, contains('vanwaar?.center.dx'),
        reason: 'uit het menu recht naar beneden, niet naar de eerste tegel van de rij');
  });

  test('3. tekstlinks vergroten niet uit bij focus', () {
    for (final anker in [
      'onPressed: onGroep == null ? null : () => onGroep!(g),',
      'onPressed: () => setState(() => _toonAlles = !_toonAlles),',
    ]) {
      final i = bron.indexOf(anker);
      expect(i, greaterThan(-1), reason: '"$anker" is verdwenen');
      expect(bron.substring(i, i + 700), contains('scaleOnFocus: false'),
          reason: 'uitvergroot duwt een tekstlink tegen zijn buurman en valt de rand scheef');
    }
  });

  test('4. één album, één nummer', () {
    expect(bron, isNot(contains("'\${mine.length} albums'")));
    expect(bron, contains("mine.length == 1 ? 'album' : 'albums'"));
    expect(bron, contains("_eigenNummers == 1 ? 'nummer' : 'nummers'"));
    expect(bron, contains("album.tracks.length == 1 ? 'nummer' : 'nummers'"));
  });

  test('5. het onderschrift op de tv krijgt een vak dat bij de geschaalde tekst past', () {
    final tv = File('lib/tv.dart').readAsStringSync();
    final a = tv.indexOf('class _TvLabelledState');
    expect(a, greaterThan(-1), reason: '_TvLabelledState is hernoemd of verdwenen');
    final b = tv.indexOf('\nclass ', a + 10);
    final staat = tv.substring(a, b < 0 ? tv.length : b);
    expect(staat, contains('MediaQuery.textScalerOf(context).scale(16)'),
        reason: 'een vaste hoogte houdt geen rekening met de tekstschaal van de tv, en dan knipt '
            'de ellipsis de staart van elke g, j, p en y eraf');
    expect(staat, isNot(contains('height: 20,')));
  });
}
