/// Het dataverbruik in Instellingen › Info (Saber, 27-10-2026: *"ik wil bij instellingen, sectie info wat men data
/// verbruik is"*).
///
/// Op een toestel: wat Android voor deze app telt, mobiel en wifi, vandaag en deze maand — en waar het heen ging
/// (dataverbruik.dart). Op de pc: wat hij vandaag naar je toestellen stuurde, thuis, via Tailscale en van buiten
/// (lan/verzendteller.dart). Alleen tekst, die mag afbreken: niets wordt afgekapt, ook niet op een smal scherm of de tv.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../dataverbruik.dart';
import '../lan/verzendteller.dart';
import 'kleuren.dart';

/// Hoe een soort heet op het scherm.
String soortNaam(String s) => switch (s) {
      'muziek' => 'muziek',
      'hoezen' => 'hoezen',
      'catalogus' => 'catalogus',
      'zones' => 'zones en wachtrij',
      'pc' => 'de pc',
      'buiten' => 'internet',
      'ongeteld' => 'ongeteld',
      _ => s,
    };

/// "muziek 380 MB · hoezen 12 MB · …" voor [net] op [d], van groot naar klein. Leeg als er niets is.
String verdelingZin(Verbruiksdag d, String net) {
  final m = d.per[net] ?? const <String, int>{};
  final delen = m.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
  return delen.map((e) => '${soortNaam(e.key)} ${bytesZin(e.value)}').join(' · ');
}

class DataverbruikInfo extends StatefulWidget {
  const DataverbruikInfo({super.key, required this.store, required this.isPc});

  /// Null op de pc.
  final DataverbruikStore? store;
  final bool isPc;

  @override
  State<DataverbruikInfo> createState() => _DataverbruikInfoState();
}

class _DataverbruikInfoState extends State<DataverbruikInfo> {
  Androidverbruik? _vandaag, _maand;
  bool _perDag = false;
  Timer? _klok;

  @override
  void initState() {
    super.initState();
    widget.store?.addListener(_ververs);
    if (!widget.isPc) {
      unawaited(_laadAndroid());
      _klok = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_laadAndroid()));
    }
  }

  @override
  void dispose() {
    widget.store?.removeListener(_ververs);
    _klok?.cancel();
    super.dispose();
  }

  void _ververs() {
    if (mounted) setState(() {});
  }

  Future<void> _laadAndroid() async {
    final nu = DateTime.now();
    final v = await androidVerbruik(DateTime(nu.year, nu.month, nu.day), nu);
    final m = await androidVerbruik(DateTime(nu.year, nu.month), nu);
    if (!mounted) return;
    setState(() {
      _vandaag = v;
      _maand = m;
    });
  }

  @override
  Widget build(BuildContext context) {
    final klein = TextStyle(color: kGedempt, fontSize: 11.5, height: 1.4);
    final gewoon = TextStyle(color: kTekst, fontSize: 12.5, height: 1.4);
    final kop = TextStyle(color: kTekst, fontSize: 13, fontWeight: FontWeight.w700);
    if (widget.isPc) return _pc(kop, gewoon, klein);
    final s = widget.store;
    final nu = DateTime.now();
    final vandaag = s?.dag(nu) ?? Verbruiksdag();
    final maand = s?.maand(nu) ?? Verbruiksdag();
    final regels = <Widget>[];
    final v = _vandaag, m = _maand;
    if (v != null && m != null) {
      regels
        ..add(Text('Mobiel: vandaag ${bytesZin(v.mobiel)} · deze maand ${bytesZin(m.mobiel)}', style: gewoon))
        ..add(Text('Wifi: vandaag ${bytesZin(v.wifi)} · deze maand ${bytesZin(m.wifi)}', style: gewoon))
        ..add(Text('Zoals Android het telt voor deze app (alles: muziek, hoezen, de rest).', style: klein));
    } else {
      final mob = vandaag.geteld('mobiel') + vandaag.van('mobiel', 'ongeteld');
      final wifi = vandaag.geteld('wifi') + vandaag.van('wifi', 'ongeteld');
      regels.add(Text('Vandaag: mobiel ${bytesZin(mob)} · wifi ${bytesZin(wifi)} (door de app geteld)', style: gewoon));
    }
    final mobVandaag = verdelingZin(vandaag, 'mobiel'), mobMaand = verdelingZin(maand, 'mobiel');
    regels.add(const SizedBox(height: 4));
    regels.add(Text(
        mobVandaag.isEmpty ? 'Vandaag nog niets over mobiel.' : 'Vandaag over mobiel: $mobVandaag',
        style: klein));
    if (mobMaand.isNotEmpty) regels.add(Text('Deze maand over mobiel: $mobMaand', style: klein));
    final cacheVandaag = vandaag.geteld('cache'), cacheMaand = maand.geteld('cache');
    if (cacheMaand > 0) {
      regels.add(Text(
          'Uit de cache op dit toestel (niet opnieuw gehaald): vandaag ${bytesZin(cacheVandaag)} · deze maand '
          '${bytesZin(cacheMaand)}',
          style: klein));
    }
    final dagen = (s?.dagen.toList() ?? <String>[])..sort((a, b) => b.compareTo(a));
    if (dagen.isNotEmpty) {
      regels.add(Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => setState(() => _perDag = !_perDag),
          child: Text(_perDag ? 'Per dag verbergen' : 'Per dag'),
        ),
      ));
      if (_perDag) {
        for (final d in dagen.take(31)) {
          final dag = s!.dag(DateTime.parse(d));
          final mob = dag.geteld('mobiel') + dag.van('mobiel', 'ongeteld');
          final wifi = dag.geteld('wifi') + dag.van('wifi', 'ongeteld');
          final verdeling = verdelingZin(dag, 'mobiel');
          regels.add(Text(
              '${d.substring(8)}-${d.substring(5, 7)}  mobiel ${bytesZin(mob)} · wifi ${bytesZin(wifi)}'
              '${verdeling.isEmpty ? '' : '\n      $verdeling'}',
              style: klein));
        }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Dataverbruik', style: kop),
      const SizedBox(height: 4),
      ...regels,
    ]);
  }

  Widget _pc(TextStyle kop, TextStyle gewoon, TextStyle klein) {
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: Verzendteller.vandaag,
      builder: (context, m, _) {
        String weg(String w) {
          final delen = [
            for (final e in m.entries)
              if (e.key.startsWith('$w|') && e.value > 0) MapEntry(e.key.substring(w.length + 1), e.value),
          ]..sort((a, b) => b.value.compareTo(a.value));
          final som = delen.fold(0, (a, b) => a + b.value);
          return som == 0 ? '' : '${bytesZin(som)} — ${delen.map((e) => '${soortNaam(e.key)} ${bytesZin(e.value)}').join(' · ')}';
        }

        final buiten = weg('buiten'), tailscale = weg('tailscale'), thuis = weg('thuis');
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Dataverbruik', style: kop),
          const SizedBox(height: 4),
          Text('Wat deze pc vandaag naar je toestellen stuurde:', style: gewoon),
          Text('Buitenshuis (via de versleutelde deur): ${buiten.isEmpty ? 'niets' : buiten}', style: klein),
          Text('Via Tailscale: ${tailscale.isEmpty ? 'niets' : tailscale}', style: klein),
          Text('Thuis: ${thuis.isEmpty ? 'niets' : thuis}', style: klein),
          Text('Elk nummer en elk kwartier staan in verbruik.log; je gsm telt zijn eigen verbruik bij Info.', style: klein),
        ]);
      },
    );
  }
}
