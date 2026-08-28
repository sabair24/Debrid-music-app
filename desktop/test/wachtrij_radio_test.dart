/// Wat het wachtrijpaneel tijdens een radio toont.
///
/// Dit paneel loog. `radioQueue` had geen enkele lezer, dus zette je een radio aan dan bleef er de
/// lijst staan van vóór de radio — een lijst die niet ging klinken en waarvan elke tik de radio
/// verliet. [radioAlsRij] is de vertaling die dat weghaalt, en hij moet drie dingen goed doen: een
/// nummer dat je HEBT als jouw bestand doorgeven, een nummer dat je NIET hebt als iets herkenbaar
/// anders, en nooit een pad verzinnen waarop straks een hoes of een echtheidsmerk wordt opgezocht.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart';

Track eigen(String titel) => Track(
      path: 'D:\\muziek\\$titel.flac',
      title: titel,
      artist: 'Snap!',
      album: 'The Madman\'s Return',
      isFlac: true,
    );

void main() {
  group('radioAlsRij', () {
    test('een nummer dat je hebt komt door als JOUW bestand', () {
      final t = eigen('Rhythm Is a Dancer');
      final rij = radioAlsRij([
        RadioItem(artist: 'Snap!', title: 'Rhythm Is a Dancer', local: t),
      ]);

      expect(rij, hasLength(1));
      expect(rij.single.eigen, isTrue);
      expect(identical(rij.single.nummer, t), isTrue,
          reason: 'een kopie zou de hoes en het album kwijtraken die alleen in dit object zitten');
      expect(rij.single.mislukt, isFalse);
    });

    test('een nummer dat je niet hebt krijgt titel en artiest, maar geen verzonnen pad', () {
      final rij = radioAlsRij([
        RadioItem(artist: '2 Unlimited', title: 'No Limit'),
      ]);

      expect(rij.single.eigen, isFalse);
      expect(rij.single.nummer.title, 'No Limit');
      expect(rij.single.nummer.artist, '2 Unlimited');
      expect(rij.single.nummer.path, isEmpty,
          reason: 'op een pad wordt een hoes opgezocht; een verzonnen pad vindt de hoes van een '
              'ander nummer of erger');
    });

    test('is er al een adres, dan is dát het pad — daar kan de speler mee openen', () {
      final rij = radioAlsRij([
        RadioItem(artist: 'Haddaway', title: 'What Is Love')..url = 'https://x/y.flac',
      ]);

      expect(rij.single.nummer.path, 'https://x/y.flac');
      expect(rij.single.eigen, isFalse, reason: 'een adres is geen bestand in je bibliotheek');
    });

    test('mislukt telt alleen als er ook niets ligt', () {
      final mis = RadioItem(artist: 'Culture Beat', title: 'Mr. Vain')..failed = true;
      final ookGehaald = RadioItem(artist: 'Culture Beat', title: 'Mr. Vain')
        ..failed = true
        ..url = 'https://x/z.flac';
      final tochEigen = RadioItem(
          artist: 'Culture Beat', title: 'Mr. Vain', local: eigen('Mr. Vain'))
        ..failed = true;

      final rij = radioAlsRij([mis, ookGehaald, tochEigen]);

      expect(rij[0].mislukt, isTrue);
      expect(rij[1].mislukt, isFalse, reason: 'er staat een adres: dit valt te spelen');
      expect(rij[2].mislukt, isFalse,
          reason: 'een nummer dat je zelf hebt is er, wat een zoektocht online ook deed');
      expect(rij[2].eigen, isTrue);
    });

    test('de volgorde blijft precies de volgorde van de radio', () {
      final rij = radioAlsRij([
        RadioItem(artist: 'A', title: 'een'),
        RadioItem(artist: 'B', title: 'twee', local: eigen('twee')),
        RadioItem(artist: 'C', title: 'drie'),
      ]);

      expect([for (final r in rij) r.nummer.title], ['een', 'twee', 'drie']);
      expect([for (final r in rij) r.eigen], [false, true, false]);
    });

    test('een lege radio geeft een lege lijst en geen fout', () {
      expect(radioAlsRij(const []), isEmpty);
    });
  });
}
