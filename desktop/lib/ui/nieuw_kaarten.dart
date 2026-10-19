/// De twee rijen nieuwe releases op Start, en de kop van hun meer-pagina (Saber, 19-10-2026).
///
/// "Maak de nieuwe releases ook specialer, uitgelicht." Wat hij koos: vooraan één GROTE kaart (grote
/// hoes, titel, datum en een afspeelknop), daarna BREDE kaarten — hoes met de tekst ernaast — twee boven
/// elkaar per kolom, een DATUMLINT op de hoes ('Vandaag', '3 dagen', '6 nov'), een kop met een accent en
/// een teller ('5 nieuw'), en geen extra beweging. De meer-pagina krijgt een vooraf gebakken collage van
/// de nieuwste hoezen als kop.
///
/// Alleen tekenen: wat er gebeurt bij een tik, en waar de hoes vandaan komt, geeft de aanroeper mee.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../tv.dart';
import 'kleuren.dart';
import 'maten.dart';
import 'tegel.dart' show HoesBouwer;
import 'typografie.dart';
import 'vlak.dart' show HoesAchtergrond;

/// Eén kaart, los van wat hij voorstelt (een nummer of een album).
class NieuwKaart {
  const NieuwKaart({
    required this.titel,
    required this.regel2,
    required this.hoes,
    required this.onTap,
    this.regel3,
    this.opschrift,
    this.lint,
    this.bezig = false,
    this.onLang,
    this.onRechts,
    this.onKnop,
    this.knopIcoon = Icons.play_arrow_rounded,
    this.knopTekst = 'Afspelen',
  });

  final String titel, regel2;

  /// De derde regel: "+ 2 remixen", "Lijkt op Dua Lipa", "van Radical Optimism".
  final String? regel3;

  /// Alleen op de grote kaart, boven de titel: "NIEUWE SINGLE · LIJKT OP DUA LIPA".
  final String? opschrift;
  final HoesBouwer hoes;

  /// Het lintje op de hoes ([datumLint] in nieuwe_releases.dart).
  final String? lint;

  /// Wordt het nummer nu opgehaald (op een gsm haalt de pc het eerst)? Dan een ringetje op de hoes.
  final bool bezig;
  final VoidCallback onTap;
  final VoidCallback? onLang;
  final void Function(Offset globaal)? onRechts;

  /// De knop op de grote kaart; null = geen knop.
  final VoidCallback? onKnop;
  final IconData knopIcoon;
  final String knopTekst;
}

/// De maten van de rij, uit de breedte die er is en de tekstschaal van het toestel.
///
/// De kaarthoogte groeit mee met de tekst (drie regels), anders knipt een vergrote tekst de derde regel
/// af. Op een gsm is een kaart zo breed dat de volgende kolom er een stukje naast zichtbaar blijft: zo
/// zie je dat er meer is.
({double kaartB, double kaartH, double grootB, double grootH, double tussen}) nieuwRijMaten(
  double breedte, {
  required bool smal,
  TextScaler schaal = TextScaler.noScaling,
}) {
  const tussen = 10.0;
  // Met speling: Flutter rondt elke regel naar boven af op een hele punt, en de knop op de grote kaart
  // groeit mee met de tekst (bij ×1,3 kwam hij 1 punt te kort, widgettoets 19-10-2026).
  final tekst = schaal.scale(14) * 1.35 + schaal.scale(12.5) * 1.35 + schaal.scale(11.5) * 1.35 + 22;
  final kaartH = math.max(smal ? 72.0 : 80.0, tekst.ceilToDouble());
  final grootH = 2 * kaartH + tussen;
  final kaartB = smal ? (breedte - 2 * kGoot - 40).clamp(240.0, 340.0) : 320.0;
  final grootB = smal ? math.max(kaartB, grootH + 150) : grootH + 230;
  return (kaartB: kaartB, kaartH: kaartH, grootB: grootB, grootH: grootH, tussen: tussen);
}

/// Het lintje linksonder op de hoes.
class DatumLint extends StatelessWidget {
  const DatumLint(this.tekst, {super.key});
  final String tekst;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xCC000000),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(tekst,
            maxLines: 1,
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, height: 1.2)),
      );
}

Widget _hoesMetLint(NieuwKaart k, double maat, double hoek) => SizedBox.square(
      dimension: maat,
      child: Stack(fit: StackFit.expand, children: [
        ClipRRect(borderRadius: BorderRadius.circular(hoek), child: k.hoes(maat)),
        if (k.lint != null) Positioned(left: 4, bottom: 4, child: DatumLint(k.lint!)),
        if (k.bezig)
          Center(
            child: Container(
              width: 34,
              height: 34,
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
              child: const CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
            ),
          ),
      ]),
    );

/// Een brede kaart: de hoes links, drie regels tekst ernaast.
class BredeKaart extends StatelessWidget {
  const BredeKaart(this.k, {super.key, required this.breedte, required this.hoogte});
  final NieuwKaart k;
  final double breedte, hoogte;

  @override
  Widget build(BuildContext context) {
    final hoes = hoogte - 12;
    return Pressable(
      onPressed: k.onTap,
      onLongPress: k.onLang,
      onSecondaryTap: k.onRechts,
      borderRadius: BorderRadius.circular(kHoek12),
      scaleOnFocus: false,
      child: Container(
        width: breedte,
        height: hoogte,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: kPaneel,
          borderRadius: BorderRadius.circular(kHoek12),
          border: Border.all(color: kLijnZacht),
        ),
        child: Row(children: [
          _hoesMetLint(k, hoes, kHoek8),
          const SizedBox(width: kRuimte12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k.titel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kTekst, height: 1.35)),
                Text(k.regel2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: kGedempt, height: 1.35)),
                if (k.regel3 != null)
                  Text(k.regel3!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: kGedempt, height: 1.35)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// De grote kaart vooraan: grote hoes, het opschrift, de titel, de artiest en een knop.
class GroteKaart extends StatelessWidget {
  const GroteKaart(this.k, {super.key, required this.breedte, required this.hoogte});
  final NieuwKaart k;
  final double breedte, hoogte;

  @override
  Widget build(BuildContext context) {
    final hoes = hoogte - 16;
    return Pressable(
      onPressed: k.onTap,
      onLongPress: k.onLang,
      onSecondaryTap: k.onRechts,
      borderRadius: BorderRadius.circular(kHoek18),
      scaleOnFocus: false,
      child: Container(
        width: breedte,
        height: hoogte,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kHoek18),
          border: Border.all(color: kAccent.withValues(alpha: .35)),
          // Een zweem van het accent: zo leest hij als de uitgelichte, zonder iets dat beweegt of per
          // beeld rekent.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kAccent.withValues(alpha: .22), kPaneel],
          ),
        ),
        child: Row(children: [
          _hoesMetLint(k, hoes, kHoek12),
          const SizedBox(width: kRuimte16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Eén regel, en de derde regel alleen zonder knop: met alles erop liep de kaart 24
                // punten over (widgettoets op 360 en 411, 19-10-2026).
                if (k.opschrift != null)
                  Text(k.opschrift!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: kAccent2, height: 1.3)),
                const SizedBox(height: kRuimte4),
                Text(k.titel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kTekst, height: 1.2)),
                const SizedBox(height: kRuimte2),
                Text(k.regel2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: kGedempt, height: 1.35)),
                if (k.regel3 != null && k.onKnop == null)
                  Text(k.regel3!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: kGedempt, height: 1.35)),
                if (k.onKnop != null) ...[
                  const SizedBox(height: kRuimte8),
                  FilledButton.icon(
                    onPressed: k.onKnop,
                    icon: Icon(k.knopIcoon, size: 18),
                    label: Text(k.knopTekst),
                    style: FilledButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// De kop boven een rij: een ster in het accent, de titel, "5 nieuw", en rechts "Alles (124) ›".
class NieuwKop extends StatelessWidget {
  const NieuwKop(this.titel, {super.key, required this.totaal, this.nieuw = 0, this.onAlles});
  final String titel;
  final int totaal, nieuw;
  final VoidCallback? onAlles;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(kGoot, kRuimte24, kGoot - kRuimte8, kRuimte12),
        // De titel en de teller in één Expanded, zodat "Alles" echt rechts staat. Met een Flexible en
        // een Spacer naast elkaar kregen die twee elk de helft van de ruimte, en stond "Alles (7)"
        // midden op een breed scherm (pc, 19-10-2026).
        child: Row(children: [
          Text('✦', style: TextStyle(fontSize: 18, color: kAccent, height: 1)),
          const SizedBox(width: kRuimte8),
          Expanded(
            child: Row(children: [
              Flexible(child: Text(titel, maxLines: 1, overflow: TextOverflow.ellipsis, style: kKopKlein)),
              if (nieuw > 0) ...[
                const SizedBox(width: kRuimte8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: kAccent.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(kHoekRond),
                  ),
                  child: Text('$nieuw nieuw',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kAccent)),
                ),
              ],
            ]),
          ),
          if (onAlles != null && totaal > 0)
            TextButton(
              onPressed: onAlles,
              style: TextButton.styleFrom(foregroundColor: kGedempt, visualDensity: VisualDensity.compact),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Alles ($totaal)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ]),
            ),
        ]),
      );
}

/// De rij zelf: vooraan de grote kaart, daarna kolommen van twee brede kaarten.
///
/// [aantal] telt de grote kaart mee. [kaart] bouwt kaart i (1 tot [aantal]), [groot] de eerste.
class NieuwRij extends StatelessWidget {
  const NieuwRij({super.key, required this.aantal, required this.kaart, required this.groot});
  final int aantal;
  final NieuwKaart Function(int i) kaart;
  final NieuwKaart Function() groot;

  /// Hoe hoog de rij is: twee kaarten en de ruimte ertussen, plus wat lucht voor de focusring.
  static double hoogte(BuildContext context, {required bool smal}) {
    final m = nieuwRijMaten(MediaQuery.sizeOf(context).width, smal: smal, schaal: MediaQuery.textScalerOf(context));
    return m.grootH + 8;
  }

  @override
  Widget build(BuildContext context) {
    final smal = isCompact(context);
    final m = nieuwRijMaten(MediaQuery.sizeOf(context).width, smal: smal, schaal: MediaQuery.textScalerOf(context));
    final kolommen = aantal <= 1 ? 1 : 1 + ((aantal - 1) + 1) ~/ 2;
    return SizedBox(
      height: m.grootH + 8,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(kGoot, 4, kGoot, 4),
        itemCount: kolommen,
        separatorBuilder: (_, __) => SizedBox(width: m.tussen),
        itemBuilder: (_, kolom) {
          if (kolom == 0) return GroteKaart(groot(), breedte: m.grootB, hoogte: m.grootH);
          final eerste = 1 + 2 * (kolom - 1);
          return Column(children: [
            BredeKaart(kaart(eerste), breedte: m.kaartB, hoogte: m.kaartH),
            SizedBox(height: m.tussen),
            if (eerste + 1 < aantal)
              BredeKaart(kaart(eerste + 1), breedte: m.kaartB, hoogte: m.kaartH)
            else
              SizedBox(width: m.kaartB, height: m.kaartH),
          ]);
        },
      ),
    );
  }
}

/// De kop van een meer-pagina: een collage van de nieuwste hoezen, één keer gebakken en vervaagd
/// ([HoesAchtergrond]). Kost bij het scrollen niets: het is één beeld.
class HoesCollage extends StatefulWidget {
  const HoesCollage({super.key, required this.urls, required this.hoogte, this.rol});
  final List<String> urls;
  final double hoogte;
  final ScrollController? rol;

  /// Hoeveel hoezen er hoogstens in de collage gaan: twee rijen van vier.
  static const max = 8;

  @override
  State<HoesCollage> createState() => _HoesCollageState();
}

class _HoesCollageState extends State<HoesCollage> {
  Uint8List? _png;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_maak());
    });
  }

  Future<ui.Image?> _laad(String url) {
    final klaar = Completer<ui.Image?>();
    final stroom = ResizeImage(NetworkImage(url), width: 96).resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (!klaar.isCompleted) klaar.complete(info.image.clone());
      info.dispose();
      stroom.removeListener(l);
    }, onError: (_, __) {
      if (!klaar.isCompleted) klaar.complete(null);
      stroom.removeListener(l);
    });
    stroom.addListener(l);
    return klaar.future.timeout(const Duration(seconds: 8), onTimeout: () => null);
  }

  Future<void> _maak() async {
    final urls = widget.urls.take(HoesCollage.max).toList();
    if (urls.isEmpty) return;
    final beelden = [for (final u in urls) await _laad(u)].whereType<ui.Image>().toList();
    if (beelden.isEmpty || !mounted) {
      for (final b in beelden) {
        b.dispose();
      }
      return;
    }
    const vak = 96.0;
    final kolommen = math.min(4, beelden.length);
    final rijen = (beelden.length / kolommen).ceil();
    final opnemer = ui.PictureRecorder();
    final c = Canvas(opnemer);
    for (final (i, b) in beelden.indexed) {
      final rect = Rect.fromLTWH((i % kolommen) * vak, (i ~/ kolommen) * vak, vak, vak);
      paintImage(canvas: c, rect: rect, image: b, fit: BoxFit.cover, filterQuality: FilterQuality.low);
    }
    final beeld = await opnemer.endRecording().toImage((kolommen * vak).toInt(), (rijen * vak).toInt());
    final bytes = await beeld.toByteData(format: ui.ImageByteFormat.png);
    beeld.dispose();
    for (final b in beelden) {
      b.dispose();
    }
    if (!mounted || bytes == null) return;
    setState(() => _png = bytes.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final png = _png;
    if (png == null) return SizedBox(height: widget.hoogte);
    return HoesAchtergrond(beeld: MemoryImage(png), hoogte: widget.hoogte, rol: widget.rol);
  }
}
