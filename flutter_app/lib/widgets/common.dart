import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

/// Kucuk buyuk harf etiket (field-key / cell-key stili).
class Caption extends StatelessWidget {
  final String text;
  final AppColors c;
  final Color? color;
  const Caption(this.text, this.c, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 9.5, fontWeight: FontWeight.w600, letterSpacing: 1.4,
          color: color ?? c.inkFaint,
        ),
      );
}

class SectionCard extends StatelessWidget {
  final Widget child;
  final AppColors c;
  final EdgeInsets padding;
  const SectionCard({super.key, required this.child, required this.c, this.padding = const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: c.bgRise, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.lineSoft),
        ),
        child: child,
      );
}

class LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final AppColors c;
  final bool obscure;
  final ValueChanged<String>? onSubmitted;
  final void Function()? onChanged;
  const LabeledField({
    super.key, required this.label, required this.controller, required this.c,
    this.hint, this.obscure = false, this.onSubmitted, this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: c.bgSink, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
        child: Row(children: [
          Caption(label, c),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              style: GoogleFonts.spaceMono(color: c.ink, fontSize: 15),
              cursorColor: c.accent,
              decoration: InputDecoration(border: InputBorder.none, hintText: hint, hintStyle: TextStyle(color: c.inkGhost), isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 16)),
              onSubmitted: onSubmitted,
              onChanged: onChanged == null ? null : (_) => onChanged!(),
            ),
          ),
        ]),
      );
}

/// Basinca kucu(l)up birakinca geri donen sarmalayici - "tikladigimi hissettim"
/// hissi icin. Mouse hover'da da hafif isik degisimi verir.
typedef _PressBuilder = Widget Function(BuildContext context, bool hover, bool down);

/// Fare uzerine gelince (hover) VE basinca (down) ayri ayri tepki verebilen
/// sarmalayici - "tikladigimi/uzerinde oldugumu hissediyorum" icin.
class _Pressable extends StatefulWidget {
  final _PressBuilder builder;
  final VoidCallback? onTap;
  const _Pressable({required this.builder, required this.onTap});
  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false, _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
          onTapUp: widget.onTap == null ? null : (_) => setState(() => _down = false),
          onTapCancel: widget.onTap == null ? null : () => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _down ? 0.965 : (_hover && widget.onTap != null ? 1.02 : 1.0),
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: widget.onTap == null ? 0.5 : 1.0,
              duration: const Duration(milliseconds: 120),
              child: widget.builder(context, _hover, _down),
            ),
          ),
        ),
      );
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppColors c;
  final bool running;
  const PrimaryButton({super.key, required this.label, required this.onPressed, required this.c, this.running = false});
  @override
  Widget build(BuildContext context) => _Pressable(
        onTap: onPressed,
        builder: (context, hover, down) {
          final base = running ? const Color(0xFFC4402A) : c.accent;
          final bg = onPressed == null ? c.inkGhost : (hover ? Color.lerp(base, Colors.white, .12)! : base);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 26),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              boxShadow: onPressed == null
                  ? null
                  : [BoxShadow(color: base.withValues(alpha: hover ? .5 : .3), blurRadius: hover ? 22 : 14, offset: Offset(0, hover ? 6 : 4))],
            ),
            child: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w700, letterSpacing: .2, color: c.accentInk)),
          );
        },
      );
}

class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppColors c;
  final Widget? icon;
  const GhostButton({super.key, required this.label, required this.onPressed, required this.c, this.icon});
  @override
  Widget build(BuildContext context) => _Pressable(
        onTap: onPressed,
        builder: (context, hover, down) => AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: hover ? c.fillHover : Colors.transparent,
            border: Border.all(color: hover ? c.lineStrong : c.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[icon!, const SizedBox(width: 6)],
            Text(label, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: hover ? c.ink : c.inkSoft)),
          ]),
        ),
      );
}

class StatCell extends StatelessWidget {
  final String label, value;
  final AppColors c;
  final Color? valueColor;
  const StatCell(this.label, this.value, this.c, {super.key, this.valueColor});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.bgRise, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.lineSoft)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Caption(label, c),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.spaceMono(fontSize: 19, color: valueColor ?? c.ink, fontWeight: FontWeight.w700)),
        ]),
      );
}

enum LogKind { sys, ok, err, warn }

class LogLine {
  final LogKind kind;
  final String msg, val, time;
  LogLine(this.kind, this.msg, this.val, this.time);
}

class LogPanel extends StatelessWidget {
  final List<LogLine> lines;
  final AppColors c;
  final String title;
  const LogPanel({super.key, required this.lines, required this.c, this.title = 'Log'});
  Color _dot(LogKind k) => switch (k) { LogKind.ok => c.ok, LogKind.err => c.alarm, LogKind.warn => c.warn, _ => c.inkGhost };
  @override
  Widget build(BuildContext context) => SectionCard(
        c: c,
        padding: const EdgeInsets.all(0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Caption(title, c),
          ),
          Divider(height: 1, color: c.lineSoft),
          SizedBox(
            height: 170,
            child: lines.isEmpty
                ? Center(child: Text('—', style: TextStyle(color: c.inkGhost)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: lines.length,
                    itemBuilder: (ctx, i) {
                      final l = lines[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                        child: Row(children: [
                          Container(width: 6, height: 6, decoration: BoxDecoration(color: _dot(l.kind), shape: BoxShape.circle)),
                          const SizedBox(width: 10),
                          SizedBox(width: 60, child: Text(l.time, style: GoogleFonts.spaceMono(fontSize: 10.5, color: c.inkGhost))),
                          Expanded(child: Text(l.msg, style: GoogleFonts.inter(fontSize: 12, color: c.inkSoft), overflow: TextOverflow.ellipsis)),
                          Text(l.val, style: GoogleFonts.spaceMono(fontSize: 11, color: c.inkFaint)),
                        ]),
                      );
                    },
                  ),
          ),
        ]),
      );
}

class ResultRow {
  final List<String> cells;
  ResultRow(this.cells);
}

class ResultTable extends StatelessWidget {
  final String title;
  final List<ResultRow> rows;
  final AppColors c;
  final VoidCallback? onClear;
  const ResultTable({super.key, required this.title, required this.rows, required this.c, this.onClear});
  @override
  Widget build(BuildContext context) => SectionCard(
        c: c,
        padding: const EdgeInsets.all(0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
            child: Row(children: [
              Expanded(child: Caption(title, c)),
              if (onClear != null) TextButton(onPressed: onClear, child: Text('Clear', style: TextStyle(color: c.inkFaint, fontSize: 11))),
            ]),
          ),
          Divider(height: 1, color: c.lineSoft),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: rows.isEmpty
                ? Padding(padding: const EdgeInsets.all(24), child: Text('—', style: TextStyle(color: c.inkGhost)))
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: rows.length,
                    itemBuilder: (ctx, i) => Container(
                      color: i.isOdd ? c.fillFaint : null,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(children: [
                        for (var j = 0; j < rows[i].cells.length; j++)
                          Expanded(
                            flex: j == 0 ? 3 : 2,
                            child: Text(rows[i].cells[j],
                                style: GoogleFonts.spaceMono(fontSize: 12, color: j == 0 ? c.accent : c.inkSoft, fontWeight: j == 0 ? FontWeight.w700 : FontWeight.w400),
                                overflow: TextOverflow.ellipsis),
                          ),
                      ]),
                    ),
                  ),
          ),
        ]),
      );
}
