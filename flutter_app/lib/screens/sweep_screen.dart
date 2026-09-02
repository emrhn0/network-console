import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/i18n.dart';
import '../core/net_utils.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class SweepScreen extends StatefulWidget {
  const SweepScreen({super.key});
  @override
  State<SweepScreen> createState() => _SweepScreenState();
}

class _SweepScreenState extends State<SweepScreen> {
  static const maxHosts = 4096, pool = 16;
  final _cidr = TextEditingController();
  final _port = TextEditingController();
  bool _running = false;
  int _token = 0;
  int _alive = 0, _dead = 0, _done = 0, _total = 0;
  String? _hint;
  final List<ResultRow> _rows = [];

  Future<void> _start() async {
    final c = parseCidr(_cidr.text);
    if (c.error != null) { setState(() => _hint = c.error); return; }
    if (c.size > maxHosts) { setState(() => _hint = t(context.read<AppState>().lang, 'sweep.tooLarge')); return; }
    final port = int.tryParse(_port.text.trim());
    final state = context.read<AppState>();
    _token++;
    final tk = _token;
    setState(() { _running = true; _hint = null; _rows.clear(); _alive = 0; _dead = 0; _done = 0; _total = c.size; });

    final hosts = <String>[];
    for (var n = c.network; n <= c.broadcast; n++) {
      hosts.add(intToIp(n));
    }
    for (var i = 0; i < hosts.length; i += pool) {
      if (tk != _token) return;
      final batch = hosts.skip(i).take(pool);
      await Future.wait(batch.map((ip) => _checkOne(ip, port, tk, state)));
      if (tk != _token) return;
    }
    if (tk != _token) return;
    setState(() => _running = false);
    state.logHistory('sweep', '${_cidr.text.trim()} · $_alive alive');
  }

  StatusKind get _kind {
    if (_running) return StatusKind.busy;
    if (_total == 0) return StatusKind.idle;
    return _alive > 0 ? StatusKind.ok : StatusKind.error;
  }

  String get _statusText {
    if (_running) return 'Scanning $_done / $_total…';
    if (_total == 0) return '';
    return _alive > 0 ? '$_alive alive / $_total scanned' : 'No alive devices found';
  }

  Future<void> _checkOne(String ip, int? port, int tk, AppState state) async {
    if (port != null) {
      final r = await state.agent.get('/api/tcp', {'host': ip, 'port': '$port', 'timeout': '1600'});
      if (tk != _token || !mounted) return;
      setState(() {
        _done++;
        if (r['ok'] == true && r['state'] == 'open') {
          _alive++;
          _rows.add(ResultRow([ip, '${r['ms']} ms', 'PORT $port', 'open']));
        } else {
          _dead++;
        }
      });
    } else {
      final r = await state.agent.get('/api/ping', {'host': ip, 'timeout': '600'});
      if (tk != _token || !mounted) return;
      setState(() {
        _done++;
        if (r['ok'] == true) {
          _alive++;
          _rows.add(ResultRow([ip, '${r['ms']} ms', r['ttl'] != null ? 'TTL ${r['ttl']}' : '', '']));
        } else {
          _dead++;
        }
      });
    }
  }

  void _stop() {
    _token++;
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppTheme(state.isDark).c;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(flex: 3, child: LabeledField(label: t(state.lang, 'sweep.cidr'), controller: _cidr, c: c, hint: '192.168.1.0/24')),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: LabeledField(label: t(state.lang, 'sweep.port'), controller: _port, c: c, hint: '443')),
          const SizedBox(width: 10),
          PrimaryButton(label: _running ? t(state.lang, 'action.stop') : t(state.lang, 'action.scan'), running: _running, onPressed: _running ? _stop : _start, c: c),
        ]),
        if (_hint != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_hint!, style: TextStyle(color: c.alarm, fontSize: 12))),
        const SizedBox(height: 16),
        StatusLine(kind: _kind, text: _statusText, c: c),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 4, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.9,
          children: [
            StatCell(t(state.lang, 'sweep.alive'), '$_alive', c, valueColor: c.ok),
            StatCell(t(state.lang, 'sweep.dead'), '$_dead', c),
            StatCell(t(state.lang, 'sweep.total'), '$_total', c),
            StatCell(t(state.lang, 'sweep.progress'), _total == 0 ? '—' : '${(_done / _total * 100).round()}%', c),
          ],
        ),
        const SizedBox(height: 16),
        ResultTable(title: 'Alive addresses', c: c, rows: _rows),
      ]),
    );
  }
}
