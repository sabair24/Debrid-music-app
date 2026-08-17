/// Eén regel per minuut, zodat een crash niet meer in het donker gebeurt.
///
/// **Waarom dit bestaat.** De pc-app viel op 15-08-2026 om 22:44 om met een toegangsfout in
/// `flutter_windows.dll` — de zesde keer in een week. Het onderzoek liep vast op iets wat je niet
/// verwacht: er was op dat moment in ÉÉN van de logboeken iets geschreven. De laatste regels lagen
/// uren eerder:
///
///     cast.log       21:22:47   (82 minuten voor de crash)
///     warm.log       19:36:14
///     ui.log         18:05:35
///
/// Dat sloot van alles uit — de verrijker, de scan, de downloads, de kleurextractie — maar het liet
/// ook een gat van anderhalf uur waarin niemand weet wat de app deed. En zolang dat gat er is, is
/// elke volgende verdachte een gok. Er was er al één, en die was mis.
///
/// Een hartslag maakt de STILTE zelf leesbaar. Stopt hij om 22:43 en crasht de app om 22:44, dan
/// weet je dat hij tot een minuut daarvoor gewoon draaide en wát hij toen omhanden had. Stopt hij
/// een uur eerder, dan is de app al veel langer stuk dan het gebeurtenislogboek zegt.
///
/// **Nooit de zaak breken die hij observeert.** Alles staat in een `try`, hij schrijft via [WarmLog]
/// (die zichzelf afkapt en nooit gooit), en de gegevens komen uit haken die de app zelf al invult —
/// deze module vraagt niets op en houdt niets vast.
library;

import 'dart:async';
import 'dart:io';

import 'warm_log.dart';

/// Wat er op dit moment omhanden is. Ingevuld door de app; leeg is ook een antwoord.
///
/// Bewust functies en geen waarden: een hartslag die een kopie van de toestand vasthoudt, houdt die
/// toestand ook in leven.
typedef Hartslagbron = String Function();

final List<Hartslagbron> _bronnen = [];

/// Meld iets dat elke minuut opgeschreven moet worden.
void meldAanBijHartslag(Hartslagbron bron) => _bronnen.add(bron);

Timer? _tikker;
int _tellen = 0;

/// Start de hartslag. Eén keer, vroeg in `main()`.
///
/// Alleen op de pc en de Mac: dáár draait de app uren achtereen als server, en dáár viel hij om.
/// Op een telefoon is de app zelden lang genoeg wakker om dit iets te laten betekenen, en elke
/// schrijfbeurt kost daar accu.
void startHartslag(String map) {
  if (_tikker != null) return;
  if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
  try {
    final log = WarmLog('$map${Platform.pathSeparator}hartslag.log');
    log.line('--- gestart ---');
    _tikker = Timer.periodic(const Duration(minutes: 1), (_) {
      try {
        _tellen++;
        final delen = <String>[];
        for (final b in _bronnen) {
          try {
            final s = b();
            if (s.isNotEmpty) delen.add(s);
          } catch (e) {
            delen.add('bron gooide: $e');
          }
        }
        // De teller staat er zodat een gat ook zichtbaar is als de klok verspringt: mist er een
        // nummer, dan is er een minuut overgeslagen — dat is iets anders dan een app die stilstond.
        log.line('#$_tellen  ${delen.isEmpty ? 'niets te melden' : delen.join('  |  ')}');
      } catch (_) {
        // Een hartslag die de app kan laten struikelen is erger dan geen hartslag.
      }
    });
  } catch (_) {
    // Dan geen hartslag. Nooit een reden om het opstarten te laten mislukken.
  }
}
