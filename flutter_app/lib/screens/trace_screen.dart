import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
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
  String _status = 'Ready';

  Future<void> _run() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    final state = context.read<AppState>();
    setState(() { _busy = true; _status = 'Tracing…'; _hops = []; });
    final r = await state.agent.get('/api/traceroute', {'host': host, 'maxhops': '30', 'timeout': '1000'});
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r['ok'] == true) {
        _targetIp = r['target_ip']?.toString();
        _hops = r['hops'] as List<dynamic>? ?? [];
        _status = '${_hops.length} hops';
        state.logHistory('trace', '$host · ${_hops.length} hops');
      } else {
        _status = r['error']?.toString() ?? 'failed';
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
        Text(_targetIp != null ? 'Target IP: $_targetIp · $_status' : _status, style: TextStyle(color: c.inkFaint, fontSize: 12)),
        const SizedBox(height: 12),
        ResultTable(
          title: 'Hops',
          c: c,
          rows: _hops.map((h) => ResultRow(['#${h['n']}', h['ip']?.toString() ?? '*'])).toList(),
        ),
      ]),
    );
  }
}
