# LightHouse

LightHouse is an interactive illuminated physical play surface for Looney Pyramids. The screen and the physical plastic pieces together form the interface.

## Current development

A clean-sheet Flutter rewrite is under active development on the [`lighthouse-2-rewrite`](../../tree/lighthouse-2-rewrite) branch and in draft pull request #1.

The application code remaining on `main` is the original 2025 React / Google AI Studio prototype, preserved as development history. **LightHouse does not require Gemini or any other AI service.** The old AI Studio instructions previously shown here were generated scaffolding and were not part of the actual application.

## LightHouse 2

The rewrite is designed around physical dimensions rather than screen pixels. Its current implementation includes:

- board geometry stored in millimeters
- automatic physical-size calibration for recognized iPhone models, with manual calibration fallback
- Small, Medium, and Large Looney Pyramid light footprints
- upright and flat footprints
- full and wall-only illumination for upright pyramids
- touch interactions for creation, resizing, tipping/standing, moving, rotating, and changing illumination
- command-based undo/redo
- local autosave
- iOS, Android, and web targets
- automated analysis and tests

The first development target is accurate physical alignment and interaction on an iPhone. Android and browser distribution are planned from the same Flutter codebase.

See the rewrite branch for the current source and architecture documentation.
