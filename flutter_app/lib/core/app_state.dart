import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'agent.dart';

class HistoryEntry {
  final String view, summary;
  final DateTime ts;
  HistoryEntry(this.view, this.summary, this.ts);
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

  // Daha once SSH'la baglanilmis host'lar (en yeni basta). shared_preferences
  // uzerinden %APPDATA% altinda saklanir - {app} kurulum klasorunun disinda
  // oldugu icin bir surum yukseltmesinde/yeniden kurulumda SILINMEZ (bkz.
  // installer.iss [InstallDelete]: sadece {app} temizlenir, kullanici
  // verisine dokunulmaz). Ayni mekanizma isDark/lang/vtKey icin de gecerli.
  List<String> sshHosts = [];

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    isDark = _prefs?.getBool('nc-dark') ?? false;
    lang = _prefs?.getString('nc-lang') ?? 'en';
    vtKey = _prefs?.getString('nc-vt-key') ?? '';
    sshHosts = _prefs?.getStringList('nc-ssh-hosts') ?? [];
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

  void addSshHost(String host) {
    final h = host.trim();
    if (h.isEmpty) return;
    sshHosts.remove(h);
    sshHosts.insert(0, h);
    if (sshHosts.length > 20) sshHosts.removeRange(20, sshHosts.length);
    _prefs?.setStringList('nc-ssh-hosts', sshHosts);
    notifyListeners();
  }

  void removeSshHost(String host) {
    sshHosts.remove(host);
    _prefs?.setStringList('nc-ssh-hosts', sshHosts);
    notifyListeners();
  }
}
