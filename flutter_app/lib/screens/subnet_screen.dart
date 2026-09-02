import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/i18n.dart';
import '../core/net_utils.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class _Req {
  String label;
  int hosts;
  _Req(this.label, this.hosts);
}

class SubnetScreen extends StatefulWidget {
  const SubnetScreen({super.key});
  @override
  State<SubnetScreen> createState() => _SubnetScreenState();
}

class _SubnetScreenState extends State<SubnetScreen> {
  final _cidr = TextEditingController(text: '192.168.1.0/24');
  final List<_Req> _reqs = [_Req('LAN', 50), _Req('WiFi', 20)];
  CidrInfo? _info;
  List<ResultRow> _vlsm = [];

  void _calc() {
    final c = parseCidr(_cidr.text);
    if (c.error != null) { setState(() { _info = c; _vlsm = []; }); return; }
    final sorted = [..._reqs]..sort((a, b) => b.hosts.compareTo(a.hosts));
    var cursor = c.network;
    final rows = <ResultRow>[];
    for (final r in sorted) {
      final p = neededPrefix(r.hosts);
      if (p == null) continue;
      final blockSize = 1 << (32 - p);
      if (cursor + blockSize - 1 > c.broadcast) {
        rows.add(ResultRow([r.label, 'does not fit', '', '']));
        continue;
      }
      rows.add(ResultRow([r.label, '${intToIp(cursor)}/$p', '${blockSize - 2} hosts', '${intToIp(cursor + 1)} - ${intToIp(cursor + blockSize - 2)}']));
      cursor += blockSize;
    }
    setState(() { _info = c; _vlsm = rows; });
  }

  @override
  void initState() {
    super.initState();
    _calc();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppTheme(state.isDark).c;
    final info = _info;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: LabeledField(label: 'CIDR', controller: _cidr, c: c, hint: '192.168.1.0/24', onSubmitted: (_) => _calc())),
          const SizedBox(width: 10),
          PrimaryButton(label: t(state.lang, 'action.calculate'), onPressed: _calc, c: c),
        ]),
        const SizedBox(height: 16),
        if (info != null && info.error != null) Text(info.error!, style: TextStyle(color: c.alarm)),
        if (info != null && info.error == null)
          GridView.count(
            crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.6,
            children: [
              StatCell('Network', intToIp(info.network), c),
              StatCell('Broadcast', intToIp(info.broadcast), c),
              StatCell('Usable hosts', '${info.size > 2 ? info.size - 2 : info.size}', c),
              StatCell('Range', '${intToIp(info.network + 1)} - ${intToIp(info.broadcast - 1)}', c),
              StatCell('Prefix', '/${info.prefix}', c),
              StatCell('Total', '${info.size}', c),
            ],
          ),
        const SizedBox(height: 20),
        Row(children: [
          Text('VLSM split', style: TextStyle(color: c.inkFaint, fontSize: 11, letterSpacing: 1.2)),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() => _reqs.add(_Req('Segment ${_reqs.length + 1}', 10))),
            child: Text('+ Add', style: TextStyle(color: c.accent)),
          ),
        ]),
        ..._reqs.asMap().entries.map((e) {
          final i = e.key, r = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: TextFormField(initialValue: r.label, style: TextStyle(color: c.ink), decoration: const InputDecoration(isDense: true), onChanged: (v) => r.label = v)),
              const SizedBox(width: 10),
              SizedBox(width: 100, child: TextFormField(initialValue: '${r.hosts}', keyboardType: TextInputType.number, style: TextStyle(color: c.ink), decoration: const InputDecoration(isDense: true), onChanged: (v) => r.hosts = int.tryParse(v) ?? 0)),
              IconButton(onPressed: () => setState(() => _reqs.removeAt(i)), icon: Icon(Icons.close, size: 16, color: c.inkFaint)),
            ]),
          );
        }),
        const SizedBox(height: 8),
        PrimaryButton(label: t(state.lang, 'action.calculate'), onPressed: _calc, c: c),
        const SizedBox(height: 16),
        ResultTable(title: 'Allocation', c: c, rows: _vlsm),
      ]),
    );
  }
}
