import 'dart:math' as math;

import 'physical_point.dart';

enum BoardUnderlay {
  none,
  grid3x3,
  grid3x4,
  grid4x4,
  grid5x5,
  grid5x6,
  martianChess2,
  chess8x8,
  wheel,
  looneyLudo4,
  launchpad23;

  static const double cellMm = 27;
  static const double coasterMm = 101.6;
  static const double wheelOuterRadiusMm = 127;
  static const double wheelPlayableRadiusMm = 112;

  bool get isVisible => this != BoardUnderlay.none;

  bool get isChessLike =>
      this == BoardUnderlay.martianChess2 || this == BoardUnderlay.chess8x8;

  bool get isRectangularGrid => switch (this) {
    BoardUnderlay.grid3x3 ||
    BoardUnderlay.grid3x4 ||
    BoardUnderlay.grid4x4 ||
    BoardUnderlay.grid5x5 ||
    BoardUnderlay.grid5x6 ||
    BoardUnderlay.martianChess2 ||
    BoardUnderlay.chess8x8 => true,
    _ => false,
  };

  int get columns => switch (this) {
    BoardUnderlay.grid3x3 => 3,
    BoardUnderlay.grid3x4 => 3,
    BoardUnderlay.grid4x4 => 4,
    BoardUnderlay.grid5x5 => 5,
    BoardUnderlay.grid5x6 => 5,
    BoardUnderlay.martianChess2 => 4,
    BoardUnderlay.chess8x8 => 8,
    _ => 0,
  };

  int get rows => switch (this) {
    BoardUnderlay.grid3x3 => 3,
    BoardUnderlay.grid3x4 => 4,
    BoardUnderlay.grid4x4 => 4,
    BoardUnderlay.grid5x5 => 5,
    BoardUnderlay.grid5x6 => 6,
    BoardUnderlay.martianChess2 => 8,
    BoardUnderlay.chess8x8 => 8,
    _ => 0,
  };

  String get menuLabel => switch (this) {
    BoardUnderlay.none => 'None',
    BoardUnderlay.grid3x3 => '3×3 grid',
    BoardUnderlay.grid3x4 => '3×4 bank',
    BoardUnderlay.grid4x4 => '4×4 grid',
    BoardUnderlay.grid5x5 => '5×5 · Volcano / Pharaoh',
    BoardUnderlay.grid5x6 => '5×6 grid',
    BoardUnderlay.martianChess2 => '4×8 · Martian Chess · 2 players',
    BoardUnderlay.chess8x8 => '8×8 · Martian Chess',
    BoardUnderlay.wheel => 'The Wheel · Petri Dish / Color Wheel',
    BoardUnderlay.looneyLudo4 => 'Looney Ludo · 4-board start',
    BoardUnderlay.launchpad23 => 'Launchpad 23',
  };

  List<PhysicalPoint> snapPoints({
    required double boardWidthMm,
    required double boardHeightMm,
  }) {
    final center = PhysicalPoint(boardWidthMm / 2, boardHeightMm / 2);
    if (isRectangularGrid) {
      return _rectGridPoints(center, columns, rows);
    }
    return switch (this) {
      BoardUnderlay.launchpad23 => _rectGridPoints(center, 3, 3),
      BoardUnderlay.looneyLudo4 => _ludoFourBoardPoints(center),
      BoardUnderlay.wheel => _wheelPoints(center),
      _ => const <PhysicalPoint>[],
    };
  }

  PhysicalPoint? nearestSnapPoint(
    PhysicalPoint point, {
    required double boardWidthMm,
    required double boardHeightMm,
  }) {
    final points = snapPoints(
      boardWidthMm: boardWidthMm,
      boardHeightMm: boardHeightMm,
    );
    if (points.isEmpty) return null;
    var nearest = points.first;
    var distance = point.distanceTo(nearest);
    for (final candidate in points.skip(1)) {
      final nextDistance = point.distanceTo(candidate);
      if (nextDistance < distance) {
        nearest = candidate;
        distance = nextDistance;
      }
    }
    return nearest;
  }

  static BoardUnderlay fromName(Object? value) {
    if (value is! String) return BoardUnderlay.none;
    for (final underlay in BoardUnderlay.values) {
      if (underlay.name == value) return underlay;
    }
    return BoardUnderlay.none;
  }
}

List<PhysicalPoint> _rectGridPoints(
  PhysicalPoint center,
  int columns,
  int rows,
) {
  final left = center.xMm - columns * BoardUnderlay.cellMm / 2;
  final top = center.yMm - rows * BoardUnderlay.cellMm / 2;
  return [
    for (var row = 0; row < rows; row += 1)
      for (var column = 0; column < columns; column += 1)
        PhysicalPoint(
          left + (column + 0.5) * BoardUnderlay.cellMm,
          top + (row + 0.5) * BoardUnderlay.cellMm,
        ),
  ];
}

List<PhysicalPoint> _ludoFourBoardPoints(PhysicalPoint center) {
  final half = BoardUnderlay.coasterMm / 2;
  final points = <PhysicalPoint>[];
  for (final dx in [-half, half]) {
    for (final dy in [-half, half]) {
      points.addAll(
        _rectGridPoints(PhysicalPoint(center.xMm + dx, center.yMm + dy), 3, 3),
      );
    }
  }
  return points;
}

List<PhysicalPoint> _wheelPoints(PhysicalPoint center) {
  final points = <PhysicalPoint>[];
  const count = 10;
  final step = 2 * math.pi / count;
  final vertices = <PhysicalPoint>[
    for (var i = 0; i < count; i += 1)
      PhysicalPoint(
        center.xMm +
            BoardUnderlay.wheelPlayableRadiusMm *
                math.cos(-math.pi / 2 + i * step),
        center.yMm +
            BoardUnderlay.wheelPlayableRadiusMm *
                math.sin(-math.pi / 2 + i * step),
      ),
  ];

  for (var i = 0; i < count; i += 1) {
    final a = vertices[i];
    final b = vertices[(i + 1) % count];
    final ca = _midpoint(center, a);
    final cb = _midpoint(center, b);
    final ab = _midpoint(a, b);

    // Connecting the three side midpoints subdivides each wedge into the four
    // triangular spaces used by The Wheel.
    points
      ..add(_centroid(center, ca, cb))
      ..add(_centroid(ca, a, ab))
      ..add(_centroid(cb, ab, b))
      ..add(_centroid(ca, ab, cb));
  }
  return points;
}

PhysicalPoint _midpoint(PhysicalPoint a, PhysicalPoint b) =>
    PhysicalPoint((a.xMm + b.xMm) / 2, (a.yMm + b.yMm) / 2);

PhysicalPoint _centroid(PhysicalPoint a, PhysicalPoint b, PhysicalPoint c) =>
    PhysicalPoint((a.xMm + b.xMm + c.xMm) / 3, (a.yMm + b.yMm + c.yMm) / 3);
