/// De minimale iOS-versie, en dat hij niet stilletjes terugzakt.
///
/// **Waarom dit bestaat.** Apple stuurde na élke levering een mail:
///
///   > ITMS-90068: MinimumOSVersion too low — This app has a MinimumOSVersion of 13.0. Starting in
///   > Spring 2027, all iOS apps must have a MinimumOSVersion of 15.0 or later in order to be
///   > uploaded to App Store Connect or submitted for distribution.
///
/// De levering slaagde nog wél, dus de bouwstraat werd er nooit rood van en de bouwlogboeken
/// zeggen er niets over — dit kwam alleen per e-mail binnen. Vanaf voorjaar 2027 is het geen
/// waarschuwing meer maar een weigering.
///
/// `MinimumOSVersion` in de gebouwde app komt rechtstreeks uit `IPHONEOS_DEPLOYMENT_TARGET`. Er is
/// geen tweede plek waar dat getal staat: `Flutter/AppFrameworkInfo.plist` heeft de sleutel niet
/// meer (uit het Flutter-sjabloon verdwenen) en `Runner/Info.plist` heeft hem ook niet. Wie hem
/// daar toevoegt, verandert niets aan wat Apple ziet.
///
/// Waarom een toets en geen aantekening: het iOS-mapje is gegenereerd. Wordt hij ooit opnieuw
/// aangemaakt of bijgewerkt door een nieuwe Flutter, dan staat de sjabloonwaarde er weer, en dan
/// begint dezelfde mail opnieuw — zonder dat iets rood wordt.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// "15.0" → 15.0, zodat 15.4 of 16 ook slaagt en alleen ZAKKEN faalt.
double _versie(String tekst) {
  final delen = tekst.trim().split('.');
  final hoofd = int.tryParse(delen.first) ?? 0;
  final onder = delen.length > 1 ? (int.tryParse(delen[1]) ?? 0) : 0;
  return hoofd + onder / 100;
}

const _minimaal = 15.0;

void main() {
  test('elk bouwprofiel staat op iOS 15.0 of hoger', () {
    final bron = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final treffers = RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);')
        .allMatches(bron)
        .map((m) => m.group(1)!)
        .toList();

    // Debug, Profile en Release. Eén vergeten profiel is precies hoe dit terugkomt: Release goed,
    // en de archivering pakt er toch een andere.
    expect(treffers.length, 3,
        reason: 'er horen drie bouwprofielen te zijn (Debug, Profile, Release) — gevonden: $treffers');
    for (final t in treffers) {
      expect(_versie(t), greaterThanOrEqualTo(_minimaal),
          reason: 'iOS $t is te laag: Apple weigert vanaf voorjaar 2027 alles onder $_minimaal '
              '(ITMS-90068)');
    }
  });

  test('de pods lopen mee, want anders blijven die op de ondergrens van Flutter', () {
    final podfile = File('ios/Podfile').readAsStringSync();
    // Alleen een regel die ECHT geldt: het sjabloon levert hem uitgecommentarieerd, en dan pakken
    // de pods de ondergrens van Flutter. Gemeten in de Apple-bouw van 3.9.278 was dat een mengsel
    // van ios12.0 en ios13.0, terwijl het project zelf op 13.0 stond.
    final regel = podfile
        .split('\n')
        .map((r) => r.trim())
        .firstWhere((r) => r.startsWith('platform :ios'), orElse: () => '');
    expect(regel, isNotEmpty,
        reason: 'zonder een niet-uitgecommentarieerde `platform :ios` bouwen de pods op wat Flutter '
            'toevallig als ondergrens heeft');

    final versie = RegExp(r"platform :ios, *'([0-9.]+)'").firstMatch(regel)?.group(1);
    expect(versie, isNotNull, reason: 'onleesbare platformregel: $regel');
    expect(_versie(versie!), greaterThanOrEqualTo(_minimaal),
        reason: 'de pods staan op $versie en het project op $_minimaal of hoger — die twee horen '
            'gelijk te lopen');
  });

  test('niemand heeft MinimumOSVersion er alsnog met de hand bij gezet', () {
    // Een tweede plek met datzelfde getal is geen extra zekerheid maar een tweede waarheid, en de
    // volgende die hem verhoogt vergeet er één. Xcode schrijft de sleutel zelf.
    for (final pad in ['ios/Runner/Info.plist', 'ios/Flutter/AppFrameworkInfo.plist']) {
      final f = File(pad);
      if (!f.existsSync()) continue;
      expect(f.readAsStringSync(), isNot(contains('MinimumOSVersion')),
          reason: '$pad zet MinimumOSVersion met de hand; dat getal hoort alleen uit '
              'IPHONEOS_DEPLOYMENT_TARGET te komen');
    }
  });
}
