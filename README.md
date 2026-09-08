# LightHouse

LightHouse is an interactive illuminated physical play surface for Looney Pyramids. The screen and the physical plastic pieces together form the interface.

## Try LightHouse 2

The current Flutter rewrite is continuously deployed for browser testing:

https://udeudeude.github.io/LightHouse-StashBoard/

The browser build requires manual physical calibration. Native iOS can automatically calibrate recognized iPhone models; Android can use reported physical display DPI when trustworthy.

## Current development

A clean-sheet Flutter rewrite is under active development on the [`lighthouse-2-rewrite`](../../tree/lighthouse-2-rewrite) branch and in draft pull request #1.

The application code remaining on `main` is the original 2025 React / Google AI Studio prototype, preserved as development history. **LightHouse does not require Gemini or any other AI service.** The old AI Studio instructions previously shown here were generated scaffolding and were not part of the actual application.

## LightHouse 2

The rewrite is designed around physical dimensions rather than screen pixels. It currently includes:

- board geometry and gesture tolerances stored in millimeters
- automatic and manual physical-size calibration
- Small, Medium, and Large light footprints
- upright/flat pose and full/wall-only upright illumination
- create, resize/delete, tip/stand, scribble, translate, and rotate interactions
- desktop mouse interaction for browser testing
- stack/nest structures with independently illuminated members
- deterministic polygon collision/pushing
- command-based undo/redo
- autosave with recovery backup
- named saved boards and JSON import/export
- native screen-awake, brightness, haptic, orientation, and safe-display behavior
- installable PWA behavior
- iOS, Android, and web targets
- automated formatting, analysis, tests, and platform build validation

See the rewrite branch for the current source, architecture documentation, and changelog.

## License

MIT.
