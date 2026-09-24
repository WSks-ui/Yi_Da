import { BodyProfile, Category, Garment, Outfit } from '../model/Wardrobe';

// 体型分析只使用用户主动填写的身高、围度和版型偏好，不从照片或衣物图片推断尺寸。
// 因此档案不完整时，结果会明确降低置信度，推荐层也只做小幅顺序调整。
export interface BodyAnalysisResult {
  shape: string;
  summary: string;
  knownFields: string[];
  confidence: number;
  // 以下字段用于推荐理由和排序；保留为可选，便于兼容只包含四个核心字段的旧调用方。
  advice?: string[];
  recommendationSummary?: string;
  fitPreference?: string;
  heightBand?: string;
  shoulderBand?: string;
}

function clean(value: string | undefined): string {
  return value === undefined ? '' : value.trim();
}

function readMeasure(value: string | undefined): number | undefined {
  const normalized: string = clean(value).replace(/厘米/gi, '').replace(/cm/gi, '').replace(/，/g, '.');
  if (normalized.length === 0) { return undefined; }
  const parsed: number = Number(normalized);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : undefined;
}

function rounded(value: number): number {
  return Math.round(value * 100) / 100;
}

function hasField(fields: string[], name: string): boolean {
  return fields.indexOf(name) >= 0;
}

function fallbackProfile(): BodyProfile {
  return { height: '', size: '', fitPreference: '', shoulder: '', chest: '', waist: '', hip: '',
    skinTone: '', hairColor: '', eyeColor: '', updatedAt: '' };
}

function heightBand(height: number | undefined): string {
  if (height === undefined) { return ''; }
  if (height < 160) { return '偏矮'; }
  if (height >= 175) { return '偏高'; }
  return '中等';
}

function inferShape(chest: number | undefined, waist: number | undefined, hip: number | undefined): string {
  // 胸围和臀围都是围度，才可以进行比例判断；肩宽是横向宽度，不能直接替代胸围参与计算。
  if (chest === undefined || hip === undefined) { return '信息不足'; }
  const difference: number = (chest - hip) / Math.max(chest, hip);
  if (waist !== undefined) {
    const waistRatio: number = waist / Math.min(chest, hip);
    if (Math.abs(difference) <= 0.1 && waistRatio <= 0.82) { return '沙漏型'; }
    if (difference >= 0.08) { return '倒三角型'; }
    if (difference <= -0.08) { return '梨型'; }
    return '直筒型';
  }
  // 没有腰围时只报告上、下半身的明显差异，避免把不完整数据描述成完整体型。
  if (difference >= 0.08) { return '倒三角型'; }
  if (difference <= -0.08) { return '梨型'; }
  return '信息不足';
}

function shoulderBand(shoulder: number | undefined): string {
  if (shoulder === undefined) { return ''; }
  if (shoulder < 39) { return '偏窄'; }
  if (shoulder > 42) { return '偏宽'; }
  return '常规';
}

function shapeAdvice(shape: string): string {
  switch (shape) {
    case '沙漏型': return '肩胸与臀部比例接近，优先考虑能保留腰线的合身版型。';
    case '倒三角型': return '肩胸相对更突出，优先考虑上装利落、下装有适度空间的组合。';
    case '梨型': return '臀部相对更突出，优先考虑上装有轮廓感、下装线条简洁的组合。';
    case '直筒型': return '整体横向比例接近，可用有轮廓感或适度叠穿增加层次。';
    default: return '当前可用信息不足以判断具体体型，仅按已确认信息调整顺序。';
  }
}

function fitAdvice(fit: string): string {
  switch (fit) {
    case '宽松': return '按你选择的宽松偏好，优先考虑宽松版型。';
    case '标准': return '按你选择的标准偏好，优先考虑合身或有轮廓感版型。';
    case '合身': return '按你选择的合身偏好，优先考虑合身版型。';
    default: return fit.length > 0 ? `已记录版型偏好“${fit}”，仅按衣物标注调整顺序。` : '';
  }
}

export function analyzeBodyProfile(profile: BodyProfile | undefined): BodyAnalysisResult {
  const source: BodyProfile = profile === undefined ? fallbackProfile() : profile;
  const knownFields: string[] = [];
  const heightText: string = clean(source.height);
  const shoulderText: string = clean(source.shoulder);
  const chestText: string = clean(source.chest);
  const waistText: string = clean(source.waist);
  const hipText: string = clean(source.hip);
  const fitText: string = clean(source.fitPreference);
  const height: number | undefined = readMeasure(heightText);
  const shoulder: number | undefined = readMeasure(shoulderText);
  const chest: number | undefined = readMeasure(chestText);
  const waist: number | undefined = readMeasure(waistText);
  const hip: number | undefined = readMeasure(hipText);
  // 只有可解析的数字才算已知字段，避免“abc”等无效输入虚增置信度。
  if (height !== undefined) { knownFields.push('height'); }
  if (shoulder !== undefined) { knownFields.push('shoulder'); }
  if (chest !== undefined) { knownFields.push('chest'); }
  if (waist !== undefined) { knownFields.push('waist'); }
  if (hip !== undefined) { knownFields.push('hip'); }
  if (fitText.length > 0) { knownFields.push('fitPreference'); }

  const shape: string = inferShape(chest, waist, hip);
  const band: string = heightBand(height);
  const shoulderType: string = shoulderBand(shoulder);
  const advice: string[] = [];
  if (shape !== '信息不足') { advice.push(shapeAdvice(shape)); }
  if (shoulderType === '偏窄') { advice.push('肩宽偏窄，可优先考虑有轮廓感的上装。'); }
  else if (shoulderType === '偏宽') { advice.push('肩宽偏宽，上装可优先考虑利落、不过度强调肩部的版型。'); }
  if (band === '偏矮') { advice.push('身高比例可优先考虑利落、不过长的版型。'); }
  else if (band === '偏高') { advice.push('身高比例可优先考虑有纵向线条或有轮廓的版型。'); }
  if (fitText.length > 0) { advice.push(fitAdvice(fitText)); }
  if (advice.length === 0 && knownFields.length > 0) { advice.push(shapeAdvice('信息不足')); }

  let summary: string = '未填写体型信息，保持原有推荐顺序。';
  if (knownFields.length > 0) {
    const parts: string[] = [];
    if (shape !== '信息不足') { parts.push(`根据已填写围度，初步判断为${shape}。`); }
    if (shoulder !== undefined) { parts.push(`已参考肩宽 ${shoulder} 厘米的上装版型。`); }
    if (height !== undefined) { parts.push(`已参考身高 ${height} 厘米的整体比例。`); }
    if (fitText.length > 0) { parts.push(`版型偏好为${fitText}。`); }
    if (parts.length === 0) { parts.push('当前可用信息不足以判断具体体型，仅按已确认信息调整顺序。'); }
    summary = parts.join('');
  }
  const confidence: number = rounded(Math.min(1, knownFields.length / 6));
  return { shape: shape, summary: summary, knownFields: knownFields, confidence: confidence,
    advice: advice, recommendationSummary: advice.join(''), fitPreference: fitText, heightBand: band,
    shoulderBand: shoulderType };
}

function shapeScore(garment: Garment, shape: string): number {
  switch (shape) {
    case '沙漏型':
      return garment.fit === '合身' ? 1.5 : garment.fit === '宽松' ? -0.25 : 0;
    case '倒三角型':
      if (garment.category === Category.BOTTOM) { return garment.fit === '宽松' ? 1.5 : 0.25; }
      if (garment.category === Category.TOP || garment.category === Category.OUTER) {
        return garment.fit === '有轮廓感' ? -1 : garment.fit === '合身' ? 0.5 : 0;
      }
      return 0;
    case '梨型':
      if (garment.category === Category.TOP || garment.category === Category.OUTER) {
        return garment.fit === '有轮廓感' ? 1.5 : garment.fit === '合身' ? 0.25 : 0;
      }
      if (garment.category === Category.BOTTOM && garment.fit === '有轮廓感') { return -0.5; }
      return 0;
    case '直筒型':
      return garment.fit === '有轮廓感' ? 1 : garment.fit === '宽松' ? 0.5 : 0;
    default:
      return 0;
  }
}

function preferenceFitScore(garment: Garment, preference: string): number {
  if (preference === '宽松' && garment.fit === '宽松') { return 1.5; }
  if (preference === '合身' && garment.fit === '合身') { return 1.5; }
  if (preference === '标准' && garment.fit === '合身') { return 1; }
  return 0;
}

function heightScore(garment: Garment, band: string): number {
  if (band === '偏矮' && (garment.category === Category.TOP || garment.category === Category.OUTER) &&
    garment.fit === '有轮廓感') { return 0.5; }
  if (band === '偏高' && garment.category === Category.TOP && garment.fit === '宽松') { return 0.25; }
  return 0;
}

function shoulderScore(garment: Garment, band: string): number {
  if (garment.category !== Category.TOP && garment.category !== Category.OUTER) { return 0; }
  if (band === '偏窄' && garment.fit === '有轮廓感') { return 0.5; }
  if (band === '偏宽' && garment.fit === '有轮廓感') { return -0.5; }
  if (band === '偏宽' && garment.fit === '合身') { return 0.25; }
  return 0;
}

export function bodyFitScore(garment: Garment, outfit: Outfit, analysis: BodyAnalysisResult): number {
  // 当前衣物模型没有衣长、裤腰等字段，组合对象仅作为 API 上下文保留；不据此臆测搭配效果。
  void outfit;
  if (analysis === undefined || analysis.confidence <= 0 || analysis.knownFields.length === 0) { return 0; }
  const shape: string = analysis.shape || '信息不足';
  const preference: string = clean(analysis.fitPreference);
  const band: string = clean(analysis.heightBand);
  const shoulderType: string = clean(analysis.shoulderBand);
  let score: number = 0;
  if (hasField(analysis.knownFields, 'chest') && hasField(analysis.knownFields, 'hip')) {
    score += shapeScore(garment, shape);
  }
  if (hasField(analysis.knownFields, 'shoulder')) { score += shoulderScore(garment, shoulderType); }
  if (hasField(analysis.knownFields, 'fitPreference')) { score += preferenceFitScore(garment, preference); }
  if (hasField(analysis.knownFields, 'height')) { score += heightScore(garment, band); }
  return rounded(score);
}
