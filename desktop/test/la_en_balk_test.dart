/// De la en de balk onderaan, en wie wat toont.
///
/// **Waarom dit bestaat.** Op een telefoon stonden vijf secties twee keer op hetzelfde scherm: als
/// knop in de balk onderaan én als regel in de la erboven. De la is nu wat de balk NIET heeft, en
/// dat is precies het soort afspraak dat stilletjes uit elkaar loopt zodra iemand er een sectie bij
/// zet — vandaar één lijst als bron en deze toets erop.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart';

void main() {
  test('elke sectie uit de balk bestaat ook echt', () {
    // `_onderbalk` zoekt ze op met firstWhere; een nummer dat niet bestaat is daar een crash bij
    // het openen van de app, niet een lege knop.
    for (final id in NavSections.balk) {
      expect(NavSections.items.where((s) => s.$1 == id), hasLength(1), reason: 'sectie $id');
    }
  });

  test('op een telefoon herhaalt de la de balk niet', () {
    final la = NavSections.voorLa(metBalk: true).map((s) => s.$1).toList();

    expect(la, isNot(contains(0)), reason: 'Albums staat onderaan in de balk');
    expect(la, isNot(contains(5)), reason: 'Start ook');
    expect(la, contains(6), reason: 'Mijn downloads staat nergens anders');
    expect(la, contains(1), reason: 'Artiesten evenmin');
    expect(la, hasLength(NavSections.items.length - NavSections.balk.length));
  });

  test('en waar geen balk is, is de la de volledige kaart', () {
    // Op een pc en een televisie is er geen balk onderaan; daar zou weglaten juist secties
    // onbereikbaar maken.
    expect(NavSections.voorLa(metBalk: false), NavSections.items);
  });

  test('samen dekken ze alles, zonder gaten', () {
    final samen = {
      ...NavSections.balk,
      ...NavSections.voorLa(metBalk: true).map((s) => s.$1),
    };
    expect(samen, NavSections.items.map((s) => s.$1).toSet(),
        reason: 'een sectie die uit allebei valt is onbereikbaar op een telefoon');
  });
}
