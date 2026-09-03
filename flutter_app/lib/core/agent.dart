import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Yerel ping-agent.py (veya derlenmis NetworkConsole-Agent.exe) surecini
/// yonetir ve HTTP JSON API'sine erisim saglar. Mimari app.py + ag-konsolu.html
/// ile ayni: Flutter burada sadece eski WebView2/HTML katmaninin yerini alir,
/// arka uctaki olcum mantigi (ping/traceroute/dns/...) hic degismez.
class Agent {
  static const List<int> portRange = [8787, 8788, 8789, 8790, 8791, 8792, 8793, 8794, 8795, 8796];
  // ping-agent.py /api/health icindeki "version" alaniyla eslesir - agent
  // yeni /api/... rotalari eklediginde burada da artirilir. Kullanicinin
  // makinesinde bir onceki kurulumdan kalip arka planda calismaya devam
  // eden ESKI bir ajan sureci varsa (upgrade sirasinda kapanmadiysa), UI
  // onu direkt yeniden kullanmak yerine kapatip taze bir surec baslatir -
  // yoksa yeni eklenen uc noktalar (orn. /api/ssh) "not found" doner.
  static const int kMinAgentVersion = 5;
  int? port;
  Map<String, dynamic>? lastHealth;

  String get base => 'http://127.0.0.1:${port ?? 8787}';

  Directory get _here => Directory(File(Platform.resolvedExecutable).parent.path);

  Future<File> _portFile() async {
    // Derlenmis pakette exe'nin yaninda; gelistirmede belge klasorunde tut.
    try {
      final f = File('${_here.path}${Platform.pathSeparator}port.txt');
      return f;
    } catch (_) {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}${Platform.pathSeparator}port.txt');
    }
  }

  Future<bool> _probe(int p, {int timeoutMs = 600}) async {
    try {
      final r = await http
          .get(Uri.parse('http://127.0.0.1:$p/api/health'))
          .timeout(Duration(milliseconds: timeoutMs));
      if (r.statusCode != 200) return false;
      final j = jsonDecode(r.body);
      if (j['agent'] == 'ping-konsolu') {
        lastHealth = j;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _portFree(int p) async {
    try {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, p);
      await s.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  String? _agentBinary() {
    final dir = _here.path;
    final exe = Platform.isWindows
        ? '$dir${Platform.pathSeparator}NetworkConsole-Agent.exe'
        : '$dir${Platform.pathSeparator}NetworkConsole-Agent';
    if (File(exe).existsSync()) return exe;
    return null;
  }

  Future<int> _pickPort() async {
    int? preferred;
    try {
      final f = await _portFile();
      if (f.existsSync()) preferred = int.tryParse(f.readAsStringSync().trim());
    } catch (_) {}

    if (preferred != null && await _probe(preferred)) return preferred;
    for (final p in portRange) {
      if (await _probe(p)) return p;
    }
    if (preferred != null && portRange.contains(preferred)) {
      for (var i = 0; i < 8; i++) {
        if (await _portFree(preferred)) return preferred;
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    for (final p in portRange) {
      if (await _portFree(p)) return p;
    }
    return portRange.first;
  }

  Future<void> _savePort(int p) async {
    try {
      final f = await _portFile();
      await f.writeAsString(p.toString());
    } catch (_) {}
  }

  /// Ajani bulur/baslatir. Zaten calisiyorsa yenisini baslatmaz.
  Future<bool> ensureRunning() async {
    final p = await _pickPort();
    port = p;
    await _savePort(p);
    if (await _probe(p)) {
      final runningVersion = (lastHealth?['version'] as num?)?.toInt() ?? 0;
      if (runningVersion >= kMinAgentVersion) return true;
      // eski surumlu bir ajan calisiyor - kapat ve asagida taze baslat
      try {
        await http.get(Uri.parse('http://127.0.0.1:$p/api/shutdown')).timeout(const Duration(seconds: 2));
      } catch (_) {}
      final freedDeadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(freedDeadline)) {
        if (!await _probe(p, timeoutMs: 300)) break;
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    final bin = _agentBinary();
    try {
      if (bin != null) {
        await Process.start(bin, ['--port', '$p'], mode: ProcessStartMode.detached);
      } else {
        // Kaynaktan calisirken: repo kokundeki ping-agent.py'yi python ile baslat.
        final script = '${_here.parent.path}${Platform.pathSeparator}ping-agent.py';
        await Process.start('python', [script, '--port', '$p', '--no-tray'],
            mode: ProcessStartMode.detached);
      }
    } catch (_) {
      return false;
    }
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (await _probe(p, timeoutMs: 1000)) return true;
      await Future.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? params, Duration? timeout]) async {
    try {
      final uri = Uri.parse('$base$path').replace(queryParameters: params);
      // traceroute butcesi agent tarafinda maxhops*3*timeout+10s'ye kadar
      // cikabilir (bkz. ping-agent.py run_traceroute) - sabit 25s burada
      // "agent unreachable" yaniligina yol aciyordu, halbuki ajan hala
      // calisiyordu, sadece uzun suruyordu.
      final effective = timeout ?? (path == '/api/traceroute' ? const Duration(seconds: 100) : const Duration(seconds: 25));
      final r = await http.get(uri).timeout(effective);
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e) {
      return {'ok': false, 'error': 'agent unreachable'};
    }
  }

  Future<Map<String, dynamic>> vtCheck(String url, String vtKey) async {
    try {
      final uri = Uri.parse('$base/api/vtcheck').replace(queryParameters: {'url': url});
      final r = await http
          .get(uri, headers: vtKey.isNotEmpty ? {'X-VT-Key': vtKey} : {})
          .timeout(const Duration(seconds: 25));
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e) {
      return {'ok': false, 'error': 'agent unreachable'};
    }
  }
}
