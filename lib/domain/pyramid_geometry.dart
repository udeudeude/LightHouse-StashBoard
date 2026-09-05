import 'light_element.dart';

class PyramidGeometryProfile {
  const PyramidGeometryProfile({
    required this.smallBaseMm,
    required this.mediumBaseMm,
    required this.largeBaseMm,
    required this.smallFlatLengthMm,
    required this.mediumFlatLengthMm,
    required this.largeFlatLengthMm,
    required this.wallBandMm,
  });

  static const prototype2025 = PyramidGeometryProfile(
    smallBaseMm: 14.2875,
    mediumBaseMm: 19.84375,
    largeBaseMm: 25.4,
    smallFlatLengthMm: 25.4,
    mediumFlatLengthMm: 34.925,
    largeFlatLengthMm: 44.45,
    wallBandMm: 3.175,
  );

  final double smallBaseMm;
  final double mediumBaseMm;
  final double largeBaseMm;
  final double smallFlatLengthMm;
  final double mediumFlatLengthMm;
  final double largeFlatLengthMm;
  final double wallBandMm;

  double baseMm(PyramidSize size) => switch (size) {
        PyramidSize.small => smallBaseMm,
        PyramidSize.medium => mediumBaseMm,
        PyramidSize.large => largeBaseMm,
      };

  double flatLengthMm(PyramidSize size) => switch (size) {
        PyramidSize.small => smallFlatLengthMm,
        PyramidSize.medium => mediumFlatLengthMm,
        PyramidSize.large => largeFlatLengthMm,
      };
}
