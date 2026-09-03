import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
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
  final _user = TextEditingController();
  bool _busy = false;
  Map<String, dynamic>? _r;

  // Gercek SSH oturumu: sistemin kendi ssh istemcisini (Windows'ta varsayilan
  // olarak kurulu OpenSSH Client) alt surec olarak baslatir, klavye/ekran
  // ham byte akisini xterm widget'ina baglar - ekstra bir konsol penceresi
  // ACILMAZ (Process.start stdio'yu boruladigi icin ayri pencere gerekmez).
  Process? _sshProcess;
  Terminal? _terminal;
  final _terminalController = TerminalController();
  bool _connecting = false;
  String? _connectError;

  @override
  void dispose() {
    _sshProcess?.kill();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    super.dispose();
  }

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

  Future<void> _connect() async {
    final host = _host.text.trim();
    if (host.isEmpty || _connecting || _sshProcess != null) return;
    final state = context.read<AppState>();
    final port = _port.text.trim().isEmpty ? '22' : _port.text.trim();
    final user = _user.text.trim();
    final target = user.isEmpty ? host : '$user@$host';

    setState(() { _connecting = true; _connectError = null; });

    final terminal = Terminal(maxLines: 5000);
    Process proc;
    try {
      // -tt: uzak tarafta bir pty tahsis etmeye zorlar, boylece parola
      // istemi/prompt/renk gibi interaktif davranis dogru gelir - yerel
      // tarafta ayri bir pty gerekmez, sadece ham byte'lari xterm'e yaziyoruz.
      proc = await Process.start(
        'ssh',
        ['-tt', '-p', port, target],
        mode: ProcessStartMode.normal,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() { _connecting = false; _connectError = t(state.lang, 'ssh.noOpenssh'); });
      return;
    }

    if (!mounted) { proc.kill(); return; }

    // Terminal boyutu (SIGWINCH/window-change) senkronize edilmiyor -
    // baslangictaki varsayilan boyut kabul edilebilir, cogu kabuk/komut icin
    // yeterli; sadece tam ekran (orn. htop) araclarda satir kirpilmasi olabilir.
    terminal.onOutput = (data) => proc.stdin.add(utf8.encode(data));

    proc.stdout.listen((bytes) => terminal.write(utf8.decode(bytes, allowMalformed: true)));
    proc.stderr.listen((bytes) => terminal.write(utf8.decode(bytes, allowMalformed: true)));
    proc.exitCode.then((_) {
      if (!mounted) return;
      terminal.write('\r\n\x1b[90m[${t(state.lang, 'ssh.connected')}]\x1b[0m\r\n');
      setState(() { _sshProcess = null; });
    });

    state.addSshHost(host);
    setState(() {
      _sshProcess = proc;
      _terminal = terminal;
      _connecting = false;
    });
  }

  void _disconnect() {
    _sshProcess?.kill();
    setState(() { _sshProcess = null; });
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
    final connected = _sshProcess != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(flex: 3, child: LabeledField(label: t(state.lang, 'field.host'), controller: _host, c: c, hint: '192.168.1.1', onSubmitted: (_) => _run())),
          const SizedBox(width: 10),
          Expanded(child: LabeledField(label: t(state.lang, 'field.port'), controller: _port, c: c, hint: '22')),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: LabeledField(label: t(state.lang, 'field.username'), controller: _user, c: c, hint: t(state.lang, 'ssh.usernameHint'))),
          const SizedBox(width: 10),
          GhostButton(label: t(state.lang, 'action.check'), c: c, onPressed: _busy ? null : _run),
          const SizedBox(width: 10),
          PrimaryButton(
            label: connected ? t(state.lang, 'action.disconnect') : t(state.lang, 'action.connect'),
            c: c,
            running: connected,
            onPressed: _connecting ? null : (connected ? _disconnect : _connect),
          ),
        ]),
        if (state.sshHosts.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Padding(padding: const EdgeInsets.only(top: 6), child: Caption(t(state.lang, 'ssh.recent'), c)),
            for (final h in state.sshHosts)
              GhostButton(label: h, c: c, onPressed: () => setState(() => _host.text = h)),
          ]),
        ],
        const SizedBox(height: 16),
        if (_connectError != null) ...[
          StatusLine(kind: StatusKind.error, text: _connectError!, c: c),
          const SizedBox(height: 4),
        ],
        StatusLine(kind: _kind, text: _statusText, c: c),
        const SizedBox(height: 4),
        if (connected || _connecting) ...[
          const SizedBox(height: 8),
          Container(
            height: 440,
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFF0B0B10), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.lineSoft)),
            child: _connecting
                ? Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)))
                : TerminalView(_terminal!, controller: _terminalController, autofocus: true, backgroundOpacity: 0),
          ),
        ] else if (ok) ...[
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
            'Check reads the SSH identification banner (e.g. "SSH-2.0-OpenSSH_9.6") without authenticating — a reachability probe. Connect opens a real interactive SSH session in-app using your system\'s ssh client, right below.',
            style: TextStyle(color: c.inkGhost, fontSize: 11, height: 1.5),
          ),
        ],
      ]),
    );
  }
}
