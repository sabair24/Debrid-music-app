/// De deur naar je hele bibliotheek, en die staat of valt met één vergelijking.
///
/// Deze toets bestaat omdat een fout hier er in code precies zo uitziet als de goede versie. Een
/// `trim()` te veel, een `toLowerCase()` erbij "voor de zekerheid", een lege string die per ongeluk
/// gelijk is aan een lege string — elk daarvan laat een vreemde binnen zonder dat er iets rood
/// wordt. De regel zelf staat in `lib/lan/accountkoppeling.dart`.
import 'package:debridmusic/lan/accountkoppeling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('magKoppelenOpAccount', () {
    test('hetzelfde account mag binnen', () {
      expect(
        magKoppelenOpAccount(uidVanSleutel: 'k7Yq2mB1', uidVanPc: 'k7Yq2mB1'),
        isTrue,
      );
    });

    test('een ander account niet', () {
      expect(
        magKoppelenOpAccount(uidVanSleutel: 'k7Yq2mB1', uidVanPc: 'z9Aa4nC3'),
        isFalse,
      );
    });

    test('twee lege waarden zijn niet "gelijk"', () {
      // Dit is het gat dat een gewone `a == b` zou laten: een pc die niet is ingelogd heeft een
      // lege uid, en een sleutel die Google niet herkende levert er ook een op. Zonder deze regel
      // komt iedereen binnen op een pc waar niemand op ingelogd is.
      expect(magKoppelenOpAccount(uidVanSleutel: '', uidVanPc: ''), isFalse);
      expect(magKoppelenOpAccount(uidVanSleutel: '   ', uidVanPc: '   '), isFalse);
    });

    test('een pc zonder inlog laat niemand binnen', () {
      expect(magKoppelenOpAccount(uidVanSleutel: 'k7Yq2mB1', uidVanPc: ''), isFalse);
    });

    test('een sleutel die niet nagekeken kon worden komt er niet in', () {
      expect(magKoppelenOpAccount(uidVanSleutel: '', uidVanPc: 'k7Yq2mB1'), isFalse);
    });

    test('spaties eromheen tellen niet mee, maar hoofdletters wél', () {
      // Ingepakt in json en weer uitgepakt kan er witruimte omheen komen; dat is dezelfde sleutel.
      expect(
        magKoppelenOpAccount(uidVanSleutel: ' k7Yq2mB1 ', uidVanPc: 'k7Yq2mB1'),
        isTrue,
      );
      // Maar een uid is geen naam die iemand typt. Soepel zijn met hoofdletters maakt de ruimte om
      // te raden kleiner, en dat is precies wat je hier niet wilt.
      expect(
        magKoppelenOpAccount(uidVanSleutel: 'K7YQ2MB1', uidVanPc: 'k7Yq2mB1'),
        isFalse,
      );
    });

    test('een sleutel die er alleen op lijkt, komt er niet in', () {
      // Geen `startsWith`, geen `contains`. Een uid die met de jouwe begint is niet de jouwe.
      expect(
        magKoppelenOpAccount(uidVanSleutel: 'k7Yq2mB1x', uidVanPc: 'k7Yq2mB1'),
        isFalse,
      );
      expect(
        magKoppelenOpAccount(uidVanSleutel: 'k7Yq2mB1', uidVanPc: 'k7Yq2mB1x'),
        isFalse,
      );
    });
  });

  group('koppelweigering', () {
    test('een pc die niet ingelogd is zegt dát, en niet "verkeerd account"', () {
      // Twee heel verschillende oplossingen: hier moet je op de PC inloggen. Wie hier "ander
      // account" leest, gaat op zijn telefoon een wachtwoord zoeken dat prima was.
      final zin = koppelweigering(uidVanSleutel: 'k7Yq2mB1', uidVanPc: '');
      expect(zin.toLowerCase(), contains('pc'));
      expect(zin.toLowerCase(), contains('niet ingelogd'));
    });

    test('een sleutel die niet nagekeken kon worden vraagt om opnieuw inloggen', () {
      final zin = koppelweigering(uidVanSleutel: '', uidVanPc: 'k7Yq2mB1');
      expect(zin.toLowerCase(), contains('opnieuw in'));
    });

    test('een ander account krijgt de enige zin die verder helpt', () {
      final zin = koppelweigering(uidVanSleutel: 'z9Aa4nC3', uidVanPc: 'k7Yq2mB1');
      expect(zin.toLowerCase(), contains('ander account'));
      expect(zin.toLowerCase(), contains('hetzelfde account'));
    });

    test('geen enkele weigering laat de uid zelf zien', () {
      // Die zin komt op een scherm en gaat over de lijn. Er hoort niets in te staan waarmee iemand
      // anders verder kan.
      for (final zin in [
        koppelweigering(uidVanSleutel: 'k7Yq2mB1', uidVanPc: ''),
        koppelweigering(uidVanSleutel: '', uidVanPc: 'k7Yq2mB1'),
        koppelweigering(uidVanSleutel: 'z9Aa4nC3', uidVanPc: 'k7Yq2mB1'),
      ]) {
        expect(zin, isNot(contains('k7Yq2mB1')));
        expect(zin, isNot(contains('z9Aa4nC3')));
      }
    });

    test('elke weigering is een hele zin en niet een code', () {
      for (final zin in [
        koppelweigering(uidVanSleutel: 'k7Yq2mB1', uidVanPc: ''),
        koppelweigering(uidVanSleutel: '', uidVanPc: 'k7Yq2mB1'),
        koppelweigering(uidVanSleutel: 'z9Aa4nC3', uidVanPc: 'k7Yq2mB1'),
      ]) {
        expect(zin.trim(), isNotEmpty);
        expect(zin.trim(), endsWith('.'));
        expect(zin.length, greaterThan(20));
      }
    });
  });
}
