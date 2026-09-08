import 'dart:math' as math;

import 'light_element.dart';
import 'physical_point.dart';
import 'pyramid_geometry.dart';

List<PhysicalPoint> polygonForElement(
  LightElement element,
  PyramidGeometryProfile geometry,
) {
  final halfBase = geometry.baseMm(element.size) / 2;
  final local = <PhysicalPoint>[];

  if (element.pose == PyramidPose.upright) {
    local.addAll([
      PhysicalPoint(-halfBase, -halfBase),
      PhysicalPoint(halfBase, -halfBase),
      PhysicalPoint(halfBase, halfBase),
      PhysicalPoint(-halfBase, halfBase),
    ]);
  } else {
    final halfLength = geometry.flatLengthMm(element.size) / 2;
    local.addAll([
      PhysicalPoint(0, -halfLength),
      PhysicalPoint(halfBase, halfLength),
      PhysicalPoint(-halfBase, halfLength),
    ]);
  }

  return [
    for (final point in local)
      _rotate(point, element.headingDegrees) + element.position,
  ];
}

/// Returns the smallest vector that should be added to polygon B to separate
/// it from polygon A, or null if the polygons do not overlap.
PhysicalPoint? minimumSeparationVector(
  List<PhysicalPoint> polygonA,
  List<PhysicalPoint> polygonB,
) {
  var minimumOverlap = double.infinity;
  PhysicalPoint? minimumAxis;

  for (final polygon in [polygonA, polygonB]) {
    for (var i = 0; i < polygon.length; i += 1) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];
      final edge = p2 - p1;
      final length = math.sqrt(edge.xMm * edge.xMm + edge.yMm * edge.yMm);
      if (length == 0) continue;
      var axis = PhysicalPoint(-edge.yMm / length, edge.xMm / length);

      final projectionA = _project(polygonA, axis);
      final projectionB = _project(polygonB, axis);
      final overlap = math.min(projectionA.$2, projectionB.$2) -
          math.max(projectionA.$1, projectionB.$1);
      if (overlap <= 0) return null;

      if (overlap < minimumOverlap) {
        final centerDirection = _centroid(polygonB) - _centroid(polygonA);
        if (_dot(centerDirection, axis) < 0) {
          axis = PhysicalPoint(-axis.xMm, -axis.yMm);
        }
        minimumOverlap = overlap;
        minimumAxis = axis;
      }
    }
  }

  final axis = minimumAxis;
  if (axis == null || !minimumOverlap.isFinite) return null;
  const clearanceMm = 0.15;
  return PhysicalPoint(
    axis.xMm * (minimumOverlap + clearanceMm),
    axis.yMm * (minimumOverlap + clearanceMm),
  );
}

(double, double) _project(
  List<PhysicalPoint> polygon,
  PhysicalPoint axis,
) {
  var min = double.infinity;
  var max = double.negativeInfinity;
  for (final point in polygon) {
    final value = _dot(point, axis);
    min = math.min(min, value);
    max = math.max(max, value);
  }
  return (min, max);
}

PhysicalPoint _centroid(List<PhysicalPoint> polygon) {
  var x = 0.0;
  var y = 0.0;
  for (final point in polygon) {
    x += point.xMm;
    y += point.yMm;
  }
  return PhysicalPoint(x / polygon.length, y / polygon.length);
}

double _dot(PhysicalPoint a, PhysicalPoint b) =>
    a.xMm * b.xMm + a.yMm * b.yMm;

PhysicalPoint _rotate(PhysicalPoint point, double degrees) {
  final radians = degrees * math.pi / 180;
  final cosA = math.cos(radians);
  final sinA = math.sin(radians);
  return PhysicalPoint(
    point.xMm * cosA - point.yMm * sinA,
    point.xMm * sinA + point.yMm * cosA,
  );
}
