import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/board_state.dart';
import '../domain/light_element.dart';
import '../domain/pyramid_geometry.dart';

class BoardPainter extends CustomPainter {
  const BoardPainter({
    required this.state,
    required this.logicalPixelsPerMm,
    required this.geometry,
  });

  final BoardState state;
  final double logicalPixelsPerMm;
  final PyramidGeometryProfile geometry;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    for (final element in state.elements) {
      _paintElement(canvas, element);
    }
  }

  void _paintElement(Canvas canvas, LightElement element) {
    final center = Offset(
      element.position.xMm * logicalPixelsPerMm,
      element.position.yMm * logicalPixelsPerMm,
    );
    final base = geometry.baseMm(element.size) * logicalPixelsPerMm;
    final flatLength = geometry.flatLengthMm(element.size) * logicalPixelsPerMm;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(element.headingDegrees * math.pi / 180);

    if (element.pose == PyramidPose.upright) {
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: base,
        height: base,
      );
      if (element.illumination == IlluminationPattern.full) {
        canvas.drawRect(rect, Paint()..color = Colors.white);
      } else {
        final band = geometry.wallBandMm * logicalPixelsPerMm;
        final inner = rect.deflate(band.clamp(0, base / 2).toDouble());
        final ring = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(rect)
          ..addRect(inner);
        canvas.drawPath(ring, Paint()..color = Colors.white);
      }
    } else {
      final triangle = Path()
        ..moveTo(0, -flatLength / 2)
        ..lineTo(base / 2, flatLength / 2)
        ..lineTo(-base / 2, flatLength / 2)
        ..close();
      canvas.drawPath(triangle, Paint()..color = Colors.white);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(BoardPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.logicalPixelsPerMm != logicalPixelsPerMm ||
      oldDelegate.geometry != geometry;
}
