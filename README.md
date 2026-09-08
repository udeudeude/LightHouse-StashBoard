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
- manual ruler calibration with a fixed left endpoint
- manual calibration using the base of a real Large pyramid
- quick physical-size verification from the board
- upright Small, Medium, and Large light footprints
- full and wall-only upright illumination
- flat pyramid rendering
- double-tap empty board to create a Small upright footprint
- double-tap a footprint to cycle Small -> Medium -> Large -> delete
- scribble over an upright footprint to toggle full/wall illumination
- one-finger directional drag to tip an upright footprint or stand a flat footprint
- two-finger translate and rotate
- mouse drag to translate on desktop; Shift-drag to rotate
- explicit interaction halos in physical millimeters
- pointer-cancel recovery
- stack/nest structure records with independently illuminated member footprints
- coherent movement and rotation of grouped structures
- deterministic convex-polygon collision separation for same-size pushing
- command-based undo/redo, including structure operations
- versioned JSON board serialization with v1 migration
- local autosave with a backup copy for recovery
- named saved boards
- save-a-copy, rename, load, and delete saved boards
- JSON copy/paste import and export
- screen-awake behavior during play
- native application-brightness control with lifecycle reset
- haptic feedback for important manipulations
- orientation lock while a board is active, with restoration on exit
- safe-board insets around display cutouts/system-reserved regions
- installable PWA metadata and iOS Add-to-Home-Screen guidance
- generated iOS, Android, and web platform runners
- automated formatting, static analysis, tests, unsigned iOS build validation, and GitHub Pages deployment

## Interaction notes

Touch:

- Double tap empty space: create Small
- Double tap a footprint: Small -> Medium -> Large -> delete
- One-finger directional drag: tip / stand
- Scribble and return near the starting point: full <-> wall-only illumination
- Two-finger drag/rotate: translate and rotate
- Tap: select a footprint for structure actions

Desktop:

- Double click mirrors double tap
- Click selects
- Mouse drag moves a footprint or structure
- Shift + mouse drag rotates it

A selected footprint exposes structure actions for snapping into a nearby stack/nest, changing the structure kind, or detaching the footprint.

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
