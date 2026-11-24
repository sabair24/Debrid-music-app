/// De voorproef: horen voor je kiest, zonder iets te bewaren (Saber, 23-11-2026).
///
/// Twee soorten, één tegelijk:
///  * **Een fragment** van 30 s van Deezer of iTunes ([fragment]) — er wordt niets gedownload. In de AI-lijst ("ja van
///    deezer").
///  * **Een Soulseek-proef** ([soulseek]) voor wat Deezer en iTunes niet kennen, en bij Bronnen en zoekresultaten
///    (*"maar gaat da via soulseek ??? da zou de max zijn, kunnen we ook gebruiken als ik een liedjes zoek en nie zeker
///    weet of het dit is"*): een gewone ▶-haal begint, de groeistroom klinkt [proefDuur] lang, en daarna stopt de haal en
///    gaat wat er al binnen was weg — tenzij je intussen op Houden tikte ([houd]): dan gaat dezelfde download gewoon door
///    (*"Verder halen bij Houden"*), en krijg je het nummer zodra het landt.
///
/// Alles wat de speler, Soulseek en de bibliotheek doen, komt erin geschoven: zo is de afloop zonder die drie te toetsen,
/// en dat is precies waar het stil fout kan gaan (een proef die blijft halen, of een gehouden nummer dat toch weggaat).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models.dart' show Track;
import 'radio.dart' show AlVanJou, Radioplek;
import 'soulseek.dart' show SoulseekFile;

/// Is dit fragment verlopen? Deezer zet een vervaltijd in het adres (`hdnea=exp=1732460000~…`): een fragment dat in
/// Ontdek of een bewaarde AI-lijst stond, speelt na een tijd niet meer. Een minuut speling; zonder vervaltijd (iTunes)
/// verloopt het niet.
bool fragmentVerlopen(String adres, {DateTime? nu}) {
  final m = RegExp(r'exp=(\d{9,})').firstMatch(adres);
  if (m == null) return false;
  final tot = int.parse(m.group(1)!);
  return (nu ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000 >= tot - 60;
}

/// Hoe lang een Soulseek-proef klinkt: het begin van het nummer.
const Duration kProefDuur = Duration(seconds: 30);

enum ProefFase {
  niets,

  /// Op Soulseek zoeken en beginnen te halen; nog niets te horen.
  zoekt,
  klinkt,

  /// Je tikte op Houden: de download gaat door.
  gehouden,

  /// Soulseek had niets bruikbaars (of de pc was er niet).
  nietGevonden,
}

/// Een Soulseek-haal voor de proef: [klinkt] met een afspeelbaar adres zodra de groeistroom kan klinken, [bijStop] met
/// het handvat om af te breken; geeft het gelande nummer, of null. Gooit [AlVanJou] als het nummer al van jou was.
typedef ProefHaal = Future<Track?> Function(Radioplek plek,
    {SoulseekFile? alleen, required void Function(String adres) klinkt, required void Function(void Function() stop) bijStop});

class _Proef {
  _Proef(this.sleutel, {required this.soulseek});
  final String sleutel;
  final bool soulseek;
  ProefFase fase = ProefFase.zoekt;
  bool gehouden = false;
  bool afgelopen = false;
  bool alVanJou = false;
  void Function()? stop;
  Track? geland;
  final landing = Completer<Track?>();
}

class Voorproef extends ChangeNotifier {
  Voorproef({
    required this.speel,
    required this.stopSpeler,
    required this.klinktNog,
    required this.haal,
    required this.vergeet,
    this.proefDuur = kProefDuur,
    this.wacht = const Duration(milliseconds: 500),
  });

  /// Speel [adres] op de tweede speler (PlayerStore.voorproef); [duur]: stop vanzelf. Geeft terug of het lukte.
  final Future<bool> Function(String adres, String sleutel, Duration? duur) speel;
  final Future<void> Function(String sleutel) stopSpeler;

  /// Klinkt [sleutel] nog op de tweede speler (PlayerStore.voorproefVan)?
  final bool Function(String sleutel) klinktNog;
  final ProefHaal haal;

  /// Een geland nummer dat niemand hield, weer weg (naar de prullenbak, zoals een radionummer).
  final Future<void> Function(Track t) vergeet;
  final Duration proefDuur;
  final Duration wacht;

  _Proef? _nu;
  Timer? _bewaker;

  /// Wat [sleutel] nu doet.
  ProefFase faseVan(String sleutel) => _nu?.sleutel == sleutel ? _nu!.fase : ProefFase.niets;

  /// Loopt er voor [sleutel] een Soulseek-proef die nog niet voorbij is? Dan is ▶ of ⬇ "Houden" ([houd]).
  bool loopt(String sleutel) {
    final p = _nu;
    return p != null && p.sleutel == sleutel && p.soulseek && !p.afgelopen;
  }

  /// Een fragment van Deezer of iTunes beluisteren.
  Future<void> fragment(String sleutel, String adres) async {
    await _rondAf();
    final p = _nu = _Proef(sleutel, soulseek: false)..fase = ProefFase.klinkt;
    notifyListeners();
    if (!await speel(adres, sleutel, null)) {
      if (identical(_nu, p)) _nu = null;
      notifyListeners();
      return;
    }
    _bewaak(p);
  }

  /// Een Soulseek-proef voor [plek] ([alleen]: dit ene bestand, uit Bronnen).
  Future<void> soulseek(String sleutel, Radioplek plek, {SoulseekFile? alleen}) async {
    await _rondAf();
    final p = _nu = _Proef(sleutel, soulseek: true);
    notifyListeners();
    Track? t;
    try {
      t = await haal(plek,
          alleen: alleen,
          bijStop: (s) {
            p.stop = s;
            if (p.afgelopen && !p.gehouden) s(); // te laat gekregen: meteen
          },
          klinkt: (adres) {
            if (p.afgelopen) return;
            if (!p.gehouden) p.fase = ProefFase.klinkt;
            notifyListeners();
            unawaited(speel(adres, sleutel, proefDuur).then((ok) {
              if (ok) _bewaak(p);
            }));
          });
    } on AlVanJou catch (e) {
      t = e.nummer;
      p.alVanJou = true;
    } catch (_) {
      t = null;
    }
    p.geland = t;
    if (!p.landing.isCompleted) p.landing.complete(t);
    if (t == null) {
      if (!p.afgelopen && identical(_nu, p) && p.fase == ProefFase.zoekt) {
        p.fase = ProefFase.nietGevonden;
        notifyListeners();
      }
      return;
    }
    // Voorbij en niet gehouden, maar het landde toch (een klein bestand, net op tijd): weer weg.
    if (p.afgelopen && !p.gehouden && !p.alVanJou) await vergeet(t);
  }

  /// Eerst een fragment zoeken ([zoekFragment]: Deezer, iTunes), en is er geen, de Soulseek-proef — voor waar de app geen
  /// fragment bij de hand heeft (een albumpagina, Ontdek, de artiestpagina, Nieuwe releases; Saber, 24-11-2026). Intussen
  /// staat de knop op "zoekt"; nog eens tikken stopt ook dit.
  Future<void> zoekEnProef(String sleutel, Radioplek plek, Future<String?> Function() zoekFragment) async {
    await _rondAf();
    final p = _nu = _Proef(sleutel, soulseek: false);
    notifyListeners();
    String? f;
    try {
      f = await zoekFragment();
    } catch (_) {}
    if (!identical(_nu, p)) return; // intussen gestopt of een andere proef
    _nu = null;
    if (f != null) return fragment(sleutel, f);
    return soulseek(sleutel, plek);
  }

  /// Houden: de download gaat door; geeft het nummer zodra het landt (null als het niet lukte).
  Future<Track?> houd(String sleutel) {
    final p = _nu;
    if (p == null || p.sleutel != sleutel || !p.soulseek) return Future.value(null);
    p
      ..gehouden = true
      ..fase = ProefFase.gehouden;
    notifyListeners();
    return p.landing.future;
  }

  /// De proef van [sleutel] stoppen (de knop nog eens).
  Future<void> stop(String sleutel) async {
    if (_nu?.sleutel != sleutel) return;
    await _rondAf();
  }

  void _bewaak(_Proef p) {
    _bewaker?.cancel();
    _bewaker = Timer.periodic(wacht, (t) {
      if (!identical(_nu, p) || p.afgelopen) {
        t.cancel();
        return;
      }
      if (!klinktNog(p.sleutel)) {
        t.cancel();
        unawaited(_rondAf(alleen: p));
      }
    });
  }

  /// De lopende proef afronden: niet gehouden = de haal stopt, en wat al landde gaat weg.
  Future<void> _rondAf({_Proef? alleen}) async {
    final p = _nu;
    if (p == null || (alleen != null && !identical(p, alleen))) return;
    _nu = null;
    _bewaker?.cancel();
    p.afgelopen = true;
    if (klinktNog(p.sleutel)) await stopSpeler(p.sleutel);
    if (p.soulseek && !p.gehouden) {
      p.stop?.call();
      final t = p.geland;
      if (t != null && !p.alVanJou) await vergeet(t);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _bewaker?.cancel();
    super.dispose();
  }
}
