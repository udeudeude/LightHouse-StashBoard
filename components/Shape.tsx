// components/Shape.tsx

import React, { useRef } from 'react';
import { ShapeState, ShapeType, PyramidSize } from '../types';
import { getSizes, getStrokeWidth, DRAG_THRESHOLD, SCRIBBLE_PATH_THRESHOLD, SCRIBBLE_DISPLACEMENT_THRESHOLD, SNAP_THRESHOLD_DIVISOR, STACK_OUTLINE_WIDTH_DIVISOR } from '../constants';

interface ShapeProps {
  shape: ShapeState;
  allShapes: ShapeState[];
  updateShape: (id: string, newProps: Partial<ShapeState>) => void;
  removeShape: (id: string) => void;
  onShapeCycled: () => void;
  onTwoFingerDrag: () => void;
  dpi: number;
}

const Shape: React.FC<ShapeProps> = ({ shape, allShapes, updateShape, removeShape, onShapeCycled, onTwoFingerDrag, dpi }) => {
  const SIZES = getSizes(dpi);
  const STROKE_WIDTH = getStrokeWidth(dpi);

  const interactionState = useRef<{
    isDragging: boolean;
    touchStart: { x: number; y: number } | null;
    touchCountAtStart: number;
    initialShapePos: { x: number; y: number } | null;
    initialTouchMidpoint: { x: number; y: number } | null;
    lastTouchMidpoint: { x: number; y: number } | null;
    initialAngle: number | null;
    initialShapeRotation: number | null;
    lastTapTime: number;
    path: Array<{ x: number; y: number }> | null;
  }>({
    isDragging: false,
    touchStart: null,
    touchCountAtStart: 0,
    initialShapePos: null,
    initialTouchMidpoint: null,
    lastTouchMidpoint: null,
    initialAngle: null,
    initialShapeRotation: null,
    lastTapTime: 0,
    path: null,
  });

  const handleDoubleClick = (e: React.MouseEvent | React.TouchEvent) => {
    e.stopPropagation();
    onShapeCycled();
    if (shape.size === PyramidSize.Large) {
      removeShape(shape.id);
    } else if (shape.size === PyramidSize.Medium) {
      updateShape(shape.id, { size: PyramidSize.Large });
    } else { // Small
      updateShape(shape.id, { size: PyramidSize.Medium });
    }
  };

  const handleTouchStart = (e: React.TouchEvent) => {
    e.preventDefault();
    e.stopPropagation();

    interactionState.current.touchCountAtStart = e.touches.length;
    interactionState.current.isDragging = false;

    if (e.touches.length === 2) {
      interactionState.current.initialShapePos = { x: shape.x, y: shape.y };
      const [t1, t2] = [e.touches[0], e.touches[1]];
      const midpoint = {
        x: (t1.clientX + t2.clientX) / 2,
        y: (t1.clientY + t2.clientY) / 2,
      };
      interactionState.current.initialTouchMidpoint = midpoint;
      interactionState.current.lastTouchMidpoint = midpoint;
      
      const dx = t2.clientX - t1.clientX;
      const dy = t2.clientY - t1.clientY;
      interactionState.current.initialAngle = Math.atan2(dy, dx) * 180 / Math.PI;
      interactionState.current.initialShapeRotation = shape.rotation;

    } else if (e.touches.length === 1) {
      const touch = e.touches[0];
      interactionState.current.touchStart = { x: touch.clientX, y: touch.clientY };
      interactionState.current.path = [{ x: touch.clientX, y: touch.clientY }];
    }
  };

  const handleTouchMove = (e: React.TouchEvent) => {
    e.preventDefault();
    e.stopPropagation();
    
    if (interactionState.current.touchCountAtStart === 1 && e.touches.length === 1 && interactionState.current.path) {
      interactionState.current.path.push({ x: e.touches[0].clientX, y: e.touches[0].clientY });
    }
    
    if (interactionState.current.touchCountAtStart === 2 && e.touches.length === 2 && interactionState.current.initialShapePos && interactionState.current.initialTouchMidpoint && interactionState.current.initialAngle != null && interactionState.current.initialShapeRotation != null && interactionState.current.lastTouchMidpoint) {
      if (!interactionState.current.isDragging) {
          interactionState.current.isDragging = true;
          onTwoFingerDrag();
      }

      const [t1, t2] = [e.touches[0], e.touches[1]];
      const currentMidpoint = {
        x: (t1.clientX + t2.clientX) / 2,
        y: (t1.clientY + t2.clientY) / 2,
      };
      
      const totalDelta = {
        x: currentMidpoint.x - interactionState.current.initialTouchMidpoint.x,
        y: currentMidpoint.y - interactionState.current.initialTouchMidpoint.y,
      };
      
      let newX = interactionState.current.initialShapePos.x + totalDelta.x;
      let newY = interactionState.current.initialShapePos.y + totalDelta.y;
      
      const currentDx = t2.clientX - t1.clientX;
      const currentDy = t2.clientY - t1.clientY;
      const currentAngle = Math.atan2(currentDy, currentDx) * 180 / Math.PI;
      const angleDelta = currentAngle - interactionState.current.initialAngle;
      const gestureRotation = interactionState.current.initialShapeRotation + angleDelta;
      let finalRotation = gestureRotation;
      
      let snappedToId = null;

      const otherShapes = allShapes.filter(s => s.id !== shape.id);
      for (const other of otherShapes) {
          const dist = Math.sqrt(Math.pow(newX - other.x, 2) + Math.pow(newY - other.y, 2));
          const snapThreshold = SIZES[other.size].base / SNAP_THRESHOLD_DIVISOR;

          if (dist < snapThreshold && shape.type === other.type) {
              if (shape.size !== other.size) { // Snap
                  newX = other.x;
                  newY = other.y;
                  finalRotation = other.rotation; // Adopt rotation of the snapped-to shape
                  snappedToId = other.id;
                  break; 
              } else { // Push
                  const moveDelta = {
                      x: currentMidpoint.x - interactionState.current.lastTouchMidpoint.x,
                      y: currentMidpoint.y - interactionState.current.lastTouchMidpoint.y,
                  };
                  const otherNewX = other.x + moveDelta.x;
                  const otherNewY = other.y + moveDelta.y;

                  // After pushing the other shape, correct the current shape's position to prevent overlap
                  const vecX = newX - otherNewX;
                  const vecY = newY - otherNewY;
                  const vecDist = Math.sqrt(vecX * vecX + vecY * vecY);
                  const minDist = SIZES[shape.size].base; // They are the same size

                  if (vecDist < minDist && vecDist > 0) {
                      newX = otherNewX + (vecX / vecDist) * minDist;
                      newY = otherNewY + (vecY / vecDist) * minDist;
                  }

                  updateShape(other.id, { x: otherNewX, y: otherNewY });
              }
          }
      }

      updateShape(shape.id, {
        x: newX,
        y: newY,
        rotation: finalRotation,
        isStackedOn: snappedToId,
      });

      interactionState.current.lastTouchMidpoint = currentMidpoint;
    }
  };

  const handleTouchEnd = (e: React.TouchEvent) => {
    e.preventDefault();
    e.stopPropagation();

    const { touchStart, touchCountAtStart, path } = interactionState.current;

    if (touchCountAtStart === 1 && touchStart && e.changedTouches.length === 1) {
      const touch = e.changedTouches[0];
      const dx = touch.clientX - touchStart.x;
      const dy = touch.clientY - touchStart.y;
      const displacement = Math.sqrt(dx * dx + dy * dy);

      let pathLength = 0;
      if (path && path.length > 1) {
        for (let i = 1; i < path.length; i++) {
          pathLength += Math.sqrt(Math.pow(path[i].x - path[i-1].x, 2) + Math.pow(path[i].y - path[i-1].y, 2));
        }
      }

      if (shape.type === ShapeType.Square && pathLength > SCRIBBLE_PATH_THRESHOLD && displacement < SCRIBBLE_DISPLACEMENT_THRESHOLD) {
        updateShape(shape.id, { isFilled: !shape.isFilled });
      }
      else if (displacement > DRAG_THRESHOLD) {
        const angleRad = -shape.rotation * (Math.PI / 180);
        const unrotatedDx = dx * Math.cos(angleRad) - dy * Math.sin(angleRad);
        const unrotatedDy = dx * Math.sin(angleRad) + dy * Math.cos(angleRad);

        const { base, height } = SIZES[shape.size];

        if (shape.type === ShapeType.Square) {
          let hingeRotation = 0;
          let shiftX = 0, shiftY = 0;

          if (Math.abs(unrotatedDx) > Math.abs(unrotatedDy)) { // Horizontal drag
            shiftX = (unrotatedDx > 0 ? 1 : -1) * (base / 2 + height / 2);
            hingeRotation = unrotatedDx > 0 ? 90 : 270;
          } else { // Vertical drag
            shiftY = (unrotatedDy > 0 ? 1 : -1) * (base / 2 + height / 2);
            hingeRotation = unrotatedDy > 0 ? 180 : 0;
          }
          const rotRad = shape.rotation * (Math.PI / 180);
          const rotatedShiftX = shiftX * Math.cos(rotRad) - shiftY * Math.sin(rotRad);
          const rotatedShiftY = shiftX * Math.sin(rotRad) + shiftY * Math.cos(rotRad);

          updateShape(shape.id, {
            type: ShapeType.Triangle, rotation: (shape.rotation + hingeRotation) % 360,
            x: shape.x + rotatedShiftX, y: shape.y + rotatedShiftY,
          });
        } else { // Triangle
          if (unrotatedDy > DRAG_THRESHOLD) {
            // A drag "down" (positive unrotatedDy) on a triangle flips it over its base
            // The shift amount is half the triangle's height plus half the new square's base
            const shiftY = (height / 2 + base / 2);
            const rotRad = shape.rotation * (Math.PI / 180);
            
            // Rotate the vertical shift vector to world space
            const rotatedShiftX = -shiftY * Math.sin(rotRad);
            const rotatedShiftY = shiftY * Math.cos(rotRad);
            
            updateShape(shape.id, { type: ShapeType.Square, x: shape.x + rotatedShiftX, y: shape.y + rotatedShiftY });
          }
        }
      } else {
        const now = new Date().getTime();
        const timeSinceLastTap = now - interactionState.current.lastTapTime;
        if (timeSinceLastTap < 300 && timeSinceLastTap > 0) {
            handleDoubleClick(e);
            interactionState.current.lastTapTime = 0;
        } else {
            interactionState.current.lastTapTime = now;
        }
      }
    }
    
    if (e.touches.length === 0) {
        interactionState.current = { ...interactionState.current, isDragging: false, touchStart: null, touchCountAtStart: 0, initialShapePos: null, initialTouchMidpoint: null, lastTouchMidpoint: null, initialAngle: null, initialShapeRotation: null, path: null};
    }
  };

  const { base, height } = SIZES[shape.size];
  const displaySize = Math.max(base, height) * 1.2 + STROKE_WIDTH;

  const renderShape = () => {
    const isStacked = !!shape.isStackedOn;
    const stackOutlineWidth = STROKE_WIDTH / STACK_OUTLINE_WIDTH_DIVISOR;

    if (shape.type === ShapeType.Square) {
      return (
        <>
          {isStacked && <rect x={-base/2} y={-base/2} width={base} height={base} fill="transparent" stroke="gray" strokeWidth={stackOutlineWidth} />}
          <rect x={-base/2} y={-base/2} width={base} height={base} fill={shape.isFilled ? 'white' : 'transparent'} stroke="white" strokeWidth={STROKE_WIDTH} />
        </>
      );
    } else { // Triangle
      const points = `${-base / 2},${height / 2} ${base / 2},${height / 2} 0,${-height / 2}`;
      return (
        <>
          {isStacked && <polygon points={points} fill="transparent" stroke="gray" strokeWidth={stackOutlineWidth} />}
          <polygon points={points} fill="white" />
        </>
      );
    }
  };

  return (
    <div
      className="absolute"
      style={{ left: shape.x, top: shape.y, width: 0, height: 0, touchAction: 'none' }}
      onDoubleClick={handleDoubleClick}
      onTouchStart={handleTouchStart}
      onTouchMove={handleTouchMove}
      onTouchEnd={handleTouchEnd}
    >
        <div 
          className="absolute transform -translate-x-1/2 -translate-y-1/2"
          style={{ transform: `translate(-50%, -50%) rotate(${shape.rotation}deg)` }}
        >
            <svg
                width={displaySize}
                height={displaySize}
                viewBox={`${-displaySize / 2} ${-displaySize / 2} ${displaySize} ${displaySize}`}
                className="overflow-visible pointer-events-auto"
            >
                {renderShape()}
            </svg>
        </div>
    </div>
  );
};

export default Shape;