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

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
