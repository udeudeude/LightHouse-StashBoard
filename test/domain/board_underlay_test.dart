import 'package:flutter_test/flutter_test.dart';
import 'package:lighthouse/domain/board_underlay.dart';
import 'package:lighthouse/domain/physical_point.dart';

void main() {
  test('wheel exposes forty snap locations', () {
    final points = BoardUnderlay.wheel.snapPoints(
      boardWidthMm: 300,
      boardHeightMm: 300,
    );
    expect(points, hasLength(40));
  });

  test('Launchpad 23 exposes a centered 3 by 3 snap grid', () {
    final points = BoardUnderlay.launchpad23.snapPoints(
      boardWidthMm: 200,
      boardHeightMm: 300,
    );
    expect(points, hasLength(9));
    expect(points[4], const PhysicalPoint(100, 150));
  });

  test('Looney Ludo four-board start exposes four 3 by 3 grids', () {
    final points = BoardUnderlay.looneyLudo4.snapPoints(
      boardWidthMm: 300,
      boardHeightMm: 300,
    );
    expect(points, hasLength(36));
  });
}
