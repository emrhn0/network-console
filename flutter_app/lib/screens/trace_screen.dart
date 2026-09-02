import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/errors.dart';
import '../core/i18n.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class TraceScreen extends StatefulWidget {
  const TraceScreen({super.key});
  @override
  State<TraceScreen> createState() => _TraceScreenState();
}

class _TraceScreenState extends State<TraceScreen> {
  final _host = TextEditingController();
  bool _busy = false;
  String? _targetIp;
  List<dynamic> _hops = [];
  StatusKind _kind = StatusKind.idle;
  String _status = '';

  Future<void> _run() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    final state = context.read<AppState>();
    setState(() { _busy = true; _kind = StatusKind.busy; _status = 'Tracing to $host — this can take up to a minute…'; _hops = []; _targetIp = null; });
    final r = await state.agent.get('/api/traceroute', {'host': host, 'maxhops': '30', 'timeout': '1000'});
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r['ok'] == true) {
        _targetIp = r['target_ip']?.toString();
        _hops = r['hops'] as List<dynamic>? ?? [];
        _kind = StatusKind.ok;
        _status = 'Done — ${_hops.length} hops';
        state.logHistory('trace', '$host · ${_hops.length} hops');
      } else {
        _kind = StatusKind.error;
        _status = friendlyAgentError(r['error']?.toString());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppTheme(state.isDark).c;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: LabeledField(label: t(state.lang, 'field.target'), controller: _host, c: c, hint: '8.8.8.8 · google.com', onSubmitted: (_) => _run())),
          const SizedBox(width: 10),
          PrimaryButton(label: t(state.lang, 'action.start'), onPressed: _busy ? null : _run, c: c),
        ]),
        const SizedBox(height: 16),
        StatusLine(kind: _kind, text: _targetIp != null ? 'Target IP: $_targetIp · $_status' : _status, c: c),
        const SizedBox(height: 4),
        ResultTable(
          title: 'Hops',
          c: c,
          rows: _hops.map((h) => ResultRow(['#${h['n']}', h['ip']?.toString() ?? '*'])).toList(),
        ),
      ]),
    );
  }
}
