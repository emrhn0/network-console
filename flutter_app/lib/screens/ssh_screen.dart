import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../core/app_state.dart';
import '../core/errors.dart';
import '../core/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Tek bir acik SSH oturumu: kendi baglantisi, kendi terminali. Sekmeler
/// arasi gecince oturum KAPANMAZ - hepsi arka planda canli kalir, sadece
/// gorunen degisir (bkz. _SshScreenState.build, IndexedStack benzeri).
class _SshSession {
  final String id;
  final String label;
  SSHClient? client;
  SSHSession? shell;
  final Terminal terminal = Terminal(maxLines: 8000);
  final TerminalController controller = TerminalController();
  bool connecting = true;
  String? error;
  _SshSession({required this.id, required this.label});
}

class SshScreen extends StatefulWidget {
  const SshScreen({super.key});
  @override
  State<SshScreen> createState() => _SshScreenState();
}

class _SshScreenState extends State<SshScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _remember = false;

  // Eski "banner probe" (kimlik dogrulamasiz erisilebilirlik testi) - hala
  // kullanisli (parola gerektirmez), Check butonuyla ayri calisir.
  bool _checking = false;
  Map<String, dynamic>? _checkResult;

  final List<_SshSession> _sessions = [];
  String? _activeId;

  @override
  void dispose() {
    for (final s in _sessions) {
      s.shell?.close();
      s.client?.close();
    }
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    final state = context.read<AppState>();
    setState(() { _checking = true; _checkResult = null; });
    final r = await state.agent.get('/api/ssh', {
      'host': host,
      'port': _port.text.trim().isEmpty ? '22' : _port.text.trim(),
      'timeout': '3000',
    });
    if (!mounted) return;
    setState(() { _checking = false; _checkResult = r; });
    if (r['ok'] == true) state.logHistory('ssh', '$host · ${r['banner'] ?? ''}');
  }

  String _friendlySshError(Object e) {
    final s = e.toString().replaceFirst(RegExp(r'^(Exception|SSHAuthError|SSHError):\s*'), '');
    return s.isEmpty ? 'connection failed' : s;
  }

  Future<void> _connect() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    final state = context.read<AppState>();
    final port = int.tryParse(_port.text.trim()) ?? 22;
    final username = _user.text.trim();
    final password = _pass.text;

    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final session = _SshSession(id: id, label: username.isEmpty ? host : '$username@$host');
    setState(() { _sessions.add(session); _activeId = id; });

    // Bir sonraki baglanti icin alanlari temizlemiyoruz (ayni host'a tekrar
    // baglanmak/duzenlemek kolay olsun diye) - sadece sifreyi ekrandan siliyoruz.
    _pass.clear();

    final profile = await state.saveSshProfile(host: host, port: port, username: username, password: _remember ? password : null);

    try {
      final socket = await SSHSocket.connect(host, port, timeout: const Duration(seconds: 12));
      final client = SSHClient(
        socket,
        username: username.isEmpty ? 'root' : username,
        onPasswordRequest: () => password,
      );
      session.client = client;
      final shell = await client.shell(pty: SSHPtyConfig(width: 120, height: 34));
      session.shell = shell;

      shell.stdout.listen((data) => session.terminal.write(utf8.decode(data, allowMalformed: true)));
      shell.stderr.listen((data) => session.terminal.write(utf8.decode(data, allowMalformed: true)));
      session.terminal.onOutput = (data) => shell.stdin.add(Uint8List.fromList(utf8.encode(data)));
      shell.done.then((_) {
        if (!mounted) return;
        session.terminal.write('\r\n\x1b[90m[${t(state.lang, 'ssh.connected')}]\x1b[0m\r\n');
      });

      if (!mounted) return;
      setState(() => session.connecting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() { session.connecting = false; session.error = _friendlySshError(e); });
      // Basarisiz denemede olasi yanlis sifreyi saklı tutmuyoruz - profili
      // (host/port/kullanici) sifresiz halde birakiyoruz.
      if (_remember && password.isNotEmpty) {
        await state.removeSshProfile(profile.id);
        await state.saveSshProfile(host: host, port: port, username: username);
      }
    }
  }

  Future<void> _connectFromProfile(SshProfile p) async {
    _host.text = p.host;
    _port.text = '${p.port}';
    _user.text = p.username;
    _pass.text = '';
    if (p.savePassword) {
      final pw = await context.read<AppState>().sshPassword(p.id);
      if (pw != null) _pass.text = pw;
    }
    setState(() { _remember = p.savePassword; });
    await _connect();
  }

  void _closeSession(String id) {
    final s = _sessions.firstWhere((x) => x.id == id);
    s.shell?.close();
    s.client?.close();
    setState(() {
      _sessions.removeWhere((x) => x.id == id);
      if (_activeId == id) {
        _activeId = _sessions.isNotEmpty ? _sessions.last.id : null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppTheme(state.isDark).c;
    final active = _sessions.where((s) => s.id == _activeId).toList();
    final activeSession = active.isEmpty ? null : active.first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(flex: 3, child: LabeledField(label: t(state.lang, 'field.host'), controller: _host, c: c, hint: '192.168.1.1', onSubmitted: (_) => _connect())),
          const SizedBox(width: 10),
          Expanded(child: LabeledField(label: t(state.lang, 'field.port'), controller: _port, c: c, hint: '22')),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: LabeledField(label: t(state.lang, 'field.username'), controller: _user, c: c, hint: t(state.lang, 'ssh.usernameHint'))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: LabeledField(label: t(state.lang, 'field.password'), controller: _pass, c: c, obscure: true, onSubmitted: (_) => _connect())),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => setState(() => _remember = !_remember),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Checkbox(value: _remember, onChanged: (v) => setState(() => _remember = v ?? false), activeColor: c.accent, visualDensity: VisualDensity.compact),
                Text(t(state.lang, 'ssh.remember'), style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
              ]),
            ),
          ),
          const Spacer(),
          GhostButton(label: t(state.lang, 'action.check'), c: c, onPressed: _checking ? null : _check),
          const SizedBox(width: 10),
          PrimaryButton(label: t(state.lang, 'action.connect'), c: c, onPressed: _connect),
        ]),
        if (state.sshProfiles.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Caption(t(state.lang, 'ssh.recent'), c),
            for (final p in state.sshProfiles)
              GhostButton(
                label: p.label,
                c: c,
                icon: p.savePassword ? Icon(Icons.lock, size: 11, color: c.inkFaint) : null,
                onPressed: () => _connectFromProfile(p),
              ),
          ]),
        ],
        const SizedBox(height: 14),
        if (_sessions.isNotEmpty) ...[
          // Tarayici sekmesi gibi: her sekme ayri, canli bir SSH oturumu.
          SizedBox(
            height: 34,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final s in _sessions) _SessionTab(session: s, active: s.id == _activeId, c: c, onTap: () => setState(() => _activeId = s.id), onClose: () => _closeSession(s.id)),
            ]),
          ),
          const SizedBox(height: 6),
        ],
        if (_checkResult != null && _sessions.isEmpty) ...[
          StatusLine(
            kind: _checking ? StatusKind.busy : (_checkResult!['ok'] == true ? StatusKind.ok : StatusKind.error),
            text: _checking
                ? t(state.lang, 'ssh.connecting')
                : (_checkResult!['ok'] == true
                    ? (_checkResult!['is_ssh'] == true ? 'SSH service detected' : 'Port open, but no SSH banner')
                    : friendlyAgentError(_checkResult!['error']?.toString())),
            c: c,
          ),
          const SizedBox(height: 10),
          if (_checkResult!['ok'] == true)
            SectionCard(
              c: c,
              child: Text(
                (_checkResult!['banner']?.toString().isEmpty ?? true) ? '(no banner received)' : _checkResult!['banner'].toString(),
                style: TextStyle(color: c.inkSoft, fontFamily: 'monospace', fontSize: 13),
              ),
            ),
        ],
        Expanded(
          child: activeSession == null
              ? _EmptyState(c: c, text: _sessions.isEmpty ? t(state.lang, 'ssh.noTabs') : '')
              : Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF0B0B10), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.lineSoft)),
                  child: activeSession.connecting
                      ? Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)))
                      : activeSession.error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(activeSession.error!, style: TextStyle(color: c.alarm, fontFamily: 'monospace', fontSize: 13)),
                              ),
                            )
                          : TerminalView(activeSession.terminal, controller: activeSession.controller, autofocus: true, backgroundOpacity: 0),
                ),
        ),
      ]),
    );
  }
}

class _SessionTab extends StatelessWidget {
  final _SshSession session;
  final bool active;
  final AppColors c;
  final VoidCallback onTap, onClose;
  const _SessionTab({required this.session, required this.active, required this.c, required this.onTap, required this.onClose});
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? c.accentWeak : c.bgRise,
              border: Border.all(color: active ? c.accentLine : c.lineSoft),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: session.error != null ? c.alarm : (session.connecting ? c.warn : c.ok),
              )),
              Text(session.label, style: TextStyle(color: active ? c.accent : c.inkSoft, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              GestureDetector(onTap: onClose, child: Icon(Icons.close, size: 13, color: c.inkFaint)),
            ]),
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final AppColors c;
  final String text;
  const _EmptyState({required this.c, required this.text});
  @override
  Widget build(BuildContext context) => text.isEmpty
      ? const SizedBox.shrink()
      : Center(child: Text(text, style: TextStyle(color: c.inkGhost, fontSize: 12.5)));
}
