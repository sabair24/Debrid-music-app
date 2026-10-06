/// "Opslaan" in de instellingen van de pc logt ook in als het accountformulier ingevuld is.
///
/// **Waarom dit bestaat.** Saber op 06-10-2026: *"men pc onthoud men inloggen niet??? heb net
/// geprobeerd en opslaan geklikt"*. Het accountblok heeft een eigen knop "Inloggen"; "Opslaan"
/// onderaan het venster bewaarde alleen de gewone instellingen en gooide e-mailadres en wachtwoord
/// weg. Er stond daarna geen `cloud_session.json`, de pc was dus nooit ingelogd — en zonder aanmelding
/// kan een telefoon onderweg niet via het account opnieuw koppelen, alleen nog met een code.
///
/// Brontekst, want het instellingenvenster hangt aan een handvol diensten die in een toets alleen
/// als nep bestaan; wat hier vastligt is de volgorde in de knop.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _bron() => File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('DE KERN: Opslaan logt in vóór het venster sluit', () {
    final bron = _bron();
    final knop = bron.indexOf("child: const Text('Opslaan'),");
    expect(knop, isNonNegative);
    final begin = bron.lastIndexOf('await s.save();', knop);
    final stuk = bron.substring(begin, knop);
    final inlog = stuk.indexOf('inloggenAlsIngevuld()');
    final dicht = stuk.indexOf('Navigator.pop(context)');
    expect(inlog, isNonNegative, reason: 'Opslaan logt niet in — e-mailadres en wachtwoord verdwijnen');
    expect(dicht, greaterThan(inlog), reason: 'het venster sluit vóór het inloggen, en dan is het weg');
    expect(stuk.substring(inlog - 10, dicht), contains('return;'),
        reason: 'een mislukte inlog hoort het venster open te laten, met de reden erbij');
  });

  test('DE GRENS: alleen als er iets ingevuld is, en niet als de pc al ingelogd is', () {
    final bron = _bron();
    final begin = bron.indexOf('Future<bool> inloggenAlsIngevuld() async {');
    expect(begin, isNonNegative);
    final lijf = bron.substring(begin, bron.indexOf('\n  }', begin));
    expect(lijf, contains('CloudState.signedIn) return true;'),
        reason: 'een pc die al ingelogd is hoeft niet opnieuw');
    expect(lijf, contains("_email.text.trim().isEmpty && _password.text.isEmpty) return true;"),
        reason: 'gewoon Opslaan zonder accountgegevens mag niet om een inlog vragen');
    expect(lijf, contains('await _cloudSubmit();'));
    expect(lijf, contains('return _cloudError == null;'));
  });
}
