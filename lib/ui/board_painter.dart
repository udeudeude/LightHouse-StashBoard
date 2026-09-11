import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/board_state.dart';
import '../domain/board_underlay.dart';
import '../domain/light_element.dart';
import '../domain/pyramid_geometry.dart';

class BoardPainter extends CustomPainter {
  const BoardPainter({
    required this.state,
    required this.logicalPixelsPerMm,
    required this.geometry,
    this.selectedId,
  });

  final BoardState state;
  final double logicalPixelsPerMm;
  final PyramidGeometryProfile geometry;
  final String? selectedId;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    _paintUnderlay(canvas, size, state.underlay);
    for (final element in state.elements) {
      _paintElement(canvas, element);
    }
  }

  void _paintUnderlay(Canvas canvas, Size size, BoardUnderlay underlay) {
    if (!underlay.isVisible) return;

    final cell = 27.0 * logicalPixelsPerMm;
    final boardWidth = underlay.columns * cell;
    final boardHeight = underlay.rows * cell;
    final left = (size.width - boardWidth) / 2;
    final top = (size.height - boardHeight) / 2;
    final gridPaint = Paint()
      ..color = const Color(0x55FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.7, logicalPixelsPerMm * 0.18);

    if (underlay.isChessLike) {
      final shade = Paint()..color = const Color(0x18FFFFFF);
      for (var row = 0; row < underlay.rows; row += 1) {
        for (var column = 0; column < underlay.columns; column += 1) {
          if ((row + column).isEven) continue;
          canvas.drawRect(
            Rect.fromLTWH(left + column * cell, top + row * cell, cell, cell),
            shade,
          );
        }
      }
    }

    for (var column = 0; column <= underlay.columns; column += 1) {
      final x = left + column * cell;
      canvas.drawLine(Offset(x, top), Offset(x, top + boardHeight), gridPaint);
    }
    for (var row = 0; row <= underlay.rows; row += 1) {
      final y = top + row * cell;
      canvas.drawLine(Offset(left, y), Offset(left + boardWidth, y), gridPaint);
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
      if (element.id == selectedId) {
        canvas.drawRect(
          rect.inflate(3),
          Paint()
            ..color = Colors.white54
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    } else {
      final triangle = Path()
        ..moveTo(0, -flatLength / 2)
        ..lineTo(base / 2, flatLength / 2)
        ..lineTo(-base / 2, flatLength / 2)
        ..close();
      canvas.drawPath(triangle, Paint()..color = Colors.white);
      if (element.id == selectedId) {
        canvas.drawPath(
          triangle,
          Paint()
            ..color = Colors.white54
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(BoardPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.logicalPixelsPerMm != logicalPixelsPerMm ||
      oldDelegate.geometry != geometry ||
      oldDelegate.selectedId != selectedId;
}
