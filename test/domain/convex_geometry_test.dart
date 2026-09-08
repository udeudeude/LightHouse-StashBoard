import 'package:flutter_test/flutter_test.dart';
import 'package:lighthouse/domain/convex_geometry.dart';
import 'package:lighthouse/domain/light_element.dart';
import 'package:lighthouse/domain/physical_point.dart';
import 'package:lighthouse/domain/pyramid_geometry.dart';

void main() {
  const geometry = PyramidGeometryProfile.prototype2025;

  LightElement upright(String id, double x) => LightElement(
    id: id,
    size: PyramidSize.large,
    pose: PyramidPose.upright,
    position: PhysicalPoint(x, 0),
    headingDegrees: 0,
    illumination: IlluminationPattern.full,
  );

  test('separated footprints do not collide', () {
    final a = polygonForElement(upright('a', 0), geometry);
    final b = polygonForElement(upright('b', 40), geometry);
    expect(minimumSeparationVector(a, b), isNull);
  });

  test('overlapping footprints produce a separation vector', () {
    final a = polygonForElement(upright('a', 0), geometry);
    final b = polygonForElement(upright('b', 10), geometry);
    final separation = minimumSeparationVector(a, b);
    expect(separation, isNotNull);
    expect(separation!.xMm, greaterThan(0));
  });
}
