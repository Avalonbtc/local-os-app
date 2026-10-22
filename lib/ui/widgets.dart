import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../data/session.dart';
import '../data/stores.dart';
import '../theme.dart';

/// The signed-in session's services. Read without subscribing: screens listen to the stores
/// they need, so a fleet refresh never rebuilds the whole tree.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.session,
    required this.backend,
    required this.fleet,
    required this.alerts,
    required super.child,
  });
  final SessionController session;
  final Backend backend;
  final FleetStore fleet;
  final AlertsStore alerts;

  static AppScope of(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}

/// Push a page above the shell, carrying the session's services along (routes live in the
/// app-wide navigator, outside the shell's [AppScope]).
Future<T?> push<T>(BuildContext context, Widget page) {
  final s = AppScope.of(context);
  return Navigator.of(context).push<T>(MaterialPageRoute<T>(
    builder: (_) => AppScope(session: s.session, backend: s.backend, fleet: s.fleet, alerts: s.alerts, child: page),
  ));
}

/// Flat card: border, no shadow (shadows and blurs cost an extra compositing pass per frame).
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color, this.borderColor, this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: borderColor ?? C.border),
    );
    return Material(
      color: color ?? C.surface,
      shape: shape,
      clipBehavior: onTap == null ? Clip.none : Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.size = 8});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      );
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, required this.fg, required this.bg});
  final String text;
  final Color fg;
  final Color bg;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 0, 2),
        child: Row(
          children: [
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: C.muted))),
            ?trailing,
          ],
        ),
      );
}

/// Status colours: never colour alone — every state also has a label.
({Color dot, String label, Color fg, Color bg}) rowLook(FleetRow r) {
  if (!r.fresh) {
    return r.state == RigState.localOffline && r.lastSeen != null
        ? (dot: C.bad, label: '离线', fg: C.badText, bg: C.badBg)
        : (dot: C.faint, label: '离线', fg: C.text2, bg: C.greyBg);
  }
  if (r.poolOffline) return (dot: C.pool, label: '矿池离线', fg: C.poolText, bg: C.poolBg);
  if (r.problem) return (dot: C.ok, label: '有问题', fg: C.info, bg: C.infoBg);
  return (dot: C.ok, label: '在线', fg: C.okText, bg: C.okBg);
}

class KeyValue extends StatelessWidget {
  const KeyValue(this.k, this.v, {super.key, this.valueStyle});
  final String k;
  final String v;
  final TextStyle? valueStyle;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 92, child: Text(k, style: const TextStyle(color: C.muted, fontSize: 13))),
            Expanded(
              child: Text(v, textAlign: TextAlign.right, style: valueStyle ?? const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );
}

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.fg = C.poolText, this.bg = const Color(0xFF211A12), this.border = const Color(0xFF5A4220), this.icon = Icons.warning_amber_rounded});
  final String text;
  final Color fg;
  final Color bg;
  final Color border;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Panel(
        color: bg,
        borderColor: border,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: fg, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(color: fg, fontSize: 13, height: 1.45))),
          ],
        ),
      );
}

class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: C.faint, size: 40),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.muted, height: 1.5)),
            ],
          ),
        ),
      );
}

/// Line chart drawn straight to the canvas; the series is already reduced to ≤240 points.
class LineChart extends StatelessWidget {
  const LineChart({super.key, required this.ys, required this.color, this.height = 104, this.fill = true});
  final List<double> ys;
  final Color color;
  final double height;
  final bool fill;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _LinePainter(ys, color, fill)),
        ),
      );
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.ys, this.color, this.fill);
  final List<double> ys;
  final Color color;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = C.divider
      ..strokeWidth = 1;
    for (var k = 1; k < 4; k++) {
      final y = size.height * k / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (ys.length < 2) return;
    var lo = ys.first, hi = ys.first;
    for (final v in ys) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    final top = 6.0, h = size.height - 12;
    final dx = size.width / (ys.length - 1);
    final line = Path();
    for (var i = 0; i < ys.length; i++) {
      final x = i * dx;
      final y = top + h * (1 - (ys[i] - lo) / span);
      i == 0 ? line.moveTo(x, y) : line.lineTo(x, y);
    }
    if (fill) {
      final area = Path.from(line)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.13));
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) => !identical(old.ys, ys) || old.color != color;
}

Future<bool> confirm(BuildContext context, String title, String body, {String action = '确定', bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body, style: const TextStyle(height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消', style: TextStyle(color: C.text2))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: C.bad, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok == true;
}

void toast(BuildContext context, String text, {String? action, VoidCallback? onAction}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(text),
    duration: const Duration(seconds: 4),
    action: action == null ? null : SnackBarAction(label: action, onPressed: onAction ?? () {}),
  ));
}

String errorText(Object e) => e is ApiException ? e.message : '$e';
