import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/errors.dart';
import '../core/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Coklu hedef cizgi renkleri - koyu/acik iki temada da secilebilir olsun
/// diye orta doygunluklu, birbirinden ayirt edilebilir sabit bir palet.
const _palette = [
  Color(0xFFC89A3C), Color(0xFF4B8FD6), Color(0xFFD2604A),
  Color(0xFF6FA766), Color(0xFF9B72CF), Color(0xFFCB8A3E),
  Color(0xFF4FA9A8), Color(0xFFB0608E),
];

class _Target {
  final TextEditingController controller;
  final FocusNode focus = FocusNode();
  final List<double?> samples = [];
  int sent = 0, lost = 0, lastTtl = 0;
  double last = 0, min = 0, max = 0, avg = 0, jitter = 0;
  bool? lastOk;
  String lastError = '';
  String? resolvedIp;
  bool active = false;
  Timer? timer;
  // down->up veya up->down gecisinde bir sure input barinin tamamini
  // vurgulamak icin: "su ana kadar kirmizi/yesil kalsin" bitis zamani.
  DateTime? flashUntil;
  bool flashIsUp = false;
  bool get flashing => flashUntil != null && DateTime.now().isBefore(flashUntil!);
  _Target([String initial = '']) : controller = TextEditingController(text: initial);
  String get host => controller.text.trim();
  void dispose() {
    timer?.cancel();
    controller.dispose();
    focus.dispose();
  }
}

class PingScreen extends StatefulWidget {
  final bool active;
  const PingScreen({super.key, required this.active});
  @override
  State<PingScreen> createState() => _PingScreenState();
}

class _PingScreenState extends State<PingScreen> {
  final List<_Target> _targets = [_Target()];
  final List<LogLine> _log = [];
  bool _running = false;
  int _interval = 1000;
  Timer? _decayTimer; // sadece flash suresi dolunca bari normale dondurmek icin, kisa araliklarla rebuild eder
  Timer? _awayTimer; // sekmeden ayrilinca 2 dk sonra sifirlamak icin

  @override
  void didUpdateWidget(covariant PingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      _awayTimer?.cancel();
      _awayTimer = Timer(const Duration(minutes: 2), _resetAll);
    } else if (!oldWidget.active && widget.active) {
      _awayTimer?.cancel();
    }
  }

  void _resetAll() {
    if (!mounted) return;
    _stop();
    setState(() {
      for (final t in _targets) {
        t.dispose();
      }
      _targets
        ..clear()
        ..add(_Target());
      _log.clear();
    });
  }

  void _addTarget() {
    setState(() => _targets.add(_Target()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _targets.last.focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _decayTimer?.cancel();
    _awayTimer?.cancel();
    for (final t in _targets) {
      t.dispose();
    }
    super.dispose();
  }

  String _clock() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:${n.second.toString().padLeft(2, '0')}';
  }

  void _onSubmit(int i) {
    final t = _targets[i];
    if (t.host.isEmpty) return;
    if (i == _targets.length - 1) {
      _addTarget();
    } else if (i + 1 < _targets.length) {
      _targets[i + 1].focus.requestFocus();
    } else if (!_running) {
      _start();
    }
  }

  void _removeTarget(int i) {
    if (_targets.length == 1) {
      setState(() => _targets[0].controller.clear());
      return;
    }
    setState(() {
      _targets[i].dispose();
      _targets.removeAt(i);
    });
  }

  Future<void> _start() async {
    final hosts = _targets.where((t) => t.host.isNotEmpty).toList();
    if (hosts.isEmpty) return;
    setState(() {
      _running = true;
      _log.clear();
      for (final t in hosts) {
        t.samples.clear();
        t.sent = 0; t.lost = 0; t.last = 0; t.min = 0; t.max = 0; t.avg = 0; t.jitter = 0;
        t.lastOk = null; t.lastError = ''; t.resolvedIp = null; t.active = true;
      }
    });
    for (final t in hosts) {
      _resolveThenPing(t);
    }
    _decayTimer?.cancel();
    _decayTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() {}); // flash suresi dolan barlari normale dondurur
    });
  }

  void _stop() {
    _decayTimer?.cancel();
    setState(() {
      _running = false;
      for (final t in _targets) {
        t.timer?.cancel();
        t.active = false;
      }
    });
  }

  Future<void> _resolveThenPing(_Target t) async {
    final state = context.read<AppState>();
    final res = await state.agent.get('/api/resolve', {'host': t.host});
    if (mounted && res['ok'] == true) {
      setState(() {
        final ips = (res['ips'] as List?) ?? [];
        t.resolvedIp = ips.isNotEmpty ? ips.first.toString() : null;
      });
    }
    _tick(t);
  }

  Future<void> _tick(_Target t) async {
    if (!_running || !t.active) return;
    final state = context.read<AppState>();
    t.sent++;
    final r = await state.agent.get('/api/ping', {'host': t.host, 'timeout': '2000'});
    if (!mounted) return;
    setState(() {
      final prevOk = t.lastOk; // gecis (down->up / up->down) tespiti icin, uzerine yazmadan once sakla
      if (r['ok'] == true) {
        final ms = (r['ms'] as num).toDouble();
        t.samples.add(ms);
        t.last = ms;
        if (r['ttl'] != null) t.lastTtl = (r['ttl'] as num).toInt();
        final vals = t.samples.whereType<double>().toList();
        t.min = vals.reduce((a, b) => a < b ? a : b);
        t.max = vals.reduce((a, b) => a > b ? a : b);
        t.avg = vals.reduce((a, b) => a + b) / vals.length;
        if (vals.length > 1) {
          var sum = 0.0;
          for (var i = 1; i < vals.length; i++) {
            sum += (vals[i] - vals[i - 1]).abs();
          }
          t.jitter = sum / (vals.length - 1);
        }
        t.lastOk = true;
        if (prevOk == false) { t.flashIsUp = true; t.flashUntil = DateTime.now().add(const Duration(seconds: 5)); }
        _log.insert(0, LogLine(LogKind.ok, '${t.host} responded', '${ms.toStringAsFixed(0)} ms · TTL ${t.lastTtl}', _clock()));
      } else {
        t.lost++;
        t.samples.add(null);
        t.lastOk = false;
        t.lastError = friendlyAgentError(r['error']?.toString());
        if (prevOk == true) { t.flashIsUp = false; t.flashUntil = DateTime.now().add(const Duration(seconds: 10)); }
        _log.insert(0, LogLine(LogKind.err, t.host, r['error']?.toString() ?? 'timeout', _clock()));
      }
      if (_log.length > 150) _log.removeLast();
      if (t.samples.length > 90) t.samples.removeAt(0);
    });
    if (_running && t.active) t.timer = Timer(Duration(milliseconds: _interval), () => _tick(t));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = AppTheme(state.isDark);
    final c = theme.c;
    final started = _targets.where((t) => t.active || t.sent > 0).toList();
    final failedCount = started.where((t) => t.lastOk == false).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(children: [
              for (var i = 0; i < _targets.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == _targets.length - 1 ? 0 : 8),
                  child: _TargetField(
                    target: _targets[i],
                    c: c,
                    lang: state.lang,
                    running: _running,
                    isLast: i == _targets.length - 1,
                    onSubmitted: () => _onSubmit(i),
                    onRemove: _targets.length > 1 || _targets[i].host.isNotEmpty ? () => _removeTarget(i) : null,
                    onAdd: i == _targets.length - 1 && !_running ? _addTarget : null,
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(10)),
            height: 52,
            alignment: Alignment.center,
            child: DropdownButton<int>(
              value: _interval,
              dropdownColor: c.bgRise,
              underline: const SizedBox(),
              style: GoogleFonts.spaceMono(color: c.ink, fontSize: 13),
              items: const [500, 1000, 2000, 5000]
                  .map((v) => DropdownMenuItem(value: v, child: Text('${v / 1000}s')))
                  .toList(),
              onChanged: (v) => setState(() => _interval = v ?? 1000),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 52,
            child: PrimaryButton(
              label: _running ? t(state.lang, 'action.stop') : t(state.lang, 'action.start'),
              running: _running,
              onPressed: _running ? _stop : _start,
              c: c,
            ),
          ),
        ]),
        const SizedBox(height: 16),
        StatusLine(
          kind: _running
              ? (failedCount == started.length && started.isNotEmpty ? StatusKind.error : StatusKind.busy)
              : (started.isEmpty ? StatusKind.idle : (failedCount == 0 ? StatusKind.ok : StatusKind.error)),
          text: _running
              ? 'Pinging ${started.length} host${started.length == 1 ? '' : 's'}…${failedCount > 0 ? ' ($failedCount not responding)' : ''}'
              : (started.isEmpty ? '' : (failedCount == 0 ? 'All responding' : '$failedCount of ${started.length} not responding')),
          c: c,
        ),
        const SizedBox(height: 4),
        if (started.isNotEmpty) ...[
          Wrap(spacing: 14, runSpacing: 6, children: [
            for (var i = 0; i < started.length; i++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: _palette[i % _palette.length], shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(started[i].host, style: GoogleFonts.spaceMono(fontSize: 11.5, color: c.inkSoft)),
              ]),
          ]),
          const SizedBox(height: 12),
          SectionCard(
            c: c,
            child: SizedBox(
              height: 170,
              child: _PingChart(targets: started, grid: c.lineSoft, textColor: c.inkGhost, accentInk: c.accentInk),
            ),
          ),
          const SizedBox(height: 16),
          _PingTable(targets: started, c: c),
          const SizedBox(height: 16),
          LogPanel(lines: _log, c: c, title: 'Ping log'),
        ],
        const SizedBox(height: 12),
        Text(
          'ICMP mode — measurements come from the operating system\'s ping command, identical to running it in a terminal. Press Enter after a target to add another one.',
          style: TextStyle(color: c.inkGhost, fontSize: 11, height: 1.5),
        ),
      ]),
    );
  }
}

class _TargetField extends StatelessWidget {
  final _Target target;
  final AppColors c;
  final String lang;
  final bool running, isLast;
  final VoidCallback onSubmitted;
  final VoidCallback? onRemove;
  final VoidCallback? onAdd;
  const _TargetField({
    required this.target, required this.c, required this.lang, required this.running,
    required this.isLast, required this.onSubmitted, required this.onRemove, required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final flashing = target.flashing;
    final flashColor = target.flashIsUp ? c.ok : c.alarm;
    // kalici nokta: su anki durum (yesil=cevap veriyor, kirmizi=vermiyor, gri=henuz baslamadi)
    Color dot = c.inkGhost;
    if (target.lastOk == true) dot = c.ok;
    if (target.lastOk == false) dot = c.alarm;

    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: flashing ? flashColor.withValues(alpha: .22) : c.bgSink,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: flashing ? flashColor : c.line, width: flashing ? 1.4 : 1),
          ),
          child: Row(children: [
            Caption(t(lang, 'field.target'), c),
            const SizedBox(width: 10),
            if (running || target.lastOk != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: target.controller,
                focusNode: target.focus,
                readOnly: running,
                style: GoogleFonts.spaceMono(color: c.ink, fontSize: 15),
                cursorColor: c.accent,
                decoration: InputDecoration(
                  border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  hintText: isLast ? '8.8.8.8 · google.com — Enter or + adds another' : null,
                  hintStyle: TextStyle(color: c.inkGhost),
                ),
                onSubmitted: (_) => onSubmitted(),
              ),
            ),
            if (onRemove != null && !running)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(onTap: onRemove, child: Icon(Icons.close, size: 16, color: c.inkFaint)),
              ),
          ]),
        ),
      ),
      if (onAdd != null) ...[
        const SizedBox(width: 8),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 52, height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.add, size: 18, color: c.inkSoft),
            ),
          ),
        ),
      ],
    ]);
  }
}

class _PingTable extends StatelessWidget {
  final List<_Target> targets;
  final AppColors c;
  const _PingTable({required this.targets, required this.c});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      c: c,
      padding: const EdgeInsets.all(0),
      child: Column(children: [
        for (var i = 0; i < targets.length; i++) ...[
          if (i > 0) Divider(height: 1, color: c.lineSoft),
          _row(targets[i], i),
        ],
      ]),
    );
  }

  Widget _row(_Target t, int i) {
    final loss = t.sent == 0 ? 0.0 : (t.lost / t.sent) * 100;
    Color dot = c.inkGhost;
    if (t.lastOk == true) dot = c.ok;
    if (t.lastOk == false) dot = c.alarm;
    Widget cell(String label, String value, {Color? color}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w600, letterSpacing: 1, color: c.inkGhost)),
            const SizedBox(height: 2),
            Text(value, style: GoogleFonts.spaceMono(fontSize: 12.5, color: color ?? c.inkSoft, fontWeight: FontWeight.w600)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 10), decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: _palette[i % _palette.length], shape: BoxShape.circle)),
        SizedBox(
          width: 160,
          child: Text(t.host, style: GoogleFonts.spaceMono(fontSize: 13, fontWeight: FontWeight.w700, color: c.accent), overflow: TextOverflow.ellipsis),
        ),
        SizedBox(width: 130, child: Text(t.resolvedIp ?? '—', style: GoogleFonts.spaceMono(fontSize: 12, color: c.inkFaint), overflow: TextOverflow.ellipsis)),
        cell('LAST', '${t.last.toStringAsFixed(0)} ms'),
        cell('MIN', '${t.min.toStringAsFixed(0)} ms'),
        cell('AVG', '${t.avg.toStringAsFixed(0)} ms'),
        cell('MAX', '${t.max.toStringAsFixed(0)} ms'),
        cell('JITTER', '${t.jitter.toStringAsFixed(1)} ms'),
        cell('LOSS', '${loss.toStringAsFixed(0)}% · ${t.sent}', color: loss > 0 ? c.alarm : c.ok),
      ]),
    );
  }
}

class _PingChart extends StatelessWidget {
  final List<_Target> targets;
  final Color grid, textColor, accentInk;
  const _PingChart({required this.targets, required this.grid, required this.textColor, required this.accentInk});

  @override
  Widget build(BuildContext context) {
    final allVals = targets.expand((t) => t.samples.whereType<double>()).toList();
    final maxV = allVals.isEmpty ? 50.0 : (allVals.reduce((a, b) => a > b ? a : b) * 1.25 + 4);

    return LayoutBuilder(builder: (context, constraints) {
      final h = constraints.maxHeight;
      final w = constraints.maxWidth - 46;
      return Row(children: [
        SizedBox(
          width: 40, height: h,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (i) {
              final v = maxV * (4 - i) / 4;
              return Text(v.toStringAsFixed(0), style: GoogleFonts.spaceMono(fontSize: 9.5, color: textColor));
            }),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: CustomPaint(
            size: Size(w, h),
            painter: _MultiSparkPainter(targets: targets, grid: grid, maxV: maxV),
          ),
        ),
      ]);
    });
  }
}

class _MultiSparkPainter extends CustomPainter {
  final List<_Target> targets;
  final Color grid;
  final double maxV;
  _MultiSparkPainter({required this.targets, required this.grid, required this.maxV});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()..color = grid..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final y = size.height / 4 * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var ti = 0; ti < targets.length; ti++) {
      final samples = targets[ti].samples;
      if (samples.whereType<double>().isEmpty) continue;
      final color = _palette[ti % _palette.length];
      final path = Path();
      final dx = samples.length <= 1 ? 0.0 : size.width / (samples.length - 1).clamp(1, 1 << 30);
      bool started = false;
      double lastX = 0, lastY = size.height;
      for (var i = 0; i < samples.length; i++) {
        final v = samples[i];
        if (v == null) { started = false; continue; }
        final x = dx * i;
        final y = size.height - (v / maxV) * size.height;
        if (!started) { path.moveTo(x, y); started = true; } else { path.lineTo(x, y); }
        lastX = x; lastY = y;
      }
      canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round);
      canvas.drawCircle(Offset(lastX, lastY), 3.2, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _MultiSparkPainter oldDelegate) => true;
}
