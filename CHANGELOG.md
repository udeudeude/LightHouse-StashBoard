# Changelog

## 0.3.0 - 2026-09-08

Major LightHouse 2 development milestone.

### Added

- physical millimeter-native board model
- automatic iPhone calibration and Android reported-DPI calibration
- ruler and Large-pyramid manual calibration
- quick calibration verification
- full/wall illumination for upright footprints
- touch tipping, standing, scribble switching, translation, and rotation
- desktop mouse translation and Shift-drag rotation
- stack/nest structure model and grouped transforms
- convex polygon collision separation for pushing
- undo/redo for semantic board operations
- autosave with recovery backup
- named board library and JSON clipboard import/export
- native brightness control, screen wake lock, haptics, safe-board insets, and orientation handling
- installable PWA metadata and GitHub Pages deployment
- CI formatting, analysis, tests, and unsigned iOS build validation

### Changed

- replaced the React / TypeScript / AI Studio prototype architecture with Flutter / Dart
- replaced pixel-domain positions and gesture thresholds with physical millimeters
- replaced rendered square/triangle domain objects with light footprints and physical pose
- upgraded the board document format from version 1 to version 2; version 1 documents migrate automatically

## 0.2.0

Initial clean-sheet Flutter rewrite foundation.

## 0.1.0

2025 React / Google AI Studio interaction prototype.
