import 'dart:math' as math;

/// A position or vector in physical millimeters.
class PhysicalPoint {
  const PhysicalPoint(this.xMm, this.yMm);

  final double xMm;
  final double yMm;

  static const zero = PhysicalPoint(0, 0);

  PhysicalPoint operator +(PhysicalPoint other) =>
      PhysicalPoint(xMm + other.xMm, yMm + other.yMm);

  PhysicalPoint operator -(PhysicalPoint other) =>
      PhysicalPoint(xMm - other.xMm, yMm - other.yMm);

  double distanceTo(PhysicalPoint other) {
    final dx = xMm - other.xMm;
    final dy = yMm - other.yMm;
    return math.sqrt(dx * dx + dy * dy);
  }

  Map<String, Object> toJson() => {'xMm': xMm, 'yMm': yMm};

  factory PhysicalPoint.fromJson(Map<String, Object?> json) => PhysicalPoint(
    (json['xMm'] as num).toDouble(),
    (json['yMm'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      other is PhysicalPoint && other.xMm == xMm && other.yMm == yMm;

  @override
  int get hashCode => Object.hash(xMm, yMm);
}
