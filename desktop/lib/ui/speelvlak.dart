/// Waar de hoes staat op het speelscherm, en hoe groot.
///
/// **Waarom dit een eigen bestand is.** Het speelscherm zelf is niet te pompen in een toets: het
/// hangt aan de speler, aan de bibliotheek en aan de speakerkeuze, en die bestaan in een toetsrun
/// geen van drieën. De REKENSOM eronder hangt nergens aan — en dat is precies de som die fout kan
/// gaan zonder dat je het ziet.
///
/// # De som, en waarom hij bestaat
///
/// Op een breed venster stond dit scherm als een kolom in het midden met links en rechts samen
/// duizend punten zwart. De hoes werd uit de HOOGTE gerekend en bleef daardoor klein terwijl er
/// breedte over was.
///
/// De hoes gaat dus links staan en de tekst ernaast. Maar de cd schuift ZIJWAARTS uit de hoes, naar
/// rechts — precies de kant waar die tekstkolom komt. `AlbumArt` reserveert die loopruimte in zijn
/// eigen breedte: het blok is `hoes + hoes × reisfactor`, oftewel 1,62 × de hoes op een breed
/// scherm. Rekent iemand daar niet mee, dan schuift de plaat bij het afspelen onder de titel.
///
/// `test/speelvlak_test.dart` bewaakt precies dat: de uitgeschoven cd raakt de kolom nooit.
library;

import 'dart:ui' show Size;

import 'maten.dart';

/// De breedte van de kolom naast de hoes.
///
/// 520 en niet "wat er over is": hier staan de titel, de spoelbalk en de transportknoppen in, en die
/// drie hebben een maat die niet met het venster hoort mee te groeien. Een spoelbalk van elfhonderd
/// punten is geen betere spoelbalk. Ligt dicht bij de 540 die de gestapelde indeling al aanhield.
const double kSpeelKolom = 520;

/// Het gat tussen het hoesblok en die kolom.
///
/// Gemeten vanaf waar de UITGESCHOVEN cd ophoudt, niet vanaf de rand van de hoes — die loopruimte
/// zit al in de breedte van het blok.
const double kSpeelGat = 64;

/// Vanaf welk venster de hoes naast de tekst gaat staan in plaats van erboven.
///
/// Onder deze breedte blijft er na de kolom, het gat en de twee goten te weinig over voor een hoes
/// die het waard is. Op 1100 punten is dat 468 voor het blok, dus een hoes van 289 — nog net groter
/// dan wat de gestapelde indeling er op die breedte van maakt. Daaronder zou de verbouwing hem juist
/// kleiner maken, en dat is het omgekeerde van de bedoeling.
const double kSpeelVanaf = 1100;

/// En hoog genoeg dat de kolom ernaast past.
///
/// De titel, de artiestregel, de spoelbalk en de knoppenrij zijn samen ruim tweehonderd punten. In
/// de gestapelde indeling duwt dat de hoes kleiner; naast elkaar zou het over de onderrand lopen, en
/// dan staat er een zwart-gele streep over de transportknoppen.
const double kSpeelHoogte = 460;

/// De lucht boven en onder het blok: de balk met de chevron en de puntjes, plus marge.
const double _lucht = 68 + kRuimte32 * 2;

/// Staat de hoes naast de tekst, of erboven?
///
/// **Een televisie krijgt hem met opzet niet**, hoe breed 960 punten ook zijn. Op de Shield is de
/// hoes de rustplek van de markering, en links en rechts zijn daar vorige en volgende. Staat de
/// knoppenrij dan RECHTS van de hoes, dan is hij met de pijlen niet meer te bereiken: rechts wordt
/// opgeslokt door "volgend nummer". Dat is geen scheve opmaak maar een scherm waar je niet meer uit
/// komt, en het is van hieruit niet na te kijken.
bool naastElkaar({required Size scherm, required bool compact, required bool tv}) =>
    !compact && !tv && scherm.width >= kSpeelVanaf && scherm.height >= kSpeelHoogte;

/// De maat van de hoes in de indeling naast elkaar.
///
/// Hier is de BREEDTE de bindende grens en niet de hoogte, en dat is de hele winst: op een venster
/// van 1600 bij 867 wordt de hoes ongeveer 597, waar de gestapelde regel er 399 van maakte.
///
/// [reisfactor] is `discTravelFactor`: 0,62 op een breed scherm. Er wordt door `1 + reisfactor`
/// gedeeld en niet door 1 — dat is de hele reden dat de cd niet in de tekst schuift.
double hoesNaast({required Size scherm, required double reisfactor}) {
  final voorHetBlok = scherm.width - kGoot * 2 - kSpeelGat - kSpeelKolom;
  final opBreedte = voorHetBlok / (1 + reisfactor);
  final opHoogte = scherm.height - _lucht;
  final kleinste = opBreedte < opHoogte ? opBreedte : opHoogte;
  // Het plafond is er tegen een scherm van drieduizend punten breed: een hoes van veertienhonderd is
  // geen hoes meer maar behang.
  return kleinste.clamp(240.0, 720.0);
}

/// Hoe breed het hoesblok werkelijk is: de hoes plus de ruimte waar de cd in uitschuift.
double blokBreedte({required double hoes, required double reisfactor}) => hoes * (1 + reisfactor);
