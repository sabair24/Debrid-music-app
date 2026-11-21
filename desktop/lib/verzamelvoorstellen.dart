/// De voorstellen van de AI voor verzamelingen en voor het rechtzetten van gegevens (`verzamelvraag.dart`), bewaard op
/// de pc en op elk toestel goed te keuren (Saber, 21-11-2026: "Voorstel, ik keur goed").
///
/// **Waar het staat.** Op de pc, in `verzamelvoorstellen.json` in de map van de app: de pc heeft de sleutel en de
/// bestanden. Een toestel vraagt de lijst aan de pc (`/api/verzamelvoorstel`) en zegt daar wat er gebeurde. Het
/// verhuizen zelf gaat langs de gewone weg (`LibraryStore.naarVerzameling`), op elk toestel.
///
/// **Op id, niet op pad.** Een voorstel noemt de nummers op hun gedeelde id: dat blijft hetzelfde na een verhuizing
/// (`lan/ids.dart`), en een toestel kent geen paden van de pc.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'verzamelvraag.dart';

/// Een nummer uit je bibliotheek zoals de voorstellen het zien.
typedef BibNummer = ({String id, String artiest, String titel, String? genre, int? jaar});

/// Eén nummer in een voorstel.
class VoorgesteldNummer {
  const VoorgesteldNummer({
    required this.id,
    required this.artiest,
    required this.titel,
    this.twijfel = false,
    this.opmerking = '',
  });

  final String id;
  final String artiest;
  final String titel;

  /// Twijfel van het model: staat bij goedkeuren níet aangevinkt.
  final bool twijfel;
  final String opmerking;

  Map<String, dynamic> toJson() => {
        'id': id,
        'artiest': artiest,
        'titel': titel,
        if (twijfel) 'twijfel': true,
        if (opmerking.isNotEmpty) 'opmerking': opmerking,
      };

  static VoorgesteldNummer? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return VoorgesteldNummer(
      id: j['id'] as String,
      artiest: '${j['artiest'] ?? ''}',
      titel: '${j['titel'] ?? ''}',
      twijfel: j['twijfel'] == true,
      opmerking: '${j['opmerking'] ?? ''}',
    );
  }
}

/// Wat er met een voorstel gebeurde.
enum VoorstelStand { open, gedaan, weg }

VoorstelStand _stand(Object? s) =>
    VoorstelStand.values.firstWhere((v) => v.name == s, orElse: () => VoorstelStand.open);

/// Eén voorgestelde verzameling.
class VerzamelAiVoorstel {
  VerzamelAiVoorstel({
    required this.id,
    required this.naam,
    required this.waarom,
    required this.nummers,
    this.stand = VoorstelStand.open,
  });

  final String id;
  final String naam;
  final String waarom;
  final List<VoorgesteldNummer> nummers;
  VoorstelStand stand;

  Map<String, dynamic> toJson() => {
        'id': id,
        'naam': naam,
        'waarom': waarom,
        'nummers': [for (final n in nummers) n.toJson()],
        'stand': stand.name,
      };

  static VerzamelAiVoorstel? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['naam'] is! String) return null;
    return VerzamelAiVoorstel(
      id: j['id'] as String,
      naam: j['naam'] as String,
      waarom: '${j['waarom'] ?? ''}',
      nummers: [
        for (final n in (j['nummers'] is List ? j['nummers'] as List : const []))
          if (VoorgesteldNummer.fromJson(n) case final v?) v
      ],
      stand: _stand(j['stand']),
    );
  }
}

/// Eén voorgestelde correctie: [veld] (`genre`, `jaar`, `artiest`) van [van] naar [naar], voor de nummers [ids].
class AiCorrectieVoorstel {
  AiCorrectieVoorstel({
    required this.id,
    required this.artiest,
    required this.titel,
    required this.veld,
    required this.van,
    required this.naar,
    required this.waarom,
    required this.ids,
    this.stand = VoorstelStand.open,
  });

  final String id;
  final String artiest;

  /// Leeg: alle nummers van [artiest].
  final String titel;
  final String veld;
  final String van;
  final String naar;
  final String waarom;
  final List<String> ids;
  VoorstelStand stand;

  /// "genre", "jaar" of "artiest" in een zin: "Genre: Toccara0217 → Jazz".
  String get regel => '${switch (veld) {
        'jaar' => 'Jaar',
        'artiest' => 'Artiest',
        _ => 'Genre',
      }}: ${van.isEmpty ? '(leeg)' : van} → $naar';

  Map<String, dynamic> toJson() => {
        'id': id,
        'artiest': artiest,
        'titel': titel,
        'veld': veld,
        'van': van,
        'naar': naar,
        'waarom': waarom,
        'ids': ids,
        'stand': stand.name,
      };

  static AiCorrectieVoorstel? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['veld'] is! String || j['naar'] is! String) return null;
    return AiCorrectieVoorstel(
      id: j['id'] as String,
      artiest: '${j['artiest'] ?? ''}',
      titel: '${j['titel'] ?? ''}',
      veld: j['veld'] as String,
      van: '${j['van'] ?? ''}',
      naar: j['naar'] as String,
      waarom: '${j['waarom'] ?? ''}',
      ids: [for (final x in (j['ids'] is List ? j['ids'] as List : const [])) '$x'],
      stand: _stand(j['stand']),
    );
  }
}

/// Je bibliotheek per artiest voor de vraag ([verzamelPrompt]): op [vraagSleutel], met de schrijfwijze die het vaakst
/// voorkomt, de drie genres die het vaakst voorkomen, vijf tags ([tagsVan]), de jaren en hoogstens [kTitelsPerArtiest]
/// titels. De artiest met de meeste nummers eerst.
List<VraagArtiest> vraagArtiesten(List<BibNummer> nummers, List<String> Function(String artiest) tagsVan) {
  final per = <String, List<BibNummer>>{};
  for (final n in nummers) {
    if (n.artiest.trim().isEmpty) continue;
    (per[vraagSleutel(n.artiest)] ??= []).add(n);
  }
  List<String> meest(Iterable<String> waarden, int hoeveel) {
    final tel = <String, int>{};
    for (final w in waarden) {
      if (w.trim().isEmpty) continue;
      tel[w.trim()] = (tel[w.trim()] ?? 0) + 1;
    }
    final l = tel.entries.toList()..sort((a, b) => b.value != a.value ? b.value - a.value : a.key.compareTo(b.key));
    return [for (final e in l.take(hoeveel)) e.key];
  }

  final uit = <VraagArtiest>[];
  for (final lijst in per.values) {
    final naam = meest(lijst.map((n) => n.artiest), 1).first;
    final jaren = [for (final n in lijst) if (n.jaar != null && n.jaar! > 0) n.jaar!]..sort();
    final titels = <String>[];
    for (final n in lijst) {
      if (titels.length >= kTitelsPerArtiest) break;
      if (!titels.any((t) => t.toLowerCase() == n.titel.trim().toLowerCase())) titels.add(n.titel.trim());
    }
    uit.add((
      artiest: naam,
      aantal: lijst.length,
      genres: meest([for (final n in lijst) n.genre ?? ''], 3),
      tags: [...tagsVan(naam).take(5)],
      vanJaar: jaren.isEmpty ? null : jaren.first,
      totJaar: jaren.isEmpty ? null : jaren.last,
      titels: titels,
    ));
  }
  uit.sort((a, b) => b.aantal != a.aantal ? b.aantal - a.aantal : a.artiest.compareTo(b.artiest));
  return uit;
}

/// Het uitgelezen antwoord ([leesVerzamelvoorstel]) terug naar nummers van je bibliotheek ([nummers]): elke artiest
/// met al zijn nummers behalve wat bij `nietDeze` staat, en elke correctie met de nummers waar ze over gaat en wat er nu
/// staat. Een correctie die niets verandert of over niets gaat, valt weg.
({List<VerzamelAiVoorstel> voorstellen, List<AiCorrectieVoorstel> correcties}) voorstellenUit(
  ({List<AiVerzameling> verzamelingen, List<AiCorrectie> correcties}) antwoord,
  List<BibNummer> nummers, {
  required int nuMs,
}) {
  final per = <String, List<BibNummer>>{};
  for (final n in nummers) {
    (per[vraagSleutel(n.artiest)] ??= []).add(n);
  }
  String t(String s) => s.trim().toLowerCase();
  final voorstellen = <VerzamelAiVoorstel>[];
  for (final (i, v) in antwoord.verzamelingen.indexed) {
    final lijst = <VoorgesteldNummer>[];
    for (final a in v.artiesten) {
      final niet = {for (final x in a.nietDeze) t(x)};
      for (final n in per[vraagSleutel(a.artiest)] ?? const <BibNummer>[]) {
        if (niet.contains(t(n.titel))) continue;
        lijst.add(VoorgesteldNummer(
            id: n.id, artiest: n.artiest, titel: n.titel, twijfel: a.twijfel, opmerking: a.opmerking));
      }
    }
    if (lijst.isEmpty) continue;
    voorstellen.add(VerzamelAiVoorstel(id: 'v$nuMs-$i', naam: v.naam, waarom: v.waarom, nummers: lijst));
  }
  final correcties = <AiCorrectieVoorstel>[];
  for (final (i, c) in antwoord.correcties.indexed) {
    final raak = [
      for (final n in per[vraagSleutel(c.artiest)] ?? const <BibNummer>[])
        if (c.titel.isEmpty || t(n.titel) == t(c.titel)) n
    ];
    String nu(BibNummer n) => switch (c.veld) {
          'jaar' => n.jaar == null || n.jaar == 0 ? '' : '${n.jaar}',
          'artiest' => n.artiest,
          _ => n.genre ?? '',
        };
    final anders = [for (final n in raak) if (t(nu(n)) != t(c.naar)) n];
    if (anders.isEmpty) continue;
    final van = {for (final n in anders) nu(n)}.join(' / ');
    correcties.add(AiCorrectieVoorstel(
      id: 'c$nuMs-$i',
      artiest: c.artiest,
      titel: c.titel,
      veld: c.veld,
      van: van,
      naar: c.naar,
      waarom: c.waarom,
      ids: [for (final n in anders) n.id],
    ));
  }
  return (voorstellen: voorstellen, correcties: correcties);
}

/// De voorstellen: op de pc uit [bestand], op een toestel van de pc ([viaPc]).
class Verzamelvoorstellen extends ChangeNotifier {
  Verzamelvoorstellen({this.bestand});

  /// Op de pc: waar ze bewaard worden.
  final File? bestand;

  /// Op een toestel: de vraag aan de pc (`/api/verzamelvoorstel`). Null op de pc, of zolang er geen pc is.
  Future<Map<String, dynamic>> Function(Map<String, dynamic> body)? Function()? viaPc;

  List<VerzamelAiVoorstel> voorstellen = [];
  List<AiCorrectieVoorstel> correcties = [];

  /// Wat er nu gebeurt ("Claude deelt je bibliotheek in…"), of null.
  String? bezig;

  /// Wat er de vorige keer misging, of null.
  String? fout;

  /// Wanneer er voor het laatst gevraagd werd.
  int gevraagdMs = 0;

  List<VerzamelAiVoorstel> get open => [for (final v in voorstellen) if (v.stand == VoorstelStand.open) v];
  List<AiCorrectieVoorstel> get openCorrecties => [for (final c in correcties) if (c.stand == VoorstelStand.open) c];

  /// Wat je afwees: die namen stelt het model niet opnieuw voor.
  List<String> get afgewezen => [
        for (final v in voorstellen)
          if (v.stand == VoorstelStand.weg) v.naam
      ];

  Map<String, dynamic> toJson() => {
        'voorstellen': [for (final v in voorstellen) v.toJson()],
        'correcties': [for (final c in correcties) c.toJson()],
        if (bezig != null) 'bezig': bezig,
        if (fout != null) 'fout': fout,
        if (gevraagdMs > 0) 'gevraagdMs': gevraagdMs,
      };

  void _vanJson(Object? j) {
    if (j is! Map) return;
    voorstellen = [
      for (final v in (j['voorstellen'] is List ? j['voorstellen'] as List : const []))
        if (VerzamelAiVoorstel.fromJson(v) case final x?) x
    ];
    correcties = [
      for (final c in (j['correcties'] is List ? j['correcties'] as List : const []))
        if (AiCorrectieVoorstel.fromJson(c) case final x?) x
    ];
    bezig = j['bezig'] is String ? j['bezig'] as String : null;
    fout = j['fout'] is String ? j['fout'] as String : null;
    gevraagdMs = j['gevraagdMs'] is num ? (j['gevraagdMs'] as num).toInt() : 0;
  }

  /// Inlezen: op de pc van schijf, op een toestel van de pc. Stil als het niet lukt.
  Future<void> laad() async {
    final pc = viaPc?.call();
    try {
      if (pc != null) {
        _vanJson(await pc({'op': 'lijst'}));
      } else {
        final f = bestand;
        if (f == null || !await f.exists()) return;
        _vanJson(jsonDecode(await f.readAsString()));
        // "Bezig" overleeft geen herstart: de vraag die liep, is weg.
        bezig = null;
      }
      notifyListeners();
    } catch (_) {/* geen lijst: dan geen voorstellen */}
  }

  Future<void> _bewaar() async {
    final f = bestand;
    if (f == null) return;
    try {
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({...toJson()}..remove('bezig')), flush: true);
      await tmp.rename(f.path);
    } catch (_) {/* volgende keer opnieuw */}
  }

  /// Op de pc: nieuwe voorstellen laten maken door [maak] (de vraag aan het model). Wat nog open stond, maakt plaats
  /// voor de nieuwe; wat je deed of afwees, blijft (zie [afgewezen]). Eén tegelijk.
  Future<void> vraagOpPc(
      Future<({List<VerzamelAiVoorstel> voorstellen, List<AiCorrectieVoorstel> correcties})> Function() maak) async {
    if (bezig != null) return;
    bezig = 'Claude deelt je bibliotheek in…';
    fout = null;
    notifyListeners();
    try {
      final r = await maak();
      voorstellen = [
        for (final v in voorstellen)
          if (v.stand != VoorstelStand.open) v,
        ...r.voorstellen,
      ];
      correcties = [
        for (final c in correcties)
          if (c.stand != VoorstelStand.open) c,
        ...r.correcties,
      ];
      gevraagdMs = DateTime.now().millisecondsSinceEpoch;
      if (r.voorstellen.isEmpty && r.correcties.isEmpty) fout = 'Claude vond niets om apart te zetten of recht te zetten.';
    } catch (e) {
      fout = '$e';
    } finally {
      bezig = null;
      await _bewaar();
      notifyListeners();
    }
  }

  /// Vragen om nieuwe voorstellen: op de pc met [opPc] (zie [vraagOpPc]), op een toestel aan de pc — en dan kijken tot
  /// de pc klaar is.
  Future<void> vraag({Future<void> Function()? opPc, Duration elke = const Duration(seconds: 5)}) async {
    final pc = viaPc?.call();
    if (pc == null) {
      if (opPc != null) await opPc();
      return;
    }
    try {
      final r = await pc({'op': 'vraag'});
      if (r['ok'] != true) {
        fout = '${r['reden'] ?? 'De pc kon Claude niet vragen.'}';
        notifyListeners();
        return;
      }
      bezig = 'Claude deelt je bibliotheek in (op de pc)…';
      fout = null;
      notifyListeners();
      for (var i = 0; i < 120; i++) {
        await Future<void>.delayed(elke);
        _vanJson(await pc({'op': 'lijst'}));
        notifyListeners();
        if (bezig == null) return;
      }
    } catch (e) {
      bezig = null;
      fout = 'Kon de pc niet bereiken: $e';
      notifyListeners();
    }
  }

  /// Zeggen wat er met voorstel of correctie [id] gebeurde.
  Future<void> zet(String id, VoorstelStand stand) async {
    for (final v in voorstellen) {
      if (v.id == id) v.stand = stand;
    }
    for (final c in correcties) {
      if (c.id == id) c.stand = stand;
    }
    notifyListeners();
    final pc = viaPc?.call();
    if (pc != null) {
      try {
        await pc({'op': 'zet', 'id': id, 'stand': stand.name});
      } catch (_) {/* de volgende lijst van de pc zegt hoe het staat */}
      return;
    }
    await _bewaar();
  }

  /// Op de pc: een vraag van een toestel beantwoorden (`/api/verzamelvoorstel`). [opPc] start de vraag aan het model.
  Future<Map<String, dynamic>> beantwoord(Map<String, dynamic> body, {Future<void> Function()? opPc}) async {
    switch ('${body['op'] ?? ''}') {
      case 'lijst':
        return toJson();
      case 'vraag':
        if (opPc == null) return {'ok': false, 'reden': 'Op de pc staat geen AI-sleutel.'};
        unawaited(opPc());
        return {'ok': true};
      case 'zet':
        await zet('${body['id'] ?? ''}', _stand(body['stand']));
        return {'ok': true};
    }
    return {'ok': false, 'reden': 'onbekende vraag'};
  }
}
