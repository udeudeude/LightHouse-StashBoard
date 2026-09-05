import 'package:flutter_test/flutter_test.dart';
import 'package:lighthouse/domain/board_state.dart';
import 'package:lighthouse/domain/light_element.dart';
import 'package:lighthouse/domain/physical_point.dart';

void main() {
  test('board documents round-trip through JSON', () {
    final original = BoardState(
      elements: const [
        LightElement(
          id: 'a',
          size: PyramidSize.medium,
          pose: PyramidPose.upright,
          position: PhysicalPoint(20, 30),
          headingDegrees: 45,
          illumination: IlluminationPattern.wall,
        ),
      ],
    );

    final restored = BoardState.fromJson(original.toJson());
    expect(restored.elements, original.elements);
  });
}
