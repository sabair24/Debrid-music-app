/// Twee platen met dezelfde naam, uit elkaar gehouden op de persing die je zelf aanwees.
///
/// **Waarvoor (Saber, 03-11-2026).** Marc Lavoine heeft twee albums die allebei "Marc Lavoine" heten: 1985 (Discogs-
/// master 95856) en 2001 (master 697091). Op titel zijn dat één tegel, en zo stonden "Elle a les yeux revolver"
/// (vastgezet op 2436536, een cd uit 1987 van de plaat uit 1985) en "J'ai tout oublié" (vastgezet op 1441911, de cd uit
/// 2001) samen op één plaat, met één uid. Zijn keuze: "Vanzelf, op de plaat" — hangen nummers met dezelfde artiest en
/// albumnaam aan verschillende PLATEN, dan krijgt elke plaat vanzelf een eigen tegel met het jaar van die plaat; wat hij
/// zelf samenvoegde blijft samen.
///
/// **Op de vastgezette persing, niet op de tags.** Vanzelf splitsen op het jaartal in de tags mag niet: gemeten op
/// 25-10-2026 hebben 26 van de 892 albums nummers met jaren die twee of meer uiteen liggen, en bijna altijd is dat één
/// plaat met rommelige jaartallen (Off The Wall 1979/1983). Daarvoor is de knop "Scheiden per jaar". Een persing die de
/// gebruiker zelf aanwees is geen gok: Discogs zegt van welke master ze is, MusicBrainz van welke release-group, en
/// twee persingen van dezelfde master blijven dus samen.
///
/// **Liever niet splitsen dan verkeerd.** Is van één vastgezette persing de plaat nog niet bekend, dan blijft alles
/// zoals het was tot dat antwoord er is. En twee platen die niet op hun nummer te vergelijken zijn — een Discogs-master
/// naast een MusicBrainz-groep, of een persing zonder master — heten pas anders als hun jaren minstens twee uiteen
/// liggen. Gemeten in Sabers bibliotheek: Betty's "Come To Me" hangt aan een persing zonder master (2001) en aan master
/// 2918149 (2000), en dat is één plaat.
library;

import 'discogs.dart';
import 'models.dart';
import 'musicbrainz.dart';
import 'settings.dart';

/// Wat er over één vastgezette persing bekend is: de plaat en het jaar van die plaat.
///
/// [plaat] is `master:95856` (Discogs-master), `rg:<uuid>` (MusicBrainz-release-group), of — voor een persing die bij
/// geen van beide hoort — `release:1067694` / `mbrelease:<uuid>`. [jaar] is dat van de PLAAT: 1985 en niet 1987.
class PlaatFeit {
  const PlaatFeit(this.plaat, this.jaar);

  final String plaat;
  final int? jaar;

  /// Een master of een release-group: twee verschillende nummers uit dezelfde bron zijn twee verschillende platen.
  bool get opNummer => plaat.startsWith('master:') || plaat.startsWith('rg:');

  String get _bron => plaat.startsWith('rg:') || plaat.startsWith('mbrelease:') ? 'mb' : 'discogs';

  Map<String, Object> toJson() => {'plaat': plaat, if (jaar != null) 'jaar': jaar!};

  static PlaatFeit? fromJson(Object? j) {
    if (j is! Map) return null;
    final p = j['plaat'];
    if (p is! String || p.isEmpty) return null;
    final jr = j['jaar'];
    return PlaatFeit(p, jr is num && jr > 0 ? jr.toInt() : null);
  }
}

/// Zijn dit dezelfde plaat? Zie de uitleg bovenaan: op nummer waar dat kan, anders pas verschillend bij twee jaar
/// verschil, en een onbekend jaar is "dezelfde".
bool zelfdePlaat(PlaatFeit a, PlaatFeit b) {
  if (a.plaat == b.plaat) return true;
  if (a.opNummer && b.opNummer && a._bron == b._bron) return false;
  final x = a.jaar, y = b.jaar;
  return x == null || y == null || (x - y).abs() <= 1;
}

/// De sleutel van de persing die in een correctie vastgezet staat: `discogs:1441911` of `mb:<uuid>`, of null.
///
/// Dezelfde velden als `LibraryStore.pinnedRelease` en `pinnedMbid` lezen. Staan ze er allebei (een oude
/// regel), dan gaat Discogs voor, net als daar.
String? plaatPin(Map<String, String>? correctie) {
  final release = int.tryParse(correctie?['release'] ?? '');
  if (release != null && release > 0) return 'discogs:$release';
  final mbid = correctie?['mbid']?.trim() ?? '';
  return mbid.isEmpty ? null : 'mb:$mbid';
}

/// Eén tegel na het scheiden: één plaat (of een paar persingen die dezelfde plaat bleken).
class PlaatGroep {
  PlaatGroep(this.sleutel, this.jaar);

  /// De plaat waar de meeste vastgezette nummers aan hangen ([PlaatFeit.plaat]).
  final String sleutel;
  int? jaar;

  /// Wat er onder de tegel staat, en waar het id van de tegel op een toestel van afhangt ([Album.edition]).
  String editie = '';
  final List<Track> leden = [];
  int _vastgezet = 0;
}

/// Hoe één artiest+titel over platen verdeeld wordt.
class PlaatIndeling {
  PlaatIndeling(this.groepen, this.groepVan, this.jaarRecht);

  final Map<String, PlaatGroep> groepen;

  /// Pad → [PlaatGroep.sleutel], voor elk nummer van deze artiest+titel.
  final Map<String, String> groepVan;

  /// Vastgezette nummers waarvan het jaartal in het bestand niet dat van hun plaat is.
  final List<({Track track, int jaar})> jaarRecht;

  PlaatGroep? groepVanNummer(Track t) => groepen[groepVan[t.path]];
}

/// Verdeel de nummers van één artiest+titel over platen, of null als er niets te scheiden valt.
///
/// [onbekend] zijn de persingen waarvan de plaat nog opgezocht moet worden; zolang die er zijn blijft het één tegel.
/// Nummers zonder pin gaan naar de plaat met hun jaartal, anders naar de grootste.
({PlaatIndeling? indeling, Set<String> onbekend}) deelOpPlaat(
  List<Track> tracks, {
  required String? Function(Track) pinVan,
  required PlaatFeit? Function(String pin) feitVan,
}) {
  const niets = (indeling: null, onbekend: <String>{});
  final pinVanPad = <String, String>{};
  for (final t in tracks) {
    final p = pinVan(t);
    if (p != null) pinVanPad[t.path] = p;
  }
  final pins = pinVanPad.values.toSet();
  if (pins.length < 2) return niets;
  final onbekend = {for (final p in pins) if (feitVan(p) == null) p};
  if (onbekend.isNotEmpty) return (indeling: null, onbekend: onbekend);

  final perPlaat = <String, int>{};
  final feitVanPlaat = <String, PlaatFeit>{};
  for (final p in pinVanPad.values) {
    final f = feitVan(p)!;
    perPlaat[f.plaat] = (perPlaat[f.plaat] ?? 0) + 1;
    feitVanPlaat[f.plaat] = f;
  }
  if (perPlaat.length < 2) return niets;

  // De plaat met de meeste nummers eerst, daarna op naam: zo valt een persing altijd onder dezelfde vertegenwoordiger.
  final volgorde = perPlaat.keys.toList()
    ..sort((a, b) {
      final n = perPlaat[b]!.compareTo(perPlaat[a]!);
      return n != 0 ? n : a.compareTo(b);
    });
  final groepen = <PlaatGroep>[];
  final groepVanPlaat = <String, PlaatGroep>{};
  for (final plaat in volgorde) {
    final f = feitVanPlaat[plaat]!;
    PlaatGroep? bij;
    for (final g in groepen) {
      if (zelfdePlaat(f, feitVanPlaat[g.sleutel]!)) {
        bij = g;
        break;
      }
    }
    if (bij == null) {
      bij = PlaatGroep(plaat, f.jaar);
      groepen.add(bij);
    }
    bij.jaar ??= f.jaar;
    groepVanPlaat[plaat] = bij;
  }
  if (groepen.length < 2) return niets;

  final groepVan = <String, String>{};
  void leg(Track t, PlaatGroep g) {
    g.leden.add(t);
    groepVan[t.path] = g.sleutel;
  }

  // Eerst wat vastgezet is, dan wat op jaartal past; de rest pas als bekend is welke plaat de grootste is.
  final rest = <Track>[];
  for (final t in tracks) {
    final pin = pinVanPad[t.path];
    if (pin != null) {
      final g = groepVanPlaat[feitVan(pin)!.plaat]!;
      g._vastgezet++;
      leg(t, g);
      continue;
    }
    final opJaar = t.year == null ? null : groepen.where((g) => g.jaar == t.year).firstOrNull;
    if (opJaar != null) {
      leg(t, opJaar);
    } else {
      rest.add(t);
    }
  }
  if (rest.isNotEmpty) {
    // De grootste: de meeste nummers, dan de meeste vastgezette, dan de oudste plaat. Vast, en niet afhankelijk van de
    // volgorde waarin de nummers binnenkwamen.
    final grootste = [...groepen]..sort((a, b) {
        var n = b.leden.length.compareTo(a.leden.length);
        if (n != 0) return n;
        n = b._vastgezet.compareTo(a._vastgezet);
        if (n != 0) return n;
        n = (a.jaar ?? 99999).compareTo(b.jaar ?? 99999);
        return n != 0 ? n : a.sleutel.compareTo(b.sleutel);
      });
    for (final t in rest) {
      leg(t, grootste.first);
    }
  }

  // De editie is het jaar van de plaat: "1985" en "2001". Alleen als dat jaar niet uniek is (of onbekend) komt het
  // nummer van de plaat erbij — anders kregen twee tegels hetzelfde id, en voegde een toestel ze weer samen.
  for (final g in groepen) {
    final uniek = g.jaar != null && groepen.where((x) => x.jaar == g.jaar).length == 1;
    final id = g.sleutel.substring(g.sleutel.indexOf(':') + 1);
    final kort = id.length > 8 ? id.substring(0, 8) : id;
    g.editie = uniek ? '${g.jaar}' : [if (g.jaar != null) '${g.jaar}', 'plaat $kort'].join(' · ');
  }

  final jaarRecht = <({Track track, int jaar})>[];
  for (final t in tracks) {
    if (!pinVanPad.containsKey(t.path)) continue;
    final j = groepVanPlaat[feitVan(pinVanPad[t.path]!)!.plaat]!.jaar;
    if (j != null && t.year != j) jaarRecht.add((track: t, jaar: j));
  }

  return (
    indeling: PlaatIndeling({for (final g in groepen) g.sleutel: g}, groepVan, jaarRecht),
    onbekend: const <String>{},
  );
}

/// Zoekt de plaat van één persing op ([plaatPin]-sleutel erin, [PlaatFeit] eruit), of null als het niet lukte.
typedef PlaatOpzoeker = Future<PlaatFeit?> Function(String pin);

/// De echte: Discogs voor `discogs:`, MusicBrainz voor `mb:`. Alleen op de pc — die bezit de muziek, en een toestel
/// krijgt de tegels kant-en-klaar met de catalogus. Beide diensten houden zich aan hun eigen wachtrij en schijfcache.
PlaatOpzoeker plaatOpzoekerVoor(AppSettings settings) {
  final discogs = DiscogsService(settings);
  final mb = MusicBrainzService();
  return (pin) async {
    if (pin.startsWith('discogs:')) {
      final id = int.tryParse(pin.substring('discogs:'.length));
      if (id == null || id <= 0) return null;
      final p = await discogs.plaatVan(id);
      if (p == null) return null;
      final master = p.master;
      return PlaatFeit(master != null && master > 0 ? 'master:$master' : 'release:$id', p.jaar);
    }
    if (pin.startsWith('mb:')) {
      final r = await mb.release(pin.substring('mb:'.length));
      if (r == null) return null;
      final rg = r.releaseGroupId?.trim() ?? '';
      return PlaatFeit(rg.isEmpty ? 'mbrelease:${r.mbid}' : 'rg:$rg', r.albumYear ?? r.year);
    }
    return null;
  };
}
