/// De verlanglijst mag geen tweede vervalsing binnenhalen.
///
/// **Waarom dit bestaat.** `_chaseWant` mat niet vóór het opbergen, en dat maakte de knop "Laat de
/// app zoeken" erger dan nutteloos. `firstIsBetter` kent de regel *wat bewezen nep is verliest*, en
/// die staat bóven de grootte — maar een ONGEMETEN binnenkomer geldt niet als nep. Dus won élke
/// verse kopie van het bewezen neppe bestand in de bibliotheek, wat het ook was: de eigen kopie ging
/// naar `_dubbel` om plaats te maken voor de volgende vervalsing, de wens verviel, en `hasLossless`
/// telde de nieuwe mee. Stilletjes "opgelost", nog steeds nep.
///
/// GEMETEN op Sabers bibliotheek: van de 334 beoordeelde bestanden die meer dan 48 kHz claimen
/// hebben er 160 een lege bovenband of erger.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/lossless_want.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/soulseek.dart';

SoulseekFile _f(String naam,
        {int size = 30 * 1024 * 1024, int dur = 200, String user = 'peer'}) =>
    SoulseekFile(
      username: user,
      filename: r'music\Madonna\' + naam,
      size: size,
      speed: 0,
      queueLength: 0,
      freeSlots: true,
      durationSec: dur,
    );

const _afgekapt = Echtheidsoordeel(
  bits: Bitdiepte.spreektNietTegen,
  boven: Bovenband.onbekend,
  band: Bandbreedte.afgekapt,
  afkapHz: 16000,
  wandDb: 44,
  vensters: 32,
);

const _opgeschaald = Echtheidsoordeel(
  bits: Bitdiepte.spreektNietTegen,
  boven: Bovenband.leeg,
  band: Bandbreedte.doorlopend,
  vensters: 32,
);

const _opgeblazen = Echtheidsoordeel(
  bits: Bitdiepte.opgeblazen,
  boven: Bovenband.leeg,
  band: Bandbreedte.doorlopend,
  gebruikteBits: 16,
  vensters: 32,
);

/// Een gewone cd-rip: proef B en A kunnen hier niets zeggen (die draaien pas boven 48 kHz en boven
/// 16 bits), dus alleen de muurproef spreekt — en die zag geen muur.
const _echteCd = Echtheidsoordeel(
  bits: Bitdiepte.onbekend,
  boven: Bovenband.onbekend,
  band: Bandbreedte.doorlopend,
  vensters: 32,
);

LosslessWant _wens({List<VasteBron> nep = const [], Map<String, String> refused = const {}}) =>
    LosslessWant(
      artist: 'Madonna',
      title: 'La Isla Bonita',
      nep: nep,
      refused: refused,
    );

void main() {
  group('wat er binnen mag blijven', () {
    test('GEEN OORDEEL IS JA — een mislukte meting mag nooit iets weigeren', () {
      // Zonder ffmpeg, bij een te kort nummer, of bij een formaat waar `readFlacTags` niets van
      // maakt komt er geen oordeel. Dan hoort de downloadweg zich te gedragen als voorheen; het
      // uitvallen van een verrijking mag hem niet stilleggen.
      expect(DownloadManager.magBlijven(null), isTrue);
    });

    test('een uit mp3 omgezette kopie wordt geweigerd', () {
      expect(DownloadManager.magBlijven(_afgekapt), isFalse);
    });

    test('een opgeschaalde en een opgeblazen kopie ook', () {
      expect(DownloadManager.magBlijven(_opgeschaald), isFalse);
      expect(DownloadManager.magBlijven(_opgeblazen), isFalse);
    });

    test('een echte cd wordt AANGENOMEN, ook al is het geen hi-res', () {
      // Sabers eigen regel: "download soulseek 24/44.1 maar blijkt ook niet echt dan is het
      // 16/44.1 cd kwaliteit". Op zo'n bestand valt aan de bemonstering niets te liegen; alleen de
      // muurproef kan hem nog betrappen, en die zweeg.
      expect(DownloadManager.magBlijven(_echteCd), isTrue);
    });
  });

  group('welke kandidaten een wens nog mag proberen', () {
    test('een betrapte upload wordt de volgende ronde overgeslagen', () {
      final betrapt = _f('11 La Isla Bonita.flac', size: 27 * 1024 * 1024);
      final w = _wens(nep: [
        VasteBron(
            username: betrapt.username,
            filename: betrapt.filename,
            size: betrapt.size,
            durationSec: betrapt.durationSec)
      ]);
      final over = DownloadManager.kandidatenVoorWens(w, [betrapt]);
      expect(over, isEmpty, reason: 'dezelfde bytes nog eens halen geeft hetzelfde oordeel');
    });

    test('maar de PEER blijft bruikbaar voor een ander bestand', () {
      // Het bestand onthouden en niet de peer, en dat is het hele verschil. Wie één vervalsing
      // deelt heeft er tien goede naast, en dezelfde nep-upload staat bij honderd peers.
      final betrapt = _f('11 La Isla Bonita.flac', size: 27 * 1024 * 1024, user: 'djphysicust');
      final ander = _f('11 - La Isla Bonita.flac', size: 41 * 1024 * 1024, user: 'djphysicust');
      final w = _wens(nep: [
        VasteBron(
            username: betrapt.username,
            filename: betrapt.filename,
            size: betrapt.size,
            durationSec: betrapt.durationSec)
      ]);
      final over = DownloadManager.kandidatenVoorWens(w, [betrapt, ander]);
      expect(over.map((f) => f.size), [ander.size]);
    });

    test('één bestand per peer, want de top van de ranglijst is één verzamelaar', () {
      final a = _f('a.flac', user: 'verzamelaar');
      final b = _f('b.flac', user: 'verzamelaar');
      final c = _f('c.flac', user: 'iemand anders');
      final over = DownloadManager.kandidatenVoorWens(_wens(), [a, b, c]);
      expect(over.map((f) => f.username).toSet(), {'verzamelaar', 'iemand anders'});
      expect(over, hasLength(2));
    });

    test('een geweigerde peer blijft geweigerd', () {
      final f = _f('x.flac', user: 'geband');
      final over =
          DownloadManager.kandidatenVoorWens(_wens(refused: {'geband': 'banned'}), [f]);
      expect(over, isEmpty);
    });

    test('een mp3 komt er niet in, ook niet als er niets anders is', () {
      // "geen mp3, ten ware ik het manueel download". Vóór het binnenhalen is dit alles wat er te
      // weten valt; de tweede laag is de meting ná het binnenhalen.
      final mp3 = SoulseekFile(
        username: 'peer',
        filename: r'music\Madonna\11 La Isla Bonita.mp3',
        size: 8 * 1024 * 1024,
        speed: 0,
        queueLength: 0,
        freeSlots: true,
        durationSec: 200,
        bitrate: 320,
      );
      expect(DownloadManager.kandidatenVoorWens(_wens(), [mp3]), isEmpty);
    });
  });
}
