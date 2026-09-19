import { DemoSnapshot, Garment, OutfitRequest, emptyProfile } from '../model/Wardrobe';
import { eligible } from '../service/OutfitEngine';

export interface CardData {
  caption: string;
  garmentName: string;
  imageKey: string;
  count: number;
  hasOutfit: boolean;
}

export function activeGarments(snapshot: DemoSnapshot): Garment[] {
  // 卡片只判断“这几件还能不能穿”，与偏好档案无关，因此传入空档案。
  const request: OutfitRequest = { occasion: snapshot.occasion, temperature: snapshot.temperature,
    lockedIds: [], excludedIds: [], profile: emptyProfile() };
  const items: Garment[] = [];
  for (const id of snapshot.activeIds) {
    const item: Garment | undefined = snapshot.garments.find((entry: Garment) => entry.id === id);
    if (!item || !eligible(item, request)) { return []; }
    items.push(item);
  }
  return items;
}

export function cardData(snapshot: DemoSnapshot): CardData {
  const items: Garment[] = activeGarments(snapshot);
  return { caption: snapshot.occasion + ' · ' + snapshot.temperature + '℃',
    garmentName: items.length > 0 ? items[0].name : '暂无可用搭配',
    imageKey: items.length > 0 ? items[0].imageKey : '', count: items.length, hasOutfit: items.length > 0 };
}

export function cardImage(key: string): Resource {
  switch (key) {
    case 'shirt': return $r('app.media.demo_shirt');
    case 'jeans': return $r('app.media.demo_jeans');
    case 'shoes': return $r('app.media.demo_sneakers');
    case 'jacket': return $r('app.media.demo_jacket');
    case 'graphic': return $r('app.media.demo_knit');
    default: return $r('app.media.demo_tee');
  }
}
