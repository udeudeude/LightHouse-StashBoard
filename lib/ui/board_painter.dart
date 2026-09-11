import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/board_state.dart';
import '../domain/board_underlay.dart';
import '../domain/light_element.dart';
import '../domain/physical_point.dart';
import '../domain/pyramid_geometry.dart';

class BoardPainter extends CustomPainter {
  const BoardPainter({
    required this.state,
    required this.logicalPixelsPerMm,
    required this.geometry,
    this.selectedId,
    this.elementOpacities = const {},
    this.burstCenter,
    this.burstProgress,
  });

  final BoardState state;
  final double logicalPixelsPerMm;
  final PyramidGeometryProfile geometry;
  final String? selectedId;
  final Map<String, double> elementOpacities;
  final PhysicalPoint? burstCenter;
  final double? burstProgress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    _paintUnderlay(canvas, size, state.underlay);
    for (final element in state.elements) {
      _paintElement(canvas, element, elementOpacities[element.id] ?? 1);
    }
    _paintBurst(canvas, size);
  }

  Paint _linePaint([double alpha = 0.34]) => Paint()
    ..color = Color.fromRGBO(255, 255, 255, alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.7, logicalPixelsPerMm * 0.18);

  void _paintUnderlay(Canvas canvas, Size size, BoardUnderlay underlay) {
    if (!underlay.isVisible) return;
    switch (underlay) {
      case BoardUnderlay.none:
        return;
      case BoardUnderlay.wheel:
        _paintWheel(canvas, size);
        return;
      case BoardUnderlay.looneyLudo4:
        _paintLudoFour(canvas, size);
        return;
      case BoardUnderlay.launchpad23:
        _paintLaunchpad23(canvas, size);
        return;
      default:
        _paintRectGrid(canvas, size, underlay);
        return;
    }
  }

  void _paintRectGrid(Canvas canvas, Size size, BoardUnderlay underlay) {
    final cell = BoardUnderlay.cellMm * logicalPixelsPerMm;
    final boardWidth = underlay.columns * cell;
    final boardHeight = underlay.rows * cell;
    final left = (size.width - boardWidth) / 2;
    final top = (size.height - boardHeight) / 2;
    final gridPaint = _linePaint();

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

  void _paintLaunchpad23(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = BoardUnderlay.coasterMm * logicalPixelsPerMm;
    final cell = BoardUnderlay.cellMm * logicalPixelsPerMm;
    final gridSize = cell * 3;
    final left = center.dx - gridSize / 2;
    final top = center.dy - gridSize / 2;
    final paint = _linePaint();

    canvas.drawRect(
      Rect.fromCenter(center: center, width: outer, height: outer),
      _linePaint(0.24),
    );
    for (var i = 0; i <= 3; i += 1) {
      final offset = i * cell;
      canvas.drawLine(
        Offset(left + offset, top),
        Offset(left + offset, top + gridSize),
        paint,
      );
      canvas.drawLine(
        Offset(left, top + offset),
        Offset(left + gridSize, top + offset),
        paint,
      );
    }

    final marker = Paint()
      ..color = const Color(0x66FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, logicalPixelsPerMm * 0.22);
    final markerRadius = cell * 0.13;
    for (final position in <Offset>[
      Offset(left + cell / 2, top + cell / 2),
      Offset(left + cell * 2.5, top + cell / 2),
      Offset(left + cell / 2, top + cell * 2.5),
      Offset(left + cell * 2.5, top + cell * 2.5),
    ]) {
      canvas.drawCircle(position, markerRadius, marker);
    }
    canvas.drawCircle(center, markerRadius * 1.15, marker);
    canvas.drawCircle(center, markerRadius * 0.45, marker);
  }

  void _paintLudoFour(Canvas canvas, Size size) {
    final boardCenter = Offset(size.width / 2, size.height / 2);
    final tile = BoardUnderlay.coasterMm * logicalPixelsPerMm;
    for (var row = 0; row < 2; row += 1) {
      for (var column = 0; column < 2; column += 1) {
        final center = Offset(
          boardCenter.dx + (column == 0 ? -tile / 2 : tile / 2),
          boardCenter.dy + (row == 0 ? -tile / 2 : tile / 2),
        );
        // The reference tile's dot is at its upper-left corner. Rotate each
        // tile so the four dots meet at the center of the starting layout.
        final quarterTurns = switch ((row, column)) {
          (0, 0) => 2,
          (0, 1) => 3,
          (1, 0) => 1,
          _ => 0,
        };
        _paintLudoTile(canvas, center, quarterTurns: quarterTurns);
      }
    }
  }

  void _paintLudoTile(
    Canvas canvas,
    Offset center, {
    required int quarterTurns,
  }) {
    final tile = BoardUnderlay.coasterMm * logicalPixelsPerMm;
    final cell = BoardUnderlay.cellMm * logicalPixelsPerMm;
    final gridSize = 3 * cell;
    final left = -gridSize / 2;
    final top = -gridSize / 2;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(quarterTurns * math.pi / 2);

    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: tile, height: tile),
      _linePaint(0.22),
    );

    final paint = _linePaint(0.3);
    for (var i = 0; i <= 3; i += 1) {
      final offset = i * cell;
      canvas.drawLine(
        Offset(left + offset, top),
        Offset(left + offset, top + gridSize),
        paint,
      );
      canvas.drawLine(
        Offset(left, top + offset),
        Offset(left + gridSize, top + offset),
        paint,
      );
    }

    // Direction topology from the Looney Ludo board. The art is intentionally
    // reduced to small line arrowheads so this remains a functional underlay,
    // not a reproduction of the printed board artwork.
    const arrows = <List<int>>[
      [1 | 2 | 4, 8 | 2 | 4, 8 | 1 | 2],
      [8 | 1 | 2, 1 | 2 | 4, 1 | 2 | 4],
      [8 | 2 | 4, 8 | 1 | 2 | 4, 8 | 1 | 2],
    ];
    const up = 1;
    const right = 2;
    const down = 4;
    const leftDirection = 8;
    for (var row = 0; row < 3; row += 1) {
      for (var column = 0; column < 3; column += 1) {
        final mask = arrows[row][column];
        final cellCenter = Offset(
          left + (column + 0.5) * cell,
          top + (row + 0.5) * cell,
        );
        if ((mask & up) != 0) {
          _paintArrowhead(canvas, cellCenter, cell, -math.pi / 2);
        }
        if ((mask & right) != 0) {
          _paintArrowhead(canvas, cellCenter, cell, 0);
        }
        if ((mask & down) != 0) {
          _paintArrowhead(canvas, cellCenter, cell, math.pi / 2);
        }
        if ((mask & leftDirection) != 0) {
          _paintArrowhead(canvas, cellCenter, cell, math.pi);
        }
      }
    }

    final homePaint = _linePaint(0.46);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset.zero,
        width: cell * 0.58,
        height: cell * 0.58,
      ),
      homePaint,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset.zero,
        width: cell * 0.34,
        height: cell * 0.34,
      ),
      homePaint,
    );
    canvas.drawCircle(Offset.zero, cell * 0.12, homePaint);

    final dot = Offset(-tile / 2 + 5, -tile / 2 + 5);
    canvas.drawCircle(
      dot,
      math.max(1.4, logicalPixelsPerMm * 1.1),
      Paint()..color = const Color(0x66FFFFFF),
    );
    canvas.restore();
  }

  void _paintArrowhead(
    Canvas canvas,
    Offset cellCenter,
    double cell,
    double angle,
  ) {
    final edge = cell * 0.43;
    final tip = Offset(
      cellCenter.dx + edge * math.cos(angle),
      cellCenter.dy + edge * math.sin(angle),
    );
    final inward = Offset(
      cellCenter.dx + cell * 0.26 * math.cos(angle),
      cellCenter.dy + cell * 0.26 * math.sin(angle),
    );
    final normal = Offset(-math.sin(angle), math.cos(angle));
    final halfWidth = cell * 0.07;
    final arrow = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        inward.dx + normal.dx * halfWidth,
        inward.dy + normal.dy * halfWidth,
      )
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        inward.dx - normal.dx * halfWidth,
        inward.dy - normal.dy * halfWidth,
      );
    canvas.drawPath(arrow, _linePaint(0.52));
  }

  void _paintWheel(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = BoardUnderlay.wheelOuterRadiusMm * logicalPixelsPerMm;
    final playableRadius =
        BoardUnderlay.wheelPlayableRadiusMm * logicalPixelsPerMm;
    const count = 10;
    final step = 2 * math.pi / count;

    Offset point(double radius, int index) {
      final angle = -math.pi / 2 + index * step;
      return Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
    }

    final outer = Path();
    for (var i = 0; i < count; i += 1) {
      final p = point(outerRadius, i);
      if (i == 0) {
        outer.moveTo(p.dx, p.dy);
      } else {
        outer.lineTo(p.dx, p.dy);
      }
    }
    outer.close();
    canvas.drawPath(outer, _linePaint(0.24));

    final paint = _linePaint(0.38);
    final vertices = [
      for (var i = 0; i < count; i += 1) point(playableRadius, i),
    ];
    for (var i = 0; i < count; i += 1) {
      final a = vertices[i];
      final b = vertices[(i + 1) % count];
      final ca = Offset((center.dx + a.dx) / 2, (center.dy + a.dy) / 2);
      final cb = Offset((center.dx + b.dx) / 2, (center.dy + b.dy) / 2);
      final ab = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

      canvas.drawLine(center, a, paint);
      canvas.drawLine(a, b, paint);
      canvas.drawLine(ca, cb, paint);
      canvas.drawLine(ca, ab, paint);
      canvas.drawLine(cb, ab, paint);
    }
  }

  void _paintElement(Canvas canvas, LightElement element, double opacity) {
    if (opacity <= 0) return;
    final alpha = opacity.clamp(0.0, 1.0).toDouble();
    final white = Color.fromRGBO(255, 255, 255, alpha);
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
        canvas.drawRect(rect, Paint()..color = white);
      } else {
        final band = geometry.wallBandMm * logicalPixelsPerMm;
        final inner = rect.deflate(band.clamp(0, base / 2).toDouble());
        final ring = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(rect)
          ..addRect(inner);
        canvas.drawPath(ring, Paint()..color = white);
      }
      if (element.id == selectedId && alpha > 0.15) {
        canvas.drawRect(
          rect.inflate(3),
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, 0.34 * alpha)
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
      canvas.drawPath(triangle, Paint()..color = white);
      if (element.id == selectedId && alpha > 0.15) {
        canvas.drawPath(
          triangle,
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, 0.34 * alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    canvas.restore();
  }

  void _paintBurst(Canvas canvas, Size size) {
    final centerMm = burstCenter;
    final progress = burstProgress;
    if (centerMm == null || progress == null || progress < 0 || progress > 1) {
      return;
    }
    final center = Offset(
      centerMm.xMm * logicalPixelsPerMm,
      centerMm.yMm * logicalPixelsPerMm,
    );
    final farthest = math.sqrt(
      size.width * size.width + size.height * size.height,
    );
    final radius = farthest * (0.04 + progress * 0.96);
    final alpha = (1 - progress).clamp(0.0, 1.0).toDouble();
    final paint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, 0.78 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, 4 * (1 - progress));
    canvas.drawCircle(center, radius, paint);

    const rays = 20;
    for (var i = 0; i < rays; i += 1) {
      final angle = 2 * math.pi * i / rays;
      final inner = radius * 0.7;
      final outer = radius * (0.94 + 0.12 * (i.isEven ? 1 : 0));
      canvas.drawLine(
        Offset(
          center.dx + inner * math.cos(angle),
          center.dy + inner * math.sin(angle),
        ),
        Offset(
          center.dx + outer * math.cos(angle),
          center.dy + outer * math.sin(angle),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(BoardPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.logicalPixelsPerMm != logicalPixelsPerMm ||
      oldDelegate.geometry != geometry ||
      oldDelegate.selectedId != selectedId ||
      oldDelegate.elementOpacities != elementOpacities ||
      oldDelegate.burstCenter != burstCenter ||
      oldDelegate.burstProgress != burstProgress;
}
