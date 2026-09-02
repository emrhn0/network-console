import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_state.dart';
import '../core/constants.dart';
import '../core/errors.dart';
import '../core/i18n.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';
import 'urlcheck_screen.dart' show kVtApiKeyUrl;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _key;
  StatusKind _testKind = StatusKind.idle;
  String _testText = '';

  @override
  void initState() {
    super.initState();
    final existing = context.read<AppState>().vtKey;
    _key = TextEditingController(text: existing);
    if (existing.isNotEmpty) _testKey(existing);
  }

  Future<void> _testKey(String value) async {
    final state = context.read<AppState>();
    setState(() { _testKind = StatusKind.busy; _testText = 'Checking key against VirusTotal…'; });
    final r = await state.agent.vtCheck('https://www.google.com', value);
    if (!mounted) return;
    setState(() {
      if (r['ok'] == true) {
        _testKind = StatusKind.ok;
        _testText = 'Key works';
      } else {
        _testKind = StatusKind.error;
        _testText = friendlyAgentError(r['error']?.toString());
      }
    });
  }

  /// Anahtari kaydettikten sonra gercekten calisip calismadigini test eder -
  /// kullaniciyi tahminde birakmak yerine "kontrol ediliyor" -> "calisiyor"
  /// veya "calismiyor, sebep su" seklinde surekli bilgilendirir.
  Future<void> _saveAndTest() async {
    final state = context.read<AppState>();
    final value = _key.text.trim();
    state.setVtKey(value);
    if (value.isEmpty) {
      setState(() { _testKind = StatusKind.idle; _testText = ''; });
      return;
    }
    await _testKey(value);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppTheme(state.isDark).c;
    final lang = state.lang;
    final health = state.agent.lastHealth;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionCard(
          c: c,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Caption(t(lang, 'settings.vtTitle'), c),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: LabeledField(label: '', controller: _key, c: c, obscure: true, hint: t(lang, 'settings.vtPlaceholder'))),
              const SizedBox(width: 10),
              GhostButton(label: t(lang, 'action.save'), c: c, onPressed: _saveAndTest),
              const SizedBox(width: 8),
              GhostButton(label: t(lang, 'action.remove'), c: c, onPressed: () {
                _key.clear();
                state.clearVtKey();
                setState(() { _testKind = StatusKind.idle; _testText = ''; });
              }),
              const SizedBox(width: 8),
              GhostButton(label: t(lang, 'action.goVt'), c: c, icon: Icon(Icons.north_east, size: 12, color: c.inkFaint), onPressed: () => launchUrl(Uri.parse(kVtApiKeyUrl))),
            ]),
            const SizedBox(height: 10),
            if (_testText.isNotEmpty)
              StatusLine(kind: _testKind, text: _testText, c: c)
            else
              Text(state.vtKey.isNotEmpty ? t(lang, 'settings.vtHave') : t(lang, 'settings.vtMissing'), style: TextStyle(color: c.inkFaint, fontSize: 11.5)),
            const SizedBox(height: 6),
            Text(t(lang, 'settings.vtSteps'), style: TextStyle(color: c.inkGhost, fontSize: 11, height: 1.5)),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          c: c,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Caption(t(lang, 'settings.appearance'), c),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _pill(t(lang, 'settings.dark'), state.isDark, () => state.toggleDark(true), c)),
              const SizedBox(width: 8),
              Expanded(child: _pill(t(lang, 'settings.light'), !state.isDark, () => state.toggleDark(false), c)),
            ]),
            const SizedBox(height: 18),
            Caption(t(lang, 'settings.language'), c),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _pill('English', state.lang == 'en', () => state.setLang('en'), c)),
              const SizedBox(width: 8),
              Expanded(child: _pill('Türkçe', state.lang == 'tr', () => state.setLang('tr'), c)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          c: c,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Caption(t(lang, 'settings.agent'), c),
            const SizedBox(height: 12),
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: state.agentConnected ? c.ok : c.alarm)),
              const SizedBox(width: 8),
              Text(state.agentConnected ? t(lang, 'settings.agentRunning') : t(lang, 'settings.agentDown'), style: TextStyle(color: c.inkSoft)),
              const Spacer(),
              GhostButton(label: t(lang, 'action.refresh'), c: c, onPressed: () => state.refreshAgent()),
            ]),
            const SizedBox(height: 10),
            Text(t(lang, 'settings.agentNote'), style: TextStyle(color: c.inkGhost, fontSize: 11.5)),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          c: c,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Caption(t(lang, 'settings.about'), c),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 3.4,
              children: [
                StatCell(t(lang, 'settings.version'), 'v$kAppVersion', c),
                StatCell('Agent', health?['app_version'] != null ? 'v${health!['app_version']}' : '—', c),
                StatCell(t(lang, 'settings.host'), health?['host']?.toString() ?? '—', c),
                StatCell(t(lang, 'settings.os'), health?['os']?.toString() ?? '—', c),
                StatCell(t(lang, 'settings.method'), state.agentMethod, c),
              ],
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _pill(String label, bool active, VoidCallback onTap, AppColors c) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? c.accentWeak : Colors.transparent,
            border: Border.all(color: active ? c.accentLine : c.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label, style: TextStyle(color: active ? c.accent : c.inkFaint, fontWeight: FontWeight.w600, fontSize: 12.5)),
        ),
      );
}
