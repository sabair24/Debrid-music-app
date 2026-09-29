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
import 'package:debridmusic/keuring.dart';
import 'package:debridmusic/lossless_want.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart';
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

  /// Schoon zijn is niet genoeg — hij moet BEWEZEN beter zijn dan wat er ligt.
  ///
  /// GEMETEN aan het echte werk op 08-09-2026: een proefjacht op "Madonna — La Isla Bonita" nam na twee
  /// terecht weggegooide opgeschaalde kopieën een eerlijke 16/48 aan, die niets beter was dan de
  /// opgeschaalde 24/96 die er lag. Daarvoor kwam hier een eigen toets, `draagtGenoeg` ("minstens
  /// evenveel").
  ///
  /// **Sinds 29-09-2026 geldt op de wensweg dezelfde regel als overal: strikt beter, bewezen** — zie
  /// `keuring.dart`. Met "minstens evenveel" ruilde de wens Sabers opgeschaalde 24/96 van Is It Scary in
  /// voor een eerlijke 24/48 en die van Stranger In Moscow voor een 24/44,1, en dat las hij als "mindere
  /// kwaliteit": "als er een slechtere binnenkomt dan wat ik heb moet die weg, en moet mijn betere
  /// kwaliteit die ik al had blijven." Het is daarmee ook een bewuste terugdraai van een eerdere vraag,
  /// "download soulseek 24/44.1" — die ruil gaat niet meer, want hij is geen winst.
  group('een vervanger moet bewezen beter zijn', () {
    const opgeschaald = Echtheidsoordeel(
        bits: Bitdiepte.spreektNietTegen, boven: Bovenband.leeg, band: Bandbreedte.doorlopend);
    const echt96 = Echtheidsoordeel(
        bits: Bitdiepte.spreektNietTegen, boven: Bovenband.vol, band: Bandbreedte.doorlopend);
    const uitMp3 = Echtheidsoordeel(
        bits: Bitdiepte.onbekend, boven: Bovenband.onbekend, band: Bandbreedte.afgekapt, afkapHz: 17200);
    final opgeschaald96 = kwaliteitUit(verliesvrij: true, kopRate: 96000, formaat: 4, oordeel: opgeschaald);

    test('een eerlijke 16/48 vervangt een opgeschaalde 24/96 NIET', () {
      final eerlijk48 = kwaliteitUit(verliesvrij: true, kopRate: 48000, formaat: 4);
      expect(vergelijkKwaliteit(eerlijk48, opgeschaald96), 0);
    });

    test('en een eerlijke 24/44.1 sinds 29-09-2026 ook niet meer — gelijk is geen winst', () {
      final eerlijk = kwaliteitUit(verliesvrij: true, kopRate: 44100, formaat: 4);
      expect(vergelijkKwaliteit(eerlijk, opgeschaald96), 0);
    });

    test('maar een GEMETEN echte 24/96 wél', () {
      final echt = kwaliteitUit(verliesvrij: true, kopRate: 96000, formaat: 4, oordeel: echt96);
      expect(vergelijkKwaliteit(echt, opgeschaald96), greaterThan(0));
    });

    test('en een eerlijke cd vervangt wél een uit mp3 omgezette kopie', () {
      final cd = kwaliteitUit(verliesvrij: true, kopRate: 44100, formaat: 4);
      final nep = kwaliteitUit(verliesvrij: true, kopRate: 44100, formaat: 4, oordeel: uitMp3);
      expect(vergelijkKwaliteit(cd, nep), greaterThan(0));
    });

    test('niet te lezen is geen bewijs, en dus geen vervanging', () {
      // Tot 29-09-2026 was "niet te lezen" hier een ja. Maar niets weten is niets bewijzen, en dan
      // blijft wat er stond.
      final onleesbaar = kwaliteitUit(verliesvrij: true, kopRate: 0, formaat: 4);
      expect(vergelijkKwaliteit(onleesbaar, opgeschaald96), 0);
    });
  });

  /// Een vervanger moet DEZELFDE OPNAME zijn — anders landt hij ernaast en blijft de nep staan.
  ///
  /// GEMETEN op 08-09-2026. Van de 22 bestanden die de jacht die avond binnenhaalde landden er elf
  /// als `(2)` naast het origineel, en van de zes waar het origineel nog naast lag was het elke
  /// keer een andere uitgave: Whitney Houston "It's Not Right But It's Okay" 3:33 tegen 4:52,
  /// Natasha St-Pier "Tu trouveras" 3:42 tegen 4:59, Garou "Sous le vent" 4:38 tegen 3:31, en de
  /// kleinste misser Whigfield "Saturday Night (radio edit)" 3:40 tegen 3:58 — achttien seconden.
  group('een vervanger moet dezelfde opname zijn', () {
    test('een radio-edit vervangt de albumversie NIET', () {
      expect(DownloadManager.zelfdeLengte(292, 213), isFalse, reason: "It's Not Right, 79s scheelt");
      expect(DownloadManager.zelfdeLengte(238, 220), isFalse, reason: 'Whigfield, 18s scheelt');
      expect(DownloadManager.zelfdeLengte(252, 233), isFalse, reason: 'Miss You Much, 20s scheelt');
    });

    test('twee ripjes van dezelfde plaat mogen een paar tellen schelen', () {
      // Een andere gapless-snit of wat stilte aan het eind; dat is geen andere uitgave.
      expect(DownloadManager.zelfdeLengte(292, 292), isTrue);
      expect(DownloadManager.zelfdeLengte(292, 294), isTrue);
      expect(DownloadManager.zelfdeLengte(292, 286), isTrue);
      expect(DownloadManager.zelfdeLengte(292, 285), isFalse, reason: 'zeven is over de grens');
    });

    test('ONBEKEND IS JA — een peer die geen duur meldt valt daar niet op af', () {
      // Dezelfde regel als bij `magBlijven` en `draagtGenoeg`: een ontbrekende meting mag nooit
      // iets weigeren. Wat er zo doorheen glipt wordt ná het binnenhalen alsnog gemeten.
      expect(DownloadManager.zelfdeLengte(292, null), isTrue);
      expect(DownloadManager.zelfdeLengte(null, 213), isTrue);
      expect(DownloadManager.zelfdeLengte(292, 0), isTrue);
      expect(DownloadManager.zelfdeLengte(0, 213), isTrue);
    });

    test('en de zeef laat een verkeerde lengte niet eens beginnen', () {
      final goed = _f('01 It\'s Not Right But It\'s Okay.flac', dur: 292, user: 'a');
      final edit = _f('It\'s Not Right But It\'s Okay (radio edit).flac', dur: 213, user: 'b');
      final w = LosslessWant(
        artist: 'Whitney Houston',
        title: "It's Not Right But It's Okay",
        authority: const TrackTags(
            artist: 'Whitney Houston',
            title: "It's Not Right But It's Okay",
            album: 'My Love Is Your Love',
            trackNo: 1,
            seconds: 292),
      );
      final over = DownloadManager.kandidatenVoorWens(w, [goed, edit]);
      expect(over.map((f) => f.username), ['a']);
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

    test('een peer die net nee zei wordt over ALLE wensen heen overgeslagen', () {
      // GEMETEN op 08-09-2026: `Inhabitantz+` kostte 24,4 minuten, verdeeld over DRIE verschillende
      // wensen — elke keer acht minuten wachten en dan "Geweigerd: Queued". `refused` staat per
      // wens, dus elke nieuwe wens ontdekte dezelfde dode peer opnieuw.
      final dood = _f('a.flac', user: 'Inhabitantz+');
      final levend = _f('b.flac', user: 'iemand anders');
      final over = DownloadManager.kandidatenVoorWens(_wens(), [dood, levend],
          rustendePeers: {'Inhabitantz+'});
      expect(over.map((f) => f.username), ['iemand anders']);
    });

    test('maar rust maakt de lijst nooit LEEG', () {
      // Een optimalisatie mag "een paar kandidaten" niet in "geen enkele" veranderen: dan valt de
      // wens stil terwijl er wel degelijk iets te proberen viel.
      final enige = _f('a.flac', user: 'Inhabitantz+');
      final over = DownloadManager.kandidatenVoorWens(_wens(), [enige],
          rustendePeers: {'Inhabitantz+'});
      expect(over.map((f) => f.username), ['Inhabitantz+']);
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
