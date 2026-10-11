/// Welke bestanden uit een Soulseek-zoekopdracht één bepaald nummer van de plaat zijn — buiten de
/// UI-draad als het er veel zijn.
///
/// **Waarom dit apart staat.** "Ontbrekende downloaden" op de albumpagina zocht één keer voor de
/// hele plaat en zeefde die lijst daarna per ontbrekend nummer met [fileOffersTitle]. Op de S26 stond
/// de UI-draad daarbij 2078 ms stil (warmte.log, 11-10-2026, *Morning Glory*, elf nummers). Gemeten op
/// de pc: 5,3 µs per bestand, dus elf nummers over 4400 bestanden is 254 ms, en een telefoon doet er
/// een veelvoud over. Dat het één blok werd en geen elf kleine, kwam doordat het albumbrede resultaat
/// na het eerste nummer klaarligt: elke volgende beurt liep als microtaak door zonder de draad ooit
/// vrij te geven.
library;

import 'dart:isolate';

import 'organize.dart' show fileOffersTitle;
import 'soulseek.dart' show SoulseekFile;

/// De zeef zelf, zonder isolate. Voor wie hem op één titel tegelijk nodig heeft en het resultaat
/// onthoudt, zoals de telling naast elke rij op de catalogusalbumpagina.
List<SoulseekFile> zeefKandidatenNu(List<SoulseekFile> files,
        {required String titel, int? seconden, required String artiest, String? album}) =>
    [
      for (final f in files)
        if (f.isAudio &&
            fileOffersTitle(titel, seconden, artiest, f.filename, f.durationSec, album: album))
          f
    ];

/// Dezelfde zeef in een eigen isolate. Altijd, ook voor een korte lijst: een isolate opstarten kost
/// een paar milliseconden, en dit draait midden in een download die er seconden over doet.
///
/// Hier op het hoogste niveau en niet in een methode van de pagina: een sluiting die `this` vangt,
/// sleept de hele `State` mee naar de isolate, en dat weigert Dart.
Future<List<SoulseekFile>> zeefKandidaten(List<SoulseekFile> files,
        {required String titel, int? seconden, required String artiest, String? album}) =>
    Isolate.run(() =>
        zeefKandidatenNu(files, titel: titel, seconden: seconden, artiest: artiest, album: album));
