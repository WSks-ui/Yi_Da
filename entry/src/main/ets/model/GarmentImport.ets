// 批量录入的数据结构。
//
// 设计原则：一个队列项 = 一张照片 + 一份独立草稿。草稿必须挂在项上，不能全队列共用一个
// 表单对象，否则切换当前项时后一项会继承前一项的名称与品类。
// 这里只放纯数据，不放任何 UI 组件类型，服务层不依赖页面。

// 队列项的处理阶段。COPYING 与 CUTTING 都表示"在途"，此时不允许离开流程。
export enum ImportPhase {
  WAITING = 'waiting',
  COPYING = 'copying',
  READY = 'ready',
  CUTTING = 'cutting',
  SAVING = 'saving',
  SAVED = 'saved',
  ERROR = 'error',
  SKIPPED = 'skipped'
}

// 失败发生在哪一步。重试按钮据此只重做失败的那一步，不重建任务。
export enum ImportFailureStep {
  NONE = 'none',
  COPY = 'copy',
  CUTOUT = 'cutout',
  SAVE = 'save'
}

// 单件草稿。温度与颜色都记录"用户是否动过"，避免换品类时静默覆盖用户已选的值。
export interface ImportGarmentDraft {
  name: string;
  // -1 表示尚未确认品类。选图后不猜品类，用户必须自己选一次。
  categoryIndex: number;
  subcategory?: string;
  material?: string;
  // 空字符串表示"未设置"颜色，不替用户声称自动识别出了颜色。
  color: string;
  minTemp: number;
  maxTemp: number;
  // 用户是否手动改过适穿温度；改过之后换品类不再套用默认区间。
  temperatureEdited: boolean;
  occasions: string[];
  error: string;
}

export interface ImportItem {
  // 任务 ID 与衣物 ID 在选图时一次性生成，重试不重建，保证幂等。
  id: string;
  garmentId: string;
  // Picker 的相册 URI 或白名单示例照片标识，只在本次会话内使用，绝不写进衣橱快照。
  sourceUri: string;
  // 归本次任务拥有的沙箱原图。
  originalUri: string;
  // 抠图结果，可空；同样归本次任务拥有。
  cutoutUri: string;
  useCutout: boolean;
  phase: ImportPhase;
  failureStep: ImportFailureStep;
  error: string;
  draft: ImportGarmentDraft;
  // 每次任务重新开始（重试、重新拷贝）都自增，用来让迟到的旧异步结果失效。
  revision: number;
}

export interface ImportSummary {
  total: number;
  saved: number;
  skipped: number;
  pending: number;
  failed: number;
}

export function emptyImportDraft(): ImportGarmentDraft {
  return { name: '', categoryIndex: -1, subcategory: '', material: '', color: '',
    minTemp: 12, maxTemp: 30, temperatureEdited: false,
    occasions: [], error: '' };
}

// 新队列项：选图后立刻建立，phase 为 WAITING，随后串行进入 COPYING。
export function createImportItem(id: string, garmentId: string, sourceUri: string): ImportItem {
  return { id: id, garmentId: garmentId, sourceUri: sourceUri, originalUri: '', cutoutUri: '',
    useCutout: false, phase: ImportPhase.WAITING, failureStep: ImportFailureStep.NONE, error: '',
    draft: emptyImportDraft(), revision: 0 };
}

// 当前用于保存/显示的图片。优先抠图结果，但只有在它确实存在且用户选了它时才用。
export function activeImageUri(item: ImportItem): string {
  if (item.useCutout && item.cutoutUri.length > 0) { return item.cutoutUri; }
  return item.originalUri;
}
