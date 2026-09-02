class CidrInfo {
  final int network, broadcast, prefix, size, ip;
  final String? error;
  CidrInfo({this.network = 0, this.broadcast = 0, this.prefix = 0, this.size = 0, this.ip = 0, this.error});
}

int? ipToInt(String s) {
  final parts = s.split('.');
  if (parts.length != 4) return null;
  var v = 0;
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return null;
    v = (v << 8) | n;
  }
  return v;
}

String intToIp(int v) => [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255].join('.');

CidrInfo parseCidr(String raw) {
  final s = raw.trim();
  final m = RegExp(r'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/(\d{1,2})$').firstMatch(s);
  if (m == null) return CidrInfo(error: 'Format: 192.168.1.0/24');
  final base = ipToInt(m.group(1)!);
  final prefix = int.parse(m.group(2)!);
  if (base == null || prefix < 0 || prefix > 32) return CidrInfo(error: 'Invalid CIDR');
  final hostBits = 32 - prefix;
  final size = hostBits >= 32 ? 4294967296 : (1 << hostBits);
  final network = hostBits == 32 ? 0 : (base & (0xFFFFFFFF << hostBits)) & 0xFFFFFFFF;
  final broadcast = hostBits == 32 ? 0xFFFFFFFF : (network + size - 1) & 0xFFFFFFFF;
  return CidrInfo(network: network, broadcast: broadcast, prefix: prefix, size: size, ip: base);
}

int? neededPrefix(int hosts) {
  if (hosts <= 0) return null;
  if (hosts == 1) return 32;
  if (hosts == 2) return 31;
  var bits = 1;
  while ((1 << bits) - 2 < hosts) {
    bits++;
  }
  return 32 - bits;
}
