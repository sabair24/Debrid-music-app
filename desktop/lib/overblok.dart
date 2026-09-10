/// De biografie op de artiestpagina: een venster dat opengaat, met een jaarlint eronder.
///
/// **Waarom dit een eigen bestand is.** Het stond als methode `_overBlok` op een `State` in een
/// bestand van 23.000 regels. Deze versie bezit een animatiecontroller, een open/dicht-stand, een
/// harmonica van secties en een beeld dat meebeweegt — en dat is precies het soort ding dat een
/// toets moet kunnen pompen zonder de hele artiestpagina, met haar drie catalogi en haar speler,
/// eromheen te bouwen.
///
/// # De vololgorde is de oplossing, niet de versiering
///
/// Uitgeklapt staat het lint en het beeld BOVEN de secties:
///
/// 1. feitenstrook · 2. inleiding · 3. **jaarlint** · 4. **beeldband** · 5. secties · 6. bron
///
/// Stonden de secties erboven, dan duwt één opengeklapte sectie het lint tot duizenden punten naar
/// beneden en van het scherm af — en dan is het ding waar dit hele blok om draait onbereikbaar
/// zodra je iets leest. Zo groeit alleen het gebied ónder de twee dingen die er toe doen.
///
/// # Eén sectie tegelijk
///
/// Een harmonica en geen verzameling open panelen. Dat begrenst de hoogte per constructie tot
/// `inleiding + N kopregels + één lichaam` — nodig, want dit blok woont in een `SliverToBoxAdapter`
/// en die geeft zijn kind een onbegrensde hoogte: alles wat open staat wordt elk frame ingedeeld en
/// getekend. Gemeten op het Nederlandse artikel van Michael Jackson: 37.367 tekens in 26 secties.
/// Allemaal tegelijk open is twintigduizend punten tekst.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'artwork.dart' show decodeWidth;
import 'enrichment.dart' show ArtiestFeiten;
import 'jaarlint.dart';
import 'tv.dart';
import 'ui/kleuren.dart';
import 'ui/maten.dart';
import 'ui/typografie.dart';
import 'wikipedia.dart';

/// De leesmaat van de tekstkolom.
///
/// 820 en niet "wat er over is": dezelfde maat die `BioText` al aanhield, en het is de breedte
/// waarop een regel van 13,5 punten nog in één oogopslag te volgen is. Op een breed venster zou de
/// tekst anders over elfhonderd punten uitlopen en dan raak je bij elke regelovergang de draad
/// kwijt.
const double kLeesmaat = 820;

/// De hoogte van de beeldband onder het lint.
const double kBandHoogte = 340;

/// Hoe breed de foto naast de tekst staat zolang het blok dicht is.
const double kZijfoto = 460;

class OverBlok extends StatefulWidget {
  const OverBlok({
    super.key,
    required this.naam,
    this.artikel,
    this.audiodbTekst,
    this.feiten,
    this.jaren = const [],
    this.beginJaar,
    this.beeldVoorJaar,
    this.foto,
    this.marge = 56,
  });

  /// Welk jaartal er aan staat voordat je zelf iets aanwijst.
  ///
  /// **Nodig, want "de laatste plaat" is een slechte keuze.** Op het scherm gezien op 10-09-2026:
  /// bij Michael Jackson landde de band op 2026 — een postume verzamelaar die hij niet in zijn
  /// bibliotheek heeft, dus zonder hoes en met een Engelse tekst. De pagina wéét welke platen van
  /// jou zijn en kan dus een betere openingszet doen; dit blok niet.
  final int? beginJaar;

  final String naam;

  /// Wikipedia, als er een artikel is. Wint van [audiodbTekst] — zie `wikipedia.dart` voor de
  /// meting waarom.
  final WikiArtikel? artikel;

  /// De oude bron. Blijft de terugval: niet elke act heeft een Wikipedia-pagina.
  final String? audiodbTekst;

  final ArtiestFeiten? feiten;
  final List<Jaarpunt> jaren;

  /// Wat er in de beeldband komt te staan voor een gekozen jaartal.
  ///
  /// **Geïnjecteerd en niet hier opgelost.** Van een jaartal naar een beeld komen betekent de eigen
  /// bibliotheek doorzoeken, hoezen uit een cache halen, een albumtekst opzoeken en `AlbumArt` met
  /// de goede vastgezette persing voeden — allemaal dingen die op de artiestpagina thuishoren en
  /// niet in een tekstblok. En het maakt de widgettoets goedkoop: die geeft een stomp door dat een
  /// gekleurd vlak teruggeeft.
  ///
  /// De TELLER erbij is wat een klik van een hertekening onderscheidt. Hij loopt op bij elke tik in
  /// het lint, ook als je hetzelfde jaartal opnieuw aanwijst — en dat is precies het geval waarin de
  /// cd anders niet opnieuw uit de hoes komt en het gebaar dood leest. Zie `AlbumArt.uitschuifTeller`.
  final Widget Function(Jaarpunt punt, int teller)? beeldVoorJaar;

  /// Het beeld naast de tekst zolang het blok dicht is. Bij het openklappen schuift het weg en
  /// neemt de beeldband zijn plek over.
  final Uint8List? foto;

  final double marge;

  @override
  State<OverBlok> createState() => _OverBlokState();
}

class _OverBlokState extends State<OverBlok> with SingleTickerProviderStateMixin {
  bool _open = false;

  /// Welke sectie openstaat. Een `int?` en geen verzameling: zie de uitleg bovenaan.
  ///
  /// Op index en niet op kop, zodat een artikel met twee gelijke koppen niet twee secties tegelijk
  /// opent — dat komt voor bij artikelen met genest "Zie ook" onder verschillende hoofdstukken.
  int? _openSectie;

  AnimationController? _c;
  late Animation<double> _curve;

  final _sectieSleutels = <int, GlobalKey>{};

  /// Het jaartal dat de band toont.
  int? _jaar;

  /// Hoe vaak er in het lint getikt is. Zie [OverBlok.beeldVoorJaar].
  int _tikken = 0;

  @override
  void initState() {
    super.initState();
    _kiesBeginJaar();
  }

  @override
  void didUpdateWidget(OverBlok oud) {
    super.didUpdateWidget(oud);
    // De jaartallen komen binnendruppelen terwijl drie catalogi antwoorden. Zolang er nog niets
    // gekozen is hoort de band mee te schuiven met wat er binnenkomt; heeft de gebruiker zelf een
    // jaar aangewezen, dan blijft dat staan ook al verandert de lijst eromheen.
    if (_jaar == null || !widget.jaren.any((p) => p.jaar == _jaar)) _kiesBeginJaar();
  }

  void _kiesBeginJaar() {
    if (widget.beginJaar != null && widget.jaren.any((p) => p.jaar == widget.beginJaar)) {
      _jaar = widget.beginJaar;
      return;
    }
    final platen = widget.jaren.where((p) => p.soort == Jaarsoort.plaat);
    _jaar = platen.isNotEmpty ? platen.last.jaar : widget.jaren.lastOrNull?.jaar;
  }

  /// Of er geanimeerd mag worden.
  ///
  /// Op één plek beslist, en bij nee wordt de controller HELEMAAL NIET aangemaakt — niet een
  /// controller met duur nul. Een ongebruikte `Ticker` per widget is precies de verspilling die
  /// `tv.dart` aanwijst, en op een televisie staan er daar veel van.
  bool _magBewegen(BuildContext c) => !MediaQuery.of(c).disableAnimations && !isTv;

  void _zorgVoorController() {
    if (_c != null) return;
    _c = AnimationController(vsync: this, duration: kOvergang);
    // CurveTween().animate() en GEEN CurvedAnimation: die heeft sinds Flutter 3.13 een eigen
    // dispose, en eentje per build is een lek dat de toetsomgeving terecht meldt. Zie
    // `navigatie.dart`, waar dezelfde afweging staat.
    _curve = CurveTween(curve: Curves.easeOutCubic).animate(_c!);
    // Zodra hij helemaal dicht is: één hertekening, zodat de staart ook echt uit de boom gaat. De
    // `AnimatedBuilder` eronder tekent hem dan wel niet meer, maar bouwen zou hij hem blijven.
    _c!.addStatusListener((s) {
      if (s == AnimationStatus.dismissed && mounted) setState(() {});
    });
  }

  void _wissel() {
    setState(() {
      _open = !_open;
      // Dicht? Dan ook de sectie dicht. Anders meet `Align(heightFactor:)` bij de VOLGENDE opening
      // elke frame een kind van twintigduizend punten, want de uitklap begint dan met een sectie al
      // open. Elke uitklap begint schoon.
      if (!_open) _openSectie = null;
    });
    if (_c == null) return;
    _open ? _c!.forward() : _c!.reverse();
  }

  void _wisselSectie(int i) {
    setState(() => _openSectie = _openSectie == i ? null : i);
    if (_openSectie != i) return;
    // Na het frame, want de kop staat nu nog op zijn oude plek. Zonder dit klapt er iets open
    // "ergens", en op een lange lijst koppen is dat buiten beeld.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _sectieSleutels[i]?.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(ctx,
          alignment: .1,
          duration: _magBewegen(context) ? kOvergang : Duration.zero,
          curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  // ── Tekst ─────────────────────────────────────────────────────────────────

  String get _inleiding =>
      (widget.artikel?.intro.trim().isNotEmpty ?? false)
          ? widget.artikel!.intro.trim()
          : (widget.audiodbTekst ?? '').trim();

  List<WikiAfdeling> get _secties => widget.artikel?.afdelingen ?? const [];

  /// De eerste alinea, die ook ingeklapt te lezen is.
  String get _eersteAlinea {
    final t = _inleiding;
    final knip = t.indexOf('\n');
    return knip < 0 ? t : t.substring(0, knip).trim();
  }

  String get _restVanDeInleiding {
    final t = _inleiding;
    final knip = t.indexOf('\n');
    return knip < 0 ? '' : t.substring(knip).trim();
  }

  @override
  Widget build(BuildContext context) {
    final smal = isCompact(context);
    final beweegt = _magBewegen(context);
    if (beweegt) _zorgVoorController();
    if (_inleiding.isEmpty && _secties.isEmpty) return const SizedBox.shrink();

    final marge = smal ? 18.0 : widget.marge;
    final deel = beweegt ? _curve : const AlwaysStoppedAnimation<double>(1);
    final open = beweegt ? null : _open; // zonder animatie beslist de stand zelf

    return Padding(
      padding: EdgeInsets.fromLTRB(marge, 0, marge, smal ? 20 : 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.feiten != null && !widget.feiten!.isEmpty)
            _FeitenStrook(feiten: widget.feiten!),
          _vlak(smal: smal, beweegt: beweegt, deel: deel, open: open),
          _staart(smal: smal, beweegt: beweegt, deel: deel, open: open),
          const SizedBox(height: 18),
          _MeerLezen(open: _open, onTik: _wissel),
        ],
      ),
    );
  }

  /// De foto links en de tekstkolom rechts. Bij het openklappen krimpt de foto weg.
  Widget _vlak({
    required bool smal,
    required bool beweegt,
    required Animation<double> deel,
    required bool? open,
  }) {
    final kolom = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kLeesmaat),
      child: Text(_eersteAlinea, style: _bioStijl),
    );
    if (widget.foto == null || smal || isTv) {
      return Align(alignment: Alignment.topLeft, child: kolom);
    }
    // **De tekst LINKS en de foto rechts.** Andersom stond de tekst ingesprongen achter een beeld
    // van 460 punten, en dan komt "Meer lezen" — dat onder het hele blok hangt — helemaal links
    // onder de FOTO te staan, ver van de alinea die hij openklapt. Op het scherm gezien op
    // 10-09-2026: het leest als een losse link die nergens bij hoort. Zo begint de tekst gewoon bij
    // de marge en staat de uitklapper eronder waar je hem verwacht.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Align(alignment: Alignment.topLeft, child: kolom)),
        // ClipRect + Align en geen AnimatedContainer: dit is een VERMENIGVULDIGING op een vaste
        // maat, dus er wordt niets gemeten. De foto verdwijnt terwijl de beeldband eronder zijn
        // plek overneemt — één beeld dat verhuist, geen twee die vechten.
        //
        // **Ook `heightFactor`, en dat bleek pas op het scherm.** Met alleen `widthFactor` krimpt
        // het vak in de breedte maar houdt het zijn HOOGTE: uitgeklapt bleef er een gat van 259
        // punten naast de eerste alinea staan, alsof er iets niet geladen was.
        AnimatedBuilder(
          animation: deel,
          builder: (_, kind) {
            final over = 1 - (open == null ? deel.value : (open ? 1.0 : 0.0));
            if (over <= 0) return const SizedBox.shrink();
            return ClipRect(
              child: Align(
                alignment: Alignment.topRight,
                widthFactor: over,
                heightFactor: over,
                child: Opacity(opacity: over, child: kind),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(left: 48),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kHoek4),
              child: SizedBox(
                width: kZijfoto,
                height: kZijfoto * 9 / 16,
                child: Image.memory(widget.foto!,
                    fit: BoxFit.cover,
                    cacheWidth: decodeWidth(kZijfoto),
                    errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Alles wat pas bij het openklappen te zien is.
  Widget _staart({
    required bool smal,
    required bool beweegt,
    required Animation<double> deel,
    required bool? open,
  }) {
    // **Helemaal dicht is helemaal niet bouwen.** `Align(heightFactor: 0)` verbergt zijn kind wel
    // maar meet en bouwt het nog steeds: zesentwintig secties, een lint en een beeldband, ingedeeld
    // voor een blok dat je niet ziet. Erger nog, ze zijn dan ook aantikbaar en vindbaar — een knop
    // die reageert op iets wat niemand kan zien.
    final zichtbaar = open ?? (_open || deel.value > 0);
    if (!zichtbaar) return const SizedBox.shrink();

    final inhoud = RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_restVanDeInleiding.isNotEmpty) ...[
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kLeesmaat),
              child: Text(_restVanDeInleiding, style: _bioStijl),
            ),
          ],
          if (widget.jaren.isNotEmpty) ...[
            const SizedBox(height: kRuimte24),
            _JaarLint(
              punten: widget.jaren,
              gekozen: _jaar,
              onKies: (j) => setState(() {
                _jaar = j;
                _tikken++;
              }),
            ),
            if (widget.beeldVoorJaar != null) ...[
              const SizedBox(height: kRuimte16),
              _JaarBeeld(
                punt: widget.jaren.firstWhere((p) => p.jaar == _jaar,
                    orElse: () => widget.jaren.first),
                teller: _tikken,
                bouw: widget.beeldVoorJaar!,
                beweegt: beweegt,
              ),
            ],
          ],
          if (_secties.isNotEmpty) ...[
            const SizedBox(height: kRuimte24),
            for (var i = 0; i < _secties.length; i++)
              _SectieRij(
                sleutel: _sectieSleutels.putIfAbsent(i, GlobalKey.new),
                afdeling: _secties[i],
                open: _openSectie == i,
                onTik: () => _wisselSectie(i),
              ),
          ],
          if (widget.artikel != null) ...[
            const SizedBox(height: kRuimte16),
            _Bronvermelding(artikel: widget.artikel!),
          ],
        ],
      ),
    );

    if (open != null) return open ? inhoud : const SizedBox.shrink();
    return ClipRect(
      child: AnimatedBuilder(
        animation: deel,
        builder: (_, kind) => Align(
          alignment: Alignment.topLeft,
          heightFactor: deel.value,
          child: Opacity(opacity: deel.value, child: kind),
        ),
        child: inhoud,
      ),
    );
  }
}

const TextStyle _bioStijl =
    TextStyle(fontSize: 13.5, height: 1.68, color: Color(0xFFC7CBDA));

// ── De feiten ───────────────────────────────────────────────────────────────

class _FeitenStrook extends StatelessWidget {
  const _FeitenStrook({required this.feiten});
  final ArtiestFeiten feiten;

  @override
  Widget build(BuildContext context) {
    // **Geboren gaat vóór opgericht, en het jaartal alleen telt ook.** Op het scherm gezien op
    // 10-09-2026: bij Michael Jackson stond er "OPGERICHT 1964", terwijl de app 1958 gewoon in
    // huis had. `strBorn` was leeg maar `intBornYear` niet, en de strook keek alleen naar die
    // eerste. Voor iemand met één lid leest "opgericht" bovendien als een band.
    final geboren = feiten.geboren ?? (feiten.geborenJaar == null ? null : '${feiten.geborenJaar}');
    final paren = <(String, String)>[
      if (geboren != null) ('GEBOREN', geboren),
      if (feiten.opgerichtJaar case final j? when geboren == null) ('OPGERICHT', '$j'),
      if (feiten.land case final l?) ('LAND', l),
      if (feiten.actief case final a?) ('ACTIEF', a),
      if (feiten.label case final l?) ('LABEL', l),
    ];
    if (paren.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: kRuimte24),
      child: Wrap(
        spacing: 40,
        runSpacing: kRuimte8,
        children: [
          for (final (label, waarde) in paren)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: kOpschrift),
                const SizedBox(height: 3),
                Text(waarde, style: kTekstNormaal),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Het jaarlint ────────────────────────────────────────────────────────────

class _JaarLint extends StatelessWidget {
  const _JaarLint({required this.punten, required this.gekozen, required this.onKies});
  final List<Jaarpunt> punten;
  final int? gekozen;
  final ValueChanged<int> onKies;

  @override
  Widget build(BuildContext context) {
    // Horizontaal schuivend en niet uitgerekt: bij vierentwintig punten op een smal venster wordt
    // elk blokje anders zo smal dat er van het jaartal niets overblijft. Op een televisie levert
    // een rij Pressables bovendien gratis D-pad-verkeer op, want die schuift zichzelf in beeld.
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: punten.length,
        separatorBuilder: (_, __) => const SizedBox(width: kRuimte8),
        itemBuilder: (_, i) {
          final p = punten[i];
          final aan = p.jaar == gekozen;
          return Pressable(
            onPressed: () => onKies(p.jaar),
            borderRadius: BorderRadius.circular(kHoek4),
            ringOnFocus: true,
            // **Een VASTE breedte, en dat is geen detail.** Het gekozen jaartal wordt groter (19
            // tegen 15), en bij een blokje dat zich naar zijn inhoud voegt duwt dat alles rechts
            // ervan opzij: je klikt op 1982 en 1987 springt weg onder je muis. Met een vaste maat
            // groeit de tekst binnen zijn eigen vak en blijft de rij staan.
            //
            // En een vaste HOOGTE met de inhoud onderaan, zodat de streepjes onder elkaar op één
            // lijn liggen. Zonder dat hangt het gekozen streepje lager dan de rest, puur omdat zijn
            // jaartal een paar punten hoger is.
            child: SizedBox(
              width: 132,
              height: 58,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: kGebaar,
                    curve: Curves.easeOut,
                    style: TextStyle(
                      fontSize: aan ? 19 : 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.2,
                      color: aan ? kTekst : kGedempt,
                    ),
                    child: Text('${p.jaar}'),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: aan ? kAccent : const Color(0xFF6C7387)),
                  ),
                  const SizedBox(height: 6),
                  // Het spoor loopt door onder alle blokjes; alleen het gekozen punt heeft een stip.
                  Container(
                    height: 2,
                    width: aan ? 26 : 12,
                    decoration: BoxDecoration(
                      color: aan ? kAccent : kLijn,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Het beeld onder het lint: traag inzoomend, kruisvervagend bij een nieuw jaartal.
class _JaarBeeld extends StatefulWidget {
  const _JaarBeeld(
      {required this.punt, required this.teller, required this.bouw, required this.beweegt});
  final Jaarpunt punt;
  final int teller;
  final Widget Function(Jaarpunt, int) bouw;
  final bool beweegt;

  @override
  State<_JaarBeeld> createState() => _JaarBeeldState();
}

class _JaarBeeldState extends State<_JaarBeeld> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Widget? _vorig;

  /// De zoom die het vertrekkende beeld had bereikt.
  ///
  /// Zonder dit springt de oude laag bij het wisselen terug naar schaal 1 en leest de vervaging als
  /// een sprong in plaats van een overgang.
  double _vorigeZoom = 1;

  @override
  void initState() {
    super.initState();
    if (widget.beweegt) {
      _c = AnimationController(vsync: this, duration: kKenBurns)..forward();
    }
  }

  @override
  void didUpdateWidget(_JaarBeeld oud) {
    super.didUpdateWidget(oud);
    if (oud.punt.jaar == widget.punt.jaar) return;
    _vorigeZoom = _zoom;
    _vorig = oud.bouw(oud.punt, oud.teller);
    _c?.forward(from: 0);
    if (_c == null) setState(() {});
  }

  double get _zoom => 1 + .08 * (_c?.value ?? 1);

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nieuw = widget.bouw(widget.punt, widget.teller);
    if (_c == null) {
      return SizedBox(height: kBandHoogte, width: double.infinity, child: nieuw);
    }
    // Twee FadeTransitions en geen kale Opacity: die laatste zet voor elk frame een `saveLayer` op,
    // en dat is bij een beeld van deze maat het duurste wat er is.
    final in_ = CurveTween(curve: const Interval(0, kVervaagAandeel, curve: Curves.easeOut))
        .animate(_c!);
    return RepaintBoundary(
      child: SizedBox(
        height: kBandHoogte,
        width: double.infinity,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_vorig != null)
                FadeTransition(
                  opacity: ReverseAnimation(in_),
                  child: Transform.scale(scale: _vorigeZoom, child: _vorig),
                ),
              AnimatedBuilder(
                animation: _c!,
                builder: (_, kind) => FadeTransition(
                  opacity: in_,
                  child: Transform.scale(scale: _zoom, child: kind),
                ),
                child: nieuw,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── De secties ──────────────────────────────────────────────────────────────

class _SectieRij extends StatelessWidget {
  const _SectieRij({
    required this.sleutel,
    required this.afdeling,
    required this.open,
    required this.onTik,
  });

  final GlobalKey sleutel;
  final WikiAfdeling afdeling;
  final bool open;
  final VoidCallback onTik;

  @override
  Widget build(BuildContext context) {
    // Niveau 3 en dieper springen in, zodat een onderdeel niet even zwaar leest als het hoofdstuk
    // erboven. Meer dan één trap wordt een trappenhuis; vandaar de klem.
    final inspring = ((afdeling.niveau - 2).clamp(0, 1)) * kRuimte24;
    return Padding(
      key: sleutel,
      padding: EdgeInsets.only(left: inspring.toDouble()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Pressable(
              onPressed: onTik,
              borderRadius: BorderRadius.circular(kHoek4),
              ringOnFocus: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(afdeling.kop.toUpperCase(), style: kOpschrift.copyWith(color: kTekst)),
                  const SizedBox(width: kRuimte8),
                  AnimatedRotation(
                    turns: open ? .5 : 0,
                    duration: kSnel,
                    curve: Curves.easeOut,
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 16, color: kGedempt),
                  ),
                ]),
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(bottom: kRuimte16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kLeesmaat),
                child: Text(afdeling.tekst, style: _bioStijl),
              ),
            ),
          Container(height: 1, color: kLijnZacht),
        ],
      ),
    );
  }
}

// ── De uitklapper en de bron ────────────────────────────────────────────────

class _MeerLezen extends StatelessWidget {
  const _MeerLezen({required this.open, required this.onTik});
  final bool open;
  final VoidCallback onTik;

  @override
  Widget build(BuildContext context) {
    // Align BUITEN de Pressable, en dat is geen stijlkwestie: een ondoorzichtige raaktest over de
    // volle rijbreedte zette een handcursor honderden punten van elke letter vandaan. Diezelfde
    // reparatie staat bij `BioText` uitgeschreven.
    return Align(
      alignment: Alignment.topLeft,
      child: Pressable(
        onPressed: onTik,
        borderRadius: BorderRadius.circular(kHoek4),
        ringOnFocus: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(open ? 'Minder lezen' : 'Meer lezen',
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: kAccent)),
          const SizedBox(width: 4),
          AnimatedRotation(
            turns: open ? .5 : 0,
            duration: kSnel,
            curve: Curves.easeOut,
            child: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: kAccent),
          ),
        ]),
      ),
    );
  }
}

/// De bronvermelding. **Onvoorwaardelijk**, en dat is geen ontwerpkeuze maar een voorwaarde.
///
/// Wikipedia's tekst staat onder CC BY-SA. Wordt deze regel verborgen zodra het blok dichtklapt, of
/// weggelaten op een televisie, of overgeslagen bij een kort artikel, dan verspreidt de app
/// andermans tekst zonder vermelding. Er is geen geval waarin dat mag.
class _Bronvermelding extends StatelessWidget {
  const _Bronvermelding({required this.artikel});
  final WikiArtikel artikel;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: kRuimte8),
        child: Text(
          'Tekst van Wikipedia (${artikel.taal}) · CC BY-SA 4.0 · ${artikel.titel}',
          style: kOpschrift.copyWith(letterSpacing: .3),
        ),
      );
}
