# Changelog

## Unreleased

- Refined board menus into Board > File and Board > Underlays, with Mac-like file ordering.
- Added The Wheel, Looney Ludo four-board start, and Launchpad 23 underlays plus optional grid snapping.
- Added exact rotation controls and persistent rotation snap increments, reflected by tick marks in the menu circle.
- Moved the menu and device-specific instructions to the lower left.
- Added a light-lottery animation and optional 30-second random fade/delete entropy control.
- Added iOS web motion-permission support for face-down credits; native mobile keeps a hard orientation lock.
- Removed the user-facing Structure menu while retaining structure semantics internally.

# Changelog

## 0.3.1 - 2026-09-09

Physical interaction refinement from hands-on testing.

### Changed

- collision pushing now resolves continuously while dragging so contact is visible
- wall-only illumination is preserved when a footprint is tipped and stood again
- tipping now uses an exact inside-square to outside-square line rather than an interaction halo
- standing now uses point-to-base travel within the actual flat triangle
- replaced scribble illumination switching with tolerant encirclement detection around an upright footprint
- overlapping different-size wall-only upright footprints automatically align as a nest, anchored to the largest member
- removed the separate snap, ruler, board-title, undo, and redo controls from the board surface
- replaced the ellipsis control with a thin hollow-circle menu control
- reorganized commands into Board, Edit, Structure, Display, Transfer, and About submenus
- locked the active board to one exact display orientation
- added a face-down device gesture that reveals credits on supported native devices

### Tested

- added regression tests for preserved wall illumination, live collision pushing, and automatic wall-only nesting

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
