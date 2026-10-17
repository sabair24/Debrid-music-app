// "Kop aanpassen": de kop van een artiestpagina zelf uitsnijden, per soort scherm.
//
// Saber, 17-10-2026, in vier antwoorden: de hero "volle breedte, slim uitgesneden, maar ik kan nog
// aanpassen, zelf de hero van hoogte veranderen, bijknippen, in en uit zoomen" — op pc, Mac en iPad,
// "rechtstreeks op de foto" (slepen, scrollen of knijpen om te zoomen, de onderrand slepen voor de
// hoogte, Opslaan en Herstel), "alles per toestel apart", en "op de pc kiezen voor welk scherm" met een
// kader in de vorm van dat scherm.
//
// Wat je hier ziet is dezelfde som als de echte kop ([KopFoto.plekVoor]), in een kader met de maat van
// dat scherm: wat je instelt is wat je daarna op dat toestel ziet.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';

import '../beeldvorm.dart';
import 'kleuren.dart';
import 'kopfoto.dart';

/// Hoe groot de kop op elk soort scherm is, in punten — het kader waarin je hem instelt. [balk] is
/// het stuk achter de zwevende balk (de foto loopt erachter door, het brandpunt hoort eronder).
///
/// Gemeten in de echte app: een tv is 960 breed en de kop 360 + 75 (zie `kTvKopZicht`); op de pc is
/// de kop op een venster van 1440 zo'n 700 hoog met de balk van 64 erboven; een gsm is 411 breed en de
/// kop daar ongeveer 520.
///
/// Een iPad rechtop: 834 breed, de kop gemeten op zo'n 740 hoog (zie `beeldvorm.dart`), met de
/// zwevende balk en de statusbalk (64 + 24) erboven.
({Size maat, double balk, bool smal}) kopKader(KopScherm s) => switch (s) {
      KopScherm.pc => (maat: const Size(1440, 700), balk: 64, smal: false),
      KopScherm.tv => (maat: const Size(960, 435), balk: 75, smal: false),
      KopScherm.gsm => (maat: const Size(411, 520), balk: 0, smal: true),
      KopScherm.staand => (maat: const Size(834, 828), balk: 88, smal: false),
    };

String kopSchermNaam(KopScherm s) => switch (s) {
      KopScherm.pc => 'Pc · Mac · iPad',
      KopScherm.tv => 'Tv',
      KopScherm.gsm => 'Gsm',
      KopScherm.staand => 'iPad rechtop',
    };

/// De bewerker. [huidig] is wat er per scherm bewaard is (null = de app kiest zelf); [bewaar] krijgt
/// per veranderd scherm de nieuwe instelling (null = weer zelf laten kiezen).
class KopBewerker extends StatefulWidget {
  const KopBewerker({
    super.key,
    required this.naam,
    required this.beeld,
    required this.huidig,
    required this.bewaar,
    this.begin = KopScherm.pc,
    this.bronMaat,
  });

  final String naam;
  final Uint8List beeld;

  /// De maat uit de kop van het bestand, voor zolang de foto nog niet bekeken is. Zonder deze maat
  /// rekende de bewerker dan met 16:9, en tekende hij een staande foto uitgerekt.
  final Size? bronMaat;
  final Map<KopScherm, KopInstelling?> huidig;
  final Future<void> Function(KopScherm scherm, KopInstelling? instelling) bewaar;
  final KopScherm begin;

  @override
  State<KopBewerker> createState() => _KopBewerkerState();
}

class _KopBewerkerState extends State<KopBewerker> {
  late KopScherm _scherm = widget.begin;

  /// Wat je hebt veranderd en nog niet bewaard, per scherm. Een sleutel met null = "Herstel".
  final Map<KopScherm, KopInstelling?> _bewerkt = {};
  FotoBlik? _blik;
  bool _bezig = false;

  @override
  void initState() {
    super.initState();
    _blik = bekendeBlik(widget.beeld);
    if (_blik == null) {
      bekijkFoto(widget.beeld).then((b) {
        if (mounted && b != null) setState(() => _blik = b);
      });
    }
  }

  KopInstelling? _instellingVan(KopScherm s) => _bewerkt.containsKey(s) ? _bewerkt[s] : widget.huidig[s];

  /// De instelling om mee te beginnen als je gaat slepen: de bewaarde, of anders precies wat de app nu
  /// zelf kiest — zodat de foto bij de eerste beweging niet verspringt.
  KopInstelling _beginVan(KopScherm s, Size vak, double balk, bool smal) {
    final i = _instellingVan(s);
    if (i != null) return i;
    final blik = _blik;
    final maat = blik?.maat ?? widget.bronMaat ?? const Size(16, 9);
    final plek = KopFoto.plekVoor(vak: vak, maat: maat, blik: blik, instelling: null, smal: smal, bovenRand: balk);
    final p = puntOpDoel(vak: vak, plek: plek, doel: doelInVak(kopDoel(smal: smal), vak, balk));
    return KopInstelling(fx: p.x, fy: p.y);
  }

  void _zet(KopInstelling i) => setState(() => _bewerkt[_scherm] = i);

  Future<void> _opslaan() async {
    setState(() => _bezig = true);
    try {
      for (final e in _bewerkt.entries) {
        if (e.value != widget.huidig[e.key]) await widget.bewaar(e.key, e.value);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _bezig = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Niet bewaard: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final kader = kopKader(_scherm);
    final i = _instellingVan(_scherm);
    final hoogte = i?.hoogte ?? (kader.maat.height - kader.balk);
    final vak = Size(kader.maat.width, hoogte + kader.balk);
    final veranderd = _bewerkt.entries.any((e) => e.value != widget.huidig[e.key]);
    return Dialog(
      backgroundColor: kPaneel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: math.min(MediaQuery.sizeOf(context).width - 48, 1100),
        height: math.min(MediaQuery.sizeOf(context).height - 48, 820),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('Kop aanpassen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(widget.naam,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kGedempt)),
                ),
                const Spacer(),
                IconButton(
                    tooltip: 'Sluiten',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(false)),
              ]),
              const SizedBox(height: 4),
              const Text(
                  'Sleep de foto om hem te verschuiven · scroll of knijp om te zoomen · sleep de onderrand '
                  'voor de hoogte. Elk scherm apart.',
                  style: TextStyle(color: kGedempt, fontSize: 12)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, children: [
                for (final s in KopScherm.values)
                  ChoiceChip(
                    key: ValueKey('kop-scherm-${s.name}'),
                    label: Text(kopSchermNaam(s) + (_instellingVan(s) == null ? '' : ' ·  eigen')),
                    selected: s == _scherm,
                    onSelected: (_) => setState(() => _scherm = s),
                  ),
              ]),
              const SizedBox(height: 14),
              Expanded(
                child: LayoutBuilder(builder: (_, c) {
                  // Het kader zo groot als past, met ruimte onder voor de greep van de onderrand.
                  final schaal = math.min(c.maxWidth / vak.width, (c.maxHeight - 24) / vak.height).clamp(.05, 1.0);
                  return Center(
                    child: SizedBox(
                      width: vak.width * schaal,
                      height: vak.height * schaal + 24,
                      child: _Kader(
                        key: ValueKey('kop-kader-${_scherm.name}'),
                        naam: widget.naam,
                        beeld: widget.beeld,
                        blik: _blik,
                        bronMaat: widget.bronMaat,
                        instelling: i,
                        vak: vak,
                        balk: kader.balk,
                        smal: kader.smal,
                        schaal: schaal,
                        begin: () => _beginVan(_scherm, vak, kader.balk, kader.smal),
                        wijzig: _zet,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 14),
              Row(children: [
                TextButton.icon(
                  key: const ValueKey('kop-herstel'),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                  label: const Text('Herstel'),
                  // Terug naar wat de app zelf kiest, op de gezichten — voor dit scherm.
                  onPressed: i == null ? null : () => setState(() => _bewerkt[_scherm] = null),
                ),
                const SizedBox(width: 6),
                Text(i == null ? 'De app kiest zelf, op de gezichten' : 'Zelf ingesteld',
                    style: const TextStyle(color: kGedempt, fontSize: 12)),
                const Spacer(),
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuleren')),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('kop-opslaan'),
                  onPressed: veranderd && !_bezig ? _opslaan : null,
                  child: Text(_bezig ? 'Bewaren…' : 'Opslaan'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Het kader van één scherm, met de foto erin zoals hij daar komt, en de bediening erop.
class _Kader extends StatefulWidget {
  const _Kader({
    super.key,
    required this.naam,
    required this.beeld,
    required this.blik,
    required this.bronMaat,
    required this.instelling,
    required this.vak,
    required this.balk,
    required this.smal,
    required this.schaal,
    required this.begin,
    required this.wijzig,
  });

  final String naam;
  final Uint8List beeld;
  final FotoBlik? blik;
  final Size? bronMaat;
  final KopInstelling? instelling;
  final Size vak;
  final double balk, schaal;
  final bool smal;
  final KopInstelling Function() begin;
  final void Function(KopInstelling) wijzig;

  @override
  State<_Kader> createState() => _KaderState();
}

class _KaderState extends State<_Kader> {
  KopInstelling? _start;
  double _startZoom = 1;
  Offset _startPunt = Offset.zero;

  Size get _maat => widget.blik?.maat ?? widget.bronMaat ?? const Size(16, 9);

  Rect _plek(KopInstelling? i) => KopFoto.plekVoor(
      vak: widget.vak, maat: _maat, blik: widget.blik, instelling: i, smal: widget.smal, bovenRand: widget.balk);

  /// De foto verschuiven met [delta] punten op het scherm (dus [delta] / schaal in het kader).
  void _schuif(KopInstelling vanaf, Offset delta) {
    final plek = _plek(vanaf).shift(delta / widget.schaal);
    final p = puntOpDoel(vak: widget.vak, plek: plek, doel: doelInVak(kopDoel(smal: widget.smal), widget.vak, widget.balk));
    widget.wijzig(vanaf.met(fx: p.x, fy: p.y));
  }

  void _zoom(double factor) {
    final i = widget.instelling ?? widget.begin();
    widget.wijzig(i.met(zoom: i.zoom * factor));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.schaal;
    final hoog = widget.vak.height * s;
    return Column(children: [
      SizedBox(
        width: widget.vak.width * s,
        height: hoog,
        child: Listener(
          // Scrollen = zoomen (muis en touchpad op de pc en de Mac).
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) _zoom(math.exp(-e.scrollDelta.dy / 600));
          },
          child: GestureDetector(
            key: const ValueKey('kop-foto'),
            behavior: HitTestBehavior.opaque,
            // Eén gebaar voor slepen én knijpen: met één vinger of de muis is de schaal 1.
            onScaleStart: (d) {
              _start = widget.instelling ?? widget.begin();
              _startZoom = _start!.zoom;
              _startPunt = d.focalPoint;
            },
            onScaleUpdate: (d) {
              final start = _start;
              if (start == null) return;
              final metZoom = start.met(zoom: _startZoom * d.scale);
              _schuif(metZoom, d.focalPoint - _startPunt);
            },
            onScaleEnd: (_) => _start = null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: _Voorbeeld(
                  naam: widget.naam,
                  beeld: widget.beeld,
                  plek: _plek(widget.instelling),
                  vak: widget.vak,
                  balk: widget.balk,
                  smal: widget.smal,
                  schaal: s,
                ),
              ),
            ),
          ),
        ),
      ),
      // De greep van de onderrand: omlaag slepen maakt de kop hoger.
      MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: GestureDetector(
          key: const ValueKey('kop-onderrand'),
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => _start = widget.instelling ?? widget.begin(),
          onVerticalDragUpdate: (d) {
            final i = widget.instelling ?? widget.begin();
            final nu = i.hoogte ?? (widget.vak.height - widget.balk);
            widget.wijzig(i.met(hoogte: nu + d.delta.dy / s));
          },
          child: SizedBox(
            width: widget.vak.width * s,
            height: 24,
            child: Center(
              child: Container(
                width: 56,
                height: 5,
                decoration: BoxDecoration(color: kGedempt, borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// De kop zoals hij op dat scherm komt: grijs, met het verloop onderaan, het verloop van links op een
/// breed scherm, de balk erboven en de naam op zijn plek.
class _Voorbeeld extends StatelessWidget {
  const _Voorbeeld({
    required this.naam,
    required this.beeld,
    required this.plek,
    required this.vak,
    required this.balk,
    required this.smal,
    required this.schaal,
  });

  final String naam;
  final Uint8List beeld;
  final Rect plek;
  final Size vak;
  final double balk, schaal;
  final bool smal;

  @override
  Widget build(BuildContext context) {
    final s = schaal;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: kAchtergrond),
      Positioned(
        left: plek.left * s,
        top: plek.top * s,
        width: plek.width * s,
        height: plek.height * s,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.2126, 0.7152, 0.0722, 0, 0, //
            0.2126, 0.7152, 0.0722, 0, 0, //
            0.2126, 0.7152, 0.0722, 0, 0, //
            0, 0, 0, 1, 0, //
          ]),
          child: Image.memory(beeld,
              fit: BoxFit.fill,
              cacheWidth: decodeerBreedte(plek.width * s * dpr),
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox()),
        ),
      ),
      Positioned(
        top: balk * s,
        left: 0,
        right: 0,
        bottom: 0,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x44000000), Color(0x66000000), Color(0xDB07080C), kAchtergrond, kAchtergrond],
              stops: [0, .30, .58, .92, 1],
            ),
          ),
        ),
      ),
      if (!smal)
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kAchtergrond, Color(0x5907080C), Color(0x0007080C)],
              stops: [0, .44, .74],
            ),
          ),
        ),
      if (balk > 0)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: balk * s,
          child: const ColoredBox(color: Color(0x6607080C)),
        ),
      // De naam, ongeveer waar hij in de echte kop staat — om te zien wat hij bedekt.
      Positioned(
        left: (smal ? 18 : 56) * s,
        right: smal ? 18 * s : vak.width * s * .45,
        bottom: vak.height * s * (smal ? .14 : .30),
        child: IgnorePointer(
          child: Text(naam.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: kTekst, fontSize: math.max(9, (smal ? 40 : 84) * s), fontWeight: FontWeight.w900, height: .95)),
        ),
      ),
    ]);
  }
}
