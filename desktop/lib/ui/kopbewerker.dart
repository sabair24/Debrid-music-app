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
import 'kop_logo.dart';
import 'kopfoto.dart';
import 'typografie.dart';

/// Hoe groot de kop op elk soort scherm is, in punten — het kader waarin je hem instelt. [balk] is
/// het stuk achter de zwevende balk (de foto loopt erachter door, het brandpunt hoort eronder).
///
/// Gemeten in de echte app: een tv is 960 breed en de kop 360 + 75 (zie `kTvKopZicht`); op de pc is
/// de kop op een venster van 1440 zo'n 700 hoog met de balk van 64 erboven; een gsm is 411 breed en de
/// kop daar ongeveer 520.
///
/// Een iPad rechtop: 834 breed, de kop gemeten op zo'n 740 hoog (zie `beeldvorm.dart`), met de
/// zwevende balk en de statusbalk (64 + 24) erboven.
///
/// Op een gsm is het kader sinds 27-10-2026 alleen de foto met de naam erop (`kGsmKopFoto`, 440): de feiten
/// en de knoppen staan daar onder de foto.
({Size maat, double balk, bool smal}) kopKader(KopScherm s) => switch (s) {
      KopScherm.pc => (maat: const Size(1440, 700), balk: 64, smal: false),
      KopScherm.tv => (maat: const Size(960, 435), balk: 75, smal: false),
      KopScherm.gsm => (maat: const Size(411, 440), balk: 0, smal: true),
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
    this.logo,
  });

  final String naam;
  final Uint8List beeld;

  /// Het logo van TheAudioDB, of null. Is er een, dan kies je per scherm of de kop het logo of de naam toont.
  final Uint8List? logo;

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
    final maat = _maat;
    final plek = KopFoto.plekVoor(
        vak: vak, maat: maat, blik: blik, instelling: null, smal: smal, bovenRand: balk, maxSchaal: _grens(s, vak, maat));
    final p = puntOpDoel(vak: vak, plek: plek, doel: doelInVak(kopDoel(smal: smal), vak, balk));
    return KopInstelling(fx: p.x, fy: p.y);
  }

  Size get _maat => _blik?.maat ?? widget.bronMaat ?? const Size(16, 9);

  /// De scherptegrens voor het kader van [s] ([scherpteGrens]): op de pc, de Mac en de iPad, zoals de echte
  /// kop; op de gsm en de tv vullend. Het kader is altijd even breed, het scherm niet: hoeveel pixels de echte
  /// kop breed is, komt van dit toestel als je het scherm bewerkt waar je op zit, en is anders een schatting
  /// (een iPad tekent twee pixels per punt).
  double? _grens(KopScherm s, Size vak, Size maat) {
    if (s == KopScherm.gsm || s == KopScherm.tv) return null;
    final pixels = s == widget.begin
        ? MediaQuery.sizeOf(context).width * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1)
        : vak.width * (s == KopScherm.staand ? 2 : 1);
    return scherpteGrens(tot: kScherpTot, bron: widget.bronMaat, maat: maat, vak: vak.width, pixels: pixels);
  }

  void _zet(KopInstelling i) => setState(() => _bewerkt[_scherm] = i);

  /// Een stap met een knop: de foto [richting] op, 3 % van het kader. Op een tv is er geen vinger en geen
  /// muis, en op een gsm is een kleine stap met een knop preciezer dan met je duim.
  void _stap(Offset richting, Size vak, double balk, bool smal) {
    final start = _beginVan(_scherm, vak, balk, smal);
    final plek = KopFoto.plekVoor(
            vak: vak,
            maat: _maat,
            blik: _blik,
            instelling: start,
            smal: smal,
            bovenRand: balk,
            maxSchaal: _grens(_scherm, vak, _maat))
        .shift(Offset(richting.dx * vak.width * .03, richting.dy * vak.height * .03));
    final p = puntOpDoel(vak: vak, plek: plek, doel: doelInVak(kopDoel(smal: smal), vak, balk));
    _zet(start.met(fx: p.x, fy: p.y));
  }

  /// Groter of kleiner met een knop, ook kleiner dan vullend (Saber, 27-10-2026: "uitvergroten en verkleinen
  /// hoe ik het wil").
  void _zoomStap(double factor, Size vak, double balk, bool smal) {
    final start = _beginVan(_scherm, vak, balk, smal);
    _zet(start.met(zoom: start.zoom * factor));
  }

  /// Een logo dat de kop kan tonen: alleen met een doorzichtige achtergrond (zie [heeftDoorzichtigheid]).
  Uint8List? get _bruikbaarLogo => switch (widget.logo) {
        final l? when heeftDoorzichtigheid(l) => l,
        _ => null,
      };

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
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: kGedempt)),
                ),
                const Spacer(),
                IconButton(
                    tooltip: 'Sluiten',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(false)),
              ]),
              const SizedBox(height: 4),
              Text(
                  'Sleep de foto in elke richting, opzij ook voorbij de rand · scroll, knijp of − en + om hem groter '
                  'of kleiner te maken · sleep de onderrand voor de hoogte. Elk scherm apart.',
                  style: TextStyle(color: kGedempt, fontSize: 12)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final s in KopScherm.values)
                  ChoiceChip(
                    key: ValueKey('kop-scherm-${s.name}'),
                    label: Text(kopSchermNaam(s) + (_instellingVan(s) == null ? '' : ' ·  eigen')),
                    selected: s == _scherm,
                    onSelected: (_) => setState(() => _scherm = s),
                  ),
                // Logo of naam, per scherm (Saber, 27-10-2026): alleen als TheAudioDB een bruikbaar logo heeft.
                if (_bruikbaarLogo != null) ...[
                  const SizedBox(width: 12),
                  Text('Kop toont', style: TextStyle(color: kGedempt, fontSize: 12)),
                  for (final metNaam in const [false, true])
                    ChoiceChip(
                      key: ValueKey(metNaam ? 'kop-toont-naam' : 'kop-toont-logo'),
                      label: Text(metNaam ? 'Naam' : 'Logo'),
                      selected: (i?.naam ?? false) == metNaam,
                      onSelected: (_) => _zet((i ?? _beginVan(_scherm, vak, kader.balk, kader.smal)).met(naam: metNaam)),
                    ),
                ],
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
                        tv: _scherm == KopScherm.tv,
                        logo: (i?.naam ?? false) ? null : _bruikbaarLogo,
                        maxSchaal: _grens(_scherm, vak, _maat),
                        schaal: schaal,
                        begin: () => _beginVan(_scherm, vak, kader.balk, kader.smal),
                        wijzig: _zet,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 2, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                IconButton(
                    key: const ValueKey('kop-kleiner'),
                    tooltip: 'Kleiner',
                    icon: const Icon(Icons.zoom_out_rounded),
                    onPressed: () => _zoomStap(1 / 1.1, vak, kader.balk, kader.smal)),
                Text('${((i?.zoom ?? 1) * 100).round()} %', style: TextStyle(color: kGedempt, fontSize: 12)),
                IconButton(
                    key: const ValueKey('kop-groter'),
                    tooltip: 'Groter',
                    icon: const Icon(Icons.zoom_in_rounded),
                    onPressed: () => _zoomStap(1.1, vak, kader.balk, kader.smal)),
                const SizedBox(width: 12),
                for (final (sleutel, icoon, tip, richting) in const [
                  ('kop-links', Icons.arrow_back_rounded, 'Naar links', Offset(-1, 0)),
                  ('kop-omhoog', Icons.arrow_upward_rounded, 'Omhoog', Offset(0, -1)),
                  ('kop-omlaag', Icons.arrow_downward_rounded, 'Omlaag', Offset(0, 1)),
                  ('kop-rechts', Icons.arrow_forward_rounded, 'Naar rechts', Offset(1, 0)),
                ])
                  IconButton(
                      key: ValueKey(sleutel),
                      tooltip: tip,
                      icon: Icon(icoon),
                      onPressed: () => _stap(richting, vak, kader.balk, kader.smal)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                TextButton.icon(
                  key: const ValueKey('kop-herstel'),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                  label: const Text('Herstel'),
                  // Terug naar wat de app zelf kiest, op de gezichten — voor dit scherm.
                  onPressed: i == null ? null : () => setState(() => _bewerkt[_scherm] = null),
                ),
                const SizedBox(width: 6),
                // Krimpt op een gsm, waar de bewerker sinds 27-10-2026 ook opengaat.
                Flexible(
                  child: Text(i == null ? 'De app kiest zelf, op de gezichten' : 'Zelf ingesteld',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: kGedempt, fontSize: 12)),
                ),
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
    required this.tv,
    required this.logo,
    required this.maxSchaal,
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
  final bool smal, tv;
  final Uint8List? logo;
  final double? maxSchaal;
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
      vak: widget.vak,
      maat: _maat,
      blik: widget.blik,
      instelling: i,
      smal: widget.smal,
      bovenRand: widget.balk,
      maxSchaal: widget.maxSchaal);

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
                  tv: widget.tv,
                  logo: widget.logo,
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
/// breed scherm, de balk erboven en de naam (of het logo) op zijn plek.
///
/// Zoals de kop sinds 27-10-2026 is: een vaste strook onderaan en de tekst onderaan, behalve op een tv
/// ([tv]), die zijn verloop over de hele kop houdt.
class _Voorbeeld extends StatelessWidget {
  const _Voorbeeld({
    required this.naam,
    required this.beeld,
    required this.plek,
    required this.vak,
    required this.balk,
    required this.smal,
    required this.tv,
    required this.logo,
    required this.schaal,
  });

  final String naam;
  final Uint8List beeld;
  final Rect plek;
  final Size vak;
  final double balk, schaal;
  final bool smal, tv;
  final Uint8List? logo;

  @override
  Widget build(BuildContext context) {
    final s = schaal;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final randen = randenVan(plek, vak);
    final grootte = tv ? 46.0 : artiestNaamGrootte(vak.width);
    final naamTekst = Text(naam.toUpperCase(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: kTekst, fontSize: math.max(9, grootte * s), fontWeight: FontWeight.w800, height: .95));
    final l = logo;
    return Stack(fit: StackFit.expand, children: [
      ColoredBox(color: kAchtergrond),
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
          child: zachteRanden(
            Image.memory(beeld,
                fit: BoxFit.fill,
                cacheWidth: decodeerBreedte(plek.width * s * dpr),
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox()),
            links: randen.links,
            rechts: randen.rechts,
            boven: randen.boven,
            onder: randen.onder,
          ),
        ),
      ),
      if (tv)
        Positioned(
          top: balk * s,
          left: 0,
          right: 0,
          bottom: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [paginaWaas(0x44, donker: Colors.black), paginaWaas(0x66, donker: Colors.black), paginaWaas(0xDB), kAchtergrond, kAchtergrond],
                stops: [0, .30, .58, .92, 1],
              ),
            ),
          ),
        )
      else
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: (smal ? 170 : 160) * s,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [paginaWaas(0x00), paginaWaas(0xDB), kAchtergrond],
                stops: const [0, .6, 1],
              ),
            ),
          ),
        ),
      if (!smal)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: tv
                  ? [kAchtergrond, paginaWaas(0x59), paginaWaas(0x00)]
                  : [paginaWaas(0xF0), paginaWaas(0xB8), paginaWaas(0x00)],
              stops: tv ? const [0, .44, .74] : const [0, .38, .60],
            ),
          ),
        ),
      if (balk > 0)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: balk * s,
          child: ColoredBox(color: paginaWaas(0x66)),
        ),
      // De naam of het logo, ongeveer waar hij in de echte kop staat — om te zien wat hij bedekt. Op een breed
      // scherm staan de feiten en de knoppen er nog onder (zo'n 180 punten), op een gsm onder de foto.
      Positioned(
        left: (smal ? 18 : 56) * s,
        right: smal ? 18 * s : vak.width * s * .45,
        bottom: (smal ? 14 : (tv ? vak.height * .30 : 180)) * s,
        child: IgnorePointer(
          child: l == null
              ? naamTekst
              : Align(
                  alignment: Alignment.bottomLeft,
                  child: KopLogo(
                      logo: l,
                      kleur: kTekst,
                      hoogte: (tv || smal ? 64 : (vak.width >= 1280 ? 104 : 88)) * s,
                      breedte: (smal ? vak.width - 36 : 520) * s,
                      terugval: naamTekst),
                ),
        ),
      ),
    ]);
  }
}
