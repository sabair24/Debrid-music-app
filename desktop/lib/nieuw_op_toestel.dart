// Wat er op de pc binnenkomt, vanzelf op dit toestel (Saber, 02-11-2026: *"ik wil dan ook een liedje die binnenkomt op de
// pc dus, direct lokaal kunnen opslaan op men gsm, ook buitenshuis en automatisch, met limiet van 150 GB"*). Gekozen: nieuwe
// downloads en betere kopieën (die vervangen wat er al staat), geen radionummers; is de grens vol, een waarschuwing met
// "Ruimte maken" en "Limiet verhogen".
//
// **Nieuw** is wat de pc heeft en dit toestel niet kende toen het begon ([BekendOpPc]) — niet de tijd van het bestand: die
// verspringt als de pc een hoes of tags in een oud bestand schrijft, en dan zou de gsm duizenden oude nummers ophalen.
// **Een betere kopie** zie je aan de handtekening van het geluid ([geluidVan]).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'paths.dart';
import 'toestel_redenen.dart';

/// De handtekening van het geluid van [t]: frequentie, diepte, lengte op de ms en het soort bestand. Een hoes of tags erin
/// schrijven verandert hem niet; een andere kopie — een andere rip, een andere master, een opwaardering — bijna altijd wel
/// (de nep-vinyl van Trip on This scheelde 11 ms met de cd).
String geluidVan(Track t) =>
    '${t.sampleRate}/${t.bitsPerSample}/${t.duration?.inMilliseconds ?? 0}/${t.ext.toLowerCase()}';

/// De nummers van de pc ([bibliotheek]) die nieuw zijn: niet [bekend] toen dit toestel begon, niet op proef in een radio
/// ([opProef], het gedeelde id via [idVan]), en geen versie van een ander nummer ([isVersie]). Het nieuwste eerst.
///
/// En het bestand zelf is van na [sindsMs] (min een dag): een oud bestand dat de pc naar een andere map verhuisde (een
/// versie naar "(cd)", 01-11-2026) heeft een nieuw pad, maar houdt zijn tijd — dat is niets nieuws om op te halen.
List<Track> nieuweNummers({
  required List<Track> bibliotheek,
  required Set<String> bekend,
  int sindsMs = 0,
  Set<String> opProef = const {},
  String? Function(String pad)? idVan,
  bool Function(String pad)? isVersie,
}) {
  final uit = [
    for (final t in bibliotheek)
      if (!bekend.contains(t.path) &&
          t.addedMs >= sindsMs - const Duration(days: 1).inMilliseconds &&
          !(isVersie?.call(t.path) ?? false) &&
          !(opProef.isNotEmpty && opProef.contains(idVan?.call(t.path))))
        t,
  ]..sort((a, b) => b.addedMs.compareTo(a.addedMs));
  return uit;
}

/// Wacht een nieuw nummer nog op de pc? De eerste [kKeuringAdem] altijd (de pc keurt wat net landde), daarna zolang hij er
/// nog mee bezig is ([bezig]: een jacht op een betere kopie, 24 bit zoeken), maar nooit langer dan [kKeuringHoogstens].
///
/// **Waarom (Saber, 02-11-2026).** Got My Mind Set On You landde om 09:47 als nep (afgekapt op 16,1 kHz); de gsm haalde
/// hem meteen, 33,7 MB over mobiele data, en een minuut later verving de pc hem door een echte. Gekozen: "Wachten tot de
/// keuring af is", op zijn laatst na 30 minuten.
bool wachtOpDePc({required int toegevoegdMs, required int nuMs, required bool bezig}) {
  final leeftijd = nuMs - toegevoegdMs;
  if (leeftijd < kKeuringAdem.inMilliseconds) return true;
  return bezig && leeftijd < kKeuringHoogstens.inMilliseconds;
}

/// Mag een betere kopie ([geluidVan] veranderde op de pc) nu al naar dit toestel? Thuis op wifi altijd. Onderweg alleen als
/// wat hier staat ([oudGeluid]) echt slecht is: verliesgevend (mp3, aac…) of onder cd-kwaliteit. Een opwaardering naar
/// studiokwaliteit wordt hier toch cd, en dat wacht op wifi thuis.
///
/// **Waarom (Saber, 02-11-2026 → 03-11-2026).** Om 07:16 haalde de gsm bij het vertrek zes betere kopieën (174 MB) over
/// mobiele data: 24/96 van de pc, hier weer 16/44,1, net als wat er al stond. Gekozen: "Pas thuis op wifi".
bool beterNuOphalen({required bool thuisOpWifi, required String? oudGeluid}) {
  if (thuisOpWifi) return true;
  final d = (oudGeluid ?? '').split('/');
  if (d.length < 4) return true;
  final rate = int.tryParse(d[0]) ?? 0, bits = int.tryParse(d[1]) ?? 0;
  if (!_verliesvrij.contains(d[3])) return true;
  return (rate > 0 && rate < 44100) || (bits > 0 && bits < 16);
}

const _verliesvrij = {'flac', 'wav', 'aif', 'aiff', 'ape', 'wv', 'dsf', 'dff'};

const kKeuringAdem = Duration(minutes: 2);
const kKeuringHoogstens = Duration(minutes: 30);

/// Wat er van [nieuw] op dit toestel mag: wat er al om deze reden staat ([al]) blijft altijd; van de rest zoveel als er
/// binnen [grens] bytes past bovenop [bezet], in volgorde. [nietMeer]: hoeveel er niet meer pasten — dan een waarschuwing.
({List<Track> houden, int nietMeer}) binnenGrens({
  required List<Track> nieuw,
  required Set<String> al,
  required int bezet,
  required int grens,
  required int Function(Track t) omvang,
}) {
  final houden = <Track>[];
  var erbij = 0, nietMeer = 0;
  for (final t in nieuw) {
    if (al.contains(t.path)) {
      houden.add(t);
      continue;
    }
    final o = omvang(t);
    if (bezet + erbij + o > grens) {
      nietMeer++;
      continue;
    }
    erbij += o;
    houden.add(t);
  }
  return (houden: houden, nietMeer: nietMeer);
}

/// De paden van de pc die dit toestel al kende toen "vanzelf op dit toestel" begon, plus wat je daarna zelf van het
/// toestel haalde (dat komt niet vanzelf terug). Bewaard in `bekend_op_pc.json`.
class BekendOpPc {
  BekendOpPc({this.bestandsnaam = 'bekend_op_pc.json'});

  final String bestandsnaam;
  final Set<String> _paden = {};
  int? _sinds;
  bool _geladen = false;

  /// Sinds wanneer (ms), of null zolang het nog niet begon.
  int? get sinds => _sinds;

  Set<String> get paden => Set.unmodifiable(_paden);

  File get _bestand => appFile(bestandsnaam);

  Future<void> laad() async {
    if (_geladen) return;
    _geladen = true;
    try {
      final f = _bestand;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      _sinds = (j['sinds'] as num?)?.toInt();
      final l = j['paden'];
      if (l is List) _paden.addAll([for (final p in l) '$p']);
    } catch (e) {
      debugPrint('bekend_op_pc onleesbaar: $e');
    }
  }

  Future<void> _bewaar() async {
    try {
      await _bestand.writeAsString(jsonEncode({'sinds': _sinds, 'paden': _paden.toList()}));
    } catch (e) {
      debugPrint('bekend_op_pc niet bewaard: $e');
    }
  }

  /// De eerste keer: alles wat de pc nu heeft, telt als gekend — alleen wat vanaf nu binnenkomt, gaat vanzelf mee.
  /// Geeft true als het net begon.
  Future<bool> begin(Iterable<Track> bibliotheek, {DateTime? nu}) async {
    await laad();
    if (_sinds != null) return false;
    _sinds = (nu ?? DateTime.now()).millisecondsSinceEpoch;
    _paden.addAll([for (final t in bibliotheek) t.path]);
    await _bewaar();
    return true;
  }

  /// Je haalde [paden] zelf van dit toestel: niet meer vanzelf terug.
  Future<void> voegToe(Iterable<String> paden) async {
    await laad();
    final voor = _paden.length;
    _paden.addAll(paden);
    if (_paden.length != voor) await _bewaar();
  }
}

/// Wat dit toestel al kende ([BekendOpPc]).
final bekendOpPc = BekendOpPc();

/// Dit toestel zit aan zijn grens: zoveel nieuwe nummers kwamen er niet meer vanzelf op ([binnenGrens]), bij [grensGB].
/// [vrijeRuimte]: niet de grens, maar de ruimte op het toestel zelf hield het tegen. Null: alles paste.
final nieuwOpToestelVol = ValueNotifier<({int aantal, int grensGB, bool vrijeRuimte})?>(null);

/// Je haalde [paden] zelf van dit toestel: geen reden meer om ze te houden, en ze komen niet vanzelf terug.
Future<void> zelfVanToestel(Iterable<String> paden) async {
  final l = paden.toList();
  await toestelRedenen.haalWeg(l, kRedenZelf);
  await toestelRedenen.haalWeg(l, kRedenNieuw);
  await bekendOpPc.voegToe(l);
}
