import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Yerel ping-agent.py (veya derlenmis NetworkConsole-Agent.exe) surecini
/// yonetir ve HTTP JSON API'sine erisim saglar. Mimari app.py + ag-konsolu.html
/// ile ayni: Flutter burada sadece eski WebView2/HTML katmaninin yerini alir,
/// arka uctaki olcum mantigi (ping/traceroute/dns/...) hic degismez.
class Agent {
  // v2 kendi port araligini kullanir. 8787 bilerek DISARIDA birakildi: eski
  // 1.5.x kurulumu (ayri bir uygulama, ayri bir ajan surumu) orayi tutuyor
  // olabiliyor ve o ajan yeni uc noktalari (SSH/SNMP/WoL) tanimadigi icin
  // "not found" donuyordu. Ayri aralik = iki surum yan yana dursa bile hicbir
  // zaman ayni surece baglanmayiz.
  static const List<int> portRange = [8877, 8878, 8879, 8880, 8881, 8882, 8883, 8884, 8885, 8886];
  // ping-agent.py /api/health icindeki "version" alaniyla eslesir - agent
  // yeni /api/... rotalari eklediginde burada da artirilir. Kullanicinin
  // makinesinde bir onceki kurulumdan kalip arka planda calismaya devam
  // eden ESKI bir ajan sureci varsa (upgrade sirasinda kapanmadiysa), UI
  // onu direkt yeniden kullanmak yerine kapatip taze bir surec baslatir -
  // yoksa yeni eklenen uc noktalar (orn. /api/ssh) "not found" doner.
  static const int kMinAgentVersion = 5;
  int? port;
  Map<String, dynamic>? lastHealth;

  String get base => 'http://127.0.0.1:${port ?? portRange.first}';

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

  /// Once port.txt'teki, sonra araliktaki portlari tarar. Yeterince yeni bir
  /// ajan bulursa portunu doner; ESKI surumlu ajan bulduklarini [stale]
  /// listesine yazar (cagiran taraf onlari kapatmayi/atlamayi secer).
  Future<int?> _findCompatiblePort(List<int> stale) async {
    int? preferred;
    try {
      final f = await _portFile();
      if (f.existsSync()) preferred = int.tryParse(f.readAsStringSync().trim());
    } catch (_) {}
    // Eski kurulumdan kalma bir port.txt bizi kendi araligimizin disina
    // (orn. 1.5.x'in 8787'sine) goturmesin.
    if (preferred != null && !portRange.contains(preferred)) preferred = null;

    final candidates = <int>[
      ?preferred,
      ...portRange.where((p) => p != preferred),
    ];

    for (final p in candidates) {
      if (!await _probe(p)) continue;
      final v = (lastHealth?['version'] as num?)?.toInt() ?? 0;
      if (v >= kMinAgentVersion) return p;
      stale.add(p);
    }
    return null;
  }

  Future<int> _freePort() async {
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

  /// Ajani bulur/baslatir. Yeterince yeni bir ajan zaten calisiyorsa yenisini
  /// baslatmaz; eski surumlu bir ajan portu tutuyorsa once onu kapatmayi
  /// dener, kapanmiyorsa o portu tamamen birakip baska bir porta taze ajan
  /// kurar.
  Future<bool> ensureRunning() async {
    final stale = <int>[];
    final ready = await _findCompatiblePort(stale);
    if (ready != null) {
      port = ready;
      await _savePort(ready);
      return true;
    }

    // Eski surumlu ajan(lar) buldu: nazikce kapanmalarini iste. /api/shutdown
    // sadece version >= 5 ajanlarda var - daha eskisi 404 doner ve yasamaya
    // devam eder; ayrica surec yonetici haklariyla baslatilmis olabilir, o
    // zaman disaridan oldurmek de mumkun degil. Bu yuzden kapanmayan portu
    // ZORLAMIYORUZ, asagida baska bos bir port seciyoruz.
    for (final p in stale) {
      try {
        await http
            .get(Uri.parse('http://127.0.0.1:$p/api/shutdown'))
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    if (stale.isNotEmpty) {
      final freedDeadline = DateTime.now().add(const Duration(seconds: 4));
      while (DateTime.now().isBefore(freedDeadline)) {
        if (await _portFree(stale.first)) break;
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    final p = await _freePort();
    port = p;
    await _savePort(p);

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

  Future<bool>? _reconnecting;

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? params, Duration? timeout, bool _retry = true]) async {
    // Sogumus baslangic (AV taramasi/yavas disk yuzunden ensureRunning'in ilk
    // 10sn'lik penceresini kacirmis olabilir) ya da ajan araya girip cokmus
    // olabilir: her istek sonrasi degil ama port hic bulunamamissa ya da bu
    // istek basarisiz olmussa, kullanicinin bir daha "Check"e basmasini
    // beklemeden burada bir kere kendimiz toparlanmayi deneriz. Ayni anda
    // birden fazla ekran ayni sorunu yasarsa tek bir ensureRunning calismasi
    // paylasilir (_reconnecting).
    if (port == null) {
      await (_reconnecting ??= ensureRunning().whenComplete(() => _reconnecting = null));
    }
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
      if (_retry) {
        final reconnected = await (_reconnecting ??= ensureRunning().whenComplete(() => _reconnecting = null));
        if (reconnected) return get(path, params, timeout, false);
      }
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
