import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Circular progress ring with any widget in the middle.
/// [value] is between 0 and 1.
class DonutChart extends StatelessWidget {
  final double value;
  final double size;
  final Color color;
  final Color track;
  final Widget? center;

  const DonutChart({
    super.key,
    required this.value,
    required this.color,
    required this.track,
    this.size = 120,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(value: value.clamp(0.0, 1.0).toDouble(), color: color, track: track),
        child: center == null ? null : Center(child: center),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;
  static const double _stroke = 14;

  _DonutPainter({required this.value, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, trackPaint);

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    if (value > 0) {
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value, false, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.value != value || old.color != color || old.track != track;
}
