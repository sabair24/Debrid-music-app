// Wat op dit toestel staat: het merkje in de lijsten en de vraag vóór het weghalen.
//
// Saber, 28-10-2026: "Ik probeerde dit op te slaan op men gsm maar zie niets staan" — het stond er wel, maar
// nergens was te zien wát er stond. En: "als ik de knop offline dus uitschakel (weer online) dan wordt het
// nummer van men gsm gewist e ??" — dat klopte, zonder te vragen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../offline.dart';
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
