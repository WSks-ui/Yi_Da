import { Category, Garment, OCCASIONS, Outfit, OutfitRequest } from '../model/Wardrobe';
import { eligible, makeOutfit } from './OutfitEngine';

export enum DadaState { IDLE = 'idle', WORKING = 'working', COMPLETE = 'complete', ERROR = 'error' }
export enum DadaPage {
  TODAY = 'today', WARDROBE = 'wardrobe', OUTFIT = 'outfit', IMPORT = 'import', TRY_ON = 'tryOn',
  DIY = 'diy', DETAIL = 'detail', DIARY = 'diary', PROFILE = 'profile'
}
export enum DadaAction {
  RECOMMEND = 'recommend', ANALYZE = 'analyze', USE_COLOR = 'useColor', USE_CATEGORY = 'useCategory',
  OPEN_IMPORT = 'openImport', TRY_ON = 'tryOn', COMPARE = 'compare', GUIDE = 'guide'
}
export interface DadaContext { page: DadaPage; key: string; objectId: string; }
export interface DadaShortcut { label: string; action: DadaAction; input: string; }
export interface AssistantProposal { id: number; contextKey: string; occasion: string; temperature: number; outfits: Outfit[]; }
export const DADA_WELCOME: string = '我是搭搭，用你已有的衣物，帮你找到合适的穿搭。';
export const TRY_ON_BOUNDARY: string = '固定离线样片 · 非实时生成';

export function dadaGuide(page: DadaPage): string {
  if (page === DadaPage.IMPORT) { return '我可以分析当前照片，给出颜色和品类建议。请分别确认建议，再用录入页的保存按钮保存衣物。'; }
  if (page === DadaPage.TRY_ON) { return '选择一组配套人像与服装，让我带你体验试穿过程。这里展示固定离线样片，非实时生成。'; }
  if (page === DadaPage.WARDROBE) { return '可以按名称搜索、筛选品类和状态，或多选衣物整理状态。我也能用已有衣物为你搭配。'; }
  if (page === DadaPage.DIY) { return '点选单品加入画布，拖动、缩放和旋转组成搭配。编辑完成后，请用画布上的保存按钮保存作品。'; }
  if (page === DadaPage.DETAIL) { return '这里可以查看搭配理由、收藏组合、记录穿着，或进入 DIY 继续编辑。试穿入口提供独立的固定样片。'; }
  if (page === DadaPage.DIARY) { return '点新增记录留下今天的穿搭。已有记录可以回看或删除，相关修改仍需你在日记页确认。'; }
  if (page === DadaPage.PROFILE) { return '你可以完善穿搭偏好和身材档案、查看试穿记录，或用迁移文件备份衣橱。'; }
  return '说说场合和温度，我会先给你方案。点击“采用这套”后，才会更新当前搭配。';
}

export function dadaShortcuts(page: DadaPage): DadaShortcut[] {
  if (page === DadaPage.IMPORT) {
    return [{ label: '分析这张照片', action: DadaAction.ANALYZE, input: '' },
      { label: '采用颜色建议', action: DadaAction.USE_COLOR, input: '' },
      { label: '采用品类建议', action: DadaAction.USE_CATEGORY, input: '' },
      { label: '哪些字段要填写', action: DadaAction.GUIDE, input: '' }];
  }
  if (page === DadaPage.TRY_ON) {
    return [{ label: '牛仔半裙', action: DadaAction.TRY_ON, input: 'denim_skirt' },
      { label: '深蓝上衣', action: DadaAction.TRY_ON, input: 'navy_top' },
      { label: '红色连衣裙', action: DadaAction.TRY_ON, input: 'red_dress' },
      { label: '查看原图对比', action: DadaAction.COMPARE, input: '' }];
  }
  if (page === DadaPage.DIY || page === DadaPage.DETAIL || page === DadaPage.DIARY || page === DadaPage.PROFILE) {
    return [{ label: '这里怎么用', action: DadaAction.GUIDE, input: '' }];
  }
  const prompts: string[] = ['今天怎么穿', '正式一点', '换一件上装', '再来一套'];
  const result: DadaShortcut[] = prompts.map((input: string): DadaShortcut =>
    ({ label: input, action: DadaAction.RECOMMEND, input: input }));
  if (page === DadaPage.WARDROBE) {
    result.push({ label: '录入衣物', action: DadaAction.OPEN_IMPORT, input: '' });
    result.push({ label: '整理衣橱怎么用', action: DadaAction.GUIDE, input: '' });
  }
  return result;
}

// 使用原推荐引擎的硬约束重新验证确切单品组合，不以“仍在前三个推荐中”作为合法依据。
// 用户可能经多轮替换得到其它合法组合；状态、温度、锁定和排除变化时则必须拒绝旧提案。
export function validateAssistantOutfit(look: Outfit, garments: Garment[], request: OutfitRequest): Outfit | undefined {
  if (!Number.isFinite(request.temperature) || request.temperature < -20 || request.temperature > 45 ||
    OCCASIONS.indexOf(request.occasion) < 0 || look.garmentIds.length === 0) { return undefined; }
  const chosen: Garment[] = [];
  for (const id of look.garmentIds) {
    const item: Garment | undefined = garments.find((entry: Garment) => entry.id === id);
    if (item === undefined || !eligible(item, request) || chosen.some((entry: Garment) => entry.category === item.category)) {
      return undefined;
    }
    chosen.push(item);
  }
  if (request.lockedIds.some((id: string) => look.garmentIds.indexOf(id) < 0)) { return undefined; }
  const required: Category[] = [Category.TOP, Category.BOTTOM, Category.SHOES];
  if (request.temperature < 18) { required.push(Category.OUTER); }
  if (required.some((category: Category) => !chosen.some((item: Garment) => item.category === category))) { return undefined; }
  return makeOutfit(chosen, request, request.profile);
}
