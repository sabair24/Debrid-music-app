/// Een AI-lijst natrekken (ai_lijst.dart): bij elk voorgesteld nummer opzoeken of het bestaat, met een hoes, een lengte en
/// een fragment van 30 s — voor er iets gedownload wordt.
///
/// Volgorde: eerst je eigen bibliotheek (dan speelt hij meteen in jouw kwaliteit), dan Deezer, dan iTunes ([elders]).
/// Wat niemand kent, wordt [LijstBron.nergens]: grijs, "niet gevonden, misschien verzonnen", standaard uit de lijst
/// ([pasRegelsToe]). De Soulseek-proef kan hem daarna nog vinden ([LijstBron.soulseek]).
library;

import 'ai_lijst.dart';
import 'radiolijst.dart' show AiNummer;
import 'recommend.dart' show RecTrack;

/// Trekt [nummers] na en vult ze in. [eigenId]: het gedeelde id van dit nummer in je bibliotheek, of null. [trekNa]: per
/// nummer de treffer bij Deezer (en [elders]), op dezelfde plek — zie `RecommendService.trekNa`. [bijVoortgang]: na elk
/// stuk, zodat de lijst zich vult terwijl je kijkt.
Future<void> trekLijstNa(
  List<LijstNummer> nummers, {
  required String? Function(String artiest, String titel) eigenId,
  required Future<List<RecTrack?>> Function(List<AiNummer> lijst, void Function(int klaar, List<RecTrack?> tot) voortgang)
      trekNa,
  void Function()? bijVoortgang,
}) async {
  final open = <LijstNummer>[];
  for (final n in nummers) {
    if (n.bron != LijstBron.bezig) continue;
    final id = eigenId(n.artiest, n.titel);
    if (id != null) {
      n
        ..bron = LijstBron.eigen
        ..eigenId = id;
    } else {
      open.add(n);
    }
  }
  bijVoortgang?.call();
  if (open.isEmpty) return;
  void vul(List<RecTrack?> tot, {required bool klaar}) {
    for (var i = 0; i < open.length && i < tot.length; i++) {
      final t = tot[i];
      final n = open[i];
      if (n.bron != LijstBron.bezig) continue;
      if (t == null) {
        if (klaar) n.bron = LijstBron.nergens;
        continue;
      }
      n
        ..bron = t.deezerId > 0 ? LijstBron.deezer : LijstBron.itunes
        ..hoes = t.cover ?? n.hoes
        ..seconden = t.seconds > 0 ? t.seconds : n.seconden
        ..album = t.album.isNotEmpty ? t.album : n.album
        ..deezerId = t.deezerId
        ..fragment = t.preview ?? n.fragment;
    }
  }

  final uit = await trekNa([for (final n in open) AiNummer(n.artiest, n.titel, jaar: n.jaar)], (klaar, tot) {
    vul(tot, klaar: false);
    bijVoortgang?.call();
  });
  vul(uit, klaar: true);
  bijVoortgang?.call();
}

/// Een index van je bibliotheek voor [trekLijstNa]: artiest + titel (zoals `eigenSleutel`) → gedeeld id.
String? Function(String artiest, String titel) eigenIndex(Iterable<({String artiest, String titel, String id})> bib) {
  final m = <String, String>{};
  for (final t in bib) {
    m.putIfAbsent(LijstNummer(artiest: t.artiest, titel: t.titel).sleutel, () => t.id);
  }
  return (a, t) => m[LijstNummer(artiest: a, titel: t).sleutel];
}
