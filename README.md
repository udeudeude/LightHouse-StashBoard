# LightHouse

LightHouse is an interactive illuminated physical play surface for Looney Pyramids. The screen and the physical plastic pieces together form the interface.

This branch is the clean-sheet Flutter rewrite of the 2025 React / Google AI Studio prototype.

## Current implementation

Implemented now:

- canonical board coordinates stored in millimeters
- automatic physical-size calibration for recognized iPhone models, with manual calibration fallback
- 50 mm ruler calibration / verification
- upright Small, Medium, and Large light footprints
- full and wall-only upright illumination
- flat pyramid rendering
- double-tap empty board to create a Small upright footprint
- double-tap a footprint to cycle Small -> Medium -> Large -> delete
- scribble over an upright footprint to toggle full/wall illumination
- one-finger directional drag to tip an upright footprint or stand a flat footprint
- two-finger translate and rotate
- command-based undo/redo
- versioned JSON board serialization
- local autosave across launches
- screen-awake behavior during play
- generated iOS, Android, and web platform runners
- automated formatting, static analysis, tests, and unsigned iOS build validation in CI

Not implemented yet:

- real stack/nest structures
- polygon collision and pushing
- saved-board management and import/export UI
- platform brightness control and haptics
- device cutout / safe-board geometry
- orientation policy and restoration behavior
- measured geometry profiles for different pyramid generations

## Development

The source is a Flutter app. Flutter 3.47 / Dart 3.13 or newer is the current baseline.

```sh
flutter pub get
flutter test
flutter run
```

For iPhone testing, open `ios/Runner.xcworkspace` in Xcode, choose your Apple development team under Signing & Capabilities, select the connected iPhone, and Run.

The browser target also builds successfully. Hosting/deployment is intentionally separate from the application code.

## Design rule

Canonical board state is expressed in physical millimeters. Screen pixels or Flutter logical pixels belong only at the calibration/rendering boundary.

See `docs/architecture.md` for the current design decisions.
