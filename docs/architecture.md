# LightHouse 2 architecture

## Product model

LightHouse is an illuminated physical play surface. A rendered light element may correspond to a pyramid already on the screen, a target for a future pyramid, or simply a useful illuminated marker. The screen and the real plastic pieces jointly form the interface.

## Coordinate system

All canonical positions, collision geometry, interaction halos, and gesture thresholds use millimeters. Calibration supplies only a `logicalPixelsPerMm` transform at the presentation boundary.

Saved board files must never contain device pixels, logical pixels, DPI, or a particular phone/tablet resolution.

## Light elements

The primitive is `LightElement`, not a simulated pyramid and not a rendered square/triangle.

A light element has:

- pyramid size
- upright or flat pose
- physical position in millimeters
- heading
- illumination pattern

For upright elements, `full` illuminates the whole base footprint and `wall` illuminates a perimeter band. Flat elements currently render as solid triangles. This asymmetry is deliberate pending a demonstrated physical use for multiple flat illumination patterns.

## Structures

`LightStructure` groups co-located light elements representing the individually addressable footprints within a physical stack or nest. The member elements retain their own illumination patterns. Structure membership affects manipulation, not rendering ownership: each constituent footprint remains independently renderable and serializable.

Structure invariants:

- a member belongs to at most one structure
- a structure contains at least two members
- automatic snapping rejects duplicate pyramid sizes
- moving or rotating one member manipulates the whole structure coherently
- detaching a member does not erase its light footprint

Stack versus nest is stored explicitly even though an upright screen footprint alone cannot infer which physical arrangement the user has made.

## Geometry profiles

Physical dimensions are supplied by `PyramidGeometryProfile`. The first profile preserves the dimensions used in the 2025 prototype. Future measured profiles can support newer pyramid generations or user-measured sets without changing board documents.

## Collision and pushing

Collision uses deterministic convex polygon geometry rather than a physics engine. Upright footprints are oriented squares and flat footprints are oriented triangles. The separating-axis theorem supplies a minimum separation vector when same-size pieces overlap after a manipulation. This moves the obstructing light geometry without introducing simulated momentum, gravity, bounce, or other physics that would compete with the real plastic pieces.

## Commands and history

Semantic board changes are commands. Commands can apply and revert themselves. Multi-element operations such as structure moves and snaps use atomic board-state commands, so undo/redo cannot leave half a structure changed.

## Gesture boundary

Gesture interpretation belongs at the presentation boundary; domain mutation belongs in `BoardController`. Gesture thresholds are expressed in millimeters after calibration.

Current touch vocabulary:

- double tap empty board: create Small
- double tap footprint: cycle size / delete
- one-finger directional drag: tip or stand
- scribble returning near its origin: switch full/wall illumination
- two-finger transform: translate and rotate
- tap: select for explicit structure operations

Desktop testing adds mouse drag to translate and Shift-drag to rotate.

Pointer cancellation restores any in-progress transform rather than committing an interrupted state.

## Calibration

Native iOS uses a known device-model PPI table when available. Android requests reported physical x/y DPI from a tiny platform channel and accepts only plausible values. Web calibration is manual because browser CSS units are not a trustworthy statement of real physical size.

Manual calibration supports both a fixed-end ruler reference and matching the base of a real Large pyramid. Manual calibration is persisted locally and can be verified quickly from the board.

## Rendering and safe board surface

The board uses one custom painter. Rendering derives squares and triangles from domain pose and geometry. Rendered geometry is never stored in board state.

The interactive canvas is inset by the platform's persistent display padding so physical pieces are not invited into notches, rounded-corner exclusions, home-indicator regions, or comparable cutouts.

## Persistence

Board document format version 2 contains title, elements, and structures. Version 1 documents migrate on read.

The current board autosaves after semantic changes. Before overwriting the current snapshot, the previous snapshot is retained as a recovery backup. Named boards are stored separately. Public interchange is indented JSON and deliberately contains no Flutter implementation details.

## Device behavior

During active play the native app:

- prevents idle sleep
- requests immersive presentation
- locks the current orientation to avoid moving a physical setup underneath the pieces
- can control application brightness without changing system brightness permanently
- resets application brightness when leaving or backgrounding the board
- uses restrained haptic feedback for discrete manipulations

Capabilities unavailable on web degrade cleanly rather than constraining the native apps.

## Distribution

One Flutter project targets iOS, Android, and web. GitHub Pages deploys the browser build for immediate testing and BoardGameGeek-style sharing. Native builds remain authoritative for physical calibration and device-control behavior.
