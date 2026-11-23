/// De knop van de voorproef (voorproef.dart): een fragment als er een is, anders een Soulseek-proef.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../radio.dart' show Radioplek;
import '../soulseek.dart' show SoulseekFile;
import '../voorproef.dart';
import 'kleuren.dart';

/// Eén knop: tik = 30 s horen, nog eens = stoppen. [fragment]: een adres van Deezer of iTunes (er wordt niets
/// gedownload); anders een Soulseek-proef voor [plek] ([bestand]: dit ene bestand, uit Bronnen). [sleutel]: wat deze
/// knop beproeft — ▶ of ⬇ ernaast vraagt [Voorproef.loopt] om dezelfde download te laten doorgaan.
class VoorproefKnop extends StatelessWidget {
  const VoorproefKnop({super.key, required this.sleutel, this.fragment, this.plek, this.bestand, this.maat = 22});

  final String sleutel;
  final String? fragment;
  final Radioplek? plek;
  final SoulseekFile? bestand;
  final double maat;

  bool get _kan => fragment != null || plek != null;

  @override
  Widget build(BuildContext context) {
    final v = context.watch<Voorproef?>();
    if (v == null || !_kan) return const SizedBox.shrink();
    final fase = v.faseVan(sleutel);
    final soulseek = fragment == null;
    final (Widget icoon, String uitleg) = switch (fase) {
      ProefFase.zoekt => (
          SizedBox(width: maat * 0.8, height: maat * 0.8, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)),
          'Zoekt op Soulseek — tik om te stoppen'
        ),
      ProefFase.klinkt => (Icon(Icons.stop_circle_outlined, size: maat, color: kAccent), 'Stop de voorproef'),
      ProefFase.gehouden => (Icon(Icons.check_circle_outline_rounded, size: maat, color: kAccent2), 'Gehouden — hij wordt gehaald'),
      ProefFase.nietGevonden => (
          Icon(Icons.hearing_disabled_rounded, size: maat, color: kUitgezet),
          'Niet gevonden op Soulseek — tik om opnieuw te proberen'
        ),
      ProefFase.niets => (
          Icon(Icons.hearing_rounded, size: maat, color: kAccent),
          soulseek ? 'Voorproef van 30 s via Soulseek (wordt niet bewaard)' : 'Voorproef van 30 s (niets wordt gedownload)'
        ),
    };
    return IconButton(
      tooltip: uitleg,
      visualDensity: VisualDensity.compact,
      icon: icoon,
      onPressed: switch (fase) {
        ProefFase.zoekt || ProefFase.klinkt => () => v.stop(sleutel),
        ProefFase.gehouden => null,
        _ => () => fragment != null ? v.fragment(sleutel, fragment!) : v.soulseek(sleutel, plek!, alleen: bestand),
      },
    );
  }
}

/// ▶ of ⬇ naast een lopende Soulseek-proef: dezelfde download laten doorgaan (Saber: "Verder halen bij Houden").
/// Geeft terug of er een proef liep — dan hoeft de knop zelf niets te beginnen.
bool houdLopendeProef(BuildContext context, String sleutel) {
  final v = context.read<Voorproef?>();
  if (v == null || !v.loopt(sleutel)) return false;
  v.houd(sleutel);
  return true;
}
