/// Wat een zone doet met een opdracht van een ander toestel ("Speelt op: … ▾", Saber 21-10-2026). Op elk
/// toestel hetzelfde: de pc voor zijn eigen zone, een gsm of iPad voor de zijne.
///
/// Elke opdracht is een STAND en geen schakelaar (`play`, niet "wissel"): komen er twee tegelijk van twee
/// toestellen, dan wint de laatste, en iedereen ziet daarna dezelfde uitkomst. Een opdracht die al eens
/// aankwam (dezelfde `id`, bijvoorbeeld na een tweede lijn naar hetzelfde toestel), wordt niet nog eens
/// uitgevoerd.
library;

import 'dart:async';

import 'models.dart';
import 'lan/zones.dart' show plekVoorNummer;
import 'player.dart' show Rijbediening, Speelbron;
import 'wekker.dart' show wektToestel;
import 'zone_speler.dart' show herhaalUit;

/// Hoeveel opdracht-ids er onthouden worden om een dubbele te herkennen.
const kZoneOpdrachtGeheugen = 50;

/// De nummers uit [ids] die dit toestel kent, en waar [plek] daarin terechtkomt. Onbekende vallen weg;
/// valt het nummer op [plek] zelf weg, dan het eerstvolgende.
({List<Track> rij, int plek}) rijUitIds(List<String> ids, int plek, Track? Function(String id) nummer) {
  final rij = <Track>[];
  var nieuw = -1;
  for (var i = 0; i < ids.length; i++) {
    final t = nummer(ids[i]);
    if (t == null) continue;
    if (i >= plek && nieuw < 0) nieuw = rij.length;
    rij.add(t);
  }
  return (rij: rij, plek: nieuw < 0 ? 0 : nieuw);
}

/// Voert opdrachten uit op de speler van dit toestel.
class ZoneUitvoerder {
  ZoneUitvoerder({
    required this.speler,
    required this.rij,
    required this.nummer,
    this.idVan,
    this.radio,
    this.radioStop,
    this.kijkInBrievenbus,
    this.verplaatst,
    this.meet,
    this.neemOver,
    this.samen,
    this.samenStop,
    this.naUitvoeren,
    this.log,
    this.tussendoor,
    this.tussendoorAB,
    this.tussendoorKlaar,
    this.versie,
    this.wek,
  });

  /// Vóór een opdracht die muziek laat beginnen ([wektToestel]): een slapende Shield wekken en wachten tot de tv aan
  /// is (wekker.dart, Saber 31-10-2026). Null: hier valt niets te wekken.
  final Future<void> Function()? wek;

  /// Een andere versie van het spelende nummer (versies.dart): [trackId] het nummer, [versieId] de versie (of het nummer
  /// zelf). Null als het lukte, anders waarom niet. Zie `PlayerStore.wisselVersie`.
  final Future<String?> Function(String trackId, String versieId)? versie;

  /// Een klaargezette kopie van [Track] beluisteren zonder de wachtrij aan te raken ("Klaar om te kiezen", Saber
  /// 26-10-2026: "op de zone die actief is"). Null als het lukte, anders waarom niet. Zie `PlayerStore.tussendoor`.
  final Future<String?> Function(Track t)? tussendoor;

  /// A en B wisselen bij het tussendoor beluisteren.
  final Future<void> Function()? tussendoorAB;

  /// Tussendoor stoppen; met [hervat] gaat het nummer dat speelde verder.
  final Future<void> Function({required bool hervat})? tussendoorKlaar;

  /// Een anker van de groep die dit toestel volgt (stap 3.2, zie `samen.dart`), en het einde daarvan.
  final Future<void> Function(Map<String, dynamic> anker)? samen;
  final Future<void> Function({bool pauzeer})? samenStop;

  /// De muziek van een andere zone hier verder spelen ([stand] = haar melding, zie `/api/zone/transfer`).
  /// True als het lukte. Zie `VerderLuisteren.neemOverUit`.
  final Future<bool> Function(Map<String, dynamic> stand)? neemOver;

  /// Het id van de pc voor een nummer hier: om bij springen, weghalen en verplaatsen het juiste nummer
  /// te vinden als de wachtrij intussen verschoof. Null: alleen op de plek.
  final String? Function(Track t)? idVan;

  /// Waar het nummer [trackId] (met [plek] als voorkeur) nu in de wachtrij van de speler staat.
  int _plek(int plek, String trackId) {
    final f = idVan;
    if (f == null || trackId.isEmpty) return plek;
    return plekVoorNummer([for (final t in speler.queueTracks) f(t) ?? ''], plek, trackId);
  }

  final Speelbron speler;
  final Rijbediening rij;

  /// Een id van de pc als nummer hier.
  final Track? Function(String id) nummer;

  /// Een radio starten rond [artiest], met [zaad] (of het nummer [titel]) eerst.
  final Future<void> Function(String artiest, {Track? zaad, String? titel, String? door})? radio;

  /// De radio van dit toestel afsluiten, op verzoek van [door] (een zone): daar komt het overzicht (Saber, 23-10-2026:
  /// "waar ik 'Radio afsluiten' tik"). Null: hier kan dat niet.
  final void Function({String? door})? radioStop;

  /// Er ligt een overzicht in de brievenbus van dit toestel (een seintje van de pc): kijk meteen.
  final void Function()? kijkInBrievenbus;

  /// De muziek van dit toestel speelt nu op een andere zone ([naar], haar naam): stop hier, en meld het meteen —
  /// zie `VerderLuisteren.isVerplaatst` en `LanServer._bronVerplaatst` (Saber, 23-10-2026: "A stopt helemaal").
  final void Function(String naar)? verplaatst;

  /// Een meetronde (`meetronde.dart`, Saber 23-10-2026: "zorg er dan voor, zo kan je het beste meten"): dit toestel
  /// meet zichzelf. Loopt op de achtergrond; de uitkomst gaat naar `warmte.log` op de pc.
  final Future<void> Function(Map<String, dynamic> op)? meet;

  /// Na elke opdracht: meld de nieuwe stand meteen, zodat wie bedient het ziet.
  final void Function()? naUitvoeren;
  final void Function(String)? log;

  final _gezien = <String>[];

  /// Voer [op] uit. Null als het lukte, anders waarom niet.
  Future<String?> voerUit(Map<String, dynamic> op) async {
    final id = '${op['id'] ?? ''}';
    if (id.isNotEmpty) {
      if (_gezien.contains(id)) return null;
      _gezien.add(id);
      if (_gezien.length > kZoneOpdrachtGeheugen) _gezien.removeAt(0);
    }
    final cmd = '${op['cmd'] ?? ''}';
    final ids = [for (final x in (op['ids'] as List? ?? const [])) '$x'];
    String? fout;
    try {
      if (wektToestel(cmd)) {
        try {
          await wek?.call();
        } catch (_) {/* niet wakker gekregen: de opdracht gaat toch door */}
      }
      switch (cmd) {
        case 'play':
          speler.speelAf();
        case 'pause':
          speler.pauzeer();
        // "Stop" op de kaart (Saber, 23-10-2026: "Pauze/stop"): hier pauzeren; de pc zet de zone op "Speelt niets",
        // en verder spelen vanaf dezelfde plek kan nog.
        case 'stop':
          speler.pauzeer();
        case 'next':
          await speler.next();
        case 'previous':
          await speler.prev();
        case 'seek':
          speler.seek(Duration(milliseconds: (op['ms'] as num?)?.toInt() ?? 0));
        case 'shuffle':
          speler.zetShuffle(op['aan'] == true);
        case 'repeat':
          speler.zetHerhaal(herhaalUit('${op['stand'] ?? 'off'}'));
        case 'volume':
          speler.setVolume(((op['waarde'] as num?) ?? 100).toDouble());
        case 'jump':
          final i = _plek((op['plek'] as num?)?.toInt() ?? 0, '${op['trackId'] ?? ''}');
          if (i < 0) {
            fout = 'Dat nummer staat niet meer in de wachtrij';
          } else {
            await speler.springNaar(i);
          }
        case 'remove':
          final i = _plek((op['plek'] as num?)?.toInt() ?? -1, '${op['trackId'] ?? ''}');
          if (i < 0 || !speler.haalUitWachtrij(i)) fout = 'Dat nummer staat niet (meer) in de wachtrij';
        case 'move':
          final i = _plek((op['van'] as num?)?.toInt() ?? -1, '${op['trackId'] ?? ''}');
          final naar = (op['naar'] as num?)?.toInt() ?? -1;
          if (i < 0 || !speler.verplaatsInWachtrij(i, naar)) fout = 'Dat nummer staat niet (meer) in de wachtrij';
        case 'speel':
          final r = rijUitIds(ids, (op['plek'] as num?)?.toInt() ?? 0, nummer);
          if (r.rij.isEmpty) {
            fout = 'Die nummers staan hier niet in de bibliotheek';
          } else if (op['shuffle'] == true) {
            await rij.shuffleAll(r.rij);
          } else {
            await rij.playQueue(r.rij, r.plek);
          }
        case 'nu':
          final t = nummer('${op['id'] ?? ''}');
          if (t == null) {
            fout = 'Dat nummer staat hier niet in de bibliotheek';
          } else {
            await rij.speelNuMetRest(t);
          }
        case 'hierna' || 'achteraan':
          final ts = [for (final i in ids) if (nummer(i) case final t?) t];
          if (ts.isEmpty) {
            fout = 'Die nummers staan hier niet in de bibliotheek';
          } else if (cmd == 'hierna') {
            rij.speelHierna(ts);
          } else {
            rij.zetAchteraan(ts);
          }
        case 'samen':
          final a = (op['anker'] as Map?)?.cast<String, dynamic>();
          if (a != null) await samen?.call(a);
        case 'samenStop':
          await samenStop?.call(pauzeer: op['houdSpelen'] != true);
        case 'neemOver':
          final stand = (op['stand'] as Map?)?.cast<String, dynamic>();
          final f = neemOver;
          if (stand == null || f == null || !await f(stand)) fout = 'Overnemen lukte niet';
        case 'radio':
          final artiest = '${op['artiest'] ?? ''}'.trim();
          final r = radio;
          if (artiest.isEmpty || r == null) {
            fout = 'Hier kan geen radio starten';
          } else {
            final zaad = op['zaad'] == null ? null : nummer('${op['zaad']}');
            final titel = '${op['titel'] ?? ''}'.trim();
            final door = '${op['door'] ?? ''}';
            await r(artiest, zaad: zaad, titel: titel.isEmpty ? null : titel, door: door.isEmpty ? null : door);
          }
        case 'radioStop':
          final f = radioStop;
          final door = '${op['door'] ?? ''}';
          if (f == null) {
            fout = 'Hier kan geen radio afgesloten worden';
          } else {
            f(door: door.isEmpty ? null : door);
          }
        case 'verplaatst':
          final f = verplaatst;
          if (f == null) {
            fout = 'Hier kan niet gestopt worden';
          } else {
            f('${op['naar'] ?? ''}');
          }
        case 'meet':
          final f = meet;
          if (f == null) {
            fout = 'Hier kan niet gemeten worden';
          } else {
            unawaited(f(op));
          }
        case 'radioOverzicht':
          kijkInBrievenbus?.call();
        case 'tussendoor':
          final t = nummer('${op['trackId'] ?? ''}');
          final f = tussendoor;
          if (f == null) {
            fout = 'Dit toestel kan nog niet tussendoor beluisteren — werk het bij';
          } else if (t == null) {
            fout = 'Dat nummer staat hier niet in de bibliotheek';
          } else {
            fout = await f(t);
          }
        case 'tussendoorAB':
          await tussendoorAB?.call();
        case 'tussendoorKlaar':
          await tussendoorKlaar?.call(hervat: op['hervat'] != false);
        case 'versie':
          final f = versie;
          fout = f == null
              ? 'Dit toestel kan nog niet van versie wisselen — werk het bij'
              : await f('${op['trackId'] ?? ''}', '${op['versieId'] ?? ''}');
        default:
          fout = 'Onbekende opdracht "$cmd"';
      }
    } catch (e) {
      fout = 'Mislukt: $e';
    }
    // Een anker komt om de vijf seconden: niet elke keer in het logboek, en geen extra melding.
    if (cmd == 'samen') return fout;
    log?.call('opdracht $cmd${fout == null ? '' : ' — $fout'}  (van ${op['van'] ?? '?'})');
    naUitvoeren?.call();
    return fout;
  }
}
