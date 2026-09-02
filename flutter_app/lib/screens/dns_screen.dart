import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/i18n.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class DnsScreen extends StatefulWidget {
  const DnsScreen({super.key});
  @override
  State<DnsScreen> createState() => _DnsScreenState();
}

class _DnsScreenState extends State<DnsScreen> {
  final _host = TextEditingController();
  final _server = TextEditingController();
  String _type = 'A';
  bool _busy = false;
  List<dynamic> _answers = [];
  String _status = 'Ready';

  Future<void> _run() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    final state = context.read<AppState>();
    setState(() { _busy = true; _status = 'Querying…'; });
    final r = await state.agent.get('/api/dns', {
      'host': host, 'type': _type,
      if (_server.text.trim().isNotEmpty) 'server': _server.text.trim(),
      'timeout': '3000',
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r['ok'] == true) {
        _answers = r['answers'] as List<dynamic>? ?? [];
        _status = '${r['status']} · ${_answers.length} records';
        state.logHistory('dns', '$host $_type · ${_answers.length} records');
      } else {
        _answers = [];
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
          Expanded(flex: 3, child: LabeledField(label: t(state.lang, 'field.query'), controller: _host, c: c, hint: 'example.com', onSubmitted: (_) => _run())),
          const SizedBox(width: 10),
          DropdownButton<String>(
            value: _type, dropdownColor: c.bgRise, underline: const SizedBox(),
            items: const ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'NS', 'SOA', 'PTR']
                .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => _type = v ?? 'A'),
          ),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: LabeledField(label: t(state.lang, 'field.server'), controller: _server, c: c, hint: 'auto')),
          const SizedBox(width: 10),
          PrimaryButton(label: t(state.lang, 'action.check'), onPressed: _busy ? null : _run, c: c),
        ]),
        const SizedBox(height: 16),
        Text(_status, style: TextStyle(color: c.inkFaint, fontSize: 12)),
        const SizedBox(height: 12),
        ResultTable(
          title: 'Records', c: c,
          rows: _answers.map((a) => ResultRow([a['name']?.toString() ?? '', a['type']?.toString() ?? '', a['data']?.toString() ?? '', 'TTL ${a['ttl']}'])).toList(),
        ),
      ]),
    );
  }
}
