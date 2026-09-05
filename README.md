# LightHouse

LightHouse is an interactive illuminated physical play surface for Looney Pyramids. The screen and the plastic pieces together form the interface.

This branch is the clean-sheet Flutter rewrite of the 2025 React/AI Studio prototype.

## Current prototype slice

Implemented in the rewrite:

- physical board coordinates stored in millimeters
- 50 mm ruler calibration
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

Not implemented yet:

- real stack/nest structures
- polygon collision and pushing
- persistent local storage
- saved-board management and import/export UI
- platform brightness, idle-timer, fullscreen, haptics, and orientation adapters
- device cutout/safe-board geometry
- measured geometry profiles for different pyramid generations

## Development

The source is a Flutter app. Flutter 3.47 / Dart 3.13 or newer is the current baseline.

This first rewrite commit intentionally contains only the shared Flutter source and tests. Generate the standard platform runners once on a development machine:

```sh
flutter create . --project-name lighthouse --org com.udeudeude --platforms=ios,android,web
flutter pub get
flutter test
flutter run
```

The generated iOS, Android, and web runners should then be committed once their identifiers and platform settings are reviewed.

## Design rule

Canonical board state is expressed in physical millimeters. Screen pixels or Flutter logical pixels belong only at the calibration/rendering boundary.

See `docs/architecture.md` for the current design decisions.
