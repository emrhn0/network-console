import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// GitHub Releases'teki en son etiketi (flutter-v2 hattinda hep v2.*.*)
/// mevcut surumle karsilastirir. Kontrol her uygulama acilisinda tekrar
/// calisir - "bu surumu atla" gibi kalici bir bayrak YOK, kullanici Cancel
/// derse sadece o oturumda sorulmaz, bir sonraki acilista tekrar sorulur.
class UpdateInfo {
  final String version; // "2.7.8" (basindaki v atilmis)
  final String htmlUrl;
  final String? windowsSetupUrl;
  UpdateInfo({required this.version, required this.htmlUrl, this.windowsSetupUrl});
}

class UpdateChecker {
  static const _repo = 'emrhn0/network-console';

  static List<int> _parse(String v) {
    final parts = v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }

  static bool isNewer(String latest, String current) {
    final a = _parse(latest), b = _parse(current);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  static Future<UpdateInfo?> checkForUpdate(String currentVersion) async {
    try {
      final r = await http.get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        headers: {'User-Agent': 'NetworkConsole-App', 'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final tag = (j['tag_name'] as String?) ?? '';
      final version = tag.startsWith('v') ? tag.substring(1) : tag;
      if (version.isEmpty || !isNewer(version, currentVersion)) return null;

      String? winUrl;
      for (final a in (j['assets'] as List? ?? [])) {
        final name = a['name'] as String? ?? '';
        final url = a['browser_download_url'] as String?;
        if (url != null && name.endsWith('_Setup.exe')) winUrl = url;
      }
      return UpdateInfo(
        version: version,
        htmlUrl: j['html_url'] as String? ?? 'https://github.com/$_repo/releases/latest',
        windowsSetupUrl: winUrl,
      );
    } catch (_) {
      // internet yok / GitHub erisilemiyor - sessizce vazgec, acilisi engelleme
      return null;
    }
  }

  /// Setup.exe'yi gecici klasore indirir ve ayri (detached) surec olarak
  /// baslatir. Cagiran taraf bundan hemen sonra uygulamayi KAPATMALI - Inno
  /// Setup calisan surumu kapatmayi kendisi de dener ama once biz kapatirsak
  /// "Setup was unable to automatically close all applications" uyarisiyla
  /// hic karsilasilmaz (bkz. v2.7.1 kurulum sorunu).
  static Future<bool> downloadAndLaunchWindowsInstaller(String url, void Function(double progress) onProgress) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}NetworkConsole_Update_Setup.exe');
      final req = http.Request('GET', Uri.parse(url));
      final resp = await req.send();
      final total = resp.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.close();
      await Process.start(file.path, [], mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }
}
