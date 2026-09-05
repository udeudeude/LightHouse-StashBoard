import 'package:flutter_test/flutter_test.dart';
import 'package:lighthouse/application/board_controller.dart';
import 'package:lighthouse/domain/light_element.dart';
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
}
