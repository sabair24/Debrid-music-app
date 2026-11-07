/// Hoeveel zoekopdrachten per vijf minuten Soulseek verdraagt — niet geraden, maar al doende gevonden.
///
/// **Waarom dit bestaat.** Saber, 07-11-2026: *"kan het afhalen van de cd kwaliteit sneller … verhoog systematisch, en
/// kijk wat de grens is, wordt ik even van soulseek eruit gegooid dat geeft niets"*. De vaste rem van veertig per vijf
/// minuten ([kZoekPerVijfMinuten]) lag ruim onder de laagste gemeten sluiting (55), en de achtergrond (de radio, de
/// cd-jacht, de verlanglijst) kreeg er daarvan maar twintig. Waar de echte grens ligt, wist niemand: hij hangt af van de
/// server en verandert misschien. Dus tast de app hem zelf af:
///
///  * **Omhoog** met [kZoekgrensStap] als de rem minstens [kZoekgrensStapNa] niet veranderde en hij nu echt vol zit
///    ([kZoekgrensVol] van de grens in de laatste vijf minuten) — alleen wat gebruikt wordt, is getoetst.
///  * **Een probleem** — de server sluit de verbinding, of geeft vier vragen op rij niets door ([kZwijgDrempel]) — bij
///    een hoog tempo ([kZoekgrensTelt] van de grens of meer): dát aantal is de gemeten grens. De rem zakt naar
///    [kZoekgrensMarge] ervan en blijft [kZoekgrensRust] staan voor hij weer probeert. Bij een laag tempo was het iets
///    anders (wifi, een herstart) en telt het niet.
///  * Nooit onder [kZoekgrensBodem], nooit boven [kZoekgrensPlafond] (de hoogste sluiting die ooit gemeten is).
///
/// Elke stap staat in `soulseek_login.log`, en de stand in `soulseek_zoekgrens.json`, zodat een herstart niet weer bij
/// veertig begint.
library;

import 'dart:convert';
import 'dart:io';

/// Waar de rem begint zonder iets bewaard (de vaste rem van vóór 07-11-2026).
const int kZoekgrensStart = 40;

/// Lager gaat hij nooit: dertig in vijf minuten bleef altijd goed.
const int kZoekgrensBodem = 30;

/// Hoger probeert hij nooit: de hoogste sluiting die gemeten is (22-10-2026: 55, 68, 70, 70 in vijf minuten).
const int kZoekgrensPlafond = 70;

/// Zoveel erbij per stap.
const int kZoekgrensStap = 2;

/// Zo lang moet een stand gelden voor de volgende stap.
const kZoekgrensStapNa = Duration(minutes: 20);

/// Alleen omhoog als er in de laatste vijf minuten minstens dit deel van de grens gezocht is.
const double kZoekgrensVol = 0.8;

/// Een probleem telt als grens als er in de vijf minuten ervoor minstens dit deel van de grens gezocht was.
const double kZoekgrensTelt = 0.6;

/// Na een probleem: de rem naar dit deel van wat er toen gezocht was.
const double kZoekgrensMarge = 0.8;

/// Na een probleem zo lang niet omhoog.
const kZoekgrensRust = Duration(hours: 24);

/// De zelf afgetaste grens van de zoekrem — zie de uitleg bovenaan.
class Zoekgrens {
  /// [bestand]: waar de stand bewaard wordt (null: niet bewaren, voor toetsen). [log]: één regel per stap.
  Zoekgrens({this.bestand, this.log, DateTime Function()? klok}) : _klok = klok ?? DateTime.now;

  final String Function()? bestand;
  final void Function(String)? log;
  final DateTime Function() _klok;

  bool _geladen = false;
  int _perVijf = kZoekgrensStart;

  /// Het aantal zoekopdrachten in vijf minuten bij het laatste probleem dat telde, en wanneer.
  int? gemeten;
  DateTime? gemetenOp;

  /// Tot wanneer hij na een probleem niet omhoog gaat.
  DateTime? rustTot;

  /// Sinds wanneer de huidige stand geldt (na een herstart: vanaf de eerste zoekopdracht).
  DateTime? _sinds;

  /// Hoeveel zoekopdrachten er nu hoogstens in vijf minuten mogen, voor de hele app samen.
  int get perVijf {
    _laad();
    return _perVijf;
  }

  /// Na elke verstuurde zoekopdracht: [inVijf] = hoeveel er nu in de laatste vijf minuten gingen (deze erbij).
  void naZoeken(int inVijf) {
    _laad();
    final nu = _klok();
    final sinds = _sinds ??= nu;
    if (nu.difference(sinds) < kZoekgrensStapNa) return;
    if (rustTot != null && nu.isBefore(rustTot!)) return;
    if (_perVijf >= kZoekgrensPlafond || inVijf < _perVijf * kZoekgrensVol) return;
    final was = _perVijf;
    _perVijf = (_perVijf + kZoekgrensStap).clamp(kZoekgrensBodem, kZoekgrensPlafond);
    _sinds = nu;
    _bewaar();
    log?.call(
      'zoekgrens: $was → $_perVijf zoekopdrachten per 5 min ($inVijf gezocht in de laatste 5 min, '
      '${kZoekgrensStapNa.inMinutes} min zonder probleem)',
    );
  }

  /// De server deed moeilijk ([waarom]), met [inVijf] zoekopdrachten in de vijf minuten ervoor.
  void probleem(String waarom, int inVijf) {
    _laad();
    final nu = _klok();
    if (inVijf < _perVijf * kZoekgrensTelt) {
      log?.call(
        'zoekgrens: $waarom bij $inVijf zoekopdrachten in 5 min — te weinig om aan het tempo te liggen, '
        'de grens blijft $_perVijf',
      );
      return;
    }
    final was = _perVijf;
    gemeten = inVijf;
    gemetenOp = nu;
    _perVijf = (inVijf * kZoekgrensMarge).floor().clamp(kZoekgrensBodem, _perVijf);
    rustTot = nu.add(kZoekgrensRust);
    _sinds = nu;
    _bewaar();
    log?.call(
      'zoekgrens: $waarom bij $inVijf zoekopdrachten in 5 min — dat is de grens; $was → $_perVijf, '
      'de volgende stap omhoog over ${kZoekgrensRust.inHours} u',
    );
  }

  void _laad() {
    if (_geladen) return;
    _geladen = true;
    final pad = bestand?.call();
    if (pad == null) return;
    try {
      final f = File(pad);
      if (!f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync());
      if (j is! Map) return;
      final p = j['perVijf'];
      if (p is int) _perVijf = p.clamp(kZoekgrensBodem, kZoekgrensPlafond);
      final g = j['gemeten'];
      if (g is int) gemeten = g;
      gemetenOp = DateTime.tryParse('${j['gemetenOp'] ?? ''}');
      rustTot = DateTime.tryParse('${j['rustTot'] ?? ''}');
    } catch (_) {
      /* dan van voren af aan */
    }
  }

  void _bewaar() {
    final pad = bestand?.call();
    if (pad == null) return;
    try {
      File(pad).writeAsStringSync(
        jsonEncode({
          'perVijf': _perVijf,
          if (gemeten != null) 'gemeten': gemeten,
          if (gemetenOp != null) 'gemetenOp': gemetenOp!.toIso8601String(),
          if (rustTot != null) 'rustTot': rustTot!.toIso8601String(),
        }),
      );
    } catch (_) {
      /* de volgende stap probeert het opnieuw */
    }
  }
}
