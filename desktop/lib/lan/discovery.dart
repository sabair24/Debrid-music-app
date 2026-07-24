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

/// A PC that answered. Everything the pairing screen needs to offer it by name.
class FoundServer {
  final String name;
  final Uri baseUrl;
  final int trackCount;

  const FoundServer({required this.name, required this.baseUrl, this.trackCount = 0});

  /// The address is the identity — two mechanisms find the same PC and it must appear once.
  @override
  bool operator ==(Object other) => other is FoundServer && other.baseUrl == baseUrl;

  @override
  int get hashCode => baseUrl.hashCode;
}

/// The other end of [LanDiscovery]: finding the PC from the Mac or the iPad.
///
/// Both mechanisms run together and the results are merged, for the same reason they are both
/// advertised. mDNS is what works without asking Apple for anything; the UDP probe is the one that
/// still answers when Bonjour is having a bad day on a mesh router. Whichever replies first, the
/// PC shows up — and typing the address by hand stays as the floor under both.
class LanBrowser {
  /// Ask the network, and collect for [timeout]. Never throws: a network that refuses to broadcast
  /// is a reason to type the address, not a reason for a red screen.
  static Future<List<FoundServer>> find({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final found = <Uri, FoundServer>{};
    await Future.wait([
      _probeUdp(found, timeout),
      _browseMdns(found, timeout),
    ]);
    final list = found.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  static Future<void> _probeUdp(Map<Uri, FoundServer> found, Duration timeout) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = socket?.receive();
        if (packet == null) return;
        try {
          final j = jsonDecode(utf8.decode(packet.data, allowMalformed: true));
          if (j is! Map || j['service'] != 'debridmusic') return;
          final port = (j['port'] as num?)?.toInt() ?? kDiscoveryPort;
          final url = Uri(scheme: 'http', host: packet.address.address, port: port);
          found[url] = FoundServer(
            name: (j['name'] ?? packet.address.address).toString(),
            baseUrl: url,
            trackCount: (j['trackCount'] as num?)?.toInt() ?? 0,
          );
        } catch (_) {/* something else answering on that port */}
      });

      final probe = Uint8List.fromList(utf8.encode(kProbe));
      // The global broadcast address, plus each interface's own. A Mac with a VPN up, or any host
      // with more than one interface, does not necessarily deliver 255.255.255.255 to the wifi the
      // PC is on — so ask on every interface we have rather than hoping.
      final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
      try {
        for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
          for (final addr in ni.addresses) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              targets.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
            }
          }
        }
      } catch (_) {/* no interface list — the global broadcast is still tried */}

      // Three times over the window: a single UDP packet is allowed to go missing, and the whole
      // point of this screen is that nothing has to be typed.
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        for (final t in targets) {
          try {
            socket.send(probe, t, kDiscoveryPort);
          } catch (_) {/* that interface will not broadcast */}
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    } catch (e) {
      debugPrint('LAN probe unavailable: $e');
    } finally {
      socket?.close();
    }
  }

  static Future<void> _browseMdns(Map<Uri, FoundServer> found, Duration timeout) async {
    nsd.Discovery? discovery;
    try {
      discovery = await nsd.startDiscovery(kServiceType, ipLookupType: nsd.IpLookupType.v4);
      discovery.addServiceListener((service, status) {
        if (status != nsd.ServiceStatus.found) return;
        final host = service.addresses?.firstOrNull?.address ?? service.host;
        final port = service.port;
        if (host == null || host.isEmpty || port == null) return;
        final url = Uri(scheme: 'http', host: host, port: port);
        // Do not overwrite a UDP answer: that one carried the track count.
        found.putIfAbsent(
          url,
          () => FoundServer(
            name: _txt(service, 'device') ?? service.name ?? host,
            baseUrl: url,
          ),
        );
      });
      await Future<void>.delayed(timeout);
    } catch (e) {
      debugPrint('LAN browse (mDNS) unavailable: $e');
    } finally {
      if (discovery != null) {
        try {
          await nsd.stopDiscovery(discovery);
        } catch (_) {/* already stopped */}
      }
    }
  }

  static String? _txt(nsd.Service s, String key) {
    final v = s.txt?[key];
    return v == null ? null : utf8.decode(v, allowMalformed: true);
  }
}
