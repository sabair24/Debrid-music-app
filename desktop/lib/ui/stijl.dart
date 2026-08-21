/// De stijlpagina: alles wat de app aan vorm heeft, op één scherm.
///
/// **Waarom dit bestaat, en waarom het de moeite waard is.** Wie hieraan werkt kan de app niet
/// zien — er draait hier geen Flutter en er hangt geen toestel aan. Elke wijziging aan de vorm kost
/// dus een ronde met schermafbeeldingen, en tot nu toe waren dat er zes per keer: Start, Albums,
/// een albumpagina, het speelscherm, een leeg scherm, en dan nog eens hetzelfde op de televisie.
///
/// Deze pagina zet de grijstrap, de hoeken, de tekstrollen, de schaduwen, de tegel in elke stand en
/// het lege vlak onder elkaar. Eén schermafbeelding in plaats van zes — nu en bij elke ronde hierna.
///
/// Ze staat met opzet niet in de navigatie: dit is gereedschap, geen scherm van de app. Achter
/// Instellingen, onderaan.
library;

import 'package:flutter/material.dart';

import '../tv.dart';
import 'kleuren.dart';
import 'leeg.dart';
import 'maten.dart';
import 'tegel.dart';
import 'typografie.dart';
import 'vlak.dart';

/// Alles wat de app aan vorm heeft, onder elkaar.
class StijlPagina extends StatelessWidget {
  const StijlPagina({super.key});

  static const _trap = <(String, Color)>[
    ('achtergrond', kAchtergrond),
    ('verzonken', kVerzonken),
    ('paneel', kPaneel),
    ('actief', kPaneelHoog),
    ('bovenop', kBovenop),
    ('lijn', kLijn),
  ];

  static const _rollen = <(String, TextStyle)>[
    ('kKopGroot 25/800', kKopGroot),
    ('kKop 22/700', kKop),
    ('kKopKlein 18/700', kKopKlein),
    ('kTekstNormaal 14/600', kTekstNormaal),
    ('kTekstBij 13,5', kTekstBij),
    ('kTekstKlein 12', kTekstKlein),
    ('kLabel 11/600', kLabel),
  ];

  static const _hoeken = <(String, double)>[
    ('kHoek4', kHoek4),
    ('kHoek8', kHoek8),
    ('kHoek12', kHoek12),
    ('kHoek18', kHoek18),
  ];

  static const _ruimtes = <(String, double)>[
    ('2', kRuimte2),
    ('4', kRuimte4),
    ('6', kRuimte6),
    ('8', kRuimte8),
    ('12', kRuimte12),
    ('16', kRuimte16),
    ('24', kRuimte24),
    ('32', kRuimte32),
  ];

  @override
  Widget build(BuildContext context) {
    final schaal = MediaQuery.textScalerOf(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kAchtergrond,
        title: const Text('Stijl'),
      ),
      backgroundColor: kAchtergrond,
      body: ListView(
        padding: const EdgeInsets.only(bottom: kRuimte32),
        children: [
          _kop('Grijstrap — L* per stap'),
          for (var i = 0; i < _trap.length; i++)
            _trede(_trap[i], i == 0 ? null : _trap[i - 1].$2),
          _kop('Niveaus met verloop, rand en schaduw'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kGoot),
            child: Wrap(
              spacing: kRuimte12,
              runSpacing: kRuimte12,
              children: [
                for (final n in Niveau.values)
                  Container(
                    width: 150,
                    height: 74,
                    alignment: Alignment.center,
                    decoration: paneelDecoratie(n),
                    child: Text(n.name, style: kTekstKlein),
                  ),
              ],
            ),
          ),
          _kop('Hoeken'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kGoot),
            child: Wrap(
              spacing: kRuimte12,
              runSpacing: kRuimte12,
              children: [
                for (final (naam, r) in _hoeken)
                  Container(
                    width: 92,
                    height: 62,
                    alignment: Alignment.center,
                    decoration: paneelDecoratie(Niveau.hoog, radius: r),
                    child: Text(naam, style: kLabel),
                  ),
                Container(
                  width: 92,
                  height: 62,
                  alignment: Alignment.center,
                  decoration: paneelDecoratie(Niveau.hoog, radius: kHoekRond),
                  child: const Text('rond', style: kLabel),
                ),
              ],
            ),
          ),
          _kop('Ruimte'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kGoot),
            child: Wrap(
              spacing: kRuimte12,
              runSpacing: kRuimte8,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                for (final (naam, w) in _ruimtes)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(naam, style: kLabel),
                      const SizedBox(height: kRuimte4),
                      Container(width: w, height: 26, color: kAccent),
                    ],
                  ),
              ],
            ),
          ),
          // Geen `plat: false` hier: op een televisie hóórt dit blok drie platte vlakken te tonen.
          // Dat is wat er daar getekend wordt, en een stijlpagina die iets anders laat zien dan het
          // toestel doet is erger dan geen stijlpagina.
          _kop('Schaduw'),
          Padding(
            padding: const EdgeInsets.fromLTRB(kGoot, 0, kGoot, kRuimte16),
            child: Wrap(
              spacing: kRuimte24,
              runSpacing: kRuimte24,
              children: [
                for (final (naam, sch) in <(String, List<BoxShadow>)>[
                  ('kSchaduw1', kSchaduw1),
                  ('kSchaduw2', kSchaduw2),
                  ('kSchaduw3', kSchaduw3),
                ])
                  Container(
                    width: 96,
                    height: 62,
                    alignment: Alignment.center,
                    decoration: paneelDecoratie(Niveau.paneel, schaduw: sch),
                    child: Text(naam, style: kLabel),
                  ),
              ],
            ),
          ),
          _kop('Tekstrollen'),
          for (final (naam, stijl) in _rollen)
            Padding(
              padding: const EdgeInsets.fromLTRB(kGoot, 0, kGoot, kRuimte6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: Text('Papaoutai — Stromae', style: stijl)),
                  Text(naam, style: kLabel),
                ],
              ),
            ),
          _kop('Tegel — rust, aangewezen, gemarkeerd'),
          SizedBox(
            height: hoogteVanTegelrij(context),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: kGoot),
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(width: kRuimte12),
              itemBuilder: (_, i) => AlbumTegel(
                hoes: (maat) => _proefhoes(maat, i),
                breedte: kTegelHoes,
                titel: 'Racine Carrée',
                ondertitel: 'Stromae',
                onTap: () {},
              ),
            ),
          ),
          _kop('Leeg vlak'),
          LeegVlak(
            teken: Icons.library_music_rounded,
            kop: 'Nog geen muziek hier',
            uitleg: 'Zodra je pc gescand heeft, staan je platen hier. Of zoek er zelf een op.',
            knop: 'Online zoeken',
            opKnop: () {},
            // Deze pagina is een `ListView`. Zie [LeegVlak.gecentreerd].
            gecentreerd: false,
          ),
          _kop('Toestel'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kGoot),
            child: Text(
              'televisie: $isTv · tekstschaal: ${(schaal.scale(10) / 10).toStringAsFixed(2)}× · '
              'rijhoogte: ${hoogteVanTegelrij(context).toStringAsFixed(0)} · '
              'breedte: ${MediaQuery.sizeOf(context).width.toStringAsFixed(0)}',
              style: kTekstKlein,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _proefhoes(double maat, int i) => Container(
        width: maat,
        height: maat,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kHoek12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              [kAccent, kAccent2, const Color(0xFFE8913A), const Color(0xFF8A90A6)][i % 4],
              kAchtergrond,
            ],
          ),
        ),
      );

  static Widget _kop(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(kGoot, kRuimte24, kGoot, kRuimte12),
        child: Text(t, style: kKopKlein),
      );

  static Widget _trede((String, Color) stap, Color? vorige) {
    final l = sterrenL(stap.$2);
    final delta = vorige == null ? null : l - sterrenL(vorige);
    return Container(
      height: 44,
      color: stap.$2,
      padding: const EdgeInsets.symmetric(horizontal: kGoot),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(child: Text(stap.$1, style: kTekstKlein.copyWith(color: kTekst))),
          Text(
            'L* ${l.toStringAsFixed(1)}'
            '${delta == null ? '' : '   ΔL* ${delta.toStringAsFixed(1)}'}',
            style: kLabel,
          ),
        ],
      ),
    );
  }
}
