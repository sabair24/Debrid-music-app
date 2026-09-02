/// Wat het paneel op de telefoon zegt over het bijwerken van de pc.
///
/// **Waarom dit zoveel toetsen waard is.** Dit is een knop die je indrukt op een machine waar je
/// níét bij staat, en die daarna een installer start die de app afsluit. Elke fout hier valt niet om
/// maar zegt stilletjes het verkeerde: een knop die bijwerken aanbiedt terwijl er niets nieuws is,
/// een knop die verdwijnt terwijl de pc aan het binnenhalen is, of een mislukking die wordt
/// weggepoetst door een pc die daarna "ik kan het niet" begint te sturen. Geen van drieën gooit.
///
/// Zuiver: een kaart met wat de pc zei gaat erin, wat er getekend wordt komt eruit.
library;

import 'package:debridmusic/lan/bijwerkstand.dart';
import 'package:flutter_test/flutter_test.dart';

/// Zoals een bijgewerkte pc hem stuurt met een uitgave klaar.
Map<String, dynamic> stand({
  bool kan = true,
  String versie = '3.9.234',
  String nieuw = '3.9.236',
  int bytes = 43 * 1024 * 1024,
  String fase = 'stil',
  double voortgang = 0,
  String fout = '',
}) =>
    {
      'kan': kan,
      'versie': versie,
      'nieuw': nieuw,
      'bytes': bytes,
      'fase': fase,
      'voortgang': voortgang,
      'fout': fout,
    };

void main() {
  group('de fase overleeft de lijn', () {
    test('namen heen en terug', () {
      for (final f in Bijwerkfase.values) {
        expect(faseUitNaam(naamVanFase(f)), f, reason: f.name);
      }
    });

    test('een onbekende of ontbrekende naam is stil, niet stuk', () {
      // Een pc van vóór deze versie stuurt hier niets. Dat is "niets aan de hand", geen fout.
      for (final rommel in [null, '', '  ', 'HALEN', 'downloading']) {
        expect(faseUitNaam(rommel), Bijwerkfase.stil, reason: '${rommel ?? "null"}');
      }
    });
  });

  group('DE KERN: er is alleen een knop als er echt iets te installeren valt', () {
    test('een uitgave klaar geeft een knop met het versienummer erop', () {
      // Het nummer OP de knop is de halve bevestiging: je ziet wat je installeert voordat je drukt,
      // op een pc waar je niet bij kunt.
      final b = bijwerkbeeldVan(stand());
      expect(b.knop, 'Pc bijwerken naar 3.9.236');
      expect(b.regel, contains('3.9.234'));
      expect(b.regel, contains('43 MB'));
      expect(b.fout, isFalse);
      expect(b.balk, isNull);
    });

    test('niets nieuws geeft GEEN bijwerkknop, maar wel een kijkknop', () {
      // De bijwerkknop blijft weg: er staat niets klaar, en beweren van wel is de fout waar dit
      // hele bestand voor bestaat. Maar er moet wél iets te DRUKKEN zijn, want de pc kijkt uit
      // zichzelf hoogstens eens per tien minuten. Gemeld op 02-09-2026: "waar is men knop om de
      // update te pushen naar pc" — hij was er alleen als de pc toevallig al gekeken had.
      final b = bijwerkbeeldVan(stand(nieuw: ''));
      expect(b.knop, isNull);
      expect(b.kijken, isNotNull);
      expect(b.regel, contains('voor zover hij weet'),
          reason: 'niet beweren dat de pc bij is als dat nog niet nagekeken is');
    });

    test('een pc die het niet kan krijgt ook geen kijkknop', () {
      // Een knop die naar een pc wijst die zichzelf toch niet kan bijwerken, is een knop die niets
      // doet. Zeggen dat het niet kan is het hele antwoord.
      expect(bijwerkbeeldVan(stand(kan: false)).kijken, isNull);
      expect(bijwerkbeeldVan(const {}).kijken, isNull);
    });

    test('en er staan nooit twee knoppen tegelijk', () {
      for (final j in [stand(), stand(nieuw: ''), stand(kan: false), const <String, dynamic>{}]) {
        final b = bijwerkbeeldVan(j);
        expect(b.knop != null && b.kijken != null, isFalse,
            reason: 'twee knoppen met twee beloftes naast elkaar is een keuze die niemand kan maken');
      }
    });

    test('een pc die het niet kan geeft geen knop', () {
      final b = bijwerkbeeldVan(stand(kan: false));
      expect(b.knop, isNull);
      expect(b.regel, contains('niet op afstand'));
    });

    test('een lege boel geeft geen knop en gooit niet', () {
      // Dit is letterlijk wat er terugkomt van een pc die deze weg niet kent.
      final b = bijwerkbeeldVan(const {});
      expect(b.knop, isNull);
      expect(b.fout, isFalse);
      expect(b.regel, isNotEmpty);
    });

    test('rommel in de velden gooit niet', () {
      // Een pc van een nieuwere versie mag velden sturen die deze telefoon niet kent, en andersom.
      final b = bijwerkbeeldVan(const {'kan': 'ja', 'versie': 3, 'nieuw': null, 'bytes': 'veel'});
      expect(b.regel, isNotEmpty);
      expect(b.knop, isNull);
    });
  });

  group('DE KERN: terwijl hij bezig is verdwijnt de knop', () {
    test('binnenhalen toont een balk die telt en geen knop', () {
      final b = bijwerkbeeldVan(stand(fase: 'halen', voortgang: .42));
      expect(b.knop, isNull, reason: 'twee installers naast elkaar is het ergste dat kan gebeuren');
      expect(b.kijken, isNull, reason: 'ook niet via de achterdeur');
      expect(b.balk, closeTo(.42, .001));
      expect(b.balkOnbepaald, isFalse);
      expect(b.regel, contains('42%'));
    });

    test('een voortgang buiten de oevers wordt bijgeknipt', () {
      // Anders staat er "-0%" of "137%" naast een balk die assert.
      expect(bijwerkbeeldVan(stand(fase: 'halen', voortgang: -1)).balk, 0);
      expect(bijwerkbeeldVan(stand(fase: 'halen', voortgang: 9)).balk, 1);
    });

    test('installeren toont een onbepaalde balk, want de installer zwijgt', () {
      final b = bijwerkbeeldVan(stand(fase: 'installeren', voortgang: 1));
      expect(b.knop, isNull);
      expect(b.balkOnbepaald, isTrue);
      expect(b.regel, contains('start hem zo weer op'));
    });
  });

  group('DE KERN: een mislukking wordt nooit weggepoetst', () {
    test('de melding van de pc komt er letterlijk uit, met een nieuwe poging', () {
      final b = bijwerkbeeldVan(stand(fase: 'mislukt', fout: 'De download gaf 403'));
      expect(b.regel, 'De download gaf 403');
      expect(b.fout, isTrue);
      expect(b.knop, 'Opnieuw proberen');
    });

    test('mislukt zonder tekst zegt nog steeds dát het misging', () {
      final b = bijwerkbeeldVan(stand(fase: 'mislukt'));
      expect(b.fout, isTrue);
      expect(b.regel, isNotEmpty);
    });

    test('de fout wint van "deze pc kan het niet"', () {
      // De volgorde in bijwerkbeeldVan, en dit is waarom hij zo staat: een mislukking is het gevolg
      // van iets wat je zelf hebt aangeraakt. Zou `kan: false` hier winnen, dan zag je na een
      // mislukte poging alleen nog "deze pc kan zichzelf niet bijwerken" — en dat is een ander,
      // verkeerd verhaal.
      final b = bijwerkbeeldVan(stand(kan: false, fase: 'mislukt', fout: 'Geen schijfruimte'));
      expect(b.regel, 'Geen schijfruimte');
      expect(b.fout, isTrue);
    });
  });

  group('megabytes', () {
    test('afgerond, want dit staat naast een knop en niet in een boekhouding', () {
      expect(megabytes(43 * 1024 * 1024), '43 MB');
      expect(megabytes(43 * 1024 * 1024 + 700 * 1024), '44 MB');
    });

    test('onbekend of leeg levert niets op in plaats van "0 MB"', () {
      expect(megabytes(0), '');
      expect(megabytes(-1), '');
    });

    test('een grootte van nul haalt de knop niet weg', () {
      // De maat is een dienst, geen voorwaarde. Een release zonder `size` mag je niet tegenhouden.
      final b = bijwerkbeeldVan(stand(bytes: 0));
      expect(b.knop, 'Pc bijwerken naar 3.9.236');
      expect(b.regel, isNot(contains('MB')));
    });
  });
}
