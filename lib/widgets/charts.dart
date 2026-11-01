import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Smooth line chart with a soft filled area, dots, and a value bubble on the last point.
class LineTrendChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;
  final String Function(double) format;

  const LineTrendChart({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: CustomPaint(
        size: Size.infinite,
        painter: _LinePainter(values: values, labels: labels, color: color, format: format),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final Color color;
  final String Function(double) format;

  static const Color _muted = Color(0xFF7A7592);
  static const double _left = 44;
  static const double _bottom = 26;
  static const double _top = 18;
  static const double _right = 14;

  _LinePainter({
    required this.values,
    required this.labels,
    required this.color,
    required this.format,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final chart = Rect.fromLTRB(_left, _top, size.width - _right, size.height - _bottom);
    final maxV = math.max(values.reduce(math.max), 1.0);

    final grid = Paint()
      ..color = _muted.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = chart.top + chart.height * i / 4;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      _label(canvas, _compact(maxV * (4 - i) / 4), Offset(chart.left - 6, y), right: true);
    }

    final pts = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? chart.center.dx
          : chart.left + chart.width * i / (values.length - 1);
      final y = chart.bottom - chart.height * (values[i] / maxV);
      pts.add(Offset(x, y));
      if (i < labels.length) {
        _label(canvas, labels[i], Offset(x, size.height - _bottom / 2));
      }
    }

    if (pts.length > 1) {
      final fill = _curve(pts)
        ..lineTo(pts.last.dx, chart.bottom)
        ..lineTo(pts.first.dx, chart.bottom)
        ..close();
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.0)],
        ).createShader(chart);
      canvas.drawPath(fill, fillPaint);
    }

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(_curve(pts), line);

    final dotFill = Paint()..color = Colors.white;
    final dotRing = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (var i = 0; i < pts.length - 1; i++) {
      canvas.drawCircle(pts[i], 4, dotFill);
      canvas.drawCircle(pts[i], 4, dotRing);
    }

    final last = pts.last;
    canvas.drawCircle(last, 8, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawCircle(last, 5, Paint()..color = color);

    final tip = _tp(format(values.last), const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    ));
    var box = Rect.fromCenter(
      center: Offset(last.dx, last.dy - 28),
      width: tip.width + 18,
      height: tip.height + 10,
    );
    final dx = box.right > size.width ? size.width - box.right : (box.left < 0 ? -box.left : 0.0);
    final dy = box.top < 0 ? -box.top : 0.0;
    box = box.shift(Offset(dx, dy));
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(8)),
      Paint()..color = color,
    );
    tip.paint(canvas, Offset(box.center.dx - tip.width / 2, box.center.dy - tip.height / 2));
  }

  Path _curve(List<Offset> pts) {
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      p.quadraticBezierTo(a.dx, a.dy, mid.dx, mid.dy);
    }
    p.lineTo(pts.last.dx, pts.last.dy);
    return p;
  }

  TextPainter _tp(String text, TextStyle style) => TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();

  void _label(Canvas canvas, String text, Offset anchor, {bool right = false}) {
    final tp = _tp(text, const TextStyle(color: _muted, fontSize: 11));
    final dx = right ? anchor.dx - tp.width : anchor.dx - tp.width / 2;
    tp.paint(canvas, Offset(dx, anchor.dy - tp.height / 2));
  }

  String _compact(double v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}K';
    }
    return v.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.values != values || old.labels != labels || old.color != color;
}

/// Ring split into coloured parts. [fractions] are relative sizes, not percentages.
class SegmentedDonut extends StatelessWidget {
  final List<double> fractions;
  final List<Color> colors;
  final double size;
  final Widget? center;

  const SegmentedDonut({
    super.key,
    required this.fractions,
    required this.colors,
    this.size = 130,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SegmentPainter(fractions: fractions, colors: colors),
        child: center == null ? null : Center(child: center),
      ),
    );
  }
}

class _SegmentPainter extends CustomPainter {
  final List<double> fractions;
  final List<Color> colors;
  static const double _stroke = 22;

  _SegmentPainter({required this.fractions, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);

    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = const Color(0x1A6A3DE8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke,
    );

    final total = fractions.fold<double>(0.0, (s, f) => s + f);
    if (total <= 0) return;

    var start = -math.pi / 2;
    for (var i = 0; i < fractions.length; i++) {
      final sweep = 2 * math.pi * fractions[i] / total;
      if (sweep <= 0) continue;
      final drawn = math.max(0.0, sweep - 0.03);
      canvas.drawArc(
        rect,
        start,
        drawn,
        false,
        Paint()
          ..color = colors[i % colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentPainter old) =>
      old.fractions != fractions || old.colors != colors;
}
