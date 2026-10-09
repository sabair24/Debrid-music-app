/// Het bijvullen van een lopende radio, zonder taalmodel.
///
/// **Waarom dit bestaat.** Op 08-10-2026 hield de radio vanaf "Niels Destadsbader — Vuur en vlam" op
/// na dertien nummers. Er was geen bijvuller: het plan was wat Deezer bij de start gaf, en wat daarvan
/// niet te vinden was of geweerd werd, kwam nooit meer terug. Saber: *"het moet tot maximum kunnen
/// zoveel mogelijk! als hij er dan geen meer vindt dan mag hij ook niet stoppen."*
///
/// De regels staan in `radioladder.dart` (wanneer, en wat er herhaald wordt); hier staat wat een ronde
/// doet:
///
/// 1. **buren** — de toppers van de ankerartiest en van zijn `/related` bij Deezer. Nooit de
///    artiestenradio (`/artist/{id}/radio`): daar zitten bij Niels K3, Kinderen Voor Kinderen en
///    Katastroof in, en zonder sfeeroordeel van het model is er niets wat ze tegenhoudt. In
///    `/related` zitten ze niet (gemeten op 08-10-2026). De buren zijn pas "op" als ELKE artiest leeg
///    is — een vol plafond per artiest is wachten, geen gebrek (beoordeling van 08-10-2026).
/// 2. **opnieuw** — elke ronde: wat niet te vinden was en minstens een half uur oud is, nog één keer.
/// 3. **herhaal** — als er niets nieuws kwam en het krap wordt: iets wat je in deze radio hoorde.
///
/// Daarnaast de **reserve**: je eigen nummers van dezelfde artiesten, gekeurd zoals elk eigen nummer.
/// Die speelt alleen mee als het krap wordt.
library;

import 'dart:async';
import 'dart:math';

import 'models.dart' show Track;
import 'radio.dart';
import 'radiokeuze.dart' show artiestSleutel, basisTitel, kMaxPerArtiest;
import 'radioladder.dart';
import 'radiovoorraad.dart' show Haalstand;
import 'recommend.dart' show RecTrack;

/// Een artiest bij Deezer: id en naam.
typedef Bronartiest = ({int id, String naam});

/// Wat de bijvuller van Deezer nodig heeft — en niet meer. Functies, zodat een toets hem zonder
/// netwerk invult; en er staat bewust geen weg naar de artiestenradio in.
class Radiodeezer {
  const Radiodeezer({required this.bronArtiesten, required this.toppers});

  /// De artiest en, als [metVerwant], zijn `/related`. Null als Deezer de artiest niet kent.
  final Future<({int id, String naam, List<Bronartiest> verwant})?> Function(String artiest, bool metVerwant)
      bronArtiesten;

  /// [limit] toppers van artiest [id] vanaf plek [index].
  final Future<List<RecTrack>> Function(int id, String naam, int limit, int index) toppers;
}

/// Hoeveel toppers er per keer per artiest opgehaald worden. Eén verzoek; meestal genoeg voor de hele
/// radio, want er mogen er per artiest toch maar drie tegelijk in.
const int kToppersPerBlad = 25;

/// Hoeveel artiesten één buren-ronde aanspreekt.
const int kArtiestenPerRonde = 8;

/// Hoe vaak een artiest hoogstens in de reserve staat: een anker (de zaadartiest) één keer, de rest
/// twee. Zonder grens was de reserve van zes bij een radio vanaf Niels grotendeels Niels — en die
/// speelt juist als de rij leeg is (beoordeling van 08-10-2026; Sabers klacht over 2 Fabiola).
const int kReserveAnker = 1;
const int kReservePerArtiest = 2;

class Radiobijvuller {
  Radiobijvuller({
    required this.radio,
    required this.deezer,
    required this.ankers,
    required this.metVerwant,
    required this.maakPlan,
    this.keurEigen,
    this.reserveKandidaten,
    this.spoor,
    DateTime Function()? klok,
    Random? toeval,
  })  : _klok = klok ?? DateTime.now,
        _toeval = toeval ?? Random();

  final RadioBesturing radio;
  final Radiodeezer deezer;

  /// Waar deze radio om draait: de zaadartiest, of de artiesten uit een getypte zin.
  final List<String> ankers;

  /// Ook de `/related` van de ankers (een radio vanaf een artiest), of alleen de ankers zelf (een zin
  /// noemt er al twintig tot veertig, en die zíjn het genre).
  final bool metVerwant;

  /// Van Deezer-nummers naar plekken, met het plafond per artiest — `_radioplan` in main.dart.
  final List<Radioplek> Function(List<RecTrack> recs) maakPlan;

  /// De keuring van een eigen nummer; null: alles mag (een radio uit een zin keurt niet).
  final Future<bool> Function(Radioplek p)? keurEigen;

  /// Eigen nummers voor de reserve, bij deze artiesten ([artiestSleutel]s).
  final List<Track> Function(Set<String> artiesten)? reserveKandidaten;

  final void Function(String regel)? spoor;
  final DateTime Function() _klok;
  final Random _toeval;

  Future<List<Bronartiest>>? _bronnenF;
  final Map<int, List<RecTrack>> _toppers = {};
  final Map<int, int> _volgendBlad = {};
  final Set<int> _bladenOp = {};
  final Set<String> _aangeboden = {};

  /// Sinds wanneer alle buren leeg zijn — zie [kTrapHerstel].
  DateTime? _opSinds;
  bool _reserveBezig = false;
  final Set<String> _reserveGeprobeerd = {};

  static String _sleutel(String artiest, String titel) => '${artiestSleutel(artiest)}|${basisTitel(titel)}';

  /// De bronartiesten: ankers (en hun `/related`), elk één keer. Leeg, of zonder één verwante artiest
  /// terwijl die gevraagd waren (een time-out van `/related`): de volgende ronde vraagt het opnieuw —
  /// anders bleef de buurt de hele radio lang alleen de zaadartiest.
  Future<List<Bronartiest>> bronnen() => _bronnenF ??= () async {
        final uit = <Bronartiest>[];
        final gezien = <int>{};
        var verwant = 0;
        for (final a in ankers) {
          try {
            final b = await deezer.bronArtiesten(a, metVerwant);
            if (b == null) continue;
            if (gezien.add(b.id)) uit.add((id: b.id, naam: b.naam));
            for (final v in b.verwant) {
              if (gezien.add(v.id)) {
                uit.add(v);
                verwant++;
              }
            }
          } catch (_) {/* deze artiest niet; de rest wel */}
        }
        if (uit.isEmpty || (metVerwant && verwant == 0)) _bronnenF = null;
        return uit;
      }();

  /// Eén ronde — zie [Bijvuller]. Geeft terug hoeveel plekken er bij kwamen.
  Future<int> call(int sessie, int ronde, Bijvulvraag v) async {
    if (v.reserveNodig > 0) unawaited(vulReserve(sessie, v.reserveNodig));
    // Herkansen kost niets en hoort niet achter de buren te wachten.
    final herkanst = radio.herkans(sessie, ronde: ronde);
    final r = await _buren(sessie, ronde);
    if (sessie != radio.sessie || ronde != radio.bijvulRonde) return 0;
    final n = r.nieuw + herkanst;
    // Niets nieuws, en het wordt krap: dan herhalen, in dezelfde ronde. Niet bij nood: dan heeft de
    // noodvulling van de radio al gezorgd (reserve of herhalen), en kwamen er anders in één keer twee
    // reservenummers plus twee herhalingen (tweede beoordeling van 08-10-2026).
    var herhaald = 0;
    if (n == 0 && !v.nood && v.verwacht < 3 && v.reserveKlaar == 0) {
      herhaald = radio.voegHerhalingBij(sessie, 2);
    }
    spoor?.call('radio-bijvul #$ronde [${r.op ? 'herhaal' : 'buren'}] vooruit≈${v.verwacht.toStringAsFixed(1)}'
        '${v.nood ? ' NOOD' : ''}: ${r.wat}'
        '${herkanst > 0 ? ' · $herkanst opnieuw geprobeerd' : ''}'
        '${herhaald > 0 ? ' · $herhaald herhaald' : ''}');
    // Alleen zeggen wat er werkelijk gebeurt: herhaald → zeggen; iets nieuws → weer gewoon.
    if (herhaald > 0) {
      radio.zetBijvulStand('Herhaalt nummers van eerder in deze radio tot er iets nieuws is');
    } else if (n > 0 || v.verwacht < 3) {
      // Iets nieuws, of het werd krap en er viel niets te herhalen: dan zegt het scherm weer gewoon
      // dat hij zoekt, en niet nog steeds dat hij herhaalt.
      radio.zetBijvulStand(null);
    }
    return n + herhaald;
  }

  static String _uur(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// [op]: alle bronartiesten zijn leeg (alles gehaald en aangeboden).
  Future<({int nieuw, String wat, bool op})> _buren(int sessie, int ronde) async {
    final bronnen = await this.bronnen();
    if (bronnen.isEmpty) return (nieuw: 0, wat: 'geen bronartiesten (Deezer gaf niets)', op: false);
    final sinds = _opSinds;
    if (sinds != null) {
      if (_klok().difference(sinds) < kTrapHerstel) {
        return (nieuw: 0, wat: 'de buurt is op (opnieuw bekeken om ${_uur(sinds.add(kTrapHerstel))})', op: true);
      }
      // Een half uur later: wat toen aangeboden maar niet genomen werd (het plafond was vol), mag nu
      // opnieuw. Wat al in het plan staat, houdt [nieuweNakomers] tegen.
      _opSinds = null;
      _aangeboden.clear();
    }
    final telling = <String, int>{};
    for (final a in artiestenVoorPlafond(radio.plan, voorbijteller: radio.voorbijteller)) {
      final k = artiestSleutel(a);
      telling[k] = (telling[k] ?? 0) + 1;
    }
    final weert = steedsGeweigerd(radio.plan);
    // Wie onder het plafond zit en nog nummers heeft; wie het minst in de radio zit eerst, bij
    // gelijkstand het toeval — anders zijn het elke ronde dezelfde acht.
    final kandidaten = [
      for (final b in bronnen)
        if (!weert.contains(artiestSleutel(b.naam)) &&
            (telling[artiestSleutel(b.naam)] ?? 0) < kMaxPerArtiest &&
            !_leeg(b.id))
          b
    ]..shuffle(_toeval);
    kandidaten.sort((a, b) =>
        (telling[artiestSleutel(a.naam)] ?? 0).compareTo(telling[artiestSleutel(b.naam)] ?? 0));
    final gekozen = kandidaten.take(kArtiestenPerRonde).toList();
    final inPlan = {for (final p in radio.plan) _sleutel(p.artiest, p.titel)};
    final recs = <RecTrack>[];
    for (final b in gekozen) {
      recs.addAll(await _volgendeVan(b, kMaxPerArtiest - (telling[artiestSleutel(b.naam)] ?? 0), inPlan));
      if (sessie != radio.sessie || ronde != radio.bijvulRonde) return (nieuw: 0, wat: 'ingehaald', op: false);
    }
    final halen = <Radioplek>[];
    final eigen = <Radioplek>[];
    if (recs.isNotEmpty) {
      final plekken = maakPlan(recs);
      halen.addAll([for (final p in plekken) if (p.eigen == null) p]);
      eigen.addAll(nieuweNakomers(radio.plan, [for (final p in plekken) if (p.eigen != null) p]));
    }
    // Achteraan: dit is aanvulling, en mag de startlijst niet verdringen — zie [RadioBesturing.voegBij].
    final n = radio.voegBij(sessie, halen, ronde: ronde, achteraan: true);
    if (eigen.isNotEmpty) unawaited(_keurEnVoegBij(sessie, eigen));
    final op = bronnen.every((b) => _leeg(b.id) || weert.contains(artiestSleutel(b.naam)));
    if (op) _opSinds = _klok();
    final wat = gekozen.isEmpty
        ? (op ? 'de buurt is op' : 'alle ${bronnen.length} bronartiesten zitten aan hun plafond')
        : '${gekozen.length} artiesten, ${recs.length} voorgesteld → $n te halen'
            '${eigen.isEmpty ? '' : ' + ${eigen.length} van jou (keuring)'}'
            '${op ? ' — de buurt is nu op' : ''}';
    return (nieuw: n + eigen.length, wat: wat, op: op && n + eigen.length == 0);
  }

  /// Heeft artiest [id] niets meer: alle bladen gehaald en alles aangeboden.
  bool _leeg(int id) =>
      _bladenOp.contains(id) &&
      (_toppers[id] ?? const <RecTrack>[]).every((t) => _aangeboden.contains(_sleutel(t.artist, t.title)));

  /// Hoogstens [hoeveel] toppers van [b] die nog niet aangeboden zijn en niet al in het plan staan
  /// ([inPlan]); een volgend blad als het nodig is.
  Future<List<RecTrack>> _volgendeVan(Bronartiest b, int hoeveel, Set<String> inPlan) async {
    final uit = <RecTrack>[];
    while (uit.length < hoeveel) {
      final lijst = _toppers[b.id] ??= [];
      for (final t in lijst) {
        if (uit.length >= hoeveel) break;
        final k = _sleutel(t.artist, t.title);
        if (_aangeboden.add(k) && !inPlan.contains(k)) uit.add(t);
      }
      if (uit.length >= hoeveel || _bladenOp.contains(b.id)) break;
      final vanaf = _volgendBlad[b.id] ?? 0;
      List<RecTrack> blad;
      try {
        blad = await deezer.toppers(b.id, b.naam, kToppersPerBlad, vanaf);
      } catch (_) {
        break;
      }
      _volgendBlad[b.id] = vanaf + kToppersPerBlad;
      // Minder dan gevraagd: meer heeft Deezer van deze artiest niet.
      if (blad.length < kToppersPerBlad) _bladenOp.add(b.id);
      if (blad.isEmpty) break;
      lijst.addAll(blad);
    }
    return uit;
  }

  /// Eigen nummers pas na de keuring — net als bij de start (zie `_voegGekeurdBij` in main.dart).
  /// Zonder ronde: een keuring die langer duurt dan de ronde is geen reden om een goedgekeurd nummer
  /// weg te gooien.
  Future<void> _keurEnVoegBij(int sessie, List<Radioplek> eigen) async {
    for (final p in eigen) {
      if (sessie != radio.sessie || !radio.loopt) return;
      var mag = true;
      final k = keurEigen;
      if (k != null) {
        try {
          mag = await k(p);
        } catch (_) {/* een keuring die stukloopt is geen nee */}
      }
      if (mag) radio.voegBij(sessie, [p], achteraan: true);
    }
  }

  /// De reserve aanvullen met hoogstens [nodig] eigen nummers. Eén tegelijk, los van de rondes.
  Future<void> vulReserve(int sessie, int nodig) async {
    final f = reserveKandidaten;
    if (_reserveBezig || f == null || nodig <= 0) return;
    _reserveBezig = true;
    try {
      final bronnen = await this.bronnen();
      final ankerSleutels = {for (final a in ankers) artiestSleutel(a)}..remove('');
      final sleutels = {...ankerSleutels, for (final b in bronnen) artiestSleutel(b.naam)}..remove('');
      final al = {for (final p in radio.plan) _sleutel(p.artiest, p.titel)};
      // Wat er per artiest al in de reserve staat en nog moet komen.
      final perArtiest = <String, int>{};
      for (final p in radio.plan) {
        if (!p.reserve || p.voorbijOp != null) continue;
        final k = artiestSleutel(p.artiest);
        perArtiest[k] = (perArtiest[k] ?? 0) + 1;
      }
      // Een anker (de zaadartiest) alleen als hij niet net klonk en er niets van hem aankomt: de reserve
      // speelt juist als de rij leeg is, en anders kwam hij zo één op de drie terug in plaats van één op
      // de tien — Sabers klacht over 2 Fabiola (tweede beoordeling van 08-10-2026).
      final ankerBezet = <String>{
        for (final p in radio.plan)
          if (ankerSleutels.contains(artiestSleutel(p.artiest)) &&
              p.stand != Haalstand.mislukt &&
              (p.voorbijOp == null ? !p.reserve : radio.voorbijteller - p.voorbijOp! < 9))
            artiestSleutel(p.artiest)
      };
      final kandidaten = [
        for (final t in f(sleutels))
          if (!al.contains(_sleutel(t.artist, t.title)) &&
              !_reserveGeprobeerd.contains(t.path) &&
              !ankerBezet.contains(artiestSleutel(t.artist)))
            t
      ]..shuffle(_toeval);
      var erbij = 0, geprobeerd = 0;
      for (final t in kandidaten) {
        // Vier keer zoveel proberen als nodig: elke vraag van de keuring staat in de rij van Discogs.
        if (erbij >= nodig || geprobeerd >= nodig * 4) break;
        if (sessie != radio.sessie || !radio.loopt) return;
        final a = artiestSleutel(t.artist);
        if ((perArtiest[a] ?? 0) >= (ankerSleutels.contains(a) ? kReserveAnker : kReservePerArtiest)) continue;
        _reserveGeprobeerd.add(t.path);
        geprobeerd++;
        final p = Radioplek(
          artiest: t.artist,
          titel: t.title,
          seconden: t.duration?.inSeconds,
          eigen: t,
          bron: 'reserve',
          reserve: true,
        );
        var mag = true;
        final k = keurEigen;
        if (k != null) {
          try {
            mag = await k(p);
          } catch (_) {/* geen nee */}
        }
        if (mag) {
          final n = radio.voegReserveBij(sessie, [p]);
          erbij += n;
          if (n > 0) perArtiest[a] = (perArtiest[a] ?? 0) + 1;
        }
      }
      spoor?.call('radio-reserve: $erbij erbij van $geprobeerd gekeurd (${kandidaten.length} kandidaten)');
    } finally {
      _reserveBezig = false;
    }
  }
}
