/// Het scherm van een AI-lijst (ai_lijst.dart): het voorstel zien en bewerken voor er iets gedownload wordt.
///
/// Saber, 23-11-2026, koos alle vier de ontwerpen in één scherm: **Lijst** (✕ weg, ↻ ander nummer, toevoegen),
/// **Bijsturen** (een zin of een snelle knop; eerst het verschil, dan overnemen), **Keuren** (één nummer per keer, met de
/// voorproef, houden of weg) en **Mix** (de verhouding per hoek schuiven). Alles wat het scherm nodig heeft van de app —
/// de AI, het natrekken, bewaren, afspelen — komt erin geschoven.
library;

import 'package:material_ui/material_ui.dart';

import '../ai_lijst.dart';
import '../ai_lijst_vraag.dart';
import '../radio.dart' show Radioplek;
import 'kleuren.dart';
import 'voorproef_knop.dart';

/// Snelle knoppen bij Bijsturen.
const kAiLijstSnelleZinnen = ['Meer modern', 'Meer klassiekers', 'Minder bekend', 'Nog 20 zoals deze'];

class AiLijstPagina extends StatefulWidget {
  const AiLijstPagina({
    super.key,
    this.zin,
    this.voorstel,
    this.lijstId,
    required this.vrager,
    required this.natrekken,
    required this.opslaan,
    required this.afspelen,
    this.fragmentZoeker,
  });

  /// Een vers fragment voor een regel waarvan het bewaarde verlopen is (Deezer zet een vervaltijd in het adres).
  final Future<String?> Function(String artiest, String titel)? fragmentZoeker;

  /// Meteen een lijst vragen met deze zin (uit "Zeg wat je wil horen").
  final String? zin;

  /// Een bestaande lijst bewerken (een opgeslagen AI-lijst: "altijd bijsturen").
  final AiLijstVoorstel? voorstel;
  final String? lijstId;
  final AiLijstVrager vrager;

  /// Trek deze regels na (eigen, Deezer, iTunes); [voortgang] na elk stuk.
  final Future<void> Function(List<LijstNummer> nummers, void Function() voortgang) natrekken;

  /// Bewaar als afspeellijst; geeft het id terug.
  final Future<String> Function(AiLijstVoorstel v, String? lijstId) opslaan;

  /// Speel de lijst af; geeft een reden terug als het niet lukte.
  final Future<String?> Function(String lijstId) afspelen;

  @override
  State<AiLijstPagina> createState() => _AiLijstPaginaState();
}

class _AiLijstPaginaState extends State<AiLijstPagina> {
  AiLijstVoorstel? _v;
  String? _bezig;
  String? _fout;
  int _tab = 0;
  Bijsturing? _verschil;
  int _keurPlek = 0;
  int _gehouden = 0, _weggekeurd = 0;
  Map<String, int> _mix = {};
  int _mixAantal = 0;
  String? _lijstId;
  final _zin = TextEditingController();
  final _naam = TextEditingController();
  final _nieuw = TextEditingController();
  final _bij = TextEditingController();

  @override
  void initState() {
    super.initState();
    _lijstId = widget.lijstId;
    final v = widget.voorstel;
    if (v != null) {
      _zet(v);
    } else if ((widget.zin ?? '').trim().isNotEmpty) {
      _zin.text = widget.zin!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maak());
    }
  }

  @override
  void dispose() {
    _zin.dispose();
    _naam.dispose();
    _nieuw.dispose();
    _bij.dispose();
    super.dispose();
  }

  void _zet(AiLijstVoorstel v) {
    _v = v;
    _naam.text = v.naam;
    _mix = {for (final h in v.hoeken) h.naam: h.aandeel};
    _mixAantal = v.actief.length;
  }

  Future<void> _maak() async {
    final zin = _zin.text.trim();
    if (zin.isEmpty) {
      setState(() => _fout = 'Typ eerst wat voor lijst je wil.');
      return;
    }
    setState(() {
      _fout = null;
      _bezig = 'De AI stelt je lijst samen… bij een grote lijst kan dat een paar minuten duren.';
    });
    try {
      final v = await widget.vrager.maak(zin);
      if (!mounted) return;
      setState(() {
        _zet(v);
        _bezig = 'Nakijken bij Deezer en iTunes — er wordt niets gedownload…';
      });
      await widget.natrekken([...v.nummers, ...v.reserve], () {
        if (mounted) setState(() {});
      });
      pasRegelsToe(v);
      if (mounted) setState(() => _bezig = null);
    } catch (e) {
      if (mounted) {
        setState(() {
          _bezig = null;
          _fout = '$e';
        });
      }
    }
  }

  // ── Lijst ─────────────────────────────────────────────────────────────────

  void _vervang(int i) {
    final v = _v!;
    if (vervang(v, i) == null) {
      setState(() => _fout = 'De reserve is op — vraag er meer bij onder Bijsturen ("Nog 20 zoals deze").');
      return;
    }
    setState(() => _fout = null);
  }

  Future<void> _voegToe() async {
    final tekst = _nieuw.text.trim();
    final delen = tekst.split(RegExp(r'\s+[—–-]\s+'));
    if (delen.length < 2 || delen.first.trim().isEmpty || delen.last.trim().isEmpty) {
      setState(() => _fout = 'Schrijf het als "artiest — titel".');
      return;
    }
    final n = LijstNummer(artiest: delen.first.trim(), titel: delen.sublist(1).join(' - ').trim(), hoek: 'Zelf toegevoegd');
    setState(() {
      _fout = null;
      _v!.nummers.add(n);
      _nieuw.clear();
    });
    await widget.natrekken([n], () {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
  }

  // ── Bijsturen ─────────────────────────────────────────────────────────────

  Future<void> _stuur(String zin) async {
    if (zin.trim().isEmpty) {
      setState(() => _fout = 'Typ eerst wat er anders moet.');
      return;
    }
    setState(() {
      _fout = null;
      _verschil = null;
      _bezig = 'De AI kijkt wat er anders moet…';
    });
    try {
      final b = await widget.vrager.bijsturen(_v!, zin);
      await widget.natrekken(b.erbij, () {});
      for (final n in b.erbij) {
        if (n.bron == LijstBron.nergens) n.aan = false;
      }
      if (mounted) {
        setState(() {
          _bezig = null;
          _verschil = b;
          if (b.leeg) _fout = 'De AI vond niets om te veranderen.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _bezig = null;
          _fout = '$e';
        });
      }
    }
  }

  void _neemOver() {
    final b = _verschil;
    if (b == null) return;
    setState(() {
      neemBijsturingOver(_v!, b);
      _naam.text = _v!.naam;
      _verschil = null;
      _bij.clear();
    });
  }

  // ── Mix ───────────────────────────────────────────────────────────────────

  void _pasMixToe() {
    final v = _v!;
    final keuze = kiesMix(v, _mix, _mixAantal);
    final gekozen = keuze.toSet();
    setState(() {
      final rest = [for (final n in [...v.nummers, ...v.reserve]) if (!gekozen.contains(n)) n];
      v.nummers
        ..clear()
        ..addAll(keuze.map((n) => n..aan = true));
      v.reserve
        ..clear()
        ..addAll(rest);
      v.aantal = keuze.length;
      v.hoeken = [for (final h in v.hoeken) (naam: h.naam, aandeel: _mix[h.naam] ?? h.aandeel)];
      _tab = 0;
    });
  }

  // ── Bewaren en afspelen ───────────────────────────────────────────────────

  Future<String?> _bewaar() async {
    final v = _v!;
    final naam = _naam.text.trim();
    if (naam.isEmpty) {
      setState(() => _fout = 'Geef de lijst een naam.');
      return null;
    }
    v.naam = naam;
    v.verzameling ??= naam;
    setState(() => _bezig = 'Bewaren…');
    try {
      final id = await widget.opslaan(v, _lijstId);
      _lijstId = id;
      if (mounted) setState(() => _bezig = null);
      return id;
    } catch (e) {
      if (mounted) {
        setState(() {
          _bezig = null;
          _fout = '$e';
        });
      }
      return null;
    }
  }

  Future<void> _speel() async {
    final id = await _bewaar();
    if (id == null) return;
    final reden = await widget.afspelen(id);
    if (!mounted) return;
    if (reden != null) {
      setState(() => _fout = reden);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  // ── Opbouw ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final v = _v;
    return Scaffold(
      backgroundColor: kAchtergrond,
      appBar: AppBar(
        backgroundColor: kAchtergrond,
        title: Text(_lijstId == null ? 'Nieuwe lijst met AI' : 'AI-lijst bijsturen'),
      ),
      body: SafeArea(
        child: v == null ? _vraagScherm() : _voorstelScherm(v),
      ),
    );
  }

  Widget _vraagScherm() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('NIEUWE LIJST', style: TextStyle(color: kAccent2, fontWeight: FontWeight.w600, letterSpacing: 1.2, fontSize: 12)),
          const SizedBox(height: 6),
          Text('Zeg wat voor lijst je wil', style: TextStyle(color: kTekst, fontSize: 25, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Je ziet eerst wat de AI voorstelt. Er wordt niets gedownload tot je de lijst afspeelt.',
              style: TextStyle(color: kGedempt, fontSize: 15)),
          const SizedBox(height: 16),
          TextField(
            controller: _zin,
            minLines: 2,
            maxLines: 4,
            enabled: _bezig == null,
            decoration: InputDecoration(
              filled: true,
              fillColor: kVerzonken,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              hintText: 'Bijvoorbeeld: 200 kerstliedjes, klassiekers maar ook modernere',
            ),
          ),
          const SizedBox(height: 14),
          if (_bezig != null) _bezigRegel(),
          if (_fout != null) _foutRegel(),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _bezig == null ? _maak : null,
            style: FilledButton.styleFrom(backgroundColor: kAccent, minimumSize: const Size.fromHeight(48)),
            child: const Text('Maak de lijst'),
          ),
        ],
      );

  Widget _bezigRegel() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)),
          const SizedBox(width: 10),
          Expanded(child: Text(_bezig!, style: TextStyle(color: kGedempt))),
        ]),
      );

  Widget _foutRegel() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(_fout!, style: const TextStyle(color: Color(0xFFB3261E))),
      );

  Widget _voorstelScherm(AiLijstVoorstel v) {
    final actief = v.actief;
    final eigen = actief.where((n) => n.bron == LijstBron.eigen).length;
    final nergens = v.nummers.where((n) => n.bron == LijstBron.nergens).length;
    final sec = actief.fold<int>(0, (a, n) => a + (n.seconden > 0 ? n.seconden : 210));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_lijstId == null ? 'NIEUWE LIJST · VOORSTEL' : 'AI-LIJST',
                style: TextStyle(color: kAccent2, fontWeight: FontWeight.w600, letterSpacing: 1.2, fontSize: 12)),
            TextField(
              controller: _naam,
              style: TextStyle(color: kTekst, fontSize: 22, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
            ),
            Text(
                '${actief.length} nummers · ${sec ~/ 3600} u ${(sec % 3600) ~/ 60} min · $eigen al van jou · '
                '${actief.length - eigen} pas bij afspelen${nergens == 0 ? '' : ' · $nergens niet gevonden'}',
                style: TextStyle(color: kGedempt, fontSize: 13)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              for (final (i, t) in const ['Lijst', 'Bijsturen', 'Keuren', 'Mix'].indexed)
                ChoiceChip(
                  label: Text(t),
                  selected: _tab == i,
                  selectedColor: kAccent,
                  labelStyle: TextStyle(color: _tab == i ? Colors.white : kTekst),
                  onSelected: (_) => setState(() => _tab = i),
                ),
            ]),
            if (_bezig != null) _bezigRegel(),
            if (_fout != null) _foutRegel(),
          ]),
        ),
        Expanded(
          child: switch (_tab) {
            1 => _bijsturen(v),
            2 => _keuren(v),
            3 => _mixScherm(v),
            _ => _lijst(v),
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: _bezig == null ? _bewaar : null,
                style: FilledButton.styleFrom(backgroundColor: kAccent, minimumSize: const Size.fromHeight(46)),
                child: Text(_lijstId == null ? 'Opslaan als afspeellijst' : 'Bewaren'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _bezig == null ? _speel : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Speel af'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _hoes(LijstNummer n, double maat) {
    final kleur = posterKleurVoor(n.hoek);
    Widget leeg() => Container(
          width: maat,
          height: maat,
          decoration: BoxDecoration(color: kleur, borderRadius: BorderRadius.circular(maat / 6)),
          alignment: Alignment.center,
          child: Text(
              n.artiest.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => w[0]).take(2).join().toUpperCase(),
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: maat / 3)),
        );
    final h = n.hoes;
    if (h == null) return leeg();
    return ClipRRect(
      borderRadius: BorderRadius.circular(maat / 6),
      child: Image.network(h, width: maat, height: maat, fit: BoxFit.cover, errorBuilder: (_, __, ___) => leeg()),
    );
  }

  Widget _merk(LijstNummer n) {
    final (String tekst, Color achter, Color voor) = switch (n.bron) {
      LijstBron.eigen => ('in je bibliotheek', const Color(0xFFDCEFEA), const Color(0xFF00564F)),
      LijstBron.nergens => ('niet gevonden, misschien verzonnen', kVerzonken, kUitgezet),
      LijstBron.bezig => ('nakijken…', kVerzonken, kGedempt),
      LijstBron.soulseek => ('op Soulseek', kPaneelHoog, kGedempt),
      _ => ('pas bij afspelen', kPaneelHoog, kGedempt),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: achter, borderRadius: BorderRadius.circular(99)),
      child: Text(tekst, style: TextStyle(color: voor, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }

  Widget _proef(LijstNummer n, {double maat = 22}) => n.bron == LijstBron.eigen || n.bron == LijstBron.bezig
      ? const SizedBox(width: 40)
      : VoorproefKnop(
          sleutel: 'ai:${n.sleutel}',
          fragment: n.fragment,
          fragmentZoeker: widget.fragmentZoeker == null ? null : () => widget.fragmentZoeker!(n.artiest, n.titel),
          maat: maat,
          plek: Radioplek(artiest: n.artiest, titel: n.titel, seconden: n.seconden > 0 ? n.seconden : null));

  Widget _lijst(AiLijstVoorstel v) => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (var i = 0; i < v.nummers.length; i++)
            Opacity(
              opacity: v.nummers[i].aan ? 1 : 0.45,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  _hoes(v.nummers[i], 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(v.nummers[i].titel, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: kTekst, fontWeight: FontWeight.w500)),
                      Text(
                          [v.nummers[i].artiest, if (v.nummers[i].jaar != null) '${v.nummers[i].jaar}', v.nummers[i].hoek]
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: kGedempt, fontSize: 12)),
                      const SizedBox(height: 3),
                      _merk(v.nummers[i]),
                    ]),
                  ),
                  _proef(v.nummers[i]),
                  IconButton(
                      tooltip: 'Ander nummer',
                      icon: Icon(Icons.refresh_rounded, color: kGedempt),
                      onPressed: () => _vervang(i)),
                  IconButton(
                      tooltip: v.nummers[i].aan ? 'Uit de lijst' : 'Toch in de lijst',
                      icon: Icon(v.nummers[i].aan ? Icons.close_rounded : Icons.add_rounded, color: kGedempt),
                      onPressed: () => setState(() => v.nummers[i].aan = !v.nummers[i].aan)),
                ]),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _nieuw,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: kVerzonken,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    hintText: 'Nummer toevoegen: artiest — titel',
                  ),
                  onSubmitted: (_) => _voegToe(),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: _voegToe, child: const Text('Toevoegen')),
            ]),
          ),
        ],
      );

  Widget _bijsturen(AiLijstVoorstel v) {
    final b = _verschil;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Zeg wat er anders moet. Je ziet eerst wat er verandert.', style: TextStyle(color: kGedempt)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final z in kAiLijstSnelleZinnen)
            ActionChip(label: Text(z), onPressed: _bezig == null ? () => _stuur(z) : null),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _bij,
              decoration: InputDecoration(
                filled: true,
                fillColor: kVerzonken,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                hintText: 'Bijvoorbeeld: meer swing, geen kinderliedjes',
              ),
              onSubmitted: _stuur,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
              onPressed: _bezig == null ? () => _stuur(_bij.text) : null,
              style: FilledButton.styleFrom(backgroundColor: kAccent),
              child: const Text('Bijsturen')),
        ]),
        if (b != null && !b.leeg)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: kVerzonken, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Voorstel', style: TextStyle(color: kTekst, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final i in b.weg)
                Text('− ${v.nummers[i].artiest} — ${v.nummers[i].titel}',
                    style: const TextStyle(color: Color(0xFFB3261E), decoration: TextDecoration.lineThrough)),
              for (final n in b.erbij)
                Text('+ ${n.artiest} — ${n.titel}${n.bron == LijstBron.nergens ? ' (niet gevonden)' : ''}',
                    style: TextStyle(color: n.bron == LijstBron.nergens ? kUitgezet : const Color(0xFF00564F))),
              if (b.naam != null) Text('Nieuwe naam: ${b.naam}', style: TextStyle(color: kGedempt)),
              const SizedBox(height: 10),
              Row(children: [
                FilledButton(
                    onPressed: _neemOver, style: FilledButton.styleFrom(backgroundColor: kAccent), child: const Text('Overnemen')),
                const SizedBox(width: 8),
                TextButton(onPressed: () => setState(() => _verschil = null), child: const Text('Laat maar')),
              ]),
            ]),
          ),
      ],
    );
  }

  Widget _keuren(AiLijstVoorstel v) {
    final actief = v.actief;
    if (_keurPlek >= actief.length) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Klaar met keuren', style: TextStyle(color: kTekst, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('$_gehouden gehouden, $_weggekeurd weg — de lijst telt nu ${actief.length} nummers.',
              style: TextStyle(color: kGedempt)),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: () => setState(() {
                    _keurPlek = 0;
                    _gehouden = 0;
                    _weggekeurd = 0;
                  }),
              style: FilledButton.styleFrom(backgroundColor: kAccent),
              child: const Text('Opnieuw')),
        ]),
      );
    }
    final n = actief[_keurPlek];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${_keurPlek + 1} / ${actief.length}',
            textAlign: TextAlign.center, style: TextStyle(color: kAccent2, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Center(child: _hoes(n, 180)),
        const SizedBox(height: 12),
        Text(n.titel, textAlign: TextAlign.center, style: TextStyle(color: kTekst, fontSize: 20, fontWeight: FontWeight.w700)),
        Text([n.artiest, if (n.jaar != null) '${n.jaar}', n.hoek].where((s) => s.isNotEmpty).join(' · '),
            textAlign: TextAlign.center, style: TextStyle(color: kGedempt)),
        const SizedBox(height: 6),
        Center(child: _merk(n)),
        Center(child: _proef(n, maat: 34)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          OutlinedButton.icon(
            onPressed: () => setState(() {
              n.aan = false;
              _weggekeurd++;
            }),
            icon: const Icon(Icons.close_rounded),
            label: const Text('Weg'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: () => setState(() {
              _keurPlek++;
              _gehouden++;
            }),
            style: FilledButton.styleFrom(backgroundColor: kAccent),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Houden'),
          ),
        ]),
      ],
    );
  }

  Widget _mixScherm(AiLijstVoorstel v) {
    final pool = [...v.nummers, ...v.reserve].where((n) => n.bron != LijstBron.nergens).length;
    final som = _mix.values.fold<int>(0, (a, b) => a + b);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Schuif de verhouding; de lijst volgt, uit het voorstel en de reserve.', style: TextStyle(color: kGedempt)),
        const SizedBox(height: 10),
        for (final h in v.hoeken)
          Row(children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: posterKleurVoor(h.naam), borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            SizedBox(width: 120, child: Text(h.naam, overflow: TextOverflow.ellipsis, style: TextStyle(color: kTekst))),
            Expanded(
              child: Slider(
                value: (_mix[h.naam] ?? 0).toDouble(),
                max: 100,
                divisions: 20,
                activeColor: kAccent,
                onChanged: (x) => setState(() => _mix[h.naam] = x.round()),
              ),
            ),
            SizedBox(
                width: 44,
                child: Text(som == 0 ? '0%' : '${((_mix[h.naam] ?? 0) * 100 / som).round()}%',
                    textAlign: TextAlign.right, style: TextStyle(color: kGedempt))),
          ]),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(width: 138, child: Text('Aantal nummers', style: TextStyle(color: kTekst))),
          Expanded(
            child: Slider(
              value: _mixAantal.clamp(1, pool < 1 ? 1 : pool).toDouble(),
              min: 1,
              max: (pool < 2 ? 2 : pool).toDouble(),
              activeColor: kAccent,
              onChanged: (x) => setState(() => _mixAantal = x.round()),
            ),
          ),
          SizedBox(width: 44, child: Text('$_mixAantal', textAlign: TextAlign.right, style: TextStyle(color: kGedempt))),
        ]),
        const SizedBox(height: 10),
        FilledButton(
            onPressed: _pasMixToe,
            style: FilledButton.styleFrom(backgroundColor: kAccent, minimumSize: const Size.fromHeight(44)),
            child: const Text('Mix toepassen')),
      ],
    );
  }
}

/// Een vaste, rustige kleur per hoek (voor hoezen zonder beeld en de mix): uit de naam, zodat een hoek overal dezelfde is.
Color posterKleurVoor(String hoek) {
  const kleuren = [Color(0xFF8A3B2E), Color(0xFF2E5A8A), Color(0xFF5B3CE0), Color(0xFF00796F), Color(0xFF7A5A1E), Color(0xFF6B4E71)];
  var h = 0;
  for (final c in hoek.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return kleuren[h % kleuren.length];
}
