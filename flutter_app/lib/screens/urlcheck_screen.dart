import 'dart:io';
import 'package:excel/excel.dart' as excel_lib;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_state.dart';
import '../core/i18n.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

const kVtApiKeyUrl = 'https://www.virustotal.com/gui/my-apikey';

class UrlCheckScreen extends StatefulWidget {
  const UrlCheckScreen({super.key});
  @override
  State<UrlCheckScreen> createState() => _UrlCheckScreenState();
}

class _UrlCheckScreenState extends State<UrlCheckScreen> {
  final _url = TextEditingController();
  bool _busy = false;
  int _token = 0;
  String? _bulkProgress;
  final List<ResultRow> _rows = [];
  final List<LogLine> _log = [];

  String _clock() => TimeOfDay.now().format(context);

  String? _normalize(String raw) {
    var u = raw.trim();
    if (u.isEmpty || u.startsWith('#')) return null;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(u)) u = 'http://$u';
    return u;
  }

  Map<String, num> _pushRow(String url, Map<String, dynamic> r) {
    if (r['ok'] != true) {
      setState(() => _rows.add(ResultRow([url, 'Error', r['error']?.toString() ?? '', ''])));
      return {'mal': 0, 'sus': 0};
    }
    final m = (r['malicious'] ?? 0) as num, s = (r['suspicious'] ?? 0) as num;
    final h = (r['harmless'] ?? 0) as num, u = (r['undetected'] ?? 0) as num;
    var label = 'Clean';
    if (m > 0) {
      label = 'Malicious';
    } else if (s > 0) {
      label = 'Suspicious';
    }
    setState(() => _rows.add(ResultRow([r['final_url']?.toString() ?? url, label, '${m + s}/${m + s + h + u}', r['last_analysis_date']?.toString() ?? ''])));
    return {'mal': m > 0 ? 1 : 0, 'sus': (m == 0 && s > 0) ? 1 : 0};
  }

  /// Kutuya yapistirilan/yazilan metni satir satir ayirir. Tek satirsa tekli
  /// sorgu akisini, birden fazlaysa toplu taramayi calistirir - ayni kutu,
  /// ayri .txt ice aktarmaya gerek kalmadan Ctrl+V ile liste atmayi da kapsar.
  Future<void> _run() async {
    final lines = _url.text
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !s.startsWith('#'))
        .toList();
    if (lines.isEmpty) return;
    if (lines.length == 1) {
      await _checkSingle(lines.first);
    } else {
      await _runBulk(lines);
    }
  }

  Future<void> _checkSingle(String raw) async {
    final url = _normalize(raw);
    if (url == null) return;
    final state = context.read<AppState>();
    setState(() => _busy = true);
    _log.insert(0, LogLine(LogKind.sys, 'Query: $url', '', _clock()));
    final r = await state.agent.vtCheck(url, state.vtKey);
    if (!mounted) return;
    _pushRow(url, r);
    setState(() {
      _busy = false;
      _log.insert(0, LogLine(r['ok'] == true ? LogKind.ok : LogKind.err, url, r['ok'] == true ? 'done' : (r['error']?.toString() ?? ''), _clock()));
    });
    state.logHistory('urlcheck', url);
  }

  Future<void> _importFile() async {
    final typeGroup = const XTypeGroup(label: 'text', extensions: ['txt']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final text = await file.readAsString();
    final urls = text.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty && !s.startsWith('#')).toList();
    if (urls.isEmpty) return;
    await _runBulk(urls);
  }

  Future<void> _runBulk(List<String> urls) async {
    final state = context.read<AppState>();
    if (state.vtKey.isEmpty) {
      setState(() => _bulkProgress = 'No VirusTotal key — add one in Settings.');
      return;
    }
    _token++;
    final tk = _token;
    setState(() { _busy = true; _bulkProgress = '0 / ${urls.length}'; });
    var mal = 0, sus = 0, done = 0;
    for (final raw in urls) {
      if (tk != _token) return;
      final url = _normalize(raw);
      done++;
      if (url == null) continue;
      final r = await state.agent.vtCheck(url, state.vtKey);
      if (tk != _token || !mounted) return;
      final delta = _pushRow(url, r);
      mal += delta['mal']!.toInt(); sus += delta['sus']!.toInt();
      setState(() => _bulkProgress = '$done / ${urls.length} · $mal malicious, $sus suspicious');
    }
    if (tk != _token) return;
    setState(() { _busy = false; });
    state.logHistory('urlcheck', '${urls.length} URLs · $mal malicious');
  }

  Future<void> _export() async {
    if (_rows.isEmpty) return;
    final suggested = 'network-console-urlcheck-${DateTime.now().millisecondsSinceEpoch}.xlsx';
    String? path;
    try {
      final location = await getSaveLocation(
        suggestedName: suggested,
        acceptedTypeGroups: const [XTypeGroup(label: 'Excel', extensions: ['xlsx'])],
      );
      path = location?.path;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      return;
    }
    if (path == null) return; // kullanici iptal etti
    if (!path.toLowerCase().endsWith('.xlsx')) path = '$path.xlsx';
    try {
      final book = excel_lib.Excel.createExcel();
      final sheetName = book.getDefaultSheet()!;
      final sheet = book[sheetName];
      const headers = ['URL', 'Verdict', 'Engines', 'Last analysis'];
      sheet.appendRow(headers.map((h) => excel_lib.TextCellValue(h)).toList());
      for (final c in sheet.row(0)) {
        c?.cellStyle = excel_lib.CellStyle(bold: true);
      }
      for (final r in _rows) {
        sheet.appendRow(r.cells.map((v) => excel_lib.TextCellValue(v)).toList());
      }
      sheet.setColumnWidth(0, 42);
      sheet.setColumnWidth(1, 14);
      sheet.setColumnWidth(2, 12);
      sheet.setColumnWidth(3, 20);
      final bytes = book.encode();
      if (bytes == null) throw Exception('encode failed');
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $path'), duration: const Duration(seconds: 3)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppTheme(state.isDark).c;
    final hasKey = state.vtKey.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: c.bgSink, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Caption(t(state.lang, 'field.url'), c),
                TextField(
                  controller: _url,
                  minLines: 1,
                  maxLines: 6,
                  style: TextStyle(color: c.ink, fontFamily: 'monospace', fontSize: 14),
                  cursorColor: c.accent,
                  decoration: InputDecoration(
                    border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.only(top: 8),
                    hintText: 'youtube.com  ·  https://example.com/path\nor paste a list, one URL per line (Ctrl+V)',
                    hintStyle: TextStyle(color: c.inkGhost),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          PrimaryButton(label: t(state.lang, 'action.check'), onPressed: _busy ? null : _run, c: c),
          const SizedBox(width: 10),
          GhostButton(label: t(state.lang, 'action.import'), onPressed: _busy ? null : _importFile, c: c, icon: Icon(Icons.file_upload_outlined, size: 15, color: c.inkFaint)),
        ]),
        if (!hasKey)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SectionCard(
              c: c,
              child: Row(children: [
                Expanded(child: Text(t(state.lang, 'urlcheck.nudge'), style: TextStyle(color: c.inkSoft, fontSize: 12.5))),
                const SizedBox(width: 12),
                GhostButton(label: t(state.lang, 'action.goVt'), onPressed: () => launchUrl(Uri.parse(kVtApiKeyUrl)), c: c, icon: Icon(Icons.north_east, size: 12, color: c.inkFaint)),
              ]),
            ),
          ),
        if (_bulkProgress != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_bulkProgress!, style: TextStyle(color: c.inkFaint, fontSize: 12))),
        const SizedBox(height: 16),
        SectionCard(
          c: c,
          padding: const EdgeInsets.all(0),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
              child: Row(children: [
                Expanded(child: Caption(t(state.lang, 'urlcheck.results'), c)),
                TextButton(onPressed: _rows.isEmpty ? null : _export, child: Text(t(state.lang, 'action.export'), style: TextStyle(color: c.accent, fontSize: 11.5))),
                TextButton(onPressed: _rows.isEmpty ? null : () => setState(() => _rows.clear()), child: Text(t(state.lang, 'action.clear'), style: TextStyle(color: c.inkFaint, fontSize: 11.5))),
              ]),
            ),
            Divider(height: 1, color: c.lineSoft),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: _rows.isEmpty
                  ? Padding(padding: const EdgeInsets.all(24), child: Text(t(state.lang, 'urlcheck.enterUrl'), style: TextStyle(color: c.inkGhost)))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _rows.length,
                      itemBuilder: (ctx, i) {
                        final row = _rows[i];
                        final tone = row.cells[1] == 'Malicious' ? c.alarm : row.cells[1] == 'Suspicious' ? c.warn : c.inkSoft;
                        return Container(
                          color: i.isOdd ? c.fillFaint : null,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(children: [
                            Expanded(flex: 3, child: Text(row.cells[0], style: TextStyle(color: c.accent, fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                            Expanded(child: Text(row.cells[1], style: TextStyle(color: tone, fontSize: 12, fontWeight: FontWeight.w600))),
                            Expanded(child: Text(row.cells[2], style: TextStyle(color: c.inkSoft, fontFamily: 'monospace', fontSize: 12))),
                            Expanded(child: Text(row.cells[3], style: TextStyle(color: c.inkFaint, fontFamily: 'monospace', fontSize: 11))),
                          ]),
                        );
                      },
                    ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        LogPanel(lines: _log, c: c, title: 'Query log'),
      ]),
    );
  }
}
