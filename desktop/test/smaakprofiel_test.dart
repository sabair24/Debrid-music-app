/// Het profiel dat zowel de startpagina als de radio meestuurt naar het model.
///
/// **Waarom hier een toets op staat.** Dit stond uitgeschreven in `main.dart` en wordt sinds
/// 12-09-2026 door twee kanten gebruikt: de aanbevelingsrij én de radio (`radiobuurt.dart`). Twee
/// kopieën van dezelfde rekensom lopen uit elkaar zonder dat iemand het merkt — de ene stuurt
/// straks twintig topartiesten mee en de andere dertig.
library;

import 'package:debridmusic/aanbevelingplan.dart';
import 'package:flutter_test/flutter_test.dart';

({String artiest, int? jaar, String? genre}) _n(String a, [int? j, String? g]) =>
    (artiest: a, jaar: j, genre: g);

void main() {
  test('DE KERN: de meest aanwezige artiesten staan vooraan, met hun aantal', () {
    final p = profielUit(nummers: [
      _n('Michael Jackson'),
      _n('Michael Jackson'),
      _n('Michael Jackson'),
      _n('Madonna'),
    ]);

    expect(p.topArtiesten.first, 'Michael Jackson (3)');
    expect(p.topArtiesten.last, 'Madonna (1)');
  });

  test('DE KERN: jaartallen worden decennia', () {
    final p = profielUit(nummers: [_n('a', 1983), _n('b', 1989), _n('c', 1995)]);

    expect(p.perDecennium, {1980: 2, 1990: 1});
  });

  test('DE VAL: onmogelijke jaartallen tellen niet mee', () {
    // Een tag met 0 of 9999 erin maakte er anders een decennium van, en dat stuurt het model
    // een tijdvak in dat niet bestaat.
    final p = profielUit(nummers: [_n('a', 0), _n('b', 9999), _n('c', 1983)]);

    expect(p.perDecennium, {1980: 1});
  });

  test('DE GRENS: wie overgeslagen moet worden telt niet mee', () {
    final p = profielUit(
      nummers: [_n('Various Artists'), _n('Various Artists'), _n('Prince'), _n('   ')],
      overslaan: (a) => a.toLowerCase() == 'various artists',
    );

    expect(p.topArtiesten, ['Prince (1)']);
  });

  test('DE GRENS: een leeg profiel weet dat het leeg is', () {
    expect(profielUit(nummers: const []).leeg, isTrue,
        reason: 'met een leeg profiel wordt het model niet eens gevraagd');
    expect(profielUit(nummers: [_n('Prince')]).leeg, isFalse);
  });
}
