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
  final _name = TextEditingController();
  bool _remember = false;
  String? _folderId;
  final Set<String> _collapsedFolders = {};

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
    _name.dispose();
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
    final name = _name.text.trim();
    final rememberChecked = _remember;
    final folderId = _folderId;

    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final initialLabel = name.isNotEmpty ? name : (username.isEmpty ? host : '$username@$host');
    final session = _SshSession(id: id, label: initialLabel);
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
        if (name.isEmpty) setState(() => session.label = '$username@$host');
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
        await state.saveSshProfile(host: host, port: port, username: username, password: password, name: name, folderId: folderId);
      } else {
        await state.saveSshProfile(host: host, port: port, username: username, name: name, folderId: folderId);
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
    _name.text = p.name;
    _pass.text = '';
    if (p.savePassword) {
      final pw = await context.read<AppState>().sshPassword(p.id);
      if (pw != null) _pass.text = pw;
    }
    setState(() { _remember = p.savePassword; _folderId = p.folderId; });
    await _connect();
  }

  /// Yeni klasor adi sorar (mRemoteNG'deki "musteri musteri" klasorlerinin
  /// karsiligi) - olusturulan klasor formdaki secime otomatik atanir.
  Future<void> _promptNewFolder() async {
    final state = context.read<AppState>();
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(state.lang, 'ssh.newFolder')),
        content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: t(state.lang, 'ssh.folderNameHint'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t(state.lang, 'action.cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(t(state.lang, 'action.create'))),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      final f = state.createSshFolder(name);
      setState(() => _folderId = f.id);
    }
  }

  Future<void> _promptRename(SshProfile p) async {
    final state = context.read<AppState>();
    final ctrl = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(state.lang, 'action.rename')),
        content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: t(state.lang, 'ssh.nameHint'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t(state.lang, 'action.cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(t(state.lang, 'action.save'))),
        ],
      ),
    );
    if (name != null) state.renameSshProfile(p.id, name);
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
            LabeledField(label: t(state.lang, 'field.name'), controller: _name, c: c, hint: t(state.lang, 'ssh.nameHint'), onSubmitted: (_) => _connect()),
            const SizedBox(height: 8),
            LabeledField(label: t(state.lang, 'field.host'), controller: _host, c: c, hint: '192.168.1.1', onSubmitted: (_) => _connect()),
            const SizedBox(height: 8),
            LabeledField(label: t(state.lang, 'field.port'), controller: _port, c: c, hint: '22'),
            const SizedBox(height: 8),
            LabeledField(label: t(state.lang, 'field.username'), controller: _user, c: c, hint: t(state.lang, 'ssh.usernameHint')),
            const SizedBox(height: 8),
            LabeledField(label: t(state.lang, 'field.password'), controller: _pass, c: c, obscure: true, onSubmitted: (_) => _connect()),
            const SizedBox(height: 8),
            Caption(t(state.lang, 'ssh.folder'), c),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: c.bgRise, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.lineSoft)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: state.sshFolders.any((f) => f.id == _folderId) ? _folderId : null,
                      isExpanded: true,
                      isDense: true,
                      icon: Icon(Icons.expand_more, size: 16, color: c.inkFaint),
                      style: TextStyle(color: c.inkSoft, fontSize: 12.5),
                      dropdownColor: c.bgHigh,
                      items: [
                        DropdownMenuItem<String?>(value: null, child: Text(t(state.lang, 'ssh.noFolder'))),
                        for (final f in state.sshFolders) DropdownMenuItem<String?>(value: f.id, child: Text(f.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _folderId = v),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _promptNewFolder,
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.bgRise, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.lineSoft)),
                    child: Icon(Icons.create_new_folder_outlined, size: 16, color: c.inkSoft),
                  ),
                ),
              ),
            ]),
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
            if (state.sshProfiles.isNotEmpty || state.sshFolders.isNotEmpty) ...[
              const SizedBox(height: 20),
              Divider(height: 1, color: c.lineSoft),
              const SizedBox(height: 14),
              Caption(t(state.lang, 'ssh.recent'), c),
              const SizedBox(height: 8),
              // mRemoteNG'deki musteri klasorleri: her klasor aç/kapa,
              // icindeki baglantilar isim-IP formatinda listelenir.
              for (final f in state.sshFolders) ...[
                _FolderRow(
                  folder: f,
                  c: c,
                  collapsed: _collapsedFolders.contains(f.id),
                  count: state.sshProfiles.where((p) => p.folderId == f.id).length,
                  onToggle: () => setState(() {
                    if (!_collapsedFolders.add(f.id)) _collapsedFolders.remove(f.id);
                  }),
                  onRename: () async {
                    final ctrl = TextEditingController(text: f.name);
                    final name = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(t(state.lang, 'action.rename')),
                        content: TextField(controller: ctrl, autofocus: true),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t(state.lang, 'action.cancel'))),
                          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(t(state.lang, 'action.save'))),
                        ],
                      ),
                    );
                    if (name != null) state.renameSshFolder(f.id, name);
                  },
                  onDelete: () => state.deleteSshFolder(f.id),
                ),
                if (!_collapsedFolders.contains(f.id))
                  for (final p in state.sshProfiles.where((p) => p.folderId == f.id))
                    Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: _SavedRow(
                        profile: p,
                        c: c,
                        lang: state.lang,
                        folders: state.sshFolders,
                        onTap: () => _connectFromProfile(p),
                        onDelete: () => state.removeSshProfile(p.id),
                        onRename: () => _promptRename(p),
                        onMove: (folderId) => state.moveSshProfile(p.id, folderId),
                      ),
                    ),
              ],
              for (final p in state.sshProfiles.where((p) => p.folderId == null || !state.sshFolders.any((f) => f.id == p.folderId)))
                _SavedRow(
                  profile: p,
                  c: c,
                  lang: state.lang,
                  folders: state.sshFolders,
                  onTap: () => _connectFromProfile(p),
                  onDelete: () => state.removeSshProfile(p.id),
                  onRename: () => _promptRename(p),
                  onMove: (folderId) => state.moveSshProfile(p.id, folderId),
                ),
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
  final String lang;
  final List<SshFolder> folders;
  final VoidCallback onTap, onDelete, onRename;
  final ValueChanged<String?> onMove;
  const _SavedRow({
    required this.profile,
    required this.c,
    required this.lang,
    required this.folders,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
    required this.onMove,
  });
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
            Expanded(child: Text(widget.profile.treeLabel, style: TextStyle(color: c.inkSoft, fontSize: 12.5), overflow: TextOverflow.ellipsis)),
            if (widget.profile.savePassword) Icon(Icons.lock, size: 11, color: c.inkGhost),
            if (_hover) ...[
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.more_horiz, size: 14, color: c.inkFaint),
                color: c.bgHigh,
                itemBuilder: (ctx) => [
                  PopupMenuItem(value: 'rename', child: Text(t(widget.lang, 'action.rename'))),
                  PopupMenuItem(value: 'move:none', child: Text('→ ${t(widget.lang, 'ssh.noFolder')}')),
                  for (final f in widget.folders) PopupMenuItem(value: 'move:${f.id}', child: Text('→ ${f.name}', overflow: TextOverflow.ellipsis)),
                ],
                onSelected: (v) {
                  if (v == 'rename') {
                    widget.onRename();
                  } else if (v.startsWith('move:')) {
                    final target = v.substring(5);
                    widget.onMove(target == 'none' ? null : target);
                  }
                },
              ),
              GestureDetector(onTap: widget.onDelete, child: Icon(Icons.close, size: 13, color: c.inkFaint)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _FolderRow extends StatefulWidget {
  final SshFolder folder;
  final AppColors c;
  final bool collapsed;
  final int count;
  final VoidCallback onToggle, onRename, onDelete;
  const _FolderRow({
    required this.folder,
    required this.c,
    required this.collapsed,
    required this.count,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
  });
  @override
  State<_FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<_FolderRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onToggle,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2, top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(color: _hover ? c.fillHover : Colors.transparent, borderRadius: BorderRadius.circular(7)),
          child: Row(children: [
            Icon(widget.collapsed ? Icons.chevron_right : Icons.expand_more, size: 15, color: c.inkFaint),
            const SizedBox(width: 2),
            Icon(Icons.folder_outlined, size: 13, color: c.accent),
            const SizedBox(width: 7),
            Expanded(child: Text(widget.folder.name, style: TextStyle(color: c.ink, fontSize: 12.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            Text('${widget.count}', style: TextStyle(color: c.inkFaint, fontSize: 11)),
            if (_hover) ...[
              const SizedBox(width: 4),
              GestureDetector(onTap: widget.onRename, child: Icon(Icons.edit_outlined, size: 12, color: c.inkFaint)),
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
