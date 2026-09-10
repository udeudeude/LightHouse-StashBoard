import 'package:flutter_test/flutter_test.dart';
import 'package:lighthouse/application/board_controller.dart';
import 'package:lighthouse/domain/board_state.dart';
import 'package:lighthouse/domain/light_element.dart';
import 'package:lighthouse/domain/light_structure.dart';
import 'package:lighthouse/domain/physical_point.dart';

LightElement element({
  required String id,
  required PyramidSize size,
  required PhysicalPoint position,
  PyramidPose pose = PyramidPose.upright,
  IlluminationPattern illumination = IlluminationPattern.full,
  double headingDegrees = 0,
}) => LightElement(
  id: id,
  size: size,
  pose: pose,
  position: position,
  headingDegrees: headingDegrees,
  illumination: illumination,
);

void main() {
  test('wall-only illumination survives tip and stand', () {
    final wall = element(
      id: 'wall',
      size: PyramidSize.medium,
      position: const PhysicalPoint(40, 40),
      illumination: IlluminationPattern.wall,
    );
    final controller = BoardController(initialState: BoardState(elements: [wall]));

    controller.tipOrStand(wall, const PhysicalPoint(10, 0));
    final tipped = controller.state.elementById('wall')!;
    expect(tipped.pose, PyramidPose.flat);
    expect(tipped.illumination, IlluminationPattern.wall);

    // A rightward tip creates a flat footprint with a 90-degree heading, so
    // global leftward travel is local point-to-base travel for standing it.
    controller.tipOrStand(tipped, const PhysicalPoint(-10, 0));
    final stood = controller.state.elementById('wall')!;
    expect(stood.pose, PyramidPose.upright);
    expect(stood.illumination, IlluminationPattern.wall);
  });

  test('collision pushes another footprint during the drag', () {
    final moving = element(
      id: 'moving',
      size: PyramidSize.small,
      position: const PhysicalPoint(0, 0),
    );
    final obstacle = element(
      id: 'obstacle',
      size: PyramidSize.small,
      position: const PhysicalPoint(20, 0),
    );
    final controller = BoardController(
      initialState: BoardState(elements: [moving, obstacle]),
    );

    controller.beginTransform(moving);
    controller.transformBy(const PhysicalPoint(10, 0), 0);

    expect(controller.state.elementById('moving')!.position.xMm, 10);
    expect(controller.state.elementById('obstacle')!.position.xMm, greaterThan(20));
  });

  test('overlapping different wall-only squares automatically nest', () {
    final large = element(
      id: 'large',
      size: PyramidSize.large,
      position: const PhysicalPoint(50, 50),
      illumination: IlluminationPattern.wall,
    );
    final small = element(
      id: 'small',
      size: PyramidSize.small,
      position: const PhysicalPoint(80, 50),
      illumination: IlluminationPattern.wall,
    );
    final controller = BoardController(
      initialState: BoardState(elements: [large, small]),
    );

    controller.beginTransform(small);
    controller.transformBy(const PhysicalPoint(-20, 0), 0);
    controller.endTransform();

    expect(controller.state.structures, hasLength(1));
    final structure = controller.state.structures.single;
    expect(structure.kind, StructureKind.nest);
    expect(structure.memberIds.toSet(), {'large', 'small'});
    expect(controller.state.elementById('large')!.position, const PhysicalPoint(50, 50));
    expect(controller.state.elementById('small')!.position, const PhysicalPoint(50, 50));
  });
}
