/// "Test buitenverbinding" op de gsm (stap 8.2 van "verbinden zoals Roon ARC", 14-10-2026).
///
/// Thuis kan je niet zien of de eigen deur van buiten werkt: het publieke adres vanaf je eigen wifi gaat
/// via de modem zelf. Deze proef stuurt daarom een paar verzoeken over **mobiele data**, ook met wifi aan
/// (`Buitenproef.kt`): naar de eigen deur (versleuteld, vastgepind), en naar 47820 en 47822 op hetzelfde
/// publieke adres — die twee moeten zwijgen. Antwoordt er een, dan staat er een deur die er niet hoort.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lan/adreswedloop.dart' show AdresSoort, adresSoort;
import 'lan/client_session.dart';
import 'lan/poorten.dart';
import 'ui/kleuren.dart';

/// De eigen deur naar buiten uit de adressen van een koppeling: https, niet thuis en niet Tailscale.
Uri? publiekeDeur(Iterable<String> adressen) {
  for (final s in adressen) {
    final u = Uri.tryParse(s);
    if (u != null && u.scheme == 'https' && u.host.isNotEmpty && adresSoort(u) == AdresSoort.anders) return u;
  }
  return null;
}

/// Wat de proef naar elk doel probeert.
({String deur, String http, String tls}) buitenDoelen(Uri deur) => (
      deur: deur.replace(path: '/health').toString(),
      http: Uri(scheme: 'http', host: deur.host, port: kHttpPoort, path: '/health').toString(),
      tls: Uri(scheme: 'https', host: deur.host, port: kTlsPoort, path: '/health').toString(),
    );

/// De uitslag in een zin. [rood]: er staat iets open dat dicht hoort, of er antwoordt een vreemde.
({bool gelukt, bool rood, String zin}) buitenUitslag(Map<String, String> uit, ({String deur, String http, String tls}) d) {
  final fout = uit['fout'];
  if (fout == 'geen-mobiel') {
    return (gelukt: false, rood: false, zin: 'Geen mobiele data: zet mobiele data aan en probeer opnieuw.');
  }
  if (fout != null) return (gelukt: false, rood: false, zin: 'De proef kon niet starten ($fout).');
  final open = [
    if ((uit[d.http] ?? 'geen') != 'geen') kHttpPoort,
    if ((uit[d.tls] ?? 'geen') != 'geen') kTlsPoort,
  ];
  if (open.isNotEmpty) {
    return (
      gelukt: false,
      rood: true,
      zin: 'Let op: van buiten antwoordt je pc ook op poort ${open.join(' en ')}. Dat hoort niet — '
          'haal die deur weg in je modem. Alleen de deur van DebridMusic mag open.',
    );
  }
  return switch (uit[d.deur]) {
    'antwoordt' => (
        gelukt: true,
        rood: false,
        zin: 'Gelukt: je pc is van buiten bereikbaar, versleuteld en alleen voor je eigen toestellen. '
            '47820 en 47822 zijn dicht, zoals het hoort.',
      ),
    'ander-certificaat' => (
        gelukt: false,
        rood: true,
        zin: 'Op het publieke adres antwoordt iets met een ander certificaat dan je pc. Klopt de deur in je modem?',
      ),
    _ => (
        gelukt: false,
        rood: false,
        zin: 'Van buiten antwoordt je pc niet. Staat "Bereikbaar van buitenaf" aan op je pc, en zegt die "Aan"?',
      ),
  };
}

/// De knop in de instellingen van een gekoppeld toestel.
class BuitenproefKnop extends StatefulWidget {
  const BuitenproefKnop({super.key, required this.session, this.gedempt});
  final ClientSession session;

  /// De kleur van de uitleg; zonder: een zacht grijs dat op dit thema leest.
  final Color? gedempt;

  @override
  State<BuitenproefKnop> createState() => _BuitenproefKnopState();
}

class _BuitenproefKnopState extends State<BuitenproefKnop> {
  static const _kanaal = MethodChannel('debridmusic/buiten');
  bool _bezig = false;
  ({bool gelukt, bool rood, String zin})? _uitslag;

  Future<void> _proef() async {
    final e = widget.session.endpoint;
    final deur = e == null ? null : publiekeDeur([e.baseUrl.toString(), ...e.uitwijk]);
    if (e == null || deur == null || e.pin.isEmpty) {
      setState(() => _uitslag = (
            gelukt: false,
            rood: false,
            // Niet "zet het aan": het kan ook aanstaan terwijl de modem de deur weigert (25-10-2026: UPnP van de
            // modem vastgelopen, en de gsm zei een dag lang dat het aan moest). Wat er mis is, staat op de pc.
            zin: 'Je gsm kent nog geen deur naar buiten van je pc. Staat "Bereikbaar van buitenaf" aan op je pc, '
                'dan staat daar waarom de deur niet lukt (soms moet de modem herstart). Verbind daarna één keer '
                'thuis. Tot dan werkt Tailscale.',
          ));
      return;
    }
    setState(() {
      _bezig = true;
      _uitslag = null;
    });
    final d = buitenDoelen(deur);
    Map<String, String> uit;
    try {
      final r = await _kanaal.invokeMapMethod<String, String>('proef', {
        'doelen': [d.deur, d.http, d.tls],
        'pin': e.pin,
      });
      uit = r ?? const {'fout': 'geen antwoord'};
    } catch (x) {
      uit = {'fout': '$x'};
    }
    final u = buitenUitslag(uit, d);
    ClientSession.logRegel('buitenproef: ${uit.entries.map((x) => '${Uri.tryParse(x.key)?.port ?? x.key}=${x.value}').join(', ')}'
        ' → ${u.gelukt ? 'GELUKT' : (u.rood ? 'ROOD' : 'niet gelukt')}');
    if (!mounted) return;
    setState(() {
      _bezig = false;
      _uitslag = u;
    });
  }

  @override
  Widget build(BuildContext context) {
    final u = _uitslag;
    final alleenMobiel = Platform.isAndroid;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      OutlinedButton.icon(
        onPressed: !alleenMobiel || _bezig ? null : _proef,
        icon: _bezig
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.public, size: 18),
        label: Text(_bezig ? 'Bezig over mobiele data…' : 'Test buitenverbinding'),
      ),
      const SizedBox(height: 6),
      Text(
        alleenMobiel
            ? 'Probeert je pc over mobiele data, zoals onderweg, ook als je thuis op wifi zit. Onderweg kost '
                'luisteren ongeveer 1,4 GB per uur in 24/96, en 0,4 GB per uur in cd-kwaliteit.'
            : 'Kan alleen op een toestel met mobiele data.',
        style: TextStyle(color: widget.gedempt ?? leesbaar(const Color(0xFF8A8F98)), fontSize: 12, height: 1.4),
      ),
      if (u != null) ...[
        const SizedBox(height: 6),
        Text(u.zin,
            style: TextStyle(
                color: u.rood
                    ? leesbaar(const Color(0xFFFF6B6B))
                    : (u.gelukt ? leesbaar(const Color(0xFF6BD49A)) : leesbaar(const Color(0xFFFFB454))),
                fontSize: 12.5,
                height: 1.4)),
      ],
    ]);
  }
}
