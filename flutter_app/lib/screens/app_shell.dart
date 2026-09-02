import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/i18n.dart';
import '../core/nav.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import 'dashboard_screen.dart';
import 'ping_screen.dart';
import 'trace_screen.dart';
import 'telnet_screen.dart';
import 'dns_screen.dart';
import 'cert_screen.dart';
import 'http_screen.dart';
import 'sweep_screen.dart';
import 'subnet_screen.dart';
import 'urlcheck_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String _view = 'dashboard';

  Widget _page(String v) => switch (v) {
        'ping' => const PingScreen(),
        'trace' => const TraceScreen(),
        'telnet' => const TelnetScreen(),
        'dns' => const DnsScreen(),
        'cert' => const CertScreen(),
        'http' => const HttpScreen(),
        'sweep' => const SweepScreen(),
        'subnet' => const SubnetScreen(),
        'urlcheck' => const UrlCheckScreen(),
        'settings' => const SettingsScreen(),
        _ => DashboardScreen(onGo: (v2) => setState(() => _view = v2)),
      };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = AppTheme(state.isDark);
    final c = theme.c;

    return Scaffold(
      backgroundColor: c.bgDeep,
      body: Row(children: [
        Container(
          width: 232,
          decoration: BoxDecoration(color: c.bgBase, border: Border(right: BorderSide(color: c.line))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
              child: Row(children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.terminal, color: c.accentInk, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('Network Console', style: theme.display.copyWith(fontSize: 15), overflow: TextOverflow.ellipsis)),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: kTools.asMap().entries.map((e) {
                  final item = e.value;
                  final active = _view == item.key;
                  return _NavRow(
                    icon: item.icon,
                    label: t(state.lang, 'nav.${item.key}'),
                    number: (e.key + 1).toString().padLeft(2, '0'),
                    active: active,
                    c: c,
                    onTap: () => setState(() => _view = item.key),
                  );
                }).toList(),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: state.agentConnected ? c.ok : c.inkGhost)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(state.agentConnected ? (state.agent.lastHealth?['host']?.toString() ?? 'agent') : 'searching…', style: TextStyle(color: c.inkGhost, fontSize: 10.5), overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 12),
                _NavRow(icon: Icons.settings, label: t(state.lang, 'nav.settings'), number: null, active: _view == 'settings', c: c, onTap: () => setState(() => _view = 'settings')),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: Column(children: [
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.lineSoft))),
              child: Row(children: [
                Text(_view == 'dashboard' ? '' : '/ ${t(state.lang, 'nav.$_view').toUpperCase()}', style: TextStyle(color: c.inkGhost, fontSize: 11, letterSpacing: 1)),
              ]),
            ),
            Expanded(child: _page(_view)),
          ]),
        ),
      ]),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? number;
  final bool active;
  final AppColors c;
  final VoidCallback onTap;
  const _NavRow({required this.icon, required this.label, required this.number, required this.active, required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? c.accentWeak : Colors.transparent,
          border: Border.all(color: active ? c.accentLine : Colors.transparent),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: active ? c.accent : c.inkFaint),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w500, color: active ? c.ink : c.inkFaint))),
          if (number != null) Text(number!, style: GoogleFonts.spaceMono(fontSize: 9, color: c.inkGhost)),
        ]),
      ),
    );
  }
}
