import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/errors.dart';
import '../core/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class SnmpScreen extends StatefulWidget {
  const SnmpScreen({super.key});
  @override
  State<SnmpScreen> createState() => _SnmpScreenState();
}

class _SnmpScreenState extends State<SnmpScreen> {
  final _host = TextEditingController();
  final _community = TextEditingController(text: 'public');
  bool _busy = false;
  Map<String, dynamic>? _r;

  Future<void> _run() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    final state = context.read<AppState>();
    setState(() { _busy = true; _r = null; });
    final r = await state.agent.get('/api/snmp', {
      'host': host,
      'community': _community.text.trim().isEmpty ? 'public' : _community.text.trim(),
      'timeout': '2000',
    });
    if (!mounted) return;
    setState(() { _busy = false; _r = r; });
    if (r['ok'] == true) state.logHistory('snmp', '$host · ${r['sysName'] ?? ''}');
  }

  StatusKind get _kind => _busy ? StatusKind.busy : (_r == null ? StatusKind.idle : (_r!['ok'] == true ? StatusKind.ok : StatusKind.error));
  String get _statusText {
    if (_busy) return 'Querying device…';
    if (_r == null) return '';
    if (_r!['ok'] == true) return 'Device responded';
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
          Expanded(flex: 2, child: LabeledField(label: 'Community', controller: _community, c: c, hint: 'public', onSubmitted: (_) => _run())),
          const SizedBox(width: 10),
          PrimaryButton(label: t(state.lang, 'action.check'), onPressed: _busy ? null : _run, c: c),
        ]),
        const SizedBox(height: 16),
        StatusLine(kind: _kind, text: _statusText, c: c),
        const SizedBox(height: 4),
        if (ok) ...[
          SectionCard(
            c: c,
            padding: const EdgeInsets.all(0),
            child: Column(children: [
              _row('sysName', r['sysName']?.toString() ?? '—', c, first: true),
              _row('sysDescr', r['sysDescr']?.toString() ?? '—', c),
              _row('sysUpTime', r['sysUpTime']?.toString() ?? '—', c),
              _row('sysContact', r['sysContact']?.toString() ?? '—', c),
              _row('sysLocation', r['sysLocation']?.toString() ?? '—', c),
            ]),
          ),
        ] else if (!_busy) ...[
          const SizedBox(height: 12),
          Text(
            'SNMP v1/v2c GET — reads a device\'s standard system OIDs (name, description, uptime, contact, location). Most managed switches/routers/firewalls expose these read-only with the "public" community by default.',
            style: TextStyle(color: c.inkGhost, fontSize: 11, height: 1.5),
          ),
        ],
      ]),
    );
  }

  Widget _row(String label, String value, AppColors c, {bool first = false}) {
    return Column(children: [
      if (!first) Divider(height: 1, color: c.lineSoft),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(color: c.inkGhost, fontSize: 11, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: TextStyle(color: c.inkSoft, fontFamily: 'monospace', fontSize: 12.5))),
        ]),
      ),
    ]);
  }
}
