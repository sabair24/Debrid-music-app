/// De albumtegel. Eén, in plaats van twee die het oneens zijn.
///
/// **Waarom dit bestand er is.** Dezelfde plaat werd op twee schermen anders getekend: op Albums in
/// een kaartje met een randje en een ronding van 14, op Start kaal op zwart met een ronding van 10.
/// De app was het met zichzelf oneens over hoe een album eruitziet, en dat is een van de dingen die
/// je als "slordig" ziet zonder te kunnen aanwijzen waaróm.
///
/// **De gekozen vorm: open met diepte.** Geen kaartje eromheen. De hoes ís de tegel, en die komt met
/// een schaduw van de pagina af. Voor een muziekapp is dat de juiste kant op: de hoes is het
/// helderste en het interessantste op het scherm, en een kader eromheen zet er een tweede rechthoek
/// omheen die niets zegt.
///
/// **Wat NIET verandert is het gebaar.** De tegel groeit bij aanwijzen met [tileFocusScale] in 170
/// milliseconden, precies zoals hij dat altijd al deed. Wat er verandert is dat er in rust een
/// schaduw ónder ligt om vanaf te groeien; de tekening had een extra lift van twee punten, maar met
/// de groei erbij zijn dat twee liften over elkaar en dan aarzelt het.
///
/// **En de rijhoogte wordt berekend.** Een liggende `ListView` geeft zijn kinderen een strákke
/// hoogte en knipt ze af, en die hoogte stond met de hand op 204 (236 op tv) met een commentaar
/// erbij dat het "maar net" genoeg was. Voeg iets toe aan de tegel — of zet de systeemletters groter
/// — en de onderste regel wordt eraf gesneden, stil, want een liggende lijst knipt gewoon door.
/// [hoogteVanTegelrij] rekent hem uit; `test/afmetingen_test.dart` bewijst dat de getekende tegel
/// erbinnen past.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../tv.dart';
import 'draaihoes.dart';
import 'kleuren.dart';
import 'maten.dart';
import 'typografie.dart';

/// De maat van een hoes in een liggende rij op Start.
const double kTegelHoes = 140;

/// De titel onder een hoes. De gewone tekstrol, met een vaste regelhoogte erbij.
///
/// Uit `ui/typografie.dart` en niet als eigen getal: dit is precies waar de 24 verschillende
/// tekstgroottes vandaan kwamen — elke widget die zijn eigen maat verzon omdat er niets was om naar
/// te wijzen.
final kTegelTitel = kTekstNormaal.copyWith(height: _regel);

/// Wat onder de titel staat: de artiest.
final kTegelOnder = kTekstKlein.copyWith(height: _regel);

/// De regelhoogte waarmee [hoogteVanTegelrij] rekent, en die de tegel zelf ook aanhoudt.
const double _regel = 1.35;

/// Lucht boven en onder de tegel in een rij: wat de schaduw nodig heeft om niet afgeknipt te worden.
const double _lucht = 10;

/// Hoeveel regels de titel onder een hoes krijgt.
///
/// **Twee, overal.** Saber op de S26, 16-10-2026: "I Just Called To S…", "Danse Méditerran…" — op
/// 140 punten passen 17 à 18 tekens, en dan is de helft van de titels weg. Twee regels kosten een rij
/// 19 punten. Op de tv bleef het eerst één (de tekst staat daar 1,35× groter), tot Saber dezelfde dag
/// op de Shield ook "twee regels, zoals de gsm" koos: daar stond "The Platinu…" en "Songs About…".
///
/// De ruimte voor die twee regels is er ook als de titel kort is: een liggende rij geeft elke tegel
/// dezelfde vaste hoogte en centreert de inhoud, dus een tegel met één regel zou anders een halve
/// regel lager staan dan zijn buren.
int get kTegelTitelRegels => 2;

/// De hoogte die een liggende rij tegels nodig heeft.
///
/// De tegel zelf plus de groei bij aanwijzen. Dat vermenigvuldigen is geen marge maar rekenwerk:
/// `AnimatedScale` schaalt om het midden, dus een tegel die 1,14× groeit heeft ook 1,14× de hoogte
/// nodig of hij wordt aan twee kanten bijgesneden. De [_lucht] erbovenop is voor de schaduw.
double hoogteVanTegelrij(BuildContext context, {double hoes = kTegelHoes}) =>
    hoogteVanTegel(context, hoes: hoes) * tileFocusScale + _lucht;

/// De hoogte van de tegel zelf, in rust.
///
/// Alles wat erin zit is gemeten en niet geschat: de hoes, het gat eronder, en twee tekstregels op
/// de schaal die de gebruiker in zijn toestel heeft ingesteld. Die laatste is waarom dit een functie
/// is en geen getal: op de Shield staat de tekst 1,35× groter, en dan zijn twee regels bijna vijftig
/// punten in plaats van vijfendertig.
///
/// Wat er NIET in zit is [AlbumTegel.onderHoes] — de streep die zegt dat er nog gegevens komen. Die
/// staat alleen op de tegels in een raster en op de tv-rijen, en daar ligt de hoes in een
/// `Expanded`: wat de streep inneemt gaat daar van de hoes af, niet van de rij.
double hoogteVanTegel(BuildContext context, {double hoes = kTegelHoes}) {
  final schaal = MediaQuery.textScalerOf(context);
  return hoes + kRuimte8 + kTegelTitelRegels * _regelhoogte(schaal, kTegelTitel) + _regelhoogte(schaal, kTegelOnder);
}

/// De hoogte die één tekstregel werkelijk inneemt.
///
/// **Naar boven afgerond, en dat is precies waar de eerste versie op zakte.** Flutter zet een regel
/// niet op de rekenkundige hoogte neer maar rondt hem af op een heel punt: 14 punten op 1,35×
/// tekstschaal met regelhoogte 1,35 rekent uit op 25,515 en meet 26. Twee regels, tweemaal iets meer
/// dan een halve punt, en de tegel was 196 hoog waar de formule 195,4 zei — en dan knipt de rij hem
/// af. Zonder afronding is dit geen bovengrens en dus geen bruikbare formule.
double _regelhoogte(TextScaler schaal, TextStyle stijl) =>
    (schaal.scale(stijl.fontSize!) * _regel).ceilToDouble();

/// Een raster van tegels waarin de hoes vierkant blijft.
///
/// Een vaste verhouding (`childAspectRatio: .78`) gaf de tegel een vaste hoogte per breedte, en de
/// hoes ligt in een `Expanded`: wat de tekst eronder meer nodig heeft gaat van de hoes af. Met twee
/// titelregels ([kTegelTitelRegels]) werd een hoes van 171 punten breed daardoor 155 hoog. Hier wordt de
/// celhoogte uitgerekend uit de echte celbreedte, met dezelfde formule als de liggende rijen.
///
/// Hetzelfde aantal kolommen als `SliverGridDelegateWithMaxCrossAxisExtent` met [maxBreedte] en
/// [tussen] — die rekent `(breedte / (max + tussen)).ceil()`. [extra] is wat er nog onder de hoes
/// kan staan (de streep van `BusyLine`).
SliverGridDelegate tegelRaster(BuildContext context, double breedte,
    {double maxBreedte = 190, double tussen = 20, double extra = 0}) {
  final n = (breedte / (maxBreedte + tussen)).ceil().clamp(1, 99);
  final cel = (breedte - (n - 1) * tussen) / n;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: n,
    mainAxisSpacing: tussen,
    crossAxisSpacing: tussen,
    mainAxisExtent: hoogteVanTegel(context, hoes: cel) + extra,
  );
}

/// De hoes, op de maat die de tegel hem geeft.
typedef HoesBouwer = Widget Function(double maat);

/// Hoe ver de cd uit de hoes schuift als de muis erop staat, als deel van de hoes.
const kTegelSchijfUit = .22;

/// De cd achter een tegel: zilver met een regenboogglans, de hoes als etiket in het midden en een gat.
///
/// Lichter dan de zwarte schijf van Nu speelt, met opzet: op de donkere achtergrond van het raster
/// was een zwarte schijf die er een stuk uit schuift nauwelijks te zien (voorbeeld van 17-10-2026).
class TegelSchijf extends StatelessWidget {
  const TegelSchijf({super.key, required this.etiket, required this.maat, this.decodeerBreedte});

  final Uint8List etiket;
  final double maat;

  /// Op welke breedte het etiket gedecodeerd wordt. Geef de breedte van de hoes zelf mee: dan is het
  /// hetzelfde beeld in de cache en wordt de hoes niet een tweede keer gedecodeerd (en naar de
  /// videokaart gestuurd) alleen voor een etiket van een derde van zijn maat. Tijdens het scrollen
  /// was dat per nieuwe tegel een volledige JPEG-decodering extra (17-10-2026).
  final int? decodeerBreedte;

  @override
  Widget build(BuildContext context) {
    final label = maat * .36;
    return SizedBox.square(
      dimension: maat,
      child: Stack(alignment: Alignment.center, children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(colors: [
              Color(0xFFC9CED8), Color(0xFF8E96A6), Color(0xFFD9D2E8), Color(0xFF9FB4C8),
              Color(0xFFE2E5EC), Color(0xFF8A90A0), Color(0xFFCFC6E0), Color(0xFFC9CED8),
            ]),
            boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: SizedBox.square(dimension: maat),
        ),
        // Een zachte donkere ring halverwege: de groef tussen het bespeelde deel en het etiket.
        Container(
          width: maat * .5,
          height: maat * .5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x33000000), width: maat * .02),
          ),
        ),
        ClipOval(
          child: Image.memory(etiket,
              width: label,
              height: label,
              fit: BoxFit.cover,
              cacheWidth: decodeerBreedte ?? (label * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (_, __, ___) => const SizedBox()),
        ),
        Container(
          width: maat * .07,
          height: maat * .07,
          decoration: const BoxDecoration(color: Color(0xFF07080C), shape: BoxShape.circle),
        ),
      ]),
    );
  }
}

/// De ronde witte afspeelknop op een tegel.
class _AfspeelRondje extends StatefulWidget {
  const _AfspeelRondje({required this.maat, required this.onTap});

  final double maat;
  final VoidCallback onTap;

  @override
  State<_AfspeelRondje> createState() => _AfspeelRondjeState();
}

class _AfspeelRondjeState extends State<_AfspeelRondje> {
  bool _aan = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _aan = true),
        onExit: (_) => setState(() => _aan = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _aan ? 1.08 : 1,
            duration: const Duration(milliseconds: 140),
            child: Container(
              key: const ValueKey('tegel-afspelen'),
              width: widget.maat,
              height: widget.maat,
              decoration: BoxDecoration(
                color: _aan ? Colors.white : const Color(0xF2FFFFFF),
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 14, offset: Offset(0, 4))],
              ),
              child: Icon(Icons.play_arrow_rounded, size: widget.maat * .62, color: const Color(0xFF07080C)),
            ),
          ),
        ),
      );
}

/// Een album (of een nummer, of een aanbeveling) als tegel.
///
/// [breedte] leeg laten betekent "vul de cel waarin je staat" — dat is het raster op Albums. Een
/// getal betekent een vaste maat, en dat is een liggende rij op Start.
class AlbumTegel extends StatefulWidget {
  const AlbumTegel({
    super.key,
    required this.hoes,
    required this.titel,
    required this.onTap,
    this.ondertitel = '',
    this.ondertitelWidget,
    this.onderHoes,
    this.onLongPress,
    this.onSecondaryTap,
    this.breedte,
    this.heroTag,
    this.draaibaar = false,
    this.achterkant,
    this.schijf,
    this.onAfspelen,
    this.voorladen,
  });

  /// Bij de eerste keer aanwijzen: alvast klaarleggen wat een klik of twee tikken straks nodig
  /// hebben (van schijf, nooit van het net). Geeft de achterkant terug als die er is; die wordt dan
  /// meteen op deze maat gedecodeerd, zodat twee tikken zonder wachten draaien.
  final Future<Uint8List?> Function()? voorladen;

  /// De cd achter de hoes, die er een stuk uit schuift als de muis erop staat (Saber, 17-10-2026:
  /// "cd schuift uit + afspeelknop"). Null = geen cd.
  final HoesBouwer? schijf;

  /// De ronde afspeelknop op de hoes, die verschijnt als de muis erop staat. Null = geen knop.
  final VoidCallback? onAfspelen;

  /// De hoes, gebouwd op de maat die hier bepaald wordt.
  final HoesBouwer hoes;

  final String titel;

  /// De kale tekst onder de titel, voor waar er geen widget is.
  final String ondertitel;

  /// De ondertitel als widget — een aanklikbare artiestnaam. Wint van [ondertitel].
  ///
  /// De aanroeper haalt hem zelf uit het focuspad waar dat moet: op een afstandsbediening zou elke
  /// tegel er anders een tweede stop bij krijgen en pijl je twee keer zo lang door een rij.
  final Widget? ondertitelWidget;

  /// Iets vlak onder de hoes, vóór de titel: de streep die zegt dat er nog gegevens komen.
  final Widget? onderHoes;

  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final void Function(Offset globaal)? onSecondaryTap;

  /// Vast, of vullend als dit leeg is.
  final double? breedte;

  /// Laat de hoes naar de albumpagina vliegen in plaats van te knippen.
  final Object? heroTag;

  /// Twee tikken draaien de hoes om (16-10-2026). Een gewone tik wacht dan [kTweedeTik]; zonder
  /// [draaibaar] verandert er niets en opent een tik meteen. Nooit op een tv.
  final bool draaibaar;

  /// Haalt de achterkant op bij de eerste dubbeltik (van schijf). Null of niets gevonden = wiebelen.
  final Future<Uint8List?> Function()? achterkant;

  @override
  State<AlbumTegel> createState() => _AlbumTegelState();
}

class _AlbumTegelState extends State<AlbumTegel> {
  bool _aan = false;

  /// Staat de MUIS erop (niet de selectie van een tv): alleen dan schuift de cd uit en komt de knop.
  bool _muis = false;

  final _draai = DraaiHoesController();
  final _tikken = TweeTikken();
  Uint8List? _achter;
  bool _zoekt = false;
  bool _voorgeladen = false;

  /// De cd schuift nog terug: tot dan blijft hij zichtbaar. Daarna tekent hij niets meer — hij ligt
  /// in rust achter een dichte hoes, en zijn wazige schaduw werd anders in elk beeld van elke tegel
  /// gerasterd.
  bool _schijfTerug = false;
  Timer? _terugKlok;

  /// De cd en de afspeelknop bestaan pas na de eerste keer aanwijzen. Daarvoor zijn ze nergens voor
  /// nodig, en een rij van twaalf nieuwe tegels bouwde ze anders allemaal tegelijk mee in het beeld
  /// waarin de rij in zicht scrolde (warmte.log, 17-10-2026: pieken van 24 ms bouwen).
  bool _extraGebouwd = false;

  /// Staat de muis er nu werkelijk op? [_muis] volgt een beeld later bij het eerste aanwijzen.
  bool _erop = false;

  /// De eerste keer dat de muis erop komt: [AlbumTegel.voorladen], één keer per tegel.
  Future<void> _laadVoor() async {
    final laad = widget.voorladen;
    if (_voorgeladen || laad == null || isTv) return;
    _voorgeladen = true;
    try {
      final b = await laad();
      if (b == null || !mounted || _achter != null || !_draaien) return;
      await precacheImage(ResizeImage(MemoryImage(b), width: _decodeer(_maat)), context);
      if (mounted && _achter == null) setState(() => _achter = b);
    } catch (_) {/* niets klaar is geen fout: dan haalt de dubbeltik hem zoals vroeger */}
  }

  bool get _draaien => widget.draaibaar && !isTv;

  /// De maat waarop de hoes laatst getekend is: de achterkant wordt op dezelfde maat gedecodeerd.
  double _maat = kTegelHoes;

  int _decodeer(double maat) => (maat * MediaQuery.devicePixelRatioOf(context)).round();

  @override
  void initState() {
    super.initState();
    // De schaduw onder de tegel is vierkant; staat de achterkant voor, dan draagt die zijn eigen.
    _draai.voorInRust.addListener(_opRust);
  }

  void _opRust() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _terugKlok?.cancel();
    _draai.voorInRust.removeListener(_opRust);
    _draai.dispose();
    _tikken.dispose();
    super.dispose();
  }

  Future<void> _dubbel() async {
    if (_achter == null && !_zoekt && widget.achterkant != null) {
      _zoekt = true;
      try {
        final b = await widget.achterkant!();
        if (b != null && mounted) {
          // Gedecodeerd vóór de draai, anders staat er halverwege een leeg vlak.
          await precacheImage(ResizeImage(MemoryImage(b), width: _decodeer(_maat)), context);
          if (mounted) setState(() => _achter = b);
        }
      } catch (_) {/* geen achterkant: dan wiebelt hij */} finally {
        _zoekt = false;
      }
    }
    if (mounted) _draai.draai(heeftAchterkant: _achter != null);
  }

  /// De hoes met zijn schaduw eronder.
  ///
  /// Geen `ClipRRect` hier: `cover` en `_netCover` knippen zichzelf al op [kHoek12] af. Er nog een
  /// kniplaag omheen zetten kost een laag op de meest getekende widget van de app — bij een
  /// scrollende lijst staan er zestien tegelijk in beeld.
  Widget _hoesMet(double maat) {
    final vorm = BorderRadius.circular(kHoek12);
    _maat = maat;
    final kaal = widget.hoes(maat);
    final hoes = !_draaien
        ? kaal
        : DraaiHoes(
            controller: _draai,
            voor: kaal,
            // Helemaal, in zijn eigen vorm (zie [achterkantMaat]).
            achter: _achter == null
                ? null
                : AchterkantBeeld(
                    beeld: _achter!, maat: maat, hoek: kHoek12, decodeerBreedte: _decodeer(maat), schaduw: kSchaduw1),
          );
    final metSchaduw = AnimatedContainer(
      duration: kGebaar,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: vorm,
        // Geen vierkante schaduw onder een achterkant die breder is dan hoog: die draagt zijn eigen.
        boxShadow: !_draai.voorInRust.value ? const [] : (_aan ? kSchaduw2 : kSchaduw1),
      ),
      child: widget.heroTag == null
          ? hoes
          : Hero(
              tag: widget.heroTag!,
              // Tijdens de vlucht alleen de hoes, zonder de schaduw eromheen: die zou meeschalen en
              // onderweg een zwarte vlek onder een groeiend vierkant worden.
              flightShuttleBuilder: (_, __, ___, ____, _____) => widget.hoes(maat),
              child: hoes,
            ),
    );
    final schijf = widget.schijf;
    final speel = widget.onAfspelen;
    if (isTv || (schijf == null && speel == null)) return metSchaduw;
    // De muis op de hoes: de cd schuift er een stuk rechts uit (zoals in de lijst op de artiestpagina)
    // en er komt een ronde afspeelknop op. Niet zolang de achterkant voor staat.
    //
    // De hoes gaat zelf de helft van de weg naar links. In een raster tekent de tegel rechts ervan
    // later, en die dekte een cd die alleen naar rechts schoof voor het grootste deel af; zo blijft
    // hij binnen de eigen cel plus de tussenruimte.
    final uit = _muis && _draai.voorInRust.value;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (schijf != null && _extraGebouwd)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            left: uit ? maat * kTegelSchijfUit / 2 : maat * .02,
            top: maat * .02,
            width: maat * .96,
            height: maat * .96,
            // Opgebouwd maar onzichtbaar in rust: zo schuift hij vloeiend uit (de animatie heeft een
            // beginstand) en kost hij niets zolang hij achter de hoes ligt. Opacity 0 tekent niets.
            child: Visibility(
              visible: uit || _schijfTerug,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              child: IgnorePointer(
              child: AnimatedRotation(
                turns: uit ? .12 : 0,
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                child: schijf(maat * .96),
              ),
            ),
            ),
          ),
        AnimatedSlide(
          offset: Offset(uit ? -kTegelSchijfUit / 2 : 0, 0),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          child: Stack(clipBehavior: Clip.none, children: [
        metSchaduw,
        if (speel != null && _extraGebouwd)
          Positioned(
            right: maat * .06,
            bottom: maat * .06,
            child: AnimatedScale(
              scale: uit ? 1 : .6,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: uit ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: IgnorePointer(
                  ignoring: !uit,
                  child: _AfspeelRondje(maat: (maat * .26).clamp(34.0, 52.0), onTap: speel),
                ),
              ),
            ),
          ),
          ]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final vast = widget.breedte;
    final tegel = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        _terugKlok?.cancel();
        _erop = true;
        if (_extraGebouwd) {
          setState(() => _aan = _muis = true);
        } else {
          // Eerst bouwen in rust, en een beeld later pas uit: anders heeft het uitschuiven geen
          // beginstand en staat de cd er meteen.
          setState(() {
            _aan = true;
            _extraGebouwd = true;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _erop) setState(() => _muis = true);
          });
        }
        unawaited(_laadVoor());
      },
      onExit: (_) {
        _erop = false;
        _terugKlok?.cancel();
        _terugKlok = Timer(const Duration(milliseconds: 460), () {
          if (mounted) setState(() => _schijfTerug = false);
        });
        setState(() {
          _aan = _muis = false;
          _schijfTerug = true;
        });
      },
      child: Pressable(
        // Wacht op een mogelijke tweede tik alleen als er iets te draaien valt.
        onPressed: _draaien ? () => _tikken.enkel(widget.onTap) : widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTap: widget.onSecondaryTap,
        borderRadius: BorderRadius.circular(kHoek12),
        // De tegel groeit al en licht al op, dus focus voedt diezelfde stand in plaats van er een
        // tweede, andere animatie bovenop te zetten.
        scaleOnFocus: false,
        ringOnFocus: false,
        onFocusChange: (v) => setState(() => _aan = v),
        child: AnimatedScale(
          scale: _aan ? tileFocusScale : 1,
          duration: kGebaar,
          curve: Curves.easeOut,
          child: Column(
            // Vullend in een rastercel (daar zit de hoes in een `Expanded`), krap in een liggende
            // rij (daar geeft de rij een strakke hoogte en zou een vullende kolom bij het groeien
            // over de randen heen schalen en afgeknipt worden).
            mainAxisSize: vast == null ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (vast == null)
                Expanded(child: LayoutBuilder(builder: (_, c) => _hoesMet(c.maxWidth)))
              else
                _hoesMet(vast),
              if (widget.onderHoes != null) widget.onderHoes!,
              const SizedBox(height: kRuimte8),
              SizedBox(
                height: kTegelTitelRegels * _regelhoogte(MediaQuery.textScalerOf(context), kTegelTitel),
                child: Text(
                  widget.titel,
                  maxLines: kTegelTitelRegels,
                  overflow: TextOverflow.ellipsis,
                  style: _aan ? kTegelTitel.copyWith(color: kFel) : kTegelTitel,
                ),
              ),
              if (widget.ondertitelWidget != null)
                Align(alignment: Alignment.centerLeft, child: widget.ondertitelWidget!)
              else if (widget.ondertitel.isNotEmpty)
                Text(
                  widget.ondertitel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kTegelOnder,
                ),
            ],
          ),
        ),
      ),
    );
    final metTikken = _draaien ? DubbelTikVlak(tikken: _tikken, onDubbel: _dubbel, child: tegel) : tegel;
    return vast == null ? metTikken : SizedBox(width: vast, child: metTikken);
  }
}
