// Berichten van uploaders lezen en zelf beantwoorden — zie uploaderberichten.dart.
//
// Saber, 25-10-2026: "ja bouw maar berichten tonen en antwoorden". Op elk scherm hetzelfde: de lijst van gesprekken,
// en per uploader het gesprek met onderaan een vak om te antwoorden. Op de tv bereik je het vak en de knop met de
// pijltjes; de tekst van een uploader is te selecteren, zodat je het gevraagde woord kunt kopiëren.

import 'package:flutter/material.dart';

import '../uploaderberichten.dart';
import 'kleuren.dart';
import 'maten.dart';
import 'typografie.dart';

/// Verstuurt jouw antwoord. Null: verstuurd; anders wat er misging, in een zin.
typedef VerstuurAntwoord = Future<String?> Function(String aan, String tekst);

const _dagen = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];

/// "zo 18:39" deze week, "18-10 18:39" daarvoor — zoals SoulseekQt het toont.
@visibleForTesting
String berichtTijd(int ms, {DateTime? nu}) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  final n = nu ?? DateTime.now();
  String twee(int v) => v.toString().padLeft(2, '0');
  final uur = '${twee(t.hour)}:${twee(t.minute)}';
  if (n.difference(t) < const Duration(days: 6)) return '${_dagen[t.weekday - 1]} $uur';
  return '${twee(t.day)}-${twee(t.month)} $uur';
}

/// "Gesprek met … verwijderen?" — waar als je ja zei. Saber, 12-11-2026: *"plus verwijderen, zet als gelezen wil ik
/// erbij als optie"*. Eerst vragen: het gaat op al je toestellen weg, en een uploader die een woord vroeg kun je dan
/// niet meer antwoorden tot hij opnieuw schrijft.
Future<bool> vraagVerwijderen(BuildContext context, String uploader) async {
  final ja = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Gesprek met $uploader verwijderen?'),
      content: const Text('Het verdwijnt op al je toestellen. Schrijft deze uploader je opnieuw, dan staat het er weer.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annuleren')),
        FilledButton(
            key: const ValueKey('verwijder-ja'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Verwijderen')),
      ],
    ),
  );
  return ja == true;
}

enum _Keuze { gelezen, verwijder }

/// De lijst van gesprekken.
class BerichtenScherm extends StatelessWidget {
  const BerichtenScherm({super.key, required this.verstuur, this.lijst});

  final VerstuurAntwoord verstuur;

  /// In een toets een eigen lijst; anders die van de app.
  final Uploaderberichten? lijst;

  @override
  Widget build(BuildContext context) {
    final l = lijst ?? uploaderberichten;
    return Scaffold(
      backgroundColor: kAchtergrond,
      appBar: AppBar(backgroundColor: kAchtergrond, title: const Text('Berichten van uploaders'), actions: [
        ListenableBuilder(
          listenable: l,
          builder: (context, _) => l.ongelezen == 0
              ? const SizedBox.shrink()
              : TextButton.icon(
                  key: const ValueKey('alles-gelezen'),
                  onPressed: l.allesGelezen,
                  icon: const Icon(Icons.done_all),
                  label: const Text('Alles gelezen'),
                ),
        ),
        const SizedBox(width: kRuimte8),
      ]),
      body: ListenableBuilder(
        listenable: l,
        builder: (context, _) {
          final gesprekken = l.gesprekken;
          if (gesprekken.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(kRuimte24),
              child: Text(
                  'Nog geen berichten. Vraagt een uploader iets — zoals "type download in this chat" — dan staat het '
                  'hier, en antwoord je zelf.',
                  style: kTekstBij),
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: kRuimte8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(kRuimte16, kRuimte4, kRuimte16, kRuimte12),
                child: Text(
                    'Sommige uploaders geven pas iets als je antwoordt op hun vraag. De app antwoordt nooit vanzelf: '
                    'jij typt wat ze vragen.',
                    style: kTekstKlein),
              ),
              for (final g in gesprekken)
                ListTile(
                  key: ValueKey('gesprek-${g.uploader}'),
                  title: Row(children: [
                    Expanded(child: Text(g.uploader, style: kTekstNormaal)),
                    Text(berichtTijd(g.laatste.ms), style: kTekstKlein),
                  ]),
                  subtitle: Text('${g.laatste.vanMij ? 'Jij: ' : ''}${g.laatste.tekst}',
                      maxLines: 3, overflow: TextOverflow.ellipsis, style: kTekstBij),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (g.ongelezen > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: kRuimte8, vertical: kRuimte2),
                        decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(kHoekRond)),
                        child: Text('${g.ongelezen}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    PopupMenuButton<_Keuze>(
                      key: ValueKey('gesprek-menu-${g.uploader}'),
                      tooltip: 'Meer',
                      onSelected: (k) async {
                        if (k == _Keuze.gelezen) return l.gelezen(g.uploader);
                        if (await vraagVerwijderen(context, g.uploader)) l.verwijder(g.uploader);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          key: const ValueKey('keuze-gelezen'),
                          value: _Keuze.gelezen,
                          enabled: g.ongelezen > 0,
                          child: const ListTile(
                              leading: Icon(Icons.mark_email_read_outlined), title: Text('Zet als gelezen')),
                        ),
                        const PopupMenuItem(
                          key: ValueKey('keuze-verwijder'),
                          value: _Keuze.verwijder,
                          child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Verwijderen')),
                        ),
                      ],
                    ),
                  ]),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => GesprekScherm(uploader: g.uploader, verstuur: verstuur, lijst: lijst))),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Het gesprek met één uploader, met onderaan jouw antwoord.
class GesprekScherm extends StatefulWidget {
  const GesprekScherm({super.key, required this.uploader, required this.verstuur, this.lijst});

  final String uploader;
  final VerstuurAntwoord verstuur;
  final Uploaderberichten? lijst;

  @override
  State<GesprekScherm> createState() => _GesprekSchermState();
}

class _GesprekSchermState extends State<GesprekScherm> {
  final _tekst = TextEditingController();
  final _rol = ScrollController();
  bool _bezig = false;
  String? _fout;

  Uploaderberichten get _lijst => widget.lijst ?? uploaderberichten;

  @override
  void initState() {
    super.initState();
    _lijst.addListener(_bijWijziging);
    WidgetsBinding.instance.addPostFrameCallback((_) => _lijst.gelezen(widget.uploader));
  }

  @override
  void dispose() {
    _lijst.removeListener(_bijWijziging);
    _tekst.dispose();
    _rol.dispose();
    super.dispose();
  }

  /// Wat er binnenkomt terwijl het gesprek openstaat, is gelezen; en de lijst schuift mee naar onder.
  void _bijWijziging() {
    if (!mounted) return;
    if (_lijst.ongelezenVan(widget.uploader) > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _lijst.gelezen(widget.uploader));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_rol.hasClients) _rol.jumpTo(_rol.position.maxScrollExtent);
    });
  }

  Future<void> _stuur() async {
    final t = antwoordVoorUploader(_tekst.text);
    if (t == null || _bezig) return;
    setState(() {
      _bezig = true;
      _fout = null;
    });
    final fout = await widget.verstuur(widget.uploader, t);
    if (!mounted) return;
    setState(() {
      _bezig = false;
      _fout = fout;
      if (fout == null) _tekst.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAchtergrond,
      appBar: AppBar(backgroundColor: kAchtergrond, title: Text(widget.uploader), actions: [
        IconButton(
          key: const ValueKey('gesprek-verwijder'),
          tooltip: 'Verwijderen',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            if (!await vraagVerwijderen(context, widget.uploader)) return;
            _lijst.verwijder(widget.uploader);
            if (mounted) Navigator.of(this.context).maybePop();
          },
        ),
      ]),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: ListenableBuilder(
              listenable: _lijst,
              builder: (context, _) {
                final berichten = _lijst.gesprek(widget.uploader);
                return ListView(
                  controller: _rol,
                  padding: const EdgeInsets.all(kRuimte16),
                  children: [for (final b in berichten) _Ballon(b)],
                );
              },
            ),
          ),
          if (_fout != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kRuimte16),
              child: Text(_fout!, style: kTekstBij.copyWith(color: Colors.redAccent)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kRuimte16, kRuimte8, kRuimte16, kRuimte16),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('antwoord-veld'),
                  controller: _tekst,
                  enabled: !_bezig,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _stuur(),
                  maxLength: kAntwoordHoogstens,
                  decoration: const InputDecoration(hintText: 'Jouw antwoord', counterText: ''),
                ),
              ),
              const SizedBox(width: kRuimte12),
              FilledButton(
                key: const ValueKey('antwoord-stuur'),
                onPressed: _bezig ? null : _stuur,
                child: Text(_bezig ? 'Bezig…' : 'Stuur'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Ballon extends StatelessWidget {
  const _Ballon(this.b);
  final Uploaderbericht b;

  @override
  Widget build(BuildContext context) {
    final mij = b.vanMij;
    return Align(
      alignment: mij ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          margin: const EdgeInsets.only(bottom: kRuimte8),
          padding: const EdgeInsets.symmetric(horizontal: kRuimte12, vertical: kRuimte8),
          decoration: BoxDecoration(
            color: mij ? kAccent.withValues(alpha: .22) : kPaneelHoog,
            borderRadius: BorderRadius.circular(kHoek12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${mij ? 'Jij' : b.uploader} · ${berichtTijd(b.ms)}', style: kLabel),
            const SizedBox(height: kRuimte2),
            SelectableText(b.tekst, style: kTekstBasis),
          ]),
        ),
      ),
    );
  }
}
