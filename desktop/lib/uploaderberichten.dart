/// Berichten van uploaders op Soulseek, en wat je terugschreef.
///
/// Saber, 25-10-2026, met drie schermafdrukken uit SoulseekQt: uploaders met een hulpje tegen automatisch downloaden
/// ("ProveIt", een plug-in voor Nicotine+) vragen eerst iets terug — *"please type "download" in this chat"*, *"type
/// the word between these brackets: [ messy ]"*, *"Reply only with this word: BEST."* — en geven pas daarna iets.
/// DebridMusic kreeg die berichten ook, maar toonde ze nergens en bevestigde ze niet: wie zo'n vraag stelde, gaf de app
/// nooit iets (thisisphyne en messiestgaze al sinds vrijdag), en de server stuurde ze bij elke login opnieuw. Om te
/// antwoorden moest Saber DebridMusic sluiten en SoulseekQt openen — twee programma's op één account gooien elkaar
/// van de server. Saber: *"ja bouw maar berichten tonen en antwoorden"*.
///
/// **Jij antwoordt, niet de app.** Zo'n vraag is er om programma's die zonder mens downloaden buiten te houden; de app
/// toont hem en verstuurt wat jij typt, en niets vanzelf.
///
/// Op de pc vult de Soulseek-verbinding de lijst (`SoulseekClient.bijBericht`) en staat hij op schijf
/// (`soulseek_berichten.json`); een toestel haalt hem bij de pc op (`/api/soulseek/berichten`) en antwoordt via de pc
/// (`/api/soulseek/bericht`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'paths.dart';

/// Zoveel berichten blijven bewaard; de oudste gaan eerst.
const int kBerichtenBewaard = 300;

/// Een antwoord is hoogstens zo lang: een uploader vraagt één woord, en de server hoeft geen opstel te bezorgen.
const int kAntwoordHoogstens = 500;

/// Eén bericht: van een uploader ([vanMij] onwaar), of jouw antwoord aan hem.
@immutable
class Uploaderbericht {
  const Uploaderbericht(
      {required this.id, required this.ms, required this.uploader, required this.tekst, this.vanMij = false});

  /// Het nummer dat de server gaf (0 voor wat jij stuurde).
  final int id;

  /// Wanneer, in milliseconden sinds 1970.
  final int ms;

  /// Met wie het gesprek is: de afzender, of bij jouw antwoord de ontvanger.
  final String uploader;
  final String tekst;
  final bool vanMij;

  Map<String, dynamic> toJson() => {'id': id, 'ms': ms, 'u': uploader, 't': tekst, if (vanMij) 'mij': true};

  static Uploaderbericht? uitJson(Object? j) {
    if (j is! Map) return null;
    final u = j['u'], t = j['t'], ms = j['ms'];
    if (u is! String || u.isEmpty || t is! String || ms is! int) return null;
    final id = j['id'];
    return Uploaderbericht(id: id is int ? id : 0, ms: ms, uploader: u, tekst: t, vanMij: j['mij'] == true);
  }

  /// Hetzelfde bericht, ook als de server het opnieuw stuurt (na een login die het niet bevestigde): zelfde afzender en
  /// zelfde nummer; zonder nummer zelfde tijd en tekst.
  bool zelfdeAls(Uploaderbericht o) =>
      uploader == o.uploader && vanMij == o.vanMij && (id != 0 && o.id != 0 ? id == o.id : ms == o.ms && tekst == o.tekst);
}

/// Eén gesprek in de lijst: met wie, het laatste bericht, en hoeveel ervan je nog niet las.
typedef Uploadergesprek = ({String uploader, Uploaderbericht laatste, int ongelezen});

/// De berichten, oudste eerst. Luister ernaar voor het scherm; [nieuw] meldt elk bericht dat er net bij kwam.
class Uploaderberichten extends ChangeNotifier {
  Uploaderberichten({this.bestand});

  /// Waar de lijst op schijf staat; null: alleen in het geheugen (een toestel, en elke toets).
  final File? bestand;

  final List<Uploaderbericht> _alle = [];

  /// Tot wanneer je alles las (ms), per uploader.
  final Map<String, int> _gelezenTot = {};

  /// Het laatste bericht van een uploader dat er net bij kwam — voor de melding onderaan het scherm.
  final ValueNotifier<Uploaderbericht?> nieuw = ValueNotifier<Uploaderbericht?>(null);

  List<Uploaderbericht> get alle => List.unmodifiable(_alle);

  /// Gaat omhoog bij elk nieuw bericht. Een toestel noemt de versie die het heeft, en krijgt de lijst alleen als die
  /// veranderd is. Niet "alles na tijdstip X": een bericht dat de server na een login opnieuw bezorgt, draagt de tijd
  /// van toen (dat van vrijdag kwam zondag binnen), en zou dan nooit aankomen. Begint bij de klok, zodat een pc die
  /// opnieuw startte nooit de versie noemt die een toestel van vroeger nog heeft.
  int versie = DateTime.now().millisecondsSinceEpoch;

  int ongelezenVan(String uploader) =>
      _alle.where((b) => b.uploader == uploader && !b.vanMij && b.ms > (_gelezenTot[uploader] ?? 0)).length;

  int get ongelezen => {for (final b in _alle) b.uploader}.fold(0, (n, u) => n + ongelezenVan(u));

  /// De gesprekken, het laatst bijgewerkte eerst.
  List<Uploadergesprek> get gesprekken {
    final laatste = <String, Uploaderbericht>{};
    for (final b in _alle) {
      final l = laatste[b.uploader];
      if (l == null || b.ms >= l.ms) laatste[b.uploader] = b;
    }
    final uit = [for (final e in laatste.entries) (uploader: e.key, laatste: e.value, ongelezen: ongelezenVan(e.key))];
    uit.sort((a, b) => b.laatste.ms.compareTo(a.laatste.ms));
    return uit;
  }

  /// Het gesprek met [uploader], oudste eerst.
  List<Uploaderbericht> gesprek(String uploader) => [for (final b in _alle) if (b.uploader == uploader) b];

  /// Erbij, tenzij hij er al is ([Uploaderbericht.zelfdeAls]). Waar als hij nieuw was. [melden]: een bericht van een
  /// uploader komt in [nieuw] (de eerste lading van een toestel meldt zich niet bericht voor bericht).
  bool voegToe(Uploaderbericht b, {bool melden = true}) {
    if (_alle.any(b.zelfdeAls)) return false;
    _alle.add(b);
    _alle.sort((x, y) => x.ms.compareTo(y.ms));
    while (_alle.length > kBerichtenBewaard) {
      _alle.removeAt(0);
    }
    versie++;
    if (melden && !b.vanMij) nieuw.value = b;
    notifyListeners();
    _bewaarStraks();
    return true;
  }

  /// Alles van [uploader] gelezen (het gesprek staat open).
  void gelezen(String uploader) {
    final tot = gesprek(uploader).fold(0, (n, b) => b.ms > n ? b.ms : n);
    if ((_gelezenTot[uploader] ?? 0) >= tot) return;
    _gelezenTot[uploader] = tot;
    notifyListeners();
    _bewaarStraks();
  }

  /// Wat de pc een toestel antwoordt dat versie [heeft] noemt: alleen de versie als er niets veranderde, anders ook
  /// alle berichten.
  Map<String, dynamic> voorToestel(int? heeft) => {
        'versie': versie,
        if (heeft != versie) 'berichten': [for (final b in _alle) b.toJson()],
      };

  Map<String, dynamic> toJson() => {
        'berichten': [for (final b in _alle) b.toJson()],
        'gelezen': _gelezenTot,
      };

  /// Inlezen bij het opstarten. Een kapot bestand begint leeg.
  Future<void> laad() async {
    final f = bestand;
    if (f == null) return;
    try {
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      final lijst = j['berichten'];
      if (lijst is List) {
        for (final e in lijst) {
          final b = Uploaderbericht.uitJson(e);
          if (b != null && !_alle.any(b.zelfdeAls)) _alle.add(b);
        }
        _alle.sort((x, y) => x.ms.compareTo(y.ms));
      }
      final g = j['gelezen'];
      if (g is Map) {
        for (final e in g.entries) {
          if (e.value is int) _gelezenTot['${e.key}'] = e.value as int;
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('soulseek_berichten.json onleesbaar: $e');
    }
  }

  Timer? _bewaarKlok;

  void _bewaarStraks() {
    if (bestand == null) return;
    _bewaarKlok?.cancel();
    _bewaarKlok = Timer(const Duration(seconds: 1), () => unawaited(bewaarNu()));
  }

  @visibleForTesting
  Future<void> bewaarNu() async {
    _bewaarKlok?.cancel();
    _bewaarKlok = null;
    final f = bestand;
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(toJson()));
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('soulseek_berichten.json niet bewaard: $e');
    }
  }
}

/// Het bestand op de pc. **In een toets niets naar schijf**: de appmap is daar die van de echte app.
File? uploaderberichtenBestand() => Platform.environment.containsKey('FLUTTER_TEST')
    ? null
    : File('$appDir${Platform.pathSeparator}soulseek_berichten.json');

/// Eén voor de hele app: op de pc gevuld door de Soulseek-verbinding, op een toestel door de pc.
final Uploaderberichten uploaderberichten = Uploaderberichten(bestand: uploaderberichtenBestand());

/// Jouw antwoord aan [aan] versturen met [stuur] (`SoulseekService.stuurBericht` op de pc) en, als het verstuurd is, in
/// het gesprek zetten. Geeft het bewaarde bericht terug (een toestel zet precies dat ene erbij, dan staat het er niet
/// twee keer), of null als er niets te versturen viel of Soulseek het niet nam.
Future<Uploaderbericht?> verstuurAntwoord(Future<bool> Function(String aan, String tekst) stuur, String aan, String tekst,
    {Uploaderberichten? lijst}) async {
  final t = antwoordVoorUploader(tekst);
  final wie = aan.trim();
  if (t == null || wie.isEmpty) return null;
  if (!await stuur(wie, t)) return null;
  final b = Uploaderbericht(id: 0, ms: DateTime.now().millisecondsSinceEpoch, uploader: wie, tekst: t, vanMij: true);
  final l = lijst ?? uploaderberichten;
  l.voegToe(b);
  l.gelezen(wie);
  return b;
}

/// Op een toestel: wat de pc antwoordde op `/api/soulseek/berichten` erbij zetten ([Uploaderberichten.voorToestel]).
/// Geeft de versie terug om de volgende keer te noemen. [eerste]: de eerste lading van deze sessie meldt zich niet bericht
/// voor bericht — anders kwamen bij elke start alle oude vragen als nieuw in beeld.
int? berichtenVanPc(Map<String, dynamic> antwoord, {required bool eerste, Uploaderberichten? lijst}) {
  final l = lijst ?? uploaderberichten;
  final lading = antwoord['berichten'];
  if (lading is List) {
    for (final e in lading) {
      final b = Uploaderbericht.uitJson(e);
      if (b != null) l.voegToe(b, melden: !eerste);
    }
  }
  final v = antwoord['versie'];
  return v is int ? v : null;
}

/// Wat je typt, zoals het naar de uploader gaat: zonder witruimte eromheen, op één regel, en niet langer dan
/// [kAntwoordHoogstens]. Null als er niets overblijft.
String? antwoordVoorUploader(String tekst) {
  final t = tekst.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return null;
  return t.length > kAntwoordHoogstens ? t.substring(0, kAntwoordHoogstens) : t;
}
