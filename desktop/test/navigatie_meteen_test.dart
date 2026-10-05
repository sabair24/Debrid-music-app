/// Twee tikken waar eerst niets op gebeurde, gemeten op Sabers S26 op 05-10-2026 met muziek erbij.
///
/// * **De artiestpagina** verscheen pas 0,8–1,3 s na de tik: [openArtist] vroeg eerst Deezer (en
///   zonder antwoord MusicBrainz) wie de artiest was, en opende pas daarna. Nu gaat de pagina
///   meteen open op naam en zoekt hij het zelf op.
/// * **Ontdek** stond bij elk bezoek opnieuw 5 s te laden, ook als je er net nog was. Nu blijft
///   een oogst [kOntdekBewaard] staan.
///
/// Saber: *"de app moet snel navigeren tussen alle schermen"*.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart';

/// Het stuk van main.dart vanaf [begin] tot de eerste regel die alleen `}` is.
String _lijf(String begin) {
  final bron = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
  final b = bron.indexOf(begin);
  expect(b, isNonNegative, reason: '"$begin" staat niet meer in main.dart');
  final e = bron.indexOf('\n}\n', b);
  return bron.substring(b, e < 0 ? bron.length : e);
}

void main() {
  group('Ontdek bewaart zijn oogst', () {
    final om = DateTime(2026, 10, 5, 20, 0);

    test('DE KERN: terug binnen een halfuur toont de vorige oogst', () {
      expect(ontdekBewaardBruikbaar(om, om), isTrue);
      expect(ontdekBewaardBruikbaar(om, om.add(const Duration(minutes: 29, seconds: 59))), isTrue,
          reason: 'binnen de bewaartijd stond er toch weer een draaiwieltje van 5 s');
    });

    test('DE GRENS: na een halfuur, of zonder oogst, wordt er opnieuw geladen', () {
      expect(ontdekBewaardBruikbaar(om, om.add(kOntdekBewaard)), isFalse,
          reason: 'een oude oogst blijft eindeloos staan en Ontdek ververst nooit meer vanzelf');
      expect(ontdekBewaardBruikbaar(null, om), isFalse, reason: 'zonder oogst niets te tonen');
    });

    test('DE VAL: een klok die terugsprong maakt de oogst niet eeuwig', () {
      expect(ontdekBewaardBruikbaar(om, om.subtract(const Duration(minutes: 5))), isFalse,
          reason: 'met een negatief verschil bleef de oogst staan tot de klok hem weer inhaalde');
    });

    test('initState toont de bewaarde oogst, opnieuw gezeefd tegen wat je nu hebt', () {
      final lijf = _lijf('class _OntdekViewState extends State<OntdekView> {');
      final init = lijf.indexOf('void initState()');
      final bewaard = lijf.indexOf('ontdekBewaardBruikbaar(_bewaardOm', init);
      final laden = lijf.indexOf('addPostFrameCallback((_) => _load())', init);
      expect(bewaard, greaterThan(init), reason: 'initState kijkt niet naar de bewaarde oogst');
      expect(laden, greaterThan(bewaard),
          reason: 'initState laadt opnieuw vóór hij naar de bewaarde oogst kijkt');
      expect(lijf.substring(bewaard, laden), contains('nogNietInBezit('),
          reason: 'wat je intussen binnenhaalde blijft als aanbeveling staan');
    });

    test('alleen een gelukte oogst wordt bewaard', () {
      final lijf = _lijf('class _OntdekViewState extends State<OntdekView> {');
      expect(lijf, contains('if (!failed && recs.isNotEmpty) {'),
          reason: 'een mislukte of lege oogst blijft een halfuur staan in plaats van opnieuw te '
              'proberen');
    });
  });

  group('De artiestpagina gaat meteen open', () {
    test('DE KERN: openArtist wacht nergens op voor hij de pagina opent', () {
      final lijf = _lijf('Future<void> openArtist(BuildContext context, String name) async {');
      expect(lijf, isNot(contains('await')),
          reason: 'openArtist wacht weer op het net voor hij opent — 0,8–1,3 s waarin een tik niets '
              'lijkt te doen');
      expect(lijf, isNot(contains('searchArtists')));
      expect(lijf, isNot(contains('resolveArtist')));
      expect(lijf, contains('openOp('));
    });

    test('DE VAL: een artiest zonder nummer vraagt Deezer niet om "artiest 0"', () {
      final bron = File('lib/main.dart').readAsStringSync();
      expect(bron, contains('bekendId: ref.isMb || widget.artist.id <= 0 ? null : widget.artist.id'),
          reason: 'met id 0 vroeg de pagina de albums van artiest 0 op en bleef de discografie leeg');
    });
  });
}
