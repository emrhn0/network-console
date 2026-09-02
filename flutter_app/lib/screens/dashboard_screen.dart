import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/i18n.dart';
import '../core/nav.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatelessWidget {
  final ValueChanged<String> onGo;
  const DashboardScreen({super.key, required this.onGo});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = AppTheme(state.isDark);
    final c = theme.c;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t(state.lang, 'dashboard.title'), style: theme.display.copyWith(fontSize: 40)),
        const SizedBox(height: 14),
        SizedBox(width: 560, child: Text(t(state.lang, 'dashboard.desc'), style: TextStyle(color: c.inkFaint, height: 1.6))),
        const SizedBox(height: 20),
        Row(children: [
          Text('${kTools.length} tools', style: TextStyle(color: c.accent, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 20),
          Text('Method ${state.agentMethod}', style: TextStyle(color: c.inkFaint, fontSize: 12)),
          const SizedBox(width: 20),
          Text('Agent ${state.agentConnected ? (state.agent.lastHealth?['host'] ?? 'connected') : 'not found'}', style: TextStyle(color: c.inkFaint, fontSize: 12)),
        ]),
        const SizedBox(height: 26),
        GridView.count(
          crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 1, crossAxisSpacing: 1, childAspectRatio: 2.6,
          children: kTools.asMap().entries.map((e) {
            final i = e.key, item = e.value;
            return InkWell(
              onTap: () => onGo(item.key),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(border: Border.all(color: c.lineSoft)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(item.icon, color: c.inkFaint, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.label, style: GoogleFonts.fraunces(fontStyle: FontStyle.italic, fontWeight: FontWeight.w600, fontSize: 16, color: c.ink)),
                      const SizedBox(height: 3),
                      Text(t(state.lang, 'desc.${item.key}'), style: TextStyle(color: c.inkFaint, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  Text((i + 1).toString().padLeft(2, '0'), style: GoogleFonts.spaceMono(color: c.inkGhost, fontSize: 10)),
                ]),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 26),
        SectionCard(
          c: c,
          padding: const EdgeInsets.all(0),
          child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 10), child: Caption(t(state.lang, 'dashboard.recent'), c)),
            Divider(height: 1, color: c.lineSoft),
            if (state.history.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Text(t(state.lang, 'dashboard.empty'), style: TextStyle(color: c.inkFaint)),
                  const SizedBox(height: 4),
                  Text(t(state.lang, 'dashboard.emptySub'), style: TextStyle(color: c.inkGhost, fontSize: 11)),
                ]),
              )
            else
              ...state.history.take(10).map((h) => ListTile(
                    dense: true,
                    title: Text(h.summary, style: TextStyle(color: c.inkSoft, fontSize: 12)),
                    leading: Text(kToolLabel[h.view] ?? h.view, style: TextStyle(color: c.accent, fontSize: 11)),
                    onTap: () => onGo(h.view == 'trace' ? 'trace' : h.view),
                  )),
          ]),
        ),
      ]),
    );
  }
}
