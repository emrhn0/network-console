import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/errors.dart';
import '../core/i18n.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class HttpScreen extends StatefulWidget {
  const HttpScreen({super.key});
  @override
  State<HttpScreen> createState() => _HttpScreenState();
}

class _HttpScreenState extends State<HttpScreen> {
  final _url = TextEditingController();
  String _method = 'GET';
  bool _busy = false;
  Map<String, dynamic>? _r;

  Future<void> _run() async {
    var url = _url.text.trim();
    if (url.isEmpty) return;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) url = 'https://$url';
    final state = context.read<AppState>();
    setState(() { _busy = true; _r = null; });
    final r = await state.agent.get('/api/http', {'url': url, 'method': _method, 'timeout': '5000', 'redirects': '10'});
    if (!mounted) return;
    setState(() { _busy = false; _r = r; });
    if (r['ok'] == true) state.logHistory('http', '$url · ${r['final_status']}');
  }

  StatusKind get _kind => _busy ? StatusKind.busy : (_r == null ? StatusKind.idle : (_r!['ok'] == true ? StatusKind.ok : StatusKind.error));
  String get _statusText {
    if (_busy) return 'Sending…';
    if (_r == null) return '';
    if (_r!['ok'] == true) return 'Final status ${_r!['final_status']}';
    return friendlyAgentError(_r!['error']?.toString());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppTheme(state.isDark).c;
    final r = _r;
    final chain = (r?['chain'] as List?) ?? [];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: LabeledField(label: t(state.lang, 'field.url'), controller: _url, c: c, hint: 'https://example.com/', onSubmitted: (_) => _run())),
          const SizedBox(width: 10),
          DropdownButton<String>(
            value: _method, dropdownColor: c.bgRise, underline: const SizedBox(),
            items: const ['GET', 'HEAD', 'POST'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => _method = v ?? 'GET'),
          ),
          const SizedBox(width: 10),
          PrimaryButton(label: t(state.lang, 'action.send'), onPressed: _busy ? null : _run, c: c),
        ]),
        const SizedBox(height: 16),
        StatusLine(kind: _kind, text: _statusText, c: c),
        const SizedBox(height: 4),
        if (r != null && r['ok'] == true)
          GridView.count(
            crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.6,
            children: [
              StatCell('Final status', '${r['final_status']}', c, valueColor: (r['final_status'] as int) < 400 ? c.ok : c.alarm),
              StatCell('Redirects', '${chain.length - 1}', c),
              StatCell('Total', '${r['total_ms']} ms', c),
            ],
          ),
        const SizedBox(height: 12),
        ResultTable(
          title: 'Redirect chain', c: c,
          rows: chain.map<ResultRow>((h) => ResultRow([h['url']?.toString() ?? '', '${h['status'] ?? '—'}', '${h['ttfb_ms'] ?? '—'} ms'])).toList(),
        ),
      ]),
    );
  }
}
