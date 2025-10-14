// types.ts

export enum PyramidSize {
  Small = 'small',
  Medium = 'medium',
  Large = 'large',
}

export enum ShapeType {
  Square = 'square',
  Triangle = 'triangle',
}

export interface ShapeState {
  id: string;
  type: ShapeType;
  size: PyramidSize;
  x: number;
  y: number;
  rotation: number;
  isFilled?: boolean;
  isStackedOn?: string | null;
}
