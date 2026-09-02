import 'package:flutter/material.dart';

/// Arac adlari markaya ait sabit isimler - dil ne olursa olsun (EN/TR/...)
/// hep orijinal Ingilizce haliyle gosterilir (bkz. NavItem.label).
class NavItem {
  final String key; // routing/i18n key, e.g. "ping"
  final String label; // sabit, hic cevrilmez
  final IconData icon;
  const NavItem(this.key, this.label, this.icon);
}

const List<NavItem> kTools = [
  NavItem('ping', 'Ping', Icons.show_chart),
  NavItem('trace', 'Trace', Icons.route),
  NavItem('telnet', 'Telnet', Icons.power),
  NavItem('dns', 'DNS', Icons.public),
  NavItem('cert', 'Certificate', Icons.verified_user),
  NavItem('http', 'HTTP', Icons.bolt),
  NavItem('sweep', 'IP Scan', Icons.radar),
  NavItem('subnet', 'Subnet', Icons.grid_view),
  NavItem('urlcheck', 'URL Check', Icons.search),
];

const Map<String, String> kToolLabel = {
  'ping': 'Ping', 'trace': 'Trace', 'telnet': 'Telnet', 'dns': 'DNS',
  'cert': 'Certificate', 'http': 'HTTP', 'sweep': 'IP Scan', 'subnet': 'Subnet',
  'urlcheck': 'URL Check', 'settings': 'Settings', 'dashboard': 'Dashboard',
};
