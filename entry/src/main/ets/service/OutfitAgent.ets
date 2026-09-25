import { BodyProfile, Category, Garment, OCCASIONS, Outfit, OutfitRequest, PreferenceProfile, Recommendation } from '../model/Wardrobe';
import { recommend, replaceGarment } from './OutfitEngine';

// Agent 的对外接口只暴露“输入 + 当前衣橱上下文 -> 回复 + 推荐结果”。
// 解析、温度修正和单件替换都藏在模块内部，页面不需要知道自然语言规则。
export interface OutfitAgentContext {
  garments: Garment[];
  profile: PreferenceProfile;
  body?: BodyProfile;
  occasion: string;
  temperature: number;
  lockedIds: string[];
  excludedIds: string[];
}

export interface OutfitAgentSession {
  latestOutfit?: Outfit;
}

export enum OutfitAgentIntent {
  RECOMMEND = 'recommend',
  REPLACE_TOP = 'replace_top',
  REPLACE_SHOES = 'replace_shoes',
  NEXT = 'next',
  CLARIFY = 'clarify',
  HELP = 'help',
  EMPTY = 'empty'
}

export interface OutfitAgentResult {
  intent: OutfitAgentIntent;
  reply: string;
  occasion: string;
  temperature: number;
  recommendation: Recommendation;
  latestOutfit?: Outfit;
}

interface OccasionToken {
  occasion: string;
  tokens: string[];
}

const OCCASION_TOKENS: OccasionToken[] = [
  { occasion: '课程展示', tokens: ['课程展示', '展示', '答辩', '汇报', '正式'] },
  { occasion: '社团', tokens: ['社团', '活动'] },
  { occasion: '约会', tokens: ['约会', '见面'] },
  { occasion: '上课', tokens: ['上课', '课堂', '上学'] }
];

function includesAny(input: string, tokens: string[]): boolean {
  return tokens.some((token: string) => input.indexOf(token) >= 0);
}

function parseOccasion(input: string, fallback: string): string {
  for (const entry of OCCASION_TOKENS) {
    if (includesAny(input, entry.tokens) && OCCASIONS.indexOf(entry.occasion) >= 0) {
      return entry.occasion;
    }
  }
  return fallback;
}

function clampTemperature(value: number): number {
  return Math.max(-20, Math.min(45, Math.round(value)));
}

function parseTemperature(input: string, fallback: number): number {
  const matched: RegExpMatchArray | null = input.match(/(-?\d{1,2})\s*(?:℃|度)/);
  if (matched !== null) { return clampTemperature(Number(matched[1])); }
  if (includesAny(input, ['冷一点', '凉一点', '降温'])) { return clampTemperature(fallback - 5); }
  if (includesAny(input, ['热一点', '暖一点', '升温'])) { return clampTemperature(fallback + 5); }
  return fallback;
}

function requestOf(context: OutfitAgentContext, occasion: string, temperature: number): OutfitRequest {
  return { occasion: occasion, temperature: temperature, lockedIds: context.lockedIds.slice(),
    excludedIds: context.excludedIds.slice(), profile: context.profile, body: context.body };
}

function helpText(): string {
  return '我可以根据你的衣橱和当前条件重新推荐。试试： “明天上课怎么穿”“约会，22度”“换一件上装” 或 “正式一点”。推荐结果会保留温度、场合和衣物状态约束。';
}

function describeRecommendation(recommendation: Recommendation, occasion: string, temperature: number): string {
  if (recommendation.outfits.length === 0) {
    return recommendation.explanation.length > 0 ? recommendation.explanation :
      '当前条件下没有完整方案，可以补充衣物或调整温度、场合。';
  }
  return `已按${occasion}、${temperature}℃重新整理 ${recommendation.outfits.length} 套方案。你可以继续说“换一件上装”，也可以直接采用下面的方案。`;
}

function replaceTopOutfit(context: OutfitAgentContext, session: OutfitAgentSession | undefined,
  occasion: string, temperature: number, category: Category): Recommendation | undefined {
  const latest: Outfit | undefined = session?.latestOutfit;
  if (latest === undefined) { return undefined; }
  const top: Garment | undefined = latest.garmentIds
    .map((id: string) => context.garments.find((item: Garment) => item.id === id))
    .find((item: Garment | undefined) => item !== undefined && item.category === category);
  if (top === undefined) { return undefined; }
  return replaceGarment(latest, top.id, context.garments, requestOf(context, occasion, temperature));
}

function nextRecommendation(recommendation: Recommendation, session: OutfitAgentSession | undefined): Recommendation {
  if (session?.latestOutfit === undefined || recommendation.outfits.length < 2) { return recommendation; }
  const index: number = recommendation.outfits.findIndex((item: Outfit) => item.id === session.latestOutfit?.id);
  const next: Outfit = recommendation.outfits[(index < 0 ? 0 : index + 1) % recommendation.outfits.length];
  return { outfits: [next].concat(recommendation.outfits.filter((item: Outfit) => item.id !== next.id)),
    explanation: recommendation.explanation };
}

export function runOutfitAgent(input: string, context: OutfitAgentContext,
  session?: OutfitAgentSession): OutfitAgentResult {
  const normalized: string = input.trim();
  const occasion: string = parseOccasion(normalized, context.occasion);
  const temperature: number = parseTemperature(normalized, context.temperature);
  if (normalized.length === 0) {
    return { intent: OutfitAgentIntent.EMPTY, reply: '告诉我场合或温度，我就能开始搭配。', occasion: occasion,
      temperature: temperature, recommendation: recommend(context.garments, requestOf(context, occasion, temperature)) };
  }
  if (includesAny(normalized, ['帮助', '能做什么', '怎么用', '指令'])) {
    return { intent: OutfitAgentIntent.HELP, reply: helpText(), occasion: occasion, temperature: temperature,
      recommendation: recommend(context.garments, requestOf(context, occasion, temperature)) };
  }
  const replaceTopRequested: boolean = includesAny(normalized, ['换上装', '换上衣', '换一件上装', '换件上衣']);
  const replaceShoesRequested: boolean = includesAny(normalized, ['换鞋', '换一双鞋', '换双鞋']);
  const nextRequested: boolean = includesAny(normalized, ['再来一套', '换一套', '下一套']);
  const replaceRequested: boolean = replaceTopRequested || replaceShoesRequested;
  const replaced: Recommendation | undefined = replaceRequested
    ? replaceTopOutfit(context, session, occasion, temperature, replaceShoesRequested ? Category.SHOES : Category.TOP) : undefined;
  let recommendation: Recommendation = replaced !== undefined && replaced.outfits.length > 0
    ? replaced : recommend(context.garments, requestOf(context, occasion, temperature));
  if (nextRequested) { recommendation = nextRecommendation(recommendation, session); }
  let reply: string = describeRecommendation(recommendation, occasion, temperature);
  let intent: OutfitAgentIntent = OutfitAgentIntent.RECOMMEND;
  if (replaced !== undefined && replaced.outfits.length > 0) {
    intent = replaceShoesRequested ? OutfitAgentIntent.REPLACE_SHOES : OutfitAgentIntent.REPLACE_TOP;
    reply = replaceShoesRequested
      ? `已为你换一双鞋，仍按${occasion}、${temperature}℃和当前衣物状态筛选。`
      : `已为你换一件上装，仍按${occasion}、${temperature}℃和当前衣物状态筛选。`;
  } else if (replaceRequested) {
    intent = replaceShoesRequested ? OutfitAgentIntent.REPLACE_SHOES : OutfitAgentIntent.REPLACE_TOP;
    reply = '上一套方案里没有可替换的目标单品，先重新生成一套方案吧。';
  } else if (nextRequested) {
    intent = OutfitAgentIntent.NEXT;
    reply = recommendation.outfits.length > 0 ? '已切换到下一套方案。' : describeRecommendation(recommendation, occasion, temperature);
  }
  if (recommendation.outfits.length === 0 && !replaceRequested) {
    intent = OutfitAgentIntent.CLARIFY;
    reply = `${reply} 你可以先调整温度、换一个场合，或去衣橱补充缺少的品类。`;
  }
  return { intent: intent,
    reply: reply, occasion: occasion, temperature: temperature, recommendation: recommendation,
    latestOutfit: recommendation.outfits.length > 0 ? recommendation.outfits[0] : undefined };
}
