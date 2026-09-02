import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/i18n.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class PingScreen extends StatefulWidget {
  const PingScreen({super.key});
  @override
  State<PingScreen> createState() => _PingScreenState();
}

class _PingScreenState extends State<PingScreen> {
  final _host = TextEditingController();
  final List<double?> _samples = [];
  final List<LogLine> _log = [];
  bool _running = false;
  int _sent = 0, _lost = 0, _lastTtl = 0;
  double _last = 0, _min = 0, _max = 0, _avg = 0, _jitter = 0;
  int _interval = 1000;
  Timer? _timer;
  String? _resolvedIp, _ptr;
  DateTime? _started;

  @override
  void dispose() {
    _timer?.cancel();
    _host.dispose();
    super.dispose();
  }

  String _clock() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:${n.second.toString().padLeft(2, '0')}';
  }

  Future<void> _start() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    final state = context.read<AppState>();
    setState(() {
      _running = true;
      _samples.clear(); _log.clear();
      _sent = 0; _lost = 0; _last = 0; _min = 0; _max = 0; _avg = 0; _jitter = 0;
      _resolvedIp = null; _ptr = null; _started = DateTime.now();
    });
    final res = await state.agent.get('/api/resolve', {'host': host});
    if (mounted && res['ok'] == true) {
      setState(() {
        final ips = (res['ips'] as List?) ?? [];
        _resolvedIp = ips.isNotEmpty ? ips.first.toString() : null;
        _ptr = res['ptr']?.toString();
      });
    }
    _tick();
  }

  void _stop() {
    _timer?.cancel();
    setState(() => _running = false);
  }

  Future<void> _tick() async {
    if (!_running) return;
    final state = context.read<AppState>();
    final host = _host.text.trim();
    _sent++;
    final r = await state.agent.get('/api/ping', {'host': host, 'timeout': '2000'});
    if (!mounted) return;
    setState(() {
      if (r['ok'] == true) {
        final ms = (r['ms'] as num).toDouble();
        _samples.add(ms);
        _last = ms;
        if (r['ttl'] != null) _lastTtl = (r['ttl'] as num).toInt();
        final vals = _samples.whereType<double>().toList();
        _min = vals.reduce((a, b) => a < b ? a : b);
        _max = vals.reduce((a, b) => a > b ? a : b);
        _avg = vals.reduce((a, b) => a + b) / vals.length;
        if (vals.length > 1) {
          var sum = 0.0;
          for (var i = 1; i < vals.length; i++) {
            sum += (vals[i] - vals[i - 1]).abs();
          }
          _jitter = sum / (vals.length - 1);
        }
        _log.insert(0, LogLine(LogKind.ok, '$host responded', '${ms.toStringAsFixed(0)} ms · TTL $_lastTtl', _clock()));
      } else {
        _lost++;
        _samples.add(null);
        _log.insert(0, LogLine(LogKind.err, host, r['error']?.toString() ?? 'timeout', _clock()));
      }
      if (_log.length > 80) _log.removeLast();
      if (_samples.length > 90) _samples.removeAt(0);
    });
    if (_running) _timer = Timer(Duration(milliseconds: _interval), _tick);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = AppTheme(state.isDark);
    final c = theme.c;
    final loss = _sent == 0 ? 0.0 : (_lost / _sent) * 100;
    final startedStr = _started == null ? '—' : '${_started!.hour.toString().padLeft(2, '0')}:${_started!.minute.toString().padLeft(2, '0')}:${_started!.second.toString().padLeft(2, '0')}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: LabeledField(
              label: t(state.lang, 'field.target'), controller: _host, c: c,
              hint: '8.8.8.8 · google.com', onSubmitted: (_) => _running ? _stop() : _start(),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(10)),
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
          PrimaryButton(
            label: _running ? t(state.lang, 'action.stop') : t(state.lang, 'action.start'),
            running: _running,
            onPressed: _running ? _stop : _start,
            c: c,
          ),
        ]),
        const SizedBox(height: 20),
        if (_started != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: GridView.count(
              crossAxisCount: 4, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 3.0,
              children: [
                StatCell('Target', _host.text.trim(), c),
                StatCell('Resolved IP', _resolvedIp ?? '—', c),
                StatCell('Reverse (PTR)', _ptr ?? '—', c),
                StatCell('Started', startedStr, c),
              ],
            ),
          ),
        SectionCard(
          c: c,
          child: SizedBox(
            height: 160,
            child: _PingChart(samples: _samples, color: c.accent, grid: c.lineSoft, textColor: c.inkGhost, bubbleBg: c.accent, bubbleFg: c.accentInk),
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.5,
          children: [
            StatCell('Last', '${_last.toStringAsFixed(0)} ms', c),
            StatCell('Min', '${_min.toStringAsFixed(0)} ms', c),
            StatCell('Avg', '${_avg.toStringAsFixed(0)} ms', c),
            StatCell('Max', '${_max.toStringAsFixed(0)} ms', c),
            StatCell('Jitter', '${_jitter.toStringAsFixed(1)} ms', c),
            StatCell('Loss', '${loss.toStringAsFixed(0)}% · $_sent sent', c, valueColor: loss > 0 ? c.alarm : c.ok),
          ],
        ),
        const SizedBox(height: 16),
        LogPanel(lines: _log, c: c, title: 'Ping log'),
        const SizedBox(height: 12),
        Text(
          'ICMP mode — measurements come from the operating system\'s ping command, identical to running it in a terminal. Name resolution uses the system resolver.',
          style: TextStyle(color: c.inkGhost, fontSize: 11, height: 1.5),
        ),
      ]),
    );
  }
}

class _PingChart extends StatelessWidget {
  final List<double?> samples;
  final Color color, grid, textColor, bubbleBg, bubbleFg;
  const _PingChart({required this.samples, required this.color, required this.grid, required this.textColor, required this.bubbleBg, required this.bubbleFg});

  @override
  Widget build(BuildContext context) {
    final vals = samples.whereType<double>().toList();
    final maxV = vals.isEmpty ? 50.0 : (vals.reduce((a, b) => a > b ? a : b) * 1.25 + 4);
    final last = samples.isNotEmpty ? samples.last : null;

    return LayoutBuilder(builder: (context, constraints) {
      final h = constraints.maxHeight;
      final w = constraints.maxWidth - 46;
      final bubbleY = last == null ? null : (h - (last / maxV) * h).clamp(10.0, h - 20.0);
      return Stack(children: [
        Row(children: [
          SizedBox(
            width: 40,
            height: h,
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
              painter: _SparkPainter(samples, color, grid, maxV),
            ),
          ),
        ]),
        if (bubbleY != null && vals.isNotEmpty)
          Positioned(
            right: 0,
            top: bubbleY - 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: bubbleBg, borderRadius: BorderRadius.circular(6)),
              child: Text('${last!.toStringAsFixed(0)} ms', style: GoogleFonts.spaceMono(fontSize: 10.5, fontWeight: FontWeight.w700, color: bubbleFg)),
            ),
          ),
      ]);
    });
  }
}

class _SparkPainter extends CustomPainter {
  final List<double?> samples;
  final Color color, grid;
  final double maxV;
  _SparkPainter(this.samples, this.color, this.grid, this.maxV);
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()..color = grid..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final y = size.height / 4 * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (samples.whereType<double>().isEmpty) return;
    final path = Path();
    final fill = Path();
    final dx = samples.length <= 1 ? 0.0 : size.width / (samples.length - 1).clamp(1, 1 << 30);
    bool started = false;
    double lastX = 0, lastY = size.height;
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i];
      if (v == null) { started = false; continue; }
      final x = dx * i;
      final y = size.height - (v / maxV) * size.height;
      if (!started) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
      lastX = x; lastY = y;
    }
    fill.lineTo(lastX, size.height);
    fill.close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: .08)..style = PaintingStyle.fill);
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.2..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round);
    canvas.drawCircle(Offset(lastX, lastY), 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) => true;
}
