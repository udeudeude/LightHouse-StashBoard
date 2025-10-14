// components/Board.tsx

import React, { useState, useCallback, useRef, useEffect } from 'react';
import { ShapeState, PyramidSize, ShapeType } from '../types';
import Shape from './Shape';
import SettingsIcon from './icons/SettingsIcon';

interface BoardProps {
  dpi: number;
  onRecalibrate: () => void;
}

const ACTION_STORAGE_PREFIX = 'lighthouse-action-count-';
const MAX_ACTION_DISPLAYS = 2;

const useActionTracker = (actionName: string) => {
    const key = `${ACTION_STORAGE_PREFIX}${actionName}`;
    const [count, setCount] = useState(() => parseInt(localStorage.getItem(key) || '0', 10));

    const increment = useCallback(() => {
        setCount(prevCount => {
            const newCount = prevCount + 1;
            localStorage.setItem(key, newCount.toString());
            return newCount;
        });
    }, [key]);

    return { count, increment };
};


const Board: React.FC<BoardProps> = ({ dpi, onRecalibrate }) => {
  const [shapes, setShapes] = useState<ShapeState[]>([]);
  const lastTap = useRef(0);
  
  const createAction = useActionTracker('create');
  const cycleAction = useActionTracker('cycle');
  const moveAction = useActionTracker('move');

  const addShapeAtPosition = (x: number, y: number) => {
    const newShape: ShapeState = {
      id: crypto.randomUUID(),
      type: ShapeType.Square,
      size: PyramidSize.Small,
      x,
      y,
      rotation: 0,
      isFilled: false,
    };
    setShapes(prevShapes => [...prevShapes, newShape]);
    createAction.increment();
  };
  
  const handleDoubleClick = (e: React.MouseEvent<HTMLDivElement>) => {
    addShapeAtPosition(e.clientX, e.clientY);
  };

  const handleTouchStart = (e: React.TouchEvent<HTMLDivElement>) => {
    e.preventDefault();
  }

  const handleTouchEnd = (e: React.TouchEvent<HTMLDivElement>) => {
    e.preventDefault();
    if (e.target !== e.currentTarget) return;

    const now = new Date().getTime();
    const timeSinceLastTap = now - lastTap.current;

    if (timeSinceLastTap < 300 && timeSinceLastTap > 0) {
      const touch = e.changedTouches[0];
      addShapeAtPosition(touch.clientX, touch.clientY);
      lastTap.current = 0;
    } else {
      lastTap.current = now;
    }
  };


  const updateShape = useCallback((id: string, newProps: Partial<ShapeState>) => {
    setShapes(prevShapes =>
      prevShapes.map(shape =>
        shape.id === id ? { ...shape, ...newProps } : shape
      )
    );
  }, []);

  const removeShape = useCallback((id: string) => {
    setShapes(prevShapes => prevShapes.filter(shape => shape.id !== id));
    cycleAction.increment(); // Removing a shape is the end of its cycle
  }, [cycleAction]);

  return (
    <div
      className="w-full h-full relative cursor-pointer"
      onDoubleClick={handleDoubleClick}
      onTouchStart={handleTouchStart}
      onTouchEnd={handleTouchEnd}
    >
        <div className="absolute top-4 left-1/2 -translate-x-1/2 text-gray-600 text-center text-sm font-sans pointer-events-none z-10 transition-opacity duration-500"
            style={{ opacity: (createAction.count < MAX_ACTION_DISPLAYS || cycleAction.count < MAX_ACTION_DISPLAYS || moveAction.count < MAX_ACTION_DISPLAYS) ? 1 : 0 }}
        >
            {createAction.count < MAX_ACTION_DISPLAYS && <p>Double-tap empty space to create a small square.</p>}
            {cycleAction.count < MAX_ACTION_DISPLAYS && <p>Double-tap a shape to cycle from Small → Medium → Large → Off.</p>}
            {moveAction.count < MAX_ACTION_DISPLAYS && <p>Two-finger drag to move and rotate.</p>}
        </div>
        <button
            onClick={onRecalibrate}
            className="absolute bottom-4 right-4 text-gray-600 hover:text-white transition-colors z-20"
            aria-label="Recalibrate screen size"
        >
            <SettingsIcon />
        </button>
      {shapes.map(shape => (
        <Shape
          key={shape.id}
          shape={shape}
          allShapes={shapes}
          updateShape={updateShape}
          removeShape={removeShape}
          onShapeCycled={cycleAction.increment}
          onTwoFingerDrag={moveAction.increment}
          dpi={dpi}
        />
      ))}
    </div>
  );
};

export default Board;