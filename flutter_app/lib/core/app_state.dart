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
  String name;
  String? folderId;
  SshProfile({
    required this.id,
    required this.host,
    required this.port,
    required this.username,
    required this.savePassword,
    this.name = '',
    this.folderId,
  });
  Map<String, dynamic> toJson() =>
      {'id': id, 'host': host, 'port': port, 'username': username, 'savePassword': savePassword, 'name': name, 'folderId': folderId};
  factory SshProfile.fromJson(Map<String, dynamic> j) => SshProfile(
        id: j['id'] as String,
        host: j['host'] as String,
        port: (j['port'] as num?)?.toInt() ?? 22,
        username: j['username'] as String? ?? '',
        savePassword: j['savePassword'] as bool? ?? false,
        name: j['name'] as String? ?? '',
        folderId: j['folderId'] as String?,
      );
  String get label => username.isEmpty ? host : '$username@$host';
  /// mRemoteNG'deki gibi baglantiya ozel bir isim ("SW1" vb.) - bos ise
  /// host/kullanici geri dusulur. Sekme basligi gibi kisa yerlerde kullanilir.
  String get displayName => name.isNotEmpty ? name : label;
  /// Kayitli baglantilar agacinda gosterilen satir - isim varsa mRemoteNG'nin
  /// "AD - IP" bicimi (orn. "ARGE SW - 10.20.5.18"), yoksa duz host/kullanici.
  String get treeLabel => name.isNotEmpty ? '$name - $host' : label;
}

/// Baglantilari gruplamak icin klasor ("musteri musteri ayirmak" icin) -
/// mRemoteNG'nin baglanti agacindaki klasorlerin karsiligi.
class SshFolder {
  final String id;
  String name;
  SshFolder({required this.id, required this.name});
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory SshFolder.fromJson(Map<String, dynamic> j) => SshFolder(id: j['id'] as String, name: j['name'] as String? ?? '');
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
  List<SshFolder> sshFolders = [];

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    isDark = _prefs?.getBool('nc-dark') ?? false;
    lang = _prefs?.getString('nc-lang') ?? 'en';
    vtKey = _prefs?.getString('nc-vt-key') ?? '';
    _loadSshProfiles();
    _loadSshFolders();
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
  /// baglanabilir). [name]/[folderId] cagiran tarafin form durumu neyse
  /// AYNEN uygulanir (birlestirme yok) - _connectFromProfile zaten eski
  /// degerleri forma yukleyip oradan tekrar geciriyor.
  Future<SshProfile> saveSshProfile({
    required String host,
    required int port,
    required String username,
    String? password,
    String name = '',
    String? folderId,
  }) async {
    final h = host.trim(), u = username.trim();
    final existing = sshProfiles.where((p) => p.host == h && p.port == port && p.username == u);
    final id = existing.isNotEmpty ? existing.first.id : '${DateTime.now().microsecondsSinceEpoch}';
    final hadPassword = existing.isNotEmpty && existing.first.savePassword;
    sshProfiles.removeWhere((p) => p.id == id);
    final profile = SshProfile(
      id: id,
      host: h,
      port: port,
      username: u,
      savePassword: (password != null && password.isNotEmpty) || hadPassword,
      name: name.trim(),
      folderId: folderId,
    );
    sshProfiles.insert(0, profile);
    if (sshProfiles.length > 300) sshProfiles.removeRange(300, sshProfiles.length);
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

  void renameSshProfile(String id, String name) {
    final matches = sshProfiles.where((p) => p.id == id);
    if (matches.isEmpty) return;
    matches.first.name = name.trim();
    _persistSshProfiles();
    notifyListeners();
  }

  void moveSshProfile(String id, String? folderId) {
    final matches = sshProfiles.where((p) => p.id == id);
    if (matches.isEmpty) return;
    matches.first.folderId = folderId;
    _persistSshProfiles();
    notifyListeners();
  }

  void _loadSshFolders() {
    final raw = _prefs?.getString('nc-ssh-folders');
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      sshFolders = list.map((e) => SshFolder.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      sshFolders = [];
    }
  }

  void _persistSshFolders() {
    _prefs?.setString('nc-ssh-folders', jsonEncode(sshFolders.map((f) => f.toJson()).toList()));
  }

  /// mRemoteNG'deki musteri klasorleri gibi - baglantilari gruplamak icin.
  SshFolder createSshFolder(String name) {
    final n = name.trim();
    final folder = SshFolder(id: '${DateTime.now().microsecondsSinceEpoch}', name: n.isEmpty ? '?' : n);
    sshFolders.add(folder);
    _persistSshFolders();
    notifyListeners();
    return folder;
  }

  void renameSshFolder(String id, String name) {
    final matches = sshFolders.where((f) => f.id == id);
    if (matches.isEmpty) return;
    final n = name.trim();
    if (n.isEmpty) return;
    matches.first.name = n;
    _persistSshFolders();
    notifyListeners();
  }

  /// Klasoru siler; icindeki baglantilar KAYBOLMAZ, sadece klasorsuz kalir.
  void deleteSshFolder(String id) {
    sshFolders.removeWhere((f) => f.id == id);
    for (final p in sshProfiles) {
      if (p.folderId == id) p.folderId = null;
    }
    _persistSshFolders();
    _persistSshProfiles();
    notifyListeners();
  }
}
