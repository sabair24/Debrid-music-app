import 'dart:ui' show Rect;

/// Het venster vullen zodra er een eerste beeld is — en opschrijven wat er daarbij gebeurde.
///
/// **Waarom dit opschrijft.** Op 04-10-2026 opende de app twee keer na een update (3.9.433→434 en
/// 434→435) klein: 1240×820 midden op het scherm, precies de herstelmaat uit `WindowOptions`. Een
/// gewone start opent gevuld. Wat er tussen die twee verschilt was niet te zien, want deze lus
/// zweeg: hij vroeg zes keer "gemaximaliseerd?" en niemand hoorde het antwoord. Drie verklaringen
/// lagen op tafel — het venster krijgt na de installer de voorgrond niet, zes keer 100 ms is te kort,
/// of `isMaximized` zegt ja voordat het waar is — en geen enkele was te toetsen.
///
/// Eén verklaring is wél al gemeten en valt af: de installer start de app met precies dezelfde
/// opstartinfo als Verkenner (`STARTF_USESHOWWINDOW`, `SW_SHOWNORMAL`), uitgelezen uit het proces
/// dat die middag klein opende.
///
/// Wat hier staat verandert het gedrag NIET: dezelfde pogingen, dezelfde pauze, hetzelfde stoppen
/// zodra het venster gemaximaliseerd is. Er komt alleen bij dat elke poging een regel krijgt, en dat
/// de stand daarna nog een paar seconden gevolgd wordt. Dat laatste is de vraag die ertoe doet: het
/// venster kan best gevuld zijn als deze lus stopt, en pas dáárna terugspringen — en dan staat dat
/// moment hier, naast de regels die `windows/runner` over zijn eigen vensterberichten schrijft.
///
/// Gooit nooit: een logboek mag het opstarten niet breken. Een fout wordt zelf een regel.
Future<void> vulVensterNaEersteBeeld({
  required Future<bool> Function() isGemaximaliseerd,
  required Future<void> Function() maximaliseer,
  required Future<Rect> Function() maten,
  required void Function(String regel) log,
  Future<bool> Function()? isZichtbaar,
  Future<bool> Function()? heeftVoorgrond,
  int pogingen = 6,
  Duration pauze = const Duration(milliseconds: 100),
  List<Duration> nakijken = const [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ],
  Duration Function()? verstreken,
  Future<void> Function(Duration)? wacht,
}) async {
  final klok = Stopwatch()..start();
  final hoeLang = verstreken ?? () => klok.elapsed;
  final slaap = wacht ?? (Duration d) => Future<void>.delayed(d);

  Future<String> stand(bool gemaximaliseerd) async {
    final delen = <String>['gemaximaliseerd=${_janee(gemaximaliseerd)}'];
    if (isZichtbaar != null) delen.add('zichtbaar=${_janee(await isZichtbaar())}');
    if (heeftVoorgrond != null) delen.add('voorgrond=${_janee(await heeftVoorgrond())}');
    delen.add(vensterMaat(await maten()));
    return delen.join(', ');
  }

  try {
    String? laatste;
    var gevuld = false;
    for (var i = 0; i < pogingen; i++) {
      final max = await isGemaximaliseerd();
      laatste = await stand(max);
      log('venster: poging ${i + 1} (+${hoeLang().inMilliseconds} ms): $laatste');
      if (max) {
        gevuld = true;
        break;
      }
      await maximaliseer();
      await slaap(pauze);
    }
    if (!gevuld) log('venster: na $pogingen pogingen nog altijd niet gemaximaliseerd');

    // Nakijken. Alleen een VERANDERING krijgt een regel: een venster dat gewoon gevuld blijft hoeft
    // niet vijf keer gemeld, en een venster dat terugspringt valt zo meteen op.
    for (final moment in nakijken) {
      final nog = moment - hoeLang();
      if (nog > Duration.zero) await slaap(nog);
      final nu = await stand(await isGemaximaliseerd());
      if (nu != laatste) {
        log('venster: veranderd na de pogingen (+${hoeLang().inMilliseconds} ms): $nu');
        laatste = nu;
      }
    }
    log('venster: nagekeken tot +${hoeLang().inMilliseconds} ms, eindstand: $laatste');
  } catch (e) {
    log('venster: meten of vullen mislukte: $e');
  }
}

/// `660,310 1240x820` — linkerbovenhoek en maat in logische punten, afgerond.
///
/// Apart en openbaar zodat de vorm vastligt: dit is wat je naast een schermafdruk legt, en een
/// schermafdruk is vaak verkleind. 1240x820 op een scherm van 2560 ziet er op een afdruk van 1456
/// breed uit als ongeveer 700x470 — en dat getal kwam op 04-10-2026 eerst als "de kleine maat" binnen.
String vensterMaat(Rect r) =>
    '${r.left.round()},${r.top.round()} ${r.width.round()}x${r.height.round()}';

String _janee(bool b) => b ? 'ja' : 'nee';
