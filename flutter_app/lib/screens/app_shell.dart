import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/constants.dart';
import '../core/nav.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../widgets/title_bar.dart';
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

const List<String> _viewOrder = [
  'dashboard', 'ping', 'trace', 'telnet', 'dns', 'cert', 'http', 'sweep', 'subnet', 'urlcheck', 'settings',
];

class _AppShellState extends State<AppShell> {
  String _view = 'dashboard';

  void _go(String v) => setState(() => _view = v);

  /// Butun sayfalari IndexedStack ile gosterip/gizliyoruz (switch ile her
  /// sekmede yeniden insa etmek yerine) - ayni tip+konum her build'de
  /// eslesince Flutter State'lerini korur, boylece bir aracta girilmis
  /// veri/calisan olcum baska sekmeye bakip geri donulunce KAYBOLMUYOR.
  /// Ping ozelinde ayrica 2 dakikalik "uzaklasinca sifirla" davranisi icin
  /// kendi "active" bayragini alir.
  List<Widget> _buildPages() => [
        DashboardScreen(onGo: _go),
        PingScreen(active: _view == 'ping'),
        const TraceScreen(),
        const TelnetScreen(),
        const DnsScreen(),
        const CertScreen(),
        const HttpScreen(),
        const SweepScreen(),
        const SubnetScreen(),
        const UrlCheckScreen(),
        const SettingsScreen(),
      ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = AppTheme(state.isDark);
    final c = theme.c;

    return Scaffold(
      backgroundColor: c.bgDeep,
      body: Column(children: [
        TitleBar(c: c),
        Expanded(child: Row(children: [
        Container(
          width: 232,
          decoration: BoxDecoration(color: c.bgBase, border: Border(right: BorderSide(color: c.line))),
          child: Column(children: [
            _HoverArea(
              onTap: () => _go('dashboard'),
              borderRadius: BorderRadius.circular(8),
              margin: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              c: c,
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
                    label: item.label,
                    number: (e.key + 1).toString().padLeft(2, '0'),
                    active: active,
                    c: c,
                    onTap: () => _go(item.key),
                  );
                }).toList(),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('v$kAppVersion', style: GoogleFonts.spaceMono(color: c.inkGhost, fontSize: 9.5, letterSpacing: .5)),
                const SizedBox(height: 8),
                Row(children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: state.agentConnected ? c.ok : c.inkGhost)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(state.agentConnected ? (state.agent.lastHealth?['host']?.toString() ?? 'agent') : 'searching…', style: TextStyle(color: c.inkGhost, fontSize: 10.5), overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 12),
                _NavRow(icon: Icons.settings, label: kToolLabel['settings']!, number: null, active: _view == 'settings', c: c, onTap: () => _go('settings')),
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
                Text(_view == 'dashboard' ? '' : '/ ${(kToolLabel[_view] ?? _view).toUpperCase()}', style: TextStyle(color: c.inkGhost, fontSize: 11, letterSpacing: 1)),
              ]),
            ),
            Expanded(child: IndexedStack(index: _viewOrder.indexOf(_view), children: _buildPages())),
          ]),
        ),
      ])),
      ]),
    );
  }
}

/// Fare uzerine gelince hafif arka plan/renk degisimi gosteren genel sarmalayici.
class _HoverArea extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;
  final EdgeInsets margin, padding;
  final AppColors c;
  const _HoverArea({required this.child, required this.onTap, required this.borderRadius, required this.margin, required this.padding, required this.c});
  @override
  State<_HoverArea> createState() => _HoverAreaState();
}

class _HoverAreaState extends State<_HoverArea> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => Padding(
        padding: widget.margin,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              padding: widget.padding,
              decoration: BoxDecoration(
                color: _hover ? widget.c.fillHover : Colors.transparent,
                borderRadius: widget.borderRadius,
              ),
              child: widget.child,
            ),
          ),
        ),
      );
}

class _NavRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? number;
  final bool active;
  final AppColors c;
  final VoidCallback onTap;
  const _NavRow({required this.icon, required this.label, required this.number, required this.active, required this.c, required this.onTap});

  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final active = widget.active;
    final bg = active ? c.accentWeak : (_hover ? c.fillHover : Colors.transparent);
    final border = active ? c.accentLine : (_hover ? c.lineStrong : Colors.transparent);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(widget.icon, size: 16, color: active ? c.accent : (_hover ? c.inkSoft : c.inkFaint)),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.label, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w500, color: active ? c.ink : (_hover ? c.ink : c.inkFaint)))),
            if (widget.number != null) Text(widget.number!, style: GoogleFonts.spaceMono(fontSize: 9, color: c.inkGhost)),
          ]),
        ),
      ),
    );
  }
}
