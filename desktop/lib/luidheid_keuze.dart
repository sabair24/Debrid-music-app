/// Gelijk volume op het scherm: het merk op Nu speelt, het blad met de uitleg en de keuzes, de
/// instelling, en de eenmalige aankondiging.
///
/// **Waarom het merk een woord draagt.** Een kaal "−3,4 dB" naast "FLAC · 24/96" leest als verlies.
/// "Gelijk −3,4 dB" zegt wat er gebeurt en waarom, en elke andere toestand — nog niet gemeten, zacht
/// opgenomen, ongemoeid — heeft een eigen zin, zodat Saber nooit hoeft te raden of het werkt.
/// Tooltips werken op een telefoon alleen met lang drukken en op de tv niet; daarom is het merk een
/// knop die een blad opent.
library;

import 'package:flutter/material.dart';

import 'luidheid.dart';
import 'luidheid_winkel.dart' show LuidheidStatus;
import 'settings.dart';
import 'tv.dart';
import 'ui/kleuren.dart';
import 'ui/typografie.dart';

/// "−3,4 dB" / "+2,1 dB" / "±0 dB": met een echte min en een komma.
String dbTekst(double db) {
  if (db.abs() < kNulDrempel) return '±0 dB';
  final s = db.abs().toStringAsFixed(1).replaceAll('.', ',');
  return '${db < 0 ? '−' : '+'}$s dB';
}

/// De tekst van het merk. Leeg = niets tonen (stand Uit).
///
/// [opPc] en [voortgang]: vóór de eerste ronde zegt de pc zelf "meten… 40 %" en een toestel "pc meet
/// nog". [speaker]: Sonos/UPnP speelt; die krijgt het origineel. Gecast naar de Shield is een eigen
/// bron ([Bijstelbron.shield]) zonder getal: de Shield rekent zelf, met de stand van de pc.
/// [kort]: op de tv, waar alle tekst 1,35× groter is.
String luidheidMerkTekst(Bijstelling b,
    {bool opPc = false, String voortgang = '', bool speaker = false, bool kort = false}) {
  if (b.bron == Bijstelbron.uit) return '';
  if (speaker) return 'Gelijk · niet op deze speaker';
  final w = b.alsAlbum ? 'Album' : 'Gelijk';
  return switch (b.bron) {
    Bijstelbron.uit => '',
    Bijstelbron.nummer || Bijstelbron.album || Bijstelbron.klemExtra => '$w ${dbTekst(b.db)}',
    Bijstelbron.opDoel => '$w ±0 dB',
    Bijstelbron.klemNul => '$w · ongemoeid',
    Bijstelbron.geenRuimte => 'Gelijk · zacht opgenomen',
    Bijstelbron.stilte => 'Gelijk · stil nummer',
    Bijstelbron.meerkanaals => kort ? 'Gelijk · meerkanaals' : 'Gelijk · meerkanaals, ongemoeid',
    Bijstelbron.ongemeten => b.netBewerkt ? 'Gelijk · net bewerkt' : 'Gelijk · nog niet gemeten',
    Bijstelbron.online => kort ? 'Gelijk · niet gemeten' : 'Gelijk · niet gemeten (online)',
    Bijstelbron.mislukt => 'Gelijk · kon niet meten',
    Bijstelbron.pcNietKlaar =>
      opPc ? (voortgang.isEmpty ? 'Gelijk · meten…' : 'Gelijk · $voortgang') : 'Gelijk · pc meet nog',
    Bijstelbron.pcOud => 'Gelijk · werk je pc bij',
    Bijstelbron.pcZonderFfmpeg => opPc ? 'Gelijk · ffmpeg ontbreekt' : 'Gelijk · pc mist ffmpeg',
    Bijstelbron.speaker => 'Gelijk · niet op deze speaker',
    Bijstelbron.shield => 'Gelijk · op de Shield',
    Bijstelbron.mpvWeigert => 'Gelijk · werkt hier niet',
    Bijstelbron.onbekendAdres => 'Gelijk · niet toegepast',
  };
}

/// Alle merkteksten die er bestaan, voor de breedtetoets (die de LANGSTE neemt, niet een vaste).
List<String> alleLuidheidMerkTeksten({bool kort = false}) => [
      for (final bron in Bijstelbron.values)
        for (final album in [false, true])
          for (final opPc in [false, true])
            luidheidMerkTekst(
                Bijstelling(-12.3, bron, alsAlbum: album, netBewerkt: bron == Bijstelbron.ongemeten),
                opPc: opPc,
                kort: kort,
                voortgang: 'meten… 1436 van 1437'),
      luidheidMerkTekst(const Bijstelling(0, Bijstelbron.nummer), speaker: true),
    ];

/// "1,4 dB": het getal zonder teken, voor zinnen die het woord "zachter" of "harder" al dragen.
String dbGetal(double db) => '${db.abs().toStringAsFixed(1).replaceAll('.', ',')} dB';

/// De uitleg in het blad, in gewone taal. [opPc]: dit is de pc zelf (voor de zin bij casten).
String luidheidUitleg(Bijstelling b, {bool opPc = false}) {
  final m = b.meting;
  final gemeten = m == null
      ? ''
      : 'Gemeten: ${m.lufs.toStringAsFixed(1).replaceAll('.', ',')} LUFS, piek '
          '${(m.piek).toStringAsFixed(1).replaceAll('.', ',')} dB. ';
  final waarom = switch (b.bron) {
    Bijstelbron.uit => 'Gelijk volume staat uit: elk nummer speelt zoals het op de schijf staat.',
    Bijstelbron.nummer => b.db < 0
        ? 'Dit nummer is luider gemasterd dan het doel en speelt ${dbTekst(b.db)}, zodat het even hard klinkt als de rest. Geen compressie: alleen het volume.'
        : 'Dit nummer is zachter opgenomen en gaat ${dbTekst(b.db)} omhoog, zo ver als de pieken het toelaten zonder af te knippen.',
    Bijstelbron.album =>
      'Je speelt een plaat op volgorde: de plaat als geheel speelt ${dbTekst(b.albumDb ?? b.db)}, en de verschillen tussen de nummers blijven zoals de artiest ze bedoelde.',
    Bijstelbron.opDoel => 'Dit nummer zit al op het doel; er verandert niets.',
    Bijstelbron.klemNul =>
      'Dit nummer heeft pieken boven 0 dB; een kleine verlaging zou ze laten afknippen, dus blijft het zoals het is (minder dan 2 dB van de rest).',
    Bijstelbron.klemExtra => b.alsAlbum
        ? 'Dit nummer heeft pieken boven 0 dB; het staat daarom ${dbGetal(b.db - (b.albumDb ?? 0))} zachter dan de rest van de plaat, zodat er niets afknipt.'
        : 'Dit nummer heeft pieken boven 0 dB; het staat daarom iets zachter dan het doel, zodat er niets afknipt.',
    Bijstelbron.geenRuimte =>
      'Zacht opgenomen, maar de pieken zitten al tegen het maximum: harder zou vervormen. Het speelt daarom zoals het is.',
    Bijstelbron.stilte => 'Een stil of verborgen nummer: daar wordt niets aan opgeblazen.',
    Bijstelbron.meerkanaals => 'Meerkanaalsopname — speelt zoals vroeger.',
    Bijstelbron.ongemeten => b.netBewerkt
        ? 'Net bewerkt — wordt zo opnieuw gemeten. Tot dan speelt het zoals vroeger.'
        : 'Nog niet gemeten — speelt zoals vroeger.',
    Bijstelbron.online => 'Een nummer van buiten je bibliotheek; dat wordt niet gemeten en speelt zoals vroeger.',
    Bijstelbron.mislukt => 'Dit bestand kon niet gemeten worden — speelt zoals vroeger.',
    Bijstelbron.pcNietKlaar =>
      'De pc meet je bibliotheek nog (eenmalig, ~30 min). Tot dan klinkt alles zoals vroeger.',
    Bijstelbron.pcOud =>
      'Je pc doet nog niet mee: werk hem bij, dan meet hij je bibliotheek één keer (~30 min). Tot dan klinkt alles zoals vroeger.',
    Bijstelbron.pcZonderFfmpeg =>
      'ffmpeg ontbreekt op de pc, dus er wordt niets gemeten. Alles klinkt zoals vroeger.',
    Bijstelbron.speaker =>
      'Speakers (Sonos, KEF) krijgen het origineel; daar geldt hun eigen volume.',
    Bijstelbron.shield => opPc
        ? 'De Shield rekent zelf, met de instelling van deze pc. Een wijziging hier geldt de volgende keer dat je naar de Shield cast.'
        : 'De Shield rekent zelf, met de instelling van je pc — niet die van dit toestel. Een wijziging op de pc geldt de volgende keer dat je naar de Shield cast.',
    Bijstelbron.mpvWeigert => 'Gelijk volume werkt niet op dit toestel (speler te oud).',
    Bijstelbron.onbekendAdres => 'Dit nummer werd niet herkend; het speelt zoals vroeger.',
  };
  final album = (b.alsAlbum && b.albumMeting != null && b.bron != Bijstelbron.album)
      ? ' Plaat ${dbTekst(b.albumDb ?? 0)}; dit nummer ${dbTekst(b.db)}.'
      : '';
  final verzamel = b.verzamelaar ? ' Verzamelalbum — elk nummer apart.' : '';
  final zender = b.vanZender
      ? ' De stand komt van je pc; wijzig hem daar — hij geldt de volgende keer dat je naar de Shield cast.'
      : '';
  return '$gemeten$waarom$album$verzamel$zender';
}

/// Het merk op Nu speelt: een stille tekstknop die het blad opent. Leeg bij Uit.
class LuidheidMerk extends StatelessWidget {
  const LuidheidMerk({super.key, required this.tekst, required this.onPressed, this.uitlijning});
  final String tekst;
  final VoidCallback onPressed;
  final TextAlign? uitlijning;

  @override
  Widget build(BuildContext context) {
    if (tekst.isEmpty) return const SizedBox.shrink();
    return Pressable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(6),
      scaleOnFocus: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(tekst,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: uitlijning,
            style: kLabel.copyWith(color: kGedempt)),
      ),
    );
  }
}

/// De naamrij van Nu speelt — de namen, het echtheidsmerk, de kwaliteitsbadge — met het
/// gelijk-volume-merk erbij: in de rij als er breedte genoeg is (tv, brede schermen), anders op een
/// eigen regel eronder. Een eigen widget zodat hij zonder speler te toetsen is; [naam] is een slot
/// (de Nu speelt-code geeft `ArtistLine` mee).
class NuSpeeltNaamrij extends StatelessWidget {
  const NuSpeeltNaamrij({
    super.key,
    this.naam,
    this.echtheid,
    this.kwaliteit,
    this.merk,
    required this.merkInDeRij,
    required this.zij,
  });

  final Widget? naam;
  final Widget? echtheid;
  final Widget? kwaliteit;
  final Widget? merk;
  /// In de rij of op een eigen regel — zie `merkEigenRegel` in ui/speelvlak.dart.
  final bool merkInDeRij;
  final bool zij;

  @override
  Widget build(BuildContext context) {
    final inDeRij = merkInDeRij && merk != null;
    final rij = Row(
      mainAxisAlignment: zij ? MainAxisAlignment.start : MainAxisAlignment.center,
      children: [
        // Met het merk in de rij krimpen de namen én het merk allebei (3 : 2), met puntjes; een vast
        // merk liep op de tv (540 punt, tekst 1,35×) 126 punt over de rand.
        if (naam != null) Flexible(flex: inDeRij ? 3 : 1, child: naam!),
        if (echtheid != null) echtheid!,
        if (kwaliteit != null) kwaliteit!,
        if (inDeRij)
          Flexible(
            flex: 2,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: merk!),
          ),
      ],
    );
    if (merk == null || merkInDeRij) return rij;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: zij ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [rij, const SizedBox(height: 2), merk!],
    );
  }
}

/// De drie keuzes en de albumschakelaar, voor de instelling en het blad. Bewaart meteen.
class _Keuzes extends StatelessWidget {
  const _Keuzes({required this.settings, this.naWijziging});
  final AppSettings settings;
  final VoidCallback? naWijziging;

  static const _standen = [('uit', 'Uit'), ('normaal', 'Gelijk'), ('luid', 'Luider')];

  @override
  Widget build(BuildContext context) {
    final huidig = luidheidsstandUit(settings.luidheid).name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final (waarde, naam) in _standen)
              ChoiceChip(
                label: Text(naam),
                selected: huidig == waarde,
                onSelected: (aan) async {
                  if (!aan) return;
                  settings.luidheid = waarde;
                  await settings.save();
                  naWijziging?.call();
                },
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Albums als geheel', style: TextStyle(fontSize: 12.5)),
          subtitle: const Text(
            'Speel je een album op volgorde, dan blijven de verschillen tussen de nummers op die plaat '
            'zoals de artiest ze bedoelde; de plaat als geheel is even hard als de rest. '
            'Verzamelalbums gaan altijd per nummer.',
            style: TextStyle(color: kGedempt, fontSize: 11.5, height: 1.35),
          ),
          value: settings.luidheidAlbum,
          onChanged: settings.luidheid == 'uit'
              ? null
              : (v) async {
                  settings.luidheidAlbum = v;
                  await settings.save();
                  naWijziging?.call();
                },
        ),
      ],
    );
  }
}

/// De uitleg bij de instelling: eerlijk over de prijs.
const String luidheidInstellingUitleg =
    'Alles even hard zonder vervorming kan alleen door luide nummers zachter te zetten — gemiddeld '
    "zo'n 3 dB, één volumestap. Geen compressie, geen begrenzer: hetzelfde als aan de volumeknop "
    'draaien. Gelijk = zoals Spotify en TIDAL (−14 LUFS). Luider = gemiddeld even hard als vroeger, '
    'alleen uitschieters gaan omlaag; zachte opnames blijven dan wat achter (−11 LUFS). Let op bij '
    'vergelijken: Uit klinkt harder, niet beter — zet bij Gelijk je volume een stap hoger. Speakers '
    "(Sonos, KEF) krijgen het origineel. Op Windows: laat 'Luidheidsvereffening' en andere "
    'geluidsverbeteringen uit.';

/// Op de Shield, onder de instelling: de keuzes hier gelden niet voor wat de pc naar deze tv cast.
const String kLuidheidOpDeShield = 'Wat je pc naar deze tv cast, volgt de instelling van de pc.';

/// De regel onder de instelling die zegt hoe ver het is.
String luidheidStatusTekst({
  required bool eigenaar,
  ({int gemeten, int mislukt, int totaal, List<String> misluktTitels})? telling,
  bool? ffmpeg,
  String voortgang = '',
  bool klaar = false,
  LuidheidStatus? vanPc,
  bool werktNiet = false,
}) {
  if (werktNiet) return 'Gelijk volume werkt niet op dit toestel (speler te oud).';
  String mislukt(int n, List<String> titels) =>
      n == 0 ? '' : ' · $n kon niet${titels.isEmpty ? '' : ': ${titels.join(', ')}'}';
  if (eigenaar) {
    if (ffmpeg == false) return 'ffmpeg ontbreekt op deze pc — er wordt niets gemeten.';
    final t = telling;
    final basis = t == null
        ? ''
        : (klaar
            ? 'Gemeten: ${t.gemeten} van ${t.totaal}${mislukt(t.mislukt, t.misluktTitels)}'
            : 'Meten… ${t.gemeten} van ${t.totaal} — tot dan klinkt alles zoals vroeger');
    return '$basis${basis.isEmpty ? '' : '\n'}De pc meet ook als het hier op Uit staat: je telefoon '
        'gebruikt die metingen. Telefoons en tv met een oudere versie doen nog niet mee.';
  }
  final s = vanPc;
  if (s == null) return 'Je pc doet nog niet mee — werk hem bij.';
  if (!s.ffmpeg) return 'Je pc mist ffmpeg; er wordt niets gemeten.';
  if (!s.klaar && s.gemeten == 0) {
    return 'De pc begint zo met meten (~30 min) — tot dan klinkt alles zoals vroeger.';
  }
  if (!s.klaar) {
    return 'De pc meet je bibliotheek (${s.gemeten} van ${s.totaal}) — tot dan klinkt alles zoals vroeger.';
  }
  return 'De pc heeft ${s.gemeten} van ${s.totaal} nummers gemeten${mislukt(s.mislukt, s.misluktTitels)}.';
}

/// De sectie "Gelijk volume" in de instellingen.
class LuidheidKeuze extends StatelessWidget {
  const LuidheidKeuze({super.key, required this.settings, required this.status, this.naWijziging});
  final AppSettings settings;
  final String status;
  final VoidCallback? naWijziging;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Gelijk volume', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _Keuzes(settings: settings, naWijziging: naWijziging),
          const SizedBox(height: 4),
          const Text(luidheidInstellingUitleg,
              style: TextStyle(color: kGedempt, fontSize: 11.5, height: 1.35)),
          if (status.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(status, style: const TextStyle(color: kGedempt, fontSize: 11.5, height: 1.35)),
          ],
        ],
      ),
    );
  }
}

/// Het blad dat het merk opent: voor dít nummer wat er gemeten is en waarom het zo speelt, plus de
/// keuzes — live, dus meteen de A/B-knop.
///
/// Op de Shield, bij een nummer van de pc ([Bijstelling.vanZender]), staan de keuzes er niet: de stand
/// komt dan van de pc, en een knop die niets doet is erger dan geen knop.
Future<void> toonLuidheidBlad(BuildContext context,
    {required Bijstelling b, required AppSettings settings, bool opPc = false, VoidCallback? naWijziging}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: !isTv,
    builder: (ctx) => ListenableBuilder(
      listenable: settings,
      builder: (ctx, _) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Gelijk volume', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(luidheidUitleg(b, opPc: opPc),
                  style: const TextStyle(fontSize: 13, height: 1.4)),
              if (!b.vanZender) ...[
                const SizedBox(height: 12),
                _Keuzes(settings: settings, naWijziging: naWijziging),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// De eenmalige aankondiging, als SnackBar: een overlay, dus hij kost geen kolomhoogte en duwt de
/// transportrij nooit van het scherm. Niet op de tv: daar is een SnackBar niet met de
/// afstandsbediening te bedienen (main.dart, `_srcToastAction`), en het merk + blad volstaan.
///
/// [opGezien] wordt aangeroepen als er een knop is ingedrukt, als hij weggeveegd is, of als hij heeft
/// uitgestaan terwijl de app op de voorgrond was ([telAfloop]); dan komt hij niet meer terug.
/// [onLuider] null = Luider staat al aan; dan is er geen Luider-knop.
void toonLuidheidAankondiging(
  BuildContext context, {
  required double db,
  required VoidCallback? onLuider,
  required VoidCallback onUit,
  required void Function() opGezien,
  required bool Function() telAfloop,
}) {
  if (isTv) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  var gedrukt = false;
  void klaar(VoidCallback? actie) {
    gedrukt = true;
    messenger.hideCurrentSnackBar();
    actie?.call();
    opGezien();
  }

  final c = messenger.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    duration: const Duration(seconds: 20),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(luidheidAankondigingTekst(db)),
        const SizedBox(height: 6),
        Wrap(spacing: 4, children: [
          if (onLuider != null) TextButton(onPressed: () => klaar(onLuider), child: const Text('Luider')),
          TextButton(onPressed: () => klaar(onUit), child: const Text('Uit')),
          TextButton(onPressed: () => klaar(null), child: const Text('Oké')),
        ]),
      ],
    ),
  ));
  c.closed.then((reden) {
    if (gedrukt) return;
    // Wegvegen is een antwoord ("gezien, weg ermee"); anders kwam hij terug bij elke keer Nu speelt.
    final weggeveegd = reden == SnackBarClosedReason.swipe || reden == SnackBarClosedReason.dismiss;
    if (weggeveegd || (reden == SnackBarClosedReason.timeout && telAfloop())) opGezien();
  });
}

/// De tekst van de aankondiging; alleen bij een verlaging (een ophoging is geen reden om de volumeknop
/// aan te raken).
String luidheidAankondigingTekst(double db) =>
    'Gelijk volume staat aan: dit nummer speelt ${db.abs().toStringAsFixed(1).replaceAll('.', ',')} dB '
    'zachter zodat alles even hard klinkt, zoals bij Spotify en TIDAL. Zet je volume een stap hoger — '
    'nog altijd lossless.';
