// Wat op dit toestel staat: het merkje in de lijsten en de vraag vóór het weghalen.
//
// Saber, 28-10-2026: "Ik probeerde dit op te slaan op men gsm maar zie niets staan" — het stond er wel, maar
// nergens was te zien wát er stond. En: "als ik de knop offline dus uitschakel (weer online) dan wordt het
// nummer van men gsm gewist e ??" — dat klopte, zonder te vragen.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../offline.dart';
import '../toestelmap.dart';
import '../tv.dart';
import 'kleuren.dart';

/// Een klein merkje als ALLE [paden] op dit toestel staan; anders niets. [rond] is de vorm voor op een hoes:
/// een schijfje eronder, zodat het ook op een lichte hoes te zien is.
///
/// Zonder [OfflineStore] in de boom (een toets, de pc die er geen nodig heeft) gewoon niets.
class OpToestelMerk extends StatelessWidget {
  const OpToestelMerk({super.key, required this.paden, this.rond = false});

  final List<String> paden;
  final bool rond;

  @override
  Widget build(BuildContext context) {
    final erop = context.select<OfflineStore?, bool>((o) => o != null && paden.isNotEmpty && paden.every(o.has));
    if (!erop) return const SizedBox.shrink();
    final icoon = Icon(Icons.offline_pin_rounded, size: rond ? 18 : 14, color: kAccent2);
    return Tooltip(
      message: 'Op dit toestel',
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

/// "12 nummers · 380 MB" — wat er van dit toestel zou gaan.
String toestelOmvang(int aantal, int bytes) {
  final n = aantal == 1 ? '1 nummer' : '$aantal nummers';
  if (bytes <= 0) return n;
  final maat = bytes >= 1000 * 1000 * 1000
      ? '${(bytes / 1e9).toStringAsFixed(1).replaceAll('.', ',')} GB'
      : '${(bytes / 1e6).round()} MB';
  return '$n · $maat';
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
