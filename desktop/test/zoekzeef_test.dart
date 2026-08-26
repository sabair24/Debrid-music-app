/// De zeef die bepaalt wat je NOOIT te zien krijgt.
///
/// **Waarom hier een toets op staat.** Tussen de bronnen en het scherm zit één regel die resultaten
/// wegwerpt omdat ze "geen muziek" zouden zijn. Zo'n regel is gevaarlijk op een manier die je niet
/// merkt: wat hij weggooit verschijnt nergens, ook niet als melding, dus een fout erin leest als
/// "die tracker heeft het gewoon niet".
///
/// En er zát een fout in. `blu-ray` en `remux` stonden op één hoop met `1080p` en `x264`, terwijl
/// een groot deel van de échte 24/96 en 24/192 juist van een Blu-Ray Audio of een DVD-Audio komt.
/// De beste hi-res die er te vinden was werd dus stilletjes weggegooid — precies het tegenovergestelde
/// van wat de zeef moest doen.
///
/// Het onderscheid dat er nu ligt: een RESOLUTIE of een VIDEOCODEC is altijd beeld, een HERKOMST is
/// dat pas als er verder niets naar geluid wijst.
library;

import 'package:debridmusic/search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DE KERN: hi-res van een Blu-Ray of DVD blijft staan', () {
    test('een Blu-Ray Audio van 24/96 is muziek, geen film', () {
      expect(isRommel('Pink Floyd - The Wall (1979) [Blu-Ray Audio] FLAC 24bit/96kHz'), isFalse);
      expect(isRommel('Dire Straits - Brothers In Arms (1985) BDRip FLAC 24-192'), isFalse);
      expect(isRommel('Kraftwerk - The Catalogue (2009) DVD-Audio APE lossless'), isFalse);
    });

    test('een remux met lossless erin ook', () {
      expect(isRommel('Various - Concert (2011) Remux DTS-HD FLAC'), isFalse);
    });

    test('maar zonder één woord over geluid blijft het weg', () {
      // Dan is er niets dat het van een film onderscheidt, en dan hoort het niet in een
      // muziekzoekopdracht thuis.
      expect(isRommel('Some Movie (2011) BluRay'), isTrue);
      expect(isRommel('Iets - Iets (2020) WEB-DL'), isTrue);
    });
  });

  group('wat altijd beeld is, blijft altijd weg', () {
    test('een resolutie of een videocodec', () {
      expect(isRommel('Concert 2011 1080p x264'), isTrue);
      expect(isRommel('Iets 720p HEVC'), isTrue);
      expect(isRommel('Iets 2160p'), isTrue);
    });

    test('ook mét FLAC erin — een concertfilm is nog steeds beeld', () {
      // Hier ligt de grens. "Blu-Ray + FLAC" is een muziekschijf; "1080p + FLAC" is een film met
      // een goede geluidsspoor, en dat is niet wat je zoekt als je een album zoekt.
      expect(isRommel('Metallica - S&M (1999) 1080p BluRay FLAC'), isTrue);
    });

    test('een filmcontainer in de naam', () {
      expect(isRommel('iets.mkv'), isTrue);
      expect(isRommel('iets.mp4'), isTrue);
    });

    test('en een videoclip', () {
      expect(isRommel('Artiest - Nummer (Music Video)'), isTrue);
    });
  });

  group('gewone muziek komt er gewoon door', () {
    test('een kale albumnaam', () {
      expect(isRommel('Air - Moon Safari (1998) FLAC'), isFalse);
      expect(isRommel('Rihanna - Good Girl Gone Bad'), isFalse);
      expect(isRommel('Кино - Группа крови (1988) APE'), isFalse);
    });

    test('een vinylrip en een SACD', () {
      expect(isRommel('Iemand - Iets (1975) Vinyl Rip 24bit/192kHz FLAC'), isFalse);
      expect(isRommel('Iemand - Iets SACD ISO DSD'), isFalse);
    });

    test('mp3 blijft ook gewoon muziek', () {
      expect(isRommel('Iemand - Iets (2001) MP3 320 kbps'), isFalse);
    });
  });

  group('de andere zeef doet nog wat hij deed', () {
    test('rommel voor volwassenen blijft weg', () {
      expect(isRommel('Iets XXX iets'), isTrue);
      expect(isRommel('brazzers iets'), isTrue);
    });

    test('en een naam die daar toevallig op lijkt niet', () {
      // "Sex" met een punt erachter is het patroon; een woord als "Sexy" hoort er niet in te vallen.
      expect(isRommel('Air - Sexy Boy (1998) FLAC'), isFalse);
    });
  });
}
