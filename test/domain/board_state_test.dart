import 'package:flutter_test/flutter_test.dart';
import 'package:lighthouse/domain/board_state.dart';
import 'package:lighthouse/domain/light_element.dart';
import 'package:lighthouse/domain/light_structure.dart';
import 'package:lighthouse/domain/physical_point.dart';

void main() {
  test('board documents round-trip through JSON with structures', () {
    final original = BoardState(
      title: 'Example',
      elements: const [
        LightElement(
          id: 'large',
          size: PyramidSize.large,
          pose: PyramidPose.upright,
          position: PhysicalPoint(20, 30),
          headingDegrees: 0,
          illumination: IlluminationPattern.wall,
        ),
        LightElement(
          id: 'small',
          size: PyramidSize.small,
          pose: PyramidPose.upright,
          position: PhysicalPoint(20, 30),
          headingDegrees: 0,
          illumination: IlluminationPattern.full,
        ),
      ],
      structures: const [
        LightStructure(
          id: 'structure-a',
          kind: StructureKind.stack,
          memberIds: ['large', 'small'],
        ),
      ],
    );

    final restored = BoardState.fromJson(original.toJson());
    expect(restored.title, 'Example');
    expect(restored.elements, original.elements);
    expect(restored.structures, original.structures);
  });

  test('version 1 board documents migrate without structures', () {
    final restored = BoardState.fromJson({
      'format': 'lighthouse-board',
      'version': 1,
      'elements': [
        {
          'id': 'a',
          'size': 'medium',
          'pose': 'upright',
          'position': {'xMm': 20, 'yMm': 30},
          'headingDegrees': 45,
          'illumination': 'wall',
        },
      ],
    });

    expect(restored.elements, hasLength(1));
    expect(restored.structures, isEmpty);
    expect(restored.title, 'Untitled Board');
  });

  test('removing a member cleans up undersized structures', () {
    final state = BoardState(
      elements: const [
        LightElement(
          id: 'a',
          size: PyramidSize.large,
          pose: PyramidPose.upright,
          position: PhysicalPoint.zero,
          headingDegrees: 0,
          illumination: IlluminationPattern.full,
        ),
        LightElement(
          id: 'b',
          size: PyramidSize.small,
          pose: PyramidPose.upright,
          position: PhysicalPoint.zero,
          headingDegrees: 0,
          illumination: IlluminationPattern.full,
        ),
      ],
      structures: const [
        LightStructure(
          id: 's',
          kind: StructureKind.nest,
          memberIds: ['a', 'b'],
        ),
      ],
    );

    expect(state.remove('a').structures, isEmpty);
  });
}
