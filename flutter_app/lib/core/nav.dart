import 'package:flutter/material.dart';

class NavItem {
  final String key; // routing/i18n key, e.g. "ping"
  final IconData icon;
  const NavItem(this.key, this.icon);
}

const List<NavItem> kTools = [
  NavItem('ping', Icons.show_chart),
  NavItem('trace', Icons.route),
  NavItem('telnet', Icons.power),
  NavItem('dns', Icons.public),
  NavItem('cert', Icons.verified_user),
  NavItem('http', Icons.bolt),
  NavItem('sweep', Icons.radar),
  NavItem('subnet', Icons.grid_view),
  NavItem('urlcheck', Icons.search),
];
