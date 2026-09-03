import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'agent.dart';

class HistoryEntry {
  final String view, summary;
  final DateTime ts;
  HistoryEntry(this.view, this.summary, this.ts);
}

/// Kaydedilmis bir SSH baglantisi (host/port/kullanici + opsiyonel sifre).
/// Sifre BURADA TUTULMAZ - profil metadata'si duz metin shared_preferences'te,
/// gercek sifre ise isletim sisteminin guvenli deposunda (Windows Credential
/// Locker / macOS Keychain) flutter_secure_storage ile "ssh-pw-<id>"
/// anahtariyla saklanir. Ikisi de {app} kurulum klasorunun DISINDA oldugu
/// icin bir surum yukseltmesinde silinmez.
class SshProfile {
  final String id, host, username;
  final int port;
  final bool savePassword;
  SshProfile({required this.id, required this.host, required this.port, required this.username, required this.savePassword});
  Map<String, dynamic> toJson() => {'id': id, 'host': host, 'port': port, 'username': username, 'savePassword': savePassword};
  factory SshProfile.fromJson(Map<String, dynamic> j) => SshProfile(
        id: j['id'] as String,
        host: j['host'] as String,
        port: (j['port'] as num?)?.toInt() ?? 22,
        username: j['username'] as String? ?? '',
        savePassword: j['savePassword'] as bool? ?? false,
      );
  String get label => username.isEmpty ? host : '$username@$host';
}

class AppState extends ChangeNotifier {
  final Agent agent = Agent();
  SharedPreferences? _prefs;

  bool isDark = false;
  String lang = 'en'; // 'en' | 'tr'
  String vtKey = '';
  bool agentConnected = false;
  String agentMethod = 'HTTPS';
  final List<HistoryEntry> history = [];
  DateTime sessionStart = DateTime.now();

  final _secure = const FlutterSecureStorage();

  // Kaydedilmis SSH baglantilari (en yeni basta). shared_preferences
  // uzerinden %APPDATA% altinda saklanir - {app} kurulum klasorunun disinda
  // oldugu icin bir surum yukseltmesinde/yeniden kurulumda SILINMEZ (bkz.
  // installer.iss [InstallDelete]: sadece {app} temizlenir, kullanici
  // verisine dokunulmaz). Ayni mekanizma isDark/lang/vtKey icin de gecerli.
  List<SshProfile> sshProfiles = [];

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    isDark = _prefs?.getBool('nc-dark') ?? false;
    lang = _prefs?.getString('nc-lang') ?? 'en';
    vtKey = _prefs?.getString('nc-vt-key') ?? '';
    _loadSshProfiles();
    notifyListeners();

    final ok = await agent.ensureRunning();
    agentConnected = ok;
    agentMethod = ok ? 'ICMP' : 'HTTPS';
    if (!ok && vtKey.isEmpty) {
      // dosya yedeginden anahtar kurtarma girisimi (agent olmasa da dosya okunabilir)
    }
    notifyListeners();
  }

  void toggleDark(bool v) {
    isDark = v;
    _prefs?.setBool('nc-dark', v);
    notifyListeners();
  }

  void setLang(String l) {
    lang = l;
    _prefs?.setString('nc-lang', l);
    notifyListeners();
  }

  void setVtKey(String v) {
    vtKey = v.trim();
    _prefs?.setString('nc-vt-key', vtKey);
    notifyListeners();
  }

  void clearVtKey() {
    vtKey = '';
    _prefs?.remove('nc-vt-key');
    notifyListeners();
  }

  Future<void> refreshAgent() async {
    final ok = await agent.ensureRunning();
    agentConnected = ok;
    agentMethod = ok ? 'ICMP' : 'HTTPS';
    notifyListeners();
  }

  void logHistory(String view, String summary) {
    history.insert(0, HistoryEntry(view, summary, DateTime.now()));
    if (history.length > 40) history.removeLast();
    notifyListeners();
  }

  void _loadSshProfiles() {
    final raw = _prefs?.getString('nc-ssh-profiles');
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      sshProfiles = list.map((e) => SshProfile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      sshProfiles = [];
    }
  }

  void _persistSshProfiles() {
    _prefs?.setString('nc-ssh-profiles', jsonEncode(sshProfiles.map((p) => p.toJson()).toList()));
  }

  /// Baglanti kurulunca (basarili ya da denenmis) cagrilir - ayni host+port+
  /// kullanici zaten kayitliysa gunceller (en basa tasir), degilse yeni ekler.
  /// [password] bos degilse guvenli depoya yazilir; bossa ve profil zaten
  /// sifre saklıyorsa o sifreye DOKUNULMAZ (kullanici bos birakip tekrar
  /// baglanabilir).
  Future<SshProfile> saveSshProfile({required String host, required int port, required String username, String? password}) async {
    final h = host.trim(), u = username.trim();
    final existing = sshProfiles.where((p) => p.host == h && p.port == port && p.username == u);
    final id = existing.isNotEmpty ? existing.first.id : '${DateTime.now().microsecondsSinceEpoch}';
    final hadPassword = existing.isNotEmpty && existing.first.savePassword;
    sshProfiles.removeWhere((p) => p.id == id);
    final profile = SshProfile(id: id, host: h, port: port, username: u, savePassword: (password != null && password.isNotEmpty) || hadPassword);
    sshProfiles.insert(0, profile);
    if (sshProfiles.length > 30) sshProfiles.removeRange(30, sshProfiles.length);
    _persistSshProfiles();
    if (password != null && password.isNotEmpty) {
      await _secure.write(key: 'ssh-pw-$id', value: password);
    }
    notifyListeners();
    return profile;
  }

  Future<String?> sshPassword(String profileId) => _secure.read(key: 'ssh-pw-$profileId');

  Future<void> removeSshProfile(String id) async {
    sshProfiles.removeWhere((p) => p.id == id);
    _persistSshProfiles();
    await _secure.delete(key: 'ssh-pw-$id');
    notifyListeners();
  }
}
