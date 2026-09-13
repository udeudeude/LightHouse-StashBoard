# Changelog

## Unreleased

- Expanded Toys into a full opt-in tray: Light Race, Territory Zones, Ghost Paths, Random Event Zone, Memory Sequence, Turn Timer, Augmented Overlay, Co-op Mirror Puzzle, and Scenario Deck now join Light Lottery and Entropy. Each toy has a persistent menu visibility toggle and its own board icon.
- Reworked iPhone/iPad web orientation handling: Safari orientation changes are now observed directly, rechecked after viewport changes, and polled as a fallback; the frozen opening board counter-rotates so the physical play surface and touch hit testing stay fixed to the glass.
- Reworked iPhone/iPad web face-down credits to use a direct browser Device Motion bridge with gravity data after permission is granted; the face-up Z-axis sign is learned from stable samples, credits appear only while face-down, and vanish when face-up.
- Moved rotation-snap degree ticks flush against the inside edge of the hollow menu circle.
- Changed Light Lottery to a completely regular 120 ms flashing cadence while randomizing which single footprint flashes on each beat and randomizing the total run time before the winner is selected.
- Added a Toys submenu with persistent on/off visibility controls for Light Lottery and Entropy Delete; each enabled toy has its own tappable board icon.
- Refined board menus into Board > File and Board > Underlays, with Mac-like file ordering.
- Added The Wheel, Looney Ludo four-board start, and Launchpad 23 underlays plus optional grid snapping.
- Added exact rotation controls and persistent rotation snap increments, reflected by tick marks in the menu circle.
- Moved the menu and device-specific instructions to the lower left.
- Removed the user-facing Structure menu while retaining structure semantics internally.

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
