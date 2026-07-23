import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;

/// The DNS-SD type the other apps browse for. Registered nowhere official — it only has to be
/// unique on your own network, and matching between this app and its clients.
const String kServiceType = '_debridmusic._tcp';

/// The UDP port the "is DebridMusic out there?" probe goes to. Same number as the HTTP port on
/// purpose — one number to remember, and TCP and UDP don't collide.
const int kDiscoveryPort = 47820;

/// What a probe answers with.
const String kProbe = 'DEBRIDMUSIC?';

/// Makes this PC findable, so nothing has to be typed in by hand.
///
/// Two mechanisms, deliberately. Bonjour/mDNS is what the iPad and the Mac can use without asking
/// Apple for the multicast entitlement, and it is what Android's NsdManager speaks. But the Dart
/// mDNS package's Windows support grew out of a prototype, and this is a Windows app — so a plain
/// UDP responder runs beside it. If one of the two is silent the devices still find the PC.
class LanDiscovery {
  LanDiscovery({
    required this.port,
    required this.deviceName,
    required this.trackCount,
  });

  final int port;
  final String deviceName;

  /// Read at announce time, so the number a client sees is current rather than whatever it was
  /// when discovery started.
  final int Function() trackCount;

  RawDatagramSocket? _udp;
  nsd.Registration? _registration;

  bool get advertising => _registration != null;
  bool get responding => _udp != null;

  Future<void> start() async {
    await Future.wait([_startUdp(), _startMdns()]);
  }

  Future<void> _startUdp() async {
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kDiscoveryPort);
      _udp!.broadcastEnabled = true;
      _udp!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = _udp?.receive();
        if (packet == null) return;
        final message = utf8.decode(packet.data, allowMalformed: true).trim();
        if (!message.startsWith(kProbe)) return;
        // Answer straight back to whoever asked. They learn our address from the packet's
        // source, so the reply never has to guess which of our interfaces they can reach.
        final reply = utf8.encode(jsonEncode(descriptor()));
        _udp?.send(Uint8List.fromList(reply), packet.address, packet.port);
      });
    } on SocketException catch (e) {
      // Another copy of the app, or something else on that port. Not fatal — mDNS and typing the
      // address by hand both still work.
      debugPrint('LAN discovery (UDP) unavailable: ${e.message}');
    }
  }

  Future<void> _startMdns() async {
    try {
      _registration = await nsd.register(nsd.Service(
        name: 'DebridMusic op $deviceName',
        type: kServiceType,
        port: port,
        txt: {
          'v': utf8.encode('1'),
          'device': utf8.encode(deviceName),
        },
      ));
    } catch (e) {
      debugPrint('LAN discovery (mDNS) unavailable: $e');
    }
  }

  /// What a device learns about us before it has a token.
  ///
  /// Deliberately harmless: a name, a port and how big the library is. No token — pairing is a
  /// thing you do on purpose, by reading the code off the PC's screen.
  Map<String, dynamic> descriptor() => {
        'service': 'debridmusic',
        'name': deviceName,
        'port': port,
        'trackCount': trackCount(),
      };

  Future<void> stop() async {
    _udp?.close();
    _udp = null;
    final registration = _registration;
    _registration = null;
    if (registration != null) {
      try {
        await nsd.unregister(registration);
      } catch (_) {/* already gone, or the platform never registered it */}
    }
  }
}
