// Favorieten en de afspeellijsten die je op dit toestel houdt, bijgehouden (Saber, 28-10-2026): wat erbij komt gaat
// op je gsm, wat eruit gaat verdwijnt "vanzelf" — tenzij het er ook om een andere reden staat (zie
// toestel_redenen.dart). Alleen via wifi, zoals al het offline bewaren (offline.dart, magOphalen).
import 'models.dart';
import 'offline.dart';
import 'toestel_redenen.dart';

/// Breng het toestel in lijn met [gewenst]: per reden (favoriet, of een lijst) de nummers die er horen.
///
/// Een reden van een lijst die niet in [gewenst] staat (je houdt hem niet meer op dit toestel, of hij is weg),
/// gaat er helemaal af. Wat daarna geen enkele reden meer heeft, gaat van het toestel.
Future<({int erbij, int weg})> houdLijstenBij({
  required ToestelRedenen redenen,
  required OfflineStore offline,
  required Map<String, List<Track>> gewenst,
}) async {
  var erbij = 0;
  final vanToestel = <String>{};
  for (final e in gewenst.entries) {
    final nu = {for (final t in e.value) t.path};
    final eerder = redenen.padenMet(e.key);
    final nieuw = [for (final t in e.value) if (!eerder.contains(t.path)) t];
    if (nieuw.isNotEmpty) {
      await redenen.voegToe([for (final t in nieuw) t.path], e.key, alOpToestel: offline.has);
      final ophalen = [
        for (final t in nieuw)
          if (!offline.has(t.path)) OfflineRequest(libraryPath: t.path, title: t.title, artist: t.artist, album: t.album),
      ];
      if (ophalen.isNotEmpty) offline.bewaarAlles(ophalen);
      erbij += ophalen.length;
    }
    final eruit = eerder.difference(nu);
    if (eruit.isNotEmpty) vanToestel.addAll(await redenen.haalWeg(eruit, e.key));
  }
  // Lijsten die je niet meer op dit toestel houdt.
  for (final r in redenen.alleRedenen) {
    if (!r.startsWith('lijst:') || gewenst.containsKey(r)) continue;
    vanToestel.addAll(await redenen.haalWeg(redenen.padenMet(r), r));
  }
  for (final p in vanToestel) {
    await offline.remove(p);
  }
  return (erbij: erbij, weg: vanToestel.length);
}
