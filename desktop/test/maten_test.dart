/// Blijven de gedeelde widgets op de maten staan?
///
/// **Waarom deze toets bestaat.** Een telling over alle 101 bestanden gaf 15 verschillende
/// rondingen, 24 verschillende tekstgroottes en 29 verschillende witruimtewaarden. Dat is niet
/// ontstaan doordat iemand een verkeerde waarde koos, maar doordat er niets was om naar te wijzen:
/// elke nieuwe widget verzon zijn eigen maat, en niemand zag ze ooit naast elkaar.
///
/// **Streng afgebakend, en dat is met opzet.** Deze toets kijkt alleen naar de widgets uit `lib/ui/`
/// die in ronde 1 opnieuw gebouwd zijn. Over heel `main.dart` zou hij eeuwig rood staan — en dan is
/// hij binnen een week uitgezet, wat erger is dan geen toets.
library;

import 'package:debridmusic/ui/kop.dart';
import 'package:debridmusic/ui/leeg.dart';
import 'package:debridmusic/ui/maten.dart';
import 'package:debridmusic/ui/tegel.dart';
import 'package:debridmusic/ui/typografie.dart';
import 'package:debridmusic/ui/vlak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// `final` en niet `const`, en dat is geen slordigheid maar een regel van de taal: een `const`
// verzameling mag geen kommagetallen bevatten, want die hebben geen "primitieve gelijkheid" —
// `0.1 + 0.2 == 0.3` is onwaar, en dan is een verzameling niet meer op het moment van compileren
// vast te stellen. Alle maten hier zijn `double`.

/// De vijf hoeken, en niets anders.
final _hoeken = <double>{kHoek4, kHoek8, kHoek12, kHoek18, kHoekRond};

/// De acht stappen ruimte, plus nul.
final _ruimtes = <double>{
  0,
  kRuimte2,
  kRuimte4,
  kRuimte6,
  kRuimte8,
  kRuimte12,
  kRuimte16,
  kRuimte24,
  kRuimte32,
};

/// De zeven tekstrollen.
final _groottes = <double>{
  kKopGroot.fontSize!,
  kKop.fontSize!,
  kKopKlein.fontSize!,
  kTekstNormaal.fontSize!,
  kTekstBij.fontSize!,
  kTekstKlein.fontSize!,
  kLabel.fontSize!,
};

Widget _hoes(double maat) => Container(width: maat, height: maat, color: const Color(0xFF334455));

/// De gedeelde widgets, zonder een knop van Material erin.
///
/// De knop staat er los onder: `FilledButton` brengt zijn eigen vulling en zijn eigen vorm mee, en
/// die zijn van Material en niet van deze app. Meetellen zou de toets laten zakken op iets wat
/// niemand hier kan veranderen.
Widget _boom() => Column(
      children: [
        const SectieKop('Recent toegevoegd', bij: '15'),
        SizedBox(
          height: 260,
          child: Align(
            alignment: Alignment.topLeft,
            child: AlbumTegel(
              hoes: _hoes,
              breedte: kTegelHoes,
              titel: 'Racine Carrée',
              ondertitel: 'Stromae',
              onTap: () {},
            ),
          ),
        ),
        const Vlak(child: Text('een paneel', style: kTekstKlein)),
        const Expanded(
          child: LeegVlak(
            teken: Icons.library_music_rounded,
            kop: 'Nog geen muziek hier',
            uitleg: 'Zodra je pc gescand heeft, staan je platen hier.',
          ),
        ),
      ],
    );

/// Alleen wat ONDER onze eigen widgets hangt.
///
/// Zonder deze afbakening telt de toets ook de vulling en de vormen mee die Material zelf in een
/// `Scaffold` of een knop stopt. Dat zijn maten van het raamwerk, niet van deze app, en er zakken op
/// is een toets die niemand kan repareren en die dus uitgezet wordt.
Finder _binnenOns(Finder wat) => find.descendant(
      of: find.byWidgetPredicate((w) =>
          w is SectieKop || w is AlbumTegel || w is Vlak || w is LeegVlak),
      matching: wat,
      matchRoot: true,
    );

/// Staat deze marge op de ladder — eventueel met een haarlijn erbij?
///
/// **Waarom die haarlijn.** Een `Container` met een `decoration` die een rand draagt telt de
/// randdikte OP bij zijn eigen vulling: `EdgeInsets.all(12)` met een rand van één punt komt als 13
/// bij de `Padding` terecht. Dat is geen slordige maat maar precies de bedoelde 12 plus de rand die
/// `paneelDecoratie` eromheen zet, en het was de eerste vondst van deze toets.
///
/// Eén punt speling kost hier niets: van de acht stappen liggen er geen twee één punt uit elkaar
/// (2, 4, 6, 8, 12, 16, 24, 32), dus 13 kan alleen "12 met een rand" betekenen en nooit een tweede
/// maat die stilletjes naast een eerste is gaan staan.
bool _opDeLadder(double w) => _ruimtes.contains(w) || _ruimtes.contains(w - 1);

void main() {
  testWidgets('elke ronding komt uit de vijf', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: _boom())));

    final gevonden = <double>{};
    for (final element in _binnenOns(find.byType(DecoratedBox)).evaluate()) {
      final d = (element.widget as DecoratedBox).decoration;
      if (d is! BoxDecoration) continue;
      final r = d.borderRadius;
      if (r is! BorderRadius) continue;
      gevonden.addAll([r.topLeft.x, r.topRight.x, r.bottomLeft.x, r.bottomRight.x]);
    }
    for (final element in _binnenOns(find.byType(ClipRRect)).evaluate()) {
      final r = (element.widget as ClipRRect).borderRadius;
      if (r is! BorderRadius) continue;
      gevonden.addAll([r.topLeft.x, r.topRight.x, r.bottomLeft.x, r.bottomRight.x]);
    }

    expect(gevonden, isNotEmpty, reason: 'er is niets gemeten — dan zegt deze toets niets');
    for (final r in gevonden) {
      expect(_hoeken.contains(r) || r == 0, isTrue, reason: 'ronding $r staat niet in de vijf');
    }
  });

  testWidgets('elke marge komt uit de acht', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: _boom())));

    final gevonden = <double, String>{};
    for (final element in _binnenOns(find.byType(Padding)).evaluate()) {
      final p = (element.widget as Padding).padding;
      if (p is! EdgeInsets) continue;
      for (final w in [p.left, p.top, p.right, p.bottom]) {
        gevonden.putIfAbsent(w, () => element.debugGetCreatorChain(6));
      }
    }

    expect(gevonden, isNotEmpty);
    for (final MapEntry(key: w, value: waar) in gevonden.entries) {
      expect(_opDeLadder(w), isTrue, reason: 'marge $w staat niet in de acht — bij $waar');
    }
  });

  testWidgets('elke tekstgrootte komt uit de zeven rollen', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: _boom())));

    final gevonden = <double>{};
    for (final element in _binnenOns(find.byType(Text)).evaluate()) {
      final maat = (element.widget as Text).style?.fontSize;
      if (maat != null) gevonden.add(maat);
    }

    expect(gevonden, isNotEmpty);
    for (final maat in gevonden) {
      expect(_groottes.contains(maat), isTrue,
          reason: 'tekstgrootte $maat is geen rol uit ui/typografie.dart');
    }
  });

  test('een binnenhoek loopt concentrisch met zijn buitenhoek', () {
    // De enige regel in `ui/maten.dart` die na te meten is: een hoes van 12 in een kaart van 12 met
    // 8 vulling hoort binnen 4 te krijgen, niet ook 12.
    expect(binnenHoek(kHoek12, kRuimte8), kHoek4);
    expect(binnenHoek(kHoek18, kRuimte4), 14);
    // En nooit een scherpe hoek, hoe dik de vulling ook is.
    expect(binnenHoek(kHoek8, kRuimte32), kHoek4);
  });

  test('de duren staan vast', () {
    // 170 is het gebaar dat op het toestel goedgekeurd is. Het staat hier zodat "even wat sneller"
    // een gezakte toets is en geen stille verschuiving.
    expect(kGebaar.inMilliseconds, 170);
    expect(kSnel < kGebaar, isTrue);
    expect(kGebaar < kOvergang, isTrue);
    expect(kOvergang < kWas, isTrue);
  });
}
