import { CanvasPiece, OutfitLayout } from '../model/Wardrobe';

export const CANVAS_BACKGROUNDS: string[] = ['#FFFFFF', '#F3E8EB', '#E7EEF5', '#E9F0E9'];
export const CANVAS_RATIO: number = 1.2;

export function copyLayout(layout: OutfitLayout): OutfitLayout {
  return { background: layout.background, items: layout.items.map((piece: CanvasPiece) => copyPiece(piece)) };
}

export function copyPiece(piece: CanvasPiece): CanvasPiece {
  return { garmentId: piece.garmentId, x: piece.x, y: piece.y, scale: piece.scale, rotation: piece.rotation };
}

function bounded(value: number, low: number, high: number, fallback: number): number {
  return Number.isFinite(value) ? Math.max(low, Math.min(high, value)) : fallback;
}

// 旋转后也约束完整包围盒，避免放大或转动后衣物消失在画布边缘之外。
export function constrainPiece(piece: CanvasPiece): CanvasPiece {
  const result: CanvasPiece = copyPiece(piece);
  result.scale = bounded(result.scale, 0.5, 1.65, 1);
  result.rotation = bounded(result.rotation, -180, 180, 0);
  const angle: number = result.rotation * Math.PI / 180;
  const width: number = 0.38 * result.scale;
  const height: number = 0.44 * result.scale;
  const halfX: number = (Math.abs(Math.cos(angle)) * width + Math.abs(Math.sin(angle)) * height) / 2;
  const halfY: number = (Math.abs(Math.sin(angle)) * width + Math.abs(Math.cos(angle)) * height) / (2 * CANVAS_RATIO);
  result.x = bounded(result.x, halfX, 1 - halfX, 0.5);
  result.y = bounded(result.y, halfY, 1 - halfY, 0.5);
  return result;
}

export function defaultPiece(id: string, index: number): CanvasPiece {
  if (index === 0) { return { garmentId: id, x: 0.28, y: 0.28, scale: 1.05, rotation: 0 }; }
  if (index === 1) { return { garmentId: id, x: 0.72, y: 0.42, scale: 1.05, rotation: 0 }; }
  if (index === 2) { return { garmentId: id, x: 0.32, y: 0.75, scale: 0.9, rotation: 0 }; }
  return constrainPiece({ garmentId: id, x: index % 2 === 0 ? 0.28 : 0.72,
    y: 0.23 + Math.floor(index / 2) * 0.22, scale: index >= 4 ? 0.65 : 0.9, rotation: 0 });
}

// 旧收藏没有 layout；损坏或已移除的单品布局也只局部恢复，不能连带丢失整套作品。
export function normalizeLayout(layout: OutfitLayout | undefined, ids: string[]): OutfitLayout {
  const pieces: CanvasPiece[] = [];
  if (layout && Array.isArray(layout.items)) {
    for (const piece of layout.items) {
      if (piece && ids.indexOf(piece.garmentId) >= 0 && !pieces.some((item: CanvasPiece) => item.garmentId === piece.garmentId)) {
        pieces.push(constrainPiece(piece));
      }
    }
  }
  for (const id of ids) {
    if (!pieces.some((piece: CanvasPiece) => piece.garmentId === id)) { pieces.push(defaultPiece(id, pieces.length)); }
  }
  return { background: layout && CANVAS_BACKGROUNDS.indexOf(layout.background) >= 0 ? layout.background : CANVAS_BACKGROUNDS[0], items: pieces };
}

export class CanvasHistory {
  private past: OutfitLayout[] = [];
  private future: OutfitLayout[] = [];

  record(layout: OutfitLayout): void {
    this.past = this.past.concat([copyLayout(layout)]).slice(-30);
    this.future = [];
  }
  canUndo(): boolean { return this.past.length > 0; }
  canRedo(): boolean { return this.future.length > 0; }
  undo(current: OutfitLayout): OutfitLayout {
    const previous: OutfitLayout | undefined = this.past.pop();
    if (!previous) { return copyLayout(current); }
    this.future.push(copyLayout(current));
    return previous;
  }
  redo(current: OutfitLayout): OutfitLayout {
    const next: OutfitLayout | undefined = this.future.pop();
    if (!next) { return copyLayout(current); }
    this.past.push(copyLayout(current));
    return next;
  }
}
