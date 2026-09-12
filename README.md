# LightHouse

LightHouse is an interactive illuminated physical play surface for Looney Pyramids. The screen and the physical plastic pieces together form the interface.

This branch is the clean-sheet Flutter rewrite of the 2025 React / Google AI Studio prototype.

## Try it

The current web build is deployed automatically from this branch:

https://udeudeude.github.io/LightHouse-StashBoard/

The web build requires manual physical calibration because browsers do not reliably expose real-world screen dimensions. Native iOS uses known device geometry where available; native Android uses the device's reported physical DPI when it is plausible, with the same manual fallback.

## Current implementation

- canonical board coordinates stored in physical millimeters
- automatic physical-size calibration for recognized iPhone models
- automatic Android calibration from reported physical DPI when trustworthy
- manual ruler and real-Large-pyramid calibration, plus quick size verification
- upright Small, Medium, and Large light footprints with full or wall-only illumination
- flat pyramid footprints
- double-tap empty board to create a Small footprint
- double-tap a footprint to cycle Small -> Medium -> Large -> delete
- loose encirclement gesture around an upright footprint to toggle full/wall illumination
- exact-footprint one-finger directional drag to tip or stand, without an interaction halo
- two-finger translate and rotate on touch devices
- mouse/trackpad interaction on desktop with device-specific instructions
- direct orientation controls at 45-degree intervals
- persistent optional rotation snapping at 15, 30, 45, or 90 degrees, shown by degree ticks inside the menu control
- optional position snapping to the active underlay
- underlays for common rectangular grids, Martian Chess, Launchpad 23, a four-board Looney Ludo start, and The Wheel used by Petri Dish / Color Wheel
- automatic different-size wall-only nesting on overlap
- internal stack/nest structure records with independently illuminated member footprints and coherent grouped movement
- deterministic convex-polygon collision pushing across pyramid sizes
- command-based undo/redo
- versioned JSON board serialization with migration support
- local autosave with recovery backup, named saved boards, and JSON clipboard import/export
- lower-left hierarchical Board > File / Underlays menu with Mac-like File ordering
- device-specific instructions shown from the lower left
- Light Lottery theatrical random chooser
- optional Entropy Delete mode that fades and removes one random footprint every 30 seconds
- deliberately hidden face-down-only credits on supported motion-enabled devices; they vanish the instant the device is face-up
- native mobile orientation lock; web builds explain the browser limitation and defer to the device's rotation lock
- screen-awake behavior, native application-brightness control, haptics, and safe-board insets
- installable PWA metadata and iOS Add-to-Home-Screen guidance
- generated iOS, Android, and web platform runners
- automated formatting, static analysis, tests, unsigned iOS build validation, Android build validation, and GitHub Pages deployment

## Interaction notes

Touch:

- Double tap empty space: create Small
- Double tap a footprint: Small -> Medium -> Large -> delete
- One-finger directional drag across the exact footprint boundary: tip / stand
- Draw a loose loop around an upright footprint: full <-> wall-only illumination
- Two-finger drag/twist: translate and rotate
- Tap: select a footprint for direct orientation commands

Desktop:

- Double click mirrors double tap
- Click selects
- Mouse/trackpad controls are summarized in the in-app Instructions panel for the current device

Board controls:

- Board > File: New, Open, Save, Save a Copy, Rename, JSON import/export
- Board > Underlays: choose an underlay and optionally enable position snapping
- Edit > Rotation: rotate in 15-degree steps, choose an exact orientation, or enable persistent rotation snapping
- Display: size/calibration, brightness, and orientation information

The user-facing Structure menu was removed. Stack/nest relationships remain an internal board concept so physically grouped footprints still move, push, save, restore, and undo correctly.

## Development

The source is a Flutter app. Flutter 3.47 / Dart 3.13 or newer is the current baseline.

```sh
flutter pub get
flutter test
flutter run
```

For iPhone testing, open `ios/Runner.xcworkspace` in Xcode, choose your Apple development team under Signing & Capabilities, select the connected iPhone, and Run.

## Design rule

Canonical board state is expressed in physical millimeters. Screen pixels or Flutter logical pixels belong only at the calibration/rendering boundary.

See `docs/architecture.md` for design rationale and physical invariants.

## License

MIT. See `LICENSE`.