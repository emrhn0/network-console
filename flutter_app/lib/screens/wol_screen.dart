import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/errors.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class WolScreen extends StatefulWidget {
  const WolScreen({super.key});
  @override
  State<WolScreen> createState() => _WolScreenState();
}

class _WolScreenState extends State<WolScreen> {
  final _mac = TextEditingController();
  final _broadcast = TextEditingController(text: '255.255.255.255');
  bool _busy = false;
  Map<String, dynamic>? _r;

  Future<void> _run() async {
    final mac = _mac.text.trim();
    if (mac.isEmpty) return;
    final state = context.read<AppState>();
    setState(() { _busy = true; _r = null; });
    final r = await state.agent.get('/api/wol', {
      'mac': mac,
      'broadcast': _broadcast.text.trim().isEmpty ? '255.255.255.255' : _broadcast.text.trim(),
    });
    if (!mounted) return;
    setState(() { _busy = false; _r = r; });
    if (r['ok'] == true) state.logHistory('wol', 'Magic packet · ${r['mac'] ?? mac}');
  }

  StatusKind get _kind => _busy ? StatusKind.busy : (_r == null ? StatusKind.idle : (_r!['ok'] == true ? StatusKind.ok : StatusKind.error));
  String get _statusText {
    if (_busy) return 'Sending magic packet…';
    if (_r == null) return '';
    if (_r!['ok'] == true) return 'Magic packet sent to ${_r!['mac']}';
    return friendlyAgentError(_r!['error']?.toString());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppTheme(state.isDark).c;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(flex: 3, child: LabeledField(label: 'MAC address', controller: _mac, c: c, hint: 'AA:BB:CC:DD:EE:FF', onSubmitted: (_) => _run())),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: LabeledField(label: 'Broadcast IP', controller: _broadcast, c: c, hint: '255.255.255.255', onSubmitted: (_) => _run())),
          const SizedBox(width: 10),
          PrimaryButton(label: 'Wake', onPressed: _busy ? null : _run, c: c),
        ]),
        const SizedBox(height: 16),
        StatusLine(kind: _kind, text: _statusText, c: c),
        const SizedBox(height: 12),
        Text(
          'Sends a Wake-on-LAN magic packet by UDP broadcast. The target device must have WoL enabled in its firmware/OS and be on the same network segment (or use its subnet\'s broadcast address, e.g. 192.168.1.255, if it\'s across a router).',
          style: TextStyle(color: c.inkGhost, fontSize: 11, height: 1.5),
        ),
      ]),
    );
  }
}
