import 'package:flutter_test/flutter_test.dart';
import 'package:lighthouse/application/board_controller.dart';
import 'package:lighthouse/domain/board_state.dart';
import 'package:lighthouse/domain/light_element.dart';
import 'package:lighthouse/domain/light_structure.dart';
import 'package:lighthouse/domain/physical_point.dart';

void main() {
  test('create resize delete undo redo are deterministic', () {
    final controller = BoardController();
    controller.createAt(const PhysicalPoint(25, 40));
    expect(controller.state.elements.single.size, PyramidSize.small);

    controller.cycleSizeOrDelete(controller.state.elements.single);
    expect(controller.state.elements.single.size, PyramidSize.medium);

    controller.cycleSizeOrDelete(controller.state.elements.single);
    expect(controller.state.elements.single.size, PyramidSize.large);

    controller.cycleSizeOrDelete(controller.state.elements.single);
    expect(controller.state.elements, isEmpty);

    controller.undo();
    expect(controller.state.elements.single.size, PyramidSize.large);

    controller.redo();
    expect(controller.state.elements, isEmpty);
  });

  test('wall illumination is reversible', () {
    final controller = BoardController();
    controller.createAt(const PhysicalPoint(10, 10));

    controller.toggleIllumination(controller.state.elements.single);
    expect(
      controller.state.elements.single.illumination,
      IlluminationPattern.wall,
    );

    controller.undo();
    expect(
      controller.state.elements.single.illumination,
      IlluminationPattern.full,
    );
  });

  test(
    'eastward drag tips upright element and reverse hinge drag stands it',
    () {
      final controller = BoardController();
      controller.createAt(const PhysicalPoint(50, 50));
      final upright = controller.state.elements.single;

      controller.tipOrStand(upright, const PhysicalPoint(10, 0));
      final flat = controller.state.elements.single;
      expect(flat.pose, PyramidPose.flat);
      expect(flat.headingDegrees, closeTo(90, 0.001));
      expect(flat.position.xMm, greaterThan(50));

      controller.tipOrStand(flat, const PhysicalPoint(-10, 0));
      final stood = controller.state.elements.single;
      expect(stood.pose, PyramidPose.upright);
      expect(stood.position.xMm, closeTo(50, 0.001));
      expect(stood.position.yMm, closeTo(50, 0.001));
    },
  );

  test('different sizes snap into a co-located structure', () {
    const large = LightElement(
      id: 'large',
      size: PyramidSize.large,
      pose: PyramidPose.upright,
      position: PhysicalPoint(50, 50),
      headingDegrees: 0,
      illumination: IlluminationPattern.wall,
    );
    const small = LightElement(
      id: 'small',
      size: PyramidSize.small,
      pose: PyramidPose.upright,
      position: PhysicalPoint(55, 50),
      headingDegrees: 0,
      illumination: IlluminationPattern.full,
    );
    final controller = BoardController(
      initialState: BoardState(elements: const [large, small]),
    );

    expect(
      controller.snapIntoNearestStructure(small, StructureKind.stack),
      isTrue,
    );
    expect(controller.state.structures, hasLength(1));
    expect(
      controller.state.elementById('small')!.position,
      controller.state.elementById('large')!.position,
    );
  });

  test('moving one member moves the whole structure', () {
    const large = LightElement(
      id: 'large',
      size: PyramidSize.large,
      pose: PyramidPose.upright,
      position: PhysicalPoint(50, 50),
      headingDegrees: 0,
      illumination: IlluminationPattern.wall,
    );
    const small = LightElement(
      id: 'small',
      size: PyramidSize.small,
      pose: PyramidPose.upright,
      position: PhysicalPoint(50, 50),
      headingDegrees: 0,
      illumination: IlluminationPattern.full,
    );
    final controller = BoardController(
      initialState: BoardState(
        elements: const [large, small],
        structures: const [
          LightStructure(
            id: 'structure',
            kind: StructureKind.stack,
            memberIds: ['large', 'small'],
          ),
        ],
      ),
    );

    controller.beginTransform(small);
    controller.transformBy(const PhysicalPoint(10, 5), 0);
    controller.endTransform();

    expect(
      controller.state.elementById('large')!.position,
      const PhysicalPoint(60, 55),
    );
    expect(
      controller.state.elementById('small')!.position,
      const PhysicalPoint(60, 55),
    );
  });
}
