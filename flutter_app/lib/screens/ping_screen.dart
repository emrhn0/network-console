import 'dart:async';
import 'package:flutter/material.dart';
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
  int _sent = 0, _lost = 0;
  double _last = 0, _min = 0, _max = 0, _avg = 0;
  int _interval = 1000;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _host.dispose();
    super.dispose();
  }

  String _clock() => TimeOfDay.now().format(context);

  void _start() {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    setState(() {
      _running = true;
      _samples.clear();
      _sent = 0; _lost = 0; _last = 0; _min = 0; _max = 0; _avg = 0;
    });
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
        _min = _samples.whereType<double>().reduce((a, b) => a < b ? a : b);
        _max = _samples.whereType<double>().reduce((a, b) => a > b ? a : b);
        final vals = _samples.whereType<double>().toList();
        _avg = vals.reduce((a, b) => a + b) / vals.length;
        _log.insert(0, LogLine(LogKind.ok, host, '${ms.toStringAsFixed(1)} ms', _clock()));
      } else {
        _lost++;
        _samples.add(null);
        _log.insert(0, LogLine(LogKind.err, host, r['error']?.toString() ?? 'timeout', _clock()));
      }
      if (_log.length > 60) _log.removeLast();
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
          DropdownButton<int>(
            value: _interval,
            dropdownColor: c.bgRise,
            underline: const SizedBox(),
            items: const [500, 1000, 2000, 5000]
                .map((v) => DropdownMenuItem(value: v, child: Text('${v / 1000}s')))
                .toList(),
            onChanged: (v) => setState(() => _interval = v ?? 1000),
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
        SectionCard(
          c: c,
          child: SizedBox(
            height: 140,
            child: CustomPaint(
              size: Size.infinite,
              painter: _SparkPainter(_samples, c.accent, c.lineSoft),
            ),
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.9,
          children: [
            StatCell('Last', '${_last.toStringAsFixed(1)} ms', c),
            StatCell('Min', '${_min.toStringAsFixed(1)} ms', c),
            StatCell('Avg', '${_avg.toStringAsFixed(1)} ms', c),
            StatCell('Max', '${_max.toStringAsFixed(1)} ms', c),
            StatCell('Sent', '$_sent', c),
            StatCell('Lost', '$_lost', c),
            StatCell('Loss', '${loss.toStringAsFixed(0)}%', c, valueColor: loss > 0 ? c.alarm : c.ok),
          ],
        ),
        const SizedBox(height: 16),
        LogPanel(lines: _log, c: c, title: 'Ping log'),
      ]),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double?> samples;
  final Color color, grid;
  _SparkPainter(this.samples, this.color, this.grid);
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()..color = grid..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height / 4 * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final vals = samples.whereType<double>().toList();
    if (vals.isEmpty) return;
    final maxV = vals.reduce((a, b) => a > b ? a : b) * 1.15 + 1;
    final path = Path();
    final dx = samples.length <= 1 ? 0.0 : size.width / (samples.length - 1);
    bool started = false;
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i];
      if (v == null) { started = false; continue; }
      final x = dx * i;
      final y = size.height - (v / maxV) * size.height;
      if (!started) { path.moveTo(x, y); started = true; } else { path.lineTo(x, y); }
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) => true;
}
