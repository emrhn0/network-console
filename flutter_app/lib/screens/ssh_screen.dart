import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/errors.dart';
import '../core/i18n.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class SshScreen extends StatefulWidget {
  const SshScreen({super.key});
  @override
  State<SshScreen> createState() => _SshScreenState();
}

class _SshScreenState extends State<SshScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  bool _busy = false;
  Map<String, dynamic>? _r;

  Future<void> _run() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    final state = context.read<AppState>();
    setState(() { _busy = true; _r = null; });
    final r = await state.agent.get('/api/ssh', {
      'host': host,
      'port': _port.text.trim().isEmpty ? '22' : _port.text.trim(),
      'timeout': '3000',
    });
    if (!mounted) return;
    setState(() { _busy = false; _r = r; });
    if (r['ok'] == true) state.logHistory('ssh', '$host · ${r['banner'] ?? ''}');
  }

  StatusKind get _kind => _busy ? StatusKind.busy : (_r == null ? StatusKind.idle : (_r!['ok'] == true ? StatusKind.ok : StatusKind.error));
  String get _statusText {
    if (_busy) return 'Connecting…';
    if (_r == null) return '';
    if (_r!['ok'] == true) return _r!['is_ssh'] == true ? 'SSH service detected' : 'Port open, but no SSH banner';
    return friendlyAgentError(_r!['error']?.toString());
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
          Expanded(flex: 3, child: LabeledField(label: t(state.lang, 'field.host'), controller: _host, c: c, hint: '192.168.1.1', onSubmitted: (_) => _run())),
          const SizedBox(width: 10),
          Expanded(child: LabeledField(label: t(state.lang, 'field.port'), controller: _port, c: c, hint: '22')),
          const SizedBox(width: 10),
          PrimaryButton(label: t(state.lang, 'action.check'), onPressed: _busy ? null : _run, c: c),
        ]),
        const SizedBox(height: 16),
        StatusLine(kind: _kind, text: _statusText, c: c),
        const SizedBox(height: 4),
        if (ok) ...[
          GridView.count(
            crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 3.2,
            children: [
              StatCell('Latency', '${r['ms']} ms', c),
              StatCell('SSH service', r['is_ssh'] == true ? 'yes' : 'no', c, valueColor: r['is_ssh'] == true ? c.ok : c.warn),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            c: c,
            child: Text(
              (r['banner']?.toString().isEmpty ?? true) ? '(no banner received)' : r['banner'].toString(),
              style: TextStyle(color: c.inkSoft, fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ] else if (!_busy) ...[
          const SizedBox(height: 12),
          Text(
            'Connects to the SSH port and reads the server\'s identification banner (e.g. "SSH-2.0-OpenSSH_9.6") to confirm the service is reachable and see its version — a reachability probe, not an authenticated session.',
            style: TextStyle(color: c.inkGhost, fontSize: 11, height: 1.5),
          ),
        ],
      ]),
    );
  }
}
