/// Past het, op elke breedte en met de systeemletters van de gebruiker?
///
/// **Waarom deze toets bestaat.** Een liggende `ListView` geeft zijn kinderen een strákke hoogte en
/// knipt wat er niet in past — zonder een woord in de bouw. De hoogte van de rijen op Start stond
/// met de hand op 204 met een commentaar erbij dat het "maar net" genoeg was, en op de televisie op
/// 236 met dezelfde slag om de arm. Voeg iets aan de tegel toe, of zet de tekst 35% groter, en de
/// onderste regel is stil weg.
///
/// `uitgave_rij_test.dart` bestaat omdat precies dat soort fout vier keer op rij alleen door een
/// schermafbeelding gevonden werd. Dit is dezelfde toets, een laag dieper: niet "past deze rij" maar
/// "klopt de formule waarmee de hoogte berekend wordt".
///
/// **En daarom wordt de tegel LOS gemeten.** In een liggende lijst krijgt hij een strakke hoogte
/// opgelegd, dus daar is hij per definitie precies zo hoog als de rij — meten binnen de lijst zou
/// altijd slagen en niets bewijzen. Hier staat hij in een `Align`, die zijn kind zijn eigen maat
/// laat kiezen, en pas dan zegt het getal iets.
library;

import 'package:debridmusic/ui/kop.dart';
import 'package:debridmusic/ui/leeg.dart';
import 'package:debridmusic/ui/skelet.dart';
import 'package:debridmusic/ui/tegel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// De vier schermen die er zijn: een smalle telefoon, de Galaxy, een venster/iPad, en de Shield.
const _schermen = <(String, Size, double)>[
  ('smalle telefoon 360', Size(360, 780), 1.0),
  ('Galaxy 411', Size(411, 915), 1.0),
  ('venster 915', Size(915, 700), 1.0),
  ('Shield 960×540 op 1,35×', Size(960, 540), 1.35),
];

Widget _omhulsel(Widget kind, Size maat, double schaal) => MediaQuery(
      data: MediaQueryData(size: maat, textScaler: TextScaler.linear(schaal)),
      child: MaterialApp(home: Scaffold(body: kind)),
    );

Widget _hoes(double maat) => Container(width: maat, height: maat, color: const Color(0xFF334455));

AlbumTegel _proef() => AlbumTegel(
      hoes: _hoes,
      breedte: kTegelHoes,
      titel: 'You’re The First, The Last, My Everything',
      ondertitel: 'Barry White',
      onTap: () {},
    );

void main() {
  for (final (naam, maat, schaal) in _schermen) {
    testWidgets('de tegel past in de berekende rijhoogte — $naam', (t) async {
      await t.binding.setSurfaceSize(maat);
      addTearDown(() => t.binding.setSurfaceSize(null));

      late double rij;
      late double tegelFormule;
      await t.pumpWidget(_omhulsel(
        Builder(builder: (context) {
          rij = hoogteVanTegelrij(context);
          tegelFormule = hoogteVanTegel(context);
          // Align legt geen hoogte op, dus wat hier uitkomt is de maat die de tegel zélf kiest.
          return Align(alignment: Alignment.topLeft, child: _proef());
        }),
        maat,
        schaal,
      ));

      final echt = t.getSize(find.byType(AlbumTegel)).height;
      expect(echt, lessThanOrEqualTo(tegelFormule + 0.5),
          reason: 'de tegel is $echt hoog, de formule zegt $tegelFormule');
      expect(echt, lessThanOrEqualTo(rij),
          reason: 'de tegel is $echt hoog en de rij maar $rij — dat wordt afgeknipt');
      // De rij hoort ook echt ruimer te zijn dan de tegel: daar zit de groei bij aanwijzen in.
      expect(rij, greaterThan(echt));
      expect(t.takeException(), isNull);
    });

    testWidgets('kop en leeg vlak lopen niet over — $naam', (t) async {
      await t.binding.setSurfaceSize(maat);
      addTearDown(() => t.binding.setSurfaceSize(null));

      await t.pumpWidget(_omhulsel(
        Column(
          children: [
            const SectieKop('Nieuw van jouw artiesten', bij: '20'),
            Expanded(
              child: LeegVlak(
                teken: Icons.library_music_rounded,
                kop: 'Nog geen muziek hier',
                uitleg: 'Zodra je pc gescand heeft, staan je platen hier. '
                    'Of zoek er zelf een op.',
                knop: 'Online zoeken',
                opKnop: () {},
              ),
            ),
          ],
        ),
        maat,
        schaal,
      ));

      expect(t.takeException(), isNull);
    });

    testWidgets('de skeletten lopen niet over — $naam', (t) async {
      // Ze staan er juist om te VOORKOMEN dat er iets verspringt, dus een skelet dat zelf overloopt
      // is erger dan het wieltje dat hij vervangt.
      await t.binding.setSurfaceSize(maat);
      addTearDown(() => t.binding.setSurfaceSize(null));

      await t.pumpWidget(_omhulsel(
        const Column(
          children: [
            Expanded(child: SkeletRaster(tegels: 8)),
            Expanded(child: SkeletLijst(regels: 5)),
          ],
        ),
        maat,
        schaal,
      ));
      await t.pump(const Duration(milliseconds: 300));

      expect(t.takeException(), isNull);
    });
  }

  testWidgets('grotere systeemletters maken de rij hoger', (t) async {
    final gemeten = <double, double>{};
    for (final schaal in <double>[1.0, 1.35]) {
      await t.pumpWidget(_omhulsel(
        Builder(builder: (context) {
          gemeten[schaal] = hoogteVanTegelrij(context);
          return const SizedBox();
        }),
        const Size(960, 540),
        schaal,
      ));
    }
    expect(gemeten[1.35]!, greaterThan(gemeten[1.0]!),
        reason: 'op 1,35× tekst hoort de rij hoger te worden, niet de tegel kleiner');
  });

  testWidgets('een tegel in een échte rij wordt niet afgeknipt', (t) async {
    // De hele reden dat de formule bestaat: dit is de opstelling waarin de fout zich voordeed.
    await t.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(_omhulsel(
      Builder(builder: (context) => SizedBox(
            height: hoogteVanTegelrij(context),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => _proef(),
            ),
          )),
      const Size(960, 540),
      1.35,
    ));

    expect(t.takeException(), isNull);
    expect(find.byType(AlbumTegel), findsWidgets);
  });
}
