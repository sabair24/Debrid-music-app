import 'dart:io';

/// Every IPv4 address this machine answers on, loopback excluded, most-likely-LAN first.
///
/// Ordered because a PC often has several: a real network card, plus whatever Hyper-V, VirtualBox
/// or a VPN client left behind. Handing a phone the address of a virtual switch it cannot reach
/// looks exactly like "the app is broken", so the ordinary private ranges come first.
Future<List<String>> lanAddresses() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  final addresses = <String>[];
  for (final nic in interfaces) {
    for (final addr in nic.addresses) {
      if (addr.address.startsWith('169.254.')) continue; // self-assigned: no network behind it
      addresses.add(addr.address);
    }
  }
  addresses.sort((a, b) => _rank(a).compareTo(_rank(b)));
  return addresses;
}

/// Home networks first (192.168 and 10.x), then the rest.
int _rank(String ip) {
  if (ip.startsWith('192.168.')) return 0;
  if (ip.startsWith('10.')) return 1;
  if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) return 2;
  return 3;
}

/// The address of ours that [targetHost] can actually reach — our address on the same /24.
///
/// This is what a speaker gets told to fetch from. Sending a Sonos on 192.168.0.x a URL pointing
/// at our 172.x Hyper-V address means it fails silently, which is indistinguishable from the
/// track simply not playing.
Future<String?> lanAddressFor(String targetHost) async {
  final all = await lanAddresses();
  if (all.isEmpty) return null;
  final prefix = targetHost.split('.').take(3).join('.');
  for (final ip in all) {
    if (ip.startsWith('$prefix.')) return ip;
  }
  return all.first;
}

/// The best guess at "the address to type into the other device".
Future<String?> primaryLanAddress() async => (await lanAddresses()).firstOrNull;

/// Does this address reach us from OUTSIDE the house, or does it stop at the front door?
///
/// A 192.168 address is worthless on a phone that is on 5G, and that is not a small detail: it is
/// the difference between "my music works everywhere" and "my music works in the living room". A
/// Tailscale address works in both places — on the same network it still connects the two devices
/// directly, so there is no reason to hand out the LAN address when this one exists.
///
/// Recognised two ways because either alone is wrong somewhere. The range 100.64.0.0/10 is what
/// every node on a tailnet gets, but it is also RFC 6598 carrier-NAT space, so a machine could in
/// principle hold one for another reason. The adapter's name is the direct evidence — and Windows,
/// macOS and Linux each spell it differently, hence the loose match.
bool isRemoteReachable(String interfaceName, String ip) =>
    _looksLikeTailscaleAdapter(interfaceName) || _inTailscaleRange(ip);

/// Deliberately NOT matching macOS's `utun*`: Tailscale uses one, but so does every other VPN on
/// that platform, and calling a work VPN "reachable from anywhere" would hand out an address that
/// answers only while that VPN is up. There the 100.64/10 test carries it.
bool _looksLikeTailscaleAdapter(String name) {
  final n = name.toLowerCase();
  return n.contains('tailscale') || n == 'ts0';
}

/// 100.64.0.0/10 — that is 100.64.x.x through 100.127.x.x.
bool _inTailscaleRange(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4 || parts[0] != '100') return false;
  final second = int.tryParse(parts[1]);
  return second != null && second >= 64 && second <= 127;
}

/// Every address this machine answers on, split into the ones that only work at home and the ones
/// that work anywhere. Ordered as [lanAddresses] orders them, within each group.
Future<({List<String> overal, List<String> thuis})> addressesByReach() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  final overal = <String>[], thuis = <String>[];
  for (final nic in interfaces) {
    for (final addr in nic.addresses) {
      if (addr.address.startsWith('169.254.')) continue;
      (isRemoteReachable(nic.name, addr.address) ? overal : thuis).add(addr.address);
    }
  }
  thuis.sort((a, b) => _rank(a).compareTo(_rank(b)));
  return (overal: overal, thuis: thuis);
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
