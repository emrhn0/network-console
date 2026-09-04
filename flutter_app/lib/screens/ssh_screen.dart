import 'dart:async';
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
  String label;
  SSHClient? client;
  SSHSession? shell;
  final Terminal terminal = Terminal(maxLines: 8000);
  final TerminalController controller = TerminalController();
  final FocusNode focusNode = FocusNode();
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
      s.focusNode.dispose();
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

  /// PuTTY'nin yaptigi gibi: prompt'u terminale yazar, kullanici Enter'a
  /// basana kadar tusladigi karakterleri (kendimiz yerel olarak yankilayarak)
  /// toplar. echo=false ise sifre alaninda oldugu gibi hicbir sey basmaz.
  /// Bu, host haric her sey bos birakildiginda "sadece IP yaz, geri kalanini
  /// terminalden gir" akisini saglar - kimlik bilgisi formda YOKSA burada
  /// devreye girer.
  Future<String> _promptLine(Terminal term, String prompt, {bool echo = true}) {
    term.write(prompt);
    final completer = Completer<String>();
    final buf = StringBuffer();
    term.onOutput = (data) {
      if (completer.isCompleted) return;
      for (final code in data.runes) {
        if (code == 13 || code == 10) {
          term.write('\r\n');
          completer.complete(buf.toString());
          return;
        } else if (code == 127 || code == 8) {
          if (buf.isNotEmpty) {
            final s = buf.toString().substring(0, buf.length - 1);
            buf.clear();
            buf.write(s);
            if (echo) term.write('\b \b');
          }
        } else if (code == 3) {
          completer.completeError(Exception('cancelled'));
          return;
        } else if (code >= 32) {
          buf.writeCharCode(code);
          if (echo) term.write(String.fromCharCode(code));
        }
      }
    };
    return completer.future;
  }

  Future<void> _connect() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    final state = context.read<AppState>();
    final port = int.tryParse(_port.text.trim()) ?? 22;
    var username = _user.text.trim();
    var password = _pass.text;
    final rememberChecked = _remember;

    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final session = _SshSession(id: id, label: username.isEmpty ? host : '$username@$host');
    setState(() { _sessions.add(session); _activeId = id; });

    // Bir sonraki baglanti icin alanlari temizlemiyoruz (ayni host'a tekrar
    // baglanmak/duzenlemek kolay olsun diye) - sadece sifreyi ekrandan siliyoruz.
    _pass.clear();

    try {
      final socket = await SSHSocket.connect(host, port, timeout: const Duration(seconds: 12));
      if (!mounted || !_sessions.contains(session)) return;
      // Soket kuruldu - terminali goster, PuTTY tarzi "login as:"/"password:"
      // sadece formda eksik olan alan(lar) icin sorulur.
      setState(() => session.connecting = false);
      // Terminal widget'i simdi kuruldu (autofocus tek basina her zaman
      // odagi almiyor, host formundaki alan hala odaklı kalabiliyordu) -
      // frame ciziminden hemen sonra klavye odagini ZORLA terminale ver.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _activeId == session.id) session.focusNode.requestFocus();
      });

      if (username.isEmpty) {
        username = (await _promptLine(session.terminal, 'login as: ')).trim();
        if (!mounted || !_sessions.contains(session)) return;
        if (username.isEmpty) throw Exception('login cancelled');
        setState(() => session.label = '$username@$host');
      }
      if (password.isEmpty) {
        password = await _promptLine(session.terminal, '$username@$host\'s password: ', echo: false);
        if (!mounted || !_sessions.contains(session)) return;
      }

      final client = SSHClient(
        socket,
        username: username,
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
      // Basarili giristen SONRA kaydediyoruz - boylece terminalden girilen
      // kullanici adi/sifre de (form bos birakilmis olsa bile) "Remember"
      // isaretliyse kaydedilir.
      if (rememberChecked) {
        await state.saveSshProfile(host: host, port: port, username: username, password: password);
      } else {
        await state.saveSshProfile(host: host, port: port, username: username);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { session.connecting = false; session.error = _friendlySshError(e); });
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

  void _activateSession(_SshSession s) {
    setState(() => _activeId = s.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _activeId == s.id) s.focusNode.requestFocus();
    });
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

    // mRemoteNG duzeni: solda dar/sabit bir "baglantilar" paneli (yeni
    // baglanti formu + kayitli liste), sagda TAMAMEN CLI - sekmeler ve
    // altinda mumkun oldugunca genis/yuksek terminal.
    return Row(children: [
      Container(
        width: 300,
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
        decoration: BoxDecoration(border: Border(right: BorderSide(color: c.lineSoft))),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Caption(t(state.lang, 'ssh.newTab'), c),
            const SizedBox(height: 12),
            LabeledField(label: t(state.lang, 'field.host'), controller: _host, c: c, hint: '192.168.1.1', onSubmitted: (_) => _connect()),
            const SizedBox(height: 8),
            LabeledField(label: t(state.lang, 'field.port'), controller: _port, c: c, hint: '22'),
            const SizedBox(height: 8),
            LabeledField(label: t(state.lang, 'field.username'), controller: _user, c: c, hint: t(state.lang, 'ssh.usernameHint')),
            const SizedBox(height: 8),
            LabeledField(label: t(state.lang, 'field.password'), controller: _pass, c: c, obscure: true, onSubmitted: (_) => _connect()),
            const SizedBox(height: 10),
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
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: PrimaryButton(label: t(state.lang, 'action.connect'), c: c, onPressed: _connect)),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: GhostButton(label: t(state.lang, 'action.check'), c: c, onPressed: _checking ? null : _check)),
            if (_checkResult != null) ...[
              const SizedBox(height: 10),
              StatusLine(
                kind: _checking ? StatusKind.busy : (_checkResult!['ok'] == true ? StatusKind.ok : StatusKind.error),
                text: _checking
                    ? t(state.lang, 'ssh.connecting')
                    : (_checkResult!['ok'] == true
                        ? (_checkResult!['is_ssh'] == true ? 'SSH service detected' : 'Port open, but no SSH banner')
                        : friendlyAgentError(_checkResult!['error']?.toString())),
                c: c,
              ),
              if (_checkResult!['ok'] == true && (_checkResult!['banner']?.toString().isNotEmpty ?? false))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_checkResult!['banner'].toString(), style: TextStyle(color: c.inkFaint, fontFamily: 'monospace', fontSize: 11)),
                ),
            ],
            if (state.sshProfiles.isNotEmpty) ...[
              const SizedBox(height: 20),
              Divider(height: 1, color: c.lineSoft),
              const SizedBox(height: 14),
              Caption(t(state.lang, 'ssh.recent'), c),
              const SizedBox(height: 8),
              for (final p in state.sshProfiles)
                _SavedRow(profile: p, c: c, onTap: () => _connectFromProfile(p), onDelete: () => state.removeSshProfile(p.id)),
            ],
          ]),
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(children: [
            if (_sessions.isNotEmpty) ...[
              SizedBox(
                height: 34,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final s in _sessions) _SessionTab(session: s, active: s.id == _activeId, c: c, onTap: () => _activateSession(s), onClose: () => _closeSession(s.id)),
                ]),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: activeSession == null
                  ? _EmptyState(c: c, text: _sessions.isEmpty ? t(state.lang, 'ssh.noTabs') : '')
                  : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
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
                              : GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: () => activeSession.focusNode.requestFocus(),
                                  child: TerminalView(
                                    activeSession.terminal,
                                    controller: activeSession.controller,
                                    focusNode: activeSession.focusNode,
                                    autofocus: true,
                                    backgroundOpacity: 0,
                                  ),
                                ),
                    ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _SavedRow extends StatefulWidget {
  final SshProfile profile;
  final AppColors c;
  final VoidCallback onTap, onDelete;
  const _SavedRow({required this.profile, required this.c, required this.onTap, required this.onDelete});
  @override
  State<_SavedRow> createState() => _SavedRowState();
}

class _SavedRowState extends State<_SavedRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(color: _hover ? c.fillHover : Colors.transparent, borderRadius: BorderRadius.circular(7)),
          child: Row(children: [
            Icon(Icons.dns_outlined, size: 13, color: c.inkFaint),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.profile.label, style: TextStyle(color: c.inkSoft, fontSize: 12.5), overflow: TextOverflow.ellipsis)),
            if (widget.profile.savePassword) Icon(Icons.lock, size: 11, color: c.inkGhost),
            if (_hover) ...[
              const SizedBox(width: 6),
              GestureDetector(onTap: widget.onDelete, child: Icon(Icons.close, size: 13, color: c.inkFaint)),
            ],
          ]),
        ),
      ),
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
