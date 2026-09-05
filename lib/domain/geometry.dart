import 'dart:math' as math;

import 'light_element.dart';
import 'physical_point.dart';
import 'pyramid_geometry.dart';

double degreesToRadians(double degrees) => degrees * math.pi / 180.0;
double radiansToDegrees(double radians) => radians * 180.0 / math.pi;

double normalizeDegrees(double degrees) {
  var result = degrees % 360.0;
  if (result < 0) result += 360.0;
  return result;
}

double normalizeRadians(double radians) {
  var result = radians;
  while (result > math.pi) result -= 2 * math.pi;
  while (result < -math.pi) result += 2 * math.pi;
  return result;
}

PhysicalPoint rotateVector(PhysicalPoint vector, double degrees) {
  final radians = degreesToRadians(degrees);
  final cosA = math.cos(radians);
  final sinA = math.sin(radians);
  return PhysicalPoint(
    vector.xMm * cosA - vector.yMm * sinA,
    vector.xMm * sinA + vector.yMm * cosA,
  );
}

bool hitTestLightElement(
  LightElement element,
  PhysicalPoint point,
  PyramidGeometryProfile geometry, {
  double haloMm = 6,
}) {
  final local = rotateVector(point - element.position, -element.headingDegrees);
  final halfBase = geometry.baseMm(element.size) / 2;

  if (element.pose == PyramidPose.upright) {
    return local.xMm.abs() <= halfBase + haloMm &&
        local.yMm.abs() <= halfBase + haloMm;
  }

  final halfLength = geometry.flatLengthMm(element.size) / 2;
  return local.xMm.abs() <= halfBase + haloMm &&
      local.yMm.abs() <= halfLength + haloMm;
}
