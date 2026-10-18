/// De toestellen die bij deze pc binnen mogen, met per toestel waar en wanneer het het laatst
/// binnenkwam, en een knop om precies dat ene toestel in te trekken.
///
/// **Waarom dit er moest komen (14-10-2026).** Elk toestel heeft sinds deze versie een sleutel van
/// zichzelf. Dat helpt alleen als je ook kunt zien wélke er zijn en er één kunt weghalen: tot nu toe
/// was de enige hendel "Nieuwe toegangscode", en die sloot alles tegelijk buiten. Een gsm die je
/// kwijt bent, haal je hier weg; de andere toestellen merken niets.
library;

import 'package:flutter/material.dart';

import 'lan/tokens.dart';
import 'tv.dart';
import 'ui/kleuren.dart';

/// "14:02" vandaag, "13-10 22:15" eerder, "nog niet gezien" als er niets is.
String laatstGezienTekst(int? ms, String? via, {DateTime? nu}) {
  if (ms == null || ms <= 0) return 'nog niet gezien';
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  final n = nu ?? DateTime.now();
  String twee(int x) => x.toString().padLeft(2, '0');
  final klok = '${twee(t.hour)}:${twee(t.minute)}';
  final wanneer = t.year == n.year && t.month == n.month && t.day == n.day ? klok : '${twee(t.day)}-${twee(t.month)} $klok';
  return via == null ? 'laatst gezien $wanneer' : 'laatst gezien $wanneer, via $via';
}

class ToestellenLijst extends StatefulWidget {
  const ToestellenLijst({super.key, required this.grants});
  final GrantStore grants;

  @override
  State<ToestellenLijst> createState() => _ToestellenLijstState();
}

class _ToestellenLijstState extends State<ToestellenLijst> {
  @override
  void initState() {
    super.initState();
    // Een nieuw toestel verschijnt meteen, niet pas als je het paneel opnieuw opent.
    widget.grants.nieuweSleutelMelding.addListener(_ververs);
  }

  @override
  void dispose() {
    widget.grants.nieuweSleutelMelding.removeListener(_ververs);
    super.dispose();
  }

  void _ververs() {
    if (mounted) setState(() {});
  }

  Future<void> _trekIn(DeviceGrant g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kPaneel,
        title: Text("'${g.deviceName}' intrekken?", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
          'Dit toestel komt er niet meer in tot je het opnieuw koppelt — thuis via je account, of met de '
          'zes cijfers. Je andere toestellen merken niets.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB54747)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Intrekken'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    widget.grants.revoke(g.deviceId);
    await widget.grants.save();
    _ververs();
  }

  @override
  Widget build(BuildContext context) {
    final rijen = widget.grants.all;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Toestellen (${rijen.length})', style: TextStyle(color: kGedempt, fontSize: 11.5)),
        const SizedBox(height: 4),
        if (rijen.isEmpty)
          Text('Nog geen enkel toestel gekoppeld.', style: TextStyle(color: kGedempt, fontSize: 11.5)),
        for (final g in rijen)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.legacy ? 'Eerder gekoppelde apparaten' : g.deviceName,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        g.legacy
                            ? 'de gedeelde sleutel — intrekken gaat met "Nieuwe toegangscode"'
                            : [
                                if (g.platform.isNotEmpty) g.platform,
                                laatstGezienTekst(g.lastSeenAt, g.lastSeenVia),
                                // Tot elk toestel dit toont, laat je Tailscale staan (plan, uitlevering B).
                                if (g.tlsToken != null) 'versleuteld',
                              ].join(' · '),
                        style: TextStyle(color: kGedempt, fontSize: 11, height: 1.3),
                      ),
                    ],
                  ),
                ),
                if (!g.legacy)
                  TvLabelled(
                    label: 'Intrekken',
                    child: TextButton(
                      onPressed: () => _trekIn(g),
                      style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFE07A7A), textStyle: const TextStyle(fontSize: 12)),
                      child: const Text('Intrekken'),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Telefoon kwijt? Trek hem hier in en wijzig het wachtwoord van je account. Dan kan wie hem vond '
          'er niet meer bij, en je andere toestellen werken gewoon door.',
          style: TextStyle(color: kGedempt, fontSize: 11, height: 1.35),
        ),
      ],
    );
  }
}
