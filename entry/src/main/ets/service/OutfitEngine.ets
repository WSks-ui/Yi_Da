import { Category, Garment, GarmentStatus, Outfit, OutfitRequest, PreferenceProfile, Recommendation } from '../model/Wardrobe';
import { analyzeBodyProfile, BodyAnalysisResult, bodyFitScore } from './BodyAnalysis';

// 允许页面显式传入已计算结果；不传时从请求里的身材档案计算，旧调用继续走空分析。
export { bodyFitScore } from './BodyAnalysis';

function resolveBodyAnalysis(request: OutfitRequest, provided?: BodyAnalysisResult): BodyAnalysisResult {
  if (provided !== undefined) { return provided; }
  if (request.body !== undefined) { return analyzeBodyProfile(request.body); }
  if (request.profile.body !== undefined) { return analyzeBodyProfile(request.profile.body); }
  return analyzeBodyProfile(undefined);
}

function bodyReason(analysis: BodyAnalysisResult): string {
  if (analysis.confidence <= 0 || analysis.knownFields.length === 0) { return ''; }
  const summary: string = analysis.summary.trim();
  const advice: string = (analysis.recommendationSummary || '').trim();
  if (summary.length > 0 && advice.length > 0 && summary !== advice) { return summary + advice; }
  return summary.length > 0 ? summary : advice;
}

function rankingContext(request: OutfitRequest, candidates: Garment[]): Outfit {
  return { id: 'ranking_context', garmentIds: candidates.map((item: Garment) => item.id),
    occasion: request.occasion, temperature: request.temperature, reason: '', name: '',
    isCustom: false, savedAt: '' };
}

export function eligible(item: Garment, request: OutfitRequest): boolean {
  return item.status === GarmentStatus.READY && request.excludedIds.indexOf(item.id) < 0 &&
    item.minTemp <= request.temperature && item.maxTemp >= request.temperature &&
    item.occasions.indexOf(request.occasion) >= 0;
}

// 偏好只调整候选顺序，不把衣物过滤掉：档案没填或填得少时，衣橱仍然可用。
// 这正是设计文稿里“可修改的多个维度”，而不是把用户锁进一种风格。
export function preferenceScore(item: Garment, profile: PreferenceProfile): number {
  let score: number = 0;
  // 单件反馈只影响排序，不改变 eligible 的硬约束；绝不因为“多推荐”
  // 把待洗、温度不合适或场合不符的衣物重新塞回方案。
  const recommendationBias: number = item.recommendationBias === 1 ? 1 :
    item.recommendationBias === -1 ? -1 : 0;
  score += recommendationBias * 4;
  if (profile.fits.indexOf(item.fit) >= 0) { score += 2; }
  if (profile.palettes.indexOf(item.palette) >= 0) { score += 2; }
  if (profile.styles.indexOf(item.style) >= 0) { score += 2; }
  // 叠穿与配饰接受度：接受叠穿时给可叠穿单品加分，不接受时不加分也不排除。
  if (profile.layering >= 1 && item.layering) { score += 1; }
  if (profile.layering <= -1 && !item.layering) { score += 1; }
  // 图案接受度：明确不喜欢图案时降低图案单品的顺序。
  if (profile.accessories <= -1 && item.pattern) { score -= 1; }
  if (profile.priority === '舒适' && item.layering) { score += 1; }
  if (profile.priority === '正式感' && (item.style === '通勤' || item.fit === '有轮廓感')) { score += 1; }
  if (profile.priority === '个性表达' && item.pattern) { score += 1; }
  return score;
}

export function makeOutfit(items: Garment[], request: OutfitRequest, profile: PreferenceProfile,
  analysis?: BodyAnalysisResult): Outfit {
  const ids: string[] = items.map((item: Garment) => item.id);
  const hasOuter: boolean = items.some((item: Garment) => item.category === Category.OUTER);
  const matched: number = items.filter((item: Garment) => preferenceScore(item, profile) > 0).length;
  const bodyText: string = bodyReason(analysis === undefined ? resolveBodyAnalysis(request) : analysis);
  return {
    id: ids.join('_') + '_' + request.occasion + '_' + request.temperature,
    garmentIds: ids, occasion: request.occasion, temperature: request.temperature,
    reason: `${request.temperature}℃ · ${request.occasion}，${items.length} 件衣物均为可穿状态，且符合已确认的温度与场合条件。` +
      (hasOuter ? '加入外套应对偏凉天气。' : '轻装出门，减少不必要的叠穿。') +
      (profile.completed ? `其中 ${matched} 件与你的偏好档案相符。` : '') +
      (bodyText.length > 0 ? `体型建议：${bodyText}` : ''),
    name: '', isCustom: false, savedAt: ''
  };
}

// 手搭方案：用户自己选好单品后生成，用自己的理由文案，不走推荐规则。
// 这里只做必要的可穿性校验，避免把已归档或待洗的衣物搭进方案。
export function customOutfit(items: Garment[], request: OutfitRequest, name: string): Outfit {
  const ids: string[] = items.map((item: Garment) => item.id);
  const unusable: Garment[] = items.filter((item: Garment) => item.status !== GarmentStatus.READY);
  const outside: Garment[] = items.filter((item: Garment) =>
    item.minTemp > request.temperature || item.maxTemp < request.temperature);
  let reason: string = `自己搭的 ${items.length} 件组合。`;
  if (unusable.length > 0) {
    reason += `${unusable.map((item: Garment) => item.name).join('、')}当前不是可穿状态。`;
  }
  if (outside.length > 0) {
    reason += `${outside.map((item: Garment) => item.name).join('、')}不在 ${request.temperature}℃ 的适穿区间内，穿之前留意一下。`;
  }
  if (unusable.length === 0 && outside.length === 0) {
    reason += `${request.temperature}℃ 下这几件都可以穿。`;
  }
  return {
    id: 'diy_' + ids.join('_') + '_' + Date.now(),
    garmentIds: ids, occasion: request.occasion, temperature: request.temperature,
    reason: reason, name: name, isCustom: true, savedAt: new Date().toLocaleDateString()
  };
}

export function recommend(garments: Garment[], request: OutfitRequest,
  providedBodyAnalysis?: BodyAnalysisResult): Recommendation {
  if (!Number.isFinite(request.temperature) || request.temperature < -20 || request.temperature > 45) {
    return { outfits: [], explanation: '请将温度设置在 -20 至 45℃ 之间。' };
  }
  const profile: PreferenceProfile = request.profile;
  const analysis: BodyAnalysisResult = resolveBodyAnalysis(request, providedBodyAnalysis);
  const locked: Garment[] = [];
  for (const id of request.lockedIds) {
    const item: Garment | undefined = garments.find((entry: Garment) => entry.id === id);
    if (!item || !eligible(item, request)) {
      return { outfits: [], explanation: `锁定的${item ? item.name : '衣物'}不符合当前状态、温度或场合，请解锁或调整条件。` };
    }
    if (locked.some((entry: Garment) => entry.category === item.category)) {
      return { outfits: [], explanation: '同一品类只能锁定一件衣物。' };
    }
    locked.push(item);
  }
  const categories: Category[] = [Category.TOP, Category.BOTTOM, Category.SHOES];
  // 比赛演示使用可解释规则，不伪装成大模型。低于 18℃ 需要外套，阈值集中放在这里便于后续调优。
  if (request.temperature < 18 || locked.some((item: Garment) => item.category === Category.OUTER)) {
    categories.push(Category.OUTER);
  }
  // 配饰是可选增强：有符合条件的配饰就加入候选组合，没有配饰也不能让完整穿搭失败。
  const lockedAccessory: Garment | undefined = locked.find((item: Garment) => item.category === Category.ACCESSORY);
  if (lockedAccessory !== undefined || garments.some((item: Garment) =>
    item.category === Category.ACCESSORY && eligible(item, request))) { categories.push(Category.ACCESSORY); }
  const pools: Garment[][] = [];
  for (const category of categories) {
    const fixed: Garment | undefined = locked.find((item: Garment) => item.category === category);
    const candidates: Garment[] = fixed ? [fixed] : garments.filter((item: Garment) =>
      item.category === category && eligible(item, request));
    const context: Outfit = rankingContext(request, candidates);
    // 先按偏好与体型软分数，再按穿着次数；软分数只影响顺序，不会让衣物变得不可选。
    candidates.sort((left: Garment, right: Garment) => {
      const rightScore: number = preferenceScore(right, profile) + bodyFitScore(right, context, analysis);
      const leftScore: number = preferenceScore(left, profile) + bodyFitScore(left, context, analysis);
      const byScore: number = rightScore - leftScore;
      return byScore !== 0 ? byScore : left.wearCount - right.wearCount;
    });
    if (candidates.length === 0) {
      return { outfits: [], explanation: `${request.temperature}℃、${request.occasion}场景缺少可穿的${category}。请补充衣物、恢复状态或调整条件。` };
    }
    pools.push(candidates);
  }
  // 有界枚举不同组合，最多返回三套；不为了凑数量复制同一套搭配。
  const outfits: Outfit[] = [];
  for (let variant: number = 0; variant < 3; variant++) {
    let cursor: number = variant;
    const selected: Garment[] = [];
    for (const pool of pools) {
      selected.push(pool[cursor % pool.length]);
      cursor = Math.floor(cursor / pool.length);
    }
    if (cursor > 0) { break; }
    outfits.push(makeOutfit(selected, request, profile, analysis));
  }
  return { outfits: outfits, explanation: '' };
}

export function replaceGarment(outfit: Outfit, itemId: string, garments: Garment[], request: OutfitRequest): Recommendation {
  if (request.lockedIds.indexOf(itemId) >= 0) { return { outfits: [], explanation: '这件衣物已锁定，请先解锁。' }; }
  const old: Garment | undefined = garments.find((item: Garment) => item.id === itemId);
  if (!old) { return { outfits: [], explanation: '这件衣物已不存在，请重新搭配。' }; }
  const alternatives: Garment[] = garments.filter((item: Garment) => item.category === old.category &&
    item.id !== old.id && eligible(item, request));
  if (alternatives.length === 0) { return { outfits: [], explanation: `没有符合条件的其他${old.category}，已保留原搭配。` }; }
  const analysis: BodyAnalysisResult = resolveBodyAnalysis(request);
  alternatives.sort((left: Garment, right: Garment) => {
    const rightScore: number = preferenceScore(right, request.profile) + bodyFitScore(right, outfit, analysis);
    const leftScore: number = preferenceScore(left, request.profile) + bodyFitScore(left, outfit, analysis);
    const byScore: number = rightScore - leftScore;
    return byScore !== 0 ? byScore : left.wearCount - right.wearCount;
  });
  const chosen: Garment[] = [];
  for (const id of outfit.garmentIds) {
    const item: Garment | undefined = id === old.id ? alternatives[0] : garments.find((entry: Garment) => entry.id === id);
    if (!item || !eligible(item, request)) { return { outfits: [], explanation: '搭配中的衣物状态已变化，请重新生成。' }; }
    chosen.push(item);
  }
  return { outfits: [makeOutfit(chosen, request, request.profile, analysis)], explanation: '' };
}
