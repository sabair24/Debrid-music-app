/// Welk adres werkt nog als de gsm het huis uit loopt?
///
/// Dit is geen cosmetische vraag. Een gsm die gekoppeld is aan `192.168.0.117` doet het perfect in
/// de zetel en zwijgt op straat, zonder dat er iets op het scherm verschijnt dat uitlegt waarom.
/// De volgorde die hier wordt vastgelegd is precies wat dat voorkomt.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/net.dart';

void main() {
  group('welke adressen gaan mee naar buiten', () {
    test('het bereik van Tailscale is 100.64 tot en met 100.127', () {
      expect(isRemoteReachable('Ethernet', '100.64.0.1'), isTrue);
      expect(isRemoteReachable('Ethernet', '100.101.42.7'), isTrue);
      expect(isRemoteReachable('Ethernet', '100.127.255.254'), isTrue);

      // Net erbuiten. 100.63 en 100.128 zijn gewone publieke adressen van iemand anders — die als
      // "dit is jouw pc, overal bereikbaar" tonen zou een adres opleveren dat naar een vreemde wijst.
      expect(isRemoteReachable('Ethernet', '100.63.255.255'), isFalse);
      expect(isRemoteReachable('Ethernet', '100.128.0.1'), isFalse);
    });

    test('een thuisadres blijft een thuisadres', () {
      expect(isRemoteReachable('Ethernet', '192.168.0.117'), isFalse);
      expect(isRemoteReachable('Ethernet 2', '192.168.56.1'), isFalse); // VirtualBox
      expect(isRemoteReachable('Wi-Fi', '10.0.0.5'), isFalse);
      expect(isRemoteReachable('Ethernet', '172.17.0.1'), isFalse); // Docker
    });

    test('de naam van de kaart telt ook mee, want een tailnet mag herNummeren', () {
      expect(isRemoteReachable('Tailscale', '10.99.0.4'), isTrue);
      expect(isRemoteReachable('tailscale0', '10.99.0.4'), isTrue);
      expect(isRemoteReachable('ts0', '10.99.0.4'), isTrue);
    });

    test('een gewone VPN gaat NIET door voor overal bereikbaar', () {
      // Zonder deze grens zou een werk-VPN of NordVPN een adres opleveren dat alleen antwoordt
      // zolang die VPN aanstaat — en dat is precies het soort adres dat stilletjes stopt te werken.
      expect(isRemoteReachable('utun3', '10.8.0.2'), isFalse);
      expect(isRemoteReachable('NordLynx', '10.5.0.2'), isFalse);
      expect(isRemoteReachable('WireGuard Tunnel', '10.7.0.2'), isFalse);
    });

    test('rommel maakt er geen buitenadres van', () {
      expect(isRemoteReachable('Ethernet', ''), isFalse);
      expect(isRemoteReachable('Ethernet', '100'), isFalse);
      expect(isRemoteReachable('Ethernet', '100.64.0'), isFalse);
      expect(isRemoteReachable('Ethernet', '100.abc.0.1'), isFalse);
      expect(isRemoteReachable('Ethernet', '169.254.24.5'), isFalse);
    });
  });

  test('deze pc splitst zichzelf zonder te struikelen', () async {
    // Draait tegen de echte netwerkkaarten: geen verwachting over WAT er staat, wel dat de twee
    // groepen elkaar niet overlappen en dat geen enkel zelftoegewezen adres erin sluipt.
    final split = await addressesByReach();
    for (final ip in split.overal) {
      expect(split.thuis, isNot(contains(ip)), reason: 'een adres hoort in precies een groep');
      expect(ip.startsWith('169.254.'), isFalse);
    }
    for (final ip in split.thuis) {
      expect(isRemoteReachable('Ethernet', ip), isFalse,
          reason: '$ip staat bij thuis maar zou als buitenadres gelden');
    }
  });
}
