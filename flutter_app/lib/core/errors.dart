/// Agent (ping-agent.py) bazi hata mesajlarini Turkce doner (orn. "zaman
/// asimi"). Kabuk Ingilizce/Turkce olabildigi icin burada bilinen mesajlari
/// okunakli Ingilizce'ye ceviriyoruz; taniyamadigimiz mesaji oldugu gibi
/// gosteririz (veri kaybi olmasin diye).
const Map<String, String> _agentErrorEn = {
  'zaman asimi': 'timed out',
  'gecersiz hedef': 'invalid target',
  'gecersiz port': 'invalid port',
  'ajan mesgul': 'agent busy',
  'ajan mesgul (traceroute)': 'agent busy (traceroute)',
  'ajan mesgul (VirusTotal)': 'agent busy (VirusTotal)',
  'cozumlenemedi': 'could not resolve',
  'hic hop bulunamadi': 'no hops found',
  'yanit ayristirilamadi': 'could not parse response',
  'traceroute komutu bulunamadi': 'traceroute command not found',
  'isim cozumlenemedi': 'name could not be resolved',
  'adres bulunamadi': 'address not found',
  'baglanti hatasi': 'connection error',
  'cok fazla yonlendirme': 'too many redirects',
  'toplam zaman asimi': 'total timeout',
  'desteklenmeyen sema': 'unsupported scheme',
  'yonlendirme dongusu': 'redirect loop',
  'bu agdan erisim yok': 'not allowed from this network',
  'uzak olcum kapali': 'remote measurement disabled',
  'anahtar gecersiz': 'invalid token',
  'VirusTotal anahtari tanimli degil - uygulamada \'Aktive Et\' ile kendi anahtarinizi ekleyin':
      'No VirusTotal key set - add your own in Settings',
  'VirusTotal anahtari gecersiz': 'Invalid VirusTotal key',
  'VirusTotal kota asimi - biraz sonra tekrar dene': 'VirusTotal quota exceeded - try again shortly',
  'agent unreachable': 'agent unreachable',
};

String friendlyAgentError(String? raw) {
  if (raw == null || raw.isEmpty) return 'error';
  return _agentErrorEn[raw] ?? raw;
}
