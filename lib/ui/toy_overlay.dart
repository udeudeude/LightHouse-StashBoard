import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/light_element.dart';
import '../domain/physical_point.dart';
import '../domain/pyramid_geometry.dart';

class ToyProjectile {
  const ToyProjectile({
    required this.position,
    required this.velocity,
    required this.radiusMm,
    this.ricochet = false,
    this.edgeHits = 0,
    this.escaping = false,
  });

  final PhysicalPoint position;
  final PhysicalPoint velocity;
  final double radiusMm;
  final bool ricochet;
  final int edgeHits;
  final bool escaping;

  ToyProjectile copyWith({
    PhysicalPoint? position,
    PhysicalPoint? velocity,
    int? edgeHits,
    bool? escaping,
  }) => ToyProjectile(
    position: position ?? this.position,
    velocity: velocity ?? this.velocity,
    radiusMm: radiusMm,
    ricochet: ricochet,
    edgeHits: edgeHits ?? this.edgeHits,
    escaping: escaping ?? this.escaping,
  );
}

class ToyImpact {
  const ToyImpact({required this.position, required this.lifeSeconds});
  final PhysicalPoint position;
  final double lifeSeconds;

  ToyImpact copyWith({double? lifeSeconds}) => ToyImpact(
    position: position,
    lifeSeconds: lifeSeconds ?? this.lifeSeconds,
  );
}

class ToyOverlayPainter extends CustomPainter {
  const ToyOverlayPainter({
    required this.logicalPixelsPerMm,
    required this.geometry,
    required this.elements,
    required this.ghostTrails,
    required this.ghostTrailsVisible,
    required this.eventZoneCenter,
    required this.eventZoneRadiusMm,
    required this.eventZoneProgress,
    required this.eventZoneDismiss,
    required this.turnTimerProgress,
    required this.radarAngleDegrees,
    required this.redSweepY,
    required this.dieValue,
    required this.dieRollPhase,
    required this.projectiles,
    required this.impacts,
    required this.sideGunsVisible,
    required this.cornerGunsVisible,
    required this.constellation,
    required this.rouletteAngleDegrees,
  });

  final double logicalPixelsPerMm;
  final PyramidGeometryProfile geometry;
  final List<LightElement> elements;
  final Map<String, List<PhysicalPoint>> ghostTrails;
  final bool ghostTrailsVisible;
  final PhysicalPoint? eventZoneCenter;
  final double? eventZoneRadiusMm;
  final double? eventZoneProgress;
  final double eventZoneDismiss;
  final double? turnTimerProgress;
  final double? radarAngleDegrees;
  final double? redSweepY;
  final int? dieValue;
  final double dieRollPhase;
  final List<ToyProjectile> projectiles;
  final List<ToyImpact> impacts;
  final bool sideGunsVisible;
  final bool cornerGunsVisible;
  final List<PhysicalPoint> constellation;
  final double? rouletteAngleDegrees;

  Offset _px(PhysicalPoint point) => Offset(
    point.xMm * logicalPixelsPerMm,
    point.yMm * logicalPixelsPerMm,
  );

  @override
  void paint(Canvas canvas, Size size) {
    _paintGhostTrails(canvas);
    _paintEventZone(canvas);
    _paintTurnTimer(canvas, size);
    _paintRadar(canvas, size);
    _paintRedSweep(canvas, size);
    _paintWireDie(canvas, size);
    _paintGuns(canvas, size);
    _paintProjectiles(canvas);
    _paintImpacts(canvas);
    _paintConstellation(canvas);
    _paintRoulette(canvas, size);
  }

  void _paintGhostTrails(Canvas canvas) {
    if (!ghostTrailsVisible) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.26)
      ..strokeWidth = 1.25
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final points in ghostTrails.values) {
      if (points.length < 2) continue;
      final path = Path()..moveTo(_px(points.first).dx, _px(points.first).dy);
      for (final point in points.skip(1)) {
        final o = _px(point);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, paint);
      for (var i = 0; i < points.length; i += 5) {
        canvas.drawCircle(_px(points[i]), 1.6, paint);
      }
    }
  }

  void _paintEventZone(Canvas canvas) {
    final center = eventZoneCenter;
    final radiusMm = eventZoneRadiusMm;
    final progress = eventZoneProgress;
    if (center == null || radiusMm == null || progress == null) return;
    final c = _px(center);
    final dismiss = eventZoneDismiss.clamp(0, 1).toDouble();
    final radius = radiusMm * logicalPixelsPerMm * (1 - dismiss * 0.18);
    final alpha = 1 - dismiss;
    final fill = Paint()
      ..color = Colors.white.withValues(alpha: 0.08 * alpha)
      ..style = PaintingStyle.fill;
    final ring = Paint()
      ..color = Colors.white.withValues(alpha: 0.70 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(c, radius, fill);
    canvas.drawCircle(c, radius, ring);

    final elapsed = 1 - progress.clamp(0, 1).toDouble();
    final timer = Paint()
      ..color = Colors.black.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: radius - 1.5),
      -math.pi / 2,
      math.pi * 2 * elapsed,
      false,
      timer,
    );

    if (dismiss > 0) {
      final shard = Paint()
        ..color = Colors.white.withValues(alpha: (1 - dismiss) * 0.65)
        ..strokeWidth = 1.5;
      for (var i = 0; i < 4; i++) {
        final a = i * math.pi / 2 + dismiss * 0.45;
        final inner = radius * (0.65 + dismiss * 0.15);
        final outer = radius * (0.90 + dismiss * 0.35);
        canvas.drawLine(
          Offset(c.dx + math.cos(a) * inner, c.dy + math.sin(a) * inner),
          Offset(c.dx + math.cos(a) * outer, c.dy + math.sin(a) * outer),
          shard,
        );
      }
    }
  }

  void _paintTurnTimer(Canvas canvas, Size size) {
    final progress = turnTimerProgress;
    if (progress == null) return;
    final rect = Rect.fromLTWH(11, 11, size.width - 22, size.height - 22);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
    final metric = path.computeMetrics().first;
    final length = metric.length * progress.clamp(0, 1).toDouble();
    final background = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final foreground = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, background);
    canvas.drawPath(metric.extractPath(0, length), foreground);
  }

  void _paintRadar(Canvas canvas, Size size) {
    final degrees = radarAngleDegrees;
    if (degrees == null) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radians = degrees * math.pi / 180;
    final radius = math.sqrt(size.width * size.width + size.height * size.height);
    final end = Offset(
      center.dx + math.cos(radians) * radius,
      center.dy + math.sin(radians) * radius,
    );
    final paint = Paint()
      ..color = const Color(0xFF35FF67).withValues(alpha: 0.80)
      ..strokeWidth = 1.4;
    canvas.drawLine(center, end, paint);
  }

  void _paintRedSweep(Canvas canvas, Size size) {
    final y = redSweepY;
    if (y == null) return;
    final paint = Paint()
      ..color = const Color(0xFFFF3030).withValues(alpha: 0.82)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, size.height * y), Offset(size.width, size.height * y), paint);
  }

  void _paintWireDie(Canvas canvas, Size size) {
    final value = dieValue;
    if (value == null) return;
    final center = Offset(size.width / 2, size.height / 2);
    final s = math.min(size.width, size.height) * 0.085;
    final phase = dieRollPhase;
    final skew = math.sin(phase) * s * 0.22;
    final front = Rect.fromCenter(center: center, width: s, height: s);
    final back = front.shift(Offset(s * 0.34 + skew, -s * 0.28 + math.cos(phase) * s * 0.08));
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(front, paint);
    canvas.drawRect(back, paint);
    for (final pair in [
      (front.topLeft, back.topLeft),
      (front.topRight, back.topRight),
      (front.bottomLeft, back.bottomLeft),
      (front.bottomRight, back.bottomRight),
    ]) {
      canvas.drawLine(pair.$1, pair.$2, paint);
    }
    final tp = TextPainter(
      text: TextSpan(
        text: '$value',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: s * 0.45, fontWeight: FontWeight.w300),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _paintGuns(Canvas canvas, Size size) {
    if (sideGunsVisible) {
      final paint = Paint()..color = Colors.white.withValues(alpha: 0.34);
      canvas.drawRect(Rect.fromCenter(center: Offset(size.width / 2, 3), width: 10, height: 5), paint);
      canvas.drawRect(Rect.fromCenter(center: Offset(size.width / 2, size.height - 3), width: 10, height: 5), paint);
      canvas.drawRect(Rect.fromCenter(center: Offset(3, size.height / 2), width: 5, height: 10), paint);
      canvas.drawRect(Rect.fromCenter(center: Offset(size.width - 3, size.height / 2), width: 5, height: 10), paint);
    }
    if (cornerGunsVisible) {
      const d = 7.0;
      final paint = Paint()..color = Colors.white.withValues(alpha: 0.22);
      for (final p in [const Offset(d, d), Offset(size.width - d, d), Offset(d, size.height - d), Offset(size.width - d, size.height - d)]) {
        canvas.drawCircle(p, 3.2, paint);
      }
    }
  }

  void _paintProjectiles(Canvas canvas) {
    for (final p in projectiles) {
      canvas.drawCircle(
        _px(p.position),
        math.max(1.4, p.radiusMm * logicalPixelsPerMm),
        Paint()..color = p.ricochet ? Colors.white.withValues(alpha: 0.72) : Colors.white.withValues(alpha: 0.88),
      );
    }
  }

  void _paintImpacts(Canvas canvas) {
    for (final impact in impacts) {
      final t = (impact.lifeSeconds / 0.8).clamp(0, 1).toDouble();
      final c = _px(impact.position);
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: t * 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3;
      canvas.drawCircle(c, 3 + (1 - t) * 9, paint);
      canvas.drawLine(c + const Offset(-4, -4), c + const Offset(4, 4), paint);
      canvas.drawLine(c + const Offset(-4, 4), c + const Offset(4, -4), paint);
    }
  }

  void _paintConstellation(Canvas canvas) {
    if (constellation.length < 2) return;
    final path = Path();
    final first = _px(constellation.first);
    path.moveTo(first.dx, first.dy);
    for (final point in constellation.skip(1)) {
      final o = _px(point);
      path.lineTo(o.dx, o.dy);
    }
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.48)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(path, paint);
    for (final point in constellation) {
      canvas.drawCircle(_px(point), 3.1, paint);
    }
  }

  void _paintRoulette(Canvas canvas, Size size) {
    final degrees = rouletteAngleDegrees;
    if (degrees == null) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radians = degrees * math.pi / 180;
    final radius = math.sqrt(size.width * size.width + size.height * size.height);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.68)
      ..strokeWidth = 1.3;
    canvas.drawLine(
      center,
      Offset(center.dx + math.cos(radians) * radius, center.dy + math.sin(radians) * radius),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant ToyOverlayPainter oldDelegate) => true;
}
