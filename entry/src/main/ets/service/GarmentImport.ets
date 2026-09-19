// 批量录入的纯状态转换。
//
// 这一层不碰文件、不碰 UI、不碰仓储，只做四件事：
//   1. 队列项的不可变更新（生成新对象/新数组，让 ArkUI V1 能观察到变化）；
//   2. 阶段的合法性判断与流转；
//   3. 保存前的字段校验；
//   4. 稳定 ID 规则。
// 这样 Node 侧的业务检查可以直接转译本文件验证失败路径，不需要在测试里复制一份生产算法。
import { CATEGORIES, OCCASIONS } from '../model/Wardrobe';
import { ImportFailureStep, ImportGarmentDraft, ImportItem, ImportPhase, ImportSummary,
  emptyImportDraft } from '../model/GarmentImport';

// 页面只依赖本服务，不直接依赖模型文件；队列项的构造与当前图片的取法统一从这里再导出。
export { activeImageUri, createImportItem } from '../model/GarmentImport';

export const IMPORT_BATCH_PREFIX: string = 'garment_batch_';
export const WARDROBE_LIMIT: number = 100;
export const IMPORT_SELECT_LIMIT: number = 10;
export const MAX_NAME_LENGTH: number = 30;
export const MIN_TEMPERATURE: number = -20;
export const MAX_TEMPERATURE: number = 45;
// 单张照片的产品资源预算。这是本应用自己定的上限，不是华为 API 的硬限制。
export const MAX_SOURCE_PIXELS: number = 40000000;
export const MAX_SOURCE_BYTES: number = 20 * 1024 * 1024;
export const MAX_EDGE: number = 2048;
export const IMPORT_SUFFIX_ORIGINAL: string = 'orig';
export const IMPORT_SUFFIX_CUTOUT: string = 'cut';

// 品类默认温度区间，与单件录入表单保持同一套起点，避免两个入口给不同建议。
export function defaultRange(categoryIndex: number): number[] {
  if (categoryIndex === 0) { return [16, 35]; }
  if (categoryIndex === 1) { return [8, 30]; }
  if (categoryIndex === 2) { return [5, 35]; }
  if (categoryIndex === 3) { return [8, 22]; }
  return [10, 32];
}

// ---- 稳定 ID ----

// 会话 ID：一次选择 = 一个会话。文件名里带上它，才能按"这一轮建立的文件"做受限清理。
export function makeSessionId(now: number, salt: number): string {
  return 's' + now + '_' + salt;
}

// 任务 ID 与衣物 ID 在选图时生成一次，重试只复用不重建；幂等靠的就是这一点。
export function makeTaskId(sessionId: string, index: number): string {
  return sessionId + '_t' + index;
}

export function makeGarmentId(sessionId: string, index: number): string {
  return IMPORT_BATCH_PREFIX + sessionId + '_' + index;
}

// 在同一次录入里追加选择时，给新的批次找一段不冲突的序号。
// 会话 ID 已含建立时刻，这里再避让一次现有任务，保证追加也不会撞上已有 ID。
export function offsetFor(items: ImportItem[], sessionId: string, count: number): number {
  const used: string[] = items.map((item: ImportItem) => item.id);
  for (let start: number = 0; start <= 10000; start += IMPORT_SELECT_LIMIT) {
    let free: boolean = true;
    for (let index: number = 0; index < count; index++) {
      if (used.indexOf(makeTaskId(sessionId, start + index)) >= 0) { free = false; break; }
    }
    if (free) { return start; }
  }
  return items.length;
}

// ---- 队列容量 ----

// 剩余额度 = min(单次上限, 衣橱剩余容量)。只拦新增，不拦编辑与幂等确认。
export function remainingCapacity(garmentCount: number): number {
  const room: number = WARDROBE_LIMIT - garmentCount;
  if (room <= 0) { return 0; }
  return Math.min(IMPORT_SELECT_LIMIT, room);
}

// 同一次选择内按 URI 精确去重并保留原顺序；不做内容去重，也不把同名文件当成同一件。
export function dedupeUris(uris: string[]): string[] {
  const unique: string[] = [];
  for (const uri of uris) {
    if (uri.length > 0 && unique.indexOf(uri) < 0) { unique.push(uri); }
  }
  return unique;
}

// ---- 队列项更新 ----

// 得到指定任务的新条目；找不到时原样返回数组，避免无意义的重建。
export function patchItem(items: ImportItem[], id: string, patch: (item: ImportItem) => ImportItem): ImportItem[] {
  let found: boolean = false;
  const next: ImportItem[] = items.map((item: ImportItem) => {
    if (item.id !== id) { return item; }
    found = true;
    return patch(item);
  });
  return found ? next : items;
}

// 得到指定任务的新草稿。草稿按字段合并，切换当前项时字段不会串。
// 用户一旦改动字段就清掉该任务的报错，否则旧错误会一直挂在新输入旁边。
export function patchDraft(items: ImportItem[], id: string, patch: (draft: ImportGarmentDraft) => ImportGarmentDraft): ImportItem[] {
  return patchItem(items, id, (item: ImportItem) => {
    // SAVED/SKIPPED 是会话终态。即使旧 UI 回调晚到，也不能让终态重新可编辑。
    if (item.phase === ImportPhase.SAVED || item.phase === ImportPhase.SKIPPED) { return item; }
    const draft: ImportGarmentDraft = patch(item.draft);
    draft.error = '';
    return { id: item.id, garmentId: item.garmentId, sourceUri: item.sourceUri, originalUri: item.originalUri,
      cutoutUri: item.cutoutUri, useCutout: item.useCutout, phase: item.phase, failureStep: item.failureStep,
      error: '', draft: draft, revision: item.revision };
  });
}

// 换品类：用户没动过温度时才套用该品类默认区间，动过就保留用户的选择。
export function applyCategory(items: ImportItem[], id: string, categoryIndex: number): ImportItem[] {
  return patchDraft(items, id, (draft: ImportGarmentDraft) => {
    const next: ImportGarmentDraft = { name: draft.name, categoryIndex: categoryIndex, color: draft.color,
      minTemp: draft.minTemp, maxTemp: draft.maxTemp, temperatureEdited: draft.temperatureEdited,
      occasions: draft.occasions.slice(), error: draft.error };
    if (!draft.temperatureEdited && categoryIndex >= 0 && categoryIndex < CATEGORIES.length) {
      const range: number[] = defaultRange(categoryIndex);
      next.minTemp = range[0]; next.maxTemp = range[1];
    }
    return next;
  });
}

// 用户拖动温度滑杆：从这一下起温度归用户所有，换品类不再覆盖。
export function applyMinTemp(items: ImportItem[], id: string, value: number): ImportItem[] {
  return patchDraft(items, id, (draft: ImportGarmentDraft) => ({ name: draft.name,
    categoryIndex: draft.categoryIndex, color: draft.color, minTemp: value, maxTemp: draft.maxTemp,
    temperatureEdited: true, occasions: draft.occasions.slice(), error: draft.error }));
}

export function applyMaxTemp(items: ImportItem[], id: string, value: number): ImportItem[] {
  return patchDraft(items, id, (draft: ImportGarmentDraft) => ({ name: draft.name,
    categoryIndex: draft.categoryIndex, color: draft.color, minTemp: draft.minTemp, maxTemp: value,
    temperatureEdited: true, occasions: draft.occasions.slice(), error: draft.error }));
}

// 按字段改草稿。页面只传出改动的字段，不重建整份草稿——
// 重建会把对象身份一起换掉，在 ArkUI V1 的复用节点里很容易写出"画面不动但数据已改"的问题。
export interface ImportDraftPatch {
  name?: string;
  color?: string;
  occasions?: string[];
}

export function applyDraft(items: ImportItem[], id: string, patch: ImportDraftPatch): ImportItem[] {
  return patchDraft(items, id, (draft: ImportGarmentDraft) => ({ name: patch.name !== undefined ? patch.name : draft.name,
    categoryIndex: draft.categoryIndex, color: patch.color !== undefined ? patch.color : draft.color,
    minTemp: draft.minTemp, maxTemp: draft.maxTemp, temperatureEdited: draft.temperatureEdited,
    occasions: patch.occasions !== undefined ? patch.occasions.slice() : draft.occasions.slice(),
    error: draft.error }));
}

// ---- 阶段流转 ----

// 重置草稿：跳过或重选图片后回到"未确认"状态，不保留上一张的属性。
export function resetDraft(items: ImportItem[], id: string): ImportItem[] {
  return patchItem(items, id, (item: ImportItem) => {
    if (item.phase === ImportPhase.SAVED || item.phase === ImportPhase.SKIPPED) { return item; }
    return { id: item.id, garmentId: item.garmentId,
    sourceUri: item.sourceUri, originalUri: item.originalUri, cutoutUri: item.cutoutUri, useCutout: false,
    phase: item.phase, failureStep: item.failureStep, error: item.error, draft: emptyImportDraft(),
    revision: item.revision };
  });
}

// 开始拷贝：revision 自增，使上一次在途的结果失效。
export function beginCopy(items: ImportItem[], id: string): ImportItem[] {
  return patchItem(items, id, (item: ImportItem) => {
    if (item.phase === ImportPhase.SAVED || item.phase === ImportPhase.SKIPPED) { return item; }
    return { id: item.id, garmentId: item.garmentId,
    sourceUri: item.sourceUri, originalUri: '', cutoutUri: '', useCutout: false, phase: ImportPhase.COPYING,
    failureStep: ImportFailureStep.NONE, error: '', draft: item.draft, revision: item.revision + 1 };
  });
}

export function copySucceeded(items: ImportItem[], id: string, originalUri: string): ImportItem[] {
  return patchItem(items, id, (item: ImportItem) => {
    if (item.phase !== ImportPhase.COPYING) { return item; }
    return { id: item.id, garmentId: item.garmentId,
    sourceUri: item.sourceUri, originalUri: originalUri, cutoutUri: '', useCutout: false,
    phase: ImportPhase.READY, failureStep: ImportFailureStep.NONE, error: '', draft: item.draft,
    revision: item.revision };
  });
}

export function copyFailed(items: ImportItem[], id: string, message: string): ImportItem[] {
  return patchItem(items, id, (item: ImportItem) => {
    if (item.phase !== ImportPhase.COPYING) { return item; }
    return { id: item.id, garmentId: item.garmentId,
    sourceUri: item.sourceUri, originalUri: item.originalUri, cutoutUri: item.cutoutUri,
    useCutout: item.useCutout, phase: ImportPhase.ERROR, failureStep: ImportFailureStep.COPY,
    error: message, draft: item.draft, revision: item.revision };
  });
}

export function beginCutout(items: ImportItem[], id: string): ImportItem[] {
  return patchItem(items, id, (item: ImportItem) => {
    // 保存失败并不代表原图失效：用户可以先补做抠图，再回到同一个保存任务重试。
    // 只有 READY 或 ERROR(SAVE) 能进入抠图；复制/抠图在途以及其他失败阶段必须原样返回。
    const canRetryAfterSave: boolean = item.phase === ImportPhase.ERROR &&
      item.failureStep === ImportFailureStep.SAVE;
    if (item.phase === ImportPhase.SAVED || item.phase === ImportPhase.SKIPPED ||
      item.originalUri.length === 0 || isActivePhase(item.phase) ||
      (item.phase !== ImportPhase.READY && !canRetryAfterSave)) { return item; }
    return { id: item.id, garmentId: item.garmentId,
    sourceUri: item.sourceUri, originalUri: item.originalUri, cutoutUri: item.cutoutUri,
    useCutout: item.useCutout, phase: ImportPhase.CUTTING, failureStep: ImportFailureStep.NONE,
    error: '', draft: item.draft, revision: item.revision };
  });
}

// 抠图成功：默认切到抠图结果，但用户可以随时切回原图。
export function cutoutSucceeded(items: ImportItem[], id: string, cutoutUri: string): ImportItem[] {
  return patchItem(items, id, (item: ImportItem) => {
    if (item.phase !== ImportPhase.CUTTING || cutoutUri.length === 0) { return item; }
    return { id: item.id, garmentId: item.garmentId,
    sourceUri: item.sourceUri, originalUri: item.originalUri, cutoutUri: cutoutUri, useCutout: true,
    phase: ImportPhase.READY, failureStep: ImportFailureStep.NONE, error: '', draft: item.draft,
    revision: item.revision };
  });
}

// 抠图失败：回到 READY，原图仍可用；失败步骤留给重试按钮。
export function cutoutFailed(items: ImportItem[], id: string, message: string): ImportItem[] {
  return patchItem(items, id, (item: ImportItem) => {
    if (item.phase !== ImportPhase.CUTTING) { return item; }
    return { id: item.id, garmentId: item.garmentId,
    sourceUri: item.sourceUri, originalUri: item.originalUri, cutoutUri: '', useCutout: false,
    phase: ImportPhase.READY, failureStep: ImportFailureStep.CUTOUT, error: message, draft: item.draft,
    revision: item.revision };
  });
}

export function setUseCutout(items: ImportItem[], id: string, useCutout: boolean): ImportItem[] {
  return patchItem(items, id, (item: ImportItem) => {
    if (item.phase === ImportPhase.SAVED || item.phase === ImportPhase.SKIPPED) { return item; }
    return { id: item.id, garmentId: item.garmentId,
    sourceUri: item.sourceUri, originalUri: item.originalUri, cutoutUri: item.cutoutUri,
    useCutout: useCutout && item.cutoutUri.length > 0, phase: item.phase, failureStep: item.failureStep,
    error: '', draft: item.draft, revision: item.revision };
  });
}

export function beginSave(items: ImportItem[], id: string): ImportItem[] {
  return patchItem(items, id, (item: ImportItem) => {
    if (item.phase === ImportPhase.SAVED || item.phase === ImportPhase.SKIPPED || isActivePhase(item.phase)) {
      return item;
    }
    if (item.originalUri.length === 0 && item.cutoutUri.length === 0) { return item; }
    return { id: item.id, garmentId: item.garmentId,
    sourceUri: item.sourceUri, originalUri: item.originalUri, cutoutUri: item.cutoutUri,
    useCutout: item.useCutout, phase: ImportPhase.SAVING, failureStep: ImportFailureStep.NONE,
    error: '', draft: item.draft, revision: item.revision };
  });
}

export function saveSucceeded(items: ImportItem[], id: string): ImportItem[] {
  return patchItem(items, id, (item: ImportItem) => {
    if (item.phase !== ImportPhase.SAVING) { return item; }
    return { id: item.id, garmentId: item.garmentId,
    sourceUri: item.sourceUri, originalUri: item.originalUri, cutoutUri: item.cutoutUri,
    useCutout: item.useCutout, phase: ImportPhase.SAVED, failureStep: ImportFailureStep.NONE,
    error: '', draft: item.draft, revision: item.revision };
  });
}

export function saveFailed(items: ImportItem[], id: string, message: string): ImportItem[] {
  return patchItem(items, id, (item: ImportItem) => {
    if (item.phase !== ImportPhase.SAVING) { return item; }
    return { id: item.id, garmentId: item.garmentId,
    sourceUri: item.sourceUri, originalUri: item.originalUri, cutoutUri: item.cutoutUri,
    useCutout: item.useCutout, phase: ImportPhase.ERROR, failureStep: ImportFailureStep.SAVE,
    error: message, draft: item.draft, revision: item.revision };
  });
}

// 标记已跳过。revision 自增，让在途的拷贝/抠图结果回来时只能清理。
export function markSkipped(items: ImportItem[], id: string): ImportItem[] {
  return patchItem(items, id, (item: ImportItem) => {
    if (item.phase === ImportPhase.SAVED || item.phase === ImportPhase.SKIPPED) { return item; }
    // 跳过后 URI 不能继续留在终态对象里，否则旧页面回调可能再次拿到已删除的图片。
    return { id: item.id, garmentId: item.garmentId,
    sourceUri: '', originalUri: '', cutoutUri: '', useCutout: false,
    phase: ImportPhase.SKIPPED, failureStep: ImportFailureStep.NONE, error: '', draft: item.draft,
    revision: item.revision + 1 };
  });
}

// ---- 查询 ----

export function isActivePhase(phase: ImportPhase): boolean {
  return phase === ImportPhase.COPYING || phase === ImportPhase.CUTTING || phase === ImportPhase.SAVING;
}

export function isPending(item: ImportItem): boolean {
  return item.phase !== ImportPhase.SAVED && item.phase !== ImportPhase.SKIPPED;
}

export function summaryOf(items: ImportItem[]): ImportSummary {
  let saved: number = 0;
  let skipped: number = 0;
  let failed: number = 0;
  let pending: number = 0;
  for (const item of items) {
    if (item.phase === ImportPhase.SAVED) { saved++; }
    else if (item.phase === ImportPhase.SKIPPED) { skipped++; }
    else { pending++; }
    if (item.phase === ImportPhase.ERROR) { failed++; }
  }
  return { total: items.length, saved: saved, skipped: skipped, pending: pending, failed: failed };
}

// 下一个还没保存也没跳过的项；都处理完返回 -1。保存成功后用它自动前进。
export function nextPendingIndex(items: ImportItem[], from: number): number {
  for (let step: number = 1; step <= items.length; step++) {
    const index: number = (from + step) % items.length;
    if (isPending(items[index])) { return index; }
  }
  return -1;
}

// 还有没有"进行中"的任务。离开流程前用它决定是否需要确认。
export function hasUnfinished(items: ImportItem[]): boolean {
  return items.some((item: ImportItem) => isPending(item));
}

export function hasActiveTask(items: ImportItem[]): boolean {
  return items.some((item: ImportItem) => isActivePhase(item.phase));
}

// ---- 校验 ----

export interface DraftErrors {
  name: string;
  category: string;
  temperature: string;
  occasions: string;
}

export function draftErrors(item: ImportItem): DraftErrors {
  const draft: ImportGarmentDraft = item.draft;
  const name: string = draft.name.trim();
  let nameError: string = '';
  if (name.length === 0) { nameError = '请填写名称，不会从文件名自动取名'; }
  else if (name.length > MAX_NAME_LENGTH) { nameError = `名称最多 ${MAX_NAME_LENGTH} 个字`; }
  return { name: nameError, category: validateCategory(draft), temperature: validateTemperature(draft),
    occasions: validateOccasions(draft) };
}

function validateCategory(draft: ImportGarmentDraft): string {
  if (draft.categoryIndex < 0 || draft.categoryIndex >= CATEGORIES.length) { return '请选择品类，不会自动判定'; }
  return '';
}

function validateTemperature(draft: ImportGarmentDraft): string {
  if (!Number.isFinite(draft.minTemp) || !Number.isFinite(draft.maxTemp)) { return '适穿温度必须是数字'; }
  if (draft.minTemp < MIN_TEMPERATURE || draft.maxTemp > MAX_TEMPERATURE ||
    draft.minTemp > MAX_TEMPERATURE || draft.maxTemp < MIN_TEMPERATURE) {
    return `适穿温度需在 ${MIN_TEMPERATURE} – ${MAX_TEMPERATURE}℃ 之间`;
  }
  if (draft.minTemp > draft.maxTemp) { return '最低温度不能高于最高温度'; }
  return '';
}

function validateOccasions(draft: ImportGarmentDraft): string {
  const valid: string[] = draft.occasions.filter((value: string) => OCCASIONS.indexOf(value) >= 0);
  if (valid.length === 0) { return '至少选择一个场合'; }
  return '';
}

export function hasFieldErrors(errors: DraftErrors): boolean {
  return errors.name.length > 0 || errors.category.length > 0 || errors.temperature.length > 0 ||
    errors.occasions.length > 0;
}

// 保存前的完整校验：先看图片，再看四个属性字段。返回空串表示可以保存。
export function canSave(item: ImportItem, wardrobeCount: number): string {
  if (item.phase === ImportPhase.SAVED) { return '这一件已经保存过了，可在衣橱里继续编辑'; }
  if (item.phase === ImportPhase.SKIPPED) { return '这一件已经跳过，不能再次保存'; }
  if (isActivePhase(item.phase)) { return '当前还有处理中的任务，请等待完成'; }
  if (item.originalUri.length === 0 && item.cutoutUri.length === 0) { return '还没有可用的本地图片，请重试导入'; }
  if (item.phase === ImportPhase.WAITING || item.phase === ImportPhase.COPYING) { return '图片尚未导入完成'; }
  const errors: DraftErrors = draftErrors(item);
  if (errors.name.length > 0) { return errors.name; }
  if (errors.category.length > 0) { return errors.category; }
  if (errors.temperature.length > 0) { return errors.temperature; }
  if (errors.occasions.length > 0) { return errors.occasions; }
  if (wardrobeCount >= WARDROBE_LIMIT) { return `本地演示版最多保存 ${WARDROBE_LIMIT} 件衣物`; }
  return '';
}

// 跳过前的确认条件：编辑过任何字段或已经产生处理结果才需要问一次。
export function needsSkipConfirm(item: ImportItem): boolean {
  const draft: ImportGarmentDraft = item.draft;
  if (draft.name.trim().length > 0 || draft.categoryIndex >= 0 || draft.color.length > 0 ||
    draft.temperatureEdited || draft.occasions.length > 0) { return true; }
  return item.originalUri.length > 0 || item.cutoutUri.length > 0;
}

// 抠图能力是否可用只需要看当前项：能力检测放在页面，这里只管状态含义。
export function cutoutLabel(item: ImportItem): string {
  if (item.phase === ImportPhase.CUTTING) { return '处理中'; }
  if (item.cutoutUri.length > 0) { return item.useCutout ? '抠图' : '切回抠图'; }
  if (item.failureStep === ImportFailureStep.CUTOUT) { return '重试抠图'; }
  return '主体抠图';
}

// ---- 单件换图的文件标识 ----
//
// 每次换图必须拿到一个独立、不可复用的标识。
// 不能拿"草稿数组长度"当序号：取消一次再换一次会取到同一个值，
// 于是第二次导入写进与第一次相同的文件名，把用户还没保存的图片覆盖掉。
// 因此这里用"会话 ID + 单调递增计数器"，并且每次调用都推进计数器。
let draftSeq: number = 0;

export function nextDraftFileKey(sessionId: string): string {
  draftSeq++;
  return sessionId + '_d' + draftSeq;
}

// 仅供检查与排查使用；不参与命名逻辑。
export function draftSequence(): number { return draftSeq; }

export function resetDraftSequence(): void { draftSeq = 0; }

// ---- 导入链的写回判据 ----

// 在途结果是否仍然有效：任务还在、revision 未变、阶段还在途。
// 会话被放弃（items 为空）时一律无效——旧结果只能清理，不能写回。
export function writeBack(items: ImportItem[], taskId: string, revision: number): boolean {
  const item: ImportItem | undefined = items.find((entry: ImportItem) => entry.id === taskId);
  if (item === undefined) { return false; }
  if (item.revision !== revision) { return false; }
  return isActivePhase(item.phase);
}
