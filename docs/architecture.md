# LightHouse 2 architecture

## Product model

LightHouse is an illuminated physical play surface. A rendered light element may correspond to a pyramid already on the screen, a target for a future pyramid, or simply a useful illuminated marker.

## Coordinate system

All canonical positions and geometry use millimeters. Calibration supplies only a `logicalPixelsPerMm` transform at the presentation boundary.

Saved board files must never contain device pixels, logical pixels, DPI, or a particular phone/tablet resolution.

## Domain object

The initial primitive is `LightElement`, not a simulated pyramid and not a rendered square/triangle.

A light element has:

- pyramid size
- upright or flat pose
- physical position in millimeters
- heading
- illumination pattern

For upright elements, `full` illuminates the whole base footprint and `wall` illuminates a perimeter band. Flat elements currently render as solid triangles. This asymmetry is deliberate pending physical experiments.

## Geometry profiles

Physical dimensions are supplied by `PyramidGeometryProfile`. The first profile preserves the dimensions used in the 2025 prototype. Future measured profiles can support newer pyramid generations or user calibration without changing board documents.

## Commands and history

Semantic board changes are commands. Commands can apply and revert themselves, which makes undo/redo, deterministic tests, journaling, and eventual synchronization possible.

## Gesture boundary

Gesture interpretation belongs at the presentation boundary; mutations belong in `BoardController`. Gesture thresholds should be expressed in millimeters after calibration.

The current gesture mapping is intentionally provisional and will change through physical testing with real pyramids.

## Rendering

The board uses one custom painter. Rendering derives squares and triangles from domain pose and geometry. Rendered geometry is not stored in board state.

## Persistence

`BoardState` has a versioned JSON representation. Durable local storage, atomic journaling, and save/load UI are deferred until the board model settles.

## Platform strategy

Shared domain, interaction, rendering, and UI code use Flutter/Dart. Small native adapters will handle capabilities where Flutter or browsers cannot provide equivalent behavior, including brightness, screen wake, immersive presentation, orientation behavior, system gestures, and haptics.
