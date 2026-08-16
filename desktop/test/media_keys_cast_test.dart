/// Bediening die NIET van het scherm komt, moet ook bij de speaker uitkomen.
///
/// Aanleiding, gemeten op de Shield op 16-08-2026 tijdens het casten naar de Sonos Amp: één druk op
/// de mediatoets "volgende" van de afstandsbediening liet libmpv op de Shield zelf beginnen. De
/// versterker viel daardoor terug op zijn tv-ingang en de muziek stopte — terwijl het scherm
/// onverstoorbaar "Speelt op Sonos Amp" bleef tonen met een voortgangsbalk die gewoon doorliep, om
/// aan het einde van het nummer stil te blijven staan. De knop óp het scherm herstelde het meteen.
///
/// De oorzaak was dat er twee wegen naar de transportbediening lopen. Het scherm gaat via
/// `_Transport`, dat naar `SpeakerTarget` kijkt. Maar `NowPlayingHandler` (audio_service) komt via
/// `NowPlayingSource` rechtstreeks in [PlayerStore] uit, en die kende het casten niet. Alles wat van
/// buiten de app komt loopt langs die tweede weg: de mediatoetsen, het vergrendelscherm, een
/// bluetoothknop, Android Auto en een autoradio.
///
/// De regel staat daarom nu in de speler zelf, zodat elke aanroeper hem krijgt.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/player.dart';

/// Een speaker die alleen onthoudt wat hem gevraagd is.
class _Speaker implements Speakerbediening {
  _Speaker(this.isCasting, {this.isPlaying = true});
  @override
  final bool isCasting;
  @override
  final bool isPlaying;
  final gevraagd = <String>[];
  @override
  Future<void> playPause() async => gevraagd.add('playPause');
  @override
  Future<void> next() async => gevraagd.add('next');
  @override
  Future<void> previous() async => gevraagd.add('previous');
  @override
  Future<void> seekTo(Duration to) async => gevraagd.add('seekTo');
}

void main() {
  group('bedienVia', () {
    test('geen speaker: de speler doet het zelf', () {
      expect(bedienVia(null), isNull);
    });

    test('wel een speaker, maar hij heeft de muziek niet: nog steeds lokaal', () {
      // Dit is het gewone geval op een pc of Mac: er staat altijd een SpeakerTarget klaar, en
      // zolang je niet cast hoort er niets omgeleid te worden.
      expect(bedienVia(_Speaker(false)), isNull);
    });

    test('de speaker heeft de muziek: die krijgt de bediening', () {
      final s = _Speaker(true);
      expect(bedienVia(s), same(s));
    });
  });

  group('de speler leidt elke transportactie om', () {
    // Een bronbewaker, net als device_name_test.dart. Het gaat hier niet om één regel code maar om
    // een regel die geldt: wie een transportactie toevoegt en de speaker vergeet, bouwt de bug van
    // 16-08-2026 opnieuw — en die is op het scherm onzichtbaar, want daar gaat alles goed.
    late final String bron = File('lib/player.dart').readAsStringSync();

    /// De body van een methode van [PlayerStore], van zijn kop tot de sluitende accolade.
    String body(String kop) {
      final start = bron.indexOf(kop);
      expect(start, greaterThan(-1), reason: '$kop niet gevonden — is hij hernoemd?');
      var diepte = 0;
      for (var i = bron.indexOf('{', start); i < bron.length; i++) {
        if (bron[i] == '{') diepte++;
        if (bron[i] == '}') {
          diepte--;
          if (diepte == 0) return bron.substring(start, i);
        }
      }
      fail('geen sluitende accolade voor $kop');
    }

    for (final kop in [
      '  void speelAf() {',
      '  void pauzeer() {',
      '  Future<void> next() async {',
      '  Future<void> prev() async {',
      '  void seek(Duration d) {',
    ]) {
      test('$kop vraagt eerst de speaker', () {
        expect(body(kop), contains('_bijSpeaker'),
            reason: 'deze actie gaat langs de speaker heen en speelt lokaal af');
      });
    }

    test('playPause blijft juist WEL lokaal', () {
      // Met opzet: die schakelaar wordt ook gebruikt als er een telefoongesprek doorheen komt of de
      // koptelefoon eruit gaat. Dat gaat over de audio van dít toestel, en mag de muziek in een
      // andere kamer niet stilzetten. Wat de gebruiker indrukt loopt via speelAf/pauzeer.
      final regel = bron
          .split('\n')
          .firstWhere((l) => l.startsWith('  void playPause()'), orElse: () => '');
      expect(regel, isNot(isEmpty), reason: 'playPause is hernoemd of van vorm veranderd');
      expect(regel, isNot(contains('_bijSpeaker')));
    });

    test('"vorige" vraagt de speaker vóór de drie-secondenregel', () {
      // Die regel leest `position` van libmpv, en die staat tijdens het casten stil op nul. Stond de
      // controle erna, dan viel "vorige" op de speaker altijd in de tak "begin dit nummer opnieuw".
      final b = body('  Future<void> prev() async {');
      expect(b.indexOf('_bijSpeaker'), lessThan(b.indexOf('seconds: 3')));
    });
  });

  group('de mediasessie blijft via de speler praten', () {
    test('NowPlayingHandler kent geen speaker', () {
      // Als de handler zelf een SpeakerTarget zou vasthouden, hadden we twee plekken die beslissen
      // waar de muziek heen gaat — precies de splitsing die deze bug veroorzaakte.
      final bron = File('lib/now_playing.dart').readAsStringSync();
      expect(bron.contains('SpeakerTarget'), isFalse);
      expect(bron.contains('Speakerbediening'), isFalse);
    });
  });
}
