// constants.ts

import { PyramidSize } from './types';

// New dimensions in inches, converted to pixels via a DPI-aware function
export const getSizes = (dpi: number) => ({
  [PyramidSize.Small]: {
    base: (9 / 16) * dpi,      // 0.5625 inches
    height: 1 * dpi,           // 1.0 inches
  },
  [PyramidSize.Medium]: {
    base: (25 / 32) * dpi,     // 0.78125 inches
    height: (1 + 3 / 8) * dpi, // 1.375 inches
  },
  [PyramidSize.Large]: {
    base: 1 * dpi,             // 1.0 inches
    height: (1 + 3 / 4) * dpi, // 1.75 inches
  },
});

export const getStrokeWidth = (dpi: number) => (1 / 8) * dpi; // 0.125 inches

export const DRAG_THRESHOLD = 20; // pixels
export const SCRIBBLE_PATH_THRESHOLD = 80; // pixels, lowered for easier activation
export const SCRIBBLE_DISPLACEMENT_THRESHOLD = 25; // pixels, raised to allow more movement

// The distance, as a fraction of a shape's base size, to trigger a snap or push.
export const SNAP_THRESHOLD_DIVISOR = 2; 

// The thickness of the stack indicator outline, as a fraction of the main stroke width.
export const STACK_OUTLINE_WIDTH_DIVISOR = 3;