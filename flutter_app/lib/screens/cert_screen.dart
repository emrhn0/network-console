import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/i18n.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class CertScreen extends StatefulWidget {
  const CertScreen({super.key});
  @override
  State<CertScreen> createState() => _CertScreenState();
}

class _CertScreenState extends State<CertScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '443');
  bool _busy = false;
  Map<String, dynamic>? _r;

  Future<void> _run() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    final state = context.read<AppState>();
    setState(() { _busy = true; _r = null; });
    final r = await state.agent.get('/api/cert', {'host': host, 'port': _port.text.trim().isEmpty ? '443' : _port.text.trim(), 'timeout': '3000'});
    if (!mounted) return;
    setState(() { _busy = false; _r = r; });
    if (r['ok'] == true) state.logHistory('cert', '$host · ${r['days_left']} days left');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppTheme(state.isDark).c;
    final r = _r;
    final ok = r != null && r['ok'] == true;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(flex: 3, child: LabeledField(label: t(state.lang, 'field.host'), controller: _host, c: c, hint: 'example.com', onSubmitted: (_) => _run())),
          const SizedBox(width: 10),
          Expanded(child: LabeledField(label: t(state.lang, 'field.port'), controller: _port, c: c, hint: '443')),
          const SizedBox(width: 10),
          PrimaryButton(label: t(state.lang, 'action.check'), onPressed: _busy ? null : _run, c: c),
        ]),
        const SizedBox(height: 16),
        if (r != null && r['ok'] != true) Text(r['error']?.toString() ?? 'error', style: TextStyle(color: c.alarm)),
        if (ok) ...[
          GridView.count(
            crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.6,
            children: [
              StatCell('Subject', r['subject_cn']?.toString() ?? '—', c),
              StatCell('Issuer', r['issuer_cn']?.toString() ?? '—', c),
              StatCell('TLS', r['tls_version']?.toString() ?? '—', c),
              StatCell('Days left', '${r['days_left'] ?? '—'}', c, valueColor: (r['days_left'] ?? 999) < 14 ? c.alarm : c.ok),
              StatCell('Verified', r['verified'] == true ? 'yes' : 'no', c, valueColor: r['verified'] == true ? c.ok : c.warn),
              StatCell('Cipher', r['cipher']?.toString() ?? '—', c),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(c: c, child: Text('Valid: ${r['not_before']} → ${r['not_after']}', style: TextStyle(color: c.inkSoft, fontFamily: 'monospace'))),
          const SizedBox(height: 12),
          if ((r['san'] as List?)?.isNotEmpty ?? false)
            SectionCard(c: c, child: Wrap(spacing: 6, runSpacing: 6, children: (r['san'] as List).map((s) => Chip(label: Text(s.toString()), backgroundColor: c.bgHigh)).toList())),
        ],
      ]),
    );
  }
}
