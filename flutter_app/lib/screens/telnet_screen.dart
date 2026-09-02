import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/i18n.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class TelnetScreen extends StatefulWidget {
  const TelnetScreen({super.key});
  @override
  State<TelnetScreen> createState() => _TelnetScreenState();
}

class _TelnetScreenState extends State<TelnetScreen> {
  final _host = TextEditingController();
  final _ports = TextEditingController(text: '22,80,443,3389');
  bool _busy = false;
  final List<ResultRow> _rows = [];
  StatusKind _kind = StatusKind.idle;
  String _status = '';
  int _open = 0;

  Future<void> _run() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    final ports = _ports.text.split(',').map((s) => int.tryParse(s.trim())).whereType<int>().toList();
    if (ports.isEmpty) {
      setState(() { _kind = StatusKind.error; _status = 'Enter at least one valid port'; });
      return;
    }
    final state = context.read<AppState>();
    setState(() { _busy = true; _rows.clear(); _open = 0; _kind = StatusKind.busy; _status = 'Checking 0 / ${ports.length}…'; });
    var done = 0;
    for (final p in ports) {
      final r = await state.agent.get('/api/tcp', {'host': host, 'port': '$p', 'timeout': '2000'});
      if (!mounted) return;
      done++;
      final st = r['state']?.toString() ?? 'error';
      if (st == 'open') _open++;
      setState(() {
        _rows.add(ResultRow([host, '$p', st, r['ms'] != null ? '${r['ms']} ms' : (r['error']?.toString() ?? '')]));
        _status = 'Checking $done / ${ports.length}…';
      });
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _kind = _open > 0 ? StatusKind.ok : StatusKind.error;
      _status = '$_open / ${ports.length} port${ports.length == 1 ? '' : 's'} open';
    });
    state.logHistory('telnet', '$host · ${ports.length} ports');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppTheme(state.isDark).c;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(flex: 3, child: LabeledField(label: t(state.lang, 'field.host'), controller: _host, c: c, hint: '192.168.1.1')),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: LabeledField(label: t(state.lang, 'field.port'), controller: _ports, c: c, hint: '22,80,443', onSubmitted: (_) => _run())),
          const SizedBox(width: 10),
          PrimaryButton(label: t(state.lang, 'action.check'), onPressed: _busy ? null : _run, c: c),
        ]),
        const SizedBox(height: 16),
        StatusLine(kind: _kind, text: _status, c: c),
        const SizedBox(height: 4),
        ResultTable(title: 'Port results', c: c, rows: _rows),
      ]),
    );
  }
}
