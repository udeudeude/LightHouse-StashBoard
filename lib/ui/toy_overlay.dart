import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/convex_geometry.dart';
import '../domain/light_element.dart';
import '../domain/physical_point.dart';
import '../domain/pyramid_geometry.dart';

class ToyTarget {
  const ToyTarget({
    required this.position,
    required this.size,
    required this.pose,
    this.headingDegrees = 0,
  });

  final PhysicalPoint position;
  final PyramidSize size;
  final PyramidPose pose;
  final double headingDegrees;
}

class ToyOverlayPainter extends CustomPainter {
  const ToyOverlayPainter({
    required this.logicalPixelsPerMm,
    required this.geometry,
    required this.elements,
    required this.raceProgress,
    required this.territoryMode,
    required this.ghostTrails,
    required this.ghostTrailsVisible,
    required this.eventZoneCenter,
    required this.eventZoneRadiusMm,
    required this.targets,
    required this.overlayMode,
    required this.turnTimerProgress,
    required this.scenarioLabel,
  });

  final double logicalPixelsPerMm;
  final PyramidGeometryProfile geometry;
  final List<LightElement> elements;
  final Map<String, double> raceProgress;
  final int territoryMode;
  final Map<String, List<PhysicalPoint>> ghostTrails;
  final bool ghostTrailsVisible;
  final PhysicalPoint? eventZoneCenter;
  final double? eventZoneRadiusMm;
  final List<ToyTarget> targets;
  final int overlayMode;
  final double? turnTimerProgress;
  final String? scenarioLabel;

  Offset _px(PhysicalPoint point) =>
      Offset(point.xMm * logicalPixelsPerMm, point.yMm * logicalPixelsPerMm);

  @override
  void paint(Canvas canvas, Size size) {
    _paintTerritory(canvas, size);
    _paintAugmentedOverlay(canvas, size);
    _paintGhostTrails(canvas);
    _paintEventZone(canvas);
    _paintTargets(canvas);
    _paintRace(canvas);
    _paintTurnTimer(canvas, size);
    _paintScenarioLabel(canvas, size);
  }

  void _paintTerritory(Canvas canvas, Size size) {
    if (territoryMode <= 0) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.24)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    if (territoryMode == 1) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        paint,
      );
      return;
    }

    if (territoryMode == 2) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
      return;
    }

    for (var column = 1; column < 3; column += 1) {
      final x = size.width * column / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  void _paintAugmentedOverlay(Canvas canvas, Size size) {
    if (overlayMode <= 0) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final center = Offset(size.width / 2, size.height / 2);

    if (overlayMode == 1) {
      canvas.drawLine(
        Offset(center.dx, 0),
        Offset(center.dx, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, center.dy),
        Offset(size.width, center.dy),
        paint,
      );
      final radius = math.min(size.width, size.height) * 0.22;
      canvas.drawCircle(center, radius, paint);
      canvas.drawCircle(center, radius * 2, paint);
      return;
    }

    if (overlayMode == 2) {
      for (var i = 1; i < 3; i += 1) {
        final x = size.width * i / 3;
        final y = size.height * i / 3;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
      return;
    }

    const spacing = 28.0;
    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.18);
    for (double y = spacing; y < size.height; y += spacing) {
      for (double x = spacing; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }
  }

  void _paintGhostTrails(Canvas canvas) {
    if (!ghostTrailsVisible) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.24)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final points in ghostTrails.values) {
      if (points.length < 2) continue;
      final path = Path()..moveTo(_px(points.first).dx, _px(points.first).dy);
      for (final point in points.skip(1)) {
        final offset = _px(point);
        path.lineTo(offset.dx, offset.dy);
      }
      canvas.drawPath(path, paint);
      for (var i = 0; i < points.length; i += 3) {
        canvas.drawCircle(_px(points[i]), 1.7, paint);
      }
    }
  }

  void _paintEventZone(Canvas canvas) {
    final center = eventZoneCenter;
    final radiusMm = eventZoneRadiusMm;
    if (center == null || radiusMm == null) return;
    final radiusPx = radiusMm * logicalPixelsPerMm;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.58)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final faint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(_px(center), radiusPx, faint);
    canvas.drawCircle(_px(center), radiusPx, paint);
    canvas.drawCircle(_px(center), 3.5, paint);
  }

  void _paintTargets(Canvas canvas) {
    if (targets.isEmpty) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    for (var i = 0; i < targets.length; i += 1) {
      final target = targets[i];
      final element = LightElement(
        id: 'toy-target-$i',
        size: target.size,
        pose: target.pose,
        position: target.position,
        headingDegrees: target.headingDegrees,
        illumination: IlluminationPattern.wall,
      );
      final polygon = polygonForElement(element, geometry);
      if (polygon.isEmpty) continue;
      final path = Path();
      final first = _px(polygon.first);
      path.moveTo(first.dx, first.dy);
      for (final point in polygon.skip(1)) {
        final offset = _px(point);
        path.lineTo(offset.dx, offset.dy);
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  void _paintRace(Canvas canvas) {
    if (raceProgress.isEmpty) return;
    for (final element in elements) {
      final progress = raceProgress[element.id];
      if (progress == null) continue;
      final baseRadius =
          geometry.baseMm(element.size) * logicalPixelsPerMm * 0.72;
      final rect = Rect.fromCircle(
        center: _px(element.position),
        radius: baseRadius + 7,
      );
      final background = Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final foreground = Paint()
        ..color = Colors.white.withValues(alpha: 0.68)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.6;
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, background);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0, 1),
        false,
        foreground,
      );
    }
  }

  void _paintTurnTimer(Canvas canvas, Size size) {
    final progress = turnTimerProgress;
    if (progress == null) return;
    final rect = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.62)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      paint,
    );
  }

  void _paintScenarioLabel(Canvas canvas, Size size) {
    final label = scenarioLabel;
    if (label == null || label.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 32);
    painter.paint(canvas, Offset((size.width - painter.width) / 2, 14));
  }

  @override
  bool shouldRepaint(covariant ToyOverlayPainter oldDelegate) => true;
}
