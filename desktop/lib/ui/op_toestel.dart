// Wat op dit toestel staat: het merkje in de lijsten en de vraag vóór het weghalen.
//
// Saber, 28-10-2026: "Ik probeerde dit op te slaan op men gsm maar zie niets staan" — het stond er wel, maar
// nergens was te zien wát er stond. En: "als ik de knop offline dus uitschakel (weer online) dan wordt het
// nummer van men gsm gewist e ??" — dat klopte, zonder te vragen.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../audioformaten.dart' show isVerliesvrij;
import '../lan/stroomstand.dart' show losslessExtensie;
import '../models.dart';
import '../offline.dart';
import '../organize.dart' show artistKey, normKey;
import '../toestelmap.dart';
import '../tv.dart';
import 'kleuren.dart';

/// Wat de pagina "Op dit toestel" toont: de nummers en de platen die hier staan, gefilterd op [zoek] en in de gekozen
/// volgorde. Zuiver, zodat het zonder scherm te toetsen is.
///
/// **Waarom (Saber, 29-10-2026).** *"liedjes die ik op men toestel heb opgeslaan moet ik kunnen shuffelen en allemaal
/// spelen kunnen doen, plus ook een zoek functie"*. Gekozen: standaard laatst opgeslagen eerst, te wisselen naar A–Z; een
/// eigen zoekveld dat alleen hier zoekt (titel, artiest, album). Een plaat staat er als er minstens één nummer van hier
/// staat — die helft speelt.
///
/// [opgeslagen]: zoals [OfflineStore.tracks] (nieuwste eerst). [nummerVan]: het nummer in de bibliotheek bij een pad;
/// een nummer dat de bibliotheek (nog) niet kent, valt weg.
({List<Track> nummers, List<Album> albums}) opToestelLijst({
  required List<OfflineTrack> opgeslagen,
  required Track? Function(String pad) nummerVan,
  required List<Album> albums,
  String zoek = '',
  bool az = false,
}) {
  final woorden = normKey(zoek).split(' ').where((w) => w.isNotEmpty).toList();
  bool past(String tekst) {
    if (woorden.isEmpty) return true;
    final k = normKey(tekst);
    return woorden.every(k.contains);
  }

  final wanneer = <String, int>{for (final o in opgeslagen) o.path: o.savedAt.millisecondsSinceEpoch};
  final nummers = [
    for (final o in opgeslagen)
      if (nummerVan(o.path) case final t? when past('${t.title} ${t.artist} ${t.album}')) t,
  ];
  int laatst(Album a) {
    var m = -1;
    for (final t in a.tracks) {
      final w = wanneer[t.path];
      if (w != null && w > m) m = w;
    }
    return m;
  }

  final platen = [
    for (final a in albums)
      if (laatst(a) >= 0 &&
          (past('${a.title} ${a.artist}') ||
              a.tracks.any((t) => wanneer.containsKey(t.path) && past('${t.title} ${t.artist} ${t.album}'))))
        a,
  ];
  if (az) {
    nummers.sort((x, y) {
      final a = artistKey(x.artist).compareTo(artistKey(y.artist));
      if (a != 0) return a;
      final b = normKey(x.album).compareTo(normKey(y.album));
      return b != 0 ? b : x.trackNo.compareTo(y.trackNo);
    });
    platen.sort((x, y) {
      final a = artistKey(x.artist).compareTo(artistKey(y.artist));
      return a != 0 ? a : normKey(x.title).compareTo(normKey(y.title));
    });
  } else {
    platen.sort((x, y) => laatst(y).compareTo(laatst(x)));
  }
  return (nummers: nummers, albums: platen);
}

/// Een klein merkje als ALLE [paden] op dit toestel staan; anders niets. [rond] is de vorm voor op een hoes:
/// een schijfje eronder, zodat het ook op een lichte hoes te zien is.
///
/// Zonder [OfflineStore] in de boom (een toets, de pc die er geen nodig heeft) gewoon niets.
class OpToestelMerk extends StatelessWidget {
  const OpToestelMerk({super.key, required this.paden, this.rond = false, this.nummer});

  final List<String> paden;
  final bool rond;

  /// Het nummer van een rij: staat het hier [onderCd], dan krijgt het merkje een andere kleur en zegt het dat.
  final Track? nummer;

  @override
  Widget build(BuildContext context) {
    final erop = context.select<OfflineStore?, bool>((o) => o != null && paden.isNotEmpty && paden.every(o.has));
    if (!erop) return const SizedBox.shrink();
    final laag = nummer != null && onderCd(nummer!);
    final icoon = Icon(Icons.offline_pin_rounded, size: rond ? 18 : 14, color: laag ? kOnderCd : kAccent2);
    return Tooltip(
      message: laag ? 'Op dit toestel — onder cd-kwaliteit (${nummer!.ext.toUpperCase()}), zo bewaard' : 'Op dit toestel',
      child: rond
          ? DecoratedBox(
              decoration: BoxDecoration(color: kBovenop, shape: BoxShape.circle, boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1)),
              ]),
              child: Padding(padding: const EdgeInsets.all(2), child: icoon),
            )
          : Padding(padding: const EdgeInsets.only(right: 6), child: icoon),
    );
  }
}

/// De kleur van [OpToestelMerk] bij een nummer onder cd-kwaliteit: amber, zoals een waarschuwing die geen fout is.
const kOnderCd = Color(0xFFE0A030);

/// Komt dit nummer onder cd-kwaliteit op dit toestel: verliesgevend (mp3, aac, ogg), of verliesvrij onder 16/44,1?
///
/// Saber, 29-10-2026 (*"plus wat met nummers die geen cd kwaliteit hebben ?"*): gewoon zo opslaan, met een merkje.
/// Omzetten maakt ze niet beter, en een hi-res-nummer komt als cd en is dus niet "onder". Een m4a is ALAC als de kop een
/// diepte noemt, anders AAC.
bool onderCd(Track t) {
  final verliesvrij = t.isFlac || isVerliesvrij(t.ext) || (t.ext == 'm4a' && t.bitsPerSample >= 16);
  if (!verliesvrij) return true;
  return (t.sampleRate > 0 && t.sampleRate < 44100) || (t.bitsPerSample > 0 && t.bitsPerSample < 16);
}

/// "12 nummers · 380 MB" — wat er van dit toestel zou gaan.
String toestelOmvang(int aantal, int bytes) {
  final n = aantal == 1 ? '1 nummer' : '$aantal nummers';
  if (bytes <= 0) return n;
  return '$n · ${toestelMaat(bytes)}';
}

/// "380 MB", "1,2 GB".
String toestelMaat(int bytes) => bytes >= 1000 * 1000 * 1000
    ? '${(bytes / 1e9).toStringAsFixed(1).replaceAll('.', ',')} GB'
    : '${(bytes / 1e6).round()} MB';

/// Hoe groot [nummers] ongeveer worden op dit toestel, in de kwaliteit waarin ze komen.
///
/// [cd]: "Offline bewaren in cd-kwaliteit" (de standaard, Saber 29-10-2026: hi-res wordt cd). Dan gaat een lossless
/// nummer boven 16/44,1 omlaag naar wat 16/44,1 is — de grootte geschaald met de bitstroom, want FLAC drukt beide
/// ongeveer even goed samen. Wat al 16/44,1 of lager is, en lossy (mp3, aac), blijft zoals het is. Zonder bekende grootte:
/// de duur maal ~110 kB/s (FLAC 16/44,1 gemiddeld).
int geschatteOmvang(Iterable<Track> nummers, {required bool cd}) {
  var som = 0;
  for (final t in nummers) {
    var b = t.sizeBytes > 0 ? t.sizeBytes : (t.duration?.inSeconds ?? 0) * 110 * 1000;
    final hoger = t.sampleRate > 44100 || t.bitsPerSample > 16;
    if (cd && hoger && losslessExtensie(t.ext)) {
      final rate = t.sampleRate > 0 ? t.sampleRate : 44100;
      final bits = t.bitsPerSample > 0 ? t.bitsPerSample : 16;
      b = (b * (44100 * 16) / (rate * bits)).round();
    }
    som += b;
  }
  return som;
}

/// Hoeveel ruimte er nog vrij is op dit toestel (bytes), of null als het toestel het niet zegt (pc, tv, een toets).
Future<int?> vrijeRuimteOpToestel() async {
  try {
    final Object? v;
    if (Platform.isAndroid) {
      v = await const MethodChannel('debridmusic/device').invokeMethod<Object>('vrijeRuimte');
    } else if (Platform.isIOS || Platform.isMacOS) {
      v = await const MethodChannel('debridmusic/ruimte').invokeMethod<Object>('vrij');
    } else {
      return null;
    }
    final n = v is num ? v.toInt() : null;
    return n == null || n < 0 ? null : n;
  } catch (_) {
    return null;
  }
}

/// Vraag vóór het opslaan of [aantal] nummers van ongeveer [bytes] op dit toestel mogen, met de vrije ruimte erbij.
/// Waar als het mag. Saber, 29-10-2026: *"voor ik begin met downloaden wil ik ook al zien hoeveel ruimte het zal
/// innemen"*. Is er te weinig ruimte, dan kan Opslaan niet.
///
/// [onderCdAantal]: hoeveel ervan onder cd-kwaliteit zijn ([onderCd]); die komen zoals ze zijn, en dat staat erbij.
Future<bool> vraagOpToestelZetten(BuildContext context,
    {required int aantal, required int bytes, int? vrij, int onderCdAantal = 0}) async {
  final ruimte = vrij ?? await vrijeRuimteOpToestel();
  if (!context.mounted) return false;
  final teVeel = ruimte != null && bytes > ruimte;
  final ja = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Op dit toestel zetten?'),
      content: Text([
        '${aantal == 1 ? '1 nummer' : '$aantal nummers'}, ongeveer ${toestelMaat(bytes)}'
            '${ruimte == null ? '.' : ' — nog ${toestelMaat(ruimte)} vrij op dit toestel.'}',
        if (onderCdAantal > 0)
          '${onderCdAantal == aantal ? (aantal == 1 ? 'Het is' : 'Ze zijn allemaal') : '$onderCdAantal daarvan zijn'} '
              'onder cd-kwaliteit (bv. mp3) en komen zoals ze zijn, met een merkje.',
        if (teVeel) 'Daar is niet genoeg ruimte voor. Maak eerst ruimte vrij, of kies minder.',
      ].join('\n\n')),
      actions: [
        TextButton(
            key: const ValueKey('toestel-op-nee'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
        FilledButton(
            key: const ValueKey('toestel-op-ja'),
            onPressed: teVeel ? null : () => Navigator.pop(ctx, true),
            child: const Text('Opslaan')),
      ],
    ),
  );
  return ja ?? false;
}

/// Vraag of [aantal] nummers ([bytes] groot) van dit toestel mogen. Waar als het mag.
Future<bool> vraagVanToestelHalen(BuildContext context, {required int aantal, required int bytes}) async {
  final ja = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Van dit toestel halen?'),
      content: Text('${toestelOmvang(aantal, bytes)} gaan van dit toestel. Op je pc blijven ze staan, en je kunt '
          'ze later opnieuw bewaren.'),
      actions: [
        TextButton(
            key: const ValueKey('toestel-weg-nee'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
        FilledButton(
            key: const ValueKey('toestel-weg-ja'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Weghalen')),
      ],
    ),
  );
  return ja ?? false;
}

/// Bovenaan "Op dit toestel": de echte map (Saber, 28-10-2026: "ik moet ook direct naar de map kunnen gaan").
///
/// Zonder toestemming (Android) een kaartje dat uitlegt waarvoor; met toestemming waar de map staat en een knop
/// die hem in Bestanden opent. Op de pc en de tv niets: daar is geen map te openen.
class ToestelMapKaart extends StatelessWidget {
  const ToestelMapKaart({super.key});

  @override
  Widget build(BuildContext context) {
    if (isTv || !(Platform.isAndroid || Platform.isIOS)) return const SizedBox.shrink();
    return ValueListenableBuilder<Directory?>(
      valueListenable: openbareMapNu,
      builder: (context, map, _) {
        if (map == null && !Platform.isAndroid) return const SizedBox.shrink();
        final kaart = map == null
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                const Text('Je muziek in een echte map', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    'Muziek › Debrid Music, met dezelfde mappen als op je pc — te zien in Mijn bestanden en in andere '
                    'spelers. Android vraagt daarvoor "Toegang tot alle bestanden"; die zet je zelf aan, op het scherm '
                    'dat nu opengaat.',
                    style: TextStyle(color: kGedempt, fontSize: 12.5, height: 1.4)),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const ValueKey('toestel-toestemming'),
                  icon: const Icon(Icons.folder_rounded, size: 18),
                  label: const Text('Toestemming geven'),
                  onPressed: () => unawaited(vraagOpenbaarBewaren()),
                ),
              ])
            : Row(children: [
                Icon(Icons.folder_open_rounded, color: kAccent2),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(Platform.isIOS ? 'Bestanden › Op mijn iPad › Debrid Music' : 'Muziek › Debrid Music',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
                TextButton.icon(
                  key: const ValueKey('toestel-open-map'),
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  label: const Text('Open in Bestanden'),
                  onPressed: () async {
                    final gelukt = await openInBestanden(map.path);
                    if (!gelukt && context.mounted) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(content: Text('Kon de map niet openen. Hij staat in ${map.path}.')));
                    }
                  },
                ),
              ]);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: kPaneel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kLijn),
            ),
            child: Padding(padding: const EdgeInsets.all(14), child: kaart),
          ),
        );
      },
    );
  }
}
