/// De ladder, en wanneer de speel-URL wél en niet aangeraakt wordt.
///
/// **Waarom dit zoveel toetsen waard is.** Elke fout hier valt niet om maar doet stilletjes het
/// verkeerde: een bestand dat onnodig door de omzetter gaat, een URL met de verkeerde extensie die
/// door AVFoundation geweigerd wordt voordat er één byte gelezen is, of een mp3 die "verlaagd" wordt
/// naar een FLAC die twee keer zo groot is. Geen van drieën gooit; alle drie kosten ze een uitgave.
///
/// Zuiver: tekst in, tekst uit. Geen netwerk, geen schijf, geen ffmpeg — dus na te meten zonder
/// toestel.
library;

import 'package:debridmusic/lan/stroomstand.dart';
import 'package:flutter_test/flutter_test.dart';

/// Zoals de pc hem serveert: het pad met de token eraan.
const _url = 'http://192.168.0.9:47820/stream/abc123.flac?token=geheim';

void main() {
  group('de ladder zelf', () {
    test('max heeft geen plafond', () {
      expect(plafondVan(Stroomstand.max), (rate: 0, bits: 0));
    });

    test('de sporten dalen, allebei de assen', () {
      expect(plafondVan(Stroomstand.hoog), (rate: 48000, bits: 24));
      expect(plafondVan(Stroomstand.cd), (rate: 44100, bits: 16));
    });

    test('namen overleven de heen- en terugweg', () {
      for (final s in Stroomstand.values) {
        expect(standUitNaam(naamVan(s)), s, reason: '${s.name}');
      }
    });

    test('een onbekende of lege naam valt terug in plaats van te gooien', () {
      // Een instellingenbestand van een oudere of nieuwere versie is een voorkeur, geen contract.
      for (final rommel in [null, '', '  ', 'MAX', 'lossless', 'high']) {
        expect(standUitNaam(rommel), Stroomstand.max, reason: '${rommel ?? "null"}');
      }
      expect(standUitNaam('rommel', terugval: Stroomstand.cd), Stroomstand.cd);
    });

    test('elke sport heeft een naam en een tempo op het scherm', () {
      for (final s in Stroomstand.values) {
        expect(labelVan(s), isNotEmpty);
        expect(tempoVan(s), isNotEmpty);
      }
    });
  });

  group('DE KERN: de URL blijft ongemoeid tenzij er echt omgezet wordt', () {
    test('op max verandert er niets, byte voor byte', () {
      // De hele voorziening hoort niets te kosten als je hem uit laat staan.
      expect(
          metStand(_url, stand: Stroomstand.max, sampleRate: 192000, bits: 24, lossless: true),
          _url);
    });

    test('een bestand dat al onder het plafond zit blijft het origineel', () {
      // Dit is de belangrijkste eigenschap van de hele ladder: nooit omhoog omzetten, en nooit
      // hercoderen voor niets. Een cd-rip op de hi-res-sport is gewoon de cd-rip.
      expect(
          metStand(_url, stand: Stroomstand.hoog, sampleRate: 44100, bits: 16, lossless: true),
          _url);
      expect(
          metStand(_url, stand: Stroomstand.cd, sampleRate: 44100, bits: 16, lossless: true),
          _url);
    });

    test('een lossy bron wordt op geen enkele sport aangeraakt', () {
      // Anders verdubbelt de databesparing de data: een mp3 van 320 komt er als FLAC van ~800 uit.
      const mp3 = 'http://192.168.0.9:47820/stream/abc123.mp3?token=geheim';
      for (final s in Stroomstand.values) {
        expect(metStand(mp3, stand: s, sampleRate: 48000, bits: 16, lossless: false), mp3,
            reason: labelVan(s));
      }
    });

    test('wat geen stroom-adres is komt ongewijzigd terug', () {
      for (final vreemd in [
        'https://store-1.tb-cdn.io/dl/xyz/01%20-%20Traffic.flac',
        'file:///storage/emulated/0/Music/nummer.flac',
        'http://192.168.0.9:47820/cover/abc.jpg?token=geheim',
      ]) {
        expect(
            metStand(vreemd, stand: Stroomstand.cd, sampleRate: 192000, bits: 24, lossless: true),
            vreemd);
      }
    });

    test('onleesbare rommel gooit niet maar komt terug zoals hij kwam', () {
      const kapot = ':::/stream/geen url';
      expect(metStand(kapot, stand: Stroomstand.cd, sampleRate: 192000, bits: 24, lossless: true),
          kapot);
    });
  });

  group('DE KERN: en wél aangeraakt als er iets te winnen valt', () {
    test('24/192 op de cd-sport krijgt allebei de grenzen', () {
      final uit =
          metStand(_url, stand: Stroomstand.cd, sampleRate: 192000, bits: 24, lossless: true);
      final q = Uri.parse(uit).queryParameters;
      expect(q['maxRate'], '44100');
      expect(q['maxBits'], '16');
    });

    test('alleen de as die overschreden wordt beweegt', () {
      // 24 bit op 44,1 kHz: de frequentie is al goed, alleen de diepte moet zakken. De grens die
      // meegestuurd wordt is dan de BESTAANDE frequentie, zodat de omzetter hem laat staan.
      final uit =
          metStand(_url, stand: Stroomstand.cd, sampleRate: 44100, bits: 24, lossless: true);
      final q = Uri.parse(uit).queryParameters;
      expect(q['maxRate'], '44100');
      expect(q['maxBits'], '16');

      // En andersom: 16 bit op 96 kHz zakt in frequentie en houdt zijn diepte.
      final uit2 =
          metStand(_url, stand: Stroomstand.cd, sampleRate: 96000, bits: 16, lossless: true);
      final q2 = Uri.parse(uit2).queryParameters;
      expect(q2['maxRate'], '44100');
      expect(q2['maxBits'], '16');
    });

    test('de token overleeft de herschrijving', () {
      // Zonder token weigert de pc het verzoek, en dan speelt er niets meer.
      final uit =
          metStand(_url, stand: Stroomstand.cd, sampleRate: 192000, bits: 24, lossless: true);
      expect(Uri.parse(uit).queryParameters['token'], 'geheim');
    });

    test('de extensie wordt .flac, want dat komt eruit', () {
      // AVFoundation typeert een bestand op zijn pad en weigert wat het daar niet kan plaatsen. Een
      // .wav-adres dat FLAC-bytes teruggeeft speelt dus niet — vandaar dat die extensie er staat.
      const wav = 'http://192.168.0.9:47820/stream/abc123.wav?token=geheim';
      final uit = metStand(wav, stand: Stroomstand.cd, sampleRate: 192000, bits: 24, lossless: true);
      expect(Uri.parse(uit).pathSegments.last, 'abc123.flac');
    });

    test('een adres zonder extensie krijgt er gewoon een', () {
      const kaal = 'http://192.168.0.9:47820/stream/abc123?token=geheim';
      final uit =
          metStand(kaal, stand: Stroomstand.cd, sampleRate: 192000, bits: 24, lossless: true);
      expect(Uri.parse(uit).pathSegments.last, 'abc123.flac');
    });

    test('een onbekende diepte levert nooit maxBits=0 op', () {
      // Een catalogus van vóór deze versie geeft 0. Dat is "ik weet het niet", en dat mag nooit als
      // grens doorgegeven worden — ffmpeg krijgt dan `-bits_per_raw_sample 0`.
      final uit = metStand(_url, stand: Stroomstand.cd, sampleRate: 192000, bits: 0, lossless: true);
      final q = Uri.parse(uit).queryParameters;
      expect(q['maxRate'], '44100');
      expect(q.containsKey('maxBits'), isFalse);
    });

    test('een onbekende diepte alleen is geen reden om om te zetten', () {
      // 44,1 kHz en diepte onbekend: er is niets aantoonbaar te hoog, dus blijf van het bestand af.
      expect(metStand(_url, stand: Stroomstand.cd, sampleRate: 44100, bits: 0, lossless: true),
          _url);
    });

    test('de hi-res-sport laat 24 bit staan en zakt alleen in frequentie', () {
      final uit =
          metStand(_url, stand: Stroomstand.hoog, sampleRate: 192000, bits: 24, lossless: true);
      final q = Uri.parse(uit).queryParameters;
      expect(q['maxRate'], '48000');
      expect(q['maxBits'], '24');
    });
  });

  group('DE KERN: de speler herkent zijn eigen herschrijving terug', () {
    // Dit is de reden dat `omzettenGevraagd` bestaat in plaats van twee losse `contains('maxRate=')`
    // in player.dart. De speler hangt er twee dingen aan op: hoeveel geduld de stilstandwacht krijgt
    // (25 s in plaats van 10, want de pc is dan aan het omzetten en de teller staat op 0:00), en of
    // het de moeite waard is het volgende nummer met een HEAD vooruit klaar te zetten. Drijft de
    // naam van de grens uit elkaar, dan valt er niets om: je krijgt alleen weer "Er komt geen
    // geluid" op een kerngezonde pc, en het wachten tussen nummers is terug.
    test('wat metStand aanraakt herkent hij als omzetten', () {
      final uit =
          metStand(_url, stand: Stroomstand.cd, sampleRate: 192000, bits: 24, lossless: true);
      expect(omzettenGevraagd(uit), isTrue);
    });

    test('en wat hij met rust laat niet', () {
      // Alle vier de gevallen waarin de URL ongemoeid blijft.
      expect(
          omzettenGevraagd(
              metStand(_url, stand: Stroomstand.max, sampleRate: 192000, bits: 24, lossless: true)),
          isFalse);
      expect(
          omzettenGevraagd(metStand(_url,
              stand: Stroomstand.cd, sampleRate: 44100, bits: 16, lossless: true)),
          isFalse);
      expect(
          omzettenGevraagd(metStand(_url,
              stand: Stroomstand.cd, sampleRate: 192000, bits: 24, lossless: false)),
          isFalse);
      expect(omzettenGevraagd('file:///storage/emulated/0/Music/nummer.flac'), isFalse);
    });

    test('een adres dat alleen maxBits zou dragen bestaat niet', () {
      // Er is geen pad waarop `maxBits` er wel staat en `maxRate` niet — `metStand` schrijft ze
      // samen. Zou dat ooit veranderen, dan valt deze toets om voordat de speler stil geduldig wordt
      // op een adres dat wél omgezet wordt.
      final uit =
          metStand(_url, stand: Stroomstand.cd, sampleRate: 44100, bits: 24, lossless: true);
      expect(Uri.parse(uit).queryParameters.containsKey('maxBits'), isTrue);
      expect(omzettenGevraagd(uit), isTrue);
    });
  });

  group('welke bestanden lossless heten', () {
    test('de containers die de app zelf kan binnenhalen', () {
      for (final e in ['flac', '.flac', 'FLAC', 'wav', 'aiff', 'ape', 'wv', 'tta']) {
        expect(losslessExtensie(e), isTrue, reason: e);
      }
    });

    test('en de containers die dat niet zijn', () {
      for (final e in ['mp3', 'm4a', 'aac', 'ogg', 'opus', '']) {
        expect(losslessExtensie(e), isFalse, reason: e);
      }
    });
  });
}
