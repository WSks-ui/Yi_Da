import { TryOnTask } from '../model/Wardrobe';

// 试穿演示场景只保存稳定的业务键和文案；图片资源由 UI 层按 demoSceneId 映射。
// 这样快照不会写入构建时分配的 Resource.id，也不会把用户衣物误当成演示样片。
export interface TryOnDemoScene {
  id: string;
  name: string;
  garmentLabel: string;
  pose: string;
  description: string;
}

export type TryOnDemoPoseId = 'front' | 'side' | 'back';

// 这里只描述演示所需的姿势槽位；正侧背素材未齐时，UI 必须明确显示不可用，
// 不得拿其他人物或其他服装的照片填充槽位。
export interface TryOnDemoPose {
  id: TryOnDemoPoseId;
  label: string;
}

export const DEMO_POSES: TryOnDemoPose[] = [
  { id: 'front', label: '正面' },
  { id: 'side', label: '侧面' },
  { id: 'back', label: '背面' }
];

export const DEMO_SCENES: TryOnDemoScene[] = [
  { id: 'denim_skirt', name: '牛仔半裙', garmentLabel: '牛仔半裙', pose: '正面站姿',
    description: '固定演示样片，不代表你的衣橱单品' },
  { id: 'navy_top', name: '深蓝上衣', garmentLabel: '深蓝上衣', pose: '正面站姿',
    description: '固定演示样片，不代表你的衣橱单品' },
  { id: 'red_dress', name: '红色连衣裙', garmentLabel: '红色连衣裙', pose: '正面站姿',
    description: '固定演示样片，不代表你的衣橱单品' }
];

const DEMO_TASK_PREFIX: string = 'tryon_demo_';
const DEMO_STATUS: string = '演示样片';
const DEMO_MESSAGE_PREFIX: string = '这是固定演示样片：';
const MAX_TASKS: number = 50;

function pad2(value: number): string {
  return value < 10 ? '0' + value : String(value);
}

// 快照兼容旧版的本地时间文本，同时把新 ISO 时间按设备本地时区展示。
// 非法历史值不抛异常，原样返回，避免「我的」页因一条旧记录无法打开。
export function formatTryOnDate(value: string): string {
  if (/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(value)) { return value; }
  const parsed: Date = new Date(value);
  if (!Number.isFinite(parsed.getTime())) { return value; }
  return parsed.getFullYear() + '-' + pad2(parsed.getMonth() + 1) + '-' + pad2(parsed.getDate()) + ' ' +
    pad2(parsed.getHours()) + ':' + pad2(parsed.getMinutes());
}

export function findDemoScene(id: string): TryOnDemoScene | undefined {
  return DEMO_SCENES.find((scene: TryOnDemoScene) => scene.id === id);
}

function requireDemoScene(sceneId: string): TryOnDemoScene {
  const scene: TryOnDemoScene | undefined = findDemoScene(sceneId);
  if (scene === undefined) { throw new Error('未知试穿样片场景'); }
  return scene;
}

// 创建时间使用 ISO 字符串，既能稳定排序，也不会因为设备区域设置改变持久化内容。
function createdAtOf(now: Date): string {
  if (!Number.isFinite(now.getTime())) { throw new Error('试穿样片时间无效'); }
  return now.toISOString();
}

export function createDemoTask(sceneId: string, now: Date = new Date()): TryOnTask {
  const scene: TryOnDemoScene = requireDemoScene(sceneId);
  return {
    id: DEMO_TASK_PREFIX + scene.id,
    demoSceneId: scene.id,
    outfitId: '',
    garmentIds: [],
    pose: scene.pose,
    createdAt: createdAtOf(now),
    status: DEMO_STATUS,
    resultUris: [],
    message: DEMO_MESSAGE_PREFIX + scene.name + '，图片仅用于展示，不代表真实生成结果'
  };
}

// 保存入口只接收合法场景 ID，不接收外部构造的任务，避免任意输入套用样片资源。
// 相同场景按 demoSceneId 幂等；容量已满时已有场景仍可返回，新增场景明确拒绝。
export function saveDemoTask(tasks: TryOnTask[], sceneId: string): TryOnTask[] {
  requireDemoScene(sceneId);
  const existing: TryOnTask | undefined = tasks.find((task: TryOnTask) =>
    task.demoSceneId === sceneId);
  if (existing !== undefined) { return tasks.slice(); }
  if (tasks.length >= MAX_TASKS) { throw new Error('试穿记录已满，请先删除一条记录'); }
  return [createDemoTask(sceneId)].concat(tasks);
}
